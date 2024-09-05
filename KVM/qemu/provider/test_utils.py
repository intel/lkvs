#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History: Sept. 2024 - Xudong Hao - creation

import os
from virttest import data_dir, asset


def get_baremetal_dir(params):
    """
    Get the test provider's BM absolute path.
    :param params: Dictionary with the test parameters
    """
    provider = params["provider"]
    provider_info = asset.get_test_provider_info(provider)
    if provider_info["uri"].startswith("file://"):
        provider_dir = provider_info["uri"][7:]
    else:
        provider_dir = data_dir.get_test_provider_dir(provider)
    baremetal_dir = os.path.join(provider_dir, "BM")

    return baremetal_dir
