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
  ebizzy -M
  ebizzy_malloc=$?
  test_print_trc "Start TDX guest ebizzy test 10s with mmap"
  ebizzy -m
  ebizzy_mmap=$?
  if [[ $ebizzy_malloc == 0 && $ebizzy_mmap == 0 ]]; then
    test_print_trc "TDX guest ebizzy test PASS"
    return 0
  else
    die "TDX guest ebizzy test FAIL"
    return 1
  fi
}

# function based on stress-ng calculate total remained mem accepted time
mem_accepted_time() {
# common expected time consumed in seconds
expected_time=$1
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
stress-ng --vm 1 --vm-bytes 100% &
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
  die "Memory accepted full time consumed: $actual_time seconds"
  die "It's over expectation $expected_time seconds 10% more!!!"
  return 1
fi
}

###################### Do Works ######################
case "$MEM_CASE" in
  EBIZZY_FUNC)
    ebizzy_func
    ;;
  MEM_ACCEPT_TIME_4G)
    # expected 4 secs
    mem_accepted_time 4
    ;;
  MEM_ACCEPT_TIME_16G)
    # expected 1 min 4 secs
    mem_accepted_time 64
    ;;
  MEM_ACCEPT_TIME_32G)
    # expected 2 mins 18 secs
    mem_accepted_time 138
    ;;
  MEM_ACCEPT_TIME_64G)
    # expected 4 mins 46 secs
    mem_accepted_time 286
    ;;
  MEM_ACCEPT_TIME_96G)
    # expected 5 mins 59 secs
    mem_accepted_time 359
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