#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History: Aug. 2024 - Xudong Hao - creation

import os
import sys
from avocado.utils import process
from avocado.core import exceptions
from virttest import error_context, env_process
from virttest import utils_package
from provider.test_utils import get_baremetal_dir

curr_dir = os.path.dirname(os.path.abspath(__file__))
check_dir = "%s/../../../BM/instruction-check" % curr_dir
sys.path.append(check_dir)
from feature_list import feature_list


def prepare_cpuid(test, params, src_dir, vm=None, session=None):
    """
    Compile cpuid test tool in host or guest.
    Return the execuable test tool with absolute path.
    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param src_dir: Test tool srouce code directory of absolute path
    :param vm: The vm object
    :param session: Guest session
    """
    source_file = params["source_file"]
    exec_file = params["exec_file"]
    src_cpuid = os.path.join(src_dir, source_file)
    if session:
        test_dir = params["test_dir"]
        vm.copy_files_to(src_cpuid, test_dir)
    else:
        test_dir = src_dir

    if not utils_package.package_install("gcc", session):
        test.cancel("Failed to install package gcc.")

    compile_cmd = "cd %s && gcc %s -o %s" % (test_dir, source_file, exec_file)
    if session:
        status = session.cmd_status(compile_cmd)
    else:
        status = process.system(compile_cmd, shell=True)
    if status:
        raise exceptions.TestError("Test suite compile failed.")

    return os.path.join(test_dir, exec_file)


def check_cpuid(cpuid_arg, exec_bin, session=None):
    """
    Run cpuid test in host or guest
    :param cpuid_arg: The feature to be checked
    :param exec_bin: The execuable bianry tool with absolute path
    :param session: Guest session
    """
    check_cmd = '%s %s' % (exec_bin, cpuid_arg)
    func = process.getstatusoutput
    if session:
        func = session.cmd_status_output
    s, o = func(check_cmd)

    return s


@error_context.context_aware
def run(test, params, env):
    """
    Check cpuid inside guest.
    1) Check if current cpuid are support in host, if no, cancel test
    2) Boot up guest
    3) Check cpuid/s in guest
    4) Shutdown guest
    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    def host_feature_cpuid():
        for feature_name in feature_names.split():
            args = feature_list[feature_name]["cpuid"]
            cpuid_arg = ' '.join(args)
            host_status = check_cpuid(cpuid_arg, host_exec_bin)  # pylint: disable=E0606
            if host_status:
                process.system("rm %s -f" % host_exec_bin, shell=True, ignore_status=True)
                test.cancel("Platform doesn't support %s" % feature_name)
        test.log.info("Host cpuid check %s pass.", feature_names)

    def host_check_cpuid():
        for cpuid_arg in cpuid_args.split(","):
            host_status = check_cpuid(cpuid_arg, host_exec_bin)   # pylint: disable=E0606
            if host_status:
                process.system("rm %s -f" % host_exec_bin, shell=True, ignore_status=True)
                test.cancel("Platform doesn't support %s" % cpuid_arg)
        test.log.info("Host cpuid check %s pass.", cpuid_args)

    def guest_feature_cpuid():
        for feature_name in feature_names.split():
            args = feature_list[feature_name]["cpuid"]
            cpuid_arg = ' '.join(args)
            guest_status = check_cpuid(cpuid_arg, vm_exec_bin, session)
            if guest_status:
                test.fail("%s cpuid check fail in guest." % feature_name)
        test.log.info("Guest cpuid check %s pass.", feature_names)

    def guest_check_cpuid():
        for cpuid_arg in cpuid_args.split(","):
            guest_status = check_cpuid(cpuid_arg, vm_exec_bin, session)
            if guest_status:
                test.fail("%s cpuid check fail in guest." % cpuid_arg)
        test.log.info("Guest cpuid check %s pass.", cpuid_args)

    test_dir = params["test_dir"]
    feature_names = params.get("features")
    cpuid_args = params.get("cpuid")
    bm_dir = get_baremetal_dir(params)
    src_dir = "%s/tools/cpuid_check" % bm_dir

    check_host_cpuid = params.get_boolean("check_host_cpuid")
    if check_host_cpuid:
        host_exec_bin = prepare_cpuid(test, params, src_dir)
        if feature_names:
            host_feature_cpuid()
        elif cpuid_args:
            host_check_cpuid()
        else:
            test.error("Failed to find feature or CPUID bit in config file")

    try:
        params["start_vm"] = "yes"
        vm_name = params['main_vm']
        env_process.preprocess_vm(test, params, env, vm_name)
        vm = env.get_vm(vm_name)
        session = vm.wait_for_login()

        vm_exec_bin = prepare_cpuid(test, params, src_dir, vm, session)
        if feature_names:
            guest_feature_cpuid()
        elif cpuid_args:
            guest_check_cpuid()
        else:
            test.error("Failed to find feature or CPUID bit in config file")

    finally:
        process.system("rm %s -f" % host_exec_bin, shell=True, ignore_status=True)
        session.cmd("rm %s/cpuid* -rf" % test_dir, ignore_all_errors=True)
        session.close()
