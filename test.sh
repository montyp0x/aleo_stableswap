#!/bin/bash

amount_in=$1
reserve1=$2
reserve2=$3

cd stableswap2
output=$(bash run_pool2.sh "${amount_in}u128" "${reserve1}u128" "${reserve2}u128")

echo "$output" | grep -oP '(?<=amount: )\d+u128' > tmp.txt

awk -F: 'NR==2 {print $1}' tmp.txt > res_leo.txt

cd ..
cd stableswap_vyper
npx hardhat test-leo --amount-in $amount_in --reserve-in $reserve1 --reserve-out $reserve2 > res_curve.txt