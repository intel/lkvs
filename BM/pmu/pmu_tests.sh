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

clear_files() {
  for i in "$@"; do
    [[ -f $i ]] && test_print_trc "Remove file: $i" && rm "$i"
  done;
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

bitmap_6_test() {
  search="Intel PMU"
  gbitmap=$(dmesg | grep -A 8  "$search" | grep "generic bitmap" | awk '{print $6}')
  fbitmap=$(dmesg | grep -A 8  "$search" | grep "fixed-purpose bitmap" | awk '{print $6}')
  [[ $gbitmap = "00000000000000ff" ]] || die "gbitmap = $gbitmap not expected!"
  [[ $fbitmap = "0000000000000077" ]] || die "fbitmap = $fbitmap not expected!"
}

umask2_cpuid_test() {
  ##EAX=023H, ECX=0, EBX=0=1
  do_cmd "cpuid_check 23 0 0 0 b 0"
}

zbit_cpuid_test() {
  ##EAX=023H, ECX=0, EBX=1=1
  do_cmd "cpuid_check 23 0 0 0 b 1"
}

umask2_test() {
  cputype='cpu'
  benchmark="sleep 1"
  perf_log="perf.log"
  clear_files $perf_log
  do_cmd "perf stat -e $cputype/event=0xd1,umask=0x0201,name=MEM_LOAD_RETIRED.L1_L2_HIT/ $benchmark >& $perf_log"
  counts=$(grep "MEM_LOAD_RETIRED" $perf_log | awk '{print $1}' | tr -cd "0-9")
  clear_files $perf_log
  [[ $counts != 0 ]] || die "$cputype counts not > 0!"
}

zbit_test() {
  cputype='cpu'
  benchmark="sleep 1"
  perf_log="perf.log"
  clear_files $perf_log
  do_cmd "perf stat -e $cputype/event=0x11,umask=0x10,cmask=1,eq=1,name=ITLB_MISSES.WALK_ACTIVE_1/ $benchmark >& $perf_log"
  clear_files $perf_log
}

counting_test() {
  cputype='cpu'
  benchmark="sleep 1"
  perf_log="perf.log"
  clear_files $perf_log
  do_cmd "perf stat -e $cputype/event=0x3c,umask=0x0,name=CYCLES/ \
    -e $cputype/event=0x73,umask=0x0,name=TOPDOWN_BAD_SPEC/ \
    -e $cputype/event=0x9c,umask=0x01,name=TOPDOWN_FE_BOUND/ \
    -e $cputype/event=0xc2,umask=0x02,name=TOPDOWN_RETIRING/ \
    -e $cputype/event=0xa4,umask=0x02,name=TOPDOWN_BE_BOUND/ $benchmark >& $perf_log"
  CYCLES=$(grep "CYCLES" $perf_log | awk '{print $1}')
  TOPDOWN_BAD_SPEC=$(grep "TOPDOWN_BAD_SPEC" $perf_log | awk '{print $1}')
  TOPDOWN_RETIRING=$(grep "TOPDOWN_RETIRING" $perf_log | awk '{print $1}')
  TOPDOWN_BE_BOUND=$(grep "TOPDOWN_BE_BOUND" $perf_log | awk '{print $1}')
  clear_files $perf_log
  [[ $CYCLES != 0 ]] || die "counts = 0 for CYCLES!"
  [[ $TOPDOWN_BAD_SPEC != 0 ]] || die "counts = 0 for TOPDOWN_BAD_SPEC!"
  [[ $TOPDOWN_RETIRING != 0 ]] || die "counts = 0 for TOPDOWN_RETIRING!"
  [[ $TOPDOWN_BE_BOUND != 0 ]] || die "counts = 0 for TOPDOWN_BE_BOUND!"
}

sampling_test() {
  e_topdown_bad_spec="topdown-bad-spec"
  e_topdown_fe_bound="topdown-fe-bound"
  e_topdown_retiring="topdown-retiring"
  e_topdown_be_bound="topdown-be-bound"
  benchmark="sleep 1"
  perf_log="perf.log"
  clear_files $perf_log
  do_cmd "perf record -e $e_topdown_bad_spec $benchmark >& $perf_log"
  samples=$(grep "sample" $perf_log | awk '{print $10}' | tr -cd "0-9")
  test_print_trc "$e_topdown_bad_spec sample = $samples"
  [[ $samples -eq 0 ]] && die "samples = 0 for $e_topdown_bad_spec!"

  do_cmd "perf record -e $e_topdown_fe_bound $benchmark >& $perf_log"
  samples=$(grep "sample" $perf_log | awk '{print $10}' | tr -cd "0-9")
  test_print_trc "$e_topdown_fe_bound sample = $samples"
  [[ $samples -eq 0 ]] && die "samples = 0 for $e_topdown_fe_bound!"

  do_cmd "perf record -e $e_topdown_retiring $benchmark >& $perf_log"
  samples=$(grep "sample" $perf_log | awk '{print $10}' | tr -cd "0-9")
  test_print_trc "$e_topdown_retiring sample = $samples"
  [[ $samples -eq 0 ]] && die "samples = 0 for $e_topdown_retiring!"

  do_cmd "perf record -e $e_topdown_be_bound $benchmark >& $perf_log"
  samples=$(grep "sample" $perf_log | awk '{print $10}' | tr -cd "0-9")
  clear_files $perf_log
  test_print_trc "$e_topdown_be_bound sample = $samples"
  [[ $samples -eq 0 ]] && die "samples = 0 for $e_topdown_be_bound!"

}

counting_multi_test() {
  cputype='cpu'
  benchmark="sleep 1"
  perf_log="perf.log"
  clear_files $perf_log
  do_cmd "perf stat -e '{$cputype/event=0x73,umask=0x0,name=TOPDOWN_BAD_SPEC/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_BAD_SPEC/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_BAD_SPEC/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_BAD_SPEC/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_BAD_SPEC/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_BAD_SPEC/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_BAD_SPEC/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_BAD_SPEC/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_BAD_SPEC/}' $benchmark >& $perf_log"
  counts=$(grep "TOPDOWN_BE_BOUND" $perf_log | awk '{print $1}')
  for count in $counts; do
    val=$(echo $count | tr -cd "0-9")
    [[ $val != 0 ]] || die "counts = 0 for TOPDOWN_BAD_SPEC!"
  done

  do_cmd "perf stat -e '{$cputype/event=0x73,umask=0x0,name=TOPDOWN_FE_BOUND/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_FE_BOUND/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_FE_BOUND/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_FE_BOUND/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_FE_BOUND/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_FE_BOUND/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_FE_BOUND/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_FE_BOUND/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_FE_BOUND/}' $benchmark >& $perf_log"
  counts=$(grep "TOPDOWN_FE_BOUND" $perf_log | awk '{print $1}')
  for count in $counts; do
    val=$(echo $count | tr -cd "0-9")
    [[ $val != 0 ]] || die "counts = 0 for TOPDOWN_FE_BOUND!"
  done

  do_cmd "perf stat -e '{$cputype/event=0x73,umask=0x0,name=TOPDOWN_BE_BOUND/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_BE_BOUND/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_BE_BOUND/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_BE_BOUND/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_BE_BOUND/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_BE_BOUND/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_BE_BOUND/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_BE_BOUND/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_BE_BOUND/}' $benchmark >& $perf_log"
  counts=$(grep "TOPDOWN_BE_BOUND" $perf_log | awk '{print $1}')
  for count in $counts; do
    val=$(echo $count | tr -cd "0-9")
    [[ $val != 0 ]] || die "counts = 0 for TOPDOWN_BE_BOUND!"
  done

  do_cmd "perf stat -e '{$cputype/event=0x73,umask=0x0,name=TOPDOWN_RETIRING/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_RETIRING/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_RETIRING/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_RETIRING/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_RETIRING/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_RETIRING/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_RETIRING/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_RETIRING/, \
    $cputype/event=0x73,umask=0x0,name=TOPDOWN_RETIRING/}' $benchmark >& $perf_log"
  counts=$(grep "TOPDOWN_RETIRING" $perf_log | awk '{print $1}')
  clear_files $perf_log
  for count in $counts; do
    val=$(echo $count | tr -cd "0-9")
    [[ $val != 0 ]] || die "counts = 0 for TOPDOWN_RETIRING!"
  done
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
    bitmap_6)
      bitmap_6_test
      ;;
    umask2_cpuid)
      umask2_cpuid_test
      ;;
    zbit_cpuid)
      zbit_cpuid_test
      ;;
    umask2)
      umask2_test
      ;;
    zbit)
      zbit_test
      ;;
    counting)
      counting_test
      ;;
    sampling)
      sampling_test
      ;;
    counting_multi)
      counting_multi_test
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
