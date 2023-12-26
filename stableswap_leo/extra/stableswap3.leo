// The 'stableswap3' program.

program stableswap3.aleo {

    // ██████████████████████████████████████████████████████████████████████
    //                                 Tokens
    // ██████████████████████████████████████████████████████████████████████

    record Token {
        owner: address,
        amount: u128,
        token_id: u64,
    }

    struct TokenInfo {
        token_id: u64,        
        max_supply: u128,
        decimals: u8,
    }

    mapping registered_tokens: u64 => TokenInfo;

    transition create_token(token_id: u64, decimals: u8, max_supply: u128) {
        let new_token: TokenInfo = TokenInfo{
            token_id,
            decimals,
            max_supply,
        };
        return then finalize(new_token);
    }

    finalize create_token(new_token: TokenInfo) {
        assert(!Mapping::contains(registered_tokens, new_token.token_id));
        Mapping::set(registered_tokens, new_token.token_id, new_token);    
    }

    transition mint_private(
        receiver: address, 
        token_id: u64, 
        amount: u128,
    ) -> Token {
        assert(amount <= 1000u128 * (10u128 ** 6u8));
        return Token {
            owner: receiver,
            amount: amount,
            token_id,
        } then finalize(token_id);        
    }

    finalize mint_private(token_id: u64) {
        let token_info: TokenInfo = Mapping::get(registered_tokens, token_id);
    }

    /// ██████████████████████████████████████████████████████████████████████
    ///                             Private AMM Swaps 
    /// ██████████████████████████████████████████████████████████████████████
    
    ///  Pools

    struct PoolKey {
        token1: u64,
        token2: u64,
        token3: u64,
    }

    record PoolAdmin {
        owner: address,
        pool_key: field
    }


    struct PoolInfo {
        id: field, // hash(token1.id, token2.id, token3.id)
        token1_id: u64,
        token2_id: u64,
        token3_id: u64,
        reserve1: u128,
        reserve2: u128,
        reserve3: u128,
        lp_total_supply: u128,
        ampl_coef: u128,
        swap_fee: u128, // 10000 based, 1 = 0.01% = 0.0001
    }

    struct DepositKey {
        holder: address,
        pool_key: field,
        deposit_id: field,
    }

    record LpTokenReceipt {
        owner: address,
        token1_id: u64,
        token2_id: u64,
        token3_id: u64,
        deposit_id: field,
    }

    ///  Extra amount
    struct ExtraAmount {
        token_id: u64,
        token_amount: u128,
    }

    record ExtraAmountVoucher {
        owner: address,
        token_id: u64,
        voucher: field,
    }

    mapping amm_pools: field => PoolInfo; // PoolInfo by hash(token1.id, token2.id, token3.id)
    mapping amm_deposits: field => u128; // lp deposit amount by hash(id, pool_key)

    inline min_u128(a: u128, b: u128) -> u128 {
        return a < b ? a : b;
    }

    inline max_u128(a: u128, b: u128) -> u128 {
        return a > b ? a : b;
    }

    inline min_u64(a: u64, b: u64) -> u64 {
        return a < b ? a : b;
    }

    inline max_u64(a: u64, b: u64) -> u64 {
        return a > b ? a : b;
    }


    inline get_pool_key(token1: u64, token2: u64, token3: u64) -> field {
        let actual_token1: u64 = min_u64(min_u64(token1, token2), token3);
        let actual_token3: u64 = max_u64(max_u64(token1, token2), token3);
        let actual_token2: u64 = token1 + token2 + token3 - actual_token1 - actual_token3;
        
        return BHP256::hash_to_field(PoolKey {token1: actual_token1, token2: actual_token2, token3: actual_token3});
    }

    
    inline get_d(reserve1: u128, reserve2: u128, reserve3: u128, ampl_coef: u128) -> u128 {
        let S: u128 = reserve1 + reserve2 + reserve3;

        if (S == 0u128) {
            return 0u128;
        }

        let D_prev: u128 = 0u128;
        let D: u128 = S;
        let Ann: u128 = ampl_coef * 3u128;

        for i: u8 in 0u8..255u8 {
            let D_P: u128 = D;
            D_P = D_P * D / (reserve1 * 3u128);
            D_P = D_P * D / (reserve2 * 3u128);
            D_P = D_P * D / (reserve3 * 3u128);

            D_prev = D;
            D = (Ann * S + D_P * 3u128) * D / ((Ann - 1u128) * D + 4u128 * D_P);
        
            let tmp_res: bool = (max_u128(D, D_prev) - min_u128(D, D_prev) <= 1u128) ? true : false;

            if (tmp_res) {
                return D;
            }
        }

        return D;
    }

    inline get_y (reserve1: u128, reserve2: u128, reserve3: u128, ampl_coef: u128, id_out: u64, id_in: u64, x: u128) -> u128 {
        // assert(token1_id != token2_id && token1_id != token3_id && token3_id != token2_id && token1_id != 0u64 && token2_id != 0u64);
        
        let D: u128 = get_d(reserve1, reserve2, reserve3, ampl_coef);
        let c: u128 = D;
        let Ann: u128 = ampl_coef;
        let S: u128 = reserve1 + reserve2 + reserve3;

        let coins: [u128; 3] = [reserve1, reserve2, reserve3];

        c = c * D / (reserve1 * 3u128);
        c = c * D / (reserve2 * 3u128);
        c = c * D / (reserve3 * 3u128);

        for iter: u64 in 1u64..4u64 {
            if id_in == iter {
                S -= coins[iter];
                S += x;
                c *= coins[iter];
                c /= x;
            }
            if id_out == iter {
                S -= coins[iter];
                c *= coins[iter] * 3u128;
                c /= D;
            }
        }

        c = c * D / (Ann * 3u128);

        let b: u128 = S + D / Ann;
        let y_prev: u128 = 0u128;
        let y: u128 = D;

        for i: u8 in 0u8..255u8 {
            y_prev = y;
            y = (y*y + c) / (2u128 * y + b - D);
        
            let tmp_res: bool = (max_u128(y, y_prev) - min_u128(y, y_prev) <= 1u128) ? true : false;

            if (tmp_res) {
                return y;
            }
        }
        return y;
    }
    

    transition transfer_pool_ownership(poolAdmin: PoolAdmin, to: address) -> (PoolAdmin) {
        assert(poolAdmin.owner == self.caller);
        return PoolAdmin {
            owner: to,
            pool_key: poolAdmin.pool_key
        };
    }


    transition create_pool(owner: address, token1: Token, initial_amount1: u128, token2: Token, initial_amount2: u128, token3: Token, initial_amount3: u128, ampl_coef: u128, swap_fee: u128) -> (PoolAdmin, Token, Token, Token) {
        assert(initial_amount1 > 0u128 && initial_amount2 > 0u128 && initial_amount3 > 0u128);
        assert(swap_fee <= 10000u128); // 10000 based, 1 = 0.01% = 0.0001
        assert(token1.token_id != token2.token_id && token1.token_id != token3.token_id && token2.token_id != token3.token_id);
        assert(token1.amount >= initial_amount1 && token2.amount >= initial_amount2);

        let change1: Token = Token {
            owner: owner,
            token_id: token1.token_id,
            amount: token1.amount - initial_amount1
        };

        let change2: Token = Token {
            owner: owner,
            token_id: token2.token_id,
            amount: token2.amount - initial_amount2
        };

        let change3: Token = Token {
            owner: owner,
            token_id: token3.token_id,
            amount: token3.amount - initial_amount3
        };

        if (token1.token_id < token2.token_id) {

        }


        let actual_token1: Token = token1.token_id > token2.token_id ? (token2.token_id > token3.token_id ? token3 : token2) : (token1.token_id > token3.token_id ? token3 : token1);
        let actual_token3: Token = token1.token_id > token2.token_id ? (token1.token_id > token3.token_id ? token1 : token3) : (token2.token_id > token3.token_id ? token2 : token3);
        let actual_token2: Token = (token1.token_id > token2.token_id && token2.token_id > token3.token_id) ? token2 : ((token2.token_id > token1.token_id && token1.token_id > token3.token_id) ? token1 : token3);
        
        let actual_amount1: u128 = token1.token_id > token2.token_id ? (token2.token_id > token3.token_id ? initial_amount3 : initial_amount2) : (token1.token_id > token3.token_id ? initial_amount3 : initial_amount1);
        let actual_amount2: u128 = (token1.token_id > token2.token_id && token2.token_id > token3.token_id) ? initial_amount2 : ((token2.token_id > token1.token_id && token1.token_id > token3.token_id) ? initial_amount1 : initial_amount3);
        let actual_amount3: u128 = token1.token_id > token2.token_id ? (token1.token_id > token3.token_id ? initial_amount1 : initial_amount3) : (token2.token_id > token3.token_id ? initial_amount2 : initial_amount3);
        
        let pool_key: field = get_pool_key(actual_token1.token_id, actual_token2.token_id, actual_token3.token_id);
        let pool_admin: PoolAdmin = PoolAdmin {
            owner: owner,
            pool_key: pool_key
        };

        return (pool_admin, change1, change2, change3) then finalize(pool_key, actual_token1.token_id, actual_amount1, actual_token2.token_id, actual_amount2, actual_token3.token_id, actual_amount3 , ampl_coef, swap_fee);
    }

    finalize create_pool(pool_key: field, token1_id: u64, token1_amount: u128, token2_id: u64, token2_amount: u128, token3_id: u64, token3_amount: u128, ampl_coef: u128, swap_fee: u128) {
        assert (!Mapping::contains(amm_pools, pool_key)); // the pool already exists

        let pool: PoolInfo = PoolInfo {
            id: pool_key, // hash(token1.id, token2.id)
            token1_id: token1_id,
            token2_id: token2_id,
            token3_id: token3_id,
            reserve1: token1_amount,
            reserve2: token2_amount,
            reserve3: token3_amount,
            lp_total_supply: token1_amount * token2_amount,
            ampl_coef: ampl_coef,
            swap_fee: swap_fee, // 10000 based, 1 = 0.01% = 0.0001
        };

        Mapping::set(amm_pools, pool_key, pool);
    }

    transition add_liquidity(owner: address, token1: Token, token1_amount: u128, token2: Token, token2_amount: u128, token3: Token, token3_amount: u128, deposit_id: field, reserve1: u128, reserve2: u128, reserve3: u128, ampl_coef: u128) -> (Token, Token, Token, LpTokenReceipt) {
        let token1_change_amount: u128 = token1.amount - token1_amount;
        let token2_change_amount: u128 = token2.amount - token2_amount;
        let token3_change_amount: u128 = token3.amount - token3_amount;

        let D0: u128 = get_d(reserve1, reserve2, reserve3, ampl_coef);

        let D1: u128 = get_d(reserve1 + token1_amount, reserve2 + token2_amount, reserve3 + token3_amount, ampl_coef);

        assert(D1 > D0);

        let D2: u128 = D1;

        // let ideal_reserve1: u128 = D1 * pool.reserve1 / D0;
        // let ideal_reserve2: u128 = D1 * pool.reserve2 / D0;
        
        let token1_change_record: Token = Token {
            owner: token1.owner,
            amount: token1_change_amount,
            token_id: token1.token_id
        };

        let token2_change_record: Token = Token {
            owner: token2.owner,
            amount: token2_change_amount,
            token_id: token2.token_id
        };

        let token3_change_record: Token = Token {
            owner: token3.owner,
            amount: token3_change_amount,
            token_id: token3.token_id
        };

        let lp_token_receipt: LpTokenReceipt = LpTokenReceipt {
            owner: owner,
            token1_id: token1.token_id,
            token2_id: token2.token_id,
            token3_id: token3.token_id,
            deposit_id: deposit_id
        };

        return (token1_change_record, token2_change_record, token3_change_record, lp_token_receipt) then finalize(deposit_id, token1.token_id, token1_amount, token2.token_id, token2_amount, token3.token_id, token3_amount);
    }

    finalize add_liquidity(deposit_id: field, token1_id: u64, token1_amount: u128, token2_id: u64, token2_amount: u128, token3_id: u64, token3_amount: u128) {
        let pool_key: field = get_pool_key(token1_id, token2_id, token3_id);
        
        let pool: PoolInfo = Mapping::get(amm_pools, pool_key);

        let new_lp1: u128 = (token1_amount * pool.lp_total_supply) / pool.reserve1;
        let new_lp2: u128 = (token2_amount * pool.lp_total_supply) / pool.reserve2;
        let new_lp3: u128 = (token3_amount * pool.lp_total_supply) / pool.reserve3;

        let lp: u128 = min_u128(new_lp1, min_u128(new_lp2, new_lp3));

        let updated_pool: PoolInfo = PoolInfo {
            id: pool.id,
            token1_id: pool.token1_id,
            token2_id: pool.token2_id,
            token3_id: pool.token3_id,
            swap_fee: pool.swap_fee,
            reserve1: pool.reserve1 + token1_amount,
            reserve2: pool.reserve2 + token2_amount,
            reserve3: pool.reserve3 + token3_amount,
            ampl_coef: pool.ampl_coef,
            lp_total_supply: pool.lp_total_supply + lp,
        };
        Mapping::set(amm_pools, pool_key, updated_pool);
        
        assert(!Mapping::contains(amm_deposits, deposit_id));
        Mapping::set(amm_deposits, deposit_id, lp);
    }

    transition remove_liquidity(receiver: address, lp_receipt: LpTokenReceipt, token1_amount: u128, token2_amount: u128, token3_amount: u128) -> (Token, Token, Token) {
        let token1: Token = Token {
            owner: receiver,
            amount: token1_amount,
            token_id: lp_receipt.token1_id
        };

        let token2: Token = Token {
            owner: receiver,
            amount: token2_amount,
            token_id: lp_receipt.token2_id
        };

        let token3: Token = Token {
            owner: receiver,
            amount: token3_amount,
            token_id: lp_receipt.token3_id
        };

        return (token1, token2, token3) then finalize(lp_receipt.deposit_id, 
                lp_receipt.token1_id, lp_receipt.token2_id, lp_receipt.token3_id, token1_amount, token2_amount, token3_amount);
    }

    finalize remove_liquidity(deposit_id: field, token1_id: u64, token2_id: u64, token3_id: u64, token1_amount: u128, token2_amount: u128, token3_amount: u128) {
        let pool_key: field = get_pool_key(token1_id, token2_id, token3_id);
        let pool: PoolInfo = Mapping::get(amm_pools, pool_key);

        let total: u128 = pool.lp_total_supply;

        let deposit_amount_lp: u128 = Mapping::get(amm_deposits, deposit_id);
        
        let deposit_amount_1: u128 = deposit_amount_lp * pool.reserve1 / total;
        let deposit_amount_2: u128 = deposit_amount_lp * pool.reserve2 / total;
        let deposit_amount_3: u128 = deposit_amount_lp * pool.reserve3 / total;

        // automatic underflow check ensures a user didn't request more than they have on this deposit
        let change1: u128 = deposit_amount_1 - token1_amount;
        let change2: u128 = deposit_amount_2 - token2_amount;
        let change3: u128 = deposit_amount_3 - token3_amount;

        let updated_pool: PoolInfo = PoolInfo {
            id: pool.id,
            token1_id: pool.token1_id,
            token2_id: pool.token2_id,
            token3_id: pool.token3_id,
            swap_fee: pool.swap_fee,
            reserve1: pool.reserve1 - deposit_amount_1,
            reserve2: pool.reserve2 - deposit_amount_2,
            reserve3: pool.reserve3 - deposit_amount_3,
            ampl_coef: pool.ampl_coef,
            lp_total_supply: pool.lp_total_supply - deposit_amount_lp
        };
        Mapping::set(amm_pools, pool_key, updated_pool);
        Mapping::remove(amm_deposits, deposit_id);
    }

    transition exchange (receiver: address, token_in: Token, token_in_id: u64, token_out_id: u64, amount_in: u128, min_amount_out: u128, reserve1: u128, reserve2: u128, reserve3: u128,
    token1_id: u64, token2_id: u64, token3_id: u64, ampl_coef: u128, swap_fee: u128) -> (Token, Token) {
        assert(amount_in > 0u128);

        let change_amount: u128 = token_in.amount - amount_in;

        let reserve_in: u128 = token1_id == token_in_id ? reserve1 : reserve2;
        let reserve_out: u128 = token2_id == token_in_id ? reserve1 : reserve2; // TODO: finish exchange
        let fee: u128 = swap_fee;

        let amount_in_with_fee: u128 = amount_in; // TODO: add fee 
        let x: u128 = amount_in_with_fee + reserve_in;
        let y: u128 = get_y(reserve1, reserve2, reserve3, ampl_coef, token_out_id, token_in_id, x);
        
        let dy: u128 = reserve_out - y - 1u128;

        assert(dy >= min_amount_out);

        let token_in_record: Token = Token {
            owner: token_in.owner,
            amount: change_amount,
            token_id: token_in.token_id
        };

        let token_out_record: Token = Token {
            owner: receiver,
            amount: dy,
            token_id: token_out_id
        };

        return (token_in_record, token_out_record) then finalize (reserve_in, reserve_out, token_in_id, amount_in_with_fee, token_out_id, dy);
    }

    finalize exchange(reserve_in_user: u128, reserve_out_user: u128, token_in_id: u64, amount_in: u128, token_out_id: u64, amount_out: u128) {
        let pool_key: field = get_pool_key(token_in_id, token_out_id);
        let pool: PoolInfo = Mapping::get(amm_pools, pool_key);

        let reserve_in: u128 = pool.token1_id == token_in_id ? pool.reserve1 : pool.reserve2;
        let reserve_out: u128 = pool.token2_id == token_in_id ? pool.reserve1 : pool.reserve2;

        // let a: u128 = 1u128;
        // let b: u128 = 2u128;
        // let c: u128 = a - b;
        // assert_eq(reserve_in, 1u128); 

        assert(max_u128(reserve_in_user, reserve_in) - min_u128(reserve_in_user, reserve_in) < 10u128);
        assert(max_u128(reserve_out_user, reserve_out) - min_u128(reserve_out_user, reserve_out) < 10u128);

        reserve_in += amount_in;
        reserve_out -= amount_out;

        let updated_pool: PoolInfo = PoolInfo {
            id: pool.id,
            token1_id: pool.token1_id,
            token2_id: pool.token2_id,
            swap_fee: pool.swap_fee,
            reserve1: pool.token1_id == token_in_id ? reserve_in : reserve_out,
            reserve2: pool.token2_id == token_in_id ? reserve_in : reserve_out,
            ampl_coef: pool.ampl_coef,
            lp_total_supply: pool.lp_total_supply
        };

        Mapping::set(amm_pools, pool_key, updated_pool);   
    }

}
