#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History:  Jun. 2024 - Xudong Hao - creation
from avocado.utils import cpu

from virttest import env_process
from virttest import error_context
from virttest import utils_misc


# This decorator makes the test function aware of context strings
@error_context.context_aware
def run(test, params, env):
    """
    Boot TD with huge CPU and memory:
    1) Caculate the host online CPU number and usable memory size
    2) Boot up one TDVM with half resource of host
    3) Shutdown TDVM

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """

    timeout = params.get_numeric("login_timeout", 240)
    params["start_vm"] = 'yes'
    host_cpu = cpu.online_count()
    host_free_mem = utils_misc.get_usable_memory_size()
    params['smp'] = params['vcpu_maxcpus'] = host_cpu//2
    params['mem'] = host_free_mem//2

    error_context.context("Booting TDVM with large CPU and memory", test.log.info)
    vm_name = params['main_vm']
    try:
        env_process.preprocess_vm(test, params, env, vm_name)
    except:
        raise
    vm = env.get_vm(vm_name)
    vm.verify_alive()
    session = vm.wait_for_login(timeout=timeout)
    vm.destroy()
    session.close()
