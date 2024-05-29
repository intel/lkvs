#!/usr/bin/python

import sys
from avocado.core.job import Job
from avocado.core.nrunner.runnable import Runnable
from avocado.core.suite import TestSuite
from feature_list import cpuid_info

def main():
    feature_name_list = cpuid_info.keys()

    suites = []

    for feature_name in feature_name_list:
        args = cpuid_info[feature_name]
        runnable = Runnable("exec-test", "../tools/cpuid_check/cpuid_check", *args)
        suite = TestSuite(name=feature_name, tests=[runnable])
        suites.append(suite)
    
    # Run the test suites
    with Job(test_suites=suites) as j:
        sys.exit(j.run())

if __name__=="__main__":
    main()