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

}
