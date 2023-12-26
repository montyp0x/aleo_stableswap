#!/bin/bash
# First check that Leo is installed.
if ! command -v leo &> /dev/null
then
    echo "leo is not installed."
    exit
fi

echo "
We will be playing the role of two parties.

The private key and address of the owner.
private_key: APrivateKey1zkp2LjnNzhzuvo3LGBRon2hACpMjqQxvT1Qfhmg4vnU8Bz9
address: aleo1kmdwqlr9lugu3u0j2nm8llj3wyn0hqr433fzejtp90mfmf5fgqgsvte5tx

The private key and address of the user.
private_key: APrivateKey1zkpDSFPwdJt7QJCVhnjPLQpPQDN57euYHvpW7PGfwB6wGG4
address: aleo1uyy6uxd3swdalye05jqtuasaxstpacvsdfmknwy92fgy6hyntvyqmpa6jw
"

echo '
NETWORK=testnet3
PRIVATE_KEY=APrivateKey1zkp2LjnNzhzuvo3LGBRon2hACpMjqQxvT1Qfhmg4vnU8Bz9
' > .env

leo run create_pool aleo1kmdwqlr9lugu3u0j2nm8llj3wyn0hqr433fzejtp90mfmf5fgqgsvte5tx "{
    owner: aleo1kmdwqlr9lugu3u0j2nm8llj3wyn0hqr433fzejtp90mfmf5fgqgsvte5tx.private,
    amount: 1000000000u128.private,
    token_id: 1u64.private,
    _nonce: 4668394794828730542675887906815309351994017139223602571716627453741502624516group.public
}" 1000u128 "{
    owner: aleo1kmdwqlr9lugu3u0j2nm8llj3wyn0hqr433fzejtp90mfmf5fgqgsvte5tx.private,
    amount: 1000000000u128.private,
    token_id: 2u64.private,
    _nonce: 605849623036268790365773177565562473735086364071033205649960161942593750353group.public
}" 1000u128 100u128 1u128

echo '
NETWORK=testnet3
PRIVATE_KEY=APrivateKey1zkpDSFPwdJt7QJCVhnjPLQpPQDN57euYHvpW7PGfwB6wGG4
' > .env

# leo run get_d2 50u128 100u128 100u128

# leo run debug aleo1uyy6uxd3swdalye05jqtuasaxstpacvsdfmknwy92fgy6hyntvyqmpa6jw "{
#     owner: aleo1uyy6uxd3swdalye05jqtuasaxstpacvsdfmknwy92fgy6hyntvyqmpa6jw.private,
#     amount: 100000u128.private,
#     token_id: 1u64.private,
#     _nonce: 1738483341280375163846743812193292672860569105378494043894154684192972730518group.public
# }" 1u64 2u64 100000u128 1u128 1000000000u128 1000000000u128 1u64 2u64 100000u128 1u128

# leo run exchange aleo1uyy6uxd3swdalye05jqtuasaxstpacvsdfmknwy92fgy6hyntvyqmpa6jw "{
#     owner: aleo1uyy6uxd3swdalye05jqtuasaxstpacvsdfmknwy92fgy6hyntvyqmpa6jw.private,
#     amount: 1000000u128.private,
#     token_id: 1u64.private,
#     _nonce: 1738483341280375163846743812193292672860569105378494043894154684192972730518group.public
# }" 1u64 2u64 100u128 1u128 1000u128 1000u128 1u64 2u64 100u128 1u128

# leo run exchange aleo1uyy6uxd3swdalye05jqtuasaxstpacvsdfmknwy92fgy6hyntvyqmpa6jw "{
#     owner: aleo1uyy6uxd3swdalye05jqtuasaxstpacvsdfmknwy92fgy6hyntvyqmpa6jw.private,
#     amount: 999900u128.private,
#     token_id: 1u64.private,
#     _nonce: 1738483341280375163846743812193292672860569105378494043894154684192972730518group.public
# }" 1u64 2u64 900u128 1u128 1100u128 901u128 1u64 2u64 100u128 1u128

leo run exchange aleo1uyy6uxd3swdalye05jqtuasaxstpacvsdfmknwy92fgy6hyntvyqmpa6jw "{
    owner: aleo1uyy6uxd3swdalye05jqtuasaxstpacvsdfmknwy92fgy6hyntvyqmpa6jw.private,
    amount: 1000000u128.private,
    token_id: 1u64.private,
    _nonce: 1738483341280375163846743812193292672860569105378494043894154684192972730518group.public
}" 1u64 2u64 1000u128 1u128 1100u128 11000u128 1u64 2u64 100u128 1u128
