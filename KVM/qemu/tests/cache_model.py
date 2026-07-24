#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

"""
Verify guest cache topology matches host cache share scope.

Boots a guest with a specific CPU model and SMP topology, then compares
the cache sharing scope (per-core, per-module, per-socket) between host
and guest for each cache index. When ``cpuid_cache_expect`` is set, also
verifies the guest CPUID.4 sharing / associativity fields for cache 0..3
against the expected values (parallels XVS ``check_cpuid_cache_info``).
"""

import re

from provider import dmesg_router  # pylint: disable=unused-import
from avocado.utils import process
from virttest import env_process
from virttest import error_context
from virttest import utils_package


def _get_cache_share_scope(session=None):
    """
    Determine cache share scope for each cache index (0-3).

    Returns a dict: {index: scope} where scope is one of:
        1 = per core, 2 = per cluster, 3 = per die, 4 = per socket

    :param session: guest session or None for host
    """

    def run_cmd(cmd):
        if session:
            return session.cmd_output(cmd).strip()
        return process.run(cmd, shell=True).stdout_text.strip()

    scopes = {}
    for index in range(4):
        base = "/sys/devices/system/cpu/cpu0/cache/index%d" % index
        try:
            shared_cpu_list = run_cmd("cat %s/shared_cpu_list" % base)
        except Exception:
            break

        if not shared_cpu_list:
            break

        # Parse CPU list into individual CPU numbers
        cpus = []
        for part in shared_cpu_list.split(","):
            part = part.strip()
            if not part:
                continue
            m = re.match(r"(\d+)-(\d+)", part)
            if m:
                cpus.extend(range(int(m.group(1)), int(m.group(2)) + 1))
            else:
                cpus.append(int(part))

        # Collect topology IDs
        core_ids = set()
        cluster_ids = set()
        die_ids = set()
        socket_ids = set()
        for cpu in cpus:
            topo = "/sys/devices/system/cpu/cpu%d/topology" % cpu
            core_ids.add(run_cmd("cat %s/core_id" % topo))
            cluster_ids.add(run_cmd("cat %s/cluster_id 2>/dev/null || echo x" % topo))
            die_ids.add(run_cmd("cat %s/die_id 2>/dev/null || echo x" % topo))
            socket_ids.add(run_cmd("cat %s/physical_package_id" % topo))

        if len(core_ids) == 1:
            scopes[index] = 1
        elif len(cluster_ids) == 1:
            scopes[index] = 2
        elif len(die_ids) == 1:
            scopes[index] = 3
        elif len(socket_ids) == 1:
            scopes[index] = 4
        else:
            scopes[index] = 0  # unknown

    return scopes


def _parse_guest_cpuid_cache(session):
    """
    Parse ``cpuid -1`` output in guest for cache 0..3 sharing/assoc fields.

    Extracts the hex value of:
      - "maximum IDs for CPUs sharing cache"  (CPUID.4:EAX[25:14] + 1)
      - "ways of associativity"               (CPUID.4:EBX[31:22] + 1)
    within each ``--- cache N ---`` block, for N in 0..3.

    :param session: guest session
    :return: dict {index: {"sharing": "0x1", "assoc": "0x8"}}, or None if
             the ``cpuid`` command failed or returned no cache blocks.
    """
    status, output = session.cmd_status_output("cpuid -1", timeout=60)
    if status != 0 or not output.strip():
        return None

    result = {}
    current = None
    header_re = re.compile(r"^\s*---\s*cache\s+(\d+)\s*---\s*$")
    # Value token after '=' is the first whitespace-separated field.
    val_re = re.compile(r"=\s*(\S+)")
    for line in output.splitlines():
        m = header_re.match(line)
        if m:
            idx = int(m.group(1))
            current = idx if 0 <= idx <= 3 else None
            if current is not None:
                result.setdefault(current, {})
            continue
        if current is None:
            continue
        if "maximum IDs for CPUs sharing cache" in line:
            mv = val_re.search(line)
            if mv:
                result[current]["sharing"] = mv.group(1)
        elif "ways of associativity" in line:
            mv = val_re.search(line)
            if mv:
                result[current]["assoc"] = mv.group(1)
    return result or None


def _hex_eq(a, b):
    """Compare two hex strings (e.g. '0x1f' vs '0x1F') by numeric value."""
    try:
        return int(a, 16) == int(b, 16)
    except (TypeError, ValueError):
        return False


@error_context.context_aware
def run(test, params, env):
    """
    Compare host and guest cache share scope.

    Steps:
        1. Collect host cache share scope for each cache index.
        2. Boot guest with configured CPU model and SMP topology.
        3. Collect guest cache share scope.
        4. Compare and fail if any mismatch.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """
    error_context.context("Collect host cache share scope", test.log.info)
    host_scopes = _get_cache_share_scope()
    test.log.info("Host cache scopes: %s", host_scopes)
    if not host_scopes:
        test.cancel("Could not determine host cache topology")

    # Force SMP topology. avocado-vt's cartesian config loads guest-hw.cfg
    # (which owns the 'smp2' variant) AFTER subtests.cfg, so any 'smp = N'
    # set in the cfg gets clobbered by the outer smp variant. Override here
    # so QEMU sees the topology we actually want:
    #   sockets * dies * modules * cores * threads = 2*1*2*16*2 = 128
    # avocado-vt has no 'modules' knob, so 'modules=2' is appended via
    # extra_params; QEMU merges both -smp options at parse time.
    smp = params.get_numeric("vcpu_maxcpus") or 128
    params["smp"] = str(smp)
    params["vcpu_maxcpus"] = str(smp)
    params.setdefault("vcpu_dies", "1")

    params["start_vm"] = "yes"
    vm_name = params["main_vm"]
    env_process.preprocess_vm(test, params, env, vm_name)
    vm = env.get_vm(vm_name)
    vm.verify_alive()

    login_timeout = params.get_numeric("login_timeout", 240)
    session = vm.wait_for_login(timeout=login_timeout)
    try:
        error_context.context("Collect guest cache share scope", test.log.info)
        guest_scopes = _get_cache_share_scope(session)
        test.log.info("Guest cache scopes: %s", guest_scopes)

        if not guest_scopes:
            test.fail("Could not determine guest cache topology")

        mismatches = []
        for idx in host_scopes:
            if idx not in guest_scopes:
                mismatches.append(
                    "cache index %d: present on host (scope=%d) but missing in guest"
                    % (idx, host_scopes[idx])
                )
            elif host_scopes[idx] != guest_scopes[idx]:
                mismatches.append(
                    "cache index %d: host scope=%d, guest scope=%d"
                    % (idx, host_scopes[idx], guest_scopes[idx])
                )

        if mismatches:
            test.fail("Cache topology mismatch:\n  " + "\n  ".join(mismatches))
        test.log.info("Cache topology matches between host and guest")

        expect_raw = params.get("cpuid_cache_expect", "").strip()
        if expect_raw:
            error_context.context(
                "Verify guest CPUID.4 cache sharing / associativity",
                test.log.info,
            )
            tokens = expect_raw.split()
            if len(tokens) != 8:
                test.error(
                    "cpuid_cache_expect must have 8 hex tokens "
                    "(c0_sharing c0_assoc ... c3_sharing c3_assoc), got: %s"
                    % expect_raw
                )
            expect = {
                i: {"sharing": tokens[i * 2], "assoc": tokens[i * 2 + 1]}
                for i in range(4)
            }

            # Ensure the `cpuid` tool is available in guest.
            cpuid_pkg = params.get("cpuid_pkg", "cpuid")
            if session.cmd_status("which cpuid") != 0:
                if not utils_package.package_install(cpuid_pkg, session):
                    test.cancel(
                        "Failed to install '%s' package in guest; "
                        "cannot verify CPUID.4 cache descriptors" % cpuid_pkg
                    )
                if session.cmd_status("which cpuid") != 0:
                    test.error(
                        "'cpuid' tool still not found in guest after "
                        "installing package '%s'" % cpuid_pkg
                    )

            guest_cpuid = _parse_guest_cpuid_cache(session)
            if guest_cpuid is None:
                test.error(
                    "Failed to run 'cpuid -1' in guest or output was empty"
                )
            test.log.info("Guest CPUID.4 cache info: %s", guest_cpuid)

            cpuid_mismatches = []
            for idx in range(4):
                got = guest_cpuid.get(idx)
                if not got:
                    cpuid_mismatches.append(
                        "cache %d: missing from guest cpuid output" % idx
                    )
                    continue
                for field in ("sharing", "assoc"):
                    exp_val = expect[idx][field]
                    got_val = got.get(field)
                    if not _hex_eq(exp_val, got_val):
                        cpuid_mismatches.append(
                            "cache %d %s: expected %s, got %s"
                            % (idx, field, exp_val, got_val)
                        )
            if cpuid_mismatches:
                test.fail(
                    "Guest CPUID.4 cache info mismatch:\n  "
                    + "\n  ".join(cpuid_mismatches)
                )
            test.log.info("Guest CPUID.4 cache info matches expected values")
    finally:
        session.close()
