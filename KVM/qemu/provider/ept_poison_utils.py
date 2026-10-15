#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-only
"""Host helpers for the hardware-poisoned EPT page-walk test."""

import errno
import os
import re
import stat
import subprocess


PHYS_PAGE_MASK = 0x000FFFFFFFFFF000
SPTE_RE = re.compile(r"spte\[(\d+)\]\s*=\s*0x([0-9a-fA-F]+)")
GPA_RE = re.compile(r"\bGPA\s+(?:0x)?([0-9a-fA-F]+)\b", re.I)
STATUS_RE = re.compile(r"\bBank\s+(\d+)\s*:\s*([0-9a-fA-F]{8,16})\b")
ADDRESS_RE = re.compile(r"\bADDR\s+(?:0x)?([0-9a-fA-F]+)\b")


def parse_spte_line(line, requested_gpa):
    """Return the PT entry and injection addresses from one debug-patch line.

    spte[2] points to the level-1 PT.  Bits GPA[20:12] select its PTE.
    This is intentionally different from poisoning spte[1]'s guest-data HPA.
    """
    match = GPA_RE.search(line)
    if not match or int(match.group(1), 16) != requested_gpa:
        raise ValueError("SPTE output does not match the requested GPA")
    entries = {int(level): int(value, 16) for level, value in SPTE_RE.findall(line)}
    if not entries or max(entries) not in (4, 5):
        raise ValueError("Expected a four- or five-level EPT SPTE chain")
    if set(entries) != set(range(1, max(entries) + 1)):
        raise ValueError("Incomplete EPT SPTE chain")
    for level, value in entries.items():
        if not value & 0x7:
            raise ValueError("spte[%d] is not present" % level)
        if level > 1 and value & 0x80:
            raise ValueError("spte[%d] is a large-page leaf" % level)
    pt_base = entries[2] & PHYS_PAGE_MASK
    if not pt_base:
        raise ValueError("spte[2] does not contain a PT physical address")
    index = (requested_gpa >> 12) & 0x1FF
    pte_hpa = pt_base + index * 8
    return {
        "gpa": requested_gpa,
        "entries": entries,
        "pt_base": pt_base,
        "index": index,
        "pte_hpa": pte_hpa,
        "poison_cl": pte_hpa & ~0x3F,
    }


def find_mce(records, poison_cl, expected_mcacod=None):
    """Find an MCE whose following ADDR record names the target cache line.

    Return (bank, full_status, address), or None.  A second Bank record
    starts a new event, so an unrelated ADDR cannot complete the first one.
    """
    for position, record in enumerate(records):
        status = STATUS_RE.search(record)
        if not status:
            continue
        bank = int(status.group(1))
        value = int(status.group(2), 16)
        if expected_mcacod is not None and value & 0xFFFF != expected_mcacod:
            continue
        for next_record in records[position + 1:position + 9]:
            if STATUS_RE.search(next_record):
                break
            address = ADDRESS_RE.search(next_record)
            if address:
                addr = int(address.group(1), 16)
                if addr & ~0x3F == poison_cl:
                    return bank, value, addr
                break
    return None


class KmsgReader:
    """Read new kernel records without clearing the system's dmesg ring."""

    def __init__(self):
        self.fd = os.open("/dev/kmsg", os.O_RDONLY | os.O_NONBLOCK)
        os.lseek(self.fd, 0, os.SEEK_END)
        self.records = []

    def drain(self):
        while True:
            try:
                raw = os.read(self.fd, 65536)
            except BlockingIOError:
                break
            except OSError as exc:
                if exc.errno == errno.EPIPE:
                    raise RuntimeError("Kernel log overran during the test") from exc
                raise
            if not raw:
                break
            line = raw.decode("utf-8", "replace").strip()
            self.records.append(line.split(";", 1)[-1])

    def close(self):
        os.close(self.fd)


def kvm_users():
    """Return processes holding /dev/kvm, regardless of their executable name."""
    device = os.stat("/dev/kvm").st_rdev
    users = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = "/proc/%s/fd" % name
        try:
            for fd in os.listdir(fd_dir):
                try:
                    info = os.stat(os.path.join(fd_dir, fd))
                    if stat.S_ISCHR(info.st_mode) and info.st_rdev == device:
                        users.append(int(name))
                        break
                except OSError:
                    continue
        except OSError:
            continue
    return users


def _run(command):
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, check=False)
    if result.returncode:
        raise RuntimeError("%s failed: %s" % (" ".join(command), result.stdout))


class HostSetup:
    """Prepare a dedicated host; never stop a VM owned by somebody else."""

    def __init__(self):
        self.thp_paths = (
            "/sys/kernel/mm/transparent_hugepage/enabled",
            "/sys/kernel/mm/transparent_hugepage/defrag",
        )
        self.previous = {}

    def apply(self):
        users = kvm_users()
        if users:
            raise RuntimeError("Stop existing /dev/kvm users first: %s" % users)
        for path in self.thp_paths:
            if os.path.exists(path):
                with open(path, encoding="ascii") as stream:
                    value = stream.read()
                current = re.search(r"\[([^]]+)\]", value)
                if current:
                    self.previous[path] = current.group(1)
                    with open(path, "w", encoding="ascii") as stream:
                        stream.write("never\n")
        _run(["modprobe", "-r", "kvm_intel"])
        _run(["modprobe", "-r", "kvm"])
        _run(["modprobe", "kvm", "nx_huge_pages=force"])
        _run(["modprobe", "kvm_intel", "ept=1"])

    def restore_thp(self):
        for path, value in self.previous.items():
            with open(path, "w", encoding="ascii") as stream:
                stream.write(value + "\n")


def inject_einj(path, address, mask):
    """Set up the platform error, then perform exactly one EINJ action."""
    values = (
        ("error_type", "0x10"),
        ("flags", "0x2"),
        ("param1", "0x%x" % address),
        ("param2", "0x%x" % mask),
        ("notrigger", "1"),
        ("error_inject", "1"),
    )
    for name, value in values:
        with open(os.path.join(path, name), "w", encoding="ascii") as stream:
            stream.write(value + "\n")
