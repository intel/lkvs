#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

"""
Verify virtual interrupt injection while a KVM guest is running.

Boots a guest, records the kvm:kvm_inj_virq tracepoint on the host via
perf, then asserts that injected virtual interrupt count is greater than
zero.
"""

from provider import dmesg_router  # pylint: disable=unused-import
from avocado.utils import process
from virttest import env_process
from virttest import error_context


@error_context.context_aware
def run(test, params, env):
    """
    Check virtual interrupt delivery while a guest is running.

    Steps:
        1. Start perf record for kvm:kvm_inj_virq on the host.
        2. Boot a guest.
        3. Wait for perf to finish recording.
        4. Parse perf report and verify kvm_inj_virq count > 0.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """
    perf_event = params["perf_event"]
    perf_duration = params.get_numeric("perf_duration", 10)
    login_timeout = params.get_numeric("login_timeout", 240)

    params["start_vm"] = "yes"
    vm_name = params["main_vm"]

    error_context.context(
        "Start perf record for %s on host" % perf_event, test.log.info
    )
    perf_output = "/tmp/perf_virq.data"
    perf_cmd = "perf record -e '%s' -a -o %s -- sleep %d" % (
        perf_event,
        perf_output,
        perf_duration,
    )
    # Start perf in background; it will record for perf_duration seconds.
    perf_proc = process.SubProcess(perf_cmd, shell=True)
    perf_proc.start()

    try:
        error_context.context("Boot guest", test.log.info)
        env_process.preprocess_vm(test, params, env, vm_name)
        vm = env.get_vm(vm_name)
        vm.verify_alive()
        session = vm.wait_for_login(timeout=login_timeout)

        error_context.context("Wait for perf recording to complete", test.log.info)
        perf_proc.wait()

        error_context.context("Parse perf report for %s" % perf_event, test.log.info)
        report = process.run(
            "perf report -i %s --stdio 2>/dev/null | grep kvm_inj_virq" % perf_output,
            shell=True,
            ignore_status=True,
        )
        test.log.info("perf report output: %s", report.stdout_text.strip())

        # Extract the sample percentage or count line
        lines = [
            l for l in report.stdout_text.strip().splitlines() if "kvm_inj_virq" in l
        ]
        if not lines:
            test.fail(
                "No kvm_inj_virq events recorded during guest boot; "
                "virtual interrupt injection may not be working"
            )
        test.log.info("Virtual interrupt injection verified: %s", lines[0].strip())
    finally:
        session.close()
        process.run("rm -f %s" % perf_output, ignore_status=True)
