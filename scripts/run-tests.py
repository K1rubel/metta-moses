import subprocess
import pathlib
import sys
import re
from concurrent.futures import ThreadPoolExecutor, as_completed

# Define ANSI escape codes for colors
RESET = "\033[0m"
BOLD = "\033[1m"
UNDERLINE = "\033[4m"
CYAN = "\033[96m"
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
MAGENTA = "\033[95m"

def extract_and_print(result, path, idx) -> bool:
    """
    Extracts the output from the test execution result and prints the status.
    """
    output = result.stdout if result.returncode == 0 else result.stderr
    extracted = output.replace("[()]\n", "")

    has_failure = "Error" in extracted

    if not has_failure:
        extracted = "test passed"

    status_color = RED if has_failure else GREEN
    print(YELLOW + f"Test {idx + 1}: {path}" + RESET)
    print(status_color + extracted + RESET)
    print(YELLOW + f"Exit-code: {result.returncode}" + RESET)
    print("-" * 40)

    return has_failure

def run_test_file(test_file):
    """
    Runs a single test file using the `mettalog` command.
    """
    print(f"Running mettalog on {test_file}")
    try:
        result = subprocess.run(
            [metta_run_command, str(test_file), "--html"],
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        )
        return result, test_file, False
    except subprocess.TimeoutExpired as e:
        print(RED + f"Timeout on {test_file}: {e}" + RESET)
        return e, test_file, True
    except subprocess.CalledProcessError as e:
        print(RED + f"Error with {test_file}: {e.stderr}" + RESET)
        return e, test_file, True

# Function to print ASCII art
def print_ascii_art(text):
    art = f"""
                {text}
           """
    print(CYAN + art + RESET)

# Define the command to run with the test files
metta_run_command = "mettalog"

# Restrict test file discovery to utilities/tests
test_dir = pathlib.Path("utilities/tests")
testMettaFiles = list(test_dir.rglob("*test.metta"))
total_files = len(testMettaFiles)

if total_files == 0:
    print(RED + "No *test.metta files found in utilities/tests" + RESET)
    sys.exit(1)

print(CYAN + f"Found {total_files} test files:" + RESET)
for test_file in testMettaFiles:
    print(f"  - {test_file}")

# Print ASCII art title
print_ascii_art("Parallel Test Runner")

# Execute tests in parallel
results = []
fails = 0
with ThreadPoolExecutor() as executor:
    future_to_test = {
        executor.submit(run_test_file, test_file): idx
        for idx, test_file in enumerate(testMettaFiles)
    }

    for future in as_completed(future_to_test):
        idx = future_to_test[future]
        try:
            result, path, has_failure = future.result()
            if isinstance(result, (subprocess.CalledProcessError, subprocess.TimeoutExpired)):
                fails += 1
                continue

            # Extract and print results
            has_failure = extract_and_print(result, path, idx)
            if has_failure:
                fails += 1

        except Exception as exc:
            print(RED + f"Test {idx + 1}: generated an exception: {exc}" + RESET)
            fails += 1

# Summary
print(CYAN + "\nTest Summary" + RESET)
print(f"{total_files} files tested.")
print(RED + f"{fails} failed." + RESET)
print(GREEN + f"{total_files - fails} succeeded." + RESET)

if fails > 0:
    print(RED + "Tests failed. Process Exiting with exit code 1" + RESET)
    sys.exit(1)