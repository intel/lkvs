#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History:  Jun. 2024 - Xudong Hao - creation
from virttest import env_process
from virttest import error_context


# This decorator makes the test function aware of context strings
@error_context.context_aware
def run(test, params, env):
    """
    Boot TD by multiple times:
    1) Boot up one TDVM
    2) Shutdown TDVM
    3) repeat step1 and step2 multiple times

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """

    params["start_vm"] = 'yes'
    timeout = params.get_numeric("login_timeout", 240)
    iterations = params.get_numeric("iterations")
    for i in range(iterations):
        error_context.context("The iteration %s of booting TDVM" % i, test.log.info)
        vm_name = params['main_vm']
        try:
            env_process.preprocess_vm(test, params, env, vm_name)
        except:
            raise
        vm = env.get_vm(vm_name)
        vm.verify_alive()
        session = vm.wait_for_login(timeout=timeout)
        vm.destroy()
