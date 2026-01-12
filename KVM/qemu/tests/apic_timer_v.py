#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History:  Jan. 2026 - Xudong Hao - creation

import os
import time
from avocado.utils import process, cpu
from virttest import error_context, data_dir, utils_misc


@error_context.context_aware
def run(test, params, env):
    """
    APIC Timer Virtualization test:
    1. Check if apic timer virtualization support by MSR on host
    2. Check apic and tscdeadline_timer test with feature enabled and disabled
    3. Check if VM-exit benifit from feature

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    def reload_module(value):
        """
        Reload module
        """
        read_cmd = params["read_cmd"]
        apic_timer_v = process.getoutput(read_cmd % mod_param)
        if apic_timer_v == value:
            return True
        process.system("rmmod %s" % module)
        cmd = "modprobe %s %s=%s" % (module, mod_param, value)
        process.system(cmd)
        apic_timer_v = process.getoutput(read_cmd % mod_param)
        if apic_timer_v != value:
            test.fail("APIC Timer Virtualization can not be configured correctly")

    def run_unit_test(kernel):
        src_test_binary = os.path.join(data_dir.get_deps_dir(), kernel)
        kernel_file = os.path.basename(src_test_binary)
        log_file = params["log_file"]
        test_cmd = params["test_cmd"] % src_test_binary

        qemu_bin = utils_misc.get_qemu_binary(params)
        qemu_cmd = "%s %s" % (qemu_bin, test_cmd)
        perf_cmd = params.get("perf_cmd")
        if perf_cmd:
            qemu_cmd = "%s %s" % (perf_cmd, qemu_cmd)
        process.system(cmd=qemu_cmd, verbose=True, ignore_status=True, shell=True)
        time.sleep(5)
        is_file = os.path.exists(log_file)
        if not is_file:
            test.fail("Can't find the log file %s" % log_file)
        try:
            with open(log_file, 'r') as file:
                content = file.read()
                if 'FAIL' in content:
                    test.fail("%s test fail" % kernel_file)
                else:
                    test.log.info("%s test pass" % kernel_file)
        finally:
            file.close()
            process.system("mv %s %s/%s.log" % (log_file, test.resultsdir, kernel_file))

    def parse_vm_exit_data(filename):
        with open(filename, 'r') as file:
            for line in file:
                line = line.strip()
                if 'MSR_WRITE' in line:
                    samples = int(line.split()[1])
                    break
            return samples

    if cpu.get_cpu_vendor_name() != 'intel':
        test.cancel("This test is supposed to run on Intel host")

    rdmsr_cmd = params["rdmsr_cmd"]
    if process.getoutput(rdmsr_cmd) != "1":
        test.fail("Platform does not support APIC Timer Virtualization")
    test.log.info("Platform supports APIC Timer Virtualization")

    module = params["module_name"]
    mod_param = params["mod_param"]
    user_on_off = params.get_boolean("check_interface")
    if user_on_off:
        reload_module("Y")
        reload_module("N")

    test_enable = params.get_boolean("test_enable")
    if test_enable:
        reload_module("Y")
        source_file = params["source_file1"]
        run_unit_test(source_file)
        source_file = params["source_file2"]
        run_unit_test(source_file)

    test_disable = params.get_boolean("test_disable")
    if test_disable:
        reload_module("N")
        source_file = params["source_file1"]
        run_unit_test(source_file)
        source_file = params["source_file2"]
        run_unit_test(source_file)

    perf_vmexit = params.get_boolean("perf_vmexit")
    if perf_vmexit:
        source_file = params["source_file2"]
        reload_module("N")
        run_unit_test(source_file)
        off_kvm_stat_log = os.path.join(test.resultsdir, "off_kvm_stat.log")
        process.system("perf kvm stat report >& %s" % off_kvm_stat_log, shell=True)
        vmexit_off = parse_vm_exit_data(off_kvm_stat_log)
        process.system("rm perf.data.guest -f", shell=True, ignore_status=True)
        reload_module("Y")
        run_unit_test(source_file)
        on_kvm_stat_log = os.path.join(test.resultsdir, "on_kvm_stat.log")
        process.system("perf kvm stat report >& %s" % on_kvm_stat_log, shell=True)
        vmexit_on = parse_vm_exit_data(on_kvm_stat_log)
        process.system("rm perf.data.guest -f", shell=True, ignore_status=True)
        if vmexit_on > vmexit_off/100:
            test.fail("VMExit data is not expected with APIC Timer Virtualization")
