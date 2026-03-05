# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

from virttest import env_process
from virttest import virt_vm
from virttest import utils_misc as vt_utils_misc
from virttest.test_setup import verify as vt_verify

from . import utils_misc as lkvs_utils_misc


_ORIG_PREPROCESS = env_process.preprocess
_ORIG_VERIFY_HOST_SETUP = vt_verify.VerifyHostDMesg.setup
_ORIG_VERIFY_HOST_CLEANUP = vt_verify.VerifyHostDMesg.cleanup
_ORIG_VM_VERIFY_DMESG = virt_vm.BaseVM.verify_dmesg


def _patched_preprocess(test, params, env, _orig_preprocess=_ORIG_PREPROCESS):
    if params.get("lkvs_verify_host_dmesg", "no") == "yes":
        params["verify_host_dmesg"] = "yes"
    if params.get("lkvs_verify_guest_dmesg", "no") == "yes":
        params["verify_guest_dmesg"] = "yes"
    return _orig_preprocess(test, params, env)


def _patched_verify_host_setup(
    self,
    _orig_setup=_ORIG_VERIFY_HOST_SETUP,
    _lkvs_utils_misc=lkvs_utils_misc,
):
    if self.params.get("lkvs_verify_host_dmesg", "no") != "yes":
        return _orig_setup(self)
    self.params["_lkvs_host_dmesg_start_time"] = _lkvs_utils_misc.dmesg_time()
    return _lkvs_utils_misc.verify_dmesg(
        self.params["_lkvs_host_dmesg_start_time"], ignore_result=True
    )


def _patched_verify_host_cleanup(
    self,
    _orig_cleanup=_ORIG_VERIFY_HOST_CLEANUP,
    _lkvs_utils_misc=lkvs_utils_misc,
    _vt_utils_misc=vt_utils_misc,
):
    if self.params.get("lkvs_verify_host_dmesg", "no") != "yes":
        return _orig_cleanup(self)
    dmesg_log_file = self.params.get("host_dmesg_logfile", "host_dmesg.log")
    level = self.params.get("host_dmesg_level", 3)
    expected_host_dmesg = self.params.get("expected_host_dmesg", "")
    ignore_result = self.params.get("host_dmesg_ignore", "no") == "yes"
    dmesg_log_file = _vt_utils_misc.get_path(self.test.debugdir, dmesg_log_file)
    start_time = self.params.get("_lkvs_host_dmesg_start_time", "full")
    return _lkvs_utils_misc.verify_dmesg(
        time=start_time,
        dmesg_log_file=dmesg_log_file,
        ignore_result=ignore_result,
        level_check=level,
        expected_dmesg=expected_host_dmesg,
    )


@virt_vm.session_handler
def _patched_vm_verify_dmesg(
    self,
    dmesg_log_file=None,
    connect_uri=None,
    _orig_vm_verify=_ORIG_VM_VERIFY_DMESG,
    _lkvs_utils_misc=lkvs_utils_misc,
):
    if self.params.get("lkvs_verify_guest_dmesg", "no") != "yes":
        return _orig_vm_verify(self, dmesg_log_file, connect_uri)

    level = self.params.get("guest_dmesg_level", 3)
    ignore_result = self.params.get("guest_dmesg_ignore", "no") == "yes"
    serial_login = self.params.get("serial_login", "no") == "yes"
    if serial_login:
        self.session = self.wait_for_serial_login()
    elif (
        len(self.virtnet) > 0
        and self.virtnet[0].nettype != "macvtap"
        and not connect_uri
    ):
        self.session = self.wait_for_login()
    expected_guest_dmesg = self.params.get("expected_guest_dmesg", "")
    verify_time = _lkvs_utils_misc.dmesg_time(self.session)
    return _lkvs_utils_misc.verify_dmesg(
        time=verify_time,
        dmesg_log_file=dmesg_log_file,
        ignore_result=ignore_result,
        level_check=level,
        session=self.session,
        expected_dmesg=expected_guest_dmesg,
    )


if env_process.preprocess is not _patched_preprocess:
    env_process.preprocess = _patched_preprocess
if vt_verify.VerifyHostDMesg.setup is not _patched_verify_host_setup:
    vt_verify.VerifyHostDMesg.setup = _patched_verify_host_setup
if vt_verify.VerifyHostDMesg.cleanup is not _patched_verify_host_cleanup:
    vt_verify.VerifyHostDMesg.cleanup = _patched_verify_host_cleanup
if virt_vm.BaseVM.verify_dmesg is not _patched_vm_verify_dmesg:
    virt_vm.BaseVM.verify_dmesg = _patched_vm_verify_dmesg
