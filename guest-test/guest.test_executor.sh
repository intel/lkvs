#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  24, Aug., 2023 - Hongyu Ning - creation


# @desc This script prepare and run $TESTCASE in Guest VM

###################### Variables ######################
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"
GUEST_TEST_DIR="/root/guest_test/"

###################### Functions ######################

# function based on sshpass to scp common.sh and $1 test_script.sh to Guest VM
guest_test_prepare() {
  rm -rf common.sh
  wget https://raw.githubusercontent.com/intel/lkvs/main/common/common.sh
  sshpass -e ssh -p "$PORT" -o StrictHostKeyChecking=no root@localhost << EOF
    rm -rf $GUEST_TEST_DIR
    mkdir $GUEST_TEST_DIR
EOF
  sshpass -e scp -P "$PORT" -o StrictHostKeyChecking=no common.sh root@localhost:"$GUEST_TEST_DIR"
  sshpass -e scp -P "$PORT" -o StrictHostKeyChecking=no "$1" root@localhost:"$GUEST_TEST_DIR"
  test_print_trc "Guest VM test script prepare complete"
}

# function based on sshpass to scp $1 source_code_dir and compile $2 test_binary in Guest VM
guest_test_source_code() {
  sshpass -e ssh -p "$PORT" -o StrictHostKeyChecking=no root@localhost << EOF
    mkdir -p $GUEST_TEST_DIR/$1
EOF
  sshpass -e scp -P "$PORT" -o StrictHostKeyChecking=no -r "$1"/* root@localhost:"$GUEST_TEST_DIR/$1"
  sshpass -e ssh -p "$PORT" -o StrictHostKeyChecking=no root@localhost << EOF
    source $GUEST_TEST_DIR/common.sh
    cd $GUEST_TEST_DIR || { die "Failed to cd to $GUEST_TEST_DIR; return 1; }
    cd $1 || { die "Failed to cd to $1; return 1; }
    make || { die "Failed to compile source code $1"; return 1; }
    if [ -f $2 ]; then
      chmod a+x $2
      cp $2 $GUEST_TEST_DIR
    else
      die "Can't find test binary $2"
      return 1
    fi
EOF
  test_print_trc "Guest VM test source code and binary prepare complete"
}

# function based on sshpass to execute $1 test_script.sh and potential $2 script params in Guest VM
guest_test_entry() {
  sshpass -e ssh -p "$PORT" -o StrictHostKeyChecking=no root@localhost << EOF
    source $GUEST_TEST_DIR/common.sh
    cd $GUEST_TEST_DIR
    test_print_trc "guest_test_entry args 1: $1"
    test_print_trc "guest_test_entry args 2: $2"
    ./$1 $2
EOF
ERR_NUM=$?
if [ $ERR_NUM -eq 0 ] || [ $ERR_NUM -eq 255 ]; then
  return 0
else
  return 1
fi
}

# function based on sshpass to close VM
guest_test_close() {
  sshpass -e ssh -p "$PORT" -o StrictHostKeyChecking=no root@localhost << EOF
    source $GUEST_TEST_DIR/common.sh
    test_print_trc "guest test complete, close VM now"
    systemctl reboot --reboot-argument=now
EOF
  test_print_trc "Guest VM closed properly after test"
}

guest_attest_test() {
  selftest_item=$1
  guest_test_prepare tdx/tdx_attest_check.sh
  guest_test_source_code tdx/tdx_attest_test_suite tdx_guest_test || \
  { die "Failed to prepare guest test source code for $selftest_item"; return 1; }
  guest_test_entry tdx_attest_check.sh "-t $selftest_item" || \
  { die "Failed on $TESTCASE tdx_attest_check.sh -t $selftest_item"; return 1; }
  if [[ $GCOV == "off" ]]; then
    guest_test_close
  fi
}

###################### Do Works ######################
cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

# get test scenario config for test_executor
source "$SCRIPT_DIR"/test_params.py

cd "$SCRIPT_DIR" || die "fail to switch to $SCRIPT_DIR"
# select test_functions by $TEST_SCENARIO
case "$TESTCASE" in
  TD_BOOT)
    guest_test_prepare tdx/tdx_guest_boot_check.sh
    guest_test_entry tdx_guest_boot_check.sh "-v $VCPU -s $SOCKETS -m $MEM" || \
    die "Failed on TD_BOOT test tdx_guest_boot_check.sh -v $VCPU -s $SOCKETS -m $MEM"
    if [[ $GCOV == "off" ]]; then
      guest_test_close
    fi
    ;;
  GUEST_TESTCASE_EXAMPLE)
    guest_test_prepare guest_test.sh
    guest_test_source_code test_source_code_dir_example test_binary_example
    guest_test_entry guest_test.sh "-t $TESTCASE" || \
    die "Failed on $TESTCASE guest_test.sh -t $TESTCASE"
    if [[ $GCOV == "off" ]]; then
      guest_test_close
    fi
    ;;
  TD_ATTEST_VERIFY_REPORT)
    guest_attest_test "global.verify_report" || \
    die "Failed on $TESTCASE"
    ;;
  TD_ATTEST_VERITY_REPORTMAC)
    guest_attest_test "global.verify_reportmac" || \
    die "Failed on $TESTCASE"
    ;;
  TD_ATTEST_VERIFY_RTMR_EXTEND)
    guest_attest_test "global.verify_rtmr_extend" || \
    die "Failed on $TESTCASE"
    ;;
  TD_ATTEST_VERIFY_QUOTE)
    guest_attest_test "global.verify_quote" || \
    die "Failed on $TESTCASE"
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