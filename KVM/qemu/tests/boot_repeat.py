#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

import re

from provider import dmesg_router  # pylint: disable=unused-import

from virttest import env_process
from virttest import error_context
from virttest import utils_misc


def _boot_vms_and_verify(test, env, vm_names, timeout, params, started_vms, mem_size=None):
    """
    Helper function to boot VMs, verify and login, then destroy.

    :param test: Test object
    :param env: Environment object
    :param vm_names: List of VM names to boot
    :param timeout: Login timeout in seconds
    :param params: Test parameters dict
    :param started_vms: List to track created VMs for cleanup
    :param mem_size: Optional memory size in MB to set for VMs
    """
    try:
        for vm_name in vm_names:
            vm_params = params.object_params(vm_name)

            # Set memory size if specified
            if mem_size:
                vm_params["mem"] = mem_size

            # Preprocess VM to apply parameter changes
            env_process.preprocess_vm(test, vm_params, env, vm_name)

            vm = env.get_vm(vm_name)
            vm.create()
            started_vms.append(vm)
        for vm in started_vms:
            vm.verify_alive()
            session = vm.wait_for_login(timeout=timeout)
            session.close()
    finally:
        for vm in started_vms:
            vm.destroy(gracefully=False)


@error_context.context_aware
def run(test, params, env):
    """
    Boot all configured VMs, verify guest login, destroy them, and repeat.
    Supports two modes:
    1. memory_sizes_list: Boot VMs with each specified memory size
    2. iterations: Repeat boot/destroy cycle N times

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """

    timeout = int(params.get_numeric("login_timeout", 240))
    cycles = int(params.get_numeric("cycles", 1))
    vm_names = params.objects("vms")
    if not vm_names:
        test.cancel("No VMs configured for boot_repeat")

    # Check if memory_sizes_list is specified for per-iteration memory size testing
    memory_sizes_list = params.get("memory_sizes_list")
    if memory_sizes_list:
        # Parse memory sizes (e.g., "66900M 67000M")
        mem_size_list = []
        for size_str in memory_sizes_list.split():
            size_str = size_str.strip()
            if not size_str:
                continue

            # Extract numeric value, ignoring case and M/MB suffix
            match = re.match(r'(\d+)\s*[mM][bB]?', size_str)
            if not match:
                test.fail(f"Invalid memory size format: {size_str}")

            mem_value = int(match.group(1))
            mem_size_list.append(mem_value)

        # Get host available memory
        available_memory = int(utils_misc.get_usable_memory_size())

        # Check and perform boot test for each memory size
        for mem_idx, mem_size in enumerate(mem_size_list, 1):
            if mem_size > available_memory:
                test.fail(
                    "Host does not have enough memory. "
                    "Required: %dM, Available: %dM"
                    % (mem_size, available_memory)
                )

            error_context.context(
                "Boot with memory size %s/%s: %dM"
                % (mem_idx, len(mem_size_list), mem_size),
                test.log.info,
            )

            started_vms = []
            _boot_vms_and_verify(test, env, vm_names, timeout, params, started_vms, mem_size)
    else:
        # Original boot_repeat logic for iterations
        for iteration in range(1, cycles + 1):
            started_vms = []
            error_context.context(
                "Boot repeat iteration %s/%s" % (iteration, cycles),
                test.log.info,
            )
            _boot_vms_and_verify(test, env, vm_names, timeout, params, started_vms)
