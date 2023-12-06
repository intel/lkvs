#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  5, Dec., 2023 - Hongyu Ning - creation


# @desc This script prepare and run $TESTCASE in for $FEATURE tdx_osv_sanity
# in tdx VM; please note, $FEATURE name and subfolder name under guest-test
# must be the exactly same, here FEATURE=tdx_osv_sanity

###################### Variables ######################
## common variables example ##
SCRIPT_DIR_LOCAL="$( cd $( dirname "$0" ) && pwd )"
echo "$SCRIPT_DIR_LOCAL"
# get test scenario config for $FEATURE tdx test_executor
source "$SCRIPT_DIR_LOCAL"/../test_params.py
## end of common variables example ##

###################### Functions ######################
## $FEATURE specific Functions ##

###################### Do Works ######################
## common works example ## 
cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../../.env

# get test_executor common functions:
# function based on sshpass to scp common.sh and $1 test_script.sh to Guest VM
## guest_test_prepare
# function based on sshpass to scp $1 source_code_dir and compile $2 test_binary in Guest VM
## guest_test_source_code
# function based on sshpass to execute $1 test_script.sh and potential $2 script params in Guest VM
## guest_test_entry
# function based on sshpass to close VM
## guest_test_close
source "$SCRIPT_DIR"/guest.test_executor.sh

cd "$SCRIPT_DIR_LOCAL" || die "fail to switch to $SCRIPT_DIR_LOCAL"
## end of common works example ##

## $FEATURE specific code path ##
# select test_functions by $TESTCASE
case "$TESTCASE" in
  GUEST_TESTCASE_EXAMPLE)
    guest_test_prepare guest_test.sh
    guest_test_source_code test_source_code_dir_example test_binary_example
    guest_test_entry guest_test.sh "-t $TESTCASE" || \
    die "Failed on $TESTCASE guest_test.sh -t $TESTCASE"
    if [[ $GCOV == "off" ]]; then
      guest_test_close
    fi
    ;;
  TD_TSC_DEFAULT)
    guest_test_prepare tdx_guest_tsc_check.sh
    source tdx_host_tsc_check.sh
    guest_test_entry tdx_guest_tsc_check.sh "-c $HOST_TSC" || \
    { die "Failed on TD_TSC_DEFAULT tdx_guest_tsc_check.sh -c $HOST_TSC"; return 1; }
    if [[ $GCOV == "off" ]]; then
      guest_test_close
    fi
    ;;
  TD_TSC_CONFIG)
    guest_test_prepare tdx_guest_tsc_check.sh
    CONFIG_TSC=3000000000
    guest_test_entry tdx_guest_tsc_check.sh "-c $CONFIG_TSC" || \
    { die "Failed on TD_TSC_CONFIG tdx_guest_tsc_check.sh -c $CONFIG_TSC"; return 1; }
    if [[ $GCOV == "off" ]]; then
      guest_test_close
    fi
    ;;
  :)
    test_print_err "Must specify the test scenario option by [-t]"
    usage && exit 1
    ;;
  \?)
    test_print_err "Input test case option $TESTCASE is not supported"
    usage && exit 1
    ;;
esac