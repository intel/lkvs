#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

import time

from provider import dmesg_router  # pylint: disable=unused-import

from virttest import error_context
from virttest import utils_package


@error_context.context_aware
def run(test, params, env):
    """
    Live migration verification test:
    1) Boot guest and collect pre-migration state.
    2) Perform local live migration.
    3) Log in after migration and verify state is preserved.

    Supported verify_target values:
      - cpu_flags: Verify CPU flags are preserved after migration.
      - cpu_num: Verify CPU count matches after migration.
      - mem_size: Verify memory size is preserved after migration.
      - time: Verify time drift is within threshold after migration.
      - continuity: Start a process before migration, verify it survives.

    :param test: QEMU test object.
    :param params: Dictionary with test parameters.
    :param env: Dictionary with the test environment.
    """
    vm = env.get_vm(params["main_vm"])
    vm.verify_alive()

    login_timeout = int(params.get("login_timeout", 360))
    mig_timeout = float(params.get("mig_timeout", 300))
    verify_target = params["verify_target"]

    error_context.context("Log into guest before migration", test.log.info)
    session = vm.wait_for_login(timeout=login_timeout)

    try:
        # Collect pre-migration state
        pre_state = _collect_state(test, session, params, verify_target)

        # For continuity test, start background process before migration
        if verify_target == "continuity":
            _start_continuity_process(test, session, params)

        session.close()

        # Perform migration
        error_context.context("Perform local live migration", test.log.info)
        vm.migrate(timeout=mig_timeout)

        # Log in after migration
        error_context.context("Log into guest after migration", test.log.info)
        session = vm.wait_for_login(timeout=30)

        # Verify post-migration state
        error_context.context(
            "Verify %s after migration" % verify_target, test.log.info
        )
        _verify_state(test, session, params, verify_target, pre_state)
    finally:
        if session:
            session.close()
        vm.destroy(gracefully=False)


def _collect_state(test, session, params, verify_target):
    """Collect guest state before migration for comparison."""
    state = {}
    if verify_target == "cpu_flags":
        output = session.cmd_output("cat /proc/cpuinfo | grep flags | head -1")
        flags = set(output.strip().split(":")[1].split()) if ":" in output else set()
        state["cpu_flags"] = flags
        test.log.info("Pre-migration CPU flags count: %d", len(flags))

    elif verify_target == "cpuid":
        cpuid_cmd = params.get("cpuid_dump_cmd", "cpuid -1 -r")
        if session.cmd_status("which cpuid") != 0:
            if not utils_package.package_install("cpuid", session):
                test.cancel("cpuid package is not available in guest")
        output = session.cmd_output(cpuid_cmd, timeout=60)
        state["cpuid"] = output.strip()
        test.log.info(
            "Pre-migration CPUID dump collected (%d lines)",
            len(output.strip().splitlines()),
        )

    elif verify_target == "cpu_num":
        output = session.cmd_output("nproc").strip()
        state["cpu_num"] = int(output)
        test.log.info("Pre-migration CPU count: %s", output)

    elif verify_target == "mem_size":
        output = session.cmd_output(
            "grep MemTotal /proc/meminfo | awk '{print $2}'"
        ).strip()
        state["mem_kb"] = int(output)
        test.log.info("Pre-migration MemTotal: %s kB", output)

    elif verify_target == "time":
        host_time = time.time()
        guest_time_str = session.cmd_output("date +%s").strip()
        state["host_time"] = host_time
        state["guest_time"] = float(guest_time_str)
        test.log.info(
            "Pre-migration host_time=%.2f guest_time=%.2f",
            host_time,
            state["guest_time"],
        )

    return state


def _start_continuity_process(test, session, params):
    """Start a background process for continuity verification."""
    continuity_cmd = params.get("continuity_cmd", "cat /dev/urandom > /dev/null")
    test.log.info("Starting continuity process: %s", continuity_cmd)
    session.sendline("nohup %s &" % continuity_cmd)
    time.sleep(3)

    # Verify process started
    check_cmd = params.get("continuity_check_cmd", 'pgrep -f "cat /dev/urandom"')
    status = session.cmd_status(check_cmd)
    if status != 0:
        test.error("Continuity process did not start")


def _verify_state(test, session, params, verify_target, pre_state):
    """Verify guest state after migration matches pre-migration state."""
    if verify_target == "cpu_flags":
        output = session.cmd_output("cat /proc/cpuinfo | grep flags | head -1")
        post_flags = (
            set(output.strip().split(":")[1].split()) if ":" in output else set()
        )
        missing = pre_state["cpu_flags"] - post_flags
        extra = post_flags - pre_state["cpu_flags"]
        if missing:
            test.fail("CPU flags lost after migration: %s" % " ".join(missing))
        if extra:
            test.log.warning("Extra CPU flags after migration: %s", " ".join(extra))
        test.log.info("CPU flags preserved after migration (%d flags)", len(post_flags))

    elif verify_target == "cpuid":
        cpuid_cmd = params.get("cpuid_dump_cmd", "cpuid -1 -r")
        post_output = session.cmd_output(cpuid_cmd, timeout=60).strip()
        pre_output = pre_state["cpuid"]
        if pre_output != post_output:
            pre_lines = pre_output.splitlines()
            post_lines = post_output.splitlines()
            diffs = []
            for i, (pre_l, post_l) in enumerate(zip(pre_lines, post_lines)):
                if pre_l != post_l:
                    diffs.append("line %d: before=%r after=%r" % (i + 1, pre_l, post_l))
            if len(pre_lines) != len(post_lines):
                diffs.append(
                    "line count: before=%d after=%d" % (len(pre_lines), len(post_lines))
                )
            test.fail("CPUID changed after migration:\n%s" % "\n".join(diffs[:20]))
        test.log.info(
            "CPUID preserved after migration (%d lines)",
            len(post_output.splitlines()),
        )

    elif verify_target == "cpu_num":
        output = session.cmd_output("nproc").strip()
        post_num = int(output)
        if post_num != pre_state["cpu_num"]:
            test.fail(
                "CPU count changed after migration: "
                "before=%d after=%d" % (pre_state["cpu_num"], post_num)
            )
        test.log.info("CPU count preserved after migration: %d", post_num)

    elif verify_target == "mem_size":
        output = session.cmd_output(
            "grep MemTotal /proc/meminfo | awk '{print $2}'"
        ).strip()
        post_mem = int(output)
        # Allow 1% tolerance for memory size
        diff_pct = abs(post_mem - pre_state["mem_kb"]) / pre_state["mem_kb"] * 100
        if diff_pct > 1:
            test.fail(
                "Memory size changed after migration: "
                "before=%d kB after=%d kB (diff=%.2f%%)"
                % (pre_state["mem_kb"], post_mem, diff_pct)
            )
        test.log.info("Memory size preserved after migration: %d kB", post_mem)

    elif verify_target == "time":
        host_time_after = time.time()
        guest_time_str = session.cmd_output("date +%s").strip()
        guest_time_after = float(guest_time_str)

        host_elapsed = host_time_after - pre_state["host_time"]
        guest_elapsed = guest_time_after - pre_state["guest_time"]
        drift = abs(host_elapsed - guest_elapsed)
        drift_threshold = float(params.get("drift_threshold", 10))

        test.log.info(
            "Host elapsed: %.2f s, Guest elapsed: %.2f s, "
            "Drift: %.2f s (threshold: %.2f s)",
            host_elapsed,
            guest_elapsed,
            drift,
            drift_threshold,
        )
        if drift > drift_threshold:
            test.fail(
                "Time drift too large after migration: "
                "%.2f seconds (threshold: %.2f)" % (drift, drift_threshold)
            )

    elif verify_target == "continuity":
        check_cmd = params.get("continuity_check_cmd", 'pgrep -f "cat /dev/urandom"')
        status = session.cmd_status(check_cmd)
        if status != 0:
            test.fail("Continuity process not running after migration")
        test.log.info("Continuity process survived migration")
        # Clean up
        session.cmd_status('pkill -f "cat /dev/urandom"')
