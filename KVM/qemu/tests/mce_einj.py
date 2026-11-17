#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2025 Intel Corporation

# Author: Farrah Chen <farrah.chen@intel.com>
#
# History: Nov. 2025 - Farrah Chen - creation

from provider import dmesg_router  # pylint: disable=unused-import
from provider import ept_poison_utils
from provider import lmce_utils
import logging
import os
import re
from avocado.utils import process
from avocado.core import exceptions
from virttest import error_context, env_process
from virttest import utils_misc


def error_inject(test, params, addr):
    """
    Check if kernel module einj is loaded, if not, load it.
    Inject error via einj
    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param addr: Host physical address
    """
    module = 'einj'
    if module not in process.system_output('lsmod').decode('utf-8'):
        if process.system('modprobe %s' % module, shell=True) != 0:
            test.cancel("module %s isn't supported ?" % module)
    debugfs = '/sys/kernel/debug'
    einj_path = os.path.join(debugfs, 'apei/einj/')
    if not os.path.exists(einj_path):
        test.cancel("error injection isn't supported, check your BIOS setting")
    error_type = params.get('error_type')
    status = process.system("echo %s > %s/error_type" % (error_type, einj_path), shell=True)
    if status:
        raise exceptions.TestError("Failed to inject error %s" % error_type)
    status = process.system("echo %s > %s/param1" % (addr, einj_path), shell=True)
    if status:
        raise exceptions.TestError("Failed to inject error to address %s" % addr)
    status = process.system("echo 0xfffffffffffff000 > %s/param2" % einj_path, shell=True)
    if status:
        raise exceptions.TestError("Failed to inject mask to param2")
    status = process.system("echo 1 > %s/notrigger" % einj_path, shell=True)
    if status:
        raise exceptions.TestError("Failed to enable notrigger")
    status = process.system("echo 1 > %s/error_inject" % einj_path, shell=True)
    if status:
        raise exceptions.TestError("Failed to inject error")


@error_context.context_aware
def run(test, params, env):
    """
    Inject error to guest memory.
    0) Before executing this case, enable error injection in BIOS, and set
       Patrol Scrub: enabled for srao_* (AO), disabled for srar_* (AR)
    1) Boot up guest
    2) Run victim in guest to get a physical address in guest
    3) Run gpa2hpa in QEMU monitor to get it's host physical address
    4) Return to host, inject error to this address by einj
    5) Return to guest victim, "enter" to trigger error
    6) Shutdown guest
    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment.
    """
    # Broadcast SRAO risk (mce_einj.srao_lmce_off only; mce_einj.srao_lmce_on /
    # mce_einj.srar_lmce_on deliver locally to a single vCPU and are not
    # affected):
    #
    # srao_lmce_off runs with LMCE off, so the SRAO delivered through the
    # host EINJ -> KVM path is broadcast to every guest vCPU. The guest
    # kernel then enters the mce_start rendezvous with a fixed
    # MCE_TIMEOUT_US window; if any vCPU misses that window the guest
    # panics in mce_panic() before it can log the SIGBUS, and this case
    # fails. It is a probabilistic host + KVM + guest timing issue, not a
    # defect of the case. When mce_einj.srao_lmce_off fails intermittently,
    # rerun before treating it as a real regression.
    lmce_state = params.get("lmce_state")
    session = None
    vm_exec_bin = None
    kmsg = None
    test_dir = params["test_dir"]
    try:
        vm_name = params['main_vm']
        env_process.preprocess_vm(test, params, env, vm_name)
        vm = env.get_vm(vm_name)
        session = vm.wait_for_login(timeout=params.get_numeric("login_timeout"))
        vm_exec_bin = lmce_utils.build_victim(test, params, vm, session)
        vmpha_log = '/tmp/vmpha.log'
        session.cmd('%s -d -k 0 > %s 2>&1 &' % (vm_exec_bin, vmpha_log))
        # victim runs in the background and prints the GPA a moment later;
        # poll the log until the address line appears.
        guest_pha_int = utils_misc.wait_for(
            lambda: lmce_utils.parse_victim_gpa(session, vmpha_log),
            timeout=30, first=1, step=1)
        if guest_pha_int is None:
            raise exceptions.TestError("Victim did not report a GPA.")
        guest_pha = '0x%x' % guest_pha_int
        output = vm.monitor.send_args_cmd("gpa2hpa %s" % guest_pha)
        host_pha = output.split()[7]
        host_pha_int = int(host_pha, 16)
        vm_dmesg_start = len(session.cmd_output('dmesg').splitlines())
        kmsg = ept_poison_utils.KmsgReader()
        error_inject(test, params, host_pha)
        vm_trigger_cmd = 'echo "trigger" > %s/trigger_start' % test_dir
        session.cmd(vm_trigger_cmd)
        # err_code depends on how the platform detects the poison (read vs. patrol scrub).
        hw_mce = r'err_code:0x[0-9a-f]+:(0x[0-9a-f]+)\s+SystemAddress:0x%x\b' % host_pha_int
        # Fallback for hosts without the skx/i10nm EDAC decoder (e.g. firmware-first).
        hw_sigbus = r'Memory failure: 0x%x: Sending SIGBUS to ' % (host_pha_int >> 12)
        mce_type = params.get("mce_type", "srao")
        if mce_type == "srar":
            vm_mce = 'mce: Uncorrected hardware memory error in user-access at %x' % guest_pha_int
        else:
            # The AO path only logs guest memory_failure(), no user-access line.
            vm_mce = r'Memory failure: 0x%x:' % (guest_pha_int >> 12)

        # The poisoned page is consumed asynchronously: the guest victim's
        # poll loop wakes up on the trigger file, reads the page, the memory
        # controller raises the MCE, KVM forwards it, then the host EDAC path
        # decodes and logs it. Poll both dmesg streams instead of racing them.
        def _host_log():
            kmsg.drain()
            return "\n".join(kmsg.records)

        def _vm_log():
            return "\n".join(session.cmd_output('dmesg').splitlines()[vm_dmesg_start:])

        hw_status = utils_misc.wait_for(
            lambda: re.search(hw_mce, _host_log()) or re.search(hw_sigbus, _host_log()),
            timeout=30, first=1, step=1)
        if not hw_status:
            raise exceptions.TestError("Failed to trigger MCE in host")
        vm_status = utils_misc.wait_for(
            lambda: re.search(vm_mce, _vm_log()),
            timeout=30, first=1, step=1)
        edac = re.search(hw_mce, _host_log())
        if edac:
            mcacod = edac.group(1)
            # SDM memory controller MCACOD 000F 0000 1MMM CCCC: MMM=100 means patrol scrub.
            scrub = (int(mcacod, 16) & 0xeff0) == 0x00c0
            if mce_type == "srar" and scrub:
                test.cancel(
                    "SRAR not exercised: host reported a patrol scrub error (MCACOD %s) "
                    "at %s, so the guest got SRAO (AO). Disable Patrol Scrub in BIOS "
                    "to run srar_* variants." % (mcacod, host_pha))
            if mce_type == "srao" and not scrub:
                test.cancel(
                    "SRAO not exercised: host reported a non-scrub error (MCACOD %s) "
                    "at %s, so the guest got SRAR (AR). Enable Patrol Scrub in BIOS "
                    "to run srao_* variants." % (mcacod, host_pha))
        if not vm_status:
            raise exceptions.TestError("Failed to trigger MCE in guest")
        vm_dmesg = _vm_log()
        vm.verify_dmesg()

        # LMCE variants additionally verify that KVM forwarded the MCE with
        # MCG_STATUS.LMCE_S set: guest MSR bits reflect lmce=on and the guest
        # kernel logs an LMCE marker. This proves the local-delivery path
        # (vs broadcast) survives the host EINJ -> KVM -> guest chain.
        if lmce_state:
            lmce_utils.install_msr_tools(test, session)
            lmce_utils.check_lmce_state(test, session, lmce_state)
            lmce_utils.check_lmce_marker(test, vm_dmesg, lmce_state)

    except exceptions.TestCancel:
        raise
    except Exception:
        # Only the broadcast SRAO path is exposed to the rendezvous panic;
        # emit the retry hint only for that variant so lmce=on failures are
        # still surfaced as real bugs.
        if not lmce_state:
            logging.warning(
                "mce_einj.srao_lmce_off failed. Broadcast SRAO can panic "
                "the guest via the mce_start rendezvous timeout on the "
                "host EINJ -> KVM -> guest path (see the comment at the top "
                "of run()). This is a probabilistic timing issue, not a "
                "defect of the case; please rerun before treating it as a "
                "regression."
            )
        raise
    finally:
        if kmsg is not None:
            kmsg.close()
        # Guard against the guest being unreachable after a rendezvous
        # panic: any of these cleanup commands may hang or fail, and we
        # must not mask the original exception with a cleanup NameError.
        if session is not None:
            try:
                session.cmd("rm -rf /tmp/vmpha.log")
                session.cmd("rm -rf %s/trigger_start" % test_dir)
                if vm_exec_bin:
                    session.cmd("rm -rf %s" % vm_exec_bin)
            except Exception:
                pass
            session.close()
