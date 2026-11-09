#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

from provider import dmesg_router  # pylint: disable=unused-import
from virttest import error_context, utils_net

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
    # VFDevice subclasses PFDevice, so `isinstance(x, PFDevice)` is True
    # for both; use strict type equality to distinguish here.
    if type(slot_manager) is hostdev.PFDevice:
        return slot_manager.mac_addresses[0]
    slot_index = slot_manager.vfs.index(slot)
    return slot_manager.mac_addresses[slot_index]


def _verify_vf_ping(test, params, vm, vf_slot, ext_host, ip_version):
    """
    SSH into vm via the VF MAC and ping ext_host once to confirm the
    passthrough NIC path is functional.
    """
    mac_addr = _resolve_vf_mac(vf_slot, params)
    session = hostdev_utils.ssh_login_from_mac(
        vm, mac_addr, int(ip_version[-1])
    )
    if not session:
        test.fail(
            f"Cannot log into {vm.name} via VF {vf_slot} MAC {mac_addr}"
        )
    try:
        error_context.context(
            f"Ping {ext_host} from {vm.name} via VF {vf_slot}", test.log.info
        )
        s_ping, _ = utils_net.ping(
            ext_host,
            10,
            session=session,
            timeout=30,
            force_ipv4=(ip_version == "ipv4"),
        )
        if s_ping:
            test.fail(
                f"Fail to ping {ext_host} from {vm.name} via VF {vf_slot}"
            )
    finally:
        session.close()


def _assign_and_create(test, vm, available_pci_slots):
    """
    Wire the required VF slot into vm.params and boot the guest. Returns
    the list of assigned VF slots so callers can track them explicitly.
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


def _violent_disable_and_check(test, vm, pf_manager, vf_slot):
    """
    While the guest is actively using vf_slot through vfio-pci, drop
    sriov_numvfs on the PF to 0 to yank the VF out from under it. Then
    verify:

      * the VF BDF is no longer present in host lspci;
      * the guest no longer sees any 'Virtual Function' PCI device.

    The guest is polled via the serial console because SSH via the killed
    VF NIC will not survive the drop.
    """
    pf_slot = pf_manager.slot_id
    serial_session = vm.wait_for_serial_login(timeout=240)
    try:
        # Baseline: guest should see at least the one assigned VF.
        _, out = serial_session.cmd_status_output(
            "lspci | grep -ci 'virtual function' || true", timeout=30
        )
        vf_count_before = int(out.strip().splitlines()[-1] or "0")
        test.log.info(
            "VFs visible in %s guest before violent disable: %d",
            vm.name, vf_count_before,
        )
        if vf_count_before < 1:
            test.fail(
                f"{vm.name} did not see the VF via lspci before violent "
                f"disable"
            )

        error_context.context(
            f"Violently dropping sriov_numvfs to 0 on {pf_slot}",
            test.log.info,
        )
        try:
            pf_manager.sriov_numvfs_path.write_text("0")
        except OSError as e:
            test.fail(f"Failed to write 0 to {pf_manager.sriov_numvfs_path}: {e}")
        # Reflect the state change in the manager so hostdev_setup's
        # restore() will re-create VFs (not just no-op) at cleanup time.
        pf_manager.vfs = []

        # Host side check: the assigned VF BDF must be gone from lspci.
        result = process.run(
            f"lspci -s {vf_slot}", ignore_status=True, shell=True,
        )
        stdout = result.stdout_text if hasattr(result, "stdout_text") else ""
        if stdout.strip():
            test.fail(
                f"VF {vf_slot} still present in host lspci after violent "
                f"disable: {stdout.strip()}"
            )
        test.log.info("VF %s no longer visible in host lspci", vf_slot)

        # Guest side check via serial: no Virtual Function should remain.
        _, out = serial_session.cmd_status_output(
            "lspci | grep -ci 'virtual function' || true", timeout=30
        )
        vf_count_after = int(out.strip().splitlines()[-1] or "0")
        test.log.info(
            "VFs visible in %s guest after violent disable: %d",
            vm.name, vf_count_after,
        )
        if vf_count_after != 0:
            test.fail(
                f"{vm.name} still saw a Virtual Function in lspci after "
                f"violent disable"
            )
    finally:
        try:
            serial_session.close()
        except Exception:  # pylint: disable=broad-except
            pass


@error_context.context_aware
def run(test, params, env):
    """
    VFIO NIC violent-disable stress:

      1. Assign a single VF to the guest and verify SSH + ping via the VF.
      2. While the guest is still running, write 0 to the PF's
         sriov_numvfs to yank all VFs off the bus.
      3. Confirm the VF BDF is gone from the host and no Virtual Function
         is visible inside the guest anymore.
      4. Destroy that guest, re-create the SR-IOV VF pool on the PF, and
         boot a second guest with a fresh VF; verify SSH + ping again to
         prove the PF/VF machinery recovered from the violent teardown.
    """
    ip_version = params["ip_version"]
    if not params.get("vm_hostdev_iommufd"):
        _iommu_type1_available(test)
        dma_cmd = params.get("dma_cmd")
        if dma_cmd:
            status = process.system(dma_cmd, shell=True)
            if status:
                raise exceptions.TestError(
                    "Failed to increase dma_entry_limit."
                )

    with hostdev_setup(params) as params:
        pf_slots = params.objects("setup_hostdev_slots")
        if not pf_slots:
            raise exceptions.TestError(
                "setup_hostdev_slots is required for vfio_net_disable"
            )
        pf_slot = pf_slots[0]
        pf_manager = params[f"hostdev_manager_{pf_slot}"]
        pf_hostdev_params = params.object_params(pf_slot)
        ext_host = params.get(
            "ext_host", utils_net.get_host_ip_address(ip_ver=ip_version)
        )

        vm = env.get_all_vms()[0]
        try:
            # Phase 1: boot with 1 VF, verify, violent disable.
            error_context.context(
                "Phase 1: boot guest with one VF and validate connectivity",
                test.log.info,
            )
            available = hostdev_utils.get_pci_by_dev_type(
                params.get("hostdev_assignment_type"),
                "network",
                params.get("vm_hostdev_driver", "vfio-pci"),
            )
            pci_slots = _assign_and_create(test, vm, available)
            _verify_vf_ping(
                test, params, vm, pci_slots[0], ext_host, ip_version
            )
            _violent_disable_and_check(test, vm, pf_manager, pci_slots[0])
            vm.destroy(gracefully=False)

            # Phase 2: recreate the VF pool and boot a fresh guest on it.
            error_context.context(
                f"Phase 2: re-configuring VFs on {pf_slot} and rebooting guest",
                test.log.info,
            )
            pf_manager.config(pf_hostdev_params)
            available = hostdev_utils.get_pci_by_dev_type(
                params.get("hostdev_assignment_type"),
                "network",
                params.get("vm_hostdev_driver", "vfio-pci"),
            )
            pci_slots = _assign_and_create(test, vm, available)
            _verify_vf_ping(
                test, params, vm, pci_slots[0], ext_host, ip_version
            )
        finally:
            vm.destroy(gracefully=False)
