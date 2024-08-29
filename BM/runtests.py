#!/usr/bin/env python3

from avocado.core.nrunner.runnable import Runnable
from avocado.core.suite import TestSuite
from avocado.core.job import Job
import subprocess
import argparse
import shlex
import sys
import os

# Parse command line arguments.
parser = argparse.ArgumentParser(description='Run tests from a list in a file(tests).')
parser.add_argument('-f', '--feature', required=True,
    help='Directory of a feature to run the tests')
parser.add_argument('-t', '--tests', required=True,
    help='Path to a test file containing the list of tests to run')
args = parser.parse_args()

BM_dir = os.path.dirname(os.path.realpath(__file__))

# Check the dependency, if the exit value is not 0, then terminate the test.
# Parse dependency information.
def parse_line(line):
    if ':' not in line:
        return None, None

    info = line.split(':', 1)[1].strip()
    if not info:
        return None, None

    if '@' in info:
        info, reason_info = map(str.strip, info.split('@', 1))
    else:
        reason_info = None

    return f"{info} >& /dev/null", reason_info

def dependency_check(ftests):
    common_dir = f"{BM_dir}/common"
    cpuid_dir = f"{BM_dir}/tools/cpuid_check"

    # Add the necessary environment variables.
    os.environ['PATH'] += os.pathsep + common_dir + os.pathsep + cpuid_dir

    # Check the dependency.
    with open(ftests, 'r') as file:
        for line in file:
            if line.startswith(('# @hw_dep', '# @other_dep', '# @other_warn')):
                info, reason_info = parse_line(line)
                if info:
                    try:
                        subprocess.run(info, shell=True, check=True)
                    except subprocess.CalledProcessError:
                        if line.startswith('# @other_warn'):
                            print(f"Warning: {reason_info}")
                        else:
                            print(f"Terminate the test: {reason_info}")
                            sys.exit(1)

# Read the tests file and create Runnable objects.
def create_runnables_from_file(ftests):
    tests = []
    with open(ftests, 'r') as file:
        for line in file:
            # Handle empty lines and comments.
            line_str = line.strip()
            if not line_str or line.startswith('#'):
                continue

            # Split command line parameters.
            cmd_line = shlex.split(line_str)
            runnable = Runnable("exec-test", *cmd_line)
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
