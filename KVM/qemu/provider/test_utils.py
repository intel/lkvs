#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author: Xudong Hao <xudong.hao@intel.com>
#
# History: Sept. 2024 - Xudong Hao - creation

import os
import resource
import shlex
import shutil
from virttest import data_dir, asset


# Prebuilt static x86_64 binary.
# Source: https://www.etallen.com/cpuid/cpuid-20260503.x86_64.tar.gz
CPUID_BINARY = os.path.join(data_dir.get_deps_dir("cpuid"), "cpuid")
CPUID_INSTALL_PATH = "/usr/local/bin/cpuid"


def set_host_nofile_limit(test, params):
    """Raise the nofile soft limit and return the original limits."""
    target_nofile = int(params.get_numeric("host_nofile_limit", 65536))
    original_limits = resource.getrlimit(resource.RLIMIT_NOFILE)
    soft_limit, hard_limit = original_limits
    if hard_limit == resource.RLIM_INFINITY:
        new_soft_limit = target_nofile
    else:
        new_soft_limit = min(target_nofile, hard_limit)

    if soft_limit < new_soft_limit:
        resource.setrlimit(resource.RLIMIT_NOFILE, (new_soft_limit, hard_limit))
        if new_soft_limit < target_nofile:
            test.log.warning(
                "Host nofile hard limit is %s; soft limit set to %s instead of %s",
                hard_limit,
                new_soft_limit,
                target_nofile,
            )
        else:
            test.log.info("Host nofile soft limit set to %s", new_soft_limit)

    return original_limits


def restore_host_nofile_limit(original_limits):
    """Restore a nofile limit returned by set_host_nofile_limit()."""
    resource.setrlimit(resource.RLIMIT_NOFILE, original_limits)


def require_host_command(test, command, package=None):
    """Cancel with a clear message when a required host command is absent."""
    if shutil.which(command) is not None:
        return
    message = "Required host command '%s' was not found" % command
    if package:
        message += "; install the '%s' package" % package
    test.cancel(message)


def require_guest_command(test, session, command, package=None):
    """Cancel with a clear message when a required guest command is absent."""
    check_cmd = "command -v %s >/dev/null 2>&1" % shlex.quote(command)
    if session.cmd_status(check_cmd) == 0:
        return
    message = "Required guest command '%s' was not found" % command
    if package:
        message += "; install the '%s' package" % package
    test.cancel(message)


def ensure_cpuid_command(test, vm=None, session=None):
    """Install the bundled cpuid binary when the package did not provide it."""
    if session:
        if session.cmd_status("command -v cpuid >/dev/null 2>&1") == 0:
            return
        vm.copy_files_to(CPUID_BINARY, CPUID_INSTALL_PATH)
        session.cmd("chmod 0755 %s" % CPUID_INSTALL_PATH)
        require_guest_command(test, session, "cpuid", "cpuid")
        return

    if shutil.which("cpuid") is not None:
        return
    try:
        shutil.copy2(CPUID_BINARY, CPUID_INSTALL_PATH)
        os.chmod(CPUID_INSTALL_PATH, 0o755)
    except OSError as error:
        test.cancel("Failed to install bundled cpuid binary: %s" % error)
    require_host_command(test, "cpuid", "cpuid")


def get_baremetal_dir(params):
    """
    Get the test provider's BM absolute path.
    :param params: Dictionary with the test parameters
    """
    provider = params["provider"]
    provider_info = asset.get_test_provider_info(provider)
    if provider_info["uri"].startswith("file://"):
        provider_dir = provider_info["uri"][7:]
    else:
        provider_dir = data_dir.get_test_provider_dir(provider)
    baremetal_dir = os.path.join(provider_dir, "BM")

    return baremetal_dir
