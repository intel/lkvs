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

# function based on stress-ng calculate total remained mem accepted time
mem_accepted_time() {
  # common expected time consumed in seconds
  expected_time=$1
  # stress-ng mem stress process number
  workers=$2
  # prepare for prerequisites
  if [ ! "$(which stress-ng)" ]; then
    dnf install -y stress-ng > /dev/null
    apt install -y stress-ng > /dev/null
  else
    test_print_trc "stress-ng prerequisites is ready for use"
    test_print_trc "unaccepted memory drained time calculation is starting now..."
  fi
  # calculate memory accepted fully completed time
  SECONDS=0
  stress-ng --vm "$workers" --vm-bytes 100% &
  while (true); do
    if [[ $(grep "nr_unaccepted" /proc/vmstat | awk '{print $2}') -eq 0 ]]; then
      actual_time=$SECONDS;
      pkill stress-ng;
      break;
    fi
  done
  # check if memory accept time far exceed expected (passed in value)
  compare_result=$(echo "scale=2; ($actual_time/$expected_time)" | bc)
  baseline_result=1.1
  result=$(awk -v n1="$compare_result" -v n2="$baseline_result" 'BEGIN {if (n1>n2) print 1; else print 0}')
  if [ "$result" -eq 0 ]; then
    test_print_trc "Memory accepted full time consumed: $actual_time"
    return 0
  else
    die "Memory accepted full time consumed: $actual_time seconds, \
    It's over expectation $expected_time seconds 10% more!!!"
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
    test_print_trc "unaccepted memory drained time calculation is starting now..."
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
    test_print_trc "TD VM unaccepted memory negative test"
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
  MEM_ACPT_T_1C_8G_32W)
    # expected 26secs in case of
    # 1VCPU + 8G MEM + 32 mem stress processes
    mem_accepted_time 26 32
    ;;
  MEM_ACPT_T_1C_32G_1W)
    # expected 148secs in case of
    # 1VCPU + 32G MEM + 1 mem stress process
    mem_accepted_time 148 1
    ;;
  MEM_ACPT_T_1C_32G_32W)
    # expected 232secs in case of
    # 1VCPU + 32G MEM + 32 mem stress processes
    mem_accepted_time 232 32
    ;;
  MEM_ACPT_T_1C_96G_1W)
    # expected 472secs in case of
    # 1VCPU + 32G MEM + 1 mem stress process
    mem_accepted_time 472 1
    ;;
  MEM_ACPT_T_1C_96G_32W)
    # expected 773secs in case of
    # 1VCPU + 32G MEM + 32 mem stress processes
    mem_accepted_time 773 32
    ;;
  MEM_ACPT_T_32C_8G_32W)
    # expected 2secs in case of
    # 32VCPU + 8G MEM + 32 mem stress processes
    mem_accepted_time 2 32
    ;;
  MEM_ACPT_T_32C_8G_256W)
    # expected 4secs in case of
    # 32VCPU + 8G MEM + 256 mem stress processes
    mem_accepted_time 4 256
    ;;
  MEM_ACPT_T_32C_32G_32W)
    # expected 29secs in case of
    # 32VCPU + 32G MEM + 32 mem stress processes
    mem_accepted_time 29 32
    ;;
  MEM_ACPT_T_32C_32G_256W)
    # expected 33secs in case of
    # 32VCPU + 32G MEM + 256 mem stress processes
    mem_accepted_time 33 256
    ;;
  MEM_ACPT_T_32C_96G_32W)
    # expected 284secs in case of
    # 32VCPU + 96G MEM + 32 mem stress processes
    mem_accepted_time 284 32
    ;;
  MEM_ACPT_T_32C_96G_256W)
    # expected 92secs in case of
    # 32VCPU + 96G MEM + 256 mem stress processes
    mem_accepted_time 92 256
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