#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History:  July. 2024 - Xudong Hao - creation

from provider import dmesg_router  # pylint: disable=unused-import
from avocado.utils import process, cpu
from virttest import env_process
from virttest import error_context
from virttest import utils_misc
from virttest import utils_package


def stress_ng_test(test, vm_cpu, vm_mem, mem_size, time, session=None):
    if not utils_package.package_install("stress-ng", session):
        test.cancel("Installation failed. Please install stress-ng manually.")
    session.cmd(
        f"stress-ng --cpu {vm_cpu} --io 1 --vm {vm_mem} --vm-bytes {mem_size} --hdd 1 --hdd-bytes 3G --timeout {time} > /tmp/stress_ng.log",
        ignore_all_errors=True
    )
    return

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
    is_nxhp = params.get_boolean("is_nxhp")
    if is_nxhp:
        is_high_mem_nxhp = params.get_boolean("is_high_mem_nxhp")
        is_low_mem_nxhp = params.get_boolean("is_low_mem_nxhp")
        nxhp_conf = params.get("nxhp_conf")
        with open(nxhp_conf, "r") as f:
            nxhp_value = f.read(1)
        with open(nxhp_conf, "w") as f:
            f.write("force")
        with open(nxhp_conf, "r") as f:
            nxhp_value_new = f.read(1)
        if nxhp_value_new != "Y":
            test.fail("Failed to enable NX huge page")
        if is_high_mem_nxhp:
            stress_ng_test(test, 2, 2, "16G", "60s", session)
        if is_low_mem_nxhp:
            stress_ng_test(test, 2, 2, "1G", "60s", session)
        vm.copy_files_from("/tmp/stress_ng.log", "/tmp/stress_ng.log")
        session.cmd("rm -f /tmp/stress_ng.log")
        with open("/tmp/stress_ng.log", "r") as f:
            stress_ng_status = f.readlines()[-1].split()[3]
        if stress_ng_status != "successful":
            test.fail("Stress-ng test failed, please check debug.log for details")
        process.system("rm -f /tmp/stress_ng.log")
        with open(nxhp_conf, "w") as f:
            f.write(nxhp_value)
    session.close()
