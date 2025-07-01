#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2025 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History:  June. 2025 - Xudong Hao - creation

from virttest import cpu, env_process, error_context


@error_context.context_aware
def run(test, params, env):
    """
    Get kernel src code from kernel.org and run protection key tests in VM.

    1) Download Linux kernel source if no prepared execuable protection_keys
    2) Checkout the correct code version and compile protection_keys.c
    3) Run executable file 'protection_keys'
    4) Check results

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
    session = vm.wait_for_login()

    guest_dir = params["guest_dir"]
    timeout = params.get_numeric("timeout")
    if params["tool_pre_compile"] == "yes":
        run_cmd = params["tool_pre_path"]
    else:
        kernel_v = session.cmd_output("uname -r").strip().rsplit(".", 1)[0]
        mkdir_cmd = session.cmd("mkdir -p %s" % guest_dir)
        download_src_cmd = "cd %s && git clone %s" % (guest_dir, params["kernel_repo"])
        src_version_cmd = "cd %s && git checkout %s" % (guest_dir + "linux", "v" + kernel_v)
        test_dir = guest_dir + "linux" + params["test_dir"]
        compile_cmd = "cd %s && " % test_dir + params["compile_cmd"]
        run_cmd = "cd %s && " % test_dir + params["run_cmd"]

    try:
        if params["tool_pre_compile"] != "yes":
            session.cmd(mkdir_cmd)  # pylint: disable=E0606
            error_context.context("Get kernel source code", test.log.info)
            session.cmd(download_src_cmd, timeout=1200)  # pylint: disable=E0606
            session.cmd(src_version_cmd, timeout)  # pylint: disable=E0606
            session.cmd(compile_cmd, timeout)  # pylint: disable=E0606
        s, output = session.cmd_status_output(run_cmd, safe=True)
        if "done (all tests OK)" not in output:
            test.fail("Protection key test runs failed.")

        vm.verify_kernel_crash()
    finally:
        if params["tool_pre_compile"] == "yes":
            session.cmd("rm -rf %s" % guest_dir)
        session.close()
