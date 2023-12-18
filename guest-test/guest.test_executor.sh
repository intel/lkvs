#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  24, Aug., 2023 - Hongyu Ning - creation


# @desc This script prepare and run $TESTCASE in Guest VM
# based on $FEATURE selection

###################### Variables ######################
# exec only if script being executed
if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
  SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
  echo "$SCRIPT_DIR"
else # bypass above execution in case of being sourced
  echo "guest.test_executor.sh being sourced"
fi
GUEST_TEST_DIR="/root/guest_test/"

###################### Functions ######################
# Common functions to be leveraged by $FEATURE/$FEATURE.test_executor.sh

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
    cd $GUEST_TEST_DIR
    cd $1
    dnf list installed gcc || dnf install -y gcc || \
    { die "Failed to install gcc in guest os"; return 1; }
    dnf list installed glibc-static || dnf install -y glibc-static || \
    { die "Failed to install glibc-static in guest os"; return 1; }
    make || { die "Failed to compile source code $1"; return 1; }
    if [ -f $2 ]; then
      chmod a+x $2
      cp $2 $GUEST_TEST_DIR
    else
      die "Can't find test binary $2"
      return 1
    fi
EOF
  ERR_NUM=$?
  if [ $ERR_NUM -eq 0 ]; then
    test_print_trc "Guest VM test source code and binary prepare complete"
    return 0
  else
    return 1
  fi
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
  ERR_NUM=$?
  if [ $ERR_NUM -eq 0 ]; then
    test_print_trc "Guest VM closed properly after test"
    return 0
  else
    return 1
  fi
}

###################### Do Works ######################
# exec only if script being executed
if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
  cd "$(dirname "$0")" 2>/dev/null || exit 1
  source ../.env

  # get test scenario config for test_executor
  echo SCRIPT_DIR="$SCRIPT_DIR" >> "$SCRIPT_DIR"/test_params.py
  source "$SCRIPT_DIR"/test_params.py

  cd "$SCRIPT_DIR" || die "fail to switch to $SCRIPT_DIR"
  # select specific "$FEATURE.test_executor.sh" by $FEATURE
  "$FEATURE"/"$FEATURE".test_executor.sh || \
  { die "Failed on $TESTCASE of $FEATURE"; return 1; }
fi
