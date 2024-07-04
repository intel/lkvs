#!/usr/bin/python3
import sys
import subprocess
import argparse
import os
import shlex
from avocado.core.job import Job
from avocado.core.nrunner.runnable import Runnable
from avocado.core.suite import TestSuite

# Parse command line arguments.
parser = argparse.ArgumentParser(description='Run tests from a list in a file(tests/tests-client/tests-server).')
parser.add_argument('-f', '--feature', help='Directory of a feature to run the tests')
parser.add_argument('-t', '--tests', help='Path to a test file containing the list of tests to run')
args = parser.parse_args()

BM_dir = os.path.dirname(os.path.realpath(__file__))

# Check the dependency, if the exit value is not 0, then terminate the test.
# Parse dependency information.
def parse_line(line):
    colon_index = line.find(':')
    if colon_index != -1:
        info = line[colon_index + 1:].strip()
        if not info:
            return None, None
        at_index = info.find('@')
        if at_index != -1:
            reason_info = info[at_index + 1:].strip()
            info = info[:at_index].strip()
        else:
            reason_info = None
        info += ' >& /dev/null'
        return info, reason_info
    return None, None

def dependency_check(ftests):
    common_dir = f"{BM_dir}/common"
    cpuid_dir = f"{BM_dir}/tools/cpuid_check"

    # Add the necessary environment variables.
    os.environ['PATH'] += os.pathsep + os.pathsep.join([common_dir, cpuid_dir])
    
    # Check the dependency.
    with open(ftests, 'r') as file:
        for line in file:
            if line.startswith('# @hw_dep') or line.startswith('# @other_dep'):
                info, reason_info = parse_line(line)
                if info:
                    try:
                        subprocess.run(info, shell=True, check=True)
                    except subprocess.CalledProcessError:
                        print(f"Terminate the test: {reason_info}")
                        sys.exit(1)
            elif line.startswith('# @other_warn'):
                info, reason_info = parse_line(line)
                if info:
                    try:
                        subprocess.run(info, shell=True, check=True)
                    except subprocess.CalledProcessError:
                        print(f"Warning:  {reason_info}")

def parse_parts(parts):
    parsed_parts = []
    current_part = []
    in_quotes = False

    for part in parts:
        if part.startswith('"') and part.endswith('"') and len(part) > 1:
            parsed_parts.append(part[1:-1])
        elif part.startswith('"'):
            current_part.append(part[1:])
            in_quotes = True
        elif part.endswith('"') and in_quotes:
            current_part.append(part[:-1])
            parsed_parts.append(' '.join(current_part))
            current_part = []
            in_quotes = False
        elif in_quotes:
            current_part.append(part)
        else:
            parsed_parts.append(part)

    if in_quotes:
        raise ValueError("No closing quotation")

    return parsed_parts

# Read the tests file and create Runnable objects.
def create_runnables_from_file(ftests):
    tests = []
    with open(ftests, 'r') as file:
        for line in file:
            # Handle empty lines and comments.
            if not line.strip() or line.startswith('#'):
                continue
            # Split command line parameters.
            parts = line.strip().split()
            # Create a Runnable object.
            params = parse_parts(parts[1:])

            runnable = Runnable("exec-test", parts[0], *params)
            tests.append(runnable)
    return tests

def main():
    # Get the absolute directory of the tests file.
    tests_abs = os.path.abspath(args.tests)

    # Check the dependency and create Runnable objects.
    os.chdir(f"{BM_dir}/{args.feature}")
    dependency_check(tests_abs)
    tests = create_runnables_from_file(tests_abs)

    # Create a test suite and add tests.
    suite = TestSuite(name="lkvs-test", tests=tests)

    # Create and run the job.
    with Job(test_suites=[suite]) as j:
        sys.exit(j.run())

if __name__=="__main__":
    main()
