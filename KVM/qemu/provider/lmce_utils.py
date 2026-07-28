#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

# Author: Farrah Chen <farrah.chen@intel.com>
#
# History: Jul. 2026 - Farrah Chen - creation

"""Helpers shared by Local Machine Check Exception (LMCE) related tests.

Provides the IA32 MSR / bit-mask / MCi_STATUS / MCG_STATUS constants used
to probe guest LMCE state and to shape MCE injections, plus the small
helpers reused by both the HMP-based (lmce.py) and EINJ-based (ras.py)
test flows.
"""

import os

from virttest import data_dir as virttest_data_dir
from virttest import utils_package


# IA32 MSR addresses used to probe LMCE support and configuration.
IA32_MCG_CAP = 0x179
IA32_FEATURE_CONTROL = 0x3A
IA32_MCG_EXT_CTL = 0x4D0

# Enabling bits: all three must be set for guest to have LMCE fully enabled.
MCG_LMCE_P_MASK = 1 << 27  # IA32_MCG_CAP.LMCE_P
FEATURE_LMCE_ON_MASK = 1 << 20  # IA32_FEATURE_CONTROL.LMCE_ON
MCG_EXT_CTL_LMCE_EN_MASK = 1  # IA32_MCG_EXT_CTL.LMCE_EN

# Precomputed IA32_MCi_STATUS values per Intel SDM Vol.3B Ch.15.
# SRAO = VAL(63) | UC(61) | EN(60) | MISCV(59) | ADDRV(58) | S(56) | mcacod=0x080
# SRAR = SRAO | AR(55), with mcacod=0x134 (data-load uncorrected read).
MCI_STATUS_SRAO = 0xBD00000000000080
MCI_STATUS_SRAR = 0xBD80000000000134

# MCG_STATUS values per Intel SDM Vol.3B Table 15-20. Bits:
#   RIPV=0x1  EIPV=0x2  MCIP=0x4  LMCE_S=0x8
# SRAO -> restart-safe context: MCIP|RIPV = 0x5, +LMCE_S = 0xD.
# SRAR -> current-instruction fault: MCIP|EIPV = 0x6, +LMCE_S = 0xE.
# Using the wrong flavor for SRAR (RIPV=1) makes the guest kernel treat
# the fault as restart-safe and skip SIGBUS.AR delivery.
MCG_STATUS_MCIP_RIPV = 0x5
MCG_STATUS_MCIP_EIPV = 0x6
MCG_STATUS_SRAO_LOCAL = 0xD
MCG_STATUS_SRAR_LOCAL = 0xE
# Back-compat alias for pre-existing callers that pass a "local SRAO" context.
MCG_STATUS_LOCAL = MCG_STATUS_SRAO_LOCAL


def install_msr_tools(test, session):
    """Ensure rdmsr is available inside the guest."""
    if not utils_package.package_install("msr-tools", session):
        test.cancel("Failed to install msr-tools inside guest.")


def rdmsr_hex(session, msr):
    """Read a guest MSR via ``rdmsr`` and return its integer value.

    Uses ``cmd_status_output`` so a non-zero exit (msr module not loaded,
    MSR unsupported on this CPU, etc.) surfaces as a ``RuntimeError`` with
    the underlying rdmsr stderr instead of an opaque ``ValueError`` from
    ``int("", 16)``.
    """
    status, out = session.cmd_status_output("rdmsr -x0 0x%x" % msr)
    out = out.strip()
    if status != 0:
        raise RuntimeError(
            "rdmsr failed for MSR 0x%x (exit=%s): %s" % (msr, status, out)
        )
    try:
        return int(out, 16)
    except ValueError:
        raise RuntimeError(
            "rdmsr returned non-hex output for MSR 0x%x: %r" % (msr, out)
        )


def detect_guest_lmce(session):
    """Return ``"on"`` if all three LMCE-enabling bits are set in guest, else ``"off"``.

    Reads are done in dependency order and short-circuited: ``IA32_MCG_EXT_CTL``
    (0x4D0) is only architecturally present when ``IA32_MCG_CAP.LMCE_P`` is 1,
    so ``MCG_CAP`` must be checked first.
    """
    session.cmd("modprobe msr")
    if not (rdmsr_hex(session, IA32_MCG_CAP) & MCG_LMCE_P_MASK):
        return "off"
    if not (rdmsr_hex(session, IA32_FEATURE_CONTROL) & FEATURE_LMCE_ON_MASK):
        return "off"
    if not (rdmsr_hex(session, IA32_MCG_EXT_CTL) & MCG_EXT_CTL_LMCE_EN_MASK):
        return "off"
    return "on"


def check_lmce_state(test, session, expected_state):
    """Verify guest LMCE MSR state matches ``expected_state`` (``"on"`` or ``"off"``)."""
    state = detect_guest_lmce(session)
    if state != expected_state:
        test.fail(
            "Guest LMCE state %s does not match expected %s" % (state, expected_state)
        )
    test.log.info("Guest LMCE state is '%s' as expected.", state)


def check_lmce_marker(test, dmesg, expected_state):
    """Assert LMCE dmesg marker is consistent with ``expected_state``.

    ``lmce=off`` -> guest dmesg must NOT contain ``LMCE`` / ``Local Machine``.
      This catches KVM incorrectly reporting a broadcast MCE as local.
    ``lmce=on``  -> presence of the marker is desirable but not required.
      The Linux kernel only prints the ``Local Machine Check Exception``
      banner when it takes the synchronous #MC handler path (AR/PANIC
      severity). SRAO / recoverable events go through the deferred
      workqueue path which emits only ``Machine check events logged``.
      MSR-level LMCE readiness is already verified by check_lmce_state();
      here we only warn when the banner is absent.
    """
    has_lmce = "LMCE" in dmesg or "Local Machine" in dmesg
    if expected_state == "off" and has_lmce:
        test.fail("lmce=off but guest dmesg shows LMCE marker: %s" % dmesg)
    if expected_state == "on" and not has_lmce:
        test.log.info(
            "lmce=on: no explicit LMCE banner in dmesg (deferred-log path); "
            "MSR state already confirmed. dmesg=%s",
            dmesg,
        )


def build_victim(test, params, vm, session):
    """Compile the ``victim`` helper from ``deps/ras/`` inside the guest.

    ``victim`` mmaps a page, prints its guest physical address, then either
    consumes the page immediately (for SRAO) or polls a trigger file (for
    SRAR / EINJ). Both lmce.py (HMP path) and ras.py (real EINJ path) need
    this binary compiled at the same guest path.

    Returns the absolute path to the compiled binary inside the guest.
    """
    source_file = params["source_file"]
    exec_file = params["exec_file"]
    test_dir = params["test_dir"]
    deps_dir = virttest_data_dir.get_deps_dir("ras")
    if not utils_package.package_install("gcc", session):
        test.cancel("Failed to install gcc inside guest.")
    vm.copy_files_to(os.path.join(deps_dir, source_file), test_dir)
    compile_cmd = "cd %s && gcc %s -o %s" % (test_dir, source_file, exec_file)
    if session.cmd_status(compile_cmd) != 0:
        test.error("Failed to compile %s inside guest." % source_file)
    session.cmd("rm -f %s/%s" % (test_dir, source_file))
    return os.path.join(test_dir, exec_file)


def parse_victim_gpa(session, log_path):
    """Return the GPA printed by ``victim`` in ``log_path`` as an ``int``.

    ``victim`` prints ``physical address of (0xVA) = 0xGPA``; we anchor on
    the ``physical address`` / ``=`` markers rather than a positional token
    so extra banner lines do not break the parser. Returns ``None`` if the
    log has not yet been written or the address cannot be decoded.
    """
    out = session.cmd_output("cat %s 2>/dev/null || true" % log_path)
    for line in out.splitlines():
        if "physical address" in line.lower() and "=" in line:
            try:
                return int(line.rsplit("=", 1)[-1].strip(), 0)
            except ValueError:
                continue
    return None
