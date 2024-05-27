#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation
# Description:  Test script for Intel i10nm EDAC driver, which supports 10nm series server
# EDAC: Error Detection and Correction
# @Author  Yi Lai  yi1.lai@intel.com


cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

EDAC_BUS="/sys/bus/edac"
EDAC_DRIVER=i10nm_edac

: "${CASE_NAME:=""}"

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-t TESTCASE_ID] [-H]
  -t  TEST CASE ID
  -H  show this
__EOF
}

edac_test() {
  case $TEST_SCENARIO in
  check_edac_bus)
    edac_bus=$(ls $EDAC_BUS)
    if [ -n "$edac_bus" ]; then
      test_print_trc "EDAC bus is found"
    else
      die "EDAC bus is not found"
    fi
    ;;
  check_edac_driver)
    test_print_trc "Check Intel i10nm edac driver"
    lsmod | grep -q $EDAC_DRIVER
    if ! lsmod | grep -q $EDAC_DRIVER; then
      die "Intel i10nm edac driver is not loaded"
    else
      test_print_trc "Intel i10nm edac driver is loaded"
    fi
    ;;
  esac
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

edac_test
