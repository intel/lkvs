#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Farrah Chen <farrah.chen@intel.com>
#
# History:  Dec. 2024 - Farrah Chen - creation

from virttest import error_context, env_process
from virttest import data_dir as virttest_data_dir

from avocado.utils import process
from avocado.core import exceptions
from provider.hostdev import utils as hostdev_utils
from provider.hostdev.dev_setup import hostdev_setup

import os


@error_context.context_aware
def run(test, params, env):
    """
    Assign host GPU device to guest and do cuda sample test.
    1) In host, remove the device from GPU driver and bind it to vfio-pci.
    2) Assign the device to guest by QEMU command and boot guest.
    3) Check device BDF, driver and run cuda samples in guest.
    4) Shutdown guest

    :param test: QEMU test object.
    :type  test: avocado_vt.test.VirtTest
    :param params: Dictionary with the test parameters.
    :type  params: virttest.utils_params.Params
    :param env: Dictionary with test environment.
    :type  env: virttest.utils_env.Env
    """
    def run_cuda_sample():
        #Copy cuda test scripts to guest
        file_name = "run_cuda.sh"
        guest_dir = "/tmp/"
        deps_dir = virttest_data_dir.get_deps_dir()
        host_file = os.path.join(deps_dir, file_name)
        guest_file = guest_dir + file_name
        vm.copy_files_to(host_file, guest_dir)
        result = session.cmd_status(guest_file)
        if result:
            test.fail("Cuda test fail")
        else:
            test.log.info("Cuda test pass")

    error_context.context("Start GPU passthrough test", test.log.info)
    timeout = params.get_numeric("login_timeout", 240)
    vm_type = params.get("vm_secure_guest_type")
    vm_name = params['main_vm']
    if not params.get("vm_hostdev_iommufd") and vm_type == "tdx":
        dma_entry_limit_cmd = params.get("dma_cmd")
        status = process.system(dma_entry_limit_cmd, shell=True)
        if status:
            raise exceptions.TestError("Failed to increase dma_entry_limit.")
    with hostdev_setup(params) as params:
        hostdev_driver = params.get("vm_hostdev_driver", "vfio-pci")
        assignment_type = params.get("hostdev_assignment_type")
        available_pci_slots = hostdev_utils.get_pci_by_dev_type(
            assignment_type, "display", hostdev_driver
        )
        # Create guest first
        env_process.preprocess_vm(test, params, env, vm_name)
        vm = env.get_vm(vm_name)
        vm_hostdevs = vm.params.objects("vm_hostdevs")
        pci_slots = []
        error_context.base_context(f"Setting hostdevs for {vm.name}", test.log.info)
        for dev in vm_hostdevs:
            pci_slot = available_pci_slots.pop(0)
            vm.params[f"vm_hostdev_host_{dev}"] = pci_slot
            pci_slots.append(pci_slot)
        vm.create(params=vm.params)
        vm.verify_alive()
        vm.params["vm_hostdev_slots"] = pci_slots
        session = vm.wait_for_login(timeout=timeout)

        # Check GPU in guest
        try:
            error_context.context("Check GPU BDF and driver in guest", test.log.info)
            if session:
                # Check GPU BDF and driver in guest
                gpu_device_check_cmd = params.get("gpu_device_check_cmd")
                result = session.cmd_status(gpu_device_check_cmd)
                if result:
                    test.fail("GPU can't be found or with incorrect driver, please install GPU driver in guest image")
                else:
                    test.log.info("GPU found with correct driver in guest")
                # Check GPU status in guest
                gpu_status_check_cmd = params.get("gpu_status_check_cmd")
                result = session.cmd_status(gpu_status_check_cmd)
                if result:
                    test.fail("GPU status check fail")
                else:
                    test.log.info("GPU status check pass")
                # Run cuda samples in guest
                guest_operation = params.get("guest_operation")
                if guest_operation:
                    test.log.info("Run %s in guest ", guest_operation)
                    locals_var = locals()
                    locals_var[guest_operation]()
                session.close()
        finally:
            vm.destroy()
