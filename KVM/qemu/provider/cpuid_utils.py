#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

"""Shared helpers for compiling and running cpuid check tools."""

from avocado.core import exceptions
from avocado.utils import process

from virttest import utils_package


def prepare_cpuid(test, params, src_dir, vm=None, session=None):
    """
    Compile the cpuid test tool in host or guest.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param src_dir: Test tool source code directory of absolute path
    :param vm: The VM object
    :param session: Guest session
    :return: The executable test tool with absolute path
    """
    source_file = params["source_file"]
    exec_file = params["exec_file"]
    src_cpuid = src_dir + "/" + source_file
    if session:
        test_dir = params["test_dir"]
        vm.copy_files_to(src_cpuid, test_dir)
    else:
        test_dir = src_dir

    if not utils_package.package_install("gcc", session):
        test.cancel("Failed to install package gcc.")

    compile_cmd = "cd %s && gcc %s -o %s" % (test_dir, source_file, exec_file)
    if session:
        status = session.cmd_status(compile_cmd)
    else:
        status = process.system(compile_cmd, shell=True)
    if status:
        raise exceptions.TestError("Test suite compile failed.")

    return test_dir + "/" + exec_file


def check_cpuid(cpuid_arg, exec_bin, session=None):
    """
    Run cpuid test in host or guest.

    :param cpuid_arg: The feature to be checked
    :param exec_bin: The executable binary tool with absolute path
    :param session: Guest session
    :return: Command exit status
    """
    check_cmd = "%s %s" % (exec_bin, cpuid_arg)
    func = process.getstatusoutput
    if session:
        func = session.cmd_status_output
    status, output = func(check_cmd)

    return status
