#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

"""Shared helpers for the host KVM ``kvm/kvm_exit`` ftrace tracepoint.

Used by tests that need to observe raw VMX exits from KVM (e.g.
``buslock_ve``, ``pf_intercepts_ept``). Enabling / disabling the same
tracepoint pattern is duplicated across those tests, so it lives here.
"""

import os

from avocado.utils import process


HOST_TRACE_DIR = "/sys/kernel/debug/tracing"
HOST_KVM_EXIT_ENABLE = os.path.join(HOST_TRACE_DIR, "events/kvm/kvm_exit/enable")
HOST_KVM_EXIT_FILTER = os.path.join(HOST_TRACE_DIR, "events/kvm/kvm_exit/filter")
HOST_TRACE_FILE = os.path.join(HOST_TRACE_DIR, "trace")


def enable_kvm_exit_trace(test, filter_expr=None):
    """Enable the host ``kvm/kvm_exit`` tracepoint and clear the ring buffer.

    :param test: avocado test object; used to raise ``test.error`` if the
        tracepoint cannot be enabled after write-back verification.
    :param filter_expr: optional ftrace filter expression written to the
        tracepoint's ``filter`` file before enabling. For example
        ``"exit_reason == 0"`` restricts recorded exits to EXCEPTION_NMI
        so the ring buffer stays tiny during a full guest boot. ``None``
        leaves the existing filter untouched.
    """
    if filter_expr is not None:
        process.run(
            "echo '%s' > %s" % (filter_expr, HOST_KVM_EXIT_FILTER),
            shell=True,
        )
    process.run("echo 1 > %s" % HOST_KVM_EXIT_ENABLE, shell=True)
    process.run("echo > %s" % HOST_TRACE_FILE, shell=True)
    enabled = process.run(
        "cat %s" % HOST_KVM_EXIT_ENABLE, shell=True
    ).stdout_text.strip()
    if enabled != "1":
        test.error("kvm_exit tracepoint could not be enabled on host")


def disable_kvm_exit_trace(clear_filter=False):
    """Best-effort disable of the ``kvm/kvm_exit`` tracepoint.

    :param clear_filter: when True, also reset the ftrace filter with
        ``echo 0 > filter`` so subsequent runs start from a clean state.
        Callers that set a filter in :func:`enable_kvm_exit_trace` should
        pass ``True`` here to avoid leaking the filter into other tests.
    """
    process.run(
        "echo 0 > %s" % HOST_KVM_EXIT_ENABLE,
        shell=True, ignore_status=True,
    )
    if clear_filter:
        process.run(
            "echo 0 > %s" % HOST_KVM_EXIT_FILTER,
            shell=True, ignore_status=True,
        )
