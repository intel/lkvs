#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

# Author: Kai Zhang <kai.zhang@intel.com>
#
# History:  Apr. 2026 - Kai Zhang - creation


from provider import dmesg_router  # pylint: disable=unused-import
from avocado.utils import process
from virttest import error_context, env_process
from provider.cpu_utils import check_cpu_flags


def check_confident(vm, session, dump_memory_path):
    session.cmd("mkdir -pv /tmp/mnt/")
    session.cmd("mount tmpfs /tmp/mnt/ -t tmpfs -o size=32M")
    vm.copy_files_to("/tmp/secret", "/tmp/mnt/")

    # paging = "off"
    process.system("rm -f %s && touch %s" % (dump_memory_path, dump_memory_path), ignore_status=True)
    vm.monitor.human_monitor_cmd("dump-guest-memory %s" % dump_memory_path)
    with open(dump_memory_path, '+rb') as f:
        content = f.read().decode('utf-8', errors='ignore')
        if "TDX Test" not in content:
            return False
    return True


@error_context.context_aware
def run(test, params, env):
    """
    TDX memory confidentiality test:
    1. Boot VM
    2. Write something in a file on host and copy it to tmpfs on VM
    3. Dump memory from VM, expect the secret could be found
    4. Boot TDVM
    5. Write something in a file on host and copy it to tmpfs on TDVM
    6. Dump memory from TDVM, expect the secret could not be found

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.

    This test will create both legacy VM and tdx-enabled VM.
    """
    with open("/tmp/secret", "w") as secret_file:
        secret_file.write("TDX Test: This is a test\n")
    dump_memory_path = params.get("dump_memory_path")
    params["start_vm"] = "yes"
    env_process.preprocess_vm(test, params, env, params["main_vm"])
    vm = env.get_vm(params["main_vm"])
    vm.verify_alive()
    timeout = params.get_numeric("login_timeout", 240)
    session = vm.wait_for_login(timeout=timeout)
    copy_result = check_confident(vm, session, dump_memory_path)
    if not copy_result:
        test.fail("Secret is not found in memory dump of legacy VM")
    session.close()
    vm.destroy()

    params["vm_secure_guest_type"] = "tdx"
    params["guest_flags"] = "tdx_guest"
    env_process.preprocess_vm(test, params, env, params["main_vm"])
    vm = env.get_vm(params["main_vm"])
    vm.verify_alive()
    timeout = params.get_numeric("login_timeout", 240)
    session = vm.wait_for_login(timeout=timeout)
    flags = params["guest_flags"]
    check_cpu_flags(params, flags, test, session)
    copy_result = check_confident(vm, session, dump_memory_path)
    if copy_result:
        test.fail("Secret is found in memory dump of TDVM")
    process.system("rm -f /tmp/secret %s" % params["dump_memory_path"], ignore_status=True)
    # TDVM will be destroyed as `kill_vm = yes` is set in cfg, no need to destroy it here.
    session.close()
