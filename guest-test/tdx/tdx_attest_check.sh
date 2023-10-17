#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  16, Oct., 2023 - Hongyu Ning - creation


# @desc This script do basic TD attestation check in TDX Guest VM
#       test binary is based on kselftest linux/tools/testing/selftests/tdx implementation

###################### Variables ######################
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"
source common.sh

while getopts :t: arg; do
	case $arg in
		t)
			ATTEST_CASE=$OPTARG
			;;
		*)
			test_print_err "Must supply an argument to -$OPTARG."
			exit 1
			;;
	esac
done

###################### Functions ######################
attest_result() {
    selftest_item=$1
    case "$selftest_item" in
        global.verify_report)
            selftest_num=1
            ;;
        global.verify_reportmac)
            selftest_num=2
            ;;
        global.verify_rtmr_extend)
            selftest_num=3
            ;;
        global.verify_quote)
            selftest_num=4
            ;;
    esac
    test_print_trc "TD attestation - $selftest_item start."
    if [ -f "attest.log" ]; then
        rm -rf attest.log
    fi
    ./tdx_guest_test | tee attest.log
    results=$(grep "not ok $selftest_num $selftest_item" attest.log)
    if [ -z "$results" ]; then
        test_print_trc "TD attestation - $selftest_item PASS."
    else
        die "TD attestation - $selftest_item FAIL."
        return 1
    fi
}

###################### Do Works ######################

case "$ATTEST_CASE" in
    global.verify_report)
        attest_result "$ATTEST_CASE"
        ;;
    global.verify_reportmac)
        attest_result "$ATTEST_CASE"
        ;;
    global.verify_rtmr_extend)
        attest_result "$ATTEST_CASE"
        ;;
    global.verify_quote)
        attest_result "$ATTEST_CASE"
        ;;
    :)
        test_print_err "Must specify the attest case option by [-t]"
        exit 1
        ;;
    \?)
        test_print_err "Input test case option $ATTEST_CASE is not supported"
        exit 1
        ;;
esac    