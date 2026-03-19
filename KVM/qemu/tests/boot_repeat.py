#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

from provider import dmesg_router  # pylint: disable=unused-import

from virttest import error_context


@error_context.context_aware
def run(test, params, env):
    """
        Boot all configured VMs, verify guest login, destroy them, and repeat.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """

    timeout = int(params.get_numeric("login_timeout", 240))
    iterations = int(params.get_numeric("iterations"))
    vm_names = params.objects("vms")
    if not vm_names:
        test.cancel("No VMs configured for boot_repeat")

    vms = [env.get_vm(vm_name) for vm_name in vm_names]
    for iteration in range(1, iterations + 1):
        started_vms = []
        error_context.context(
            "Boot repeat iteration %s/%s" % (iteration, iterations),
            test.log.info,
        )
        try:
            for vm in vms:
                vm.create()
                started_vms.append(vm)
            for vm in started_vms:
                vm.verify_alive()
                session = vm.wait_for_login(timeout=timeout)
                session.close()
        finally:
            for vm in started_vms:
                vm.destroy(gracefully=False)
