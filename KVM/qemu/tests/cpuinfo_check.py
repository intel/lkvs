#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2025 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History: Jan. 2025 - Xudong Hao - creation

import os

from virttest import data_dir, utils_package


def compile_cpuinfo_chk(test, vm, session):
    """
    Copy and compile cpuinfo_chk on guest

    :param test: QEMU test object
    :param vm: Object qemu_vm.VM
    :param session: vm session
    :return: Path to binary cpuinfo_chk or None if compile failed
    """
    cpuinfo_chk_dir = "/home/"
    cpuinfo_chk_bin = "cpuinfo_chk"
    cpuinfo_chk_c = "cpuinfo_chk.c"
    src_file = os.path.join(data_dir.get_deps_dir("cpuinfo_chk"), cpuinfo_chk_c)
    exec_bin = os.path.join(cpuinfo_chk_dir, cpuinfo_chk_bin)
    rm_cmd = "rm -rf %s*" % exec_bin
    session.cmd(rm_cmd)
    vm.copy_files_to(src_file, cpuinfo_chk_dir)

    if not utils_package.package_install("gcc", session):
        test.cancel("Failed to install package gcc.")
    compile_cmd = "cd %s && gcc -o %s %s" % (cpuinfo_chk_dir, cpuinfo_chk_bin, cpuinfo_chk_c)
    guest_status = session.cmd_status(compile_cmd)
    if guest_status:
        session.cmd_output_safe(rm_cmd)
        session.close()
        test.fail("Compile cpuinfo_chk failed")
    return exec_bin


def run(test, params, env):
    """
    cpuinfo check function test, each vcpu info (/proc/cpuinfo)
    in guest should be the same.

    1. Boot guest with multiple vCPUs
    2. Download and compile cpuinfo_chk on guest
    3. Run cpuinfo_chk inside guest
    4. Shutdown guest

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """

    def clean(tool_bin):
        """Clean the environment"""
        cmd_rm = "rm -rf %s" % tool_bin
        session.cmd_output_safe(cmd_rm)
        session.close()

    vm = env.get_vm(params["main_vm"])
    vm.verify_alive()
    session = vm.wait_for_login()

    tool_bin = compile_cpuinfo_chk(test, vm, session)
    chk_status = session.cmd_status(tool_bin)
    if chk_status:
        clean(tool_bin)
        test.fail("Run cpuinfo_chk in guest with fail result")
    clean(tool_bin)
