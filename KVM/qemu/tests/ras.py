#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2025 Intel Corporation

# Author: Farrah Chen <farrah.chen@intel.com>
#
# History: Nov. 2025 - Farrah Chen - creation

import os
import re
from avocado.utils import process
from avocado.core import exceptions
from virttest import error_context, env_process
from virttest import utils_package
from virttest import data_dir as virttest_data_dir


def prepare_vm_victim(test, params, vm, session):
    """
    Compile test tool victim in guest.
    Return the execuable test tool with absolute path.
    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param vm: The vm object
    :param session: Guest session
    """
    source_file = params["source_file"]
    exec_file = params["exec_file"]
    test_dir = params["test_dir"]
    deps_dir = virttest_data_dir.get_deps_dir('ras')
    src_path = os.path.join(deps_dir, source_file)
    vm.copy_files_to(src_path, test_dir)
    if not utils_package.package_install("gcc", session):
        test.cancel("Failed to install package gcc.")
    compile_cmd = "cd %s && gcc %s -o %s" % (test_dir, source_file, exec_file)
    status = session.cmd_status(compile_cmd)
    if status:
        raise exceptions.TestError("Victim compile failed.")
    session.cmd("rm -rf %s/%s" % (test_dir, source_file))

    return os.path.join(test_dir, exec_file)


def error_inject(test, params, addr):
    """
    Check if kernel module einj is loaded, if not, load it.
    Inject error via einj
    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param addr: Host physical address
    """
    module = 'einj'
    if module not in process.system_output('lsmod').decode('utf-8'):
        if process.system('modprobe %s' % module, shell=True) != 0:
            test.cancel("module %s isn't supported ?" % module)
    debugfs = '/sys/kernel/debug'
    einj_path = os.path.join(debugfs, 'apei/einj/')
    if not os.path.exists(einj_path):
        test.cancel("error injection isn't supported, check your BIOS setting")
    error_type = params.get('error_type')
    status = process.system("echo %s > %s/error_type" % (error_type, einj_path), shell=True)
    if status:
        raise exceptions.TestError("Failed to inject error %s" % error_type)
    status = process.system("echo %s > %s/param1" % (addr, einj_path), shell=True)
    if status:
        raise exceptions.TestError("Failed to inject error to address %s" % addr)
    status = process.system("echo 0xfffffffffffff000 > %s/param2" % einj_path, shell=True)
    if status:
        raise exceptions.TestError("Failed to inject mask to param2")
    status = process.system("echo 1 > %s/notrigger" % einj_path, shell=True)
    if status:
        raise exceptions.TestError("Failed to enable notrigger")
    status = process.system("echo 1 > %s/error_inject" % einj_path, shell=True)
    if status:
        raise exceptions.TestError("Failed to inject error")


@error_context.context_aware
def run(test, params, env):
    """
    Inject error to guest memory.
    0) Before executing this case, enable error injection, disable Patrol Scrub in BIOS
    1) Boot up guest
    2) Run victim in guest to get a physical address in guest
    3) Run gpa2hpa in QEMU monitor to get it's host physical address
    4) Return to host, inject error to this address by einj
    5) Return to guest victim, "enter" to trigger error
    6) Shutdown guest
    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    try:
        vm_name = params['main_vm']
        env_process.preprocess_vm(test, params, env, vm_name)
        vm = env.get_vm(vm_name)
        session = vm.wait_for_login()
        vm_exec_bin = prepare_vm_victim(test, params, vm, session)
        victim_cmd = '%s -d -k 0 > /tmp/vmpha.log &' % vm_exec_bin
        session.cmd(victim_cmd)
        vmpha_cmd = 'cat /tmp/vmpha.log'
        output = session.cmd_output(vmpha_cmd)
        guest_pha = output.split()[5]
        output = vm.monitor.send_args_cmd("gpa2hpa %s" % guest_pha)
        host_pha = output.split()[7]
        error_inject(test, params, host_pha)
        test_dir = params["test_dir"]
        vm_trigger_cmd = 'echo "trigger" > %s/trigger_start' % test_dir
        session.cmd(vm_trigger_cmd)
        hw_mce = 'err_code:0x00a0:0x0090  SystemAddress:0x%s' % host_pha.lstrip('0x')
        vm_mce = 'mce: Uncorrected hardware memory error in user-access at %s' % guest_pha.lstrip('0x')
        hw_dmesg = process.system_output('dmesg').decode('utf-8')
        vm_dmesg = session.cmd_output('dmesg')
        hw_status = re.search('%s' % hw_mce, hw_dmesg)
        if not hw_status:
            raise exceptions.TestError("Failed to trigger MCE in host")
        vm_status = re.search('%s' % vm_mce, vm_dmesg)
        if not vm_status:
            raise exceptions.TestError("Failed to trigger MCE in guest")
        vm.verify_dmesg()

    finally:
        session.cmd("rm -rf /tmp/vmpha.log")
        session.cmd("rm -rf %s/trigger_start" % test_dir)
        session.cmd("rm -rf %s" % vm_exec_bin)
        session.close()
