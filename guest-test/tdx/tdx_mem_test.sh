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

###################### Do Works ######################
case "$MEM_CASE" in
  EBIZZY_FUNC)
    ebizzy_func
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