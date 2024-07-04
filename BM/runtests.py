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

# Read the tests file and create Runnable objects.
def create_runnables_from_file(ftests):
    tests = []
    with open(ftests, 'r') as file:
        for line in file:
            # Handle empty lines and comments.
            if not line.strip() or line.startswith('#'):
                continue

            # Split command line parameters.
            parts = parse_cmd_str(line.strip())
            runnable = Runnable("exec-test", *parts)
            tests.append(runnable)

    return tests

def parse_cmd_str(cmd):
    lexer = shlex.shlex(cmd, posix=True)
    lexer.whitespace_split = True
    lexer.whitespace = ' '
    return list(lexer)

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
