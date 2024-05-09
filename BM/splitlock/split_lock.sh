#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation
# Description:  Test script for split lock of CPU

cd "$(dirname "$0")" 2>/dev/null && source ../.env

: "${CASE_NAME:="check_cpu_info"}"

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-t TESTCASE_ID] [-H]
  -t  TEST CASE ID
  -H  show this
__EOF
}

# Check this feature is enabled/supported
# Return: 0 for true, otherwise false
check_cpu_info() {
  local cpu_func="split_lock_detect"
  grep -q "$cpu_func" /proc/cpuinfo || block_test "CPU not support:$cpu_func"
  test_print_trc "/proc/cpuinfo contain '$cpu_func'"
}

# Call split lock test and check dmesg if #AC is triggered
split_lock_ac() {
  local ac_dmesg_start=$(dmesg | grep "x86/split lock detection: #" | wc -l)
  sl_test
  local ac_dmesg_end=$(dmesg | grep "x86/split lock detection: #" | wc -l)
  grep -q "split_lock_detect=fatal" /proc/cmdline && block_test "If set is fatal won't trigger #AC"
  if [[ $ac_dmesg_end -gt $ac_dmesg_start ]];then
    test_print_trc "split_lock_dect: [PASS]"
  else
    die "split_lock_dect: [FAIL]"
  fi
}

split_lock_test() {
  case $TEST_SCENARIO in
  sl_on_default)
    check_cpu_info
    ;;
  check_ac_dmesg)
    split_lock_ac
    ;;
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

split_lock_test
