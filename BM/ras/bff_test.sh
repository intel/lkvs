#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation
# Author: Yi Lai <yi1.lai@intel.com>
# @Desc  Test script to verify MCE corrected error yellow threshold status

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env
source ./ras_common.sh

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-t TESTCASE_ID] [-H]
  -t  TEST CASE ID
  -H  show this
__EOF
}

bff_test() {
  case $TEST_SCENARIO in
  bff_yellow)
    mce_config
    mce_log_clear # Clear previous MCE records

    # Load mce-inject module
    modprobe mce-inject || die "Failed to load mce-inject module"

    # Inject corrected-yellow MCE
    mce-inject ./mce-inject/test/corrected-yellow || die "mce-inject corrected-yellow failed"

    # Verify dmesg reports machine check events
    if ! dmesg | grep -q "Machine check events logged"; then
      die "dmesg does not contain 'Machine check events logged'"
    fi
    test_print_trc "dmesg confirms machine check events logged"

    # Verify MCE log reports yellow threshold status
    if ! mce_log_check "Threshold based error status: yellow"; then
      die "MCE log does not contain yellow threshold status"
    fi
    test_print_trc "MCE log confirms yellow threshold status"
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

bff_test
