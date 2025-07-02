import subprocess
import pathlib
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

# ANSI Colors
RESET = "\033[0m"
BOLD = "\033[1m"
CYAN = "\033[96m"
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"

def print_ascii_art(text):
    print(CYAN + f"\n    {text}\n" + RESET)

def extract_and_print(result, path, idx):
    output = result.stdout if result.returncode == 0 else result.stderr
    has_failure = "Error" in output or "ERROR" in output or result.returncode != 0

    print(YELLOW + f"Test {idx + 1}: {path}" + RESET)
    print((RED if has_failure else GREEN) + output.strip() + RESET)
    print(YELLOW + f"Exit-code: {result.returncode}" + RESET)
    print("-" * 40)

    return has_failure

def run_test_file(test_file):
    try:
        result = subprocess.run(
            [mettalog_command, str(test_file)],
            capture_output=True,
            text=True,
            check=True,
        )
        return result, test_file, False
    except subprocess.CalledProcessError as e:
        return e, test_file, True

# Define the command
mettalog_command = "./metta-wam/mettalog"

# Locate test files
root = pathlib.Path("../")
test_files = list(root.rglob("*test.metta"))
total_files = len(test_files)
fails = 0

print_ascii_art("Running MeTTaLog Tests")

with ThreadPoolExecutor() as executor:
    future_to_index = {
        executor.submit(run_test_file, test_file): idx
        for idx, test_file in enumerate(test_files)
    }

    for future in as_completed(future_to_index):
        idx = future_to_index[future]
        try:
            result, path, has_failure = future.result()
            has_failure = extract_and_print(result, path, idx)
            if has_failure:
                fails += 1
        except Exception as exc:
            print(RED + f"Test {idx + 1} failed with exception: {exc}" + RESET)
            fails += 1

# Summary
print(CYAN + "\nTest Summary" + RESET)
print(f"{total_files} files tested.")
print(RED + f"{fails} failed." + RESET)
print(GREEN + f"{total_files - fails} succeeded." + RESET)

if fails > 0:
    sys.exit(1)
