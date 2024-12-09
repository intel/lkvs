#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History:  Jun. 2024 - Xudong Hao - creation
from avocado.utils import process

from virttest import env_process


def run(test, params, env):
    """
    Boot TD after disable ept or tdx:
    1) Disable ept or tdx
    2) Boot up TDVM
    3) TDVM can not be lanuch as expect

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """
    xfail = False
    if (params.get("xfail") is not None) and (params.get("xfail") == "yes"):
        xfail = True

    output = process.getoutput(params["check_status_cmd"])
    if output != params["expected_status"]:
        test.fail("Disable %s failed" % params["parameter_name"])

    params["start_vm"] = 'yes'
    has_error = False
    try:
        env_process.preprocess_vm(test, params, env, params["main_vm"])
    except:
        has_error = True
        if xfail is False:
            raise

    if (has_error is False) and (xfail is True):
        test.fail("Test was expected to fail, but it didn't")
