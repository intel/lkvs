# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; specifically version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# See LICENSE for more details.
#
# Copyright: Red Hat (c) 2024 and Avocado contributors
# Copy from tp-qemu

import math
import os
import shutil
import tempfile
import time

from provider import dmesg_router  # pylint: disable=unused-import
from virttest import error_context, remote, utils_misc, utils_net

from avocado.utils import process
from avocado.core import exceptions
from provider import hostdev
from provider.hostdev import utils as hostdev_utils
from provider.hostdev.dev_setup import hostdev_setup


def _iommu_type1_available(test):
    """Ensure vfio_iommu_type1 is loadable/present on the host."""
    status = process.system(
        "modprobe vfio_iommu_type1 2>/dev/null; "
        "test -d /sys/module/vfio_iommu_type1",
        shell=True, ignore_status=True,
    )
    if status:
        dmesg_out = process.system_output(
            "dmesg | grep -i 'DMAR\\|IOMMU' | head -10",
            shell=True, ignore_status=True,
        ).decode()
        test.cancel("vfio_iommu_type1 is not available; "
                    "intel_iommu must be enabled (cmdline or built-in). "
                    "DMAR/IOMMU dmesg:\n%s" % dmesg_out)


def _kernel_log_grep(pattern):
    """
    Return True if the host kernel ring buffer or persistent journal ever
    reported a line matching the given case-insensitive extended regex.

    Long-lived hosts commonly rotate the dmesg ring buffer, so a plain
    `dmesg | grep` for boot-time DMAR strings can miss messages that were
    printed hours or days ago. Fall back to `journalctl -k -b` when it is
    available; otherwise stay with `dmesg`.
    """
    dmesg_hit = process.system(
        f"dmesg 2>/dev/null | grep -qiE '{pattern}'",
        shell=True, ignore_status=True,
    )
    if dmesg_hit == 0:
        return True
    return process.system(
        f"journalctl -k -b 2>/dev/null | grep -qiE '{pattern}'",
        shell=True, ignore_status=True,
    ) == 0


def _require_ir_qi_enabled(test):
    """
    Cancel the test if the host has not brought Interrupt Remapping and
    Queued Invalidation up. Both are hard prerequisites for the VT-d
    behaviour the vtd_ir_qi action wants to exercise; without them the VF
    interrupt path would fall back to a different mechanism and no longer
    represent the intent of the case.
    """
    ir_patterns = "Enabled IRQ remapping"
    qi_patterns = "Queued [Ii]nvalidation"
    if not _kernel_log_grep(ir_patterns):
        test.cancel(
            "Host has no 'Enabled IRQ remapping' message in kernel log; "
            "intel_iommu=on / IR is not active."
        )
    if not _kernel_log_grep(qi_patterns):
        test.cancel(
            "Host has no 'Queued Invalidation' message in kernel log; "
            "VT-d QI is not active."
        )
    test.log.info(
        "Host IR remapping and Queued Invalidation both confirmed enabled."
    )


def _resolve_vf_mac(slot, params):
    """Look up the MAC address of a VF slot from its PF manager cache."""
    parent_slot = hostdev_utils.get_parent_slot(slot)
    slot_manager = params[f"hostdev_manager_{parent_slot}"]
    # NOTE: VFDevice subclasses PFDevice, so `isinstance(x, PFDevice)` is True
    # for both; use strict type equality to distinguish the two cases here.
    if type(slot_manager) is hostdev.PFDevice:
        return slot_manager.mac_addresses[0]
    slot_index = slot_manager.vfs.index(slot)
    return slot_manager.mac_addresses[slot_index]


def _ping_from_vm(test, vm, session, ext_host, ip_version):
    """Ping ext_host from the given VM session; fail test on non-zero return."""
    error_context.context(f"Ping {ext_host} from {vm.name}", test.log.info)
    s_ping, _ = utils_net.ping(
        ext_host,
        10,
        session=session,
        timeout=30,
        force_ipv4=(ip_version == "ipv4"),
    )
    if s_ping:
        test.fail(f"Fail to ping {ext_host} from {vm.name}")


def _scp_and_verify(test, vm, session, ip_addr, size_mb):
    """
    Create a size_mb sparse test file on the host, scp it into the guest via
    the given VF IP, and confirm md5 sums match end-to-end.
    """
    tmp_dir = tempfile.mkdtemp(prefix="vfio_net_boot_")
    host_file = os.path.join(tmp_dir, "test.img")
    guest_file = "/tmp/vfio_net_boot_test.img"
    try:
        # bs=1M count=1 seek=<size_mb-1> produces a ~size_mb sparse file
        # without writing the full payload on the host side.
        seek = max(int(size_mb) - 1, 0)
        process.run(
            f"dd if=/dev/zero of={host_file} bs=1M count=1 seek={seek}",
            shell=True,
        )
        host_md5 = process.system_output(
            f"md5sum {host_file}", shell=True
        ).decode().split()[0]

        error_context.context(
            f"SCP {size_mb} MiB file to {vm.name} at {ip_addr} and verify md5",
            test.log.info,
        )
        username = vm.params.get("username", "")
        password = vm.params.get("password", "")
        port = vm.params.get("shell_port", "22")
        remote.scp_to_remote(
            ip_addr, port, username, password,
            host_file, guest_file, timeout=1500,
        )
        guest_md5_out = session.cmd_output(f"md5sum {guest_file}", timeout=120)
        guest_md5 = guest_md5_out.strip().splitlines()[-1].split()[0]
        if guest_md5 != host_md5:
            test.fail(
                f"SCP md5 mismatch on {vm.name}: "
                f"host={host_md5} guest={guest_md5}"
            )
        session.cmd(f"rm -f {guest_file}", timeout=30, ignore_all_errors=True)
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def _serial_wait_for_mac(session, mac_addr, timeout):
    """Wait until the guest reports the given MAC on some interface."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        status = session.cmd_status(
            f"ip -o link | grep -qi '{mac_addr}'",
            timeout=15,
        )
        if status == 0:
            return True
        time.sleep(3)
    return False


def _serial_ifname_of_mac(session, mac_addr):
    """Return the guest interface name that owns mac_addr, or empty string."""
    out = session.cmd_output_safe(
        f"ip -o link | awk -v m={mac_addr.lower()} "
        f"'tolower($0) ~ m {{print $2}}' | head -1 | tr -d ':'"
    )
    out = utils_misc.strip_console_codes(out).strip()
    if out:
        # Guard against a trailing shell echo of the command itself.
        out = out.splitlines()[-1].strip()
    return out


def _verify_slot_serial(test, params, vm, session, slot, ext_host):
    """
    Verify one passthrough NIC via an existing serial session:
      - wait for the expected MAC to appear on some guest interface
      - bring the interface up
      - wait for a global IPv4 address
      - ping ext_host through the interface
      - log the interrupt class (MSI / IO-APIC)
    """
    mac_addr = _resolve_vf_mac(slot, params)
    error_context.context(
        f"Serial verify slot {slot} MAC {mac_addr} on {vm.name}",
        test.log.info,
    )
    link_timeout = int(params.get("hostdev_serial_link_timeout", 120))
    ping_count = int(params.get("hostdev_serial_ping_count", 10))
    ping_timeout = int(params.get("hostdev_serial_ping_timeout", 60))

    if not _serial_wait_for_mac(session, mac_addr, link_timeout):
        test.fail(
            f"MAC {mac_addr} (slot {slot}) did not appear in guest "
            f"{vm.name} within {link_timeout}s"
        )
    ifname = _serial_ifname_of_mac(session, mac_addr)
    if not ifname:
        test.fail(
            f"Cannot find guest interface for MAC {mac_addr} "
            f"(slot {slot}) on {vm.name}"
        )
    # Bring the interface up (nmcli covers RHEL/CentOS guests, ip link is a
    # generic fallback if NetworkManager is absent).
    session.cmd_output_safe(
        f"nmcli device up {ifname} 2>/dev/null; "
        f"ip link set {ifname} up",
        timeout=30,
    )
    addr_family = "inet"
    deadline = time.time() + link_timeout
    got_addr = False
    while time.time() < deadline:
        addr_out = utils_misc.strip_console_codes(session.cmd_output_safe(
            f"ip -o -f {addr_family} addr show {ifname} scope global"
        )).strip()
        if addr_out:
            got_addr = True
            break
        time.sleep(3)
    if not got_addr:
        test.fail(
            f"{ifname} (MAC {mac_addr}) has no global {addr_family} "
            f"address on {vm.name}"
        )
    status = session.cmd_status(
        f"ping -4 -c {ping_count} -I {ifname} {ext_host}",
        timeout=ping_timeout + 30,
    )
    if status != 0:
        test.fail(
            f"Ping {ext_host} through {ifname} failed on {vm.name}"
        )
    # Log the NIC's interrupt class.
    # i40e/ice/ixgbe name IRQs like "i40e-<ifname>-TxRx-N", so match ifname
    # as a substring rather than a whole word. Do the classification in
    # Python to avoid multi-pipe quoting issues in the serial shell.
    raw = utils_misc.strip_console_codes(session.cmd_output_safe(
        f"grep {ifname} /proc/interrupts 2>/dev/null; echo __END__"
    ))
    raw = raw.split("__END__", 1)[0]
    seen = []
    for kw in ("PCI-MSI", "MSI-X", "MSI", "IO-APIC"):
        if kw in raw and kw not in seen:
            seen.append(kw)
    msi_out = " ".join(seen)
    test.log.info(
        "Interrupt class for %s (MAC %s) on %s: %s",
        ifname, mac_addr, vm.name, (msi_out or "unknown"),
    )


def _open_serial_session(vm, timeout=240):
    """Return a serial login with bracketed-paste disabled for stable output."""
    session = vm.wait_for_serial_login(timeout=timeout)
    session.cmd_output_safe(
        "bind 'set enable-bracketed-paste off' 2>/dev/null; true"
    )
    return session


def _verify_slots(test, params, vm, pci_slots, ext_host, ip_version):
    """
    Dispatch NIC verification for pci_slots based on hostdev_verify_mode:
      - "ssh" (default): SSH into the guest via each slot's MAC and ping
      - "serial":        drive verification through the serial console only,
                         no host-guest IP reachability required
    """
    verify_mode = params.get("hostdev_verify_mode", "ssh")
    if verify_mode == "serial":
        session = _open_serial_session(vm)
        try:
            for slot in pci_slots:
                _verify_slot_serial(
                    test, params, vm, session, slot, ext_host
                )
        finally:
            session.close()
        return
    for slot in pci_slots:
        mac_addr = _resolve_vf_mac(slot, params)
        session = hostdev_utils.ssh_login_from_mac(
            vm, mac_addr, int(ip_version[-1])
        )
        if not session:
            test.fail(
                f"Cannot log into {vm.name} via slot {slot} MAC {mac_addr}"
            )
        try:
            _ping_from_vm(test, vm, session, ext_host, ip_version)
        finally:
            session.close()


def _boot_and_verify(test, params, vm, pci_slots, ext_host, ip_version, action):
    """
    Log into vm via each assigned VF's MAC, ping ext_host, and run the
    selected extra action (e.g. scp) on the last established session.
    """
    verify_mode = params.get("hostdev_verify_mode", "ssh")
    if verify_mode == "serial":
        _verify_slots(test, params, vm, pci_slots, ext_host, ip_version)
        return

    scp_size_mb = int(params.get("scp_file_size_mb", 100))
    ip_wait_timeout = params.get_numeric("vf_ip_wait_timeout", 90)
    last_session = None
    last_ip = ""
    try:
        error_context.context(
            f"Verify hostdev NICs on {vm.name}", test.log.info
        )
        for slot in pci_slots:
            mac_addr = _resolve_vf_mac(slot, params)
            # Multi-VF guests may have several VF NICs racing for DHCP at
            # once; poll get_guest_ip_from_mac until the target VF has an
            # address instead of failing on the first empty result.
            deadline = time.time() + ip_wait_timeout
            ip_addr = ""
            while True:
                ip_addr = hostdev_utils.get_guest_ip_from_mac(
                    vm, mac_addr, int(ip_version[-1])
                )
                if ip_addr or time.time() >= deadline:
                    break
                time.sleep(5)
            if not ip_addr:
                test.fail(
                    f"Cannot resolve guest IP on {vm.name} for VF "
                    f"{slot} MAC {mac_addr} within {ip_wait_timeout}s"
                )
            session = hostdev_utils.ssh_login_from_mac(
                vm, mac_addr, int(ip_version[-1])
            )
            if not session:
                test.fail(
                    f"Cannot log into {vm.name} via VF {slot} MAC {mac_addr}"
                )
            _ping_from_vm(test, vm, session, ext_host, ip_version)
            if last_session is not None:
                last_session.close()
            last_session = session
            last_ip = ip_addr
        if action == "scp" and last_session is not None:
            _scp_and_verify(test, vm, last_session, last_ip, scp_size_mb)
    finally:
        if last_session is not None:
            last_session.close()


def _boot_and_verify_max_vfs(test, params, vm, pci_slots, action):
    """
    Verify a guest that owns the PF's full VF set.

    Resolving dozens of VF IPs one MAC at a time over the serial console does
    not scale and is fragile, so batch-resolve every VF IP in a single pass,
    then ping each VF's guest IP from the host. Connectivity is checked
    host -> VF rather than guest -> gateway: a max-VF guest is multi-homed
    with every VF on one subnet, so guest-sourced pings are unreliable
    (rp_filter and route selection pick a single egress), whereas pinging
    each VF IP from the host exercises that VF's data path directly and
    independently.

    Strict pass criteria: every VF must obtain an IP AND every VF IP must be
    reachable from the host. Any missing IP or any failed ping fails the case
    with the offending MACs (and IPs when known) logged. For the scp action a
    single SSH session is established on one working VF.
    """
    scp_size_mb = int(params.get("scp_file_size_mb", 100))
    ip_wait_timeout = params.get_numeric("vf_ip_wait_timeout", 90)
    macs = [_resolve_vf_mac(slot, params) for slot in pci_slots]
    total = len(macs)
    error_context.context(
        f"Batch-verify {total} VF NIC(s) on {vm.name}", test.log.info
    )
    mac_to_ip = hostdev_utils.get_guest_ips_from_macs(
        vm, macs, timeout=ip_wait_timeout
    )
    without_ip = [m for m in macs if not mac_to_ip.get(m.lower())]
    with_ip = [m for m in macs if mac_to_ip.get(m.lower())]
    test.log.info(
        "%d/%d VF NIC(s) on %s obtained an IP", len(with_ip), total, vm.name
    )
    if without_ip:
        test.fail(
            f"{len(without_ip)}/{total} VF NIC(s) on {vm.name} did not obtain "
            f"an IP within {ip_wait_timeout}s; missing MACs: "
            f"{', '.join(without_ip)}"
        )

    # Ping every VF's guest IP from the host. Every VF must be reachable.
    error_context.context(
        f"Ping {total} VF(s) on {vm.name} from the host", test.log.info,
    )
    unreachable = []
    for mac in macs:
        vf_ip = mac_to_ip[mac.lower()]
        status = process.system(
            f"ping -c 3 -W 2 {vf_ip}",
            shell=True, ignore_status=True,
        )
        if status:
            test.log.warning(
                "Fail to ping VF IP %s (MAC %s) on %s from the host",
                vf_ip, mac, vm.name,
            )
            unreachable.append((mac, vf_ip))
    test.log.info(
        "%d/%d VF NIC(s) on %s reachable from the host",
        total - len(unreachable), total, vm.name
    )
    if unreachable:
        details = ", ".join(f"{mac}({ip})" for mac, ip in unreachable)
        test.fail(
            f"{len(unreachable)}/{total} VF NIC(s) on {vm.name} not reachable "
            f"from the host; unreachable MAC(IP): {details}"
        )

    if action == "scp":
        last_ip = mac_to_ip[macs[-1].lower()]
        session = hostdev_utils.ssh_login_from_ip(vm, last_ip)
        if not session:
            test.fail(f"Cannot log into {vm.name} via VF IP {last_ip}")
        try:
            _scp_and_verify(test, vm, session, last_ip, scp_size_mb)
        finally:
            session.close()


def _assign_and_create(test, vm, available_pci_slots):
    """
    Pop the required number of VF slots from the shared pool, wire them
    into the vm params, boot the vm and return the assigned slots.
    """
    vm_hostdevs = vm.params.objects("vm_hostdevs")
    pci_slots = []
    error_context.base_context(
        f"Setting hostdevs for {vm.name}", test.log.info
    )
    for dev in vm_hostdevs:
        if not available_pci_slots:
            test.cancel(
                "Not enough VF slots available; need at least "
                f"{len(vm_hostdevs)} for {vm.name}"
            )
        pci_slot = available_pci_slots.pop(0)
        vm.params[f"vm_hostdev_host_{dev}"] = pci_slot
        pci_slots.append(pci_slot)
    vm.create(params=vm.params)
    vm.verify_alive()
    return pci_slots


def _assign_and_create_max_vfs(test, params, vm, available_pci_slots):
    """
    Assign every available VF (the NIC's real Total VFs) to a single guest,
    spreading them across as many PCI bridges as needed since a single root
    bus cannot host them all.

    The number of VFs is whatever the PF actually exposed at runtime
    (len(available_pci_slots)), so the same case adapts to each NIC's
    sriov_totalvfs. An optional cap (hostdev_max_assign) limits how many are
    assigned.
    """
    slots_per_bridge = params.get_numeric("hostdev_vf_slots_per_bridge", 31)
    n = len(available_pci_slots)
    max_assign = params.get_numeric("hostdev_max_assign", 0)
    if max_assign and max_assign < n:
        n = max_assign
    if n == 0:
        test.cancel("No VF slots available for max_vfs topology")

    # q35 exposes a PCIe root complex, so conventional PCI slots come from a
    # pcie-pci-bridge; i440fx (pc) uses a legacy pci-bridge.
    machine_type = params.get("machine_type", "")
    default_bridge = (
        "pcie-pci-bridge" if machine_type.startswith("q35") else "pci-bridge"
    )
    bridge_type = params.get("hostdev_vf_bridge_type", default_bridge)

    num_bridges = int(math.ceil(float(n) / slots_per_bridge))
    controllers = [f"vfbr{b}" for b in range(num_bridges)]
    existing = vm.params.objects("pci_controllers")
    vm.params["pci_controllers"] = " ".join(existing + controllers)
    for name in controllers:
        vm.params[f"type_{name}"] = bridge_type

    hostdev_names = [f"hostdev{i + 1}" for i in range(n)]
    vm.params["vm_hostdevs"] = " ".join(hostdev_names)
    error_context.base_context(
        f"Assigning {n} VF(s) across {num_bridges} bridge(s) "
        f"({bridge_type}) for {vm.name}",
        test.log.info,
    )
    pci_slots = []
    for i, dev in enumerate(hostdev_names):
        pci_slot = available_pci_slots.pop(0)
        vm.params[f"vm_hostdev_host_{dev}"] = pci_slot
        vm.params[f"pci_bus_{dev}"] = controllers[i // slots_per_bridge]
        pci_slots.append(pci_slot)
    vm.create(params=vm.params)
    vm.verify_alive()
    return pci_slots


def _wait_for_vf_session(test, vm, mac_addr, ip_version, timeout=120):
    """Wait for an SSH session via VF MAC after hotplug."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        session = hostdev_utils.ssh_login_from_mac(vm, mac_addr, int(ip_version[-1]))
        if session:
            return session
        time.sleep(5)
    test.fail(f"Cannot log into {vm.name} via hotplugged VF MAC {mac_addr}")


def _wait_for_mac_removed(test, vm, mac_addr, timeout=60):
    """Wait until the guest no longer reports the detached VF MAC."""
    session = vm.wait_for_serial_login(timeout=240)
    try:
        deadline = time.time() + timeout
        while time.time() < deadline:
            status = session.cmd_status(
                f"ip -o link | grep -qi '{mac_addr}'",
                timeout=20,
            )
            if status != 0:
                return
            time.sleep(3)
    finally:
        session.close()
    test.fail(f"Detached VF MAC {mac_addr} is still present in guest")


def _hotplug_cycle(test, params, vm, dev_name, pci_slot, ext_host, ip_version,
                   reuse_dev=None):
    """Hotplug one VF, verify network path, then unplug and verify removal.

    When reuse_dev is provided, plug that existing QDevice back into its
    original bus (used by hotswap flows where the guest was cold-plugged and
    then unplugged, so the pcie-root-port is still allocated in the devices
    representation).
    """
    if reuse_dev is not None:
        hotplug_dev = reuse_dev
    else:
        dev_params = vm.params.object_params(dev_name)
        dev_params["vm_hostdev_host"] = pci_slot
        hotplug_dev = vm.devices.hostdev_define_by_params(dev_name, dev_params)
    error_context.context(
        f"Hotplug VF {pci_slot} on {vm.name}",
        test.log.info,
    )
    vm.devices.simple_hotplug(hotplug_dev, vm.monitor)

    mac_addr = _resolve_vf_mac(pci_slot, params)
    verify_mode = params.get("hostdev_verify_mode", "ssh")
    if verify_mode == "serial":
        session = _open_serial_session(vm)
        try:
            _verify_slot_serial(
                test, params, vm, session, pci_slot, ext_host
            )
        finally:
            session.close()
    else:
        session = _wait_for_vf_session(test, vm, mac_addr, ip_version)
        try:
            _ping_from_vm(test, vm, session, ext_host, ip_version)
        finally:
            session.close()

    error_context.context(
        f"Hot-unplug VF {pci_slot} on {vm.name}",
        test.log.info,
    )
    vm.devices.simple_unplug(hotplug_dev, vm.monitor)
    _wait_for_mac_removed(test, vm, mac_addr)


def _run_hotswap_action(test, params, env, ext_host, ip_version,
                        serial_vfs=False):
    """Execute hotswap-based actions used by vtd_ras_* variants.

    When serial_vfs is True, iterate the hotplug/unplug cycle across every
    VF exposed by the PF, booting a fresh single-hostdev guest for each VF
    so successive VF assignment is exercised end-to-end.
    """
    vm = env.get_all_vms()[0]
    hostdev_driver = params.get("vm_hostdev_driver", "vfio-pci")
    assignment_type = params.get("hostdev_assignment_type")
    available_pci_slots = hostdev_utils.get_pci_by_dev_type(
        assignment_type, "network", hostdev_driver
    )
    if not available_pci_slots:
        test.cancel("No VF slots available for vfio net hotswap action")

    vm_hostdevs = vm.params.objects("vm_hostdevs")
    if len(vm_hostdevs) != 1:
        test.cancel(
            "Hotswap action requires exactly one hostdev definition; "
            f"got {len(vm_hostdevs)}"
        )
    dev_name = vm_hostdevs[0]
    hotswap_iterations = params.get_numeric("hotplug_iterations", 2)

    slot_iterable = available_pci_slots if serial_vfs else [available_pci_slots[0]]
    for slot_idx, pci_slot in enumerate(slot_iterable):
        if serial_vfs:
            error_context.base_context(
                f"Serial hotswap on VF {slot_idx + 1}/{len(slot_iterable)} "
                f"({pci_slot})",
                test.log.info,
            )
        # Boot the guest with the VF pre-attached so QEMU creates the
        # pcie-root-port + vfio-pci pair at cold-plug time. simple_hotplug
        # only supports inserting a single QDevice per call, so the root
        # port must be present before we plug the hostdev.
        vm.params[f"vm_hostdev_host_{dev_name}"] = pci_slot
        vm.create(params=vm.params)
        vm.verify_alive()
        vm.wait_for_serial_login(timeout=240).close()
        # Detach the cold-plugged hostdev to bring the guest into the "no
        # VF" baseline expected by _hotplug_cycle (which starts with plug).
        initial_dev = vm.devices.get(dev_name)
        if initial_dev is not None:
            vm.devices.simple_unplug(initial_dev, vm.monitor)
        try:
            for idx in range(hotswap_iterations):
                error_context.context(
                    f"Hotswap iteration {idx + 1}/{hotswap_iterations}",
                    test.log.info,
                )
                _hotplug_cycle(
                    test, params, vm, dev_name, pci_slot, ext_host, ip_version,
                    reuse_dev=initial_dev,
                )
        finally:
            vm.destroy(gracefully=False)


def _verify_all_vfs(test, params, vm, pci_slots, ext_host, ip_version):
    """
    Verify each assigned NIC by MAC, using the mode selected by
    hostdev_verify_mode. Safe to call repeatedly across reboots and
    re-creations because each call opens fresh session(s).
    """
    _verify_slots(test, params, vm, pci_slots, ext_host, ip_version)


def _run_reass_reboot(test, params, env, ext_host, ip_version, iterations):
    """
    Boot the guest once with its VFs assigned, then reboot the guest OS
    iterations times, verifying VF NIC connectivity after every reboot.
    """
    reboot_timeout = params.get_numeric("reass_reboot_timeout", 360)
    hostdev_driver = params.get("vm_hostdev_driver", "vfio-pci")
    assignment_type = params.get("hostdev_assignment_type")
    vm = env.get_all_vms()[0]
    available = hostdev_utils.get_pci_by_dev_type(
        assignment_type, "network", hostdev_driver,
    )
    pci_slots = _assign_and_create(test, vm, available)
    try:
        _verify_all_vfs(test, params, vm, pci_slots, ext_host, ip_version)
        for i in range(iterations):
            error_context.context(
                f"Reass reboot iteration {i + 1}/{iterations} on {vm.name}",
                test.log.info,
            )
            # Use serial login so the reboot flow does not depend on a
            # virtnet[0] entry (the guest only has passthrough VFs).
            session = vm.wait_for_serial_login(timeout=reboot_timeout)
            new_session = vm.reboot(
                session=session,
                method="shell",
                timeout=reboot_timeout,
                serial=True,
            )
            new_session.close()
            _verify_all_vfs(test, params, vm, pci_slots, ext_host, ip_version)
    finally:
        vm.destroy(gracefully=False)


def _run_reass_lifecycle(
    test, params, env, ext_host, ip_version, iterations, from_guest
):
    """
    Loop iterations times: create the guest with its VFs, verify the VFs,
    tear the guest down (either by asking the guest OS to power itself off
    or by killing the QEMU process directly), and clean up before the next
    iteration.
    """
    shutdown_timeout = params.get_numeric("reass_shutdown_timeout", 240)
    hostdev_driver = params.get("vm_hostdev_driver", "vfio-pci")
    assignment_type = params.get("hostdev_assignment_type")
    vm = env.get_all_vms()[0]
    for i in range(iterations):
        error_context.context(
            f"Reass lifecycle iteration {i + 1}/{iterations}"
            f" ({'shutdown' if from_guest else 'destroy'})",
            test.log.info,
        )
        try:
            # Re-query the free VF pool each iteration so the same VF is
            # picked up after the previous iteration returned it.
            available = hostdev_utils.get_pci_by_dev_type(
                assignment_type, "network", hostdev_driver,
            )
            pci_slots = _assign_and_create(test, vm, available)
            _verify_all_vfs(test, params, vm, pci_slots, ext_host, ip_version)
            if from_guest:
                error_context.context(
                    f"Guest-side shutdown of {vm.name}", test.log.info
                )
                vm.graceful_shutdown(timeout=shutdown_timeout)
        finally:
            # gracefully=False ensures the QEMU process and any lingering
            # child threads are released before the next iteration starts.
            vm.destroy(gracefully=False)


def _run_many_vms_boot(test, params, vms, available_pci_slots,
                       ext_host, ip_version):
    """Boot every registered VM with a single VF assigned from the shared
    pool, then verify each VF NIC once all guests are up.

    The many_vms topology (vms = "vm1 vm2", vm_hostdevs = hostdev1) covers
    the scale-out coverage where each guest owns exactly one passthrough
    VF. Guests are created sequentially so VF assignment order is
    deterministic; verification happens after every guest is alive to
    exercise concurrent VF ownership.
    """
    vm_slots = []
    try:
        for vm in vms:
            error_context.base_context(
                f"Booting {vm.name} with one VF", test.log.info
            )
            pci_slots = _assign_and_create(test, vm, available_pci_slots)
            vm_slots.append((vm, pci_slots))
        for vm, pci_slots in vm_slots:
            error_context.context(
                f"Verify VF NIC on {vm.name}", test.log.info
            )
            _verify_all_vfs(test, params, vm, pci_slots, ext_host, ip_version)
    finally:
        for vm in vms:
            try:
                vm.destroy(gracefully=False)
            except Exception:
                pass


def _do_live_migration(test, params, vm, pci_slots, ext_host, ip_version):
    """Hot-unplug every assigned NIC, live-migrate the guest, then re-attach
    each device on the destination and re-verify the NIC end-to-end.

    PCI passthrough blocks migration, so the hostdev(s) must be released
    before vm.migrate() is invoked. After migration:
      1. A serial console login on the destination confirms the guest
         survived migration.
      2. Every previously assigned NIC is hot-plugged back into the guest.
      3. Each re-attached NIC is verified through the serial console so it
         is confirmed functional on the destination.
      4. Every re-attached NIC is hot-unplugged again and its removal from
         the guest is confirmed, so the case leaves no device plugged in on
         teardown.
    """
    mig_protocol = params.get("mig_protocol", "tcp")
    mig_timeout = params.get_numeric("mig_timeout", 300)
    serial_timeout = params.get_numeric("serial_login_timeout", 120)
    vm_hostdevs = vm.params.objects("vm_hostdevs")
    error_context.context(
        f"Hot-unplug {len(vm_hostdevs)} NIC(s) on {vm.name} before migration",
        test.log.info,
    )
    for dev_name in vm_hostdevs:
        dev = vm.devices.get(dev_name)
        if dev is not None:
            vm.devices.simple_unplug(dev, vm.monitor)
    error_context.context(
        f"Verify {vm.name} responsive via serial before migration",
        test.log.info,
    )
    vm.wait_for_serial_login(timeout=serial_timeout).close()
    error_context.context(
        f"Live migrate {vm.name} via {mig_protocol}", test.log.info,
    )
    vm.migrate(mig_timeout, mig_protocol)
    error_context.context(
        f"Verify {vm.name} responsive on migration destination",
        test.log.info,
    )
    vm.wait_for_serial_login(timeout=serial_timeout).close()

    error_context.context(
        f"Re-attach {len(vm_hostdevs)} NIC(s) to {vm.name} after migration",
        test.log.info,
    )
    replugged = []
    rescan_needed = False
    for dev_name, pci_slot in zip(vm_hostdevs, pci_slots):
        # vm.migrate() rebuilds the destination command line from params, so a
        # hostdev cold-plugged via vm_hostdevs is already re-created on the
        # destination QEMU. The migrated guest ejected that device before
        # migration, however, so it is present in QEMU but invisible to the
        # guest until a PCI rescan is issued. Devices not present after
        # migration (e.g. ones hot-plugged at runtime) are defined and
        # hot-plugged back, which raises a guest hot-add event on its own.
        hotplug_dev = vm.devices.get(dev_name)
        if hotplug_dev is None:
            dev_params = vm.params.object_params(dev_name)
            dev_params["vm_hostdev_host"] = pci_slot
            hotplug_dev = vm.devices.hostdev_define_by_params(
                dev_name, dev_params
            )
            vm.devices.simple_hotplug(hotplug_dev, vm.monitor)
        else:
            rescan_needed = True
        replugged.append((hotplug_dev, pci_slot))

    if rescan_needed:
        error_context.context(
            f"Rescan guest PCI bus on {vm.name} so re-created NIC(s) "
            f"are detected",
            test.log.info,
        )
        session = _open_serial_session(vm, timeout=serial_timeout)
        try:
            session.cmd_output_safe(
                "echo 1 > /sys/bus/pci/rescan", timeout=60
            )
        finally:
            session.close()

    error_context.context(
        f"Verify re-attached NIC(s) on {vm.name}", test.log.info,
    )
    _verify_slots(test, params, vm, pci_slots, ext_host, ip_version)

    error_context.context(
        f"Hot-unplug {len(replugged)} re-attached NIC(s) on {vm.name} "
        f"after migration",
        test.log.info,
    )
    for hotplug_dev, pci_slot in replugged:
        vm.devices.simple_unplug(hotplug_dev, vm.monitor)
        mac_addr = _resolve_vf_mac(pci_slot, params)
        _wait_for_mac_removed(test, vm, mac_addr)


def _apply_viommu_params(params, vm):
    """Inject a guest intel-iommu (vIOMMU) device when viommu_mode is set.

    avocado-vt's built-in intel_iommu builder emits the legacy
    ``x-scalable-mode`` property, which current QEMU renamed to
    ``scalable-mode``; assemble the device string here so both legacy and
    scalable vIOMMU modes work on current QEMU. This is a no-op unless the
    case sets viommu_mode, so other vfio_net_boot cases are unaffected.

    caching-mode is emitted by default (required whenever an assigned device
    shares the vIOMMU). A case with a pure emulated topology and no assigned
    device can set viommu_caching_mode=no to request a bare ``intel-iommu``,
    matching sources that omit caching-mode; scalable mode always keeps it.
    """
    mode = params.get("viommu_mode")
    if not mode:
        return
    props = []
    if params.get("viommu_caching_mode", "yes") == "yes" or mode == "scalable":
        props.append("caching-mode=on")
    if mode == "scalable":
        props.extend(["scalable-mode=on", "device-iotlb=on"])
    device = "-device intel-iommu"
    if props:
        device += "," + ",".join(props)
    existing = vm.params.get("extra_params", "")
    vm.params["extra_params"] = (existing + " " + device).strip()


def _set_guest_iommu_cmdline(test, params, vm):
    """Enforce the guest intel_iommu kernel cmdline and reboot to apply it.

    guest_iommu_cmdline is the exact intel_iommu token to set, e.g.
    ``intel_iommu=off`` or ``intel_iommu=on,sm_off``. grubby dedups by key,
    so any existing intel_iommu argument is removed first. No-op when unset.
    """
    iommu_cmdline = params.get("guest_iommu_cmdline")
    if not iommu_cmdline:
        return
    reboot_timeout = params.get_numeric("guest_iommu_reboot_timeout", 360)
    error_context.context(
        f"Set guest kernel cmdline '{iommu_cmdline}' on {vm.name}",
        test.log.info,
    )
    session = _open_serial_session(vm)
    try:
        session.cmd(
            "grubby --update-kernel=$(grubby --default-kernel) "
            f'--remove-args="intel_iommu" --args="{iommu_cmdline}"',
            timeout=120,
        )
    finally:
        session.close()
    session = vm.wait_for_serial_login(timeout=reboot_timeout)
    session = vm.reboot(
        session=session, method="shell", timeout=reboot_timeout, serial=True,
    )
    try:
        cmdline = utils_misc.strip_console_codes(
            session.cmd_output_safe("cat /proc/cmdline")
        )
        if iommu_cmdline not in cmdline:
            test.fail(
                f"Guest kernel cmdline on {vm.name} does not contain "
                f"'{iommu_cmdline}' after reboot: {cmdline.strip()}"
            )
    finally:
        session.close()


def _verify_bridge_nic(test, params, vm):
    """Ping the guest's bridge virtio-net NIC IP from the host.

    Log into the guest to settle the DHCP lease, resolve the NIC's guest IP,
    then ping it from the host.
    """
    error_context.context(
        f"Verify bridge NIC connectivity on {vm.name}", test.log.info
    )
    login_timeout = params.get_numeric("login_timeout", 360)
    session = vm.wait_for_login(timeout=login_timeout)
    try:
        guest_ip = vm.get_address()
    finally:
        session.close()
    if not guest_ip:
        test.fail(f"Cannot resolve bridge NIC IP for {vm.name}")
    status = process.system(
        f"ping -c 5 -W 2 {guest_ip}",
        shell=True, ignore_status=True,
    )
    if status:
        test.fail(
            f"Fail to ping bridge NIC IP {guest_ip} of {vm.name} from the host"
        )
    test.log.info(
        "Bridge NIC IP %s of %s reachable from the host", guest_ip, vm.name
    )


def _run_viommu_net(test, params, env):
    """Boot a guest with a guest vIOMMU and a bridge virtio-net NIC (no
    assigned device), then ping that NIC from the host.

    Only entered when viommu_net_check is set, so every other vfio_net_boot
    case runs the unmodified code below.
    """
    vm = env.get_all_vms()[0]
    _apply_viommu_params(params, vm)
    try:
        vm.create(params=vm.params)
        vm.verify_alive()
        _verify_bridge_nic(test, params, vm)
    finally:
        vm.destroy(gracefully=False)


@error_context.context_aware
def run(test, params, env):
    """
    Assign network host devices to a VM and validate them.

    Supported actions (controlled by hostdev_action):
        * boot:           log into the guest via each VF's MAC and ping
                          ext_host
        * scp:            everything boot does, plus SCP a large file and
                          verify md5
        * hotswap:        iteratively hot-unplug/hot-plug a single VF and
                          verify guest connectivity across the cycles
        * reass_reboot:   boot once, reboot the guest reass_iterations
                          times, verify each VF NIC after every reboot
        * reass_shutdown: reass_iterations times, create the guest, verify
                          each VF NIC, shut the guest down from inside,
                          reap the QEMU process
        * reass_destroy:  reass_iterations times, create the guest, verify
                          each VF NIC, destroy the QEMU process directly
        * live_migration: verify VF NICs, hot-unplug every VF, live-migrate
                          the guest via a local tcp (mig_protocol) channel,
                          confirm the guest survives via serial login on the
                          destination, re-attach every VF and re-verify the
                          NIC, then hot-unplug every VF again so no device is
                          left plugged in on teardown
        * vtd_ir_qi:      precheck host kernel log for VT-d Interrupt
                          Remapping + Queued Invalidation, then behave
                          like boot (ping ext_host from the guest via
                          the assigned VF). Successful ping implies IR
                          remapping delivered VF MSI(-X) interrupts
                          through the QI engine end-to-end.

    Setting hostdev_serial_vfs = yes reruns the boot+verify loop once per VF
    exposed by the PF, each time booting a single-hostdev guest that owns
    exactly one VF, so a serial (successive) VF assignment path is covered.

    Setting vms to more than one entry (many_vms topology) boots every
    registered guest with one VF assigned from the shared pool and then
    verifies each VF NIC concurrently; only the boot action is supported
    in this mode.

    dma_cmd (used to raise dma_entry_limit for large VF pools) is only
    executed for TDX guests where the default kernel limit is otherwise hit
    during hostdev setup; other guest types keep the kernel default.
    """
    if params.get("viommu_net_check"):
        _run_viommu_net(test, params, env)
        return
    ip_version = params["ip_version"]
    action = params.get("hostdev_action", "boot")
    vm_type = params.get("vm_secure_guest_type")
    if not params.get("vm_hostdev_iommufd"):
        _iommu_type1_available(test)
        if vm_type == "tdx":
            dma_cmd = params.get("dma_cmd")
            if dma_cmd:
                status = process.system(dma_cmd, shell=True)
                if status:
                    raise exceptions.TestError(
                        "Failed to increase dma_entry_limit."
                    )

    if action == "vtd_ir_qi":
        _require_ir_qi_enabled(test)
    serial_vfs = params.get("hostdev_serial_vfs") == "yes"
    with hostdev_setup(params) as params:
        hostdev_driver = params.get("vm_hostdev_driver", "vfio-pci")
        assignment_type = params.get("hostdev_assignment_type")
        ext_host = params.get(
            "ext_host", utils_net.get_host_ip_address(ip_ver=ip_version)
        )
        available_pci_slots = hostdev_utils.get_pci_by_dev_type(
            assignment_type, "network", hostdev_driver
        )

        if action == "hotswap":
            _run_hotswap_action(
                test, params, env, ext_host, ip_version,
                serial_vfs=serial_vfs,
            )
            return

        if action == "reass_reboot":
            iterations = params.get_numeric("reass_iterations", 10)
            _run_reass_reboot(
                test, params, env, ext_host, ip_version, iterations
            )
            return

        if action in ("reass_shutdown", "reass_destroy"):
            iterations = params.get_numeric("reass_iterations", 10)
            _run_reass_lifecycle(
                test, params, env, ext_host, ip_version,
                iterations, from_guest=(action == "reass_shutdown"),
            )
            return

        vms = env.get_all_vms()
        if len(vms) > 1:
            _run_many_vms_boot(
                test, params, vms, available_pci_slots,
                ext_host, ip_version,
            )
            return

        vm = vms[0]
        _apply_viommu_params(params, vm)
        if serial_vfs:
            slots_snapshot = list(available_pci_slots)
            if not slots_snapshot:
                test.cancel("No VF slots available for serial VF assignment")
            for iteration, slot in enumerate(slots_snapshot):
                error_context.context(
                    f"Serial VF assignment iteration {iteration + 1}/"
                    f"{len(slots_snapshot)} on {slot}",
                    test.log.info,
                )
                try:
                    pci_slots = _assign_and_create(test, vm, [slot])
                    _boot_and_verify(
                        test, params, vm, pci_slots,
                        ext_host, ip_version, action,
                    )
                    if action == "live_migration":
                        _do_live_migration(
                            test, params, vm, pci_slots,
                            ext_host, ip_version,
                        )
                finally:
                    vm.destroy(gracefully=False)
            return

        try:
            if params.get("hostdev_max_vfs") == "yes":
                pci_slots = _assign_and_create_max_vfs(
                    test, params, vm, available_pci_slots
                )
                _boot_and_verify_max_vfs(
                    test, params, vm, pci_slots, action,
                )
            else:
                pci_slots = _assign_and_create(test, vm, available_pci_slots)
                _set_guest_iommu_cmdline(test, params, vm)
                _boot_and_verify(
                    test, params, vm, pci_slots, ext_host, ip_version, action,
                )
                if action == "live_migration":
                    _do_live_migration(
                        test, params, vm, pci_slots,
                        ext_host, ip_version,
                    )
        finally:
            vm.destroy(gracefully=False)
