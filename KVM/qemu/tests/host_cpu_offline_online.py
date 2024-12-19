#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History: Dec. 2024 - Xudong Hao - creation

import random
from avocado.utils import cpu

from virttest.cpu import check_if_vm_vcpu_match


def run(test, params, env):
    """
    pCPU offline/online test:
    1) Launch a guest with many CPU.
    2) Offline 3 random online pCPU.
    3) Check guest's status
    4) Online the offlined pCPU again.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    vm = env.get_vm(params["main_vm"])
    vcpus = params["smp"]
    vm.verify_alive()
    timeout = params.get_numeric("login_timeout", 240)
    session = vm.wait_for_login(timeout=timeout)

    host_cpu_list = cpu.online_list()
    processor_list = random.sample(host_cpu_list, 3)
    for processor in processor_list:
        cpu.offline(processor)
    test.log.info("CPUs {} have been offline.".format(processor_list))
    vm.verify_dmesg()
    if not check_if_vm_vcpu_match(vcpus, vm):
        test.fail("vCPU quantity on guest mismatch after offline")

    for processor in processor_list:
        cpu.online(processor)
    test.log.info("CPUs {} have been online.".format(processor_list))
    vm.verify_dmesg()
    session.close()
