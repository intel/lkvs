#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation
# Description: Test script for Data Streaming Accelerator(DSA)

cd "$(dirname "$0")" 2>/dev/null && source ../.env

: "${CASE_NAME:="check_dsa_driver"}"

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-t TESTCASE_ID] [-H]
  -t  TEST CASE ID
  -H  show this
__EOF
}

# Check if idxd driver is loaded
# Return: 0 for true, otherwise false
check_dsa_driver() {
  if lsmod | grep -q "idxd"; then
    test_print_trc "dsa: idxd driver is loaded [PASS]"
  else
    die "dsa: idxd driver is not loaded [FAIL]"
  fi
}

# Check if there is dsa device dsa0
check_dsa0_device() {
  if [ -d "/sys/bus/dsa/devices/dsa0" ]; then
    test_print_trc "dsa: there is dsa0 device [PASS]"
  else
    die "dsa: no dsa0 device [FAIL]"
  fi
}

# check if pasid is supported
check_shared_mode() {
  [ ! -f "/sys/bus/dsa/devices/dsa0/pasid_enabled" ] && echo "No SVM support" && exit 1
  pasid_en=$(cat /sys/bus/dsa/devices/dsa0/pasid_enabled)
  if [ "$pasid_en" -eq 1 ]; then
    test_print_trc "dsa: shared mode is enabled [PASS]"
  else
    die "dsa: shared mode is not enabled [FAIL]"
  fi
}

dsa_test() {
  case $TEST_SCENARIO in
  check_dsa_driver)
    check_dsa_driver
    ;;
  check_dsa0_device)
    check_dsa0_device
    ;;
  check_shared_mode)
    check_shared_mode
    ;;
  *)
    block_test "Invalid NAME:$NAME for test number."
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

dsa_test
