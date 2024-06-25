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
#  should_fail "dmesg | grep 'generic architected perfmon'"
}

lbr_events_cpuid_test() {
  #CPUID leaf 0x1c  ECX (19:16) must be all 1 for SRF.
  for((i=16;i<=19;i++)); do
    do_cmd "cpuid_check 1c 0 0 0 c $i"
  done
}

lbr_events_s_test() {
  perfdata="perf.data"
  logfile="temp.txt"
  do_cmd "perf record -o $perfdata -e "{branch-instructions,branch-misses}:S" -j any,counter sleep 1 >& $logfile"
  sample_count=$(grep "sample" $logfile| awk '{print $10}' | tr -cd "0-9")
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  val=$(perf report -D -i $perfdata | grep -c "branch stack counters")
  [[ $val -eq 0 ]] && die "branch stack counters val = 0!"
  lbr_vals=$(perf report -D -i $perfdata | grep "branch stack counters" | awk '{print $5}')
  for lbr_val in $lbr_vals; do
    temp=$(echo "$lbr_val" | cut -d ":" -f 2)
    test_print_trc "counts=$temp, lbr_val=$lbr_val!"
    [[ $temp -eq 0 ]] && die "branch stack counters = 0!"
  done
}

lbr_events_all_test() {
  perfdata="perf.data"
  logfile="temp.txt"
  do_cmd "perf record -o $perfdata -e "{cpu/branch-instructions,branch_type=any/, cpu/branch-misses,branch_type=counter/}" sleep 1 >& $logfile"
  sample_count=$(grep "sample" $logfile| awk '{print $10}' | tr -cd "0-9")
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  val=$(perf report -D -i $perfdata | grep -c "branch stack counters")
  [[ $val -eq 0 ]] && die "branch stack counters val = 0!"
  lbr_vals=$(perf report -D -i $perfdata | grep "branch stack counters" | awk '{print $5}')
  for lbr_val in $lbr_vals; do
    temp=$(echo "$lbr_val" | cut -d ":" -f 2)
    test_print_trc "counts=$temp, lbr_val=$lbr_val!"
    [[ $temp -eq 0 ]] && die "branch stack counters = 0!"
  done 
}

timed_pebs_msr_test() {
  #MSR_IA32_PERF_CAPABILITIES(0x345) bit 17 for Timed PEBs
  bit_17=$(rdmsr 0x345 -f 17:17)
  test_print_trc "MSR IA32_PERF_CAPABILITIES(0x345) bit 17 is: $bit_17"
  [[ $bit_17 -eq 1 ]] || die "Timed PEBS msr bit is not set!"
}

uncore_events_test() {
  uncore_events=$(perf list | grep uncore | grep PMU | awk '{print $1}')    
  for uncore_event in $uncore_events; do
    test_print_trc "uncore_event=$uncore_event"
    do_cmd "perf stat -e $uncore_event sleep 1"
  done
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
    lbr_events_cpuid)
      lbr_events_cpuid_test
      ;;
    lbr_events_s)
      lbr_events_s_test
      ;;
    lbr_events_all)
      lbr_events_all_test
      ;;
    timed_pebs_msr)
      timed_pebs_msr_test
      ;;
    uncore_events)
      uncore_events_test
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
