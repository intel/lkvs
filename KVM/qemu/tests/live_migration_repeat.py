#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

import time

from provider import dmesg_router  # pylint: disable=unused-import

from virttest import error_context


@error_context.context_aware
def run(test, params, env):
    """
    Live migration repeat test:
    1) Boot a guest VM.
    2) Perform local live migration N times in a loop.
    3) After each migration, log in to verify guest is alive.
    4) Destroy VM.

    :param test: QEMU test object.
    :param params: Dictionary with test parameters.
    :param env: Dictionary with the test environment.
    """
    vm = env.get_vm(params["main_vm"])
    vm.verify_alive()

    login_timeout = int(params.get("login_timeout", 360))
    migration_iterations = int(params.get("migration_iterations", 1))
    iteration_sleep_time = int(params.get("iteration_sleep_time", 5))
    mig_timeout = float(params.get("mig_timeout", 300))

    error_context.context("Verify guest is bootable before migration", test.log.info)
    session = vm.wait_for_login(timeout=login_timeout)
    session.close()

    try:
        for i in range(1, migration_iterations + 1):
            error_context.context(
                "Live migration iteration %d of %d" % (i, migration_iterations),
                test.log.info,
            )
            time.sleep(iteration_sleep_time)
            vm.migrate(timeout=mig_timeout)

            error_context.context(
                "Verify guest alive after migration %d" % i, test.log.info
            )
            session = vm.wait_for_login(timeout=30)
            session.close()
            test.log.info("Migration iteration %d PASS", i)
    finally:
        vm.destroy(gracefully=False)
