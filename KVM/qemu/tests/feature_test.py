#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History: Sept. 2024 - Xudong Hao - creation

from provider import dmesg_router  # pylint: disable=unused-import
import os
import re
import aexpect
from avocado.core import exceptions
from virttest import error_context
from virttest import utils_package
from provider.test_utils import get_baremetal_dir
from provider.cpu_utils import check_cpu_flags


def prepare_test_suite(test, vm_test_path, session):
    """
    Compile test suite in guest.
    :param test: QEMU test object
    :param vm_test_path: The absolute path of test suite in guest
    :param session: Guest session
    """
    vm_test_makefile = os.path.join(vm_test_path, 'Makefile')
    if session.cmd_status("test -f %s" % vm_test_makefile):
        return

    if not utils_package.package_install("gcc", session):
        test.cancel("Failed to install package gcc.")

    compile_cmd = "cd %s && make" % vm_test_path
    status, output = session.cmd_status_output(compile_cmd, timeout=300)
    if status:
        test.log.error("make in %s failed (exit=%d):\n%s",
                       vm_test_path, status, output)
        raise exceptions.TestError(
            "Test suite compile failed (exit=%d): %s"
            % (status, output.strip().splitlines()[-1] if output.strip()
               else "<no output>"))


def _build_cpuid_check(test, guest_bm_path, session):
    """
    Build BM/tools/cpuid_check inside the guest.

    The migrate-before-test path skips avocado_install() to reduce SSH
    churn, but scenarios still depend on the cpuid_check binary for their
    `# @hw_dep` line. Build it explicitly on the stable pre-migration
    session so the sequential runner can resolve it via PATH.
    """
    tool_path = os.path.join(guest_bm_path, "tools", "cpuid_check")
    if not utils_package.package_install("gcc", session):
        test.cancel("Failed to install package gcc.")
    build_cmd = "cd %s && make" % tool_path
    status, output = session.cmd_status_output(build_cmd, timeout=120)
    if status:
        test.log.error("make in %s failed (exit=%d):\n%s",
                       tool_path, status, output)
        raise exceptions.TestError(
            "cpuid_check build failed (exit=%d)" % status)


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


def disable_parallel_run(test, session):
    """
    Disable parallel execution in guest.

    The pre-modification state of the avocado config is captured and returned so
    the caller can restore it after the case, avoiding leaking the setting into
    other cases running on the same persistent guest image.
    :param test: QEMU test object
    :param session: Guest session
    :return: dict describing the original state, for restore_parallel_run().
    """
    conf_file = "/etc/avocado/avocado.conf"
    conf_bak = "/tmp/lkvs_avocado_conf.bak"
    dir_exists = session.cmd_status("ls -d /etc/avocado") == 0
    conf_exists = session.cmd_status("ls %s" % conf_file) == 0
    if conf_exists:
        # Preserve the original config so it can be restored later.
        session.cmd("cp -f %s %s" % (conf_file, conf_bak), ignore_all_errors=True)
    else:
        cmd = "mkdir -p /etc/avocado && touch %s" % conf_file
        status, output = session.cmd_status_output(cmd)
        if status:
            test.error("Fail to create config file in guest: %s" % output)

    cmd = "cat %s | grep max_parallel_tasks=1" % conf_file
    if session.cmd_status(cmd):
        conf_content = "[run]\\nmax_parallel_tasks=1"
        cmd = "echo -e '%s' > %s" % (conf_content, conf_file)
        status, output = session.cmd_status_output(cmd)
        if status:
            test.error("Fail to add configurations in guest file: %s" % output)

    return {"dir_exists": dir_exists, "conf_exists": conf_exists}


def restore_parallel_run(session, state):
    """
    Restore /etc/avocado/avocado.conf to the pre-modification default state
    recorded by disable_parallel_run().
    :param session: Guest session
    :param state: dict returned by disable_parallel_run()
    """
    conf_file = "/etc/avocado/avocado.conf"
    conf_bak = "/tmp/lkvs_avocado_conf.bak"
    if not state["dir_exists"]:
        # We created /etc/avocado; remove it entirely.
        session.cmd("rm -rf /etc/avocado", ignore_all_errors=True)
    elif state["conf_exists"]:
        # Restore the original config content.
        session.cmd("mv -f %s %s" % (conf_bak, conf_file), ignore_all_errors=True)
    else:
        # Directory existed but the config file did not; drop what we created.
        session.cmd("rm -f %s" % conf_file, ignore_all_errors=True)


def migrate_and_verify_flags(test, params, vm, session, flags):
    """
    Live migrate the guest and verify the cpu flags survive the migration.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param vm: The vm object
    :param session: Guest session before migration
    :param flags: Space separated cpu flags to verify (e.g. "user_shstk ibt")
    :return: New guest session after the migration
    """
    mig_timeout = float(params.get("mig_timeout", 300))
    login_timeout = params.get_numeric("login_timeout", 240)

    error_context.context("Verify host exposes flags before migration.",
                          test.log.info)
    check_cpu_flags(params, flags, test)

    error_context.context("Verify guest exposes flags before migration.",
                          test.log.info)
    cmd = "lscpu | grep Flags | awk -F ':' '{print $2}'"
    guest_flags = session.cmd_output(cmd).split()
    missing = [f for f in flags.split() if f not in guest_flags]
    if missing:
        test.cancel("Guest does not expose flags %s, skip test" % missing)

    session.close()
    error_context.context("Live migrate the guest.", test.log.info)
    vm.migrate(timeout=mig_timeout)

    session = vm.wait_for_login(timeout=login_timeout)
    error_context.context("Verify guest keeps flags after migration.",
                          test.log.info)
    try:
        check_cpu_flags(params, flags, test, session)
    except aexpect.ShellError:
        # Occasionally the freshly-attached SSH channel drops right after
        # migration. Re-login once and retry the post-migration verification.
        test.log.warning("Post-migrate session dropped, re-login once")
        session = _reconnect(session, vm, login_timeout)
        check_cpu_flags(params, flags, test, session)
    return session


def _parse_dep_line(line):
    """
    Parse a `# @hw_dep/@other_dep/@other_warn` header line from a scenario
    file, using the same semantics as BM/runtests.py.

    :param line: raw line from the scenario file
    :return: tuple (kind, cmd, reason) where kind is one of "hw_dep",
             "other_dep", "other_warn" or None if the line is not a header.
             cmd is the dependency check command (or None) and reason is
             the human readable reason string (or None).
    """
    stripped = line.strip()
    if stripped.startswith("# @hw_dep"):
        kind = "hw_dep"
    elif stripped.startswith("# @other_dep"):
        kind = "other_dep"
    elif stripped.startswith("# @other_warn"):
        kind = "other_warn"
    else:
        return None, None, None
    if ":" not in stripped:
        return kind, None, None
    info = stripped.split(":", 1)[1].strip()
    if not info:
        return kind, None, None
    if "@" in info:
        cmd, reason = [x.strip() for x in info.split("@", 1)]
    else:
        cmd, reason = info, None
    return kind, cmd, reason


def _reconnect(session, vm, login_timeout):
    """Best-effort close-and-relogin used when the guest SSH channel drops."""
    try:
        session.close()
    except Exception:  # pylint: disable=broad-except
        pass
    return vm.wait_for_login(timeout=login_timeout)


def _read_scenario_lines(session, vm, login_timeout, scen_path):
    """
    Return the raw lines of a scenario file inside the guest.

    :param session: Guest session
    :param vm: The vm object (used to re-login on transient SSH drop)
    :param login_timeout: seconds to allow for a re-login attempt
    :param scen_path: Absolute path of the scenario file in the guest
    :return: (session, list of raw lines) - session may be a fresh re-login
    """
    try:
        output = session.cmd_output("cat %s" % scen_path)
    except aexpect.ShellError:
        session = _reconnect(session, vm, login_timeout)
        output = session.cmd_output("cat %s" % scen_path)
    return session, output.splitlines()


def _run_one_subtest(test, session, vm, feature_path, env_prefix, cmd,
                     per_subtest_timeout, login_timeout):
    """
    Run one subtest command in the guest via the current shell session.

    A single SSH re-login retry is attempted to absorb the post-migrate
    channel drops observed on cet_lm. Returns a tuple (session, status,
    output). status is None if the session died twice in a row (the caller
    treats that as an unrecoverable per-subtest failure).
    """
    run_cmd = ("cd %s && %s timeout %d %s"
               % (feature_path, env_prefix, per_subtest_timeout, cmd))
    session_timeout = per_subtest_timeout + 30
    try:
        status, output = session.cmd_status_output(
            run_cmd, timeout=session_timeout, safe=True)
        return session, status, output
    except aexpect.ShellError as err:
        test.log.warning("Guest SSH dropped mid-subtest (%s), re-login once",
                         err)
    session = _reconnect(session, vm, login_timeout)
    try:
        status, output = session.cmd_status_output(
            run_cmd, timeout=session_timeout, safe=True)
        return session, status, output
    except aexpect.ShellError as err:
        test.log.error("Guest SSH dropped again, giving up on subtest: %s",
                       err)
        return session, None, str(err)


def run_scenarios_sequential(test, params, session, vm, guest_bm_path,
                             feature_dir_name, scen, cmd_timeout):
    """
    Run each subtest of a scenario file directly over the guest shell.

    Compared with nesting an in-guest avocado job per subtest, this keeps
    session churn low (one command per subtest instead of four) which is
    important right after live migration when the SSH channel is more
    fragile. Each subtest is bounded by a bash `timeout` and a single
    re-login retry is used to absorb transient channel drops.

    Dependency headers (`# @hw_dep`, `# @other_dep`, `# @other_warn`) are
    honoured with the same semantics as BM/runtests.py: hw_dep and other_dep
    failures cancel the test, other_warn failures only log a warning.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param session: Guest session
    :param vm: The vm object (used to re-login when the session drops)
    :param guest_bm_path: The absolute path of BM in guest
    :param feature_dir_name: e.g. "cet"
    :param scen: scenario file basename, e.g. "tests-shstk"
    :param cmd_timeout: overall guest-side per-subtest budget in seconds
    :return: the current guest session (possibly refreshed on retry)
    """
    del cmd_timeout  # kept for signature symmetry with the nested-avocado path
    feature_path = os.path.join(guest_bm_path, feature_dir_name)
    scen_path = os.path.join(feature_path, scen)
    session, lines = _read_scenario_lines(
        session, vm, params.get_numeric("login_timeout", 240), scen_path)

    # BM/runtests.py extends PATH with common/ and tools/cpuid_check so
    # bare names like general_test.sh and cpuid_check resolve. Include the
    # feature directory itself as well so the leading token of a subtest
    # line (e.g. cet_tests.sh) resolves without an explicit ./ prefix.
    env_prefix = ('PATH="$PATH:%s:%s/common:%s/tools/cpuid_check"'
                  % (feature_path, guest_bm_path, guest_bm_path))
    per_subtest_timeout = params.get_numeric("subtest_timeout", 120)
    login_timeout = params.get_numeric("login_timeout", 240)

    subtests = []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        kind, dep_cmd, reason = _parse_dep_line(line)
        if kind is not None:
            if dep_cmd is None:
                continue
            dep_run = ("cd %s && %s %s >/dev/null 2>&1"
                       % (feature_path, env_prefix, dep_cmd))
            try:
                status = session.cmd_status(
                    dep_run, timeout=per_subtest_timeout)
            except aexpect.ShellError:
                session = _reconnect(session, vm, login_timeout)
                status = session.cmd_status(
                    dep_run, timeout=per_subtest_timeout)
            if status == 0:
                continue
            if kind == "other_warn":
                test.log.warning("Scenario %s dependency warning: %s",
                                 scen, reason or dep_cmd)
                continue
            test.cancel("Scenario %s cannot run: %s"
                        % (scen, reason or dep_cmd))
        if stripped.startswith("#"):
            continue
        subtests.append(stripped)

    if not subtests:
        test.log.info("Scenario %s has no runnable subtests.", scen)
        return session

    failures = []
    timeouts = []
    total = len(subtests)
    for idx, cmd in enumerate(subtests, 1):
        test.log.info("[seq %s %d/%d] %s", scen, idx, total, cmd)
        session, status, output = _run_one_subtest(
            test, session, vm, feature_path, env_prefix, cmd,
            per_subtest_timeout, login_timeout)
        # BM/cet's "no_cp" glibc_shstk_test subtests occasionally SIGSEGV or
        # emit a spurious dmesg hit on this host. Give any non-zero exit
        # (including timeouts) a single retry so the migrate-verification
        # signal is not drowned out by an inherently-flaky BM subtest.
        if status is None or status != 0:
            reason = ("SSH dropped" if status is None
                      else "timeout" if status == 124
                      else "exit=%d" % status)
            test.log.warning("[seq %s %d/%d] %s, retrying once",
                             scen, idx, total, reason)
            session, status, output = _run_one_subtest(
                test, session, vm, feature_path, env_prefix, cmd,
                per_subtest_timeout, login_timeout)
        if status is None or status == 124:
            timeouts.append(cmd)
            continue
        if status != 0:
            failures.append(cmd)
            test.log.warning("[seq %s %d/%d] FAIL exit=%d\n%s",
                             scen, idx, total, status, output.strip())

    if failures or timeouts:
        summary = "%d/%d fail, %d timeout in scenario %s" % (
            len(failures), total, len(timeouts), scen)
        test.log.error("%s\nfailed: %s\ntimeouts: %s",
                       summary, failures, timeouts)
        test.fail("Feature %s %s sequential-run: %s"
                  % (feature_dir_name, scen, summary))
    test.log.info("Scenario %s sequential-run passed %d/%d subtests.",
                  scen, total, total)
    return session


def get_test_results(test, output, vm, session):
    """
    Copy guest avocado run result to host.
    :param test: QEMU test object
    :param output: The output in guest test
    :param vm: The vm object
    :param session: Guest session
    """
    # BM test may be terminated with some reasons, then no valid result.
    test_terminate = "Terminate the test"
    if test_terminate in output:
        test.fail("Guest %s " % output)

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
    migrate_before_test = params.get_boolean("migrate_before_test")
    migrate_verify_flags = params.get("migrate_verify_flags", "")
    login_timeout = params.get_numeric("login_timeout", 240)
    # Variants that migrate before running subtests execute each subtest
    # directly over the shell (see run_scenarios_sequential); guest avocado
    # is not required for that path, so skip the pip install to reduce SSH
    # churn and its exposure to the fragile post-migrate channel.
    if not migrate_before_test:
        avocado_install(test, params, guest_bm_path, vm, session)
    vm_config = params.get_boolean("disable_parallel_run")
    conf_state = None
    if vm_config:
        conf_state = disable_parallel_run(test, session)

    try:
        # When we plan to migrate before running subtests, compile the test
        # suite up-front on the stable pre-migration session. The freshly
        # attached post-migrate SSH channel is fragile enough that a long
        # sequence of package_install / make commands routinely drops it.
        if migrate_before_test:
            try:
                _build_cpuid_check(test, guest_bm_path, session)
            except aexpect.ShellError:
                test.log.warning("SSH dropped during cpuid_check build, "
                                 "re-login once")
                session = _reconnect(session, vm, login_timeout)
                _build_cpuid_check(test, guest_bm_path, session)
            for feature_dir_name in feature_dir_names.split():
                vm_test_path = os.path.join(guest_bm_path, feature_dir_name)
                try:
                    prepare_test_suite(test, vm_test_path, session)
                except aexpect.ShellError:
                    test.log.warning("SSH dropped during prepare, "
                                     "re-login once")
                    session = _reconnect(session, vm, login_timeout)
                    prepare_test_suite(test, vm_test_path, session)
            session = migrate_and_verify_flags(test, params, vm, session,
                                               migrate_verify_flags)

        for feature_dir_name in feature_dir_names.split():
            vm_test_path = os.path.join(guest_bm_path, feature_dir_name)
            if not migrate_before_test:
                prepare_test_suite(test, vm_test_path, session)
            cmd_timeout = params.get_numeric("cmd_timeout", 240)
            if params.get("cmd_timeout"):
                cmd_timeout = params.get_numeric("cmd_timeout")
            cases_file = params.get("test_scen")
            if cases_file is None:
                cases_file = "tests"
            for scen in cases_file.split():
                if migrate_before_test:
                    session = run_scenarios_sequential(
                        test, params, session, vm, guest_bm_path,
                        feature_dir_name, scen, cmd_timeout)
                    continue
                #run_cmd = "cd %s && ./runtests -f %s/tests" % (guest_bm_path, feature_dir_name)
                run_cmd = "cd %s && ./runtests.py -f %s -t %s/%s " % (guest_bm_path, feature_dir_name, feature_dir_name, scen)
                s, o = session.cmd_status_output(run_cmd, timeout=cmd_timeout)

                get_test_results(test, o, vm, session)

                if s:
                    test.fail("Feature %s scenario %s test fail in guest." % (feature_dir_name, scen))

            #results dict for further debug
            #b = o.splitlines()[-2]
            #part = [i.split() for i in b.split(":")[1].split("|")]
            #results = dict(part)

            test.log.info("Guest feature %s test pass." % feature_dir_name)
    finally:
        try:
            session.cmd("rm %s -rf" % guest_bm_path, ignore_all_errors=True)
        except Exception:  # pylint: disable=broad-except
            # The channel is already dead; do not let cleanup exceptions
            # (aexpect.ShellError or aexpect internal TypeError on a torn
            # down expect_pipe) mask the real test result.
            pass
        if vm_config:
            try:
                restore_parallel_run(session, conf_state)
            except Exception:  # pylint: disable=broad-except
                pass
        try:
            session.close()
        except Exception:  # pylint: disable=broad-except
            pass
