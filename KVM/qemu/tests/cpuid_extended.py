#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

"""
Verify guest CPUID extended leaves return expected values.

Boots a guest and checks specific CPUID leaves (e.g. 0x80000005,
0x80000006) against expected register values configured in params.
"""

from provider import dmesg_router  # pylint: disable=unused-import
from virttest import env_process
from virttest import error_context


def _read_cpuid_leaf(session, leaf):
    """
    Read a CPUID leaf inside the guest using cpuid command.

    :param session: guest login session
    :param leaf: leaf number as string (e.g. "0x80000005")
    :return: dict with keys eax, ebx, ecx, edx as integers
    """
    output = session.cmd_output("cpuid -1 -r -l %s" % leaf).strip()
    regs = {"eax": 0, "ebx": 0, "ecx": 0, "edx": 0}
    for line in output.splitlines():
        if "eax=" not in line:
            continue
        # Parse line like: 0x80000005 0x00: eax=0x00000000 ebx=...
        for reg in regs:
            idx = line.find("%s=" % reg)
            if idx >= 0:
                start = idx + len(reg) + 1
                val_str = line[start:].split()[0]
                regs[reg] = int(val_str, 16)
        break  # only first subleaf
    return regs


@error_context.context_aware
def run(test, params, env):
    """
    Check guest CPUID extended leaf register values.

    Steps:
        1. Boot guest with configured CPU model.
        2. Read the specified CPUID leaf inside guest.
        3. Compare each register against expected values.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """
    cpuid_leaf = params["cpuid_leaf"]
    login_timeout = params.get_numeric("login_timeout", 240)

    params["start_vm"] = "yes"
    vm_name = params["main_vm"]
    env_process.preprocess_vm(test, params, env, vm_name)
    vm = env.get_vm(vm_name)
    vm.verify_alive()

    session = vm.wait_for_login(timeout=login_timeout)
    try:
        error_context.context("Read CPUID leaf %s in guest" % cpuid_leaf, test.log.info)
        regs = _read_cpuid_leaf(session, cpuid_leaf)
        test.log.info(
            "Guest CPUID %s: eax=0x%x ebx=0x%x ecx=0x%x edx=0x%x",
            cpuid_leaf,
            regs["eax"],
            regs["ebx"],
            regs["ecx"],
            regs["edx"],
        )

        failures = []
        for reg_name in ("eax", "ebx", "ecx", "edx"):
            expected_key = "expected_%s" % reg_name
            if params.get(expected_key) is not None:
                expected = params.get_numeric(expected_key)
                if regs[reg_name] != expected:
                    failures.append(
                        "%s: got 0x%x, expected 0x%x"
                        % (reg_name, regs[reg_name], expected)
                    )

        if failures:
            test.fail("CPUID %s mismatch:\n  " % cpuid_leaf + "\n  ".join(failures))
        test.log.info("CPUID %s check passed", cpuid_leaf)
    finally:
        session.close()
