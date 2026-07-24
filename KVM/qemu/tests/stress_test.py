#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

"""
CPU / memory / IO / disk stress workload inside a KVM guest.

Boots one guest, installs the configured stress tool, runs it with the
configured worker/duration parameters, and verifies the tool's completion
banner reports "successful".
"""

from provider import dmesg_router  # pylint: disable=unused-import
from virttest import env_process
from virttest import error_context
from virttest import utils_package


def _run_stress(test, session, params):
    """
    Run the configured stress tool inside the guest and return the tail of
    its output log.

    :param test: QEMU test object
    :param session: active guest login session
    :param params: Cartesian params dict for the current case
    :return: last line of the stress log captured in the guest
    """
    tool = params["stress_tool"]
    stress_cpu = params.get_numeric("stress_cpu")
    stress_vm_workers = params.get_numeric("stress_vm_workers")
    stress_vm_bytes = params["stress_vm_bytes"]
    stress_io = params.get_numeric("stress_io")
    stress_hdd = params.get_numeric("stress_hdd")
    stress_hdd_bytes = params["stress_hdd_bytes"]
    stress_timeout = params.get_numeric("stress_timeout")

    if not utils_package.package_install(tool, session):
        test.cancel(f"Installation of {tool} failed; please install it manually.")

    guest_log = f"/tmp/{tool.replace('-', '_')}.log"
    session.cmd(f"rm -f {guest_log}")

    # stress and stress-ng share the same option layout for these flags.
    cmd = (
        f"{tool} --cpu {stress_cpu} --io {stress_io} "
        f"--vm {stress_vm_workers} --vm-bytes {stress_vm_bytes} "
        f"--hdd {stress_hdd} --hdd-bytes {stress_hdd_bytes} "
        f"--timeout {stress_timeout} > {guest_log} 2>&1"
    )
    # Allow the guest command up to timeout + 120s slack for setup / teardown.
    session.cmd(cmd, timeout=stress_timeout + 120, ignore_all_errors=True)

    tail_line = session.cmd_output(f"tail -n 1 {guest_log}").strip()
    session.cmd(f"rm -f {guest_log}")
    return tail_line


@error_context.context_aware
def run(test, params, env):
    """
    Run stress or stress-ng inside a guest and verify successful completion.

    Steps:
        1. Boot a single guest per case parameters.
        2. Install the configured stress tool inside the guest.
        3. Run the tool with configured worker / memory / disk / timeout
           parameters.
        4. Verify the tool's completion line reports "successful".

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """
    params["start_vm"] = "yes"

    vm_name = params["main_vm"]
    env_process.preprocess_vm(test, params, env, vm_name)
    vm = env.get_vm(vm_name)
    vm.verify_alive()

    login_timeout = params.get_numeric("login_timeout", 240)
    session = vm.wait_for_login(timeout=login_timeout)
    try:
        error_context.context(
            f"Running {params['stress_tool']} in guest for "
            f"{params.get_numeric('stress_timeout')}s",
            test.log.info,
        )
        tail_line = _run_stress(test, session, params)
        test.log.info("Stress tool tail line: %s", tail_line)

        fields = tail_line.split()
        status = fields[3] if len(fields) >= 4 else ""
        if status != "successful":
            test.fail(
                f"{params['stress_tool']} did not report successful "
                f"completion; last line: {tail_line!r}"
            )
    finally:
        session.close()
