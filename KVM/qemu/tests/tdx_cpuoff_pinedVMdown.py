#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

# Author: Kai Zhang <kai.zhang@intel.com>
#
# History:  Apr. 2026 - Kai Zhang - creation

import re

from provider import dmesg_router  # pylint: disable=unused-import
from avocado.utils import process, cpu
from virttest import error_context, env_process
from provider.cpu_utils import check_cpu_flags


@error_context.context_aware
def run(test, params, env):
    """
    TDX CPU off pinned VM down test:
    1. Boot TDVM
    2. Pin a TD VM to a cpu, poweroff the cpu and shutdown the TD VM

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """

    with open("/tmp/cpuoff.sh", "w") as f:
        f.write("#! /bin/bash\n")
        f.write("sleep 6;\n")
        f.write(" echo 0 > /sys/devices/system/cpu/cpu18/online\n")
    process.system("chmod +x /tmp/cpuoff.sh")

    for i in range(0, 20):
        params["start_vm"] = "yes"
        env_process.preprocess_vm(test, params, env, params["main_vm"])
        vm = env.get_vm(params["main_vm"])
        vm.verify_alive()
        timeout = params.get_numeric("login_timeout", 240)
        session = vm.wait_for_login(timeout=timeout)
        if params.get("guest_flags"):
            flags = params["guest_flags"]
        check_cpu_flags(params, flags, test, session)
        pid = process.getoutput("ps -edf | grep qemu | grep -E 'avocado\-vt\-vm.*' | grep -v grep | awk '{print $2}'")
        process.system(f"taskset -pc 18 {pid}", ignore_status=True)
        process.SubProcess("/tmp/cpuoff.sh &")
        session.cmd("init 0 &", ignore_all_errors=True)
        process.system("sleep 3")

        hkid = params["hkid"]
        tdx_crash_flag = params["tdx_crash_flag"]
        dmesg = process.system_output("dmesg")
        hkid_str = re.findall(r'%s' % hkid, dmesg.decode('utf-8'))
        crash_str = re.findall(r'%s' % tdx_crash_flag, dmesg.decode('utf-8'))
        seamcall_failed_pattern = re.compile(r'^.*SEAMCALL.*failed.*$', re.MULTILINE)
        seamcall_failed_match = seamcall_failed_pattern.search(dmesg.decode('utf-8'))
        if hkid_str or crash_str or seamcall_failed_match:
            test.fail(f"Detected the crash information in {i} time run. Fail!")
        process.system("echo 1 > /sys/devices/system/cpu/cpu18/online")
        session.close()

    process.system("rm -f /tmp/cpuoff.sh")
    process.system("echo 1 > /sys/devices/system/cpu/cpu18/online")