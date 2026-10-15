#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-only
"""Recover from a guest EPT walk over a hardware-poisoned EPT PT entry."""

import glob
import os
import re
import shlex
import subprocess
import time

from provider import dmesg_router  # pylint: disable=unused-import
from provider import ept_poison_utils as ept

from virttest import data_dir, env_process, error_context


READY_RE = re.compile(r"\bREADY gva=0x([0-9a-fA-F]+) gpa=0x([0-9a-fA-F]+)\b")


def _read(path):
    with open(path, encoding="ascii") as stream:
        return stream.read().strip()


def _wait_for(callback, timeout, interval=0.2):
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        result = callback()
        if result:
            return result
        time.sleep(interval)
    return None


def _preflight(test, params):
    if os.geteuid():
        test.cancel("Host root is required for /dev/kmsg, debugfs and EINJ")
    if ept.kvm_users():
        test.cancel("Stop all other /dev/kvm users before this isolated run")
    if "[never]" not in _read("/sys/kernel/mm/transparent_hugepage/enabled"):
        test.cancel("Host THP is not disabled")
    defrag = "/sys/kernel/mm/transparent_hugepage/defrag"
    if os.path.exists(defrag) and "[never]" not in _read(defrag):
        test.cancel("Host THP defrag is not disabled")
    nx_param = "/sys/module/kvm/parameters/nx_huge_pages"
    nx_value = _read(nx_param) if os.path.exists(nx_param) else None
    # KVM accepts "force" as input, but exposes the effective state through
    # a boolean sysfs getter ("Y" when the mitigation is enabled).
    if nx_value not in ("Y", "1", "force"):
        test.cancel("kvm.nx_huge_pages is not enabled (readback: %r)" % nx_value)
    test.log.info("kvm.nx_huge_pages readback: %s", nx_value)
    ept_param = "/sys/module/kvm_intel/parameters/ept"
    if not os.path.exists(ept_param) or _read(ept_param) not in ("Y", "1"):
        test.cancel("kvm_intel.ept is not enabled")
    einj_dir = params.get("einj_dir", "/sys/kernel/debug/apei/einj")
    if not os.path.isdir(einj_dir):
        subprocess.run(["modprobe", "einj"], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not os.path.isdir(einj_dir):
        test.cancel("EINJ debugfs directory is missing: %s" % einj_dir)
    if not re.search(r"\b0x0*10\b", _read(os.path.join(einj_dir, "available_error_type")), re.I):
        test.cancel("EINJ does not advertise memory uncorrectable non-fatal (0x10)")
    for name in ("error_type", "flags", "param1", "param2", "notrigger", "error_inject"):
        if not os.path.exists(os.path.join(einj_dir, name)):
            test.cancel("EINJ control %s is missing" % name)
    return einj_dir


def _build_guest_victim(test, params, vm, session):
    guest_dir = params.get("guest_test_dir", "/tmp")
    src = os.path.join(data_dir.get_deps_dir("hwpoison_ept_pagewalk"), "guest_victim.c")
    dest = os.path.join(guest_dir, "guest_victim.c")
    binary = os.path.join(guest_dir, "guest_victim")
    if session.cmd_output("id -u").strip() != "0":
        test.cancel("Guest root is needed to read physical PFNs from pagemap")
    if session.cmd_status("command -v gcc >/dev/null 2>&1"):
        test.cancel("Guest gcc is needed to compile guest_victim.c")
    vm.copy_files_to(src, dest)
    cmd = "gcc -O2 -Wall -Wextra %s -o %s" % (
        shlex.quote(dest), shlex.quote(binary))
    status, output = session.cmd_status_output(cmd, timeout=60)
    if status:
        test.error("Guest victim build failed: %s" % output)
    return binary


def _start_victim(session, binary, params):
    guest_dir = params.get("guest_test_dir", "/tmp")
    fifo = os.path.join(guest_dir, "ept_poison_trigger.fifo")
    log = os.path.join(guest_dir, "ept_poison_victim.log")
    status_file = os.path.join(guest_dir, "ept_poison_victim.status")
    session.cmd("rm -f %s %s %s && mkfifo %s" % tuple(
        shlex.quote(path) for path in (fifo, log, status_file, fifo)))
    victim = "%s %s > %s 2>&1; echo $? > %s" % tuple(
        shlex.quote(path) for path in (binary, fifo, log, status_file))
    session.cmd("nohup sh -c %s </dev/null >/dev/null 2>&1 &" % shlex.quote(victim))
    return fifo, log, status_file


def _get_ready(session, log):
    output = session.cmd_output("cat %s 2>/dev/null || true" % shlex.quote(log))
    match = READY_RE.search(output)
    return (int(match.group(1), 16), int(match.group(2), 16)) if match else None


def _get_guest_status(session, status_file):
    try:
        status = session.cmd_output(
            "cat %s 2>/dev/null || true" % shlex.quote(status_file)).strip()
    except Exception as exc:
        return "unavailable (%s)" % exc
    return status or "not reported"


def _spte_node(test, params, pid):
    override = params.get("spte_debugfs")
    paths = [override] if override else glob.glob(
        "/sys/kernel/debug/kvm/%d-*/print_sptes" % pid)
    if len(paths) != 1 or not os.path.isfile(paths[0]):
        test.cancel("Expected exactly one print_sptes node for QEMU PID %d: %s" %
                    (pid, paths))
    return paths[0]


def _get_spte(test, reader, path, gpa, timeout):
    reader.drain()
    start = len(reader.records)
    with open(path, "w", encoding="ascii") as stream:
        stream.write("0x%x\n" % gpa)

    def find_line():
        reader.drain()
        for line in reader.records[start:]:
            match = ept.GPA_RE.search(line)
            if match and int(match.group(1), 16) == gpa and "spte[" in line:
                return line
        return None

    line = _wait_for(find_line, timeout)
    if line is None:
        test.error("No SPTE line for GPA 0x%x in new kernel log records" % gpa)
    try:
        return ept.parse_spte_line(line, gpa), line
    except ValueError as exc:
        test.cancel("Target GPA has no valid 4 KB EPT SPTE chain: %s; %s" %
                    (exc, line))


def _log_mapping(test, mapping, spte_line):
    test.log.info("EPT SPTE snapshot: %s", spte_line)
    test.log.info("GPA=0x%x PT=0x%x index=0x%x PTE_HPA=0x%x poison_CL=0x%x",
                  mapping["gpa"], mapping["pt_base"], mapping["index"],
                  mapping["pte_hpa"], mapping["poison_cl"])
    for page_type in ("pages_4k", "pages_2m", "pages_1g"):
        path = "/sys/kernel/debug/kvm/" + page_type
        if os.path.exists(path):
            test.log.info("KVM %s=%s", page_type, _read(path))


def _save_kmsg(test, records):
    path = os.path.join(test.logdir, "ept_poison_host_kmsg.log")
    with open(path, "w", encoding="utf-8") as stream:
        stream.write("\n".join(records) + "\n")


@error_context.context_aware
def run(test, params, env):
    """Inject once into an EPT PTE cache line, then consume it in the guest."""
    setup = ept.HostSetup()
    reader = None
    vm = None
    session = None
    injected = False
    boot_id = _read("/proc/sys/kernel/random/boot_id")
    timeout = int(params.get("event_timeout", "45"))
    try:
        if params.get("prepare_host", "yes") == "yes":
            error_context.context("Prepare dedicated host (no other VMs)", test.log.info)
            try:
                setup.apply()
            except (OSError, RuntimeError) as exc:
                test.cancel("Host preparation failed: %s" % exc)
        einj_dir = _preflight(test, params)
        reader = ept.KmsgReader()

        error_context.context("Start the test VM and wait for victim READY", test.log.info)
        params["start_vm"] = "yes"
        env_process.preprocess_vm(test, params, env, params["main_vm"])
        vm = env.get_vm(params["main_vm"])
        vm.verify_alive()
        session = vm.wait_for_login(timeout=int(params.get("login_timeout", "120")))
        binary = _build_guest_victim(test, params, vm, session)
        fifo, guest_log, guest_status = _start_victim(session, binary, params)
        ready = _wait_for(lambda: _get_ready(session, guest_log), 30, 0.5)
        if ready is None:
            guest_output = session.cmd_output(
                "cat %s 2>/dev/null || true" % shlex.quote(guest_log))
            test.error("Victim did not report READY/GPA: %s" % guest_output)
        gva, gpa = ready
        test.log.info("Guest victim READY: GVA=0x%x GPA=0x%x", gva, gpa)

        error_context.context("Pause VM and identify the 4 KB EPT PTE", test.log.info)
        vm.pause()
        node = _spte_node(test, params, vm.get_pid())
        mapping, line = _get_spte(test, reader, node, gpa, 5)
        _log_mapping(test, mapping, line)
        if params.get("perform_injection", "yes") == "no":
            test.log.info("Address-only run complete; no EINJ was performed")
            return
        reader.drain()
        mce_start = len(reader.records)

        error_context.context("Inject once into the EPT PTE cache line", test.log.info)
        mask = int(params.get("einj_mask", "0xffffffffffffffff"), 0)
        # Treat any failure during EINJ as potentially leaving a poisoned
        # page behind; never tear down the VM in that case.
        injected = True
        ept.inject_einj(einj_dir, mapping["poison_cl"], mask)
        reader.drain()
        if ept.find_mce(reader.records[mce_start:], mapping["poison_cl"]):
            test.fail("The poison was consumed during EINJ, before VM resume")

        error_context.context("Resume VM and trigger its explicit data load", test.log.info)
        vm.resume()
        reader.drain()
        if ept.find_mce(reader.records[mce_start:], mapping["poison_cl"]):
            test.fail("The poison was consumed on VM resume, before victim trigger")
        trigger_start = len(reader.records)
        try:
            status, output = session.cmd_status_output(
                "printf x > %s" % shlex.quote(fifo), timeout=10)
            if status:
                test.log.warning("Guest trigger command returned %d: %s", status, output)
        except Exception as exc:
            # An MCE may have killed QEMU while the SSH command was in flight.
            test.log.info("Guest connection ended during trigger: %s", exc)

        expected = int(params.get("expected_mcacod", "0x1a4"), 0)
        target = mapping["poison_cl"]

        def mce_and_dead_vm():
            reader.drain()
            event = ept.find_mce(reader.records[trigger_start:], target, expected)
            return event if event and not vm.is_alive() else None

        event = _wait_for(mce_and_dead_vm, timeout, 0.5)
        reader.drain()
        if not event:
            other = ept.find_mce(reader.records[trigger_start:], target)
            guest_status_value = _get_guest_status(session, guest_status)
            test.fail("Expected MCACOD=0x%x at CL=0x%x and VM exit; "
                      "matching-address MCE=%s, VM alive=%s, guest status=%s" %
                      (expected, target, other, vm.is_alive(), guest_status_value))
        bank, status, addr = event
        test.log.info("Target MCE: Bank %d STATUS=0x%x MCACOD=0x%x ADDR=0x%x",
                      bank, status, status & 0xFFFF, addr)
        time.sleep(int(params.get("host_survival_seconds", "5")))
        if _read("/proc/sys/kernel/random/boot_id") != boot_id:
            test.fail("Host boot ID changed after the MCE")
        if vm.is_alive():
            test.fail("Target VM is still alive")
        test.log.info("PASS: MCACOD 0x%x, VM exited, host survived", expected)
    finally:
        if reader is not None:
            try:
                reader.drain()
            except Exception as exc:
                test.log.warning("Could not finish kernel log capture: %s", exc)
            try:
                _save_kmsg(test, reader.records)
            except OSError as exc:
                test.log.warning("Could not save kernel log: %s", exc)
            finally:
                reader.close()
        if session is not None:
            try:
                session.close()
            except Exception:
                pass
        # Once poisoned, do not automatically restart, resume or tear down a
        # still-running VM; that can itself consume the poisoned PT page.
        if vm is not None and not injected and vm.is_alive():
            try:
                vm.destroy(gracefully=False)
            except Exception as exc:
                test.log.warning("Could not destroy unpoisoned VM: %s", exc)
        if setup.previous:
            try:
                setup.restore_thp()
            except OSError as exc:
                test.log.warning("Could not restore original THP settings: %s", exc)
