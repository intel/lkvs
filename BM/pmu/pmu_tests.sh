#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation

# Author:   Ammy Yi <ammy.yi@intel.com>
#
# History:  26. Dec, 2022 - (Ammy Yi)Creation
#           Nov 2024 Wendy Wang Updated


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
    sync && sleep 1
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
    sync && sleep 1
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

# Basic test: Verify if Intel PMU driver is loaded
basic_test() {
  do_cmd "dmesg | grep 'Intel PMU driver'"
}

uncore_dmesg_check() {
  # Uncore is failed when there is following dmesg:
  # “Invalid address is detected for uncore type %d box %d, Disable the uncore unit.”
  # “A spurious uncore type %d is detected, Disable the uncore type.”
  # “Duplicate uncore type %d box ID %d is detected, Drop the duplicate uncore unit.”
  should_fail "dmesg | grep 'Disable the uncore'"
  should_fail "dmesg | grep 'Drop the duplicate uncore unit'"
  should_fail "dmesg | grep 'Invalid address is detected for uncore type'"
}

# CPUID test for Last Branch Record events
lbr_events_cpuid_test() {
  #CPUID leaf 0x1c  ECX (19:16) must be all 1 for SRF.
  for((i=16;i<=19;i++)); do
    do_cmd "cpuid_check 1c 0 0 0 c $i"
  done
}

# Last Branch Record event sample test with "S" option
# :S means sample
lbr_events_s_test() {
  perfdata="perf.data"
  logfile="temp.txt"
  perf record -o $perfdata -e "{branch-instructions,branch-misses}:S" -j any,counter sleep 1 >& $logfile
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

# Test for all Last Branch Record events
lbr_events_all_test() {
  perfdata="perf.data"
  logfile="temp.txt"
  perf record -o $perfdata -e "{cpu/branch-instructions,branch_type=any/, cpu/branch-misses,branch_type=counter/}" sleep 1 >& $logfile
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

# Test for timed Precise Event Based Sampling(PEBS) MSR capability
timed_pebs_msr_test() {
  #MSR_IA32_PERF_CAPABILITIES(0x345) bit 17 for Timed PEBs
  bit_17=$(rdmsr 0x345 -f 17:17)
  test_print_trc "MSR IA32_PERF_CAPABILITIES(0x345) bit 17 is: $bit_17"
  [[ $bit_17 -eq 1 ]] || die "Timed PEBS msr bit is not set!"
}

# Test Uncore Events
uncore_events_test() {
  uncore_events=$(perf list | grep uncore | grep PMU | awk '{print $1}')    
  for uncore_event in $uncore_events; do
    test_print_trc "uncore_event=$uncore_event"
    do_cmd "perf stat -e $uncore_event sleep 1"
  done
}

arch_pebs_cpuid_test() {
  ##CPUID.0x23.0.EAX[5] == 1
  do_cmd "cpuid_check 23 0 0 0 a 5"

  ## For PTL
  ## CPUID.0x23.0.EAX[5:4] == 0x3
  model=$(< /proc/cpuinfo grep mode | awk '{print $3}' | awk 'NR==1')
  [[ $model -eq 204 ]] && do_cmd "cpuid_check 23 0 0 0 a 4"
}

reg_group_test(){
  reg=$1
  perfdata="pebs.data"
  logfile="temp.txt"
  event="cycles:$level"
  test_print_trc "Will test with $reg now!"
  perf record -o $perfdata -I$reg -e $event -a sleep 1 2>&1|tee $logfile
  sample_count=$(grep "sample" $logfile | awk '{print $10}' | tr -cd "0-9")
  count=$(perf report -D -i $perfdata| grep -v events | grep -c "\. $reg" )
  test_print_trc "before sample_count = $sample_count; count = $count"
  sample_count=$((sample_count))
  test_print_trc "after sample_count = $sample_count; count = $count"
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  [[ $sample_count -eq $count ]] || die "samples does not match!"
}

reg_group_test_more_option(){
  reg=$1
  reg_v=$2
  times=$3
  perfdata="pebs.data"
  logfile="temp.txt"
  event="cycles:$level"
  test_print_trc "Will test with $reg with $reg_v $times now!"
  perf record -o $perfdata -I$reg -e $event -a sleep 1 2>&1|tee $logfile
  sample_count=$(grep "sample" $logfile | awk '{print $10}' | tr -cd "0-9")
  count=$(perf report -D -i $perfdata| grep -v events | grep -c "\. $reg_v" )
  test_print_trc "before sample_count = $sample_count; count = $count"
  sample_count=$((sample_count * times))
  test_print_trc "after sample_count = $sample_count; count = $count"
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  [[ $sample_count -eq $count ]] || die "samples does not match!"
}

arch_pebs_gp_reg_group_test() {
  ##CPUID.0x23.4.EBX.GPR[29] == 1
  do_cmd "cpuid_check 23 0 4 0 b 29"
  level="p"
  reg_group_test "AX"
  reg_group_test "BX"
  reg_group_test "CX"
  reg_group_test "DX"
  reg_group_test "SI"
  reg_group_test "DI"
  reg_group_test "BP"
  reg_group_test "SP"
  reg_group_test "IP"
  reg_group_test "FLAGS"
  reg_group_test "CS"
  reg_group_test "SS"
#  reg_group_test "DS"
#  reg_group_test "ES"
#  reg_group_test "FS"
#  reg_group_test "GS"
  reg_group_test "R8" 
}

arch_pebs_xer_group_test() {
  level="p"
#  reg_group_test_more_option "OPMASK0" "opmask0" 1
  reg_group_test_more_option "YMMH0" "YMMH0" 2
#  reg_group_test_more_option "ZMMH0" "ZMMLH0" 4
}

arch_pebs_counter_group_test() {
  perfdata="pebs.data"
  logfile="temp.txt"
  perfdata_s="pebs_s.data"
  logfile_s="temp_s.txt"
  mode=$(< /proc/cpuinfo grep mode | awk '{print $3}' | awk 'NR==1')
  case $mode in
    221)
      perf record -o $perfdata_s -e '{cycles:p,cache-misses,cache-references,topdown-bad-spec,topdown-fe-bound,topdown-retiring}:S' -- sleep 1 2>&1|tee $logfile_s
      perf record -o $perfdata -e '{cycles,cache-misses,cache-references,topdown-bad-spec,topdown-fe-bound,topdown-retiring}:p' -- sleep 1 2>&1|tee $logfile
      ;;
    1)
    # Topdown events don't rely on real counter and they are caculated from perf metrics MSR. Could not sample with P core on DMR.
      perf record -o $perfdata_s -e '{slots,cache-misses,cache-references,branches,branches-misses}:S' -- sleep 1 2>&1|tee $logfile_s
      perf record -o $perfdata -e '{slots,cache-misses,cache-references,branches,branch-misses}:p' -- sleep 1 2>&1|tee $logfile      
      ;;
  esac
  sample_count=$(grep "sample" $logfile_s | awk '{print $10}' | tr -cd "0-9")
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  sample_count=$(grep "sample" $logfile | awk '{print $10}' | tr -cd "0-9")
  count=$(perf report -D -i $perfdata| grep -c "PERF_RECORD_SAMPLE")
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  [[ $sample_count -eq $count ]] || die "samples does not match!"
}

arch_pebs_counter_group_stress_test() {
  perfdata="pebs.data"
  logfile="temp.txt"
  #because nmi_watchdog will occupy one fix counter, so disable it
  echo 0 > /proc/sys/kernel/nmi_watchdog
  event="{branches,branches,branches,branches,branches,branches,branches,branches,cycles,instructions,ref-cycles,topdown-bad-spec,topdown-fe-bound,topdown-retiring"
  perf record -o $perfdata -e "$event:p" -a -- sleep 1 2>&1|tee $logfile
  sample_count=$(grep "sample" $logfile | awk '{print $10}' | tr -cd "0-9")
  count=$(perf report -D -i $perfdata| grep -c "PERF_RECORD_SAMPLE")
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  [[ $sample_count -eq $count ]] || die "samples does not match!"
}

arch_pebs_gp_counter_test() {
  event="branches:p"
  perfdata="pebs.data"
  logfile="temp.txt" 
  perf record -o $perfdata -e $event -a sleep 1 2>&1|tee $logfile
  sample_count=$(grep "sample" $logfile| awk '{print $10}' | tr -cd "0-9")
  count=$(perf report -D -i $perfdata| grep -c "PERF_RECORD_SAMPLE")
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  [[ $sample_count -eq $count ]] || die "samples does not match!" 
}

arch_pebs_basic_group_test() {
  event="cycles:pp"
  perfdata="pebs.data"
  logfile="temp.txt" 
  perf record -o $perfdata -e $event -a sleep 1 2>&1|tee $logfile
  sample_count=$(grep "sample" $logfile | awk '{print $10}' | tr -cd "0-9")
  count=$(perf report -D -i $perfdata| grep -c "PERF_RECORD_SAMPLE")
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  [[ $sample_count -eq $count ]] || die "samples does not match!" 
}

pmu_test() {
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
    uncore_dmesg)
      uncore_dmesg_check
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
    arch_pebs_cpuid)
      arch_pebs_cpuid_test
      ;;
    arch_pebs_gp_reg_group)
      arch_pebs_gp_reg_group_test
      ;;
    arch_pebs_xer_group)
      arch_pebs_xer_group_test
      ;;
    arch_pebs_counter_group)
      arch_pebs_counter_group_test
      ;;
    arch_pebs_counter_group_stres)
      arch_pebs_counter_group_stress_test
      ;;
    arch_pebs_gp_counter)
      arch_pebs_gp_counter_test
      ;;
    arch_pebs_basic_group)
      arch_pebs_basic_group_test
      ;;
    esac
  return 0
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

pmu_test "$@"
# Call teardown for passing case
exec_teardown
