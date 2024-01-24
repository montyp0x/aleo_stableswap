program arcanetoken.aleo {
    
    struct BalanceKey {
        token_id: u64,
        addr: address
    }

    record ArcaneToken {
        private owner: address,
        private token_id: u64,
        private amount: u128
    }

    struct ArcaneTokenInfo {
        token_id: u64,        
        max_supply: u128,
        decimals: u8,
        admin: address,
    }

    mapping arcane_registered_tokens: u64 => ArcaneTokenInfo;
    mapping arcane_balances: field => u128;

    inline get_balance_key(token_id: u64, addr: address) -> field {
        return BHP256::hash_to_field(BalanceKey {token_id: token_id, addr: addr});
    }

    transition create_arcane_token(token_id: u64, decimals: u8, max_supply: u128) {
        let new_token: ArcaneTokenInfo = ArcaneTokenInfo{
            token_id: token_id,
            max_supply: max_supply,
            decimals: decimals,
            admin: self.caller
        };
        return then finalize(new_token);
    }

    finalize create_arcane_token(new_token: ArcaneTokenInfo) {
        assert(!Mapping::contains(arcane_registered_tokens, new_token.token_id));
        Mapping::set(arcane_registered_tokens, new_token.token_id, new_token);    
    }

    transition split_arc(token: ArcaneToken, owner1: address, amount1: u128, owner2: address) -> (ArcaneToken, ArcaneToken) {
        let part1: ArcaneToken = ArcaneToken {
            owner: owner1,
            token_id: token.token_id,
            amount: amount1
        };

        let part2: ArcaneToken = ArcaneToken {
            owner: owner2,
            token_id: token.token_id,
            amount: token.amount - amount1
        };
        return (part1, part2);
    }

    transition mint_private_arc(
        token_id: u64,
        receiver: address, 
        amount: u128,
    ) -> ArcaneToken {
        return ArcaneToken {
            owner: receiver,
            amount: amount,
            token_id,
        } then finalize(token_id, self.caller, amount);        
    }

    finalize mint_private_arc(token_id: u64, caller: address, amount: u128) {
        let token_info: ArcaneTokenInfo = Mapping::get(arcane_registered_tokens, token_id);
        assert (token_info.admin == caller || token_info.admin == 0field as address);
    }

    transition transfer_public_arc(token_id: u64, public to: address, public amount: u128) {
        return then finalize(get_balance_key(token_id, self.caller), get_balance_key(token_id, to), amount);
    }

    finalize transfer_public_arc(from: field, to: field, amount: u128) {
        let balance_from: u128 = Mapping::get(arcane_balances, from);
        Mapping::set(arcane_balances, from, balance_from - amount);

        let balance_to: u128 = Mapping::get_or_use(arcane_balances, to, 0u128);
        Mapping::set(arcane_balances, to, balance_to + amount);
    }

    transition transfer_private_arc(input: ArcaneToken, to: address, amount: u128) -> (ArcaneToken, ArcaneToken) {
        let output: ArcaneToken = ArcaneToken {
            owner: to, 
            token_id: input.token_id,
            amount: amount
        };
        let change: ArcaneToken = ArcaneToken {
            owner: input.owner,
            token_id: input.token_id,
            amount: input.amount - amount,
        };
        return (output, change);
    }

    transition transfer_private_to_public_arc(input: ArcaneToken, to: address, amount: u128) -> ArcaneToken {
        let change: ArcaneToken = ArcaneToken {
            owner: input.owner,
            token_id: input.token_id,
            amount: input.amount - amount
        };
        return change then finalize(get_balance_key(input.token_id, to), amount);
    }

    finalize transfer_private_to_public_arc(to: field, amount: u128) {
        let balance_to: u128 = Mapping::get_or_use(arcane_balances, to, 0u128);
        Mapping::set(arcane_balances, to, balance_to + amount);
    }

    transition transfer_public_to_private_arc(token_id: u64, to: address, amount: u128) -> ArcaneToken {
       return ArcaneToken {
           owner: to,
           token_id: token_id,
           amount: amount
       } then finalize(get_balance_key(token_id, self.caller), amount);
    }

    finalize transfer_public_to_private_arc(from: field, amount: u128) {
        let balance_from: u128 = Mapping::get(arcane_balances, from);
        Mapping::set(arcane_balances, from, balance_from - amount);
    }

    transition init_demo_tokens() {
        return then finalize();
    }

    finalize init_demo_tokens() {
        let decimals: u8 = 6u8;

        Mapping::set(arcane_registered_tokens, 1u64, ArcaneTokenInfo {
             token_id: 1u64,
             max_supply: 1000000000u128 * (10u128 ** decimals),
             decimals: decimals,
             admin: 0field as address,
        });    
        Mapping::set(arcane_registered_tokens, 2u64, ArcaneTokenInfo {
             token_id: 2u64,
             max_supply: 1000000000u128 * (10u128 ** decimals),
             decimals: decimals,
             admin: 0field as address,
        });    
        Mapping::set(arcane_registered_tokens, 3u64, ArcaneTokenInfo {
             token_id: 3u64,
             max_supply: 1000000000u128 * (10u128 ** decimals),
             decimals: decimals,
             admin: 0field as address,
        });    
        Mapping::set(arcane_registered_tokens, 4u64, ArcaneTokenInfo {
             token_id: 4u64,
             max_supply: 1000000000u128 * (10u128 ** decimals),
             decimals: decimals,
             admin: 0field as address,
        });
    }

}