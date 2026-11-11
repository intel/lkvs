#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

# Author: Farrah Chen <farrah.chen@intel.com>

"""
Test CET (Control-flow Enforcement Technology) exposure on guest.

This handler validates the hypervisor side of CET, covering:
- exposed: SHSTK and IBT are exposed to the guest by default (host and guest
  CPUID bits set, user_shstk/ibt flags present on host and guest).
- xsave: CET bits in the XSAVES state are enabled (CPUID.0xD sub-leaves and
  IA32_XSS bit) on the guest.
- unexposed: SHSTK and IBT are not exposed to the guest when CET is disabled
  on the guest kernel cmdline, on the host, or on the qemu command line.
"""

from provider import dmesg_router  # pylint: disable=unused-import
from avocado.utils import process
from virttest import error_context, env_process, utils_package
from provider.test_utils import (
    get_baremetal_dir,
    require_guest_command,
)
from provider.cpuid_utils import check_cpuid, prepare_cpuid
from provider.cpu_utils import check_cpu_flags


def _host_flags(flags, session=None):
    """
    Read the CPU flags reported by lscpu on host or guest.

    :param flags: Space separated flags to look for
    :param session: Guest session, None for host
    :return: List of the requested flags that are present
    """
    cmd = "lscpu | grep Flags | awk -F ':'  '{print $2}'"
    func = session.cmd_output if session else process.getoutput
    out = func(cmd).split()
    return [f for f in flags.split() if f in out]


def _check_cpuid_list(test, cpuid_args, exec_bin, session, is_host):
    """
    Run a comma separated list of CPUID checks and judge the result.

    :param test: QEMU test object
    :param cpuid_args: Comma separated CPUID argument strings
    :param exec_bin: The cpuid_check executable with absolute path
    :param session: Guest session, None for host
    :param is_host: True for host check(cancel on miss), False for guest(fail)
    """
    for cpuid_arg in cpuid_args.split(","):
        cpuid_arg = cpuid_arg.strip()
        if check_cpuid(cpuid_arg, exec_bin, session):
            if is_host:
                test.cancel("Host CPUID does not support '%s'" % cpuid_arg)
            test.fail("Guest CPUID check '%s' fail" % cpuid_arg)


def _disable_guest_cet(test, vm, session, timeout):
    """
    Disable CET on the guest kernel cmdline and reboot the guest.

    :param test: QEMU test object
    :param vm: The VM object
    :param session: Guest session
    :param timeout: Login timeout while waiting for the reboot
    :return: New guest session after the reboot
    """
    disable_args = "nousershstk ibt=off"
    cmd = "grubby --update-kernel=ALL --args='%s'" % disable_args
    if session.cmd_status(cmd) != 0:
        test.cancel("Failed to update guest kernel cmdline with grubby")

    session = vm.reboot(session, timeout=timeout)
    cmdline = session.cmd_output("cat /proc/cmdline")
    if "ibt=off" not in cmdline:
        test.fail("Guest did not boot with CET disabled on the kernel cmdline")
    return session


@error_context.context_aware
def run(test, params, env):
    """
    Test CET exposure on guest.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    cet_test_type = params["cet_test_type"]
    cet_flags = params["cet_flags"]
    test_dir = params["test_dir"]
    login_timeout = params.get_numeric("login_timeout", 360)
    bm_dir = get_baremetal_dir(params)
    src_dir = "%s/%s" % (bm_dir, params["cpuid_src_subdir"])

    host_exec_bin = None
    session = None
    grub_disabled = False
    try:
        if cet_test_type == "unexposed" and params["disable_method"] == "host":
            # This case requires host kernel cmdline "ibt=off clearcpuid=519".
            error_context.context("Check host CET is disabled", test.log.info)
            if _host_flags(cet_flags):
                test.cancel("Host CET is enabled; boot the host with "
                            "'ibt=off clearcpuid=519' on the kernel cmdline")

        if params.get_boolean("check_host_cpuid"):
            error_context.context("Check CET CPUID on host", test.log.info)
            host_exec_bin = prepare_cpuid(test, params, src_dir)
            _check_cpuid_list(test, params["host_cpuid"], host_exec_bin,
                              None, True)
            if cet_test_type == "exposed":
                check_cpu_flags(params, cet_flags, test)

        error_context.context("Boot guest for CET check", test.log.info)
        params["start_vm"] = "yes"
        vm_name = params["main_vm"]
        env_process.preprocess_vm(test, params, env, vm_name)
        vm = env.get_vm(vm_name)
        session = vm.wait_for_login()

        if cet_test_type in ("exposed", "xsave"):
            error_context.context("Check CET CPUID on guest", test.log.info)
            vm_exec_bin = prepare_cpuid(test, params, src_dir, vm, session)
            _check_cpuid_list(test, params["guest_cpuid"], vm_exec_bin,
                              session, False)
            guest_only_cpuid = params.get("guest_only_cpuid")
            if guest_only_cpuid:
                _check_cpuid_list(test, guest_only_cpuid, vm_exec_bin,
                                  session, False)

        if cet_test_type == "exposed":
            error_context.context("Check CET flags on guest", test.log.info)
            check_cpu_flags(params, cet_flags, test, session)

        if cet_test_type == "xsave":
            error_context.context("Check IA32_XSS CET bit on guest",
                                  test.log.info)
            utils_package.package_install("msr-tools", session)
            require_guest_command(test, session, "rdmsr", "msr-tools")
            msr_cmd = "modprobe msr && rdmsr %s -f %s" % (
                params["xss_msr"], params["xss_msr_bitfield"])
            xss_value = session.cmd_output(msr_cmd).strip()
            if xss_value != "1":
                test.fail("IA32_XSS %s bit %s is not set on guest, got '%s'" % (
                    params["xss_msr"], params["xss_msr_bitfield"], xss_value))

        if cet_test_type == "unexposed":
            if params["disable_method"] == "guest_cmdline":
                error_context.context("Disable CET on guest cmdline",
                                      test.log.info)
                session = _disable_guest_cet(test, vm, session, login_timeout)
                grub_disabled = True
            error_context.context("Check CET flags are absent on guest",
                                  test.log.info)
            check_cpu_flags(params, "", test, session)

        vm.verify_kernel_crash()
    finally:
        if grub_disabled and session:
            try:
                session.cmd("grubby --update-kernel=ALL "
                            "--remove-args='nousershstk ibt=off'")
            except Exception:  # pylint: disable=broad-except
                pass
        if host_exec_bin:
            process.system("rm -f %s" % host_exec_bin, shell=True,
                           ignore_status=True)
        if session:
            try:
                session.cmd("rm -f %s/cpuid*" % test_dir, ignore_all_errors=True)
                session.close()
            except Exception:  # pylint: disable=broad-except
                pass
