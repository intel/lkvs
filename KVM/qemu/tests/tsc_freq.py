#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History:  June. 2024 - Xudong Hao - creation

from avocado.utils import process

from virttest import error_context, env_process
from virttest.utils_misc import verify_dmesg
from virttest import utils_package


def get_tsc_freq(params, test, session=None):
    """
    Check tsc frequency on host or guest.(only for Linux now)
    :param params: Dictionary with the test parameters
    :param test: QEMU test object
    :param session: guest session
    """
    cpuid_pkg = params.get("cpuid_pkg")
    # Set up guest environment
    if not utils_package.package_install(cpuid_pkg, session):
        test.cancel("Failed to install package %s." % cpuid_pkg)

    check_cpuid_entry_cmd = params.get("cpuid_entry_cmd")
    func = process.getoutput
    if session:
        func = session.cmd_output
    output = func(check_cpuid_entry_cmd)
    eax_value = output.splitlines()[-1].split()[2].split('0x')[-1]
    ebx_value = output.splitlines()[-1].split()[3].split('0x')[-1]
    ecx_value = output.splitlines()[-1].split()[4].split('0x')[-1]
    eax_value = int(eax_value, 16)
    ebx_value = int(ebx_value, 16)
    ecx_value = int(ecx_value, 16)
    tsc_freq = ecx_value * ebx_value / eax_value

    return tsc_freq


@error_context.context_aware
def run(test, params, env):
    """
    TSC frequency test:
    1. Boot VM
    2. Check if TSC frequency in guest is expected
    3. Destroy VM

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    error_context.context("Start tsc frequency test", test.log.info)
    timeout = params.get_numeric("login_timeout", 240)

    vm_name = params['main_vm']
    env_process.preprocess_vm(test, params, env, vm_name)
    vm = env.get_vm(vm_name)
    vm.create()
    vm.verify_alive()
    session = vm.wait_for_login(timeout=timeout)
    try:
        verify_dmesg()

        if params.get("cpu_model_flags"):
            cpu_model_tsc_freq = params.get("cpu_model_flags")
            qemu_tsc_freq = cpu_model_tsc_freq.split("=")[-1]
            expect_tsc_freq = int(qemu_tsc_freq)
        else:
            error_context.context("Get TSC frequency from host", test.log.info)
            host_tsc_freq = get_tsc_freq(params, test)
            expect_tsc_freq = host_tsc_freq

        error_context.context("Get TSC frequency from VM", test.log.info)
        vm_tsc_freq = get_tsc_freq(params, test, session)
        if vm_tsc_freq != expect_tsc_freq:
            test.fail("TSC value in guest is not as expected")
    finally:
        session.close()
    vm.destroy()
