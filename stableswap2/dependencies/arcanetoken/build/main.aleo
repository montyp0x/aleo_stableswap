program arcanetoken.aleo;

struct BalanceKey:
    token_id as u64;
    addr as address;

record ArcaneToken:
    owner as address.private;
    token_id as u64.private;
    amount as u128.private;

struct ArcaneTokenInfo:
    token_id as u64;
    max_supply as u128;
    decimals as u8;
    admin as address;


mapping arcane_registered_tokens:
	key as u64.public;
	value as ArcaneTokenInfo.public;


mapping arcane_balances:
	key as field.public;
	value as u128.public;

function get_token_info:
    input r0 as ArcaneToken.record;
    output r0.owner as address.private;
    output r0.token_id as u64.private;
    output r0.amount as u128.private;




function create_arcane_token:
    input r0 as u64.private;
    input r1 as u8.private;
    input r2 as u128.private;
    cast r0 r2 r1 self.caller into r3 as ArcaneTokenInfo;
    async create_arcane_token r3 into r4;
    output r4 as arcanetoken.aleo/create_arcane_token.future;

finalize create_arcane_token:
    input r0 as ArcaneTokenInfo.public;
    contains arcane_registered_tokens[r0.token_id] into r1;
    not r1 into r2;
    assert.eq r2 true;
    set r0 into arcane_registered_tokens[r0.token_id];


function split_arc:
    input r0 as ArcaneToken.record;
    input r1 as address.private;
    input r2 as u128.private;
    input r3 as address.private;
    cast r1 r0.token_id r2 into r4 as ArcaneToken.record;
    sub r0.amount r2 into r5;
    cast r3 r0.token_id r5 into r6 as ArcaneToken.record;
    output r4 as ArcaneToken.record;
    output r6 as ArcaneToken.record;


function mint_private_arc:
    input r0 as u64.private;
    input r1 as address.private;
    input r2 as u128.private;
    cast r1 r0 r2 into r3 as ArcaneToken.record;
    async mint_private_arc r0 self.caller r2 into r4;
    output r3 as ArcaneToken.record;
    output r4 as arcanetoken.aleo/mint_private_arc.future;

finalize mint_private_arc:
    input r0 as u64.public;
    input r1 as address.public;
    input r2 as u128.public;
    get arcane_registered_tokens[r0] into r3;
    is.eq r3.admin r1 into r4;
    cast 0field into r5 as address;
    is.eq r3.admin r5 into r6;
    or r4 r6 into r7;
    assert.eq r7 true;


function transfer_public_arc:
    input r0 as u64.private;
    input r1 as address.public;
    input r2 as u128.public;
    cast r0 self.caller into r3 as BalanceKey;
    hash.bhp256 r3 into r4 as field;
    cast r0 r1 into r5 as BalanceKey;
    hash.bhp256 r5 into r6 as field;
    async transfer_public_arc r4 r6 r2 into r7;
    output r7 as arcanetoken.aleo/transfer_public_arc.future;

finalize transfer_public_arc:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as u128.public;
    get arcane_balances[r0] into r3;
    sub r3 r2 into r4;
    set r4 into arcane_balances[r0];
    get.or_use arcane_balances[r1] 0u128 into r5;
    add r5 r2 into r6;
    set r6 into arcane_balances[r1];


function transfer_private_arc:
    input r0 as ArcaneToken.record;
    input r1 as address.private;
    input r2 as u128.private;
    cast r1 r0.token_id r2 into r3 as ArcaneToken.record;
    sub r0.amount r2 into r4;
    cast r0.owner r0.token_id r4 into r5 as ArcaneToken.record;
    output r3 as ArcaneToken.record;
    output r5 as ArcaneToken.record;


function transfer_private_to_public_arc:
    input r0 as ArcaneToken.record;
    input r1 as address.private;
    input r2 as u128.private;
    sub r0.amount r2 into r3;
    cast r0.owner r0.token_id r3 into r4 as ArcaneToken.record;
    cast r0.token_id r1 into r5 as BalanceKey;
    hash.bhp256 r5 into r6 as field;
    async transfer_private_to_public_arc r6 r2 into r7;
    output r4 as ArcaneToken.record;
    output r7 as arcanetoken.aleo/transfer_private_to_public_arc.future;

finalize transfer_private_to_public_arc:
    input r0 as field.public;
    input r1 as u128.public;
    get.or_use arcane_balances[r0] 0u128 into r2;
    add r2 r1 into r3;
    set r3 into arcane_balances[r0];


function transfer_public_to_private_arc:
    input r0 as u64.private;
    input r1 as address.private;
    input r2 as u128.private;
    cast r1 r0 r2 into r3 as ArcaneToken.record;
    cast r0 self.caller into r4 as BalanceKey;
    hash.bhp256 r4 into r5 as field;
    async transfer_public_to_private_arc r5 r2 into r6;
    output r3 as ArcaneToken.record;
    output r6 as arcanetoken.aleo/transfer_public_to_private_arc.future;

finalize transfer_public_to_private_arc:
    input r0 as field.public;
    input r1 as u128.public;
    get arcane_balances[r0] into r2;
    sub r2 r1 into r3;
    set r3 into arcane_balances[r0];


function init_demo_tokens:
    async init_demo_tokens into r0;
    output r0 as arcanetoken.aleo/init_demo_tokens.future;

finalize init_demo_tokens:
    pow 10u128 6u8 into r0;
    mul 1000000000u128 r0 into r1;
    cast 0field into r2 as address;
    cast 1u64 r1 6u8 r2 into r3 as ArcaneTokenInfo;
    set r3 into arcane_registered_tokens[1u64];
    pow 10u128 6u8 into r4;
    mul 1000000000u128 r4 into r5;
    cast 0field into r6 as address;
    cast 2u64 r5 6u8 r6 into r7 as ArcaneTokenInfo;
    set r7 into arcane_registered_tokens[2u64];
    pow 10u128 6u8 into r8;
    mul 1000000000u128 r8 into r9;
    cast 0field into r10 as address;
    cast 3u64 r9 6u8 r10 into r11 as ArcaneTokenInfo;
    set r11 into arcane_registered_tokens[3u64];
    pow 10u128 6u8 into r12;
    mul 1000000000u128 r12 into r13;
    cast 0field into r14 as address;
    cast 4u64 r13 6u8 r14 into r15 as ArcaneTokenInfo;
    set r15 into arcane_registered_tokens[4u64];
