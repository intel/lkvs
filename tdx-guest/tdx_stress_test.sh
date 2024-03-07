#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  5, Mar., 2024 - Hongyu Ning - creation


# @desc This script do multiple types of stress tests in TDX Guest VM

###################### Variables ######################
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"
source common.sh

# general stress time set as 300 seconds
STRESS_TIME=300

while getopts :t:w: arg; do
  case $arg in
    t)
      STRESS_CASE=$OPTARG
      ;;
    w)
      WORKERS=$OPTARG
      ;;
    *)
      test_print_err "Must supply an argument to -$OPTARG."
      exit 1
      ;;
  esac
done

###################### Functions ######################
# function based on stress-ng memrate stressor to stress
# mememory by read and write
stress_memrate() {
  local stress_result
  local pass_result
  local fail_result
  local skip_result
  stress_result=$(stress-ng --memrate "$WORKERS" --memrate-bytes 1G --memrate-rd-mbs 1000 --memrate-wr-mbs 1000 -t "$STRESS_TIME")
  pass_result=$(echo "$stress_result" | grep -oP '(?<=passed: )\d+')
  fail_result=$(echo "$stress_result" | grep -oP '(?<=failed: )\d+')
  skip_result=$(echo "$stress_result" | grep -oP '(?<=skipped: )\d+')
  test_print_trc "stress-ng memrate stressor results:"
  echo "$stress_result"
  if [[ "$fail_result" -gt 0 ]]; then
    die "stress-ng with memrate stressor failed $fail_result out of $WORKERS"
  elif [[ "$skip_result" -gt 0 ]]; then
    test_print_wrg "stress-ng with memrate stressor skipped $skip_result out of $WORKERS"
  else
    test_print_trc "stress-ng with memrate stressor passed $pass_result out of $WORKERS"
  fi
}

# function based on stress-ng sock(et) and iomix stressors
# to stress socket handling and IO
stress_sock_iomix () {
  local stress_result
  local pass_result
  local fail_result
  local skip_result
  stress_result=$(stress-ng --sock "$WORKERS" --iomix "$WORKERS" -t "$STRESS_TIME")
  pass_result=$(echo "$stress_result" | grep -oP '(?<=passed: )\d+')
  fail_result=$(echo "$stress_result" | grep -oP '(?<=failed: )\d+')
  skip_result=$(echo "$stress_result" | grep -oP '(?<=skipped: )\d+')
  test_print_trc "stress-ng sock + iomix stressor results:"
  echo "$stress_result"
  if [[ "$fail_result" -gt 0 ]]; then
    die "stress-ng with sock + iomix stressor failed $fail_result out of $((WORKERS * 2))"
  elif [[ "$skip_result" -gt 0 ]]; then
    test_print_wrg "stress-ng with sock + iomix stressor skipped $skip_result out of $((WORKERS * 2))"
  else
    test_print_trc "stress-ng with sock + iomix stressor passed $pass_result out of $((WORKERS * 2))"
  fi
}

###################### Do Works ######################
# prepare for stress prerequisites
if [ ! "$(which stress-ng)" ]; then
  dnf install -y stress-ng > /dev/null
  apt install -y stress-ng > /dev/null
else
  test_print_trc "stress-ng prerequisites is ready for use"
fi

case "$STRESS_CASE" in
  STRESS_MEMRATE)
    stress_memrate
    ;;
  STRESS_SOCK_IOMIX)
    stress_sock_iomix
    ;;
  :)
    test_print_err "Must specify the memory case option by [-t]"
    exit 1
    ;;
  \?)
    test_print_err "Input test case option $STRESS_CASE is not supported"
    exit 1
    ;;
esac