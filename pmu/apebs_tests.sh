#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation

# Author:   Ammy Yi <ammy.yi@intel.com>
#
# History:  26. Dec, 2022 - (Ammy Yi)Creation


# @desc This script verify pmu adaptive PEBS functional tests
# @returns Fail the test if return code is non-zero (value set not found)

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env


: "${CASE_NAME:=""}"
: "${WATCHDOG:=0}"
: "${RAWFILE:="perf.data"}"

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-t TESTCASE_ID] [-H]
  -t  TEST CASE ID
  -H  show this
__EOF
}

lbr_test() {
  level=$1
  perfdata="pebs.data"
  logfile="temp.txt"
  perf record -o "$perfdata" -b -e cycles:"$level" -a sleep 1 2> "$logfile"
  sample_count=$(grep "sample" $logfile | awk '{print $10}' | tr -cd "0-9")
  lbr_count=$(perf report -D -i $perfdata| grep -c "branch stack")
  test_print_trc "sample_count = $sample_count; lbr_count = $lbr_count"
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  [[ $sample_count -eq $lbr_count ]] || die "samples does not match!"
}

lbr_test() {
  level=$1
  perfdata="pebs.data"
  logfile="temp.txt"
  perf record -o "$perfdata" -b -e cycles:"$level" -a sleep 1 2> "$logfile"
  sample_count=$(grep "sample" $logfile | awk '{print $10}' | tr -cd "0-9")
  count=$(perf report -D -i $perfdata| grep -c "branch stack")
  test_print_trc "sample_count = $sample_count; count = $count"
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  [[ $sample_count -eq $count ]] || die "samples does not match!"
}

xmm_test() {
  level=$1
  perfdata="pebs.data"
  logfile="temp.txt"
  perf record -o "$perfdata" -IXMM0 -e cycles:"$level" -a sleep 1 2> "$logfile"
  sample_count=$(grep "sample" $logfile | awk '{print $10}' | tr -cd "0-9")
  count=$(perf report -D -i $perfdata| grep -c "XMM0")
  test_print_trc "before sample_count = $sample_count; count = $count"
  sample_count=$((sample_count * 2))
  test_print_trc "after sample_count = $sample_count; count = $count"
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  [[ $sample_count -eq $count ]] || die "samples does not match!"
}

ip_test() {
  level=$1
  perfdata="pebs.data"
  logfile="temp.txt"
  task="mem-loads"
  model=$(grep model /proc/cpuinfo | awk '{print $3}' | head -1)
  [[ $model -eq 150 ]] && task="cycles"
  [[ $model -eq 156 ]] && task="cycles"
  test_print_trc "task=$task"
  perf mem record -o "$perfdata"  -t load -a sleep 1 2> "$logfile"
  sample_count=$(grep "sample" $logfile | awk '{print $10}' | tr -cd "0-9")
  count=$(perf report -D -i $perfdata| grep -c "data_src")
  test_print_trc "sample_count = $sample_count; count = $count"
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  [[ $sample_count -eq $count ]] || die "samples does not match!"
}

data_src_test() {
  level=$1
  perfdata="pebs.data"
  logfile="temp.txt"
  perf record -o "$perfdata" -b -e cycles:"$level" -d -a sleep 1 2> "$logfile"
  sync
  sync
  sleep 1
  sample_count=$(grep "sample" $logfile | awk '{print $10}' | tr -cd "0-9")
  count=$(perf report -D -i $perfdata| grep -c "data_src")
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  [[ $sample_count -eq $count ]] || die "samples does not match!"
}

apebs_test() {
  echo $WATCHDOG > /proc/sys/kernel/nmi_watchdog
  wd_value=$(cat /proc/sys/kernel/nmi_watchdog)
  test_print_trc "nmi_watchdog = $wd_value"
  case $TEST_SCENARIO in
    lbr_1)
      lbr_test p
      ;;
    lbr_2)
      lbr_test P
      ;;
    xmm_1)
      xmm_test p
      ;;
    xmm_2)
      xmm_test P
      ;;
    ip_1)
      ip_test p
      ;;
    ip_2)
      ip_test P
      ;;
    data_src)
      data_src_test p
      ;;
    esac
  return 0
}

while getopts :t:w:H arg; do
  case $arg in
    t)
      TEST_SCENARIO=$OPTARG
      ;;
    w)
      WATCHDOG=$OPTARG
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

apebs_test
# Call teardown for passing case
exec_teardown
