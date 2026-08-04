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

import json
import logging
import re
import time

from aexpect.remote import wait_for_login
from virttest import utils_misc, utils_net

from provider.hostdev import DEV_CLASSES, PCI_DEV_PATH, PCI_DRV_PATH

LOG_JOB = logging.getLogger("avocado.test")

# Some guests colorize `ip`/other tool output (e.g. an `ip -color` alias), which
# leaves ANSI escape sequences in serial command output and corrupts the values
# we parse out of it (an IP would come back as "\x1b[35m192.168.0.1\x1b[0m").
# Strip ANSI control sequences from serial console captures. Covers not only
# SGR color codes (final byte `m`) but also the bracketed-paste mode toggles
# (`\x1b[?2004h` / `\x1b[?2004l`) bash emits around every command. Without
# stripping the paste-off sequence, the first line of `cmd_output_safe`
# stdout carries a `\x1b[?2004l` prefix, which silently corrupts the ifname
# parsed for the first interface in a batch listing.
_ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")


def get_pci_by_class(dev_class, driver=None):
    """
    Get device pci slots by given device type and driver

    Args:
        dev_class (str): The device class type, e.g.: "network"
        driver (str): Driver used by devices

    Returns: A list of all matched devices
    """
    pci_ids = set()
    class_id = DEV_CLASSES.get(dev_class)
    for dev_path in PCI_DEV_PATH.iterdir():
        if dev_path.joinpath("class").read_text()[2:4] != class_id:
            continue
        pci_ids.add(dev_path.name)
    if driver:
        pci_ids &= set(get_pci_by_driver(driver))
    return sorted(pci_ids)


def get_pci_by_driver(driver):
    """
    Get device pci slots by given driver

    Args:
        driver (str): Driver used by devices

    Returns: A list of all matched devices
    """
    driver_path = PCI_DRV_PATH / driver
    pci_ids = {
        pci_path.name
        for pci_path in driver_path.glob("**/[0-9a-z]*:[0-9a-z]*:[0-9a-z]*.[0-9a-z]*")
    }
    return sorted(pci_ids)


def get_pci_by_dev_type(dev_type, dev_class, driver=None):
    """

    Args:
        dev_type (str): "pf" or "vf" you want to filter
        dev_class: The device class type, e.g.: "network"
        driver: Driver used by devices

    Returns: A list of all matched devices

    """
    dev_type = dev_type.lower()
    if dev_type not in ["pf", "vf"]:
        raise ValueError(f'Device type({dev_type}) must be "pf" or "vf"')
    pf_pci_ids = []
    vf_pci_ids = []
    pci_ids = get_pci_by_class(dev_class, driver)
    for pci in pci_ids:
        if PCI_DEV_PATH.joinpath(pci, "physfn").exists():
            vf_pci_ids.append(pci)
        else:
            pf_pci_ids.append(pci)

    return pf_pci_ids if dev_type == "pf" else vf_pci_ids


def get_parent_slot(slot_id):
    """
    Get the device parent id. If it's a VF device, return the physical parent
    device ID. Otherwise, return the slot_id itself.

    Args:
        slot_id (str): The device slot ID, e.g.: '0000:01:00.0'

    Returns: The parent slot id
    """
    physfn_path = PCI_DEV_PATH / slot_id / "physfn"
    if physfn_path.exists():
        return physfn_path.resolve().name
    return slot_id


def get_ifname_from_pci(pci_slot):
    """
    Get the NIC device name from its pci slot id.

    Args:
        pci_slot (str): The slot id of the NIC device

    Returns: The NIC name from its pci slot

    """
    pci_net_path = PCI_DEV_PATH / pci_slot / "net"
    if pci_net_path.exists():
        try:
            return next((PCI_DEV_PATH / pci_slot / "net").iterdir()).name
        except OSError as e:
            LOG_JOB.error("Cannot get the NIC name of %s: %s", pci_slot, str(e))
            return ""


def get_guest_ip_from_mac(vm, mac, ip_version=4):
    """
    Get IP address from MAC address with selected IP version

    Args:
        vm (virttest.qemu_vm.VM): The vm object
        mac (str): The MAC address of the VM's network interface
        ip_version (int): IP version to use for connecting (default is IPv4)

    Returns: The IP address if found
    """
    if ip_version not in [4, 6]:
        raise ValueError(f"Unsupported IP version: {ip_version}")
    ip_addr = ""
    os_type = vm.params["os_type"]
    serial_session = vm.wait_for_serial_login()

    try:
        if os_type == "linux":
            addr_family = "inet" if ip_version == 4 else "inet6"
            # Disable readline bracketed-paste in the serial shell so command
            # outputs are not prefixed with \x1b[?2004l escapes that break
            # downstream JSON parsing.
            serial_session.cmd_output_safe(
                "bind 'set enable-bracketed-paste off' 2>/dev/null; true"
            )
            for ifname in utils_net.get_linux_ifname(serial_session):
                link_out = utils_misc.strip_console_codes(
                    serial_session.cmd_output_safe(f"ip -j link show {ifname}")
                )
                nic_info = json.loads(link_out)[0]
                if nic_info["address"] == mac:
                    if "(disconnected)" in serial_session.cmd_output_safe(
                        f"nmcli -g GENERAL.STATE device show {ifname}"
                    ):
                        serial_session.cmd(f"nmcli device up {ifname}")
                    addr_out = utils_misc.strip_console_codes(
                        serial_session.cmd_output_safe(f"ip -j addr show {ifname}")
                    )
                    ip_info = json.loads(addr_out)[0]
                    for addr_info in ip_info["addr_info"]:
                        if (
                            addr_info["family"] == addr_family
                            and addr_info["scope"] == "global"
                        ):
                            ip_addr = addr_info["local"]
                else:
                    if "(connected)" in serial_session.cmd_output_safe(
                        f"nmcli -g GENERAL.STATE device show {ifname}"
                    ):
                        serial_session.cmd(f"nmcli device down {ifname}")
        elif os_type == "windows":
            ifname = utils_net.get_windows_nic_attribute(
                serial_session, "macaddress", mac, "netconnectionid"
            )
            utils_net.enable_windows_guest_network(serial_session, ifname)
            nic_info = utils_net.get_net_if_addrs_win(serial_session, mac)
            ip_addr = nic_info["ipv4"] if ip_version == 4 else nic_info["ipv6"]
        else:
            raise ValueError("Unknown os type")
    finally:
        serial_session.close()
    LOG_JOB.info("IP address of MAC address(%s) is: %s", mac, ip_addr)
    return ip_addr


def get_guest_ips_from_macs(vm, macs, timeout=240, poll_interval=5,
                            stall_cycles=6):
    """
    Resolve the guest IPv4 address of many MAC addresses in a single pass.

    Unlike get_guest_ip_from_mac(), this opens one serial session and never
    issues a per-interface command per MAC, which does not scale to the dozens
    of VFs a max-VF guest owns. It also avoids large `ip -j` JSON dumps: a
    64-interface dump is routinely truncated on a busy serial console, so the
    MAC -> ifname map is built from tiny sysfs reads and IPs are polled with
    compact one-line `ip -o` output. Target interfaces are activated once, then
    the whole set is polled until every MAC has a global address, the timeout
    expires, or IP acquisition plateaus (a lab DHCP pool smaller than the VF
    count can never satisfy every MAC).

    Args:
        vm (virttest.qemu_vm.VM): The vm object
        macs (list): MAC addresses to resolve
        timeout (int): Overall seconds to wait for all IPs
        poll_interval (int): Seconds between poll cycles
        stall_cycles (int): Stop after this many poll cycles with no new IP
            (only once at least one address has been obtained)

    Returns: dict mapping each lowercased MAC to its IP ("" if unresolved)
    """
    wanted = {m.lower() for m in macs}
    result = {m: "" for m in wanted}
    serial_session = vm.wait_for_serial_login()
    try:
        # Build MAC -> ifname from sysfs (one tiny read per NIC) rather than a
        # huge `ip -j link show` dump the serial console would truncate.
        mac_dump = serial_session.cmd_output_safe(
            "for i in /sys/class/net/*; do "
            'echo "$(basename "$i") $(cat "$i"/address)"; done'
        )
        mac_to_if = {}
        for line in _ANSI_RE.sub("", mac_dump).splitlines():
            fields = line.split()
            if len(fields) == 2 and fields[1].lower() in wanted:
                mac_to_if[fields[1].lower()] = fields[0]

        # Activate every target interface so NetworkManager runs DHCP on it.
        # `-w 0` returns immediately, so 64 activations do not serialise on
        # per-device connect timeouts.
        iflist = " ".join(mac_to_if.values())
        if iflist:
            serial_session.cmd_output_safe(
                f"for i in {iflist}; do "
                "nmcli -w 0 device connect $i >/dev/null 2>&1; done",
                timeout=120,
            )

        deadline = time.time() + timeout
        resolved = 0
        stall = 0
        while True:
            # Compact one-line-per-address output: "<idx>: <if> inet <ip>/..".
            addr_dump = serial_session.cmd_output_safe(
                "ip -o -4 addr show scope global"
            )
            if_to_ip = {}
            for line in _ANSI_RE.sub("", addr_dump).splitlines():
                fields = line.split()
                if len(fields) >= 4 and fields[2] == "inet":
                    if_to_ip[fields[1]] = fields[3].split("/")[0]
            for mac, ifname in mac_to_if.items():
                if not result[mac] and ifname in if_to_ip:
                    result[mac] = if_to_ip[ifname]
            now_resolved = sum(1 for m in wanted if result[m])
            if all(result[m] for m in wanted) or time.time() >= deadline:
                break
            # Stop early once IP acquisition plateaus: a lab DHCP pool smaller
            # than the VF count will never satisfy every MAC, so waiting out the
            # full timeout is pointless once no new address appears for a while.
            if now_resolved > resolved:
                resolved = now_resolved
                stall = 0
            elif resolved:
                stall += 1
                if stall >= stall_cycles:
                    break
            # Re-trigger activation for any interface still without an address;
            # a fire-and-forget connect can occasionally miss a straggler.
            pending = " ".join(
                mac_to_if[m] for m in wanted if not result[m] and m in mac_to_if
            )
            if pending:
                serial_session.cmd_output_safe(
                    f"for i in {pending}; do "
                    "nmcli -w 0 device connect $i >/dev/null 2>&1; done",
                    timeout=120,
                )
            time.sleep(poll_interval)
    finally:
        serial_session.close()
    for mac in sorted(wanted):
        LOG_JOB.info("IP address of MAC address(%s) is: %s", mac, result[mac])
    return result


def ssh_login_from_ip(vm, ip_addr):
    """
    Establish an SSH login session to a VM given an already-resolved guest IP.

    Args:
        vm (virttest.qemu_vm.VM): The vm object
        ip_addr (str): The guest IP address to connect to

    Returns: The ssh session object, or None if ip_addr is empty
    """
    if not ip_addr:
        return None
    username = vm.params.get("username", "")
    password = vm.params.get("password", "")
    prompt = vm.params.get("shell_prompt", r"[\#\$]\s*$")
    port = vm.params.get("shell_port")
    linesep = vm.params.get("shell_linesep", "\n").encode().decode("unicode_escape")
    log_filename = (
        f'session-{vm.name}-{time.strftime("%m-%d-%H-%M-%S")}-'
        f"{utils_misc.generate_random_string(4)}.log"
    )
    log_filename = utils_misc.get_log_filename(log_filename)
    log_function = utils_misc.log_line
    return wait_for_login(
        "ssh",
        ip_addr,
        port,
        username,
        password,
        prompt,
        linesep,
        log_filename,
        log_function,
    )


def ssh_login_from_mac(vm, mac, ip_version=4):
    """
    Establish an SSH login session to a VM using its MAC address.

    Args:
        vm (virttest.qemu_vm.VM): The vm object
        mac (str): The MAC address of the VM's network interface
        ip_version (int): IP version to use for connecting (default is IPv4)

    Returns: The ssh session object
    """
    ip_addr = get_guest_ip_from_mac(vm, mac, ip_version)
    return ssh_login_from_ip(vm, ip_addr)
