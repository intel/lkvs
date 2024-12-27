#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History:  Dec. 2024 - Xudong Hao - creation

import re

from avocado.utils import process, cpu
from virttest import env_process


def run(test, params, env):
    """
    TDX module test:
    1. Check host TDX capability
    2. Check TDX module load status

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    if cpu.get_cpu_vendor_name() != 'intel':
        test.cancel("This test is supposed to run on Intel host")

    rdmsr_cmd = params["rdmsr_cmd"]
    if process.getoutput(rdmsr_cmd) != "1":
        test.fail("Platform does not support TDX-SEAM")

    read_cmd = params["read_cmd"]
    tdx_value = process.getoutput(read_cmd % "tdx")
    if tdx_value != "Y":
        test.fail("TDX is not supported in KVM")

    module_pattern = params["tdx_module_pattern"]
    negative_pattern = params["tdx_negative_pattern"]
    dmesg = process.system_output("dmesg")
    module_str = re.findall(r'%s' % module_pattern, dmesg.decode('utf-8'))
    negative_str = re.findall(r'%s' % negative_pattern, dmesg.decode('utf-8'))
    if negative_str or not module_str:
        test.fail("TDX module isn't initialized")
