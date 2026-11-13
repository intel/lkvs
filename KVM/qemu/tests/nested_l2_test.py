#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation
#
# Nested L2 hardware feature validation (PKU, vPMU, CET SHSTK).
#
# Reuses nested_boot infrastructure to boot L2 inside L1, then runs
# a feature-specific test inside L2. See nested_boot.py for the
# shared nested KVM boot flow.

import logging
import os
import re
import tarfile
import tempfile

from virttest import data_dir
from virttest import error_context

from provider.cpu_utils import check_cpu_flags
from provider.test_utils import get_baremetal_dir

import feature_test
import nested_boot

LOG = logging.getLogger("avocado.test." + __name__)


# ---------- L1->L2 SCP helper ----------

def _scp_to_l2(session, ssh_port, password, src, dst, timeout=60):
    """SCP a file from L1 into L2."""
    scp_cmd = (
        "sshpass -p '%s' scp -P %s "
        "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
        "-o ConnectTimeout=5 %s root@localhost:%s 2>/dev/null"
        % (password, ssh_port, src, dst)
    )
    session.cmd(scp_cmd, timeout=timeout)


def _ssh_l2_status(session, ssh_port, password, command, timeout=120):
    """Run a command in L2 and return (exit status or None, output)."""
    out = nested_boot._ssh_l2(session, ssh_port, password,
                              "(%s) 2>&1; echo LKVS_RC=$?" % command,
                              timeout=timeout)
    match = re.search(r"LKVS_RC=(\d+)\s*$", out)
    if not match:
        return None, out
    return int(match.group(1)), out[:match.start()]


# ---------- Feature tests inside L2 ----------

def _run_pku_test(test, session, vm, ssh_port, password):
    error_context.context("Verify PKU flag in L2 /proc/cpuinfo", LOG.info)
    r = nested_boot._ssh_l2(session, ssh_port, password,
                            "grep -q pku /proc/cpuinfo && echo PKU_OK")
    if "PKU_OK" not in r:
        test.fail("PKU flag not present in L2 /proc/cpuinfo")

    error_context.context("Copy pku_test.c into L2 and compile", LOG.info)
    deps_dir = data_dir.get_deps_dir("nested_l2_test")
    pku_src = os.path.join(deps_dir, "pku_test.c")
    vm.copy_files_to(pku_src, "/tmp/pku_test.c")
    _scp_to_l2(session, ssh_port, password,
               "/tmp/pku_test.c", "/tmp/pku_test.c")
    build = nested_boot._ssh_l2(session, ssh_port, password,
                                "cd /tmp && gcc -o pku_test pku_test.c 2>&1")
    if "error" in build.lower():
        test.fail("Failed to compile pku_test in L2: %s" % build)

    error_context.context("Run PKU selftest in L2", LOG.info)
    out = nested_boot._ssh_l2(session, ssh_port, password,
                              "/tmp/pku_test 2>&1")
    LOG.info("L2 PKU test output:\n%s", out)
    if "all tests OK" not in out:
        test.fail("PKU selftest did not report success in L2")


def _run_vpmu_test(test, session, ssh_port, password):
    error_context.context("Install perf in L2", LOG.info)
    install = nested_boot._ssh_l2(
        session, ssh_port, password,
        "which perf >/dev/null 2>&1 || "
        "dnf install -y perf >/dev/null 2>&1 || "
        "apt-get install -y linux-tools-common linux-tools-generic "
        ">/dev/null 2>&1; which perf",
        timeout=300,
    )
    if "/perf" not in install:
        test.fail("Could not install/find perf in L2")

    events = [
        "cpu-cycles",
        "instructions",
        "ref-cycles",
        "branch-instructions",
        "branch-misses",
    ]
    for event in events:
        error_context.context("Run perf stat -e %s in L2" % event,
                              LOG.info)
        out = nested_boot._ssh_l2(
            session, ssh_port, password,
            "perf stat -e %s -- sleep 1 2>&1" % event,
            timeout=60,
        )
        LOG.info("L2 perf [%s] output:\n%s", event, out)
        if "<not supported>" in out:
            test.fail("PMU event %s reported <not supported> in L2" % event)
        # Verify counter is non-zero
        found = False
        for line in out.splitlines():
            parts = line.strip().split()
            if len(parts) >= 2 and parts[1] == event:
                try:
                    if int(parts[0].replace(",", "")) > 0:
                        found = True
                        break
                except ValueError:
                    continue
        if not found:
            test.fail("PMU event %s returned zero or unparseable in L2: %s"
                      % (event, out))


def _pack_cet_payload(bm_dir, bm_paths):
    """Tar the BM pieces needed by BM/cet, skipping prebuilt binaries."""
    def _skip_built(info):
        if not info.isfile():
            return info
        if info.name.endswith((".o", ".ko")):
            return None
        src = os.path.join(os.path.dirname(bm_dir), info.name)
        with open(src, "rb") as f:
            if f.read(4) == b"\x7fELF":
                return None
        return info

    fd, tar_path = tempfile.mkstemp(suffix=".tar.gz")
    os.close(fd)
    with tarfile.open(tar_path, "w:gz") as tar:
        for rel in bm_paths:
            tar.add(os.path.join(bm_dir, rel),
                    arcname=os.path.join("BM", rel), filter=_skip_built)
    return tar_path


def _run_cet_shstk_test(test, params, session, vm, ssh_port, password):
    cet_flags = params.get("cet_flags", "user_shstk")
    error_context.context("Verify CET flags %s in L1" % cet_flags, LOG.info)
    check_cpu_flags(params, cet_flags, test, session)

    error_context.context("Verify CET flags %s in L2" % cet_flags, LOG.info)
    out = nested_boot._ssh_l2(session, ssh_port, password,
                              "lscpu | grep Flags")
    missing = [f for f in cet_flags.split() if f not in out.split()]
    if missing:
        test.fail("Flag %s not in L2" % missing)

    error_context.context("Install gcc/make in L2", LOG.info)
    _ssh_l2_status(session, ssh_port, password,
                   "command -v gcc && command -v make || "
                   "dnf install -y gcc make || "
                   "apt-get install -y gcc make", timeout=600)
    rc, out = _ssh_l2_status(session, ssh_port, password,
                             "command -v gcc && command -v make")
    if rc != 0:
        test.error("Could not install/find gcc and make in L2: %s" % out)

    error_context.context("Copy BM/cet payload into L2", LOG.info)
    l2_cet_root = params["cet_l2_root"]
    payload = params["cet_payload"]
    bm_dir = get_baremetal_dir(params)
    tar_path = _pack_cet_payload(bm_dir, params.objects("cet_bm_paths"))
    try:
        vm.copy_files_to(tar_path, payload)
    finally:
        os.remove(tar_path)
    _scp_to_l2(session, ssh_port, password, payload, payload)
    session.cmd("rm -f %s" % payload, ignore_all_errors=True)
    rc, out = _ssh_l2_status(session, ssh_port, password,
                             "rm -rf %s && mkdir -p %s && tar xzf %s -C %s"
                             % (l2_cet_root, l2_cet_root, payload,
                                l2_cet_root))
    if rc != 0:
        test.error("Failed to extract BM/cet payload in L2: %s" % out)

    l2_bm = l2_cet_root + "/BM"
    feature_path = l2_bm + "/cet"
    error_context.context("Build cpuid_check and CET tests in L2", LOG.info)
    for build in ("cd %s/tools/cpuid_check && make" % l2_bm,
                  "cd %s && make %s" % (feature_path,
                                        params["cet_make_targets"])):
        rc, out = _ssh_l2_status(session, ssh_port, password, build,
                                 timeout=300)
        if rc != 0:
            test.error("Build failed in L2 (%s):\n%s" % (build, out))

    scen = params.get("cet_test_scen", "tests-shstk")
    with open(os.path.join(bm_dir, "cet", scen)) as f:
        lines = f.read().splitlines()

    # Same PATH layout and dependency header semantics as feature_test.
    env_prefix = ('PATH="$PATH:%s:%s/common:%s/tools/cpuid_check"'
                  % (feature_path, l2_bm, l2_bm))
    subtest_timeout = params.get_numeric("cet_subtest_timeout", 120)
    subtests = []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        kind, dep_cmd, reason = feature_test._parse_dep_line(line)
        if kind is not None:
            if dep_cmd is None:
                continue
            rc, _ = _ssh_l2_status(session, ssh_port, password,
                                   "cd %s && %s %s"
                                   % (feature_path, env_prefix, dep_cmd))
            if rc == 0:
                continue
            reason = reason or dep_cmd
            if kind == "other_warn":
                LOG.warning("L2 scenario %s dependency warning: %s",
                            scen, reason)
                continue
            if kind == "hw_dep":
                # Host and L1 expose CET, so missing CPUID in L2 is a
                # nested CET virtualization failure, not an unsupported host.
                test.fail("L2 missing CET hardware dependency: %s" % reason)
            test.cancel("L2 cannot run scenario %s: %s" % (scen, reason))
        if stripped.startswith("#"):
            continue
        subtests.append(stripped)

    if not subtests:
        test.error("Scenario %s has no runnable subtests" % scen)

    failures = []
    total = len(subtests)
    for idx, cmd in enumerate(subtests, 1):
        error_context.context("[L2 %s %d/%d] %s" % (scen, idx, total, cmd),
                              LOG.info)
        rc, out = _ssh_l2_status(
            session, ssh_port, password,
            "cd %s && %s timeout %d %s"
            % (feature_path, env_prefix, subtest_timeout, cmd),
            timeout=subtest_timeout + 30)
        if rc != 0:
            failures.append(cmd)
            LOG.warning("[L2 %s %d/%d] FAIL rc=%s\n%s",
                        scen, idx, total, rc, out.strip())

    if failures:
        test.fail("CET %s failed in L2: %d/%d subtests failed: %s"
                  % (scen, len(failures), total, failures))
    LOG.info("CET %s passed in L2: %d/%d subtests", scen, total, total)


# ---------- Entry point ----------

@error_context.context_aware
def run(test, params, env):
    """Nested L2 feature test (PKU, vPMU or CET SHSTK) using L2 image as
    L1's vdb."""
    l2_state = None
    session = None
    l2_booted = False
    ssh_port = params.get_numeric("l2_ssh_port", 2222)
    password = params.get("password", "")
    l2_test_type = params.get("l2_test_type")

    if l2_test_type == "cet_shstk":
        error_context.context("Verify host CET flags", LOG.info)
        check_cpu_flags(params, params.get("cet_flags", "user_shstk"), test)

    try:
        error_context.context("Prepare L2 image on host", LOG.info)
        l1_image = nested_boot._get_l1_image_path(test, params)
        l2_state = nested_boot._prepare_l2_image(params, l1_image)

        error_context.context("Attach L2 image as vdb to L1", LOG.info)
        nested_boot._attach_l2_as_vdb(params, l2_state["l2_image_base"],
                                      l2_state["l2_image_format"])

        error_context.context("Boot L1 guest (with vdb=L2 image)", LOG.info)
        vm = env.get_vm(params["main_vm"])
        vm.create(params=params)
        vm.verify_alive()
        session = vm.wait_for_login(timeout=params.get_numeric("login_timeout"))

        error_context.context("Verify nested KVM in L1", LOG.info)
        nested_boot._l1_verify_kvm(session, test)

        error_context.context("Install QEMU/sshpass in L1", LOG.info)
        if not nested_boot._l1_install_deps(session):
            test.error("Cannot install required packages in L1 "
                       "(check L1 network / repos)")

        error_context.context("Copy host QEMU binary to L1", LOG.info)
        nested_boot._l1_copy_host_qemu(vm, session, params)

        error_context.context("Locate L2 passthrough disk in L1", LOG.info)
        l2_dev = nested_boot._l1_find_l2_disk(session)
        if not l2_dev:
            test.error("L2 disk not found in L1 (expected /dev/vdb or "
                       "another virtio-blk device besides /dev/vda)")
        LOG.info("L2 block device inside L1: %s", l2_dev)

        error_context.context("Boot L2 QEMU inside L1", LOG.info)
        nested_boot._boot_l2(session, params, l2_dev,
                             l2_state["l2_image_format"])
        l2_booted = True

        boot_timeout = params.get_numeric("l2_boot_timeout", 180)
        error_context.context("Wait for L2 sshd (timeout %ds)"
                              % boot_timeout, LOG.info)
        if not nested_boot._wait_l2_ssh(session, ssh_port, password,
                                        boot_timeout):
            l2_log = session.cmd_output("tail -80 /tmp/l2_serial.log "
                                        "2>/dev/null", timeout=15)
            LOG.info("L2 serial tail:\n%s", l2_log)
            test.fail("L2 SSH did not become ready within %ds" % boot_timeout)

        error_context.context("Run L2 feature test: %s" % l2_test_type,
                              LOG.info)
        if l2_test_type == "pku":
            _run_pku_test(test, session, vm, ssh_port, password)
        elif l2_test_type == "vpmu":
            _run_vpmu_test(test, session, ssh_port, password)
        elif l2_test_type == "cet_shstk":
            _run_cet_shstk_test(test, params, session, vm, ssh_port,
                                password)
        else:
            test.error("Unknown l2_test_type: %s" % l2_test_type)

    finally:
        if l2_booted and session is not None:
            try:
                nested_boot._shutdown_l2(session, ssh_port, password)
            except Exception as e:
                LOG.warning("L2 shutdown error: %s", e)
        nested_boot._cleanup_l2_image(l2_state)
