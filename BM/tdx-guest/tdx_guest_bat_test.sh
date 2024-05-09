#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  14, Dec., 2023 - Hongyu Ning - creation


# @desc This script do basic acceptance test in TDX Guest VM

###################### Variables ######################
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"
source common.sh

while getopts :t: arg; do
  case $arg in
    t)
      BAT_CASE=$OPTARG
      ;;
    *)
      test_print_err "Must supply an argument to -$OPTARG."
      exit 1
      ;;
  esac
done

###################### Functions ######################
# Check this cpu could support the function which contain the parameter
# $1: Parameter should be support in cpuinfo
# Return: 0 for true, otherwise false
cpu_info_check() {
  local cpu_func=$1
  [ -n "$cpu_func" ] || die "cpu info check name is null:$cpu_func"
  grep -q "$cpu_func" /proc/cpuinfo || block_test "CPU not support:$cpu_func"
  test_print_trc "/proc/cpuinfo contain '$cpu_func'"
  return 0
}

# function based on test_kconfig, check if kconfig is set to y
kconfig_y() {
  local KCONFIG_ITEM=$1
  test_kconfig "y" "$KCONFIG_ITEM" || \
    die "$KCONFIG_ITEM not set to y"
  test_print_trc "$KCONFIG_ITEM set to y as expected"
}

# function based on test_kconfig, check if kconfig is set to y or m
kconfig_y_or_m() {
  local KCONFIG_ITEM=$1
  if test_kconfig "y" "$KCONFIG_ITEM"; then
    test_print_trc "$KCONFIG_ITEM set to y as expected"
  elif test_kconfig "m" "$KCONFIG_ITEM"; then
    test_print_trc "$KCONFIG_ITEM set to m as expected"
  else
    die "$KCONFIG_ITEM not set to y or m"
  fi
}

###################### Do Works ######################
case "$BAT_CASE" in
  GUEST_CPUINFO)
    cpu_info_check tdx_guest
    ;;
  GUEST_KCONFIG)
    kconfig_y CONFIG_INTEL_TDX_GUEST
    ;;
  GUEST_DRIVER_KCONFIG)
    kconfig_y_or_m CONFIG_TDX_GUEST_DRIVER
    ;;
  GUEST_LAZY_ACCEPT_KCONFIG)
    kconfig_y CONFIG_UNACCEPTED_MEMORY
    ;;
  GUEST_TSM_REPORTS_KCONFIG)
    kconfig_y_or_m CONFIG_TSM_REPORTS
    ;;
  GUEST_ATTEST_DEV)
    ATTEST_DEV=/dev/tdx_guest
    if [ -c "$ATTEST_DEV" ]; then
      test_print_trc "TDX guest attestation device exists"
    else
      die "TDX guest attestation device $ATTEST_DEV doesn't exist"
    fi
    ;;
  :)
    test_print_err "Must specify the memory case option by [-t]"
    exit 1
    ;;
  \?)
    test_print_err "Input test case option $BAT_CASE is not supported"
    exit 1
    ;;
esac