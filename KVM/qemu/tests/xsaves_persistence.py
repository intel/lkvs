#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

# Author: Farrah Chen <farrah.chen@intel.com>
#
# History:  Jul. 2026 - Farrah Chen - creation

import os
import re
import time

from provider import cpu_utils
from provider import dmesg_router  # pylint: disable=unused-import

from virttest import data_dir, env_process, error_context, utils_package
from virttest.staging import utils_memory


_NBENCH_RESULT_RE = re.compile(
    r"^\s*(NUMERIC SORT|STRING SORT|BITFIELD|FP EMULATION|FOURIER|"
    r"ASSIGNMENT|IDEA|HUFFMAN|NEURAL NET|LU DECOMPOSITION)\b"
)


def _prepare_nbench(session, deps_dir, guest_workdir, params, vm):
    session.cmd("mkdir -p %s" % guest_workdir)
    session.cmd("rm -rf %s/*" % guest_workdir, ignore_all_errors=True)

    tarball = params["nbench_tarball"]
    extracted = params["nbench_extracted_dir"]

    src = os.path.join(deps_dir, tarball)
    if not os.path.isfile(src):
        raise IOError("deps file not found: %s" % src)
    vm.copy_files_to(src, guest_workdir)

    session.cmd(
        "cd %s && tar xzf %s" % (guest_workdir, tarball), timeout=60,
    )
    session.cmd(
        "cd %s/%s && sed -i 's/-static//' Makefile && make"
        % (guest_workdir, extracted),
        timeout=180,
    )


def _run_nbench_short(session, guest_workdir, params, test, label):
    extracted = params["nbench_extracted_dir"]
    max_seconds = int(params["nbench_max_runtime_seconds"])
    min_lines = int(params["nbench_min_result_lines"])

    out = session.cmd_output(
        "cd %s/%s && stdbuf -oL timeout %d ./nbench 2>&1"
        % (guest_workdir, extracted, max_seconds),
        timeout=max_seconds + 60,
    )
    result_lines = [
        line for line in out.splitlines() if _NBENCH_RESULT_RE.match(line)
    ]
    test.log.info(
        "%s: nbench emitted %d result lines (need >= %d)",
        label, len(result_lines), min_lines,
    )
    for line in result_lines[:min_lines]:
        test.log.info("  %s", line)
    if len(result_lines) < min_lines:
        test.fail(
            "%s: nbench produced %d result lines; expected >= %d. Tail:\n%s"
            % (
                label,
                len(result_lines),
                min_lines,
                "\n".join(out.splitlines()[-10:]),
            )
        )


def _do_save_restore(vm, test, params):
    save_file = params["save_file"]
    login_timeout = int(params.get("login_timeout", 240))

    error_context.context("Pause VM", test.log.info)
    vm.pause()

    error_context.context(
        "Save VM state to file %s (exec:cat migration)" % save_file,
        test.log.info,
    )
    vm.save_to_file(save_file)

    error_context.context(
        "Restore VM from file %s" % save_file, test.log.info,
    )
    time.sleep(5)
    utils_memory.drop_caches()
    vm.restore_from_file(save_file)
    vm.resume()

    session = vm.wait_for_login(timeout=login_timeout)
    return session


def _do_live_migrate(vm, test, params):
    mig_timeout = int(params.get("mig_timeout", 300))
    mig_protocol = params.get("mig_protocol", "tcp")

    error_context.context(
        "Live migrate guest locally (%s)" % mig_protocol, test.log.info,
    )
    vm.migrate(mig_timeout, mig_protocol)

    session = vm.wait_for_login(
        timeout=int(params.get("login_timeout", 240)),
    )
    return session


@error_context.context_aware
def run(test, params, env):
    """
    Verify XSAVES survives save/restore or live migration.

    Variants:
        sr - pause + save_to_file + restore_from_file round-trip.
        lm - vm.migrate() to a fresh local QEMU instance.

    In both cases, the guest must still expose XSAVES afterwards and the
    nbench FP workload must still complete.
    """
    xsaves_flag = params["xsaves_flag"]
    mode = params["persistence_mode"]
    guest_workdir = params["guest_workdir"]
    deps_subdir = params["deps_subdir"]
    workload_packages = params.objects("workload_packages")
    save_file = params.get("save_file")

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
            "Verify %s exposed to guest before %s" % (xsaves_flag, mode),
            test.log.info,
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
        _prepare_nbench(session, deps_dir, guest_workdir, params, vm)

        error_context.context(
            "Run baseline nbench workload (pre-%s)" % mode, test.log.info,
        )
        _run_nbench_short(session, guest_workdir, params, test, "pre-%s" % mode)

        if mode == "sr":
            session.close()
            session = _do_save_restore(vm, test, params)
        elif mode == "lm":
            session.close()
            session = _do_live_migrate(vm, test, params)
        else:
            test.error("Unknown persistence_mode: %r" % mode)

        error_context.context(
            "Verify %s still exposed to guest after %s"
            % (xsaves_flag, mode),
            test.log.info,
        )
        cpu_utils.check_cpu_flags(
            params, xsaves_flag, test, session=session,
        )

        error_context.context(
            "Re-run nbench workload (post-%s)" % mode, test.log.info,
        )
        _run_nbench_short(
            session, guest_workdir, params, test, "post-%s" % mode,
        )
    finally:
        if session is not None:
            try:
                session.close()
            except Exception as exc:  # pylint: disable=broad-except
                test.log.warning("Failed to close guest session: %s", exc)
        if save_file and os.path.exists(save_file):
            try:
                os.remove(save_file)
            except OSError as exc:
                test.log.warning(
                    "Failed to remove save file %s: %s", save_file, exc,
                )
        vm.destroy(gracefully=False)
