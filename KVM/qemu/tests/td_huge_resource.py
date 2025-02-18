#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History:  Jun. 2024 - Xudong Hao - creation
import time

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
    2) Boot up one TDVM with huge resource of host
    3) Shutdown TDVM

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """
    xfail = False
    if (params.get("xfail") is not None) and (params.get("xfail") == "yes"):
        xfail = True

    timeout = params.get_numeric("login_timeout", 240)
    params["start_vm"] = 'yes'
    host_cpu = cpu.online_count()
    host_free_mem = utils_misc.get_usable_memory_size()
    params['mem'] = host_free_mem//2

    if params.get("sleep_after_powerdown"):
        sleep_after_powerdown = int(params.get("sleep_after_powerdown"))
    else:
        sleep_after_powerdown = 10
    if (params.get("check_host_cpu") is not None) and (params['check_host_cpu'] == 'yes'):
        params['smp'] = params['vcpu_maxcpus'] = host_cpu
    elif (params.get("overrange_host_cpu") is not None) and (params['overrange_host_cpu'] == 'yes'):
        params['smp'] = params['vcpu_maxcpus'] = host_cpu+1
    else:
        params['smp'] = params['vcpu_maxcpus'] = host_cpu//2

    error_context.context("Booting TDVM with large CPU and memory", test.log.info)
    vm_name = params['main_vm']
    has_error = False
    try:
        env_process.preprocess_vm(test, params, env, vm_name)
    except:
        has_error = True
        if xfail is False:
            raise

    if (has_error is False) and (xfail is True):
        test.fail("Test was expected to fail, but it didn't")

    if xfail is False:
        vm = env.get_vm(vm_name)
        vm.verify_alive()
        session = vm.wait_for_login(timeout=timeout)
        session.close()
        vm.destroy()
    # Add sleep time for qemu to release resources completely
    time.sleep(sleep_after_powerdown)
