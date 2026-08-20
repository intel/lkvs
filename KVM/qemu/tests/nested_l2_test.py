#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation
#
# Nested L2 hardware feature validation (PKU, vPMU).
#
# Reuses nested_boot infrastructure to boot L2 inside L1, then runs
# a feature-specific test inside L2. See nested_boot.py for the
# shared nested KVM boot flow.

import logging
import os

from virttest import data_dir
from virttest import error_context

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


# ---------- Entry point ----------

@error_context.context_aware
def run(test, params, env):
    """Nested L2 feature test (PKU or vPMU) using L2 image as L1's vdb."""
    l2_state = None
    session = None
    l2_booted = False
    ssh_port = params.get_numeric("l2_ssh_port", 2222)
    password = params.get("password", "")

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
        session = vm.wait_for_login(timeout=360)

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

        l2_test_type = params.get("l2_test_type")
        error_context.context("Run L2 feature test: %s" % l2_test_type,
                              LOG.info)
        if l2_test_type == "pku":
            _run_pku_test(test, session, vm, ssh_port, password)
        elif l2_test_type == "vpmu":
            _run_vpmu_test(test, session, ssh_port, password)
        else:
            test.error("Unknown l2_test_type: %s" % l2_test_type)

    finally:
        if l2_booted and session is not None:
            try:
                nested_boot._shutdown_l2(session, ssh_port, password)
            except Exception as e:
                LOG.warning("L2 shutdown error: %s", e)
        nested_boot._cleanup_l2_image(l2_state)
