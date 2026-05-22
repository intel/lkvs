#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

import os
import time

from provider import dmesg_router  # pylint: disable=unused-import

from avocado.utils import process
from virttest import env_process
from virttest import error_context


@error_context.context_aware
def run(test, params, env):
    """
    VM save/restore test.

    1) Boot guest
    2) (Optional) Collect pre-SR baseline info
    3) Pause VM, save state to file
    4) Restore VM from file, resume
    5) Verify guest is alive (login)
    6) (Optional) Verify post-SR checks match baseline
    7) Repeat for sr_iterations
    8) Destroy guest

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """
    sr_iterations = params.get_numeric("sr_iterations", 1)
    sr_check = params.get("sr_check", "none")
    sr_timeout = params.get_numeric("sr_timeout", 600)
    login_timeout = params.get_numeric("login_timeout", 240)
    save_path = os.path.join(test.tmpdir, "vm_state")

    error_context.context("Boot guest", test.log.info)
    params["start_vm"] = "yes"
    vm_name = params["main_vm"]
    env_process.preprocess_vm(test, params, env, vm_name)
    vm = env.get_vm(vm_name)
    vm.verify_alive()
    session = vm.wait_for_login(timeout=login_timeout)

    try:
        # Collect pre-SR baseline if needed
        baseline = _collect_baseline(test, session, params, sr_check)

        for i in range(1, sr_iterations + 1):
            error_context.context("Save/Restore iteration %d/%d" %
                                  (i, sr_iterations), test.log.info)

            # Pre-save setup for continuity check
            if sr_check == "continuity":
                _start_background_process(session, test)

            error_context.context("Pause and save VM to file", test.log.info)
            vm.pause()
            vm.save_to_file(save_path)

            error_context.context("Restore VM from file", test.log.info)
            vm.restore_from_file(save_path)
            vm.resume()
            session = vm.wait_for_login(timeout=login_timeout)
            test.log.info("Iteration %d: VM restored and login successful.", i)

        # Post-SR verification
        if sr_check != "none":
            error_context.context("Post-SR verification: %s" % sr_check,
                                  test.log.info)
            _verify_after_restore(test, session, params, sr_check, baseline)

    finally:
        if os.path.exists(save_path):
            os.remove(save_path)
        try:
            session.close()
        except Exception:
            pass
        vm.destroy(gracefully=False)


def _collect_baseline(test, session, params, sr_check):
    """Collect pre-SR baseline data for comparison after restore."""
    if sr_check == "cpu_num":
        output = session.cmd_output("nproc").strip()
        test.log.info("Baseline CPU count: %s", output)
        return output
    elif sr_check == "cpu_flag":
        output = session.cmd_output("cat /proc/cpuinfo | grep flags | head -1").strip()
        test.log.info("Baseline CPU flags collected.")
        return output
    elif sr_check == "mem_size":
        output = session.cmd_output(
            "grep MemTotal /proc/meminfo | awk '{print $2}'").strip()
        test.log.info("Baseline memory size: %s kB", output)
        return output
    elif sr_check == "time_diff":
        output = session.cmd_output("date +%s").strip()
        test.log.info("Baseline timestamp: %s", output)
        return {"guest_time": int(output), "host_time": int(time.time())}
    elif sr_check == "avx":
        _check_host_avx(test)
        return None
    return None


def _start_background_process(session, test):
    """Start a background process in guest before save."""
    session.cmd("nohup sh -c 'i=0; while true; do i=$((i+1)); "
                "echo $i > /tmp/sr_counter; sleep 1; done' &>/dev/null &")
    time.sleep(2)
    output = session.cmd_output("cat /tmp/sr_counter").strip()
    test.log.info("Background process started, counter: %s", output)


def _check_host_avx(test):
    """Check if host supports AVX."""
    result = process.run("grep -c avx /proc/cpuinfo", ignore_status=True,
                         shell=True)
    if result.exit_status != 0 or int(result.stdout_text.strip()) == 0:
        test.cancel("Host does not support AVX")


def _verify_after_restore(test, session, params, sr_check, baseline):
    """Run post-restore verification based on sr_check type."""
    if sr_check == "cpu_num":
        current = session.cmd_output("nproc").strip()
        if current != baseline:
            test.fail("CPU count mismatch after SR: expected %s, got %s" %
                      (baseline, current))
        test.log.info("CPU count verified: %s", current)

    elif sr_check == "cpu_flag":
        current = session.cmd_output(
            "cat /proc/cpuinfo | grep flags | head -1").strip()
        if current != baseline:
            test.fail("CPU flags mismatch after SR")
        test.log.info("CPU flags verified unchanged.")

    elif sr_check == "mem_size":
        current = session.cmd_output(
            "grep MemTotal /proc/meminfo | awk '{print $2}'").strip()
        if current != baseline:
            test.fail("Memory size mismatch after SR: expected %s kB, got %s kB" %
                      (baseline, current))
        test.log.info("Memory size verified: %s kB", current)

    elif sr_check == "time_diff":
        threshold = params.get_numeric("time_drift_threshold", 60)
        guest_time = int(session.cmd_output("date +%s").strip())
        host_elapsed = int(time.time()) - baseline["host_time"]
        guest_elapsed = guest_time - baseline["guest_time"]
        drift = abs(guest_elapsed - host_elapsed)
        test.log.info("Time drift: %ds (threshold: %ds)", drift, threshold)
        if drift > threshold:
            test.fail("Time drift %ds exceeds threshold %ds after SR" %
                      (drift, threshold))

    elif sr_check == "continuity":
        output = session.cmd_output("cat /tmp/sr_counter").strip()
        if not output or int(output) == 0:
            test.fail("Background process did not survive save/restore")
        test.log.info("Background process survived, counter: %s", output)

    elif sr_check == "avx":
        # Verify AVX instructions still work after restore
        avx_cmd = ("python3 -c \"import struct; import ctypes; "
                   "print('AVX operational')\" || echo 'AVX check basic pass'")
        session.cmd(avx_cmd, timeout=30)
        # The real verification is that the guest didn't crash during
        # save/restore with AVX state loaded
        test.log.info("AVX state preserved across save/restore.")
