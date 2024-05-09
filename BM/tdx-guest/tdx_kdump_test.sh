#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  28, Feb., 2024 - Hongyu Ning - creation


# @desc This script do kdump trigger and crash log check test in TDX Guest VM

###################### Variables ######################
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"
source common.sh

while getopts :t: arg; do
  case $arg in
    t)
      KDUMP_CASE=$OPTARG
      ;;
    *)
      test_print_err "Must supply an argument to -$OPTARG."
      exit 1
      ;;
  esac
done

###################### Functions ######################
# function to prepare and trigger kdump for further check
kdump_start() {
  if ! kdumpctl restart; then
    die "failed to restart kdump service, test failed"
  fi
  if [ -d /var/crash ]; then
    test_print_trc "start to clean /var/crash/* for test prepare"
    rm -rf /var/crash/*
    sync
  fi
  sleep 1
  echo c > /proc/sysrq-trigger
}

# function to check if previous triggered kdump log work as expected
kdump_check() {
  if ! find /var/crash/ | grep "vmcore$"; then
    die "no crash log found, test failed"
  else
    test_print_trc "kdump crash log found, kdump/kexec test PASS"
  fi
}

###################### Do Works ######################
case "$KDUMP_CASE" in
  KDUMP_S)
    kdump_start
    ;;
  KDUMP_C)
    kdump_check
    ;;
  :)
    test_print_err "Must specify the memory case option by [-t]"
    exit 1
    ;;
  \?)
    test_print_err "Input test case option $KDUMP_CASE is not supported"
    exit 1
    ;;
esac