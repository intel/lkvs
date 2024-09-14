#!/usr/bin/python
import sys
import os

from avocado.core.job import Job
from avocado.core.nrunner.runnable import Runnable
from avocado.core.suite import TestSuite
from feature_list import feature_list
from feature_list import get_platform

current_dir = os.path.dirname(os.path.realpath(__file__))
BM_dir = os.path.dirname(current_dir)
source_dir = f"{BM_dir}/tools/cpuid_check"

def main():
    feature_name_list = feature_list.keys()
    platform = get_platform()
    
    tests = []
    for feature_name in feature_name_list:
        if platform in feature_list[feature_name]["platforms"]:
            args = feature_list[feature_name]["cpuid"]
            runnable = Runnable("exec-test", f"{source_dir}/cpuid_check", *args, identifier=feature_name)
            tests.append(runnable)
        else:
            continue

    suite = TestSuite(name="Check", tests=tests)

    # Run the test suites
    with Job(test_suites=[suite]) as j:
        sys.exit(j.run())

if __name__=="__main__":
    main()