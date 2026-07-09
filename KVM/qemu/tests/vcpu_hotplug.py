#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

# Author: Farrah Chen <farrah.chen@intel.com>
#
# History:  Jul. 2026 - Farrah Chen - creation

from provider import dmesg_router  # pylint: disable=unused-import

from virttest import env_process, error_context, utils_misc

from provider import cpu_utils


def _bring_online(session, cpu_ids):
    """Online each guest CPU by id (idempotent)."""
    for cid in cpu_ids:
        session.cmd_status(
            "echo 1 > /sys/devices/system/cpu/cpu%d/online" % cid
        )


def _bring_offline(session, cpu_ids):
    """Offline each guest CPU by id (idempotent)."""
    for cid in cpu_ids:
        session.cmd_status(
            "echo 0 > /sys/devices/system/cpu/cpu%d/online" % cid
        )


def _get_present_cpu_ids(session):
    """Return the set of cpu ids present in guest (online or offline)."""
    out = session.cmd_output("cat /sys/devices/system/cpu/present").strip()
    ids = set()
    for part in out.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            a, b = part.split("-")
            ids.update(range(int(a), int(b) + 1))
        else:
            ids.add(int(part))
    return ids


def _hotplug_all(test, vm, session, vcpu_devices, initial_ids, verify_timeout,
                 label):
    """Hotplug every configured vcpu device and verify guest CPU count."""
    for dev in vcpu_devices:
        error_context.context("Hotplug %s (%s)" % (dev, label), test.log.info)
        vm.hotplug_vcpu_device(dev)

    added_ids = sorted(_get_present_cpu_ids(session) - initial_ids)
    _bring_online(session, added_ids)

    if not utils_misc.wait_for(
        lambda: cpu_utils.check_if_vm_vcpus_match_qemu(vm),
        verify_timeout, first=2, step=2,
    ):
        test.fail("Guest CPU count mismatch after hotplug (%s)" % label)


def _hotunplug_all(test, vm, session, vcpu_devices, initial_ids,
                   verify_timeout, label):
    """Offline newly added CPUs, then hotunplug them and verify guest count."""
    added_ids = sorted(_get_present_cpu_ids(session) - initial_ids)
    _bring_offline(session, added_ids)

    for dev in vcpu_devices:
        error_context.context(
            "Hotunplug %s (%s)" % (dev, label), test.log.info
        )
        vm.hotunplug_vcpu_device(dev)

    if not utils_misc.wait_for(
        lambda: cpu_utils.check_if_vm_vcpus_match_qemu(vm),
        verify_timeout, first=2, step=2,
    ):
        test.fail("Guest CPU count mismatch after hotunplug (%s)" % label)


@error_context.context_aware
def run(test, params, env):
    """
    vCPU hotplug tests using QEMU device_add / device_del.

    Actions (selected via ``vcpu_action``):
    - ``hot_add``: hotplug every configured vcpu device and verify guest count.
    - ``hot_remove``: hotplug + verify, then hotunplug + verify.
    - ``repeat_hotplug``: repeat the hot_add + hot_remove cycle
      ``vcpu_iterations`` times.
    - ``multiple_hotplug``: hot_add + hot_remove with many devices in one cycle.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    action = params["vcpu_action"]
    iterations = params.get_numeric("vcpu_iterations", 1)
    verify_timeout = params.get_numeric("verify_wait_timeout", 60)
    login_timeout = params.get_numeric("login_timeout", 240)
    smp = params.get_numeric("smp")
    vcpu_devices = params.objects("vcpu_devices")

    params["start_vm"] = "yes"
    env_process.preprocess_vm(test, params, env, params["main_vm"])
    vm = env.get_vm(params["main_vm"])
    vm.verify_alive()
    session = vm.wait_for_login(timeout=login_timeout)

    try:
        initial_ids = _get_present_cpu_ids(session)
        if len(initial_ids) != smp:
            test.error(
                "Initial guest CPU count %d does not match smp=%d"
                % (len(initial_ids), smp)
            )

        if action == "hot_add":
            _hotplug_all(test, vm, session, vcpu_devices, initial_ids,
                         verify_timeout, "hot_add")
        elif action in ("hot_remove", "multiple_hotplug"):
            _hotplug_all(test, vm, session, vcpu_devices, initial_ids,
                         verify_timeout, action)
            _hotunplug_all(test, vm, session, vcpu_devices, initial_ids,
                           verify_timeout, action)
        elif action == "repeat_hotplug":
            for i in range(iterations):
                label = "iteration %d/%d" % (i + 1, iterations)
                _hotplug_all(test, vm, session, vcpu_devices, initial_ids,
                             verify_timeout, label)
                _hotunplug_all(test, vm, session, vcpu_devices, initial_ids,
                               verify_timeout, label)
        else:
            test.error("Unknown vcpu_action: %s" % action)
    finally:
        session.close()
