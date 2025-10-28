#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History: Sept. 2024 - Xudong Hao - creation

import os
import re
from avocado.core import exceptions
from virttest import error_context
from virttest import utils_package
from provider.test_utils import get_baremetal_dir


def prepare_test_suite(test, vm_test_path, session):
    """
    Compile test suite in guest.
    :param test: QEMU test object
    :param vm_test_path: The absolute path of test suite in guest
    :param session: Guest session
    """
    if not utils_package.package_install("gcc", session):
        test.cancel("Failed to install package gcc.")

    compile_cmd = "cd %s && make" % vm_test_path
    status = session.cmd_status(compile_cmd)
    if status:
        raise exceptions.TestError("Test suite compile failed.")


def avocado_install(test, params, guest_bm_path, vm, session):
    """
    Install test framework avocado in guest.
    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param guest_bm_path: The absolute path of BM in guest
    :param vm: The vm object
    :param session: Guest session
    """
    pip_packages = params["pip_packages"]
    if not utils_package.package_install(pip_packages, session):
        test.cancel("Failed to install package pip.")

    if "ubuntu" in vm.get_distro().lower():
        env_cmd = "python3 -m venv /root/.local/"
        session.cmd_status(env_cmd)
        pip_bin = "/root/.local/bin/pip"
    else:
        pip_bin = "pip"
    install_cmd = "%s list | grep avocado || %s install avocado-framework" % (pip_bin, pip_bin)
    status = session.cmd_status(install_cmd)
    if status:
        raise exceptions.TestError("Test framework installation failed.")

    # Some features running from dependence on cpuid_check
    compile_cmd = "cd %s/tools/cpuid_check && make" % guest_bm_path
    if session.cmd_status(compile_cmd):
        raise exceptions.TestError("Dependence test tool compile failed.")


def get_test_results(test, output, vm, session):
    """
    Install test framework avocado in guest.
    :param test: QEMU test object
    :param output: The output in guest test
    :param vm: The vm object
    :param session: Guest session
    """
    remove_str = "job.log"
    guest_log = re.sub(remove_str, "", re.search(r'.*JOB LOG\s*:\s(.*)', output).group(1))
    # Delete the symbolic link to avoid remote copy failure
    session.cmd("rm %s/test-results/by-status -rf" % guest_log, ignore_all_errors=True)

    error_context.context("Copy result log from guest to host.", test.log.info)
    try:
        vm.copy_files_from(guest_log, test.resultsdir)
    except Exception as err:
        test.log.warn("Log file copy failed: %s", err)
    session.cmd("rm %s -rf" % guest_log, ignore_all_errors=True)


@error_context.context_aware
def run(test, params, env):
    """
    Run feature functionality test inside guest.
    1) Check if current cpuid are support in host, if no, cancel test
    2) Boot up guest
    3) Check cpuid/s in guest
    4) Shutdown guest
    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    feature_dir_names = params["feature_dir_names"]
    vm = env.get_vm(params['main_vm'])
    session = vm.wait_for_login()

    # Copy BM test suite to guest
    test_dir = params["test_dir"]
    bm_dir = get_baremetal_dir(params)
    vm.copy_files_to(bm_dir, test_dir)
    guest_bm_path = os.path.join(test_dir, "BM")
    avocado_install(test, params, guest_bm_path, vm, session)

    try:
        for feature_dir_name in feature_dir_names.split():
            vm_test_path = os.path.join(guest_bm_path, feature_dir_name)
            prepare_test_suite(test, vm_test_path, session)
            cmd_timeout = params.get_numeric("cmd_timeout", 240)
            if params.get("cmd_timeout"):
                cmd_timeout = params.get_numeric("cmd_timeout")
            #run_cmd = "cd %s && ./runtests -f %s/tests" % (guest_bm_path, feature_dir_name)
            run_cmd = "cd %s && ./runtests.py -f %s -t %s/tests" % (guest_bm_path, feature_dir_name, feature_dir_name)
            s, o = session.cmd_status_output(run_cmd, timeout=cmd_timeout)

            get_test_results(test, o, vm, session)

            if s:
                test.fail("Feature %s test fail in guest." % feature_dir_name)

            #results dict for further debug
            #b = o.splitlines()[-2]
            #part = [i.split() for i in b.split(":")[1].split("|")]
            #results = dict(part)

            test.log.info("Guest feature %s test pass." % feature_dir_name)
    finally:
        session.cmd("rm %s -rf" % guest_bm_path, ignore_all_errors=True)
        session.close()
