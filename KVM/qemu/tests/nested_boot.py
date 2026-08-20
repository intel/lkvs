#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation
#
# Nested KVM boot validation.
#
# Boots an L2 guest inside an L1 KVM guest using a copied L2 image
# attached to L1 as a virtio-blk device (/dev/vdb). No NFS or
# initramfs is required. Both raw and qcow2 images are supported.
#
# Flow:
#   1. Resolve the L1 image path and verify it exists (cancel if not).
#      Nested KVM is enabled on the host via the cfg pre_command before
#      this test runs.
#   2. Host: copy L1 image to L2 image (preserving original format).
#      Attach the L2 image as image2 (virtio-blk) via avocado-vt params
#      so L1 sees it as /dev/vdb.
#   3. Boot L1.
#   4. In L1: install qemu-kvm + sshpass, launch nested QEMU booted
#      from /dev/vdb with user-mode NAT and hostfwd :2222->:22.
#   5. L1 ssh to L2 (localhost:2222) using L1's root password.
#   6. Verify basic L2 responsiveness (uname).
#   7. Cleanup: shutdown L2, remove L2 image file.

import logging
import os
import re
import time

from avocado.utils import process
from virttest import data_dir
from virttest import error_context
from virttest import storage
from virttest import utils_package

LOG = logging.getLogger("avocado.test." + __name__)


# ---------- Host-side helpers ----------

def _get_l1_image_path(test, params):
    """Resolve the L1 image path and cancel the test if it is missing.
    Nested KVM is enabled on the host via the cfg pre_command before
    the test starts."""
    image_params = params.object_params("image1")
    l1_image = storage.get_image_filename(image_params,
                                          data_dir.get_data_dir())
    if not os.path.isfile(l1_image):
        test.cancel("L1 image not found: %s" % l1_image)
    return l1_image


def _detect_image_format(image_path):
    """Return 'raw' or 'qcow2' by probing the file with `qemu-img info`."""
    r = process.run("qemu-img info %s" % image_path,
                    ignore_status=True, shell=True)
    if r.exit_status == 0:
        m = re.search(r"^file format:\s*(\S+)",
                      r.stdout_text, re.MULTILINE)
        if m:
            return m.group(1)
    try:
        with open(image_path, "rb") as f:
            head = f.read(4)
        if head == b"QFI\xfb":
            return "qcow2"
    except OSError:
        pass
    return "raw"


def _prepare_l2_image(params, l1_image_path):
    """Copy L1 image to L2 in the same host directory, preserving format."""
    l1_dir = os.path.dirname(l1_image_path)
    l1_fmt = _detect_image_format(l1_image_path)
    if l1_fmt not in ("raw", "qcow2"):
        raise RuntimeError(
            "Unsupported L1 image format %r (only raw/qcow2 supported)"
            % l1_fmt)

    ext = ".qcow2" if l1_fmt == "qcow2" else ".raw"
    l2_base = params.get("l2_image_basename", "l2_guest")
    l2_image_path = os.path.join(l1_dir, l2_base + ext)

    if os.path.exists(l2_image_path):
        os.remove(l2_image_path)

    LOG.info("cp --reflink L1 %s -> L2: %s -> %s",
             l1_fmt, l1_image_path, l2_image_path)
    process.run(
        "cp --reflink=auto -f %s %s" % (l1_image_path, l2_image_path),
        shell=True, timeout=600
    )

    return {
        "l2_image_path": l2_image_path,
        "l2_image_base": os.path.join(l1_dir, l2_base),
        "l2_image_format": l1_fmt,
    }


def _attach_l2_as_vdb(params, l2_image_base, l2_format):
    """Mutate params so avocado-vt attaches L2 as image2 (virtio-blk)."""
    imgs = params.get("images", "image1").split()
    if "image2" not in imgs:
        imgs.append("image2")
    params["images"] = " ".join(imgs)
    params["image_name_image2"] = l2_image_base
    params["image_format_image2"] = l2_format
    params["image_snapshot_image2"] = "no"
    params["create_image_image2"] = "no"
    params["force_create_image_image2"] = "no"
    params["remove_image_image2"] = "no"
    params["check_image_image2"] = "no"
    params["drive_format_image2"] = "virtio"


def _cleanup_l2_image(state):
    if not state:
        return
    l2 = state.get("l2_image_path")
    if l2 and os.path.exists(l2):
        try:
            os.remove(l2)
            LOG.info("Removed L2 image: %s", l2)
        except OSError as e:
            LOG.warning("Failed to remove L2 image %s: %s", l2, e)


# ---------- L1-side helpers ----------

def _l1_find_l2_disk(session):
    r = session.cmd_output("ls /dev/vdb 2>/dev/null; true", timeout=15)
    if "/dev/vdb" in r:
        return "/dev/vdb"
    r = session.cmd_output(
        "ls /dev/vd? 2>/dev/null | grep -v '/dev/vda' | head -1",
        timeout=15
    )
    dev = r.strip().splitlines()[-1] if r.strip() else ""
    if not dev:
        return None
    return dev


def _l1_install_deps(session):
    """Install qemu and sshpass in L1. Return False on failure."""
    if not (utils_package.package_install("qemu-kvm", session) or
            utils_package.package_install("qemu-system-x86", session)):
        return False
    if not utils_package.package_install("sshpass", session):
        return False
    return True


def _l1_copy_host_qemu(vm, session, params):
    """Copy host qemu binary and its data dir into L1."""
    host_qemu = vm.qemu_binary
    l1_qemu_path = "/usr/local/bin/qemu-system-x86_64"
    vm.copy_files_to(host_qemu, l1_qemu_path)
    session.cmd("chmod +x %s" % l1_qemu_path, timeout=10)

    # Copy QEMU data directory (BIOS, firmware ROMs) so the binary
    # can find bios-256k.bin and other required files inside L1.
    r = process.run("%s -L help" % host_qemu,
                    ignore_status=True, shell=True, timeout=10)
    for line in r.stdout_text.splitlines():
        path = line.strip()
        if path and os.path.isdir(path) and "share" in path:
            session.cmd("mkdir -p /usr/local/share", timeout=10)
            session.cmd("rm -rf /usr/local/share/qemu", timeout=10)
            vm.copy_files_to(path, "/usr/local/share/")
            break


def _l1_verify_kvm(session, test):
    """Ensure /dev/kvm is present in L1 (nested KVM is enabled)."""
    if session.cmd_status("test -e /dev/kvm") != 0:
        # Try loading module in case L1 didn't auto-load it. nested=1 is
        # not needed here: L1 only runs L2, not a further L3.
        session.cmd("modprobe kvm_intel 2>/dev/null; true",
                    timeout=60, ignore_all_errors=True)
        if session.cmd_status("test -e /dev/kvm") != 0:
            test.fail("/dev/kvm not present in L1 - nested KVM unavailable")


def _boot_l2(session, params, l2_block_dev, l2_fmt="raw"):
    """Boot L2 QEMU (daemonized) inside L1 using a block device."""
    l2_mem = params.get("l2_mem", "2048")
    l2_smp = params.get("l2_smp", "2")
    l2_cpu_flags = params.get("l2_cpu_flags", "")
    ssh_port = params.get_numeric("l2_ssh_port", 2222)

    cpu_opt = "host"
    if l2_cpu_flags:
        cpu_opt = "host,%s" % l2_cpu_flags

    qemu_bin = "/usr/local/bin/qemu-system-x86_64"
    qemu_datadir = "/usr/local/share/qemu"
    session.cmd("rm -f /tmp/l2_serial.log /tmp/l2.pid")
    cmd = (
        "%s -L %s -accel kvm -cpu %s -m %s -smp %s "
        "-drive file=%s,format=%s,if=virtio,cache=none,aio=native "
        "-netdev user,id=n0,hostfwd=tcp::%s-:22 "
        "-device virtio-net,netdev=n0 "
        "-display none -monitor none "
        "-serial file:/tmp/l2_serial.log "
        "-daemonize -pidfile /tmp/l2.pid"
        % (qemu_bin, qemu_datadir, cpu_opt, l2_mem, l2_smp,
           l2_block_dev, l2_fmt, ssh_port)
    )
    LOG.info("Starting L2 QEMU: %s", cmd)
    session.cmd(cmd, timeout=60)
    return ssh_port


def _ssh_l2(session, ssh_port, password, command, timeout=120):
    """Run a command in L2 via SSH from L1. Return stdout."""
    escaped = command.replace("'", "'\"'\"'")
    ssh_cmd = (
        "sshpass -p '%s' ssh -p %s "
        "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
        "-o ConnectTimeout=5 root@localhost '%s' 2>/dev/null"
        % (password, ssh_port, escaped)
    )
    return session.cmd_output(ssh_cmd, timeout=timeout)


def _wait_l2_ssh(session, ssh_port, password, timeout):
    """Poll until L2 SSH is reachable or timeout expires."""
    end = time.time() + timeout
    while time.time() < end:
        r = _ssh_l2(session, ssh_port, password,
                    "echo L2_SSH_READY", timeout=15)
        if "L2_SSH_READY" in r:
            return True
        time.sleep(5)
    return False


def _shutdown_l2(session, ssh_port, password):
    try:
        _ssh_l2(session, ssh_port, password,
                "nohup poweroff >/dev/null 2>&1 &", timeout=15)
    except Exception as e:
        LOG.warning("L2 graceful poweroff failed: %s", e)
    session.cmd(
        "sleep 5; "
        "[ -f /tmp/l2.pid ] && kill -9 $(cat /tmp/l2.pid) 2>/dev/null; true",
        timeout=30
    )


# ---------- Entry point ----------

@error_context.context_aware
def run(test, params, env):
    """Nested KVM boot test: boot an L2 guest inside L1 and verify it."""
    l2_state = None
    session = None
    l2_booted = False
    ssh_port = params.get_numeric("l2_ssh_port", 2222)
    password = params.get("password", "")

    try:
        error_context.context("Prepare L2 raw image on host", LOG.info)
        l1_image = _get_l1_image_path(test, params)
        l2_state = _prepare_l2_image(params, l1_image)

        error_context.context("Attach L2 image as vdb to L1", LOG.info)
        _attach_l2_as_vdb(params, l2_state["l2_image_base"],
                          l2_state["l2_image_format"])

        error_context.context("Boot L1 guest (with vdb=L2 image)", LOG.info)
        vm = env.get_vm(params["main_vm"])
        vm.create(params=params)
        vm.verify_alive()
        session = vm.wait_for_login(timeout=360)

        error_context.context("Verify nested KVM in L1", LOG.info)
        _l1_verify_kvm(session, test)

        error_context.context("Install QEMU/sshpass in L1", LOG.info)
        if not _l1_install_deps(session):
            test.error("Cannot install required packages in L1 "
                       "(check L1 network / repos)")

        error_context.context("Copy host QEMU binary to L1", LOG.info)
        _l1_copy_host_qemu(vm, session, params)

        error_context.context("Locate L2 passthrough disk in L1", LOG.info)
        l2_dev = _l1_find_l2_disk(session)
        if not l2_dev:
            test.error("L2 disk not found in L1 (expected /dev/vdb or "
                       "another virtio-blk device besides /dev/vda)")
        LOG.info("L2 block device inside L1: %s", l2_dev)

        error_context.context("Boot L2 QEMU inside L1", LOG.info)
        _boot_l2(session, params, l2_dev, l2_state["l2_image_format"])
        l2_booted = True

        boot_timeout = params.get_numeric("l2_boot_timeout", 180)
        error_context.context("Wait for L2 sshd (timeout %ds)"
                              % boot_timeout, LOG.info)
        if not _wait_l2_ssh(session, ssh_port, password, boot_timeout):
            l2_log = session.cmd_output("tail -80 /tmp/l2_serial.log "
                                        "2>/dev/null", timeout=15)
            LOG.info("L2 serial tail:\n%s", l2_log)
            test.fail("L2 SSH did not become ready within %ds" % boot_timeout)

        error_context.context("Verify L2 responsiveness (uname)", LOG.info)
        out = _ssh_l2(session, ssh_port, password, "uname -a")
        LOG.info("L2 uname: %s", out.strip())
        if "Linux" not in out:
            test.fail("L2 uname did not report a Linux kernel: %r" % out)

    finally:
        if l2_booted and session is not None:
            try:
                _shutdown_l2(session, ssh_port, password)
            except Exception as e:
                LOG.warning("L2 shutdown error: %s", e)
        _cleanup_l2_image(l2_state)
