import random
import subprocess

for i in range(100):
    amount_in = random.randint(1, 1000000)
    reserve_in = random.randint(1, 10000000)
    reserve_out = random.randint(1, 10000000)

    # amount_in = 320556

    # reserve_in = 10000000
    # reserve_out = 100000000

    if amount_in > reserve_in:
        amount_in, reserve_in = reserve_in, amount_in

    bash_script = "test.sh"
    script_path = "./test.sh"

    command = f"{script_path} {amount_in} {reserve_in} {reserve_out}"

    try:
        subprocess.run(command, shell=True, check=True)
        print(f"Bash script executed successfully with {amount_in}, {reserve_in}, {reserve_out} parameters.")
    except subprocess.CalledProcessError as error:
        print(f"Error running Bash script: {error}")

    curve_res = "/home/ramych/VSCodeProjects/stableswap/stableswap_vyper/res_curve.txt" # TODO: change to normal path
    leo_res = "/home/ramych/VSCodeProjects/stableswap/stableswap2/res_leo.txt"

    with open(curve_res, "r") as curve:
        data1 = curve.read()
        res1 = int(data1[:-2])

    with open(leo_res, "r") as leo:
        data2 = leo.read()
        res2 = int(data2[:-5])
    
    if abs(res1 - res2) > 1:
        print("Error")
        break