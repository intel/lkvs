#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

import os
import time

from provider import dmesg_router  # pylint: disable=unused-import
from provider import kvm_trace_utils

from avocado.utils import process
from virttest import data_dir, env_process, error_context, utils_package


HOST_TRACE_FILE = kvm_trace_utils.HOST_TRACE_FILE

# Bit 26 of exit_reason (Intel SDM Vol.3C 27.2) is the bus-lock flag. This
# test matches only dedicated BUS_LOCK basic-reason (74) vmexits via
# ``grep BUS_LOCK`` on the kvm_exit trace, then additionally assert bit 26
# is set in the extra-flags hex of that record.
# The kernel-side ftrace filter below is a defensive optimisation only: it
# suppresses unrelated kvm_exit lines so the tiny per-CPU trace ring buffer
# cannot wrap and drop the BUS_LOCK record on a noisy host. It does not
# change the assertion (``grep BUS_LOCK`` still only sees Case A because
# Case B rows print the other basic reason name, not "BUS_LOCK").
BUS_LOCK_EXIT_REASON_MASK = 0x4000000
BUS_LOCK_FILTER = "exit_reason & 0x%x" % BUS_LOCK_EXIT_REASON_MASK


def _check_host_bus_lock_msr(test, params):
    """Ensure host CPU exposes BUS_LOCK_DETECT via IA32_VMX_PROCBASED_CTLS2."""
    process.run("modprobe msr", shell=True, ignore_status=True)
    probe_cmd = params["host_msr_probe"]
    result = process.run(probe_cmd, shell=True, ignore_status=True)
    if result.exit_status != 0 or result.stdout_text.strip() != "1":
        test.cancel(
            "Host does not report BUS_LOCK_DETECT support: %s"
            % probe_cmd
        )


def _install_guest_gcc(test, session):
    """Ensure gcc is available inside the guest for compiling the bus-lock tool."""
    if not utils_package.package_install("gcc", session):
        test.cancel("Failed to install gcc in guest")


def _prepare_guest_bus_lock_tool(test, params, vm, session, source_file,
                                 exec_file):
    """Copy and compile a bus-lock helper in the guest; return its guest path."""
    deps_subdir = params["deps_subdir"]
    test_dir = params["test_dir"]
    deps_dir = data_dir.get_deps_dir(deps_subdir)

    files_to_copy = [source_file]
    shared_header = params.get("bus_lock_common_file")
    if shared_header:
        files_to_copy.append(shared_header)

    for name in files_to_copy:
        vm.copy_files_to(os.path.join(deps_dir, name), test_dir)

    compile_cmd = "cd %s && gcc %s -o %s" % (test_dir, source_file, exec_file)
    if session.cmd_status(compile_cmd) != 0:
        test.error("Failed to compile %s inside guest" % source_file)
    session.cmd("rm -f %s/%s" % (test_dir, " ".join(files_to_copy)))
    return os.path.join(test_dir, exec_file)


def _verify_host_bus_lock_exit(test):
    """a BUS_LOCK vmexit occurred with bit 26 set.

      1. ``grep BUS_LOCK`` on host kvm_exit trace -- only matches the
         dedicated BUS_LOCK basic-reason (74) vmexit, not bus locks that
         happen to accompany another exit reason.
      2. Parse the exit_reason extra-flags hex token that follows
         ``BUS_LOCK`` on that trace line.
      3. Assert bit 26 (``0x4000000``) is set in that value.
    Raises ``test.fail`` if any step is not satisfied.
    """
    result = process.run(
        "grep -m 1 BUS_LOCK %s || true" % HOST_TRACE_FILE,
        shell=True, ignore_status=True,
    )
    line = result.stdout_text.strip()
    if not line:
        test.fail("No BUS_LOCK VM exit observed in host kvm_exit trace")
    tokens = line.split("BUS_LOCK", 1)[1].split()
    if not tokens:
        test.fail("No exit_reason flags after BUS_LOCK in trace: %r" % line)
    flags_str = tokens[0]
    try:
        flags = int(flags_str, 16)
    except ValueError:
        test.fail(
            "Cannot parse exit_reason flags %r from BUS_LOCK trace: %r"
            % (flags_str, line)
        )
    test.log.info("Host BUS_LOCK vmexit exit_reason flags: %s", flags_str)
    if not flags & BUS_LOCK_EXIT_REASON_MASK:
        test.fail(
            "BUS_LOCK vmexit captured but bit 26 not set in exit_reason %s"
            % flags_str
        )


def _boot_vm(test, params, env):
    """Boot the main VM using the current params snapshot."""
    params["start_vm"] = "yes"
    env_process.preprocess_vm(test, params, env, params["main_vm"])
    vm = env.get_vm(params["main_vm"])
    vm.verify_alive()
    return vm


def _run_bus_lock_exit(test, params, env):
    """Verify a BUS_LOCK VM exit is recorded on host."""
    vm = _boot_vm(test, params, env)
    try:
        session = vm.wait_for_login(
            timeout=params.get_numeric("login_timeout", 240)
        )
        try:
            _install_guest_gcc(test, session)
            exec_path = _prepare_guest_bus_lock_tool(
                test, params, vm, session,
                params["bus_lock_source_file"],
                params["bus_lock_exec_file"],
            )
            kvm_trace_utils.enable_kvm_exit_trace(
                test, filter_expr=BUS_LOCK_FILTER)
            try:
                error_context.context(
                    "Trigger a bus lock inside guest", test.log.info,
                )
                session.cmd_status(exec_path,
                                   timeout=params.get_numeric(
                                       "bus_lock_run_timeout", 30))
                time.sleep(params.get_numeric("trace_settle_time", 3))
                _verify_host_bus_lock_exit(test)
            finally:
                kvm_trace_utils.disable_kvm_exit_trace(clear_filter=True)
        finally:
            session.close()
    finally:
        vm.destroy(gracefully=False)


def _measure_bus_lock_count(test, params, env, run_label, machine_extra):
    """Boot a VM with the given machine params, run bus_lock_ct in guest,
    sample host perf-kvm counters, return the second-interval count."""
    run_params = params.copy()
    run_params["machine_type_extra_params"] = machine_extra

    error_context.context(
        "Boot VM for '%s' run (machine_type_extra_params=%r)"
        % (run_label, machine_extra),
        test.log.info,
    )
    vm = _boot_vm(test, run_params, env)
    try:
        session = vm.wait_for_login(
            timeout=run_params.get_numeric("login_timeout", 240)
        )
        try:
            _install_guest_gcc(test, session)
            exec_path = _prepare_guest_bus_lock_tool(
                test, run_params, vm, session,
                run_params["bus_lock_source_file"],
                run_params["bus_lock_exec_file"],
            )
            error_context.context(
                "Start bus_lock_ct in guest background", test.log.info,
            )
            session.cmd("nohup %s >/dev/null 2>&1 &" % exec_path)
            # Give the guest a moment to enter its hot loop so the host perf
            # window actually captures bus-lock events.
            time.sleep(run_params.get_numeric("bus_lock_settle_time", 2))

            perf_cmd = (
                "perf stat -e %s -a -I %d --interval-count %d"
                % (
                    run_params["perf_event"],
                    run_params.get_numeric("perf_interval_ms", 1000),
                    run_params.get_numeric("perf_interval_count", 2),
                )
            )
            error_context.context(
                "Host: %s" % perf_cmd, test.log.info,
            )
            result = process.run(perf_cmd, shell=True, ignore_status=True)
            perf_output = (result.stdout_text or "") + \
                (result.stderr_text or "")
            test.log.info("perf output for %s:\n%s", run_label, perf_output)

            count = _parse_second_interval_count(test, perf_output, run_label)
            test.log.info("%s bus-lock count: %d", run_label, count)
            return count
        finally:
            session.close()
    finally:
        vm.destroy(gracefully=False)


def _parse_second_interval_count(test, perf_output, run_label):
    """Extract the counter value from the 2nd data line of perf-stat output."""
    data_lines = []
    for line in perf_output.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        parts = stripped.split()
        if len(parts) < 2:
            continue
        try:
            float(parts[0])
        except ValueError:
            continue
        data_lines.append(parts)
    if len(data_lines) < 2:
        test.error(
            "perf output for %s has fewer than 2 interval rows" % run_label
        )
    raw = data_lines[1][1].replace(",", "")
    if raw in ("<not", "not"):
        test.cancel(
            "perf reported counter as not supported/counted for %s" % run_label
        )
    try:
        return int(raw)
    except ValueError:
        test.error(
            "Cannot parse bus-lock count from %r in %s output"
            % (raw, run_label)
        )


def _run_ratelimit_effect(test, params, env):
    """Baseline vs ratelimit-20 bus-lock counts on host."""
    labels = params.objects("ratelimit_runs")
    if len(labels) != 2:
        test.error(
            "ratelimit_runs must define exactly two labels; got %s" % labels
        )

    counts = {}
    for label in labels:
        machine_extra = params.get("machine_extra_%s" % label, "")
        counts[label] = _measure_bus_lock_count(
            test, params, env, label, machine_extra
        )

    baseline_label, ratelimit_label = labels
    if counts[baseline_label] < counts[ratelimit_label]:
        test.fail(
            "Bus-lock ratelimit did not reduce host count: "
            "%s=%d < %s=%d"
            % (
                baseline_label, counts[baseline_label],
                ratelimit_label, counts[ratelimit_label],
            )
        )


@error_context.context_aware
def run(test, params, env):
    """
    Bus-lock VM-exit tests.

    ``buslock_ve_action`` selects the flow:
    - ``bus_lock_exit``: boot one VM with ``bus-lock-ratelimit=20``, trigger a
      bus lock inside the guest, and verify a BUS_LOCK VM exit is recorded on
      the host kvm_exit tracepoint.
    - ``ratelimit_effect``: boot two VMs sequentially (baseline vs.
      ``bus-lock-ratelimit=20``), run ``bus_lock_ct`` in the guest and sample
      the host ``bus_lock.split_locks`` performance counter with ``perf stat``;
      assert the ratelimited run reports no more bus locks than the baseline
      run.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    action = params["buslock_ve_action"]
    _check_host_bus_lock_msr(test, params)

    if action == "bus_lock_exit":
        _run_bus_lock_exit(test, params, env)
    elif action == "ratelimit_effect":
        _run_ratelimit_effect(test, params, env)
    else:
        test.error("Unknown buslock_ve_action: %s" % action)
