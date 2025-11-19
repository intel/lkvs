#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2025 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History: Nov. 2025 - Xudong Hao - creation

from virttest import cpu

import logging
LOG_JOB = logging.getLogger('avocado.test')


intel_cpu_family_mapping = {
    "Icelake-Server": (6, 106),
    "SapphireRapids": (6, 143),
    "EmeraldRapids": (6, 207),
    "GraniteRapids": (6, 173),
    "SierraForest": (6, 175),
    "ClearwaterForest": (6, 221),
    "DiamondRapids": (19, 1)
}


def get_host_platform():
    """
    Get Intel host platform from lscpu family id and model id
    """
    cpu_info = cpu.get_cpu_info()
    family_id = int(cpu_info["CPU family"])
    model_id = int(cpu_info["Model"])
    family_model = (family_id, model_id)

    platform = None
    for key, values in intel_cpu_family_mapping.items():
        if family_model == values:
            platform = key
            break
    LOG_JOB.info("Current platform is: %s", platform)
    return platform


def get_matched_cpu_model(params):
    """
    Get similar QEMU CPU model with host.

    1) Get host CPU generation
    2) Verify if host CPU model is in the list of supported qemu cpu models
    3) If so, return the latest version of CPU model
    4) If not, return the default cpu model set in params.
    """
    host_platform = get_host_platform()
    if host_platform is None:
        return None
    # QEMU doesn't emulate EmeraldRapids, instead of SapphireRapids
    if host_platform == "EmeraldRapids":
        host_platform = "SapphireRapids"
    qemu_binary = params.get("qemu_binary")
    qemu_cpu_models = cpu.get_qemu_cpu_models(qemu_binary)
    for qemu_cpu_model in reversed(qemu_cpu_models):
        if host_platform in qemu_cpu_model:
            return qemu_cpu_model
    return params.get("default_cpu_model", None)
