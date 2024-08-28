#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation
# Author: Yi Lai <yi1.lai@intel.com>
# @Desc  Test script to verify Intel RAS error injection functionality

# Prerequisite
if ! rpm -q screen &> /dev/null; then
    echo "screen is not installed. Installing now..."
    sudo yum install -y screen
fi

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-t TESTCASE_ID] [-H]
  -t  TEST CASE ID
  -H  show this
__EOF
}

mce_check_result() {
  local testcase=$1

  if [ $2 -eq 0 ]; then
    test_print_trc "${testcase} Test PASS"
  else
    die "${testcase} Test FAIL"
  fi
}

load_edac_driver() {
  for i in $(find /lib/modules/$(uname -r) -type f | grep edac); do
    filename=${i##*/}
    edac_driver=${filename%.ko.xz}
    modprobe $edac_driver
  done
}

mce_test() {
  case $TEST_SCENARIO in
  apei-inj)
    load_edac_driver
    cd mce-test/cases/function/apei-inj/
    sh runtest.sh
    ;;
  core_recovery_ifu)
    cd mce-test/cases/function/core_recovery/
    sh runtest_ifu.sh
    ;;
  core_recovery_dcu)
    cd mce-test/cases/function/core_recovery/
    sh runtest_dcu.sh
    ;;
  edac)
    cd mce-test/cases/function/edac/
    sh runtest.sh
    ;;
  einj-ext)
    load_edac_driver
    cd mce-test/cases/function/einj-ext/
    sh runtest.sh
    ;;
  emca-inj)
    cd mce-test/cases/function/emca-inj/
    sh runtest.sh
    ;;
  erst-inject)
    cd mce-test/cases/function/erst-inject/
    sh runtest.sh
    ;;
  pfa)
    cd mce-test/cases/function/pfa/
    sh runtest.sh
    ;;
  esac
  mce_check_result $TEST_SCENARIO $?
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

mce_test
