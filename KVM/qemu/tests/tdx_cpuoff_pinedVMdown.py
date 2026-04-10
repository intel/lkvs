#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

# Author: Kai Zhang <kai.zhang@intel.com>
#
# History:  Apr. 2026 - Kai Zhang - creation

import random
import re
import time

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
    # TD can not boot up with vCPU number larger than host pCPU
    if cpu.online_count() < 64:
        test.cancel("Platform doesn't support to run this test")
    params["smp"] = 64

    for i in range(0, 20):
        params["start_vm"] = "yes"
        env_process.preprocess_vm(test, params, env, params["main_vm"])
        vm = env.get_vm(params["main_vm"])
        vm.verify_alive()
        timeout = params.get_numeric("login_timeout", 240)
        session = vm.wait_for_login(timeout=timeout)
        flags = params["guest_flags"]
        check_cpu_flags(params, flags, test, session)
        pid = vm.get_pid()

        host_cpu_list = cpu.online_list()
        processor_list = random.sample(host_cpu_list, 1)
        for processor in processor_list:
            process.system(f"taskset -pc {processor} {pid}", ignore_status=True)
            cpu.offline(processor)
        session.cmd("init 0 &", ignore_all_errors=True)
        time.sleep(3)

        hkid = params["hkid"]
        tdx_crash_flag = params["tdx_crash_flag"]
        dmesg = process.system_output("dmesg")
        hkid_str = re.findall(r'%s' % hkid, dmesg.decode('utf-8'))
        crash_str = re.findall(r'%s' % tdx_crash_flag, dmesg.decode('utf-8'))
        seamcall_failed_pattern = re.compile(r'^.*SEAMCALL.*failed.*$', re.MULTILINE)
        seamcall_failed_match = seamcall_failed_pattern.search(dmesg.decode('utf-8'))
        if hkid_str or crash_str or seamcall_failed_match:
            test.fail(f"Detected the crash information in {i} time run. Fail!")
        for processor in processor_list:
            cpu.online(processor)
        session.close()
