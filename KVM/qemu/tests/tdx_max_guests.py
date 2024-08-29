#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History:  Aug. 2024 - Xudong Hao - creation
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
    s, o = process.getstatusoutput("rpm -qa | grep %s" % msr_pkg,
                                   shell=True)
    if s != 0:
        install_status = utils_package.package_install(msr_pkg)
        if not install_status:
            test.cancel("Failed to install %s." % msr_pkg)

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

    :param test: QEMU test object
    :param params: Dictionary with the test parameters
    :param env: Dictionary with test environment
    """
    xfail = False
    if (params.get("xfail") is not None) and (params.get("xfail") == "yes"):
        xfail = True
    timeout = params.get_numeric("login_timeout", 240)
    serial_login = params.get("serial_login", "no") == "yes"

    tdx_kids = get_tdx_kids(params, test)
    # The TDX module itself requires one KeyID
    td_vms = tdx_kids - 1
    if (params.get("overrange_tdx_kids") is not None) and (params['overrange_tdx_kids'] == 'yes'):
        td_vms = tdx_kids
    vms_list = ["vm" + str(x) for x in range(1, td_vms + 1)]
    params['vms'] = " ".join(vms_list)

    host_free_mem = utils_misc.get_usable_memory_size()
    if (int(params['mem']) * td_vms > int(host_free_mem)):
        test.cancel("Not enough memory resource for %d TDVMs." % td_vms)

    error_context.context("Booting multiple %d TDVM " % td_vms, test.log.info)
    env_process.preprocess(test, params, env)
    vms = env.get_all_vms()
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
                session = vm.wait_for_login(timeout=timeout)
            session.close()
            vm.destroy()
    else:
        for vm in vms:
            vm.destroy(gracefully=False)
