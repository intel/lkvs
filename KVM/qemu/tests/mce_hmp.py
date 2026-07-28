#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

# Author: Farrah Chen <farrah.chen@intel.com>
#
# History:  Jul. 2026 - Farrah Chen - creation

from provider import dmesg_router  # pylint: disable=unused-import
from provider import lmce_utils

from virttest import env_process, error_context, utils_misc


def _inject_mce(
    vm,
    cpu,
    bank,
    status,
    addr,
    misc=0x8C,
    mcg_status=lmce_utils.MCG_STATUS_MCIP_RIPV,
    broadcast=False,
):
    """Inject an MCE into the guest via QEMU HMP and return the QMP event.

    QEMU raises a ``MEMORY_FAILURE`` QMP event once it has delivered the
    exception to the guest; that event is a reliable, guest-independent
    proof of injection and is used in place of legacy mce-inject/mcelog
    scraping. The event may also be picked up by the caller via
    ``vm.monitor.get_event("MEMORY_FAILURE")`` after this returns.
    """
    vm.monitor.clear_events()
    prefix = "mce -b" if broadcast else "mce"
    cmd = "%s %d %d 0x%x 0x%x 0x%x 0x%x" % (
        prefix,
        cpu,
        bank,
        status,
        mcg_status,
        addr,
        misc,
    )
    vm.monitor.human_monitor_cmd(cmd)
    return utils_misc.wait_for(
        lambda: vm.monitor.get_event("MEMORY_FAILURE"),
        timeout=10,
        first=0.5,
        step=0.5,
    )


def _get_guest_mce_dmesg(session):
    """Return concatenated MCE-related dmesg lines from the guest."""
    return session.cmd_output(
        "dmesg | grep -iE 'mce:|machine check|hardware error' || true"
    )


def _wait_for_mce_in_guest(session, timeout=30):
    """Poll guest dmesg for an MCE record and return the matching lines.

    Returns the stripped dmesg output on the first successful poll, or ``""``
    on timeout. Callers can use the return value directly and avoid a second
    dmesg query.
    """

    def _fetch():
        return _get_guest_mce_dmesg(session).strip() or None

    return utils_misc.wait_for(_fetch, timeout, first=1, step=1) or ""


def _launch_victim(session, params, log_path, exit_path, cpu=0):
    """Launch victim pinned to ``cpu`` in auto-trigger mode, backgrounded.

    ``victim -d -k 0`` mmaps a page, prints its GPA, then polls
    ``./trigger_start`` until it contains ``trigger`` and loops reading the
    page. Its exit status is captured to ``exit_path`` so the caller can
    verify SIGBUS delivery.

    Pinning is essential for SRAR injection: the MCE targets a specific
    vCPU, and the kernel #MC handler on that vCPU delivers SIGBUS.AR to
    the task currently running there. If the victim is running elsewhere,
    the wrong task (typically the login shell) receives the fault.
    """
    test_dir = params["test_dir"]
    exe = params["exec_file"]
    session.cmd(
        "cd %s && (taskset -c %d ./%s -d -k 0 > %s 2>&1; echo $? > %s) &"
        % (test_dir, cpu, exe, log_path, exit_path)
    )


def _run_srao(test, params, vm, session, expected_state):
    """Inject an SRAO MCE and verify LMCE marker matches guest configuration.

    lmce=on -> local delivery with MCG_STATUS.LMCE_S set; guest dmesg must
    contain an ``LMCE`` marker. lmce=off -> broadcast delivery; guest dmesg
    must NOT contain an LMCE marker.
    """
    lmce_utils.check_lmce_state(test, session, expected_state)
    session.cmd("dmesg -C")
    if expected_state == "on":
        event = _inject_mce(
            vm,
            cpu=0,
            bank=1,
            status=lmce_utils.MCI_STATUS_SRAO,
            addr=0x1000,
            mcg_status=lmce_utils.MCG_STATUS_SRAO_LOCAL,
        )
    else:
        event = _inject_mce(
            vm,
            cpu=0,
            bank=1,
            status=lmce_utils.MCI_STATUS_SRAO,
            addr=0x1000,
            broadcast=True,
        )
    if not event:
        test.fail("QEMU did not report MEMORY_FAILURE for SRAO injection.")
    test.log.info("SRAO delivered to guest: %s", event)
    dmesg = _wait_for_mce_in_guest(session, timeout=10)
    if not dmesg:
        test.fail("SRAO not recorded in guest dmesg.")
    test.log.info("SRAO recorded in guest dmesg: %s", dmesg)
    lmce_utils.check_lmce_marker(test, dmesg, expected_state)


def _run_srar(test, params, vm, session, expected_state):
    """Full SRAR test: inject on a mapped guest page, then trigger a user-space
    load; expect the guest kernel to hwpoison the page and deliver SIGBUS.AR
    to the victim process (exit status 135 = 128 + SIGBUS).
    """
    lmce_utils.check_lmce_state(test, session, expected_state)
    lmce_utils.build_victim(test, params, vm, session)
    test_dir = params["test_dir"]
    exe = params["exec_file"]
    trigger = "%s/trigger_start" % test_dir
    log = "%s/vmpha.log" % test_dir
    exit_f = "%s/victim_exit" % test_dir
    try:
        session.cmd("rm -f %s %s %s" % (trigger, log, exit_f))
        session.cmd("dmesg -C")
        target_cpu = 0
        _launch_victim(session, params, log, exit_f, cpu=target_cpu)
        gpa = utils_misc.wait_for(
            lambda: lmce_utils.parse_victim_gpa(session, log),
            timeout=30,
            first=1,
            step=1,
        )
        if not gpa:
            test.error(
                "Victim did not report a GPA (log: %s)."
                % session.cmd_output("cat %s || true" % log)
            )
        test.log.info(
            "Victim mapped page at GPA 0x%x, pinned to vCPU %d.", gpa, target_cpu
        )

        # Trigger victim into the hot read loop BEFORE injecting so that the
        # SRAR MCE (delivered with MCG_STATUS.EIPV=1) arrives while victim is
        # the current task on the target vCPU. Otherwise SIGBUS.AR would be
        # steered to whichever task happens to be scheduled on that vCPU.
        session.cmd("echo trigger > %s" % trigger)
        session.cmd_status("sleep 1")

        event = _inject_mce(
            vm,
            cpu=target_cpu,
            bank=1,
            status=lmce_utils.MCI_STATUS_SRAR,
            addr=gpa,
            mcg_status=lmce_utils.MCG_STATUS_SRAR_LOCAL,
        )
        if not event:
            test.fail("QEMU did not report MEMORY_FAILURE for SRAR injection.")
        if not event.get("data", {}).get("flags", {}).get("action-required"):
            test.fail("SRAR delivered without action-required flag: %s" % event)
        test.log.info("SRAR delivered to guest: %s", event)

        # Victim should be killed by SIGBUS(7) on the poisoned load -> exit 135.
        if not utils_misc.wait_for(
            lambda: session.cmd_status("test -e %s" % exit_f) == 0,
            timeout=30,
            first=1,
            step=1,
        ):
            test.fail(
                "Victim did not exit after trigger; SRAR was not delivered "
                "to the consumer process."
            )
        raw = session.cmd_output("cat %s" % exit_f).strip()
        try:
            status = int(raw)
        except ValueError:
            test.fail("Invalid victim exit status: %r" % raw)
        if status != 128 + 7:
            test.fail(
                "Victim did not die with SIGBUS: exit=%d (expected 135)." % status
            )
        test.log.info("Victim received SIGBUS.AR as expected (exit=%d).", status)

        dmesg = _wait_for_mce_in_guest(session, timeout=10)
        if not dmesg:
            test.fail("SRAR not recorded in guest dmesg.")
        if "Uncorrected" not in dmesg:
            test.fail("SRAR dmesg missing 'Uncorrected' marker: %s" % dmesg)
        lmce_utils.check_lmce_marker(test, dmesg, expected_state)
        test.log.info("SRAR recorded in guest dmesg: %s", dmesg)
    finally:
        session.cmd_status("pkill -9 -x %s 2>/dev/null" % exe)
        session.cmd_status("rm -f %s %s %s" % (trigger, log, exit_f))


@error_context.context_aware
def run(test, params, env):
    """
    Local Machine Check Exception (LMCE) tests.

    ``lmce_action`` selects the flow:
    - ``check``: verify that guest LMCE MSR bits reflect the configured
      ``-cpu ...,lmce=on|off`` flag.
    - ``srao``: verify LMCE state, then inject an SRAO MCE via QEMU HMP
      ``mce`` command and confirm the guest records the machine-check event.
    - ``srar``: verify LMCE state, allocate a target guest page, then inject
      an SRAR MCE tied to that page and confirm the guest records it.

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    action = params["lmce_action"]
    expected_state = params["lmce_state"]
    login_timeout = params.get_numeric("login_timeout", 240)

    params["start_vm"] = "yes"
    env_process.preprocess_vm(test, params, env, params["main_vm"])
    vm = env.get_vm(params["main_vm"])
    vm.verify_alive()
    session = vm.wait_for_login(timeout=login_timeout)

    try:
        lmce_utils.install_msr_tools(test, session)
        if action == "check":
            lmce_utils.check_lmce_state(test, session, expected_state)
        elif action == "srao":
            _run_srao(test, params, vm, session, expected_state)
        elif action == "srar":
            _run_srar(test, params, vm, session, expected_state)
        else:
            test.error("Unknown lmce_action: %s" % action)
    finally:
        session.close()
