#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

import os

from virttest import data_dir, env_process, error_context, utils_package
from virttest.utils_sys import check_dmesg_output

from provider import dmesg_router  # pylint: disable=unused-import
from provider.test_utils import get_baremetal_dir


def _prepare_guest_tdx_compliance_tree(test, params, vm, session, caselist_header):
    """Copy tdx-compliance sources and case header into guest working directory.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param vm: VM object used to copy files into guest
    :param session: Guest session object
    :param caselist_header: CPUID case header file name to copy
    :return: Guest working directory path for tdx-compliance
    """
    guest_dir = params["guest_test_dir"]
    session.cmd("rm -rf %s && mkdir -p %s" % (guest_dir, guest_dir))

    bm_dir = get_baremetal_dir(params)
    src_subdir = params.get("tdx_compliance_src_subdir", "tdx-compliance")
    src_dir = os.path.join(bm_dir, src_subdir)

    source_files = [
        "Makefile",
        "tdx-compliance-main.c",
        "tdx-compliance.h",
        "tdx-compliance-msr.h",
        "tdx-compliance-cr.h",
        "tdcall.S",
        "tdxcall.S",
    ]
    for source_file in source_files:
        vm.copy_files_to(os.path.join(src_dir, source_file), guest_dir)

    deps_dir = data_dir.get_deps_dir(params["deps_subdir"])
    vm.copy_files_to(
        os.path.join(deps_dir, caselist_header),
        "%s/tdx-compliance-cpuid.h" % guest_dir,
    )

    return guest_dir


def _run_tdx_cpuid_compliance(test, session, guest_dir, cpu_pin=None, verify_ve=False):
    """Build and execute one cpuid compliance run in guest and check results.

    :param test: QEMU test object
    :param session: Guest session object
    :param guest_dir: Guest directory containing tdx-compliance sources
    :param cpu_pin: Optional host CPU index for numactl pinning
    :param verify_ve: Whether to verify VE trigger count in guest dmesg
    """
    ret = 0
    try:
        status = session.cmd_status("cd %s && make clean && make" % guest_dir, timeout=120)
        if status != 0:
            make_output = session.cmd_output("cd %s && make 2>&1 | tail -50" % guest_dir)
            test.fail(
                "Failed to build tdx-compliance in guest; please check whether kernel-devel is installed. Build output:\n%s"
                % make_output
            )

        try:
            session.cmd("dmesg -C")
        except Exception:
            pass  # dmesg clear may fail in some environments

        status = session.cmd_status("cd %s && insmod tdx-compliance.ko" % guest_dir)
        if status != 0:
            test.fail("Failed to load tdx-compliance.ko")

        status = session.cmd_status("echo kretprobe > /sys/kernel/debug/tdx/tdx-tests")
        if status != 0:
            test.fail("Failed to register kretprobe")

        if cpu_pin is not None:
            if not utils_package.package_install("numactl", session):
                test.cancel("Failed to install numactl for cpu pinned cpuid case")
            trigger_cmd = (
                "numactl -C %s sh -c \"echo cpuid > /sys/kernel/debug/tdx/tdx-tests\""
                % cpu_pin
            )
        else:
            trigger_cmd = "echo cpuid > /sys/kernel/debug/tdx/tdx-tests"

        status = session.cmd_status(trigger_cmd)
        if status != 0:
            test.fail("Failed to trigger cpuid compliance run")

        result_output = session.cmd_output("cat /sys/kernel/debug/tdx/tdx-tests")
        test.log.debug("tdx cpuid compliance raw output:\n%s", result_output)
        if "FAIL:0" not in result_output:
            test.fail("tdx compliance cpuid test failed:\n%s" % result_output)
        test.log.info("tdx compliance cpuid test passed")

        if verify_ve:
            dmesg_output = session.cmd_output("dmesg")
            start_marker = "Testing CPUID start"
            end_marker = "CPUID test end"
            start_index = dmesg_output.find(start_marker)
            end_index = dmesg_output.find(end_marker)
            if start_index != -1 and end_index != -1 and end_index > start_index:
                dmesg_scope = dmesg_output[start_index:end_index]
            else:
                dmesg_scope = dmesg_output
            ve_trigger_count = dmesg_scope.count("VE trigger")
            if ve_trigger_count != 1:
                test.fail("Expected 1 VE trigger, got %s" % ve_trigger_count)
    finally:
        try:
            session.cmd_status("echo unregister > /sys/kernel/debug/tdx/tdx-tests")
        except Exception:
            pass
        try:
            session.cmd_status("rmmod tdx_compliance")
        except Exception:
            pass


@error_context.context_aware
def run(test, params, env):
    """TDX VE reduction cpuid and feature matrix test cases.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """
    case_action = params["case_action"]
    timeout = params.get_numeric("login_timeout", 240)
    vm_name = params["main_vm"]

    session = None
    vm = None
    try:
        params["start_vm"] = "yes"
        env_process.preprocess_vm(test, params, env, vm_name)
        vm = env.get_vm(vm_name)
        vm.verify_alive()
        session = vm.wait_for_login(timeout=timeout)

        error_context.context("Install guest build prerequisites", test.log.info)
        for pkg in ["gcc", "make"]:
            if not utils_package.package_install(pkg, session):
                test.cancel("Failed to install %s in guest" % pkg)

        if case_action == "ve_check":
            error_context.context("Check guest dmesg for REDUCE_VE marker", test.log.info)
            if not check_dmesg_output("REDUCE_VE", session=session):
                test.fail("#VE Reduction is not enabled in TD guest")
            test.log.info("tdx VE reduction check passed")
            return

        if case_action == "compliance":
            caselist = params["caselist"]
            guest_dir = _prepare_guest_tdx_compliance_tree(test, params, vm, session, caselist)
            cpu_pin = params.get("cpu_pin")
            error_context.context("Run tdx cpuid compliance with %s" % caselist, test.log.info)
            _run_tdx_cpuid_compliance(test, session, guest_dir, cpu_pin=cpu_pin, verify_ve=False)
            return

        if case_action == "compliance_ve_series":
            caselists = params.objects("ve_case_headers")
            cpu_pin = params.get("cpu_pin")
            for caselist in caselists:
                guest_dir = _prepare_guest_tdx_compliance_tree(test, params, vm, session, caselist)
                error_context.context("Run VE compliance caselist %s" % caselist, test.log.info)
                _run_tdx_cpuid_compliance(test, session, guest_dir, cpu_pin=cpu_pin, verify_ve=True)
            return

        test.error("Unsupported case_action: %s" % case_action)
    finally:
        if session:
            session.close()
        if vm and vm.is_alive():
            vm.destroy(gracefully=False)
