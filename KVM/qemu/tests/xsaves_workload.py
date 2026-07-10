#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

import os
import re

from provider import cpu_utils
from provider import dmesg_router  # pylint: disable=unused-import
from provider import nbench_utils

from virttest import data_dir, env_process, error_context, utils_package


def _prepare_guest_workdir(session, guest_workdir):
    session.cmd("mkdir -p %s" % guest_workdir)
    session.cmd("rm -rf %s/*" % guest_workdir, ignore_all_errors=True)


def _copy_dep(vm, deps_dir, filename, guest_workdir):
    src = os.path.join(deps_dir, filename)
    if not os.path.isfile(src):
        raise IOError("deps file not found: %s" % src)
    vm.copy_files_to(src, guest_workdir)


def _run_vz(vm, session, test, params, deps_dir, guest_workdir):
    source_file = params["vz_source_file"]
    max_seconds = int(params["vz_max_runtime_seconds"])
    ratio_limit = int(params["vz_ratio_limit"])

    error_context.context("Copy %s to guest" % source_file, test.log.info)
    _copy_dep(vm, deps_dir, source_file, guest_workdir)

    error_context.context(
        "Compile vz and novz binaries in guest", test.log.info,
    )
    session.cmd(
        "cd %s && gcc -O0 -o vz %s -DVZ && gcc -O0 -o novz %s"
        % (guest_workdir, source_file, source_file),
        timeout=60,
    )

    error_context.context(
        "Run vz and novz, capture wall time via /usr/bin/time", test.log.info,
    )
    vz_time = _time_binary(session, guest_workdir, "vz", max_seconds)
    novz_time = _time_binary(session, guest_workdir, "novz", max_seconds)
    test.log.info(
        "vz=%.3fs novz=%.3fs (limit each %ds)",
        vz_time, novz_time, max_seconds,
    )

    if vz_time >= novz_time * ratio_limit:
        test.fail(
            "vz runtime %.3fs is >= %d x novz runtime %.3fs"
            % (vz_time, ratio_limit, novz_time)
        )
    if novz_time >= vz_time * ratio_limit:
        test.fail(
            "novz runtime %.3fs is >= %d x vz runtime %.3fs"
            % (novz_time, ratio_limit, vz_time)
        )


def _time_binary(session, guest_workdir, name, max_seconds):
    cmd = (
        "cd %s && /usr/bin/time -f '__WALL__%%e' ./%s 2>&1 1>/dev/null | "
        "grep '__WALL__' | tail -1"
    ) % (guest_workdir, name)
    out = session.cmd_output(cmd, timeout=max_seconds + 30).strip()
    m = re.search(r"__WALL__([\d.]+)", out)
    if not m:
        raise RuntimeError(
            "Failed to parse /usr/bin/time output for %s: %r" % (name, out)
        )
    return float(m.group(1))


def _run_security(vm, session, test, params, deps_dir, guest_workdir):
    source_file = params["security_source_file"]
    dmesg_pattern = params["security_dmesg_pattern"]

    error_context.context("Copy %s to guest" % source_file, test.log.info)
    _copy_dep(vm, deps_dir, source_file, guest_workdir)

    error_context.context(
        "Compile security payload in guest", test.log.info,
    )
    session.cmd(
        "cd %s && gcc -O0 -o security %s" % (guest_workdir, source_file),
        timeout=60,
    )

    error_context.context(
        "Clear dmesg and run security payload (expected to be killed)",
        test.log.info,
    )
    session.cmd("dmesg -c > /dev/null 2>&1", ignore_all_errors=True)
    exit_status = session.cmd_status(
        "cd %s && ./security" % guest_workdir, timeout=30,
    )
    test.log.info("security payload exited with status %d", exit_status)

    if exit_status == 0:
        test.fail(
            "security payload exited cleanly (0); kernel should have "
            "killed the process due to corrupted fpstate"
        )

    error_context.context(
        "Verify guest dmesg contains %r" % dmesg_pattern, test.log.info,
    )
    dmesg = session.cmd_output("dmesg | tail -20", timeout=30)
    if dmesg_pattern not in dmesg:
        test.fail(
            "Expected %r in guest dmesg after security payload run; "
            "got:\n%s" % (dmesg_pattern, dmesg)
        )
    test.log.info(
        "Guest kernel detected corrupt fpstate (%r in dmesg)", dmesg_pattern,
    )


def _run_nbench(session, test, params, guest_workdir):
    error_context.context(
        "Download, build and run nbench in guest", test.log.info,
    )
    nbench_utils.prepare_nbench(session, guest_workdir, params)
    nbench_utils.run_nbench(session, guest_workdir, params, test)


@error_context.context_aware
def run(test, params, env):
    """
    Exercise guest XSAVES via three self-contained user-space payloads.

    Variants:
        vz       - SSE + vzeroupper timing sanity check.
        security - corrupt sigframe fpstate; kernel must detect + terminate.
        nbench   - the nbench numeric benchmark suite as an FP workload.

    Cancels early if the host lacks the ``xsaves_flag``.
    """
    xsaves_flag = params["xsaves_flag"]
    workload_type = params["workload_type"]
    guest_workdir = params["guest_workdir"]
    deps_subdir = params["deps_subdir"]
    workload_packages = params.objects("workload_packages")

    error_context.context(
        "Check %s is available on host" % xsaves_flag, test.log.info,
    )
    cpu_utils.check_cpu_flags(params, xsaves_flag, test)

    error_context.context("Boot guest with cpu_model=host", test.log.info)
    params["start_vm"] = "yes"
    vm_name = params["main_vm"]
    env_process.preprocess_vm(test, params, env, vm_name)
    vm = env.get_vm(vm_name)
    vm.verify_alive()

    session = None
    try:
        session = vm.wait_for_login(
            timeout=int(params.get("login_timeout", 240)),
        )

        error_context.context(
            "Verify %s exposed to guest" % xsaves_flag, test.log.info,
        )
        cpu_utils.check_cpu_flags(
            params, xsaves_flag, test, session=session,
        )

        error_context.context(
            "Install workload build dependencies: %s"
            % " ".join(workload_packages),
            test.log.info,
        )
        if not utils_package.package_install(workload_packages, session):
            test.cancel(
                "Failed to install build dependencies %s inside guest"
                % workload_packages
            )

        deps_dir = data_dir.get_deps_dir(deps_subdir)
        _prepare_guest_workdir(session, guest_workdir)

        if workload_type == "vz":
            _run_vz(vm, session, test, params, deps_dir, guest_workdir)
        elif workload_type == "security":
            _run_security(vm, session, test, params, deps_dir, guest_workdir)
        elif workload_type == "nbench":
            _run_nbench(session, test, params, guest_workdir)
        else:
            test.error("Unknown workload_type: %r" % workload_type)
    finally:
        if session is not None:
            session.close()
        vm.destroy(gracefully=False)
