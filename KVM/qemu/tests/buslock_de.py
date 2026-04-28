#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

from provider import dmesg_router  # pylint: disable=unused-import
from collections import Counter
import os
import re
import time
from aexpect import exceptions as aexpect_exceptions
from avocado.core import exceptions
from avocado.utils import process
from virttest import data_dir, error_context
from virttest import utils_misc, utils_package
from provider.cpu_utils import check_cpu_flags
from provider.cpuid_utils import check_cpuid, prepare_cpuid
from provider.test_utils import get_baremetal_dir


def _install_guest_packages(test, session):
    """Install the required guest packages for compilation and MSR checks."""
    pkg_candidates = ["gcc", "msr-tools"]
    for pkg_name in pkg_candidates:
        if not utils_package.package_install(pkg_name, session):
            test.cancel("Failed to install package %s" % pkg_name)


def _check_guest_bus_lock_capability(test, params, vm, session):
    """Ensure guest supports bus lock detection feature."""
    try:
        check_cpu_flags(params, "bus_lock_detect", test, session)
    except exceptions.TestFail:
        test.cancel("Guest CPU does not support bus_lock_detect")

    cpuid_arg = params.get("cpuid")
    if cpuid_arg is None:
        test.error("Failed to find CPUID bit in config file")

    bm_dir = get_baremetal_dir(params)
    cpuid_src_subdir = params.get("cpuid_src_subdir", "tools/cpuid_check")
    cpuid_src_dir = "%s/%s" % (bm_dir, cpuid_src_subdir)
    cpuid_tool = None
    try:
        cpuid_params = params.copy()
        cpuid_params["source_file"] = params["cpuid_source_file"]
        cpuid_params["exec_file"] = params["cpuid_exec_file"]
        cpuid_tool = prepare_cpuid(test, cpuid_params, cpuid_src_dir, vm, session)
        if check_cpuid(cpuid_arg, cpuid_tool, session):
            test.cancel("Guest CPUID does not expose bus lock detect")
    finally:
        if cpuid_tool:
            session.cmd("rm -f %s" % cpuid_tool, ignore_all_errors=True)


def _update_split_lock_mode(test, session, split_lock_mode):
    """Update guest split_lock_detect mode through kexec and verify cmdline."""

    if not utils_package.package_install("kexec-tools", session):
        test.cancel("Failed to install kexec-tools in guest")

    cmd = (
        "set -e; "
        "kernel=/boot/vmlinuz-$(uname -r); "
        "initrd=$(ls /boot | grep $(uname -r) | grep -E 'initrd|initramfs' | head -n1); "
        "old_cmdline=$(cat /proc/cmdline); "
        "clean_cmdline=$(echo $old_cmdline | sed -r 's/split_lock_detect=[^ ]+//g' | xargs); "
        "new_cmdline=\"$clean_cmdline split_lock_detect=%s\"; "
        "kexec -l $kernel --append=\"$new_cmdline\" --initrd=/boot/$initrd; "
        "nohup sh -c 'sleep 3; kexec -e; sleep 15' >/dev/null 2>&1 &"
    ) % split_lock_mode
    session.cmd_status(cmd, timeout=180)


def _prepare_guest_bus_lock_tool(test, params, vm, session):
    """Copy and compile bus_lock test tool in guest."""
    deps_subdir = params["deps_subdir"]
    source_file = params.get("bus_lock_source_file_tdx", params["bus_lock_source_file"])
    exec_file = params.get("bus_lock_exec_file_tdx", params["bus_lock_exec_file"])

    test_dir = params["test_dir"]

    deps_dir = data_dir.get_deps_dir(deps_subdir)
    copied_files = [source_file]
    shared_header = params.get("bus_lock_common_file")
    if shared_header:
        header_path = os.path.join(deps_dir, shared_header)
        if not os.path.exists(header_path):
            raise exceptions.TestError("Failed to find %s" % shared_header)
        copied_files.append(shared_header)

    for file_name in copied_files:
        vm.copy_files_to(os.path.join(deps_dir, file_name), test_dir)

    compile_cmd = "cd %s && gcc %s -o %s" % (test_dir, source_file, exec_file)
    status = session.cmd_status(compile_cmd)
    if status:
        raise exceptions.TestError("Failed to compile %s" % source_file)

    session.cmd("rm -f %s/%s" % (test_dir, " ".join(copied_files)))
    return os.path.join(test_dir, exec_file)


def _get_bus_lock_db_lines(session):
    """Get guest dmesg lines for bus_lock #DB traps."""
    cmd = (
        "dmesg | grep 'split lock detection: #DB' "
        "| grep 'took a bus_lock trap at address' || true"
    )
    output = session.cmd_output(cmd)
    lines = [line for line in output.splitlines() if line.strip()]
    return lines


def _get_guest_msr_bit(session):
    """Read IA32_DEBUGCTL[2] raw value from guest."""
    session.cmd("modprobe msr")
    return session.cmd_output("rdmsr 0x01d9 -0 --bitfield 2:2").strip()


def _is_signal_exit_status(status, signal_num):
    """Return True if shell status indicates termination by signal."""
    return status == 128 + signal_num


def _verify_guest_cmdline_with_retry(
    test,
    vm,
    session,
    split_lock_mode,
    timeout,
    retry_count=3,
    retry_sleep=5,
):
    """Verify guest cmdline with retry/reconnect for transient SSH drops."""
    verify_cmd = "grep -qw 'split_lock_detect=%s' /proc/cmdline" % split_lock_mode
    for attempt in range(1, retry_count + 1):
        try:
            if session.cmd_status(verify_cmd) == 0:
                return session
            if attempt == retry_count:
                test.fail(
                    "Guest cmdline does not contain split_lock_detect=%s"
                    % split_lock_mode
                )
            test.log.warning(
                "Guest cmdline not ready (attempt %s/%s), retrying in %ss",
                attempt,
                retry_count,
                retry_sleep,
            )
            time.sleep(retry_sleep)
        except (
            aexpect_exceptions.ShellProcessTerminatedError,
            aexpect_exceptions.ExpectProcessTerminatedError,
        ) as err:
            if attempt == retry_count:
                raise
            test.log.warning(
                "Session dropped during cmdline check (attempt %s/%s): %s",
                attempt,
                retry_count,
                err,
            )
            session = vm.wait_for_login(timeout=timeout)
            time.sleep(retry_sleep)

    return session


def _check_host_split_lock_cmdline():
    """Ensure host kernel cmdline contains split_lock_detect=off."""
    try:
        host_cmdline = utils_misc.get_ker_cmd().strip()
    except Exception as err:  # pylint: disable=broad-except
        raise exceptions.TestError("Failed to read host /proc/cmdline: %s" % str(err))

    if "split_lock_detect=off" not in host_cmdline:
        raise exceptions.TestError(
            "Host kernel cmdline must include split_lock_detect=off before running this test"
        )


def _extract_second_from_dmesg(line, timestamp_mode):
    """Extract a comparable integer second value from a dmesg timestamp line.

    Supports two timestamp formats produced by dmesg:

    - Seconds since boot: ``[  123.456789]``
      The integer part (123) is returned directly.

    - Human-readable HH:MM:SS (``dmesg -T``):
      ``[Mon Apr 14 12:34:56 2026]`` or ``[2026-04-14T12:34:56.789012+0800]``
      The time part is converted to total seconds (H*3600 + M*60 + S) so that
      lines in the same wall-clock second compare equal.

    :param timestamp_mode: parsing mode: "boot" or "hms".
    :returns: integer second value, or None if no recognised format is found.
    """
    # Format 1: seconds since boot  [  123.456789]
    boot_match = re.search(r"\[\s*([0-9]+)\.[0-9]+\]", line)
    boot_second = int(boot_match.group(1)) if boot_match else None

    # Format 2: HH:MM:SS embedded in human-readable timestamp
    # Examples: [Mon Apr 14 12:34:56 2026]  [2026-04-14T12:34:56.789012+0800]
    hms_match = re.search(r"\[.*?(\d{1,2}):(\d{2}):(\d{2})", line)
    hms_second = None
    if hms_match:
        h = int(hms_match.group(1))
        m = int(hms_match.group(2))
        s = int(hms_match.group(3))
        hms_second = h * 3600 + m * 60 + s

    if timestamp_mode == "boot":
        return boot_second
    if timestamp_mode == "hms":
        return hms_second
    return None


def _enable_kvm_trace():
    """Enable KVM exit tracing on host."""
    try:
        process.run(
            "echo 1 > /sys/kernel/debug/tracing/events/kvm/kvm_exit/enable",
            shell=True,
        )
        process.run("echo 0 > /sys/kernel/debug/tracing/trace", shell=True)
    except process.CmdError as e:
        raise exceptions.TestError("Failed to enable KVM trace: %s" % str(e))


def _check_exception_nmi_in_trace(test, expect_present, retry_count=0):
    """Check if EXCEPTION_NMI with 0x80000301 exists in KVM trace.

    Args:
        test: Test object for logging and failure
        expect_present: True if EXCEPTION_NMI is expected, False if not expected
        retry_count: Number of retries with sleep between checks (for ratelimit case)
    """
    found = False

    if retry_count > 0:
        # For ratelimit case: retry checking trace
        for i in range(retry_count):
            try:
                output = process.run(
                    "cat /sys/kernel/debug/tracing/trace | "
                    "grep \"0x80000301\" || true",
                    shell=True,
                ).stdout.strip()
                if output:
                    found = True
                    break
                time.sleep(1)
            except process.CmdError:
                pass
    else:
        # For standard case: check trace for EXCEPTION_NMI
        try:
            output = process.run(
                "cat /sys/kernel/debug/tracing/trace | "
                "grep EXCEPTION_NMI | grep 0x80000301 || true",
                shell=True,
            ).stdout.strip()
            found = bool(output)
        except process.CmdError:
            pass

    if expect_present and not found:
        test.fail("Expected EXCEPTION_NMI(0x80000301) in KVM trace")
    elif not expect_present and found:
        test.fail("Unexpected EXCEPTION_NMI(0x80000301) found in KVM trace")


@error_context.context_aware
def run(test, params, env):
    """Test bus_lock_detect feature with various split_lock_detect modes and verify guest/host behavior."""
    _check_host_split_lock_cmdline()

    vm_name = params["main_vm"]
    split_lock_mode = params["split_lock_mode"]
    expected_msr_bit = params.get_numeric("expected_msr_bit", 1)
    expected_dmesg_delta = params.get("expected_dmesg_delta", "ge1")
    expected_dmesg_count = params.get_numeric("expected_dmesg_count", 0)
    expect_bus_error = params.get_boolean("expect_bus_error")
    check_core_dump = params.get_boolean("check_core_dump")
    timeout = params.get_numeric("login_timeout", 240)
    reboot_settle_time = params.get_numeric("reboot_settle_time", 20)
    cmdline_check_retry = params.get_numeric("cmdline_check_retry", 3)
    cmdline_check_retry_sleep = params.get_numeric("cmdline_check_retry_sleep", 5)

    vm = env.get_vm(vm_name)
    vm.verify_alive()
    session = vm.wait_for_login(timeout=timeout)

    test_dir = params["test_dir"]
    guest_tool = None

    # Detect TDX environment: TDX VMs don't perform host-side EXCEPTION_NMI verification
    is_tdx = params.get("vm_secure_guest_type") == "tdx"

    # Keep ratelimit validation enabled for both VM/TDX because it validates
    # guest dmesg behavior, while EXCEPTION_NMI trace checking is host-side only.
    ratelimit_retry = params.get_boolean("ratelimit_retry", False)

    # For TDX: skip EXCEPTION_NMI checks (host-side KVM trace verification)
    # For non-TDX (standard KVM): perform EXCEPTION_NMI checks as configured
    expect_exception_nmi = params.get_boolean("expect_exception_nmi", None) if not is_tdx else None
    trace_retry = ratelimit_retry if not is_tdx else False
    try:
        error_context.context("Install required packages in guest", test.log.info)
        _install_guest_packages(test, session)

        error_context.context("Check guest bus lock capability", test.log.info)
        _check_guest_bus_lock_capability(test, params, vm, session)

        error_context.context("Reboot guest with split_lock_detect=%s" % split_lock_mode,
                              test.log.info)
        _update_split_lock_mode(test, session, split_lock_mode)
        session.close()
        session = vm.wait_for_login(timeout=timeout)
        time.sleep(reboot_settle_time)

        session = _verify_guest_cmdline_with_retry(
            test,
            vm,
            session,
            split_lock_mode,
            timeout,
            retry_count=cmdline_check_retry,
            retry_sleep=cmdline_check_retry_sleep,
        )

        error_context.context("Check guest MSR bit for bus lock detection", test.log.info)
        msr_bit_value = _get_guest_msr_bit(session)
        if msr_bit_value != str(expected_msr_bit):
            test.fail("Guest MSR bit[2] mismatch for split_lock_detect=%s" % split_lock_mode)

        error_context.context("Enable KVM trace for bus lock monitoring", test.log.info)
        _enable_kvm_trace()

        error_context.context("Compile bus lock trigger tool in guest", test.log.info)
        guest_tool = _prepare_guest_bus_lock_tool(test, params, vm, session)

        before_lines = _get_bus_lock_db_lines(session)

        error_context.context("Run bus lock trigger tool", test.log.info)
        # Run via bash -c so that the shell's signal message (e.g. "Bus error")
        # is printed to the subshell's stderr, which is captured in the log.
        # Directly running the binary causes the session shell to print "Bus error"
        # to the terminal rather than into the redirected log file.
        run_cmd = "bash -c '%s' > %s/bus_lock.log 2>&1" % (guest_tool, test_dir)
        run_status = session.cmd_status(run_cmd)
        run_log = session.cmd_output("cat %s/bus_lock.log || true" % test_dir)

        has_bus_error = "Bus error" in run_log
        has_sigbus_exit = _is_signal_exit_status(run_status, 7)
        if expect_bus_error:
            if not (has_bus_error or has_sigbus_exit):
                test.fail(
                    "Expected bus error behavior when split_lock_detect=%s, "
                    "got status=%s log=%s"
                    % (split_lock_mode, run_status, run_log)
                )
        else:
            if has_bus_error:
                test.fail("Unexpected 'Bus error' when split_lock_detect=%s" % split_lock_mode)
            if run_status:
                test.fail("Bus lock tool execution failed with status %s" % run_status)

        if check_core_dump and "core dumped" in run_log:
            test.fail("Unexpected core dumped in bus lock output")

        if expect_exception_nmi is not None:
            error_context.context("Check EXCEPTION_NMI in KVM trace", test.log.info)
            if trace_retry:
                _check_exception_nmi_in_trace(test, expect_exception_nmi, retry_count=30)
            else:
                _check_exception_nmi_in_trace(test, expect_exception_nmi)

        after_lines = _get_bus_lock_db_lines(session)
        new_lines = after_lines[len(before_lines):]

        if expected_dmesg_delta == "ge1":
            if len(new_lines) < 1:
                test.fail("Expected at least one #DB bus_lock trap in guest dmesg")
        elif expected_dmesg_delta == "zero":
            if len(new_lines) != 0:
                test.fail("Expected no new #DB bus_lock trap in guest dmesg")
        elif expected_dmesg_delta == "exact":
            if not (ratelimit_retry and expected_dmesg_count > 0):
                test.error(
                    "exact mode requires ratelimit_retry=yes and expected_dmesg_count > 0"
                )

            # Ratelimit case: validate per-second trap count instead of total
            # line count, because the tool may run across multiple seconds.
            parsed_seconds = None
            mode_hint = None
            for timestamp_mode, mode_label in (("boot", "boot-seconds"),
                                               ("hms", "HH:MM:SS")):
                candidate_seconds = [
                    _extract_second_from_dmesg(
                        line,
                        timestamp_mode=timestamp_mode,
                    )
                    for line in new_lines
                ]
                if all(second is not None for second in candidate_seconds):
                    parsed_seconds = candidate_seconds
                    mode_hint = mode_label
                    break

            if parsed_seconds is None:
                test.fail(
                    "Failed to parse dmesg timestamp for ratelimit validation "
                    "(tried both boot and HH:MM:SS formats)"
                )

            per_second_counts = Counter(parsed_seconds)
            if any(
                count != expected_dmesg_count
                for count in per_second_counts.values()
            ):
                test.fail(
                    "Expected %s traps per second, got per-second counts %s "
                    "(mode=%s, total=%s)"
                    % (
                        expected_dmesg_count,
                        sorted(per_second_counts.values()),
                        mode_hint,
                        len(new_lines),
                    )
                )
        else:
            test.error("Unknown expected_dmesg_delta mode: %s" % expected_dmesg_delta)

    finally:
        if session:
            session.cmd("rm -f %s/bus_lock.log" % test_dir, ignore_all_errors=True)
            if guest_tool:
                session.cmd("rm -f %s" % guest_tool, ignore_all_errors=True)
            session.close()
