#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation

# Author:   Ammy Yi <ammy.yi@intel.com>
#
# History:  26. Dec, 2022 - (Ammy Yi)Creation


# @desc This script verify pmu functional tests
# @returns Fail the test if return code is non-zero (value set not found)


cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env


: "${CASE_NAME:=""}"

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-t TESTCASE_ID] [-H]
  -t  TEST CASE ID
  -H  show this
__EOF
}

fix_counter_test() {
  # platform before ICL: uncore_cbox_0/clockticks/
  flag=0
  clockticks="uncore_cbox_0/clockticks/"
  logfile="temp.txt"

  if ! perf stat -e $clockticks -a -x, sleep 1 2> $logfile; then
    flag=$((flag + 1))
  else
    sync
    sync
    sleep 1
    value=$(cat $logfile)
    test_print_trc "value = $value"
    value=$(echo "$value" | cut -d "," -f 1)
    test_print_trc "value_2 = $value"
    if [[ $value -le 1000000 ]] || [[ $value -gt 10000000000 ]]; then
      die "Counters are not correct!"
    fi
  fi

  # platform after ICL: uncore_clock/clockticks
  clockticks="uncore_clock/clockticks/"
  logfile="temp.txt"
  if ! perf stat -e $clockticks -a -x, sleep 1 2> $logfile; then
    flag=$((flag + 1))
  else
    sync
    sync
    sleep 1
    value=$(cat $logfile)
    test_print_trc "value = $value"
    value=$(echo "$value" | cut -d "," -f 1)
    test_print_trc "value_2 = $value"
    if [[ $value -le 1000000 ]] || [[ $value -gt 10000000000 ]]; then
      die "Counters are not correct!"
    fi
  fi

  test_print_trc "flag = $flag"
  [[ $flag -eq 2 ]] && die "Fix counter is not working!"

}

basic_test() {
  do_cmd "dmesg | grep 'Intel PMU driver'"
  should_fail "dmesg | grep 'generic architected perfmon'"
}

pmu_test() {
  echo "$WATCHDOG" > /proc/sys/kernel/nmi_watchdog
  value=$(cat /proc/sys/kernel/nmi_watchdog)
  test_print_trc "nmi_watchdog = $value"
  case $TEST_SCENARIO in
    fix_counter)
      fix_counter_test
      ;;
    basic)
      basic_test      
      ;;
    uncore)
      do_cmd "ls /sys/devices/ | grep uncore"
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

pmu_test
# Call teardown for passing case
exec_teardown
