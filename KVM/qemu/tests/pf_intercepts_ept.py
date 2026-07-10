#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation


import os
import time

from provider import dmesg_router  # pylint: disable=unused-import
from provider import kvm_trace_utils

from avocado.utils import process

from virttest import env_process, error_context


HOST_TRACE_FILE = kvm_trace_utils.HOST_TRACE_FILE

# VMX EXIT_REASON_EXCEPTION_NMI = 0. Restricting the tracepoint to this exit
# reason keeps the ftrace buffer tiny even during a full guest boot.
KVM_EXIT_REASON_EXCEPTION_NMI = 0


def _ensure_ept_enabled(test, params):
    """Cancel unless the host reports Intel EPT enabled."""
    process.run("modprobe kvm", shell=True, ignore_status=True)
    process.run("modprobe kvm_intel", shell=True, ignore_status=True)
    ept_sysfs = params["ept_sysfs"]
    if not os.path.exists(ept_sysfs):
        test.cancel(
            "Host does not expose %s; kvm_intel EPT status unknown"
            % ept_sysfs
        )
    with open(ept_sysfs) as fp:
        ept = fp.read().strip()
    if ept != "Y":
        test.cancel(
            "Host kvm_intel EPT not enabled (%s=%r)" % (ept_sysfs, ept)
        )


def _count_pf_intercepts(test, pf_vector):
    """Count filtered EXCEPTION_NMI lines whose intr_info vector matches ``pf_vector``.

    The kvm_exit tracepoint's ``intr_info`` field is printed as ``0x%08x``;
    the low 8 bits carry the interrupt vector on Intel VMX. We match on the
    last two hex characters of the intr_info field to keep grep cheap.
    """
    vec_hex = "%02x" % (pf_vector & 0xFF)
    # grep -c returns 1 (no match) instead of failing the whole run.
    pattern = "intr_info 0x[0-9a-fA-F]\\{6\\}%s" % vec_hex
    result = process.run(
        "grep -c -E %r %s || true" % (pattern, HOST_TRACE_FILE),
        shell=True, ignore_status=True,
    )
    return int(result.stdout_text.strip() or "0")


@error_context.context_aware
def run(test, params, env):
    """
    Verify that host KVM does not intercept guest page faults when EPT is
    enabled.

    Steps:
      1. Ensure ``kvm_intel`` is loaded with EPT enabled (skip otherwise).
      2. Enable the host ``kvm/kvm_exit`` tracepoint and clear its buffer.
      3. Boot the guest and let it run for ``trace_duration`` seconds so boot
         and steady-state exits are captured.
      4. Read the ftrace buffer and count EXCEPTION_NMI exits whose
         ``intr_info`` vector equals ``pf_vector`` (14 = #PF).
      5. Fail if any such intercept is observed; log the total EXCEPTION_NMI
         count for context.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    pf_vector = params.get_numeric("pf_vector", 14)
    trace_duration = params.get_numeric("trace_duration", 10)

    _ensure_ept_enabled(test, params)

    error_context.context(
        "Enable host kvm_exit tracepoint and clear buffer",
        test.log.info,
    )
    kvm_trace_utils.enable_kvm_exit_trace(
        test,
        filter_expr="exit_reason == %d" % KVM_EXIT_REASON_EXCEPTION_NMI,
    )
    try:
        error_context.context(
            "Boot guest with EPT-backed memory", test.log.info,
        )
        params["start_vm"] = "yes"
        env_process.preprocess_vm(test, params, env, params["main_vm"])
        vm = env.get_vm(params["main_vm"])
        vm.verify_alive()
        try:
            time.sleep(trace_duration)

            error_context.context(
                "Read host trace and count #PF intercepts", test.log.info,
            )
            pf_count = _count_pf_intercepts(test, pf_vector)
            test.log.info(
                "#PF (vector %d) intercepts found: %d",
                pf_vector, pf_count,
            )
            if pf_count > 0:
                test.fail(
                    "Detected %d guest #PF (vector %d) intercepts while EPT "
                    "is enabled; expected 0"
                    % (pf_count, pf_vector)
                )
        finally:
            vm.destroy(gracefully=False)
    finally:
        kvm_trace_utils.disable_kvm_exit_trace(clear_filter=True)
