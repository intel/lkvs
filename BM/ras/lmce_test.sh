#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation
# Author: Yi Lai <yi1.lai@intel.com>
# @Desc  Test script to verify Intel RAS LMCE functionality

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

# Check whether LMCE feature is supported
lmce_support_check() {
  local lmce_support=$(((0x$(rdmsr 0x3a) >> 20) & 1)) # 0x3a is IA32_FEATURE_CONTROL, bit 20 is LMCE_ON
  if [ $lmce_support -eq 1 ]; then
    test_print_trc "LMCE feature is supported"
  else
    die "LMCE feature is not supported"
  fi
}

lmce_check_result() {
  local testcase=$1

  if [[ $2 -eq 0 ]] && grep -q LMCE ${MCELOG_LOGFILE}; then
        test_print_trc "${testcase} Test PASS"
  else
    die "${testcase} Test FAIL"
  fi
}

lmce_test() {
  disable_cmci # disable MCE CMCI before LMCE test execution
  cat /dev/null > ${MCELOG_LOGFILE} # clear previous decoded MCE event records
  cd ras-tools/
  case $TEST_SCENARIO in
  sameaddr_samecore_instr/instr)
    ./lmce -a -c 1 -t INSTR/INSTR
    ;;
  sameaddr_samecore_instr/data)
    ./lmce -a -c 1 -t INSTR/DATA
    ;;
  sameaddr_samecore_data/data)
    ./lmce -a -c 1 -t DATA/DATA
    ;;
  sameaddr_samesocket_instr/instr)
    ./lmce -a -c 2 -t INSTR/INSTR
    ;;
  sameaddr_samesocket_instr/data)
    ./lmce -a -c 2 -t INSTR/DATA
    ;;
  sameaddr_samesocket_data/data)
    ./lmce -a -c 2 -t DATA/DATA
    ;;
  sameaddr_diffsocket_instr/instr)
    ./lmce -a -c 3 -t INSTR/INSTR
    ;;
  sameaddr_diffsocket_instr/data)
    ./lmce -a -c 3 -t INSTR/DATA
    ;;
  sameaddr_diffsocket_data/data)
    ./lmce -a -c 3 -t DATA/DATA
    ;;
  diffaddr_samecore_instr/instr)
    ./lmce -c 1 -t INSTR/INSTR
    ;;
  diffaddr_samecore_instr/data)
    ./lmce -c 1 -t INSTR/DATA
    ;;
  diffaddr_samecore_data/data)
    ./lmce -c 1 -t DATA/DATA
    ;;
  diffaddr_samesocket_instr/instr)
    ./lmce -c 2 -t INSTR/INSTR
    ;;
  diffaddr_samesocket_instr/data)
    ./lmce -c 2 -t INSTR/DATA
    ;;
  diffaddr_samesocket_data/data)
    ./lmce -c 2 -t DATA/DATA
    ;;
  diffaddr_diffsocket_instr/instr)
    ./lmce -c 3 -t INSTR/INSTR
    ;;
  diffaddr_diffsocket_instr/data)
    ./lmce -c 3 -t INSTR/DATA
    ;;
  diffddr_diffsocket_data/data)
    ./lmce -c 3 -t DATA/DATA
    ;;
  esac
  enable_cmci # restore ENV
  lmce_check_result $TEST_SCENARIO $?
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

lmce_support_check # check whether LMCE feature is supported
mcelog_config # configure mcelog service
lmce_test
