#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  13, Dec., 2023 - Hongyu Ning - creation


# @desc This script do test by kernel test module in TDX Guest VM

###################### Variables ######################
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"
source common.sh
test_module=$1

###################### Functions ######################
module_check() {
  lsmod | grep "$test_module" || \
  { die "test module $test_module not found in lsmod"; return 1; }
  test_print_trc "test module loaded and test should be completed now"
}

###################### Do Works ######################
if [[ -f "$test_module".ko ]]; then
  test_print_trc "Kernel test module: $test_module.ko is ready for test"
  insmod "$test_module".ko || \
    { die "Fail to insmod test module $test_module.ko"; exit 1; }
  test_print_trc "$test_module.ko inserted and hlt instruction triggered"
  module_check
  sleep 3
  rmmod "$test_module" || \
    { die "Fail to rmmod test module $test_module.ko"; exit 1; }
else
  die "Kernel test module $test_module.ko not found"
  exit 1
fi