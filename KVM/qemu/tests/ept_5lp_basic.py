#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History:  May. 2025 - Xudong Hao - creation

from avocado.utils import process, cpu
from virttest import error_context, env_process
from provider.cpu_utils import check_vmx_flags


@error_context.context_aware
def run(test, params, env):
    """
    EPT 5 level paging basic test:
    1. Check host EPT 5 level paging capability
    2. Boot VM
    3. Check VMX flag in VM (VM Nested supported)

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    if cpu.get_cpu_vendor_name() != 'intel':
        test.cancel("This test is supposed to run on Intel host")

    rdmsr_cmd = params["rdmsr_cmd"]
    if process.getoutput(rdmsr_cmd) != "1":
        test.fail("Platform does not support EPT 5 level paging")

    flags = params["flags"]
    check_host_flags = params.get_boolean("check_host_flags")
    if check_host_flags:
        check_vmx_flags(params, flags, test)

    read_cmd = params["read_cmd"]
    ept_value = process.getoutput(read_cmd % "ept")
    if ept_value != "Y":
        test.fail("EPT is not enabled in KVM")

    params["start_vm"] = "yes"
    env_process.preprocess_vm(test, params, env, params["main_vm"])
    vm = env.get_vm(params["main_vm"])
    vm.verify_alive()
    timeout = params.get_numeric("login_timeout", 240)
    session = vm.wait_for_login(timeout=timeout)
    if params.get("guest_flags"):
        flags = params["guest_flags"]
    if params.get("no_flags", "") == flags:
        flags = ""
    check_vmx_flags(params, flags, test, session)
    session.close()
