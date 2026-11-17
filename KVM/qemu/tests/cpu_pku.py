#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2025 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History:  June. 2025 - Xudong Hao - creation

import os
import posixpath
import shlex

from provider import dmesg_router  # pylint: disable=unused-import
from virttest import cpu, data_dir, env_process, error_context


def _get_deps_dir(deps_subdir):
    """Resolve a deps directory relative to this test provider."""
    return data_dir.get_deps_dir(deps_subdir)


def _copy_sources(vm, session, deps_dir, guest_dir):
    """Copy the vendored Linux PKU selftest source tree into the guest."""
    quoted_guest_dir = shlex.quote(guest_dir)
    session.cmd("rm -rf %s && mkdir -p %s" %
                (quoted_guest_dir, quoted_guest_dir))
    for root, dirs, files in os.walk(deps_dir):
        dirs.sort()
        files.sort()
        relative_dir = os.path.relpath(root, deps_dir)
        guest_subdir = guest_dir
        if relative_dir != ".":
            guest_subdir = posixpath.join(guest_dir, relative_dir)
            session.cmd("mkdir -p %s" % shlex.quote(guest_subdir))
        for filename in files:
            if filename == "README.md":
                continue
            vm.copy_files_to(
                os.path.join(root, filename),
                posixpath.join(guest_subdir, filename),
            )


@error_context.context_aware
def run(test, params, env):
    """
    Build and run the vendored Linux protection key selftest in the VM.

    1) Copy the source and helper files from the LKVS deps directory
    2) Compile the protection_keys executable in the guest
    3) Run the executable and check its results

    :param test:   QEMU test object.
    :param params: Dictionary with the test parameters.
    :param env:    Dictionary with test environment.
    """
    unsupported_models = params.get("unsupported_models", "")
    cpu_model = params.get("cpu_model", cpu.get_qemu_best_cpu_model(params))
    if cpu_model in unsupported_models.split():
        test.cancel("'%s' doesn't support this test case" % cpu_model)

    params["start_vm"] = "yes"
    vm_name = params["main_vm"]
    env_process.preprocess_vm(test, params, env, vm_name)

    vm = env.get_vm(vm_name)
    error_context.context("Try to log into guest", test.log.info)
    session = vm.wait_for_login(timeout=params.get_numeric("login_timeout"))

    guest_dir = params["guest_dir"].rstrip("/")
    timeout = params.get_numeric("timeout")
    deps_dir = _get_deps_dir(params["deps_subdir"])
    compile_cmd = "cd %s && %s" % (
        shlex.quote(guest_dir), params["compile_cmd"]
    )
    run_cmd = "cd %s && %s" % (
        shlex.quote(guest_dir), params["run_cmd"]
    )

    try:
        if session.cmd_status("command -v gcc >/dev/null 2>&1"):
            test.cancel("gcc is required to build the vendored PKU selftest")
        error_context.context("Copy and compile the PKU selftest", test.log.info)
        _copy_sources(vm, session, deps_dir, guest_dir)
        session.cmd(compile_cmd, timeout)
        s, output = session.cmd_status_output(run_cmd, safe=True)
        if s == 0 and "running PKEY tests for unsupported CPU/OS" in output:
            test.cancel("Guest CPU or kernel does not support protection keys")
        success_markers = ("done (all tests OK)", "all tests OK",
                           "Totals: pass:")
        summary_ok = "fail:0" in output and "Totals:" in output
        if s != 0 or (not any(marker in output for marker in success_markers)
                      and not summary_ok):
            test.fail("Protection key test runs failed. status=%s\n%s" %
                      (s, output))

        vm.verify_kernel_crash()
    finally:
        session.cmd("rm -rf %s" % shlex.quote(guest_dir),
                    ignore_all_errors=True)
        session.close()
