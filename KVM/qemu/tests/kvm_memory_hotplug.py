#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

# Author: Kai Zhang <kai.zhang@intel.com>
#
# History:  Jun. 2026 - Kai Zhang - creation

from provider import dmesg_router  # pylint: disable=unused-import
from virttest import error_context, env_process
from virttest.utils_test.qemu import MemoryHotplugTest


@error_context.context_aware
def run(test, params, env):
    """
    KVM memory hotplug & unplug test:
    1. boot legacy VM with memory hotplug capability enabled
    2. check whether hotplugged memory is increasing correctly
    3. hot unplug the hot plugged memory

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """

    params["start_vm"] = "yes"
    env_process.preprocess_vm(test, params, env, params["main_vm"])
    vm = env.get_vm(params["main_vm"])
    vm.verify_alive()
    timeout = params.get_numeric("login_timeout", 240)
    session = vm.wait_for_login(timeout=timeout)
    mem_name = params["target_mems"]
    hotplug_test = MemoryHotplugTest(test, params, env)
    hotplug_test.hotplug_memory(vm, mem_name)
    hotplug_test.unplug_memory(vm, mem_name)
    session.close()
