#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2025 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History: Feb. 2025 - Xudong Hao - creation

import os

from virttest import data_dir, utils_package, utils_misc


def compile_test_tool(test, params, vm, session):
    """
    Copy and compile test tool on guest

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param vm: Object qemu_vm.VM
    :param session: vm session
    :return: Path to test binary or None if compile failed
    """
    test_dir = "/home/"
    test_src = params["test_tool"]
    test_bin = test_src.split(".")[0]
    src_file = os.path.join(data_dir.get_deps_dir("smp"), test_src)
    exec_bin = os.path.join(test_dir, test_bin)
    rm_cmd = "rm -rf %s*" % exec_bin
    session.cmd(rm_cmd)
    vm.copy_files_to(src_file, test_dir)

    if not utils_package.package_install("gcc", session):
        test.cancel("Failed to install package gcc.")
    compile_cmd = "cd %s && gcc -O2 -lpthread -DCONFIG_SMP -o %s %s" % (test_dir, test_bin, test_src)
    guest_status = session.cmd_status(compile_cmd)
    if guest_status:
        session.cmd_output_safe(rm_cmd)
        session.close()
        test.fail("Compile test tool %s failed." % test_src)
    return exec_bin


def run(test, params, env):
    """
    SMP(Symmetrical Multi-Processing) function test

    1. Boot guest with multiple vCPUs
    2. Download and compile test tool on guest
    3. Run test inside guest
    4. Shutdown guest

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """

    def clean(tool_bin):
        """Clean the environment"""
        cmd_rm = "rm -rf %s" % tool_bin
        if test_tool == "mem_coh.c":
            cmd_rm += "; rm -rf %s" % tmp_file
        session.cmd_output_safe(cmd_rm)
        session.close()

    vm = env.get_vm(params["main_vm"])
    test_tool = params["test_tool"]
    if test_tool == "mem_coh.c":
        tmp_file = "/tmp/smp-test-flag1_%s" % utils_misc.generate_random_string(6)
    vm.verify_alive()
    session = vm.wait_for_login()

    tool_bin = compile_test_tool(test, params, vm, session)
    if test_tool == "mem_coh.c":
        cmd_generate = "dd if=/dev/zero of=%s bs=1M count=10 && %s %s" % (tmp_file, tool_bin, tmp_file)
    else:
        cmd_generate = tool_bin
    chk_status = session.cmd_status(cmd_generate)
    if chk_status:
        clean(tool_bin)
        test.fail("Run test %s in guest with fail result." % tool_bin)
    clean(tool_bin)
