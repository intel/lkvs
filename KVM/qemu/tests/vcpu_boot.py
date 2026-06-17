#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

from avocado.utils import cpu

from virttest import env_process, error_context

from provider import dmesg_router  # pylint: disable=unused-import


@error_context.context_aware
def run(test, params, env):
    """
    Boot a guest with vCPU count exceeding the host online CPU count.

    1. Get host online CPU count
    2. Set guest vCPU count to host_count + 1
    3. Boot guest with the computed vCPU count
    4. Verify guest reports expected vCPU count

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """
    vm_name = params["main_vm"]

    error_context.context("Get host online CPU count", test.log.info)
    host_cpu_count = cpu.online_count()
    expected_vcpu = host_cpu_count + 1

    error_context.context(
        "Boot VM with %d vCPUs (host has %d)" % (expected_vcpu, host_cpu_count),
        test.log.info,
    )
    params["start_vm"] = "yes"
    params["smp"] = str(expected_vcpu)
    env_process.preprocess_vm(test, params, env, vm_name)
    vm = env.get_vm(vm_name)
    vm.verify_alive()

    timeout = params.get_numeric("login_timeout", 240)
    session = vm.wait_for_login(timeout=timeout)
    try:
        error_context.context(
            "Verify guest vCPU count is %d" % expected_vcpu, test.log.info
        )
        actual_vcpu = vm.get_cpu_count()
        if actual_vcpu != expected_vcpu:
            test.fail(
                "Guest vCPU count mismatch: expected %d, got %d"
                % (expected_vcpu, actual_vcpu)
            )
    finally:
        session.close()
