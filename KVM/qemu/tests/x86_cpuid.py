#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History: Aug. 2024 - Xudong Hao - creation

from provider import dmesg_router  # pylint: disable=unused-import
import os
import sys
from avocado.utils import process
from virttest import error_context, env_process
from provider.test_utils import get_baremetal_dir
from provider.cpuid_utils import check_cpuid, prepare_cpuid

curr_dir = os.path.dirname(os.path.abspath(__file__))
check_dir = "%s/../../../BM/instruction-check" % curr_dir
sys.path.append(check_dir)
from feature_list import feature_list


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
    if feature_names is None and cpuid_args is None:
        test.error("Failed to find feature or CPUID bit in config file")
    bm_dir = get_baremetal_dir(params)
    src_dir = "%s/tools/cpuid_check" % bm_dir

    check_host_cpuid = params.get_boolean("check_host_cpuid")
    if check_host_cpuid:
        host_exec_bin = prepare_cpuid(test, params, src_dir)
        if feature_names:
            host_feature_cpuid()
        if cpuid_args:
            host_check_cpuid()

    try:
        params["start_vm"] = "yes"
        vm_name = params['main_vm']
        env_process.preprocess_vm(test, params, env, vm_name)
        vm = env.get_vm(vm_name)
        session = vm.wait_for_login()

        vm_exec_bin = prepare_cpuid(test, params, src_dir, vm, session)
        if feature_names:
            guest_feature_cpuid()
        if cpuid_args:
            guest_check_cpuid()

    finally:
        if check_host_cpuid:
            process.system("rm %s -f" % host_exec_bin, shell=True, ignore_status=True)
        session.cmd("rm %s/cpuid* -rf" % test_dir, ignore_all_errors=True)
        session.close()
