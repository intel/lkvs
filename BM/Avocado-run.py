#!/usr/bin/python3
import sys
import subprocess
import argparse
import os
from avocado.core.job import Job
from avocado.core.nrunner.runnable import Runnable
from avocado.core.suite import TestSuite

# Parse command line arguments.
parser = argparse.ArgumentParser(description='Run tests from a list in a file(tests/tests-client/tests-server).')
parser.add_argument('-f', '--feature', help='Directory of a feature to run the tests')
parser.add_argument('-t', '--tests', help='Path to a test file containing the list of tests to run')
args = parser.parse_args()

# Check the dependency, if the exit value is not 0, then terminate the test.
# TODO

# Read the tests file and create Runnable objects.
def create_runnables_from_file(ftests, feature_dir):
    tests = []
    with open(ftests, 'r') as file:
        for line in file:
            # Handle empty lines and comments.
            if not line.strip() or line.startswith('#'):
                continue
            # Split command line parameters.
            parts = line.strip().split()
            script_path = os.path.join(feature_dir, parts[0])
            # Create a Runnable object.
            runnable = Runnable("exec-test", script_path, *parts[1:])
            tests.append(runnable)
    return tests

def main():
    tests = create_runnables_from_file(args.tests, args.feature)

    # Create a test suite and add tests.
    suite = TestSuite(name="lkvs-test", tests=tests)

    # Create and run the job.
    with Job(test_suites=[suite]) as j:
        sys.exit(j.run())

if __name__=="__main__":
    main()
