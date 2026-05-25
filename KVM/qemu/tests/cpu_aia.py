#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Kai Zhang <kai.zhang@intel.com>
#
# History:  May. 2026 - Kai Zhang - creation


from pathlib import Path

from provider import dmesg_router  # pylint: disable=unused-import
from avocado.utils import process
from virttest import env_process, error_context
from virttest import utils_package


def aia_test(vm, test, session, command):
    if not utils_package.package_install("gcc", session):
        test.cancel("Failed to install package gcc.")
    if not utils_package.package_install("make", session):
        test.cancel("Failed to install package make.")

    script_dir = Path(__file__).resolve().parent
    aia_deps_path = f"{script_dir}/../deps/aia"

    vm.copy_files_to(f"{aia_deps_path}/test.c", "~/")
    vm.copy_files_to(f"{aia_deps_path}/Makefile", "~/")
    vm.copy_files_to(f"{aia_deps_path}/libaia.h", "~/")

    session.cmd("cd ~ && make", ignore_all_errors=True)
    session.cmd(f"~/test {command} > ~/aia_test.log 2>&1", ignore_all_errors=True)

    vm.copy_files_from("~/aia_test.log", "/tmp/aia_test.log")
    with open("/tmp/aia_test.log", "r") as f:
        if "not supported" in f.read():
            test.fail(f"{command} not supported")
    session.cmd("rm -f ~/aia_test.log", ignore_all_errors=True)
    process.system("rm -f /tmp/aia_test.log")
    return


@error_context.context_aware
def run(test, params, env):
    """
    Test AIA related CPU features in VM:
    1. Boot VM
    2. Copy dependency script to VM and compile
    3. Run executable in VM and check whether selected AIA is enabled
    3. Destroy VM

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    params["start_vm"] = 'yes'
    env_process.preprocess_vm(test, params, env, params["main_vm"])
    vm = env.get_vm(params["main_vm"])
    vm.verify_alive()
    timeout = params.get_numeric("login_timeout", 240)
    session = vm.wait_for_login(timeout=timeout)

    command = params["test_command"]
    aia_test(vm, test, session, command)

    session.close()
