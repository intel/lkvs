#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

from provider import dmesg_router  # pylint: disable=unused-import
from provider.cpuid_utils import check_cpuid, prepare_cpuid
from provider.test_utils import get_baremetal_dir
from virttest import env_process, error_context


@error_context.context_aware
def run(test, params, env):
    """
    Verify NMI source CPUID bit is hidden when -nmi-source is set.

    NMI Source depends on FRED. The test first confirms FRED CPUID is
    present in the guest, then verifies that the NMI Source bit is NOT
    visible when QEMU disables it via -nmi-source.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """
    fred_cpuid_arg = params["fred_cpuid"]
    nmis_cpuid_arg = params["cpuid"]
    test_dir = params["test_dir"]
    bm_dir = get_baremetal_dir(params)
    src_dir = "%s/tools/cpuid_check" % bm_dir

    error_context.context("Boot VM with -nmi-source disabled", test.log.info)
    params["start_vm"] = "yes"
    vm_name = params["main_vm"]
    env_process.preprocess_vm(test, params, env, vm_name)
    vm = env.get_vm(vm_name)
    vm.verify_alive()
    session = vm.wait_for_login()
    try:
        exec_bin = prepare_cpuid(test, params, src_dir, vm, session)

        error_context.context("Check FRED CPUID as prerequisite", test.log.info)
        if check_cpuid(fred_cpuid_arg, exec_bin, session):
            test.cancel("FRED CPUID not set, NMI source depends on FRED")
        s, output = session.cmd_status_output("grep -w fred /proc/cpuinfo")
        if s:
            test.cancel("FRED cpu flag not found in guest /proc/cpuinfo")

        error_context.context(
            "Verify NMI source CPUID bit is NOT set in guest", test.log.info
        )
        if not check_cpuid(nmis_cpuid_arg, exec_bin, session):
            test.fail("NMI source CPUID bit should NOT be set with -nmi-source")
        test.log.info("NMI source CPUID correctly hidden with -nmi-source")
    finally:
        session.cmd("rm %s/cpuid* -rf" % test_dir, ignore_all_errors=True)
        session.close()
        vm.destroy(gracefully=False)
