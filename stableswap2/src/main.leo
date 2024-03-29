import arcanetoken.aleo;
import credits.aleo;

program stableswap2.aleo {

    const SELF_ADDRESS: address = aleo1hy8w46tflux7zwpeaw8ny7tq6wkzqux40z75a9ah3q9tqa4t758qltkqu7;

    const MAX_U64: u64 = 18446744073709551615u64;

    /// ██████████████████████████████████████████████████████████████████████
    ///                             Private AMM Swaps 
    /// ██████████████████████████████████████████████████████████████████████

    
    ///  Pools
    struct PoolKey {
        token1: u64,
        token2: u64,
    }

    record PoolAdmin {
        owner: address,
        pool_key: field
    }

    struct PoolInfo {
        id: field, // hash(token1.id, token2.id)
        token1_id: u64,
        token2_id: u64,
        reserve1: u128,
        reserve2: u128,
        ampl_coef: u128,
        lp_total_supply: u128,
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
        deposit_id: field
    }


    mapping amm_pools: field => PoolInfo; // PoolInfo by hash(token1.id, token2.id)
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

    inline get_pool_key(token1: u64, token2: u64) -> field {
        let actual_token1: u64 = token1 > token2 ? token2 : token1;
        let actual_token2: u64 = token1 <= token2 ? token2 : token1;

        return BHP256::hash_to_field(PoolKey {token1: actual_token1, token2: actual_token2});
    }

    inline get_d(reserve1: u128, 
                reserve2: u128, 
                ampl_coef: u128) -> u128 {

        let S: u128 = reserve1 + reserve2;

        if (S == 0u128) {   
            return 0u128;
        }

        let D_prev: u128 = 0u128;
        let D: u128 = S;
        let Ann: u128 = ampl_coef * 2u128;
        

        for i: u8 in 0u8..8u8 {
            let D_P: u128 = D;
            D_P = D_P * D / (reserve1 * 2u128);
            D_P = D_P * D / (reserve2 * 2u128);

            D_prev = D;
            D = (Ann * S + D_P * 2u128) * D / ((Ann - 1u128) * D + 3u128 * D_P);
            
            let tmp_res: bool = (max_u128(D, D_prev) - min_u128(D, D_prev) <= 1u128) ? true : false;

            if (tmp_res) {
                return D;
            }
        }

        return D;
    }    
    
    inline get_y(reserve1: u128, 
                reserve2: u128, 
                ampl_coef: u128, 
                token1_id: u64, 
                token2_id: u64, 
                id: u64, 
                x: u128) -> u128 {

        assert(token1_id != token2_id && token1_id != 0u64 && token2_id != 0u64);
        
        
        let D: u128 = get_d(reserve1, reserve2, ampl_coef);
        
        let c: u128 = D;
        let Ann: u128 = ampl_coef * 2u128;
        let S: u128 = 0u128;

        S = x;
        c = c * D / (x * 2u128);
        

        c = c * D / (Ann * 2u128);

        let b: u128 = S + D / Ann;
        let y_prev: u128 = 0u128;
        let y: u128 = D;

        for i: u8 in 0u8..8u8 {
            y_prev = y;
            y = (y * y + c) / (2u128 * y + b - D);

            let tmp_res: bool = (max_u128(y, y_prev) - min_u128(y, y_prev) <= 1u128) ? true : false;

            if (tmp_res) {
                return y;
            }
        }
        return y;
    }

    transition create_pool(owner: address, 
                          token1: arcanetoken.aleo/ArcaneToken,
                          initial_amount1: u128, 
                          token2: arcanetoken.aleo/ArcaneToken, 
                          initial_amount2: u128, 
                          ampl_coef: u128, 
                          swap_fee: u128) -> (PoolAdmin, arcanetoken.aleo/ArcaneToken, arcanetoken.aleo/ArcaneToken) {

        assert(initial_amount1 > 0u128 && initial_amount2 > 0u128);
        assert(swap_fee <= 10000u128); // 10000 based, 1 = 0.01% = 0.0001
        assert(token1.token_id > token2.token_id);
        assert(token1.amount >= initial_amount1 && token2.amount >= initial_amount2);

        let change1: arcanetoken.aleo/ArcaneToken = arcanetoken.aleo/transfer_private_to_public_arc(token1, SELF_ADDRESS, initial_amount1);
        let change2: arcanetoken.aleo/ArcaneToken = arcanetoken.aleo/transfer_private_to_public_arc(token2, SELF_ADDRESS, initial_amount2);

        let pool_key: field = get_pool_key(token1.token_id, token2.token_id);
        let pool_admin: PoolAdmin = PoolAdmin {
            owner: owner,
            pool_key: pool_key
        };

        return (pool_admin, change1, change2) then finalize(pool_key, token1.token_id, initial_amount1, token2.token_id, initial_amount2, ampl_coef, swap_fee);
    }

    finalize create_pool(pool_key: field, 
                        token1_id: u64, 
                        token1_amount: u128, 
                        token2_id: u64, 
                        token2_amount: u128, 
                        ampl_coef: u128, 
                        swap_fee: u128) {

        assert (!Mapping::contains(amm_pools, pool_key)); // the pool already exists

        let pool: PoolInfo = PoolInfo {
            id: pool_key, // hash(token1.id, token2.id)
            token1_id: token1_id,
            token2_id: token2_id,
            reserve1: token1_amount,
            reserve2: token2_amount,
            lp_total_supply: token1_amount * token2_amount,
            ampl_coef: ampl_coef,
            swap_fee: swap_fee, // 10000 based, 1 = 0.01% = 0.0001
        };

        Mapping::set(amm_pools, pool_key, pool);
        
    }

    transition transfer_pool_ownership(poolAdmin: PoolAdmin, to: address) -> (PoolAdmin) {
        assert(poolAdmin.owner == self.caller);
        return PoolAdmin {
            owner: to,
            pool_key: poolAdmin.pool_key
        };
    }

    transition add_liquidity(owner: address, 
                            token1: arcanetoken.aleo/ArcaneToken, 
                            token1_amount: u128, 
                            token2: arcanetoken.aleo/ArcaneToken, 
                            token2_amount: u128, 
                            deposit_id: field, 
                            reserve1: u128, 
                            reserve2: u128, 
                            ampl_coef: u128) -> (arcanetoken.aleo/ArcaneToken, arcanetoken.aleo/ArcaneToken, LpTokenReceipt) {

        let token1_change_amount: u128 = token1.amount - token1_amount;
        let token2_change_amount: u128 = token2.amount - token2_amount;

        let D0: u128 = get_d(reserve1, reserve2, ampl_coef);

        let D1: u128 = get_d(reserve1 + token1_amount, reserve2 + token2_amount, ampl_coef);

        assert(D1 > D0);

        let D2: u128 = D1;

        // let ideal_reserve1: u128 = D1 * pool.reserve1 / D0; TODO: ideal reserve
        // let ideal_reserve2: u128 = D1 * pool.reserve2 / D0;
        
        let change1: arcanetoken.aleo/ArcaneToken = arcanetoken.aleo/transfer_private_to_public_arc(token1, SELF_ADDRESS, token1_change_amount);
        let change2: arcanetoken.aleo/ArcaneToken = arcanetoken.aleo/transfer_private_to_public_arc(token2, SELF_ADDRESS, token2_change_amount);

        let lp_token_receipt: LpTokenReceipt = LpTokenReceipt {
            owner: owner,
            token1_id: token1.token_id,
            token2_id: token2.token_id,
            deposit_id: deposit_id
        };

        return (change1, change2, lp_token_receipt) then finalize(deposit_id, token1.token_id, token1_amount, token2.token_id, token2_amount);
    }

    finalize add_liquidity(deposit_id: field, token1_id: u64, token1_amount: u128, token2_id: u64, token2_amount: u128) {
        let pool_key: field = get_pool_key(token1_id, token2_id);
        
        let pool: PoolInfo = Mapping::get(amm_pools, pool_key);

        let new_lp1: u128 = (token1_amount * pool.lp_total_supply) / pool.reserve1;
        let new_lp2: u128 = (token2_amount * pool.lp_total_supply) / pool.reserve2;

        let lp: u128 = min_u128(new_lp1, new_lp2);

        let updated_pool: PoolInfo = PoolInfo {
            id: pool.id,
            token1_id: pool.token1_id,
            token2_id: pool.token2_id,
            swap_fee: pool.swap_fee,
            reserve1: pool.reserve1 + token1_amount,
            reserve2: pool.reserve2 + token2_amount,
            ampl_coef: pool.ampl_coef,
            lp_total_supply: pool.lp_total_supply + lp,
        };
        Mapping::set(amm_pools, pool_key, updated_pool);
        
        assert(!Mapping::contains(amm_deposits, deposit_id));
        Mapping::set(amm_deposits, deposit_id, lp);
    }
    
    transition remove_liquidity(receiver: address, 
                                lp_receipt: LpTokenReceipt, 
                                token1_amount: u128, 
                                token2_amount: u128) -> (arcanetoken.aleo/ArcaneToken, arcanetoken.aleo/ArcaneToken) {
        
        let change1: arcanetoken.aleo/ArcaneToken = arcanetoken.aleo/transfer_public_to_private_arc(lp_receipt.token1_id, receiver, token1_amount);
        let change2: arcanetoken.aleo/ArcaneToken = arcanetoken.aleo/transfer_public_to_private_arc(lp_receipt.token2_id, receiver, token2_amount);

        
        return (change1, change2) then finalize(lp_receipt.deposit_id, 
                lp_receipt.token1_id, lp_receipt.token2_id, token1_amount, token2_amount);
    }

    finalize remove_liquidity(deposit_id: field, token1_id: u64, token2_id: u64, token1_amount: u128, token2_amount: u128) {
        let pool_key: field = get_pool_key(token1_id, token2_id);
        let pool: PoolInfo = Mapping::get(amm_pools, pool_key);

        let total: u128 = pool.lp_total_supply;

        let deposit_amount_lp: u128 = Mapping::get(amm_deposits, deposit_id);
        
        let deposit_amount_1: u128 = deposit_amount_lp * pool.reserve1 / total;
        let deposit_amount_2: u128 = deposit_amount_lp * pool.reserve2 / total;

        // automatic underflow check ensures a user didn't request more than they have on this deposit
        let change1: u128 = deposit_amount_1 - token1_amount;
        let change2: u128 = deposit_amount_2 - token2_amount;

        let updated_pool: PoolInfo = PoolInfo {
            id: pool.id,
            token1_id: pool.token1_id,
            token2_id: pool.token2_id,
            swap_fee: pool.swap_fee,
            reserve1: pool.reserve1 - deposit_amount_1,
            reserve2: pool.reserve2 - deposit_amount_2,
            ampl_coef: pool.ampl_coef,
            lp_total_supply: pool.lp_total_supply - deposit_amount_lp
        };
        Mapping::set(amm_pools, pool_key, updated_pool);
        Mapping::remove(amm_deposits, deposit_id);
    }

    transition exchange (receiver: address, 
                        token_in: arcanetoken.aleo/ArcaneToken, 
                        token_in_id: u64, 
                        token_out_id: u64, 
                        amount_in: u128, 
                        min_amount_out: u128, 
                        reserve1: u128, 
                        reserve2: u128, 
                        token1_id: u64, 
                        token2_id: u64, 
                        ampl_coef: u128, 
                        swap_fee: u128) -> (arcanetoken.aleo/ArcaneToken, arcanetoken.aleo/ArcaneToken) {

        assert(amount_in > 0u128);

        let change_amount: u128 = token_in.amount - amount_in;

        let reserve_in: u128 = token1_id == token_in_id ? reserve1 : reserve2;
        let reserve_out: u128 = token2_id == token_in_id ? reserve1 : reserve2;

        let fee: u128 = swap_fee;

        let amount_in_with_fee: u128 = amount_in; // TODO: add fee 
        let x: u128 = amount_in_with_fee + reserve_in;
        let y: u128 = get_y(reserve1, reserve2, ampl_coef, token1_id, token2_id, token_in_id, x);
        
        let dy: u128 = reserve_out - y - 1u128;

        assert(dy >= min_amount_out);

        let token_in_record: ArcaneToken = arcanetoken.aleo/transfer_private_to_public_arc(token_in, SELF_ADDRESS, amount_in_with_fee);
        let token_out_record: ArcaneToken = arcanetoken.aleo/transfer_public_to_private_arc(token_out_id, receiver, dy);


        return (token_in_record, token_out_record) then finalize (reserve_in, reserve_out, token_in_id, amount_in_with_fee, token_out_id, dy);
    }

    finalize exchange(reserve_in_user: u128, reserve_out_user: u128, token_in_id: u64, amount_in: u128, token_out_id: u64, amount_out: u128) {
        let pool_key: field = get_pool_key(token_in_id, token_out_id);
        let pool: PoolInfo = Mapping::get(amm_pools, pool_key);

        let reserve_in: u128 = pool.token1_id == token_in_id ? pool.reserve1 : pool.reserve2;
        let reserve_out: u128 = pool.token2_id == token_in_id ? pool.reserve1 : pool.reserve2;

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

    /// ██████████████████████████████████████████████████████████████████████
    ///                             CREDITS
    /// ██████████████████████████████████████████████████████████████████████

    transition create_pool_pric(owner: address, 
                          token1: credits.aleo/credits,
                          initial_amount1: u64, 
                          token2: arcanetoken.aleo/ArcaneToken, 
                          initial_amount2: u128, 
                          ampl_coef: u128, 
                          swap_fee: u128) -> (PoolAdmin, credits.aleo/credits, arcanetoken.aleo/ArcaneToken) {

        assert(initial_amount1 > 0u64 && initial_amount2 > 0u128);
        assert(swap_fee <= 10000u128 && ampl_coef >= 0u128); // 10000 based, 1 = 0.01% = 0.0001
        assert(token1.microcredits >= initial_amount1 && token2.amount >= initial_amount2);

        let change1: credits = credits.aleo/transfer_private_to_public(token1, SELF_ADDRESS, initial_amount1);
        let change2: ArcaneToken = arcanetoken.aleo/transfer_private_to_public_arc(token2, SELF_ADDRESS, initial_amount2);

        let pool_key: field = get_pool_key(0u64, token2.token_id);
        let pool_admin: PoolAdmin = PoolAdmin {
            owner: owner,
            pool_key: pool_key
        };

        return (pool_admin, change1, change2) then finalize(pool_key, 0u64, initial_amount1 as u128, token2.token_id, initial_amount2, ampl_coef, swap_fee);
    }


    finalize create_pool_pric(pool_key: field, 
                            token1_id: u64, 
                            token1_amount: u128,
                            token2_id: u64, 
                            token2_amount: u128, 
                            ampl_coef: u128, 
                            swap_fee: u128) {

        assert (!Mapping::contains(amm_pools, pool_key)); // the pool already exists

        let pool: PoolInfo = PoolInfo {
            id: pool_key, // hash(token1.id, token2.id)
            token1_id: token1_id,
            token2_id: token2_id,
            reserve1: token1_amount,
            reserve2: token2_amount,
            lp_total_supply: token1_amount * token2_amount,
            ampl_coef: ampl_coef,
            swap_fee: swap_fee, // 10000 based, 1 = 0.01% = 0.0001
        };

        Mapping::set(amm_pools, pool_key, pool);
    }


    transition add_amm_liquidity_pric(owner: address, 
                                      token1: credits.aleo/credits, 
                                      token1_amount: u64, 
                                      token2: arcanetoken.aleo/ArcaneToken, 
                                      token2_amount: u128, 
                                      deposit_id: field,
                                      reserve1: u128, 
                                      reserve2: u128, 
                                      ampl_coef: u128) -> (credits.aleo/credits, arcanetoken.aleo/ArcaneToken, LpTokenReceipt) {

        let D0: u128 = get_d(reserve1, reserve2, ampl_coef);

        let D1: u128 = get_d(reserve1 + token1_amount as u128, reserve2 + token2_amount, ampl_coef);

        assert(D1 > D0);

        let D2: u128 = D1;

        // let ideal_reserve1: u128 = D1 * pool.reserve1 / D0; TODO: ideal reserve
        // let ideal_reserve2: u128 = D1 * pool.reserve2 / D0;
        
        let token1_change_record: credits = credits.aleo/transfer_private_to_public(token1, SELF_ADDRESS, token1_amount);
        let token2_change_record: ArcaneToken = arcanetoken.aleo/transfer_private_to_public_arc(token2, SELF_ADDRESS, token2_amount);

        let lp_token_receipt: LpTokenReceipt = LpTokenReceipt {
            owner: owner,
            token1_id: 0u64,
            token2_id: token2.token_id,
            deposit_id: deposit_id
        };

        return (token1_change_record, token2_change_record, lp_token_receipt) then finalize(deposit_id, token1_amount as u128, token2.token_id, token2_amount);
    }

    finalize add_amm_liquidity_pric(deposit_id: field, token1_amount: u128, token2_id: u64, token2_amount: u128) {
        let token1_id: u64 = 0u64;
        let pool_key: field = get_pool_key(token1_id, token2_id);
        
        let pool: PoolInfo = Mapping::get(amm_pools, pool_key);

        let new_lp1: u128 = (token1_amount * pool.lp_total_supply) / pool.reserve1;
        let new_lp2: u128 = (token2_amount * pool.lp_total_supply) / pool.reserve2;

        let lp: u128 = min_u128(new_lp1, new_lp2);

        let updated_pool: PoolInfo = PoolInfo {
            id: pool.id,
            token1_id: pool.token1_id,
            token2_id: pool.token2_id,
            swap_fee: pool.swap_fee,
            reserve1: pool.reserve1 + token1_amount,
            reserve2: pool.reserve2 + token2_amount,
            ampl_coef: pool.ampl_coef,
            lp_total_supply: pool.lp_total_supply + lp,
        };
        Mapping::set(amm_pools, pool_key, updated_pool);
        
        assert(!Mapping::contains(amm_deposits, deposit_id));
        Mapping::set(amm_deposits, deposit_id, lp);
    }

    transition remove_amm_liquidity_pric(receiver: address, 
                                        lp_receipt: LpTokenReceipt, 
                                        token1_amount: u64, 
                                        token2_amount: u128, 
                                        /*extra_voucher1: field, 
                                        extra_voucher2: field*/) -> (credits.aleo/credits, arcanetoken.aleo/ArcaneToken/*, ExtraAmountVoucher, ExtraAmountVoucher*/) {
        // assert(extra_voucher1 != extra_voucher2);

        let token1: credits = credits.aleo/transfer_public_to_private(receiver, token1_amount);
        let token2: ArcaneToken = arcanetoken.aleo/transfer_public_to_private_arc(lp_receipt.token2_id, receiver, token2_amount);

        // let extra_amount_voucher1: ExtraAmountVoucher = ExtraAmountVoucher {
        //     owner: receiver,
        //     token_id: lp_receipt.token1_id,
        //     voucher: extra_voucher1
        // };
        // let extra_amount_voucher2: ExtraAmountVoucher = ExtraAmountVoucher {
        //     owner: receiver,
        //     token_id: lp_receipt.token2_id,
        //     voucher: extra_voucher2
        // };

        return (token1, token2, /* extra_amount_voucher1, extra_amount_voucher2 */) then finalize(lp_receipt.deposit_id, 
                lp_receipt.token1_id, lp_receipt.token2_id, token1_amount as u128, token2_amount/*, extra_voucher1, extra_voucher2 */);
    }

    finalize remove_amm_liquidity_pric(deposit_id: field, 
                                       token1_id: u64, 
                                       token2_id: u64, 
                                       token1_amount: u128, 
                                       token2_amount: u128, 
                                       /*extra_voucher1: field, 
                                       extra_voucher2: field */) {

        let pool_key: field = get_pool_key(token1_id, token2_id);
        let pool: PoolInfo = Mapping::get(amm_pools, pool_key);

        let total: u128 = pool.lp_total_supply;

        let deposit_amount_lp: u128 = Mapping::get(amm_deposits, deposit_id);
        
        let deposit_amount_1: u128 = deposit_amount_lp * pool.reserve1 / total;
        let deposit_amount_2: u128 = deposit_amount_lp * pool.reserve2 / total;

        // automatic underflow check ensures a user didn't request more than they have on this deposit
        let change1: u128 = deposit_amount_1 - token1_amount;
        let change2: u128 = deposit_amount_2 - token2_amount;

        // assert (!Mapping::contains(amm_extras, extra_voucher1)); // check if voucher1 is already in use
        // Mapping::set(amm_extras, extra_voucher1, ExtraAmount {
        //     token_id: token1_id,
        //     token_amount: change1
        // });

        // assert (!Mapping::contains(amm_extras, extra_voucher2)); // check if voucher2 is already in use
        // Mapping::set(amm_extras, extra_voucher2, ExtraAmount {
        //     token_id: token2_id,
        //     token_amount: change2
        // });

        let updated_pool: PoolInfo = PoolInfo {
            id: pool.id,
            token1_id: pool.token1_id,
            token2_id: pool.token2_id,
            swap_fee: pool.swap_fee,
            reserve1: pool.reserve1 - deposit_amount_1,
            reserve2: pool.reserve2 - deposit_amount_2,
            ampl_coef: pool.ampl_coef,
            lp_total_supply: pool.lp_total_supply - deposit_amount_lp
        };
        Mapping::set(amm_pools, pool_key, updated_pool);
        Mapping::remove(amm_deposits, deposit_id);
    }

    transition swap_amm_pric_in(receiver: address, 
                                token_in: credits.aleo/credits, 
                                amount_in: u64,
                                reserve_in: u128,
                                token_out_id: u64, 
                                min_amount_out: u128, 
                                reserve_out: u128,
                                ampl_coef: u128,
                                /* extra_voucher: field */) -> (credits.aleo/credits, arcanetoken.aleo/ArcaneToken /*, ExtraAmountVoucher */) {
        
        assert(min_amount_out > 0u128);
        assert(amount_in > 0u64);

        // let change_amount: u128 = token_in.amount - amount_in as u128;
        
        let amount_in_with_fee: u64 = amount_in; // TODO: add fee 
        let x: u128 = amount_in_with_fee as u128 + reserve_in;
        let y: u128 = get_y(reserve_in, reserve_out, ampl_coef, 0u64, token_out_id, 0u64, x);
        
        let dy: u128 = reserve_out - y - 1u128;

        assert(dy >= min_amount_out);

        let token_in_record: credits = credits.aleo/transfer_private_to_public(token_in, SELF_ADDRESS, amount_in_with_fee);
        let token_out_record: ArcaneToken = arcanetoken.aleo/transfer_public_to_private_arc(token_out_id, receiver, dy);


        // user can get change using this voucher if amount_out is less than actual amount they could receive according to AMM math
        // let extra_amount_voucher: ExtraAmountVoucher = ExtraAmountVoucher {
        //     owner: receiver,
        //     token_id: token_out_id,
        //     voucher: extra_voucher
        // };

        return (token_in_record, token_out_record,/* extra_amount_voucher */) then finalize(reserve_in, reserve_out, amount_in as u128, token_out_id, dy/*, extra_voucher*/);
    }

    finalize swap_amm_pric_in(reserve_in_user: u128, 
                              reserve_out_user: u128,
                              amount_in: u128, 
                              token_out_id: u64, 
                              amount_out: u128, 
                              /*extra_change_voucher: field*/) {
        
        let token_in_id: u64 = 0u64;
        
        let pool_key: field = get_pool_key(token_in_id, token_out_id);
        let pool: PoolInfo = Mapping::get(amm_pools, pool_key);

        let total: u128 = pool.lp_total_supply;

        let reserve_in: u128 = pool.token1_id == token_in_id ? pool.reserve1 : pool.reserve2;
        let reserve_out: u128 = pool.token2_id == token_in_id ? pool.reserve1 : pool.reserve2;

        assert(max_u128(reserve_in_user, reserve_in) - min_u128(reserve_in_user, reserve_in) < 10u128);
        assert(max_u128(reserve_out_user, reserve_out) - min_u128(reserve_out_user, reserve_out) < 10u128);

        let fee: u128 = pool.swap_fee;


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

    
    transition swap_amm_pric_out(receiver: address, 
                                token_in: arcanetoken.aleo/ArcaneToken, 
                                amount_in: u128, 
                                reserve_in: u128,
                                reserve_out: u64,
                                min_amount_out: u64, 
                                ampl_coef: u128,
                                swap_fee: u128,
                                /*extra_voucher: field*/) -> (arcanetoken.aleo/ArcaneToken, credits.aleo/credits/*, ExtraAmountVoucher*/) {

        assert(min_amount_out > 0u64);

        let change_amount: u128 = token_in.amount - amount_in;

        let fee: u128 = swap_fee;

        let amount_in_with_fee: u128 = amount_in; // TODO: add fee 
        let x: u128 = amount_in_with_fee + reserve_in;
        let y: u128 = get_y(reserve_in, reserve_out as u128, ampl_coef, token_in.token_id, 0u64, token_in.token_id, x);
        
        let dy: u128 = reserve_out as u128 - y - 1u128;

        assert(dy >= min_amount_out as u128);

        let token_in_record: ArcaneToken = arcanetoken.aleo/transfer_private_to_public_arc(token_in, SELF_ADDRESS, amount_in);
        let token_out_record: credits = credits.aleo/transfer_public_to_private(receiver, dy as u64);

        // user can get change using this voucher if amount_out is less than actual amount they could receive according to AMM math
        // let extra_amount_voucher: ExtraAmountVoucher = ExtraAmountVoucher {
        //     owner: receiver,
        //     token_id: 0u64,
        //     voucher: extra_voucher
        // };

        return (token_in_record, token_out_record, /*extra_amount_voucher*/) then finalize(reserve_in, reserve_out as u128, token_in.token_id, amount_in, dy/*, extra_voucher*/);
    }

    finalize swap_amm_pric_out(reserve_in_user: u128, 
                              reserve_out_user: u128,
                              token_in_id: u64, 
                              amount_in: u128, 
                              amount_out: u128, 
                              /*extra_change_voucher: field*/) {

        let token_out_id: u64 = 0u64;
        
        let pool_key: field = get_pool_key(token_in_id, token_out_id);
        let pool: PoolInfo = Mapping::get(amm_pools, pool_key);

        let total: u128 = pool.lp_total_supply;

        let reserve_in: u128 = pool.token1_id == token_in_id ? pool.reserve1 : pool.reserve2;
        let reserve_out: u128 = pool.token2_id == token_in_id ? pool.reserve1 : pool.reserve2;

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

    
    transition main (n_coins: u32) -> u128 {
        let actual_token2: u32 = (5u32 > 3u32 && 3u32 > 4u32) ? 3u32 : ((3u32 > 1u32 && 1u32 > 5u32) ? 1u32 : 1u32);

        let token1_id: u128 = 1u128;
        let token2_id: u128 = 2u128;
        let token3_id: u128 = 3u128;

        let actual_amount2: u128 = (token1_id > token2_id && token2_id > token3_id) ? token2_id : ((token2_id > token1_id && token1_id > token3_id) ? token1_id : token3_id);
 
        let gr: group = group::GEN; // the group generator
        return actual_amount2;
    }

}