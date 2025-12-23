#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2025 Intel Corporation
# Author:   Farrah Chen <farrah.chen@intel.com>
# @Desc This script verify Fred tests

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env


: "${CASE_NAME:=""}"

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-t TESTCASE_ID] [-H]
  -t  TEST CASE ID
  -H  show this
__EOF
}

###################### Functions ######################
# Check if FRED is enabled in Kernel config
kconfig_test() {
  local ret=0
  general_test.sh -t kconfig -k "CONFIG_X86_FRED=y" || ret=1
  [ $ret -eq 0 ] || die "CONFIG_X86_FRED=y is not set in Kconfig, FRED is not enabled"
}

# Check this cpu could support the function which contain the parameter
# $1: Parameter should be support in cpuinfo
# Return: 0 for true, otherwise false
cpu_info_check() {
  do_cmd "grep -q 'fred=on' '/proc/cmdline'"
  local cpu_func=$1
  [ -n "$cpu_func" ] || die "cpu info check name is null:$cpu_func"
  grep -q "$cpu_func" /proc/cpuinfo || block_test "CPU not support:$cpu_func"
  test_print_trc "/proc/cpuinfo contain '$cpu_func'"
  return 0
}

# Dmesg test: Verify if FRED is initialized
dmesg_test() {
  do_cmd "grep -q 'fred=on' '/proc/cmdline'"
  do_cmd "dmesg | grep 'Initialize FRED on CPU'"
}

# CPUID test: Check FRED CPUID
cpuid_test() {
  #CPUID.0x7.1.EAX[17] == 1
  do_cmd "cpuid_check 7 0 1 0 a 17"
}

# LKGS CPUID test: Check LKGS CPUID
lkgs_cpuid_test() {
  #CPUID.0x7.1.EAX[18] == 1
  do_cmd "cpuid_check 7 0 1 0 a 18"
}

# CPUINFO test: Check FRED cpu flag in cpu info
cpuinfo_test() {
  do_cmd "cpu_info_check fred"
}

fred_test() {
  case $TEST_SCENARIO in
    kconfig)
      kconfig_test
      ;;
    dmesg)
      dmesg_test
      ;;
    cpuid)
      cpuid_test
      ;;
    cpuinfo)
      cpuinfo_test
      ;;
    lkgs)
      lkgs_cpuid_test
      ;;
    *)
      echo "Invalid option"
      return 1
  esac
  return 0
 }

while getopts :t:H arg; do
  case $arg in
    t)
      TEST_SCENARIO=$OPTARG
      ;;
    H)
      usage && exit 0
      ;;
    \?)
      usage
      die "Invalid Option -$OPTARG"
      ;;
    :)
      usage
      die "Option -$OPTARG requires an argument."
      ;;
  esac
done

fred_test "$@"
# Call teardown for passing case
exec_teardown
