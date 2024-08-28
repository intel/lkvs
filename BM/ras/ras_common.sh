#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation
# Author: Yi Lai <yi1.lai@intel.com>
# @Desc  Common functions used in ras test suite

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

# check whether one package is installed, if not, install the package
# Usage: pkg_check_install pkg_name_1 pkg_name_2 pkg_name_x
pkg_check_install() {
  for pkg_name in "$@"; do
    if ! rpm -q $pkg_name &> /dev/null; then
      test_print_trc "${pkg_name} is not installed. Installing now."
      if ! yum install -y $pkg_name; then
        die "Failed to install ${pkg_name}"
      fi
    else
      test_print_trc "${pkg_name} is already installed"
    fi
  done
}
