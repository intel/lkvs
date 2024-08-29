#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History:  Jun. 2024 - Xudong Hao - creation
from virttest import error_context


# This decorator makes the test function aware of context strings
@error_context.context_aware
def run(test, params, env):
    """
    Boot TD by multiple times:
    1) Boot up TDVM
    2) Shutdown TDVM
    3) repeat step1 and step2 multiple times

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """

    timeout = params.get_numeric("login_timeout", 240)
    serial_login = params.get("serial_login", "no") == "yes"
    iterations = params.get_numeric("iterations")
    for i in range(iterations):
        error_context.context("The iteration %s of booting TDVM(s)" % i, test.log.info)
        vms = env.get_all_vms()
        for vm in vms:
            vm.create()
        for vm in vms:
            vm.verify_alive()
            if serial_login:
                session = vm.wait_for_serial_login(timeout=timeout)
            else:
                session = vm.wait_for_login(timeout=timeout)
            session.close()
            vm.destroy()
