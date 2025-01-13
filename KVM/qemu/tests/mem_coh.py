#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2025 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History: Jan. 2025 - Xudong Hao - creation

import os

from virttest import data_dir, utils_package, utils_misc


def compile_mem_coh(test, vm, session):
    """
    Copy and compile mem_coh on guest

    :param test: QEMU test object
    :param vm: Object qemu_vm.VM
    :param session: vm session
    :return: Path to binary mem_coh or None if compile failed
    """
    mem_coh_dir = "/home/"
    mem_coh_bin = "mem_coh"
    mem_coh_c = "mem_coh.c"
    src_file = os.path.join(data_dir.get_deps_dir("mem_coh"), mem_coh_c)
    exec_bin = os.path.join(mem_coh_dir, mem_coh_bin)
    rm_cmd = "rm -rf %s*" % exec_bin
    session.cmd(rm_cmd)
    vm.copy_files_to(src_file, mem_coh_dir)

    if not utils_package.package_install("gcc", session):
        test.cancel("Failed to install package gcc.")
    compile_cmd = "cd %s && gcc -O2 -lpthread -DCONFIG_SMP -o %s %s" % (mem_coh_dir, mem_coh_bin, mem_coh_c)
    guest_status = session.cmd_status(compile_cmd)
    if guest_status:
        session.cmd_output_safe(rm_cmd)
        session.close()
        test.fail("Compile mem_coh failed")
    return exec_bin


def run(test, params, env):
    """
    Memory coherency function test

    1. Boot guest with multiple vCPUs
    2. Download and compile mem_coh on guest
    3. Run memory coherency test inside guest
    4. Shutdown guest

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """

    def clean(tool_bin):
        """Clean the environment"""
        cmd_rm = "rm -rf %s" % tool_bin
        cmd_rm += "; rm -rf %s" % tmp_file
        session.cmd_output_safe(cmd_rm)
        session.close()

    vm = env.get_vm(params["main_vm"])
    tmp_file = "/tmp/smp-test-flag1_%s" % utils_misc.generate_random_string(6)
    vm.verify_alive()
    session = vm.wait_for_login()

    tool_bin = compile_mem_coh(test, vm, session)
    cmd_generate = "dd if=/dev/zero of=%s bs=1M count=10 && %s %s" % (tmp_file, tool_bin, tmp_file)
    chk_status = session.cmd_status(cmd_generate)
    if chk_status:
        clean(tool_bin)
        test.fail("Run mem_coh in guest with fail result")
    clean(tool_bin)
