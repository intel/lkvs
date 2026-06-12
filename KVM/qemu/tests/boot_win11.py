#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

# Author: Kai Zhang <kai.zhang@intel.com>
#
# History:  Jun. 2026 - Kai Zhang - creation

import re
import base64
import time

from provider import dmesg_router  # pylint: disable=unused-import
from virttest import env_process, error_context, guest_agent


def _append_param(params, key, value):
    values = params.get(key, "").split()
    if value not in values:
        values.append(value)
        params[key] = " ".join(values)


def get_cmd_output(gagent, exe, args=None):
    pid = gagent.cmd(
        cmd="guest-exec",
        args={
            "path": exe,
            "arg": args,
            "capture-output": True,
        },
    )["pid"]
    while True:
        status = gagent.guest_exec_status(pid) or {}
        if status.get("exited"):
            break
        time.sleep(1)

    log = base64.b64decode(status.get("out-data", "")).decode("utf-8", errors="replace")
    return log


@error_context.context_aware
def run(test, params, env):
    """
    Windows 11 host boot test:
    1. Boot VM with windows 11 image and login through qemu guest agent
    2. Get os version related information
    3. Get driver related information
    4. Destroy VM

    Windows host cannot use session to run command, use qemu guest agent.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    params["start_vm"] = 'yes'
    params["bios_path"] = params.get("boot_win11_bios_path", "")
    gagent_name = params.get("gagent_name", "org.qemu.guest_agent.0")
    _append_param(params, "serials", gagent_name)
    params["serial_type_%s" % gagent_name] = "virtserialport"
    params["serial_name_%s" % gagent_name] = gagent_name
    env_process.preprocess_vm(test, params, env, params["main_vm"])
    vm = env.get_vm(params["main_vm"])
    vm.verify_alive()

    drivers_keywords = params.get("drivers_keywords", "VirtIO vio").split()
    drivers_pattern = "|".join(drivers_keywords)

    error_context.context("Connect to QEMU guest agent.", test.log.info)
    filename = vm.get_serial_console_filename(gagent_name)
    gagent_params = params.object_params(gagent_name)
    gagent_params["monitor_filename"] = filename

    gagent = guest_agent.QemuAgent(
        vm, gagent_name, "virtio", gagent_params, get_supported_cmds=True)
    gagent.verify_responsive()

    error_context.context("Get OS version and name.", test.log.info)
    output = get_cmd_output(gagent, "cmd.exe", ["/c", "ver"])
    test.log.info("%s", output)
    output = get_cmd_output(gagent, "cmd.exe", ["/c", "wmic os get Name"])
    test.log.info("%s", output)

    error_context.context("Get driver version information in guest.", test.log.info)
    system_drivers = get_cmd_output(gagent, "cmd.exe", ["/c", "wmic sysdriver get DisplayName,PathName"])
    test.log.debug("Drivers exist in the system:\n %s", system_drivers)

    test.log.info(system_drivers)

    for driver in system_drivers.splitlines():
        if re.findall(drivers_pattern, driver, re.I):
            driver_info = driver.strip().split()
            driver_name = " ".join(driver_info[:-1])
            path = driver_info[-1]
            path = re.sub(r"\\", "\\\\\\\\", path)
            driver_ver_cmd = "wmic datafile where name="
            driver_ver_cmd += "'%s' get version" % path
            output = get_cmd_output(gagent, "cmd.exe", ["/c", driver_ver_cmd])
            msg = "Driver %s" % driver_name
            msg += " version is %s" % output.strip().split()[-1]
            test.log.info(output)
            test.log.info(msg)
