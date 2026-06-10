#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

import os

from provider import dmesg_router  # pylint: disable=unused-import
from avocado.utils import process
from virttest import data_dir, env_process, error_context, utils_package


@error_context.context_aware
def run(test, params, env):
    """Validate CPUID leaf 0x1F topology information.

    The host variant runs the checker directly. Guest variants boot the
    configured CPU model and topology, then run the checker inside the guest.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """
    host_only = params.get_boolean("host_only")
    source_file = params.get("source_file", "cpuid_1f_check.c")
    exec_file = params.get("exec_file", "cpuid_1f_check")
    deps_dir = os.path.join(data_dir.get_deps_dir("cpuid_1f"))
    src_path = os.path.join(deps_dir, source_file)
    test_dir = params.get("test_dir", "/home")

    def _compile_and_run_host():
        error_context.context("Compile and run CPUID 0x1F check on host", test.log.info)
        host_bin = os.path.join(deps_dir, exec_file)
        compile_cmd = "gcc -o %s %s" % (host_bin, src_path)
        result = process.run(compile_cmd, shell=True)
        if result.exit_status:
            test.error("Failed to compile %s: %s" % (source_file, result.stderr_text))
        try:
            result = process.run(host_bin, shell=True)
            if result.exit_status:
                test.fail("Host %s failed: %s" % (exec_file, result.stdout_text))
            test.log.info(
                "Host CPUID 0x1F check passed: %s", result.stdout_text.strip()
            )
        finally:
            process.system("rm -f %s" % host_bin, shell=True, ignore_status=True)

    def _compile_and_run_guest():
        error_context.context(
            "Boot VM and run CPUID 0x1F check in guest", test.log.info
        )
        params["start_vm"] = "yes"
        vm_name = params["main_vm"]
        env_process.preprocess_vm(test, params, env, vm_name)
        vm = env.get_vm(vm_name)
        vm.verify_alive()
        session = vm.wait_for_login()
        try:
            if not utils_package.package_install("gcc", session):
                test.cancel("Failed to install gcc in guest.")
            vm.copy_files_to(src_path, test_dir)
            guest_src = os.path.join(test_dir, source_file)
            guest_bin = os.path.join(test_dir, exec_file)
            compile_cmd = "gcc -o %s %s" % (guest_bin, guest_src)
            error_context.context("Compile %s in guest" % source_file, test.log.info)
            status, output = session.cmd_status_output(compile_cmd, timeout=60)
            if status:
                test.error("Failed to compile %s in guest: %s" % (source_file, output))
            error_context.context("Execute %s in guest" % exec_file, test.log.info)
            status, output = session.cmd_status_output(guest_bin, timeout=60)
            if status:
                test.fail("Guest CPUID 0x1F check failed: %s" % output)
            test.log.info("Guest CPUID 0x1F check passed: %s", output.strip())
        finally:
            session.cmd(
                "rm -f %s/%s %s/%s" % (test_dir, source_file, test_dir, exec_file),
                ignore_all_errors=True,
            )
            session.close()
            vm.destroy(gracefully=False)

    if host_only:
        _compile_and_run_host()
    else:
        _compile_and_run_guest()
