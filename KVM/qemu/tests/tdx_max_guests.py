#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History:  Aug. 2024 - Xudong Hao - creation
from provider import dmesg_router  # pylint: disable=unused-import
from provider.test_utils import require_host_command
from avocado.utils import process

from virttest import env_process
from virttest import error_context
from virttest import utils_misc, utils_package


def get_tdx_kids(params, test):
    """
    Get TDX private KeyIDs of platform.(only for Linux now)
    Return an interger value.
    :param params: Dictionary with the test parameters
    :param test: QEMU test object
    """
    msr_pkg = params.get("msr_pkg")
    utils_package.package_install(msr_pkg)
    require_host_command(test, "rdmsr", msr_pkg)
    output = process.getoutput(params.get("rdmsr_cmd"))
    # Bit [63:32]:   Number of TDX private KeyIDs
    tdx_kids = int(output[:-8], 16)

    return tdx_kids


# This decorator makes the test function aware of context strings
@error_context.context_aware
def run(test, params, env):
    """
    Boot the maximum number of TDs:
    1) Caculate the platform supported maximum number of TDs
    2) Boot up all TDVMs
    3) Shutdown all of TDVMs
    4) Repeat 2) and 3) for the configured number of cycles

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """
    xfail = False
    if (params.get("xfail") is not None) and (params.get("xfail") == "yes"):
        xfail = True
    timeout = params.get_numeric("login_timeout", 240)
    serial_login = params.get("serial_login", "no") == "yes"
    cycles = int(params.get_numeric("cycles", 1))
    gracefully = params.get("destroy_gracefully", "yes") == "yes"

    tdx_kids = get_tdx_kids(params, test)
    # The TDX module itself requires one KeyID
    td_vms = tdx_kids - 1
    overrange_tdx_kids = params.get("overrange_tdx_kids") == "yes"
    if overrange_tdx_kids:
        td_vms = tdx_kids
    max_guest_count = params.get_numeric("max_guest_count", 0)
    if max_guest_count and td_vms > max_guest_count:
        if overrange_tdx_kids:
            test.cancel(
                "Cannot test the out-of-range TDX KeyID at %d guests; "
                "network limit is %d" % (td_vms, max_guest_count)
            )
        td_vms = max_guest_count
    vms_list = ["vm" + str(x) for x in range(1, td_vms + 1)]
    params['vms'] = " ".join(vms_list)

    host_free_mem = utils_misc.get_usable_memory_size()
    if (int(params['mem']) * td_vms > int(host_free_mem)):
        test.cancel("Not enough memory resource for %d TDVMs." % td_vms)

    error_context.context("Booting multiple %d TDVM " % td_vms, test.log.info)
    env_process.preprocess(test, params, env)
    vms = env.get_all_vms()
    for cycle in range(1, cycles + 1):
        if cycles > 1:
            error_context.context("Boot %d TDVMs, cycle %d/%d"
                                  % (td_vms, cycle, cycles), test.log.info)
        has_error = False
        try:
            for vm in vms:
                vm.create()
        except:
            has_error = True
            if xfail is False:
                raise
        if (has_error is False) and (xfail is True):
            test.fail("Test was expected to fail, but it didn't")

        if xfail is False:
            for vm in vms:
                vm.verify_alive()
                if serial_login:
                    session = vm.wait_for_serial_login(timeout=timeout)
                else:
                    session = vm.wait_for_login(timeout=params.get_numeric("login_timeout"))
                session.close()
                vm.destroy(gracefully=gracefully)
        else:
            for vm in vms:
                vm.destroy(gracefully=False)
