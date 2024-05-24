#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  23, Nov., 2023 - Hongyu Ning - creation


# @desc This script do basic memory test in TDX Guest VM

###################### Variables ######################
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"
source common.sh

while getopts :t: arg; do
  case $arg in
    t)
      MEM_CASE=$OPTARG
      ;;
    *)
      test_print_err "Must supply an argument to -$OPTARG."
      exit 1
      ;;
  esac
done

###################### Functions ######################
ebizzy_func() {
  test_print_trc "Start TDX guest ebizzy test 10s with malloc"
  ./ebizzy -M
  ebizzy_malloc=$?
  test_print_trc "Start TDX guest ebizzy test 10s with mmap"
  ./ebizzy -m
  ebizzy_mmap=$?
  if [[ $ebizzy_malloc == 0 && $ebizzy_mmap == 0 ]]; then
    test_print_trc "TDX guest ebizzy test PASS"
    return 0
  else
    die "TDX guest ebizzy test FAIL"
  fi
}

# function calculate total remained mem accepted time
mem_accepted_time() {
  # common expected time consumed in seconds
  expected_time=$1
  # mem stress process number
  workers=$2
  # calculate memory accepted fully completed time
  SECONDS=0
  count=1
  # tail /dev/zero to continously read and store null bytes w/o newline char into memory
  while [ $count -le $workers ]; do
    tail /dev/zero &
    count=$((count+1))
  done
  # monitor on /proc/vmstat of unaccepted memory as mem drained signal
  while (true); do
    if [[ $(grep "nr_unaccepted" /proc/vmstat | awk '{print $2}') -eq 0 ]]; then
      actual_time=$SECONDS;
      killall -e -v tail;
      break;
    fi
  done
  # check if memory accept time far exceed expected (passed in value)
  compare_result=$(echo "scale=2; ($actual_time/$expected_time)" | bc)
  baseline_result=1.15
  result=$(awk -v n1="$compare_result" -v n2="$baseline_result" 'BEGIN {if (n1>n2) print 1; else print 0}')
  if [ "$result" -eq 0 ]; then
    test_print_trc "Memory accepted full time consumed: $actual_time"
    return 0
  else
    die "Memory accepted full time consumed: $actual_time seconds, \
    It's over expectation $expected_time seconds 15% more!!!"
  fi
}

# function based on stress-ng do basic mem lazy accept function check
mem_accept_func() {
  # prepare for prerequisites
  if [ ! "$(which stress-ng)" ]; then
    dnf install -y stress-ng > /dev/null
    apt install -y stress-ng > /dev/null
  else
    test_print_trc "stress-ng prerequisites is ready for use"
  fi
  bootup_vmstat=$(grep "nr_unaccepted" /proc/vmstat | cut -d' ' -f2)
  stress-ng --vm 1 --vm-bytes 10% --timeout 3s
  stress_vmstat=$(grep "nr_unaccepted" /proc/vmstat | cut -d' ' -f2)
  if [[ "$bootup_vmstat" -gt "$stress_vmstat" ]]; then
    test_print_trc "TD VM unaccepted memory func test PASS"
  else
    die "TD VM unaccepted memory func test FAIL"
  fi
}

# function mem lazy accept info calculation
mem_accept_cal() {
  test_print_trc "Start TD VM unaccepted memory info calculation check"
  vmstat=$(grep "nr_unaccepted" /proc/vmstat | cut -d' ' -f2)
  meminfo=$(awk '/Unaccepted/{printf "%d\n", $2;}' </proc/meminfo)
  pagesize=$(getconf PAGESIZE)
  test_print_trc "vmstat: $vmstat; meminfo= $meminfo"
  if [[ $((vmstat * pagesize / 1024)) -eq "$meminfo" ]]; then
    test_print_trc "TD VM unaccepted memory info calculation PASS"
  else
    die "TD VM unaccepted memory info calculation FAIL"
  fi
}

# function mem lazy accept negative test
mem_accept_neg() {
  test_print_trc "Start TD VM unaccepted memory negative test"
  vmstat_disable=$(grep "nr_unaccepted" /proc/vmstat | cut -d' ' -f2)
  if [[ "$vmstat_disable" -eq 0 ]]; then
    test_print_trc "TD VM unaccepted memory negative test PASS"
  else
    die "TD VM unaccepted memory negative test FAIL with nr_unaccepted: $vmstat_disable"
  fi
}

###################### Do Works ######################
case "$MEM_CASE" in
  EBIZZY_FUNC)
    ebizzy_func
    ;;
  MEM_ACPT_T_1C_8G_1W)
    # expected 24secs in case of
    # 1VCPU + 8G MEM + 1 mem stress process
    mem_accepted_time 24 1
    ;;
  MEM_ACPT_T_1C_8G_8W)
    # expected 19secs in case of
    # 1VCPU + 8G MEM + 8 mem stress processes
    mem_accepted_time 19 8
    ;;
  MEM_ACPT_T_1C_32G_1W)
    # expected 119secs in case of
    # 1VCPU + 32G MEM + 1 mem stress process
    mem_accepted_time 119 1
    ;;
  MEM_ACPT_T_1C_32G_8W)
    # expected 95secs in case of
    # 1VCPU + 32G MEM + 8 mem stress processes
    mem_accepted_time 95 8
    ;;
  MEM_ACPT_T_1C_96G_1W)
    # expected 398secs in case of
    # 1VCPU + 32G MEM + 1 mem stress process
    mem_accepted_time 398 1
    ;;
  MEM_ACPT_T_1C_96G_8W)
    # expected 321secs in case of
    # 1VCPU + 32G MEM + 8 mem stress processes
    mem_accepted_time 321 8
    ;;
  MEM_ACPT_T_32C_16G_1W)
    # expected 34secs in case of
    # 32VCPU + 16G MEM + 1 mem stress process
    mem_accepted_time 34 1
    ;;
  MEM_ACPT_T_32C_16G_32W)
    # expected 6secs in case of
    # 32VCPU + 16G MEM + 32 mem stress processes
    mem_accepted_time 6 32
    ;;
  MEM_ACPT_T_32C_32G_1W)
    # expected 80secs in case of
    # 32VCPU + 32G MEM + 1 mem stress process
    mem_accepted_time 80 1
    ;;
  MEM_ACPT_T_32C_32G_32W)
    # expected 11secs in case of
    # 32VCPU + 32G MEM + 32 mem stress processes
    mem_accepted_time 11 32
    ;;
  MEM_ACPT_T_32C_96G_1W)
    # expected 271secs in case of
    # 32VCPU + 96G MEM + 1 mem stress process
    mem_accepted_time 271 1
    ;;
  MEM_ACPT_T_32C_96G_32W)
    # expected 33secs in case of
    # 32VCPU + 96G MEM + 32 mem stress processes
    mem_accepted_time 33 32
    ;;
  MEM_ACPT_FUNC)
    mem_accept_func
    ;;
  MEM_ACPT_CAL)
    mem_accept_cal
    ;;
  MEM_ACPT_NEG)
    mem_accept_neg
    ;;
  :)
    test_print_err "Must specify the memory case option by [-t]"
    exit 1
    ;;
  \?)
    test_print_err "Input test case option $MEM_CASE is not supported"
    exit 1
    ;;
esac