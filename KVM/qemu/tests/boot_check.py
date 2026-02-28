#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History:  July. 2024 - Xudong Hao - creation

import subprocess

from avocado.utils import cpu
from virttest import env_process
from virttest import error_context
from virttest import utils_misc


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
    params["start_vm"] = 'yes'
    if (params.get("vm_secure_guest_type") is not None) and (params['vm_secure_guest_type'] == 'tdx'):
        # TD can not boot up with vCPU number larger than host pCPU
        host_cpu = cpu.online_count()
        if params.get_numeric("smp") > host_cpu:
            test.cancel("Platform doesn't support to run this test")

    vm_name = params['main_vm']
    env_process.preprocess_vm(test, params, env, vm_name)
    vm = env.get_vm(vm_name)
    vm.verify_alive()
    timeout = params.get_numeric("login_timeout", 240)
    session = vm.wait_for_login(timeout=timeout)

    vcpus = params.get_numeric("smp")
    if vm.get_cpu_count() != vcpus:
        test.fail("CPU number in guest is not same as configured vcpus number")
    is_max_mem = params.get_boolean("is_max_mem")
    if is_max_mem:
        memory = utils_misc.get_usable_memory_size()
    else:
        memory = params.get_numeric("mem")
        if vm.get_totalmem_sys()//1024 != memory:
            test.fail("Memory in guest is not same as configured")
    session.close()
