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
    Boot TD with debug on/off:
    1) Boot up one TDVM with "debug=off" or "debug=on"
    2) Inject NMI to TDVM
    3) The TD works well
    4) Shutdown TDVM and close session

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """

    vm = env.get_vm(params["main_vm"])
    vm.verify_alive()
    timeout = params.get_numeric("login_timeout", 240)
    session = vm.wait_for_login(timeout=timeout)
    if (params.get("nmi") == "yes"):
        error_context.context("Inject NMI to TDVM", test.log.info)
        vm.monitor.cmd("inject-nmi")
        vm.verify_alive()
    session.close()
