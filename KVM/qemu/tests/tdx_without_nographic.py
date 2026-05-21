#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

# Author: Kai Zhang <kai.zhang@intel.com>
#
# History:  May. 2026 - Kai Zhang - creation

from provider import dmesg_router  # pylint: disable=unused-import
from virttest import error_context, env_process


@error_context.context_aware
def run(test, params, env):
    """
    Check whether TDX guest can boot up without nographic:
    1. Boot TDVM without -nographic parameter

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """

    test.log.warning("Before running this test, please comment the `display` parameter in tdx_temp.cfg")
    params["start_vm"] = "yes"
    env_process.preprocess_vm(test, params, env, params["main_vm"])
    vm = env.get_vm(params["main_vm"])
    vm.verify_alive()
