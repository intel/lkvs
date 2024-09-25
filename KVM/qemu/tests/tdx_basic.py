#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History:  May. 2024 - Xudong Hao - creation

from avocado.utils import process, cpu
from virttest import error_context, env_process
from provider.cpu_utils import check_cpu_flags


@error_context.context_aware
def run(test, params, env):
    """
    TDX basic test:
    1. Check host TDX capability
    2. Boot TDVM
    3. Verify TDX enabled in guest

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    if cpu.get_cpu_vendor_name() != 'intel':
        test.cancel("This test is supposed to run on Intel host")

    rdmsr_cmd = params["rdmsr_cmd"]
    if process.getoutput(rdmsr_cmd) != "1":
        test.fail("Platform does not support TDX-SEAM")

    flags = params["flags"]
    check_host_flags = params.get_boolean("check_host_flags")
    if check_host_flags:
        check_cpu_flags(params, flags, test)

    read_cmd = params["read_cmd"]
    tdx_value = process.getoutput(read_cmd % "tdx")
    if tdx_value != "Y":
        test.fail("TDX is not supported in KVM")

    params["start_vm"] = "yes"
    env_process.preprocess_vm(test, params, env, params["main_vm"])
    vm = env.get_vm(params["main_vm"])
    vm.verify_alive()
    timeout = params.get_numeric("login_timeout", 240)
    session = vm.wait_for_login(timeout=timeout)
    if params.get("guest_flags"):
        flags = params["guest_flags"]
    check_cpu_flags(params, flags, test, session)
    session.close()
