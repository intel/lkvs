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
parser.add_argument('file_path', help='Path to the file containing the list of tests to run')
args = parser.parse_args()
script_dir = os.path.dirname(args.file_path)

# Check the dependency, if the exit value is not 0, then terminate the test.
bash_script = f"./runtests -d {args.file_path}"
result = subprocess.run(bash_script, shell=True)
if result.returncode != 0:
    # Terminate the test.
    sys.exit(1) 


# Read the tests file and create Runnable objects.
def create_runnables_from_file(file_path, script_dir):
    tests = []
    with open(file_path, 'r') as file:
        for line in file:
            # Handle empty lines and comments.
            if not line.strip() or line.startswith('#'):
                continue
            # Split command line parameters.
            parts = line.strip().split()
            script_path = os.path.join(script_dir, parts[0])
            # Create a Runnable object.
            runnable = Runnable("exec-test", script_path, *parts[1:])
            tests.append(runnable)
    return tests

def main():
    tests = create_runnables_from_file(args.file_path, script_dir)

    # Create a test suite and add tests.
    suite = TestSuite(name="lkvs-test", tests=tests)

    # Create and run the job.
    with Job(test_suites=[suite]) as j:
        sys.exit(j.run())

if __name__=="__main__":
    main()