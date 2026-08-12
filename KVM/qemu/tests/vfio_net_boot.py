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

import os
import shutil
import tempfile
import time

from provider import dmesg_router  # pylint: disable=unused-import
from virttest import error_context, remote, utils_net

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


def _boot_and_verify(test, params, vm, pci_slots, ext_host, ip_version, action):
    """
    Log into vm via each assigned VF's MAC, ping ext_host, and run the
    selected extra action (e.g. scp) on the last established session.
    """
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


def _run_hotswap_action(test, params, env, ext_host, ip_version):
    """Execute hotswap-based actions used by vtd_ras_* variants."""
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
    pci_slot = available_pci_slots[0]
    hotswap_iterations = params.get_numeric("hotplug_iterations", 2)

    # Boot the guest with the VF pre-attached so QEMU creates the
    # pcie-root-port + vfio-pci pair at cold-plug time. simple_hotplug only
    # supports inserting a single QDevice per call, so the root port must be
    # present before we plug the hostdev.
    vm.params[f"vm_hostdev_host_{dev_name}"] = pci_slot
    vm.create(params=vm.params)
    vm.verify_alive()
    vm.wait_for_serial_login(timeout=240).close()
    # Detach the cold-plugged hostdev to bring the guest into the "no VF"
    # baseline expected by _hotplug_cycle (which starts with plug).
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
    Log into vm via every assigned VF MAC and ping ext_host once per VF to
    confirm the VF NICs are functional after a guest lifecycle event.
    Unlike _boot_and_verify, this opens a fresh session per VF so it is safe
    to call repeatedly across reboots and re-creations.
    """
    for slot in pci_slots:
        mac_addr = _resolve_vf_mac(slot, params)
        session = hostdev_utils.ssh_login_from_mac(
            vm, mac_addr, int(ip_version[-1])
        )
        if not session:
            test.fail(
                f"Cannot log into {vm.name} via VF {slot} MAC {mac_addr}"
            )
        try:
            _ping_from_vm(test, vm, session, ext_host, ip_version)
        finally:
            session.close()


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

    Setting hostdev_serial_vfs = yes reruns the boot+verify loop once per VF
    exposed by the PF, each time booting a single-hostdev guest that owns
    exactly one VF, so a serial (successive) VF assignment path is covered.

    dma_cmd (used to raise dma_entry_limit for large VF pools) is only
    executed for TDX guests where the default kernel limit is otherwise hit
    during hostdev setup; other guest types keep the kernel default.
    """
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
            _run_hotswap_action(test, params, env, ext_host, ip_version)
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

        vm = env.get_all_vms()[0]
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
                finally:
                    vm.destroy(gracefully=False)
            return

        try:
            pci_slots = _assign_and_create(test, vm, available_pci_slots)
            _boot_and_verify(
                test, params, vm, pci_slots, ext_host, ip_version, action,
            )
        finally:
            vm.destroy(gracefully=False)
