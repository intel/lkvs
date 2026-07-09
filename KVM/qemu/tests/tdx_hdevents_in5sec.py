#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

# Author: Farrah Chen <farrah.chen@intel.com>
#
# History:  Jul. 2026 - Farrah Chen - creation

from provider import dmesg_router  # pylint: disable=unused-import

from virttest import env_process, error_context, utils_package


@error_context.context_aware
def run(test, params, env):
    """
    TDX PMU hardware events collection test:
    1. Host mediated-PMU setup (disable nmi_watchdog, reload kvm_intel with
       enable_mediated_pmu=Y) is performed by avocado-vt via ``pre_command``
       before this handler runs.
    2. Boot TD VM with pmu=on.
    3. Run `perf stat` on six hardware events for a fixed duration in guest.
    4. Verify perf output contains the expected header line.
    5. Host restore (re-enable nmi_watchdog, reload kvm_intel without mediated
       PMU) is performed by avocado-vt via ``post_command`` after this handler
       returns and the VM is destroyed.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    perf_events = params["perf_events"]
    perf_duration = params.get_numeric("perf_duration", 5)
    expected_output = params["perf_expected_output"]
    login_timeout = params.get_numeric("login_timeout", 240)

    event_args = " ".join("-e %s" % ev.strip() for ev in perf_events.split(","))
    perf_cmd = "perf stat %s -a -- sleep %d 2>&1" % (event_args, perf_duration)

    error_context.context("Boot TD VM with pmu enabled", test.log.info)
    params["start_vm"] = "yes"
    env_process.preprocess_vm(test, params, env, params["main_vm"])
    vm = env.get_vm(params["main_vm"])
    vm.verify_alive()
    session = vm.wait_for_login(timeout=login_timeout)

    error_context.context("Ensure perf tool is available in guest",
                          test.log.info)
    if not utils_package.package_install("perf", session):
        test.cancel("Failed to install perf in guest")

    error_context.context(
        "Collect hardware events for %d seconds in guest" % perf_duration,
        test.log.info,
    )
    output = session.cmd_output(perf_cmd, timeout=perf_duration + 60)
    test.log.info("perf output:\n%s", output)
    if expected_output not in output:
        test.fail(
            "perf did not produce expected header %r; got: %s"
            % (expected_output, output)
        )

    session.close()
