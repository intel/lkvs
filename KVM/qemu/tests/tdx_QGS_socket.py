#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

# Author: Farrah Chen <farrah.chen@intel.com>
#
# History:  May. 2026 - Farrah Chen - creation

from provider import dmesg_router  # pylint: disable=unused-import
from virttest import error_context, env_process


@error_context.context_aware
def run(test, params, env):
    """
    TDX QGS socket test:
    1. Boot TD VM with quote-generation-socket (vsock) configured
    2. Verify TD guest boots successfully
    3. Validate TSM report interface inside guest

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    error_context.context("Boot TD VM with QGS socket", test.log.info)
    params["start_vm"] = "yes"
    env_process.preprocess_vm(test, params, env, params["main_vm"])
    vm = env.get_vm(params["main_vm"])
    vm.verify_alive()
    timeout = params.get_numeric("login_timeout", 240)
    session = vm.wait_for_login(timeout=timeout)

    error_context.context("Validate TSM report interface in guest", test.log.info)
    tsm_report_dir = params["tsm_report_dir"]
    session.cmd("mkdir -p %s" % tsm_report_dir)
    session.cmd("dd if=/dev/urandom bs=64 count=1 > %s/inblob" % tsm_report_dir)
    session.cmd("hexdump -C %s/outblob" % tsm_report_dir, timeout=30, ok_status=[0])
    test.log.info("TSM report interface verified successfully")

    session.close()
