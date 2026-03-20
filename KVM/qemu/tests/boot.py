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

from provider import dmesg_router  # pylint: disable=unused-import
import re
import time

from avocado.utils import cpu
from virttest import env_process
from virttest import error_context
from virttest import test_setup
from virttest import utils_misc
from virttest import utils_test


def _get_hugepage_size_mb(params):
    kernel_hp_file = params.get("kernel_hp_file", "/proc/sys/vm/nr_hugepages")
    if kernel_hp_file != "/proc/sys/vm/nr_hugepages":
        match = re.search(r"hugepages-(\d+)kB", kernel_hp_file)
        if match:
            return max(int(match.group(1)) // 1024, 1)

    with open("/proc/meminfo", "r", encoding="utf-8") as meminfo_file:
        for line in meminfo_file:
            if line.startswith("Hugepagesize:"):
                return max(int(line.split()[1]) // 1024, 1)

    raise ValueError("Could not determine hugepage size from /proc/meminfo")


def _update_dynamic_params(test, params):
    params["start_vm"] = "yes"

    if params.get_boolean("is_high_mem"):
        host_cpu = cpu.online_count()
        host_free_mem = utils_misc.get_usable_memory_size()
        hugepage_size_mb = _get_hugepage_size_mb(params)
        aligned_mem = (host_free_mem // 2 // hugepage_size_mb) * hugepage_size_mb
        if aligned_mem < hugepage_size_mb:
            test.cancel("Platform doesn't have enough free memory for one hugepage-backed guest")
        params["smp"] = params["vcpu_maxcpus"] = max(host_cpu // 2, 1)
        params["mem"] = aligned_mem
    elif params.get_boolean("is_low_mem"):
        params["mem"] = params.get_numeric("mem", 1024)

    if params.get("vm_secure_guest_type") == "tdx":
        host_cpu = cpu.online_count()
        if params.get_numeric("smp", 1) > host_cpu:
            test.cancel("Platform doesn't support to run this test")


def _setup_manual_hugepages(params):
    hugepage_config = test_setup.HugePageConfig(params)
    suggest_mem = hugepage_config.setup()
    if suggest_mem is not None:
        hugepage_size_mb = _get_hugepage_size_mb(params)
        params["mem"] = (suggest_mem // hugepage_size_mb) * hugepage_size_mb
    if not params.get("hugepage_path"):
        params["hugepage_path"] = hugepage_config.hugepage_path
    return hugepage_config


@error_context.context_aware
def run(test, params, env):
    """
    Boot a guest with hugepage-related settings and optionally reboot it.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """

    hugepage_config = None
    try:
        _update_dynamic_params(test, params)

        if params.get_boolean("manual_hugepage_setup"):
            hugepage_config = _setup_manual_hugepages(params)

        vm_name = params["main_vm"]
        env_process.preprocess_vm(test, params, env, vm_name)

        timeout = float(params.get("login_timeout", 240))
        serial_login = params.get("serial_login", "no") == "yes"
        vms = env.get_all_vms()
        for vm in vms:
            error_context.context("Try to log into guest '%s'." % vm.name,
                                  test.log.info)
            if serial_login:
                session = vm.wait_for_serial_login(timeout=timeout)
            else:
                session = vm.wait_for_login(timeout=timeout)
            session.close()

        if params.get("rh_perf_envsetup_script"):
            for vm in vms:
                if serial_login:
                    session = vm.wait_for_serial_login(timeout=timeout)
                else:
                    session = vm.wait_for_login(timeout=timeout)
                utils_test.service_setup(vm, session, test.virtdir)
                session.close()

        if params.get("reboot_method"):
            for vm in vms:
                error_context.context("Reboot guest '%s'." % vm.name,
                                      test.log.info)
                if params["reboot_method"] == "system_reset":
                    time.sleep(int(params.get("sleep_before_reset", 10)))
                if serial_login:
                    session = vm.wait_for_serial_login(timeout=timeout)
                else:
                    session = vm.wait_for_login(timeout=timeout)
                for _ in range(int(params.get("reboot_count", 1))):
                    session = vm.reboot(session,
                                        params["reboot_method"],
                                        0,
                                        timeout,
                                        serial_login)
                session.close()
    finally:
        if hugepage_config is not None:
            hugepage_config.cleanup()