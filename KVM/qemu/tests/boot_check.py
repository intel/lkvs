#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History:  July. 2024 - Xudong Hao - creation

from virttest import error_context


@error_context.context_aware
def run(test, params, env):
    """
    VM boot test and check resource of cpu and memeory:
    1. Boot VM
    2. Check if guest cpu and memory are expected as configured
    3. Destroy VM

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    vm = env.get_vm(params["main_vm"])
    vm.verify_alive()
    timeout = params.get_numeric("login_timeout", 240)
    session = vm.wait_for_login(timeout=timeout)

    vcpus = params.get_numeric("smp")
    if vm.get_cpu_count() != vcpus:
        test.fail("CPU number in guest is not same as configured vcpus number")
    memory = params.get_numeric("mem")
    if vm.get_totalmem_sys()//1024 != memory:
        test.fail("Memory in guest is not same as configured")
    session.close()
