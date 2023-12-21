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

    
    inline get_d(pool: PoolInfo) -> u128 {
        let S: u128 = pool.reserve1 + pool.reserve2 + pool.reserve3;

        if (S == 0u128) {
            return 0u128;
        }

        let D_prev: u128 = 0u128;
        let D: u128 = S;
        let Ann: u128 = pool.ampl_coef * 3u128;

        for i: u8 in 0u8..255u8 {
            let D_P: u128 = D;
            D_P = D_P * D / (pool.reserve1 * 3u128);
            D_P = D_P * D / (pool.reserve2 * 3u128);
            D_P = D_P * D / (pool.reserve3 * 3u128);

            D_prev = D;
            D = (Ann * S + D_P * 3u128) * D / ((Ann - 1u128) * D + 4u128 * D_P);
        

            if (D > D_prev){
                if (D - D_prev <= 1u128) {
                    return D;
                }
            }    
            if (D <= D_prev){
                if (D_prev - D <= 1u128) {
                    return D;
                }
            }
        }

        return D;
    }

    inline get_y (pool: PoolInfo, id: u64, x: u128) -> u128 {
        assert(pool.token1_id != pool.token2_id && pool.token1_id != 0u64 && pool.token2_id != 0u64);
        
        let D: u128 = get_d(pool);
        let c: u128 = D;
        let Ann: u128 = pool.ampl_coef;
        let S: u128 = 0u128;

        if (pool.token1_id == id) {
            S = x + pool.reserve2 + pool.reserve3;
            c = c * D / (x * 3u128);
            c = c * D / (pool.reserve2 * 3u128);
            c = c * D / (pool.reserve3 * 3u128);
        }

        if (pool.token2_id == id) {
            S = x + pool.reserve1 + pool.reserve3;
            c = c * D / (x * 3u128);
            c = c * D / (pool.reserve1 * 3u128);
            c = c * D / (pool.reserve3 * 3u128);
        }

        if (pool.token3_id == id) {
            S = x + pool.reserve1 + pool.reserve2;
            c = c * D / (x * 3u128);
            c = c * D / (pool.reserve1 * 3u128);
            c = c * D / (pool.reserve2 * 3u128);
        }

        c = c * D / (Ann * 3u128);

        let b: u128 = S + D / Ann;
        let y_prev: u128 = 0u128;
        let y: u128 = D;

        for i: u8 in 0u8..255u8 {
            y_prev = y;
            y = (y*y + c) / (2u128 * y + b - D);
        
            if (y > y_prev) {
                if (y - y_prev <= 1u128) {
                    return y;
                }
            }
            if (y <= y_prev) {
                if (y_prev - y <= 1u128) {
                    return y;
                }
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
        // let actual_token2: Token = (actual_token1.id < token1.token_id && token1.token_id < actual_token3.id) ? (token2.token_id > token3.token_id ? token3 : token2) : token1;
        
        // let actual_amount1: u128 = token1.token_id > token2.token_id ? initial_amount2 : initial_amount1;
        // let actual_amount2: u128 = token1.token_id < token2.token_id ? initial_amount2 : initial_amount1;
        // let actual_amount3: u128 = token1.token_id < token2.token_id ? initial_amount2 : initial_amount1;
        
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

}
