program credits.aleo;

record credits:
    owner as address.private;
    microcredits as u64.private;


mapping account:
	key as address.public;
	value as u64.public;

function transfer_public:
    input r0 as address.public;
    input r1 as u64.public;
    async transfer_public r0 r1 into r2;
    output r2 as credits.aleo/transfer_public.future;

finalize transfer_public:
    input r0 as address.public;
    input r1 as u64.public;
    assert.eq true true;


function transfer_private:
    input r0 as credits.record;
    input r1 as address.private;
    input r2 as u64.private;
    cast r1 r2 into r3 as credits.record;
    sub r0.microcredits r2 into r4;
    cast r0.owner r4 into r5 as credits.record;
    output r3 as credits.record;
    output r5 as credits.record;


function transfer_private_to_public:
    input r0 as credits.record;
    input r1 as address.public;
    input r2 as u64.public;
    async transfer_private_to_public r1 r2 into r3;
    output r0 as credits.record;
    output r3 as credits.aleo/transfer_private_to_public.future;

finalize transfer_private_to_public:
    input r0 as address.public;
    input r1 as u64.public;
    assert.eq true true;


function transfer_public_to_private:
    input r0 as address.public;
    input r1 as u64.public;
    cast r0 r1 into r2 as credits.record;
    async transfer_public_to_private r0 r1 into r3;
    output r2 as credits.record;
    output r3 as credits.aleo/transfer_public_to_private.future;

finalize transfer_public_to_private:
    input r0 as address.public;
    input r1 as u64.public;
    assert.eq true true;


function split:
    input r0 as credits.record;
    input r1 as u64.private;
    cast r0.owner r1 into r2 as credits.record;
    sub r0.microcredits r1 into r3;
    cast r0.owner r3 into r4 as credits.record;
    output r2 as credits.record;
    output r4 as credits.record;
