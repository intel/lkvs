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
  usage: ./${0##*/} [-t TESTCASE_ID] [-l LOOP_TIMES] [-H]
  -t  TEST CASE ID
  -l  stress loop times, default 10 (for acr_stress)
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
    clear_files $logfile
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
    clear_files $logfile
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
  if [[ $sample_count -eq 0 ]]; then
    clear_files $logfile $perfdata
    die "samples = 0!"
  fi
  val=$(perf report -D -i $perfdata | grep -c "branch stack counters")
  if [[ $val -eq 0 ]]; then
    clear_files $logfile $perfdata
    die "branch stack counters val = 0!"
  fi
  lbr_vals=$(perf report -D -i $perfdata | grep "branch stack counters" | awk '{print $5}')
  clear_files $logfile $perfdata
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
  if [[ $sample_count -eq 0 ]]; then
    clear_files $logfile $perfdata
    die "samples = 0!"
  fi
  val=$(perf report -D -i $perfdata | grep -c "branch stack counters")
  if [[ $val -eq 0 ]]; then
    clear_files $logfile $perfdata
    die "branch stack counters val = 0!"
  fi
  lbr_vals=$(perf report -D -i $perfdata | grep "branch stack counters" | awk '{print $5}')
  clear_files $logfile $perfdata
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
  clear_files $logfile $perfdata
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
  clear_files $logfile $perfdata
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
  simdfile="simd.txt"
  do_cmd "perf record -I? 2>&1|tee $simdfile"
  if grep 'YMM0-15' $simdfile > /dev/null; then
    # All 16 YMM registers are recorded, so 4*16=64
    reg_group_test_more_option "YMM" "YMM" 64
    clear_files $simdfile
  else
    clear_files $simdfile
    die "SIMD sampling format is incorrect!"
  fi
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
  #[[ $sample_count -eq 0 ]] && die "samples = 0!"
  if [[ $sample_count -eq 0 ]]; then
    clear_files $logfile $perfdata $perfdata_s $logfile_s
    die "samples = 0!"
  fi
  sample_count=$(grep "sample" $logfile | awk '{print $10}' | tr -cd "0-9")
  count=$(perf report -D -i $perfdata| grep -c "PERF_RECORD_SAMPLE")
  clear_files $logfile $perfdata $perfdata_s $logfile_s
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  [[ $sample_count -eq $count ]] || die "samples does not match!"
}

arch_pebs_counter_group_stress_test() {
  perfdata="pebs.data"
  logfile="temp.txt"
  #because nmi_watchdog will occupy one fix counter, so disable it
  echo 0 > /proc/sys/kernel/nmi_watchdog
  event="{branches,branches,branches,branches,branches,branches,branches,branches,cycles,instructions,ref-cycles,topdown-bad-spec,topdown-fe-bound,topdown-retiring}"
  perf record -o $perfdata -e "$event:p" -a -- sleep 1 2>&1|tee $logfile
  if grep "Error" $logfile > /dev/null; then
    clear_files $logfile $perfdata
    die "Sampling some events failed!"
  fi
  sample_count=$(grep "sample" $logfile | awk '{print $10}' | tr -cd "0-9")
  count=$(perf report -D -i $perfdata| grep -c "PERF_RECORD_SAMPLE")
  clear_files $logfile $perfdata
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
  clear_files $logfile $perfdata
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
  clear_files $logfile $perfdata
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
  perfdata="perf.data"
  perf_log="perf.log"
  clear_files $perf_log
  do_cmd "perf record -o $perfdata -e $e_topdown_bad_spec $benchmark >& $perf_log"
  samples=$(perf report -D -i perf.data |grep -A 1 $e_topdown_bad_spec |grep -i "sample" | awk '{print $3}' | tr -cd "0-9")
  clear_files $perf_log $perfdata
  test_print_trc "$e_topdown_bad_spec sample = $samples"
  [[ $samples -eq 0 ]] && die "samples = 0 for $e_topdown_bad_spec!"

  do_cmd "perf record -o $perfdata -e $e_topdown_fe_bound $benchmark >& $perf_log"
  samples=$(perf report -D -i perf.data |grep -A 1 $e_topdown_fe_bound |grep -i "sample" | awk '{print $3}' | tr -cd "0-9")
  clear_files $perf_log $perfdata
  test_print_trc "$e_topdown_fe_bound sample = $samples"
  [[ $samples -eq 0 ]] && die "samples = 0 for $e_topdown_fe_bound!"

  do_cmd "perf record -o $perfdata -e $e_topdown_retiring $benchmark >& $perf_log"
  samples=$(perf report -D -i perf.data |grep -A 1 $e_topdown_retiring |grep -i "sample" | awk '{print $3}' | tr -cd "0-9")
  clear_files $perf_log $perfdata
  test_print_trc "$e_topdown_retiring sample = $samples"
  [[ $samples -eq 0 ]] && die "samples = 0 for $e_topdown_retiring!"

  do_cmd "perf record -o $perfdata -e $e_topdown_be_bound $benchmark >& $perf_log"
  samples=$(perf report -D -i perf.data |grep -A 1 $e_topdown_be_bound |grep -i "sample" | awk '{print $3}' | tr -cd "0-9")
  clear_files $perf_log $perfdata
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

rdpmc_user_disable() {
  local logfile1="temp1.log"
  local logfile2="temp2.log"
  local logfile3="temp3.log"
  local logfile4="temp4.log"
  #23H.00H:EBX[2]: RDPMC_USR_DISABLE
  do_cmd "cpuid_check 23 0 0 0 b 2"

  rdpmc_attr=$1
  echo $rdpmc_attr > /sys/devices/cpu/rdpmc

  clear_files $logfile1 $logfile2 $logfile3 $logfile4
  [ -f rdpmc_user_disable_test ] || die "please compile rdpmc_user_disable_test firstly "
  rdpmc_user_disable_test 0 system gp > $logfile1
  rdpmc_user_disable_test 0 system fixed > $logfile2
  rdpmc_user_disable_test 0 process gp > $logfile3
  rdpmc_user_disable_test 0 process fixed > $logfile4
  case $rdpmc_attr in
    0)
      for file in $logfile1 $logfile2 $logfile3 $logfile4;
      do
        if ! cat $file | grep "Receive and handle #GP fault"; then
          die "rdpmc user disable test fail with rdpmc 0"
        fi
        clear_files $file
      done
      ;;
    1)
      for file in $logfile1 $logfile2;
      do
        num=$(cat $file | awk '{print $NF}')
        clear_files $file
        [ $num -eq 0 ] || die "rdpmc user disable test fail with rdpmc 1"
      done

      for file in $logfile3 $logfile4;
      do
        num=$(cat $file | awk '{print $NF}')
        clear_files $file
        [ $num -gt 0 ] || die "rdpmc user disable test fail with rdpmc 1"
      done
      ;;
    2)
      for file in $logfile1 $logfile2 $logfile3 $logfile4;
      do
        num=$(cat $file | awk '{print $NF}')
        clear_files $file
        [ $num -gt 0 ] || die "rdpmc user disable test fail with rdpmc 2"
      done
      ;;
  esac
}

# ACR (Auto Counter Reload) test functions
acr_detect_pmu() {
  local pmu
  for pmu in cpu cpu_core cpu_atom; do
    if [[ -f /sys/devices/${pmu}/format/acr_mask ]]; then
      ACR_PMU=$pmu
      return 0
    fi
  done
  return 1
}

acr_cpuid_test() {
  # 07H.01H:EAX[8] ArchPerfMonExt should be set first
  do_cmd "cpuid_check 7 0 1 0 a 8"
  # ACR CPUID
  do_cmd "cpuid_check 23 0 0 0 a 2"
}

acr_format_test() {
  local cputype=$1
  if [[ -z $cputype ]]; then
    acr_detect_pmu || die "No PMU exposes acr_mask, platform may not support ACR"
    cputype=$ACR_PMU
  fi
  do_cmd "test -f /sys/devices/${cputype}/format/acr_mask"
}

acr_basic_test() {
  local cputype=$1
  local perfdata="acr_basic.data"
  local logfile="acr_basic.log"
  local scriptlog="acr_basic_script.log"
  local cpunums=""

  if [[ -z $cputype ]]; then
    acr_detect_pmu || die "No PMU exposes acr_mask, skip ACR basic"
    cputype=$ACR_PMU
  fi

  [[ $cputype != "cpu" ]] && cpunums=$(cat /sys/devices/${cputype}/cpus)
  clear_files $perfdata $logfile $scriptlog

  if [[ -n $cpunums ]]; then
    perf record -o $perfdata \
      -e "{${cputype}/instructions,period=200000,acr_mask=0x2/,${cputype}/cycles,period=100000,acr_mask=0x3/}" \
      -a taskset -c $cpunums sleep 1 >& $logfile
  else
    perf record -o $perfdata \
      -e "{${cputype}/instructions,period=200000,acr_mask=0x2/,${cputype}/cycles,period=100000,acr_mask=0x3/}" \
      -a sleep 1 >& $logfile
  fi

  sample_count=$(grep "sample" $logfile | awk '{print $10}' | tr -cd "0-9")
  [[ -n $sample_count && $sample_count -gt 0 ]] || die "ACR basic: samples = 0!"

  perf script -i $perfdata > $scriptlog 2>&1
  instr_count=$(grep -c "instructions" $scriptlog)
  cycles_count=$(grep -c "cycles" $scriptlog)
  [[ $instr_count -gt 0 ]] || die "ACR basic: no instructions samples in perf script output!"
  [[ $cycles_count -eq 0 ]] || die "ACR basic: cycles should not produce samples, found $cycles_count!"

  clear_files $perfdata $logfile $scriptlog
}

acr_ratio_to_prev_test() {
  local cputype=$1
  local perfdata="acr_ratio.data"
  local logfile="acr_ratio.log"
  local scriptlog="acr_ratio_script.log"
  local cpunums=""

  if [[ -z $cputype ]]; then
    acr_detect_pmu || die "No PMU exposes acr_mask, skip ratio-to-prev"
    cputype=$ACR_PMU
  fi

  [[ $cputype != "cpu" ]] && cpunums=$(cat /sys/devices/${cputype}/cpus)
  clear_files $perfdata $logfile $scriptlog

  if [[ -n $cpunums ]]; then
    perf record -o $perfdata \
      -e "{${cputype}/instructions/,${cputype}/cycles,period=100000,ratio-to-prev=0.5/}" \
      -a taskset -c $cpunums sleep 1 >& $logfile
  else
    perf record -o $perfdata \
      -e "{${cputype}/instructions/,${cputype}/cycles,period=100000,ratio-to-prev=0.5/}" \
      -a sleep 1 >& $logfile
  fi

  sample_count=$(grep "sample" $logfile | awk '{print $10}' | tr -cd "0-9")
  [[ -n $sample_count && $sample_count -gt 0 ]] || die "ACR ratio-to-prev: samples = 0!"

  perf script -i $perfdata > $scriptlog 2>&1
  instr_count=$(grep -c "instructions" $scriptlog)
  cycles_count=$(grep -c "cycles" $scriptlog)
  [[ $instr_count -gt 0 ]] || die "ACR ratio-to-prev: no instructions samples in perf script output!"
  [[ $cycles_count -eq 0 ]] || die "ACR ratio-to-prev: cycles should not produce samples, found $cycles_count!"

  clear_files $perfdata $logfile $scriptlog
}

acr_stat_test() {
  local cputype=$1
  local logfile="acr_stat.log"

  if [[ -z $cputype ]]; then
    acr_detect_pmu || die "No PMU exposes acr_mask, skip ACR stat"
    cputype=$ACR_PMU
  fi

  clear_files $logfile
  perf stat -e "{${cputype}/instructions,period=200000,acr_mask=0x2/,${cputype}/cycles,period=100000,acr_mask=0x3/}" \
    -a sleep 1 >& $logfile
  clear_files $logfile
}

acr_reject_freq_test() {
  local cputype
  acr_detect_pmu || die "No PMU exposes acr_mask, skip ACR reject freq"
  cputype=$ACR_PMU

  should_fail "perf record -o /dev/null -e '{${cputype}/instructions,acr_mask=0x2/,${cputype}/cycles,acr_mask=0x3/}' -F 1000 -a true 2>/dev/null"
}

acr_reject_ppp_test() {
  local cputype
  acr_detect_pmu || die "No PMU exposes acr_mask, skip ACR reject ppp"
  cputype=$ACR_PMU

  should_fail "perf record -o /dev/null -e '{${cputype}/instructions,period=200000,acr_mask=0x2/ppp,${cputype}/cycles,period=100000,acr_mask=0x3/}' -a true 2>/dev/null"
}

acr_reject_contiguity_test() {
  local cputype
  acr_detect_pmu || die "No PMU exposes acr_mask, skip ACR reject contiguity"
  cputype=$ACR_PMU

  should_fail "perf record -o /dev/null -e '{${cputype}/instructions,period=200000,acr_mask=0x2/,dummy,${cputype}/cycles,period=100000,acr_mask=0x3/}' -a true 2>/dev/null"
}

acr_stress_test() {
  local cputype=$1
  : "${STRESS_TIMES:=10}"
  for ((i = 0; i < STRESS_TIMES; i++)); do
    acr_basic_test "$cputype"
    acr_ratio_to_prev_test "$cputype"
    acr_stat_test "$cputype"
  done
}

acr_run_on_supported_pmus() {
  local fn=$1
  local has_hybrid=0

  if [[ -f /sys/devices/cpu_atom/format/acr_mask ]]; then
    has_hybrid=1
    $fn "cpu_atom"
  fi
  if [[ -f /sys/devices/cpu_core/format/acr_mask ]]; then
    has_hybrid=1
    $fn "cpu_core"
  fi

  [[ $has_hybrid -eq 1 ]] && return 0
  $fn
}

get_pebs_mrt_workload() {
  local benchmark src

  src="$(pwd)/pebs_mrt_workload.c"
  benchmark="$(pwd)/pebs_mrt_workload"
  [[ -f "$src" ]] || die "workload source $src does not exist!"
  if [[ ! -x "$benchmark" || "$src" -nt "$benchmark" ]]; then
    gcc -O2 -pthread -o "$benchmark" "$src" || die "failed to build $benchmark"
  fi
  [[ -x "$benchmark" ]] || die "benchmark $benchmark does not exist!"
  echo "$benchmark"
}

find_first_online_cpu() {
  local cpu_dir cpu

  for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
    cpu=${cpu_dir##*cpu}
    if [[ -f "$cpu_dir/online" ]] && [[ $(cat "$cpu_dir/online") -ne 1 ]]; then
      continue
    fi
    echo "$cpu"
    return 0
  done

  die "No online CPU found!"
}

list_cross_core_worker_cpus() {
  local reader_cpu=$1
  local reader_dir="/sys/devices/system/cpu/cpu${reader_cpu}"
  local reader_core reader_pkg cpu_dir cpu core_id pkg_id workers=""

  [[ -d "$reader_dir" ]] || die "reader CPU $reader_cpu is not present!"
  reader_core=$(cat "$reader_dir/topology/core_id")
  reader_pkg=$(cat "$reader_dir/topology/physical_package_id")
  for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
    cpu=${cpu_dir##*cpu}
    [[ "$cpu" == "$reader_cpu" ]] && continue
    if [[ -f "$cpu_dir/online" ]] && [[ $(cat "$cpu_dir/online") -ne 1 ]]; then
      continue
    fi
    core_id=$(cat "$cpu_dir/topology/core_id")
    pkg_id=$(cat "$cpu_dir/topology/physical_package_id")
    if [[ "$pkg_id" == "$reader_pkg" && "$core_id" != "$reader_core" ]]; then
      workers+="$cpu "
    fi
  done

  [[ -n "$workers" ]] || die "No online cross-core CPU pair found!"
  echo "$workers"
}

pebs_mrt_local_ram_test() {
  local perfdata="pebs_mrt_local_ram.data"
  local perfdump="pebs_mrt_local_ram.dump"
  local logfile="pebs_mrt_local_ram.log"
  local benchmark sample_count local_ram_count

  benchmark=$(get_pebs_mrt_workload)
  clear_files "$perfdata" "$perfdump" "$logfile"
  do_cmd "perf record -d -o $perfdata -C 0 -c 200 -e '{cpu/event=0x03,umask=0x82/,cpu/mem-loads,ldlat=3/}:P' -- $benchmark -m local-ram -r 0 -i 200000 2>&1|tee $logfile"
  sample_count=$(grep "sample" "$logfile" | awk '{print $10}' | tr -cd "0-9")
  [[ -n "$sample_count" ]] || die "No samples found in $logfile!"
  perf report --stdio -D -i "$perfdata" > "$perfdump"
  local_ram_count=$(python3 - "$perfdump" <<'PY'
import sys
count = 0
for line in open(sys.argv[1], errors='ignore'):
    if 'data_src:' not in line:
        continue
    value = int(line.split()[-1], 16)
    if not (value & 0x2):
        continue
    region = (value >> 46) & 0x1f
    lvl_num = (value >> 33) & 0xf
    remote = (value >> 37) & 0x1
    if 0x8 <= region <= 0xf and lvl_num == 0xd and remote == 0:
        count += 1
print(count)
PY
) || die "failed to decode perf data_src values"
  test_print_trc "sample_count=$sample_count local_ram_count=$local_ram_count"
  [[ $sample_count -gt 0 ]] || die "samples = 0!"
  [[ $local_ram_count -gt 0 ]] || die "no local RAM memory-region samples found!"
  clear_files "$perfdata" "$perfdump" "$logfile"
}

pebs_mrt_snoop_hit_test() {
  local perfdata="pebs_mrt_snoop_hit.data"
  local perfdump="pebs_mrt_snoop_hit.dump"
  local logfile="pebs_mrt_snoop_hit.log"
  local benchmark sample_count reader_cpu worker_cpu worker_cpus
  local snoop_na_count snoop_miss_count snoop_hit_count snoop_hitm_count snoop_none_count

  reader_cpu=$(find_first_online_cpu)
  worker_cpus=$(list_cross_core_worker_cpus "$reader_cpu")
  benchmark=$(get_pebs_mrt_workload)
  for worker_cpu in $worker_cpus; do
    clear_files "$perfdata" "$perfdump" "$logfile"
    do_cmd "perf record -d -o $perfdata -c 100 -e 'cpu/mem-loads/P' -- $benchmark -m snoop-hit -r $reader_cpu -w $worker_cpu -i 262144 2>&1|tee $logfile"
    sample_count=$(grep "sample" "$logfile" | awk '{print $10}' | tr -cd "0-9")
    perf report --stdio -D -i "$perfdata" > "$perfdump"
    read -r snoop_na_count snoop_miss_count snoop_hit_count snoop_hitm_count snoop_none_count <<< "$(python3 - "$perfdump" <<'PY'
import sys
counts = {1: 0, 2: 0, 4: 0, 8: 0, 16: 0}
for line in open(sys.argv[1], errors='ignore'):
  if 'data_src:' not in line:
      continue
  value = int(line.split()[-1], 16)
  region = (value >> 46) & 0x1f
  lvl_num = (value >> 33) & 0xf
  snoop = (value >> 19) & 0x1f
  if region == 0x2 and lvl_num == 0x3 and snoop in counts:
      counts[snoop] += 1
print(counts[1], counts[8], counts[4], counts[16], counts[2])
PY
    )" || die "failed to decode snoop data_src values"
    test_print_trc "reader_cpu=$reader_cpu worker_cpu=$worker_cpu sample_count=$sample_count source2_snoop_na=$snoop_na_count source2_snoop_miss=$snoop_miss_count source2_snoop_hit=$snoop_hit_count source2_snoop_hitm=$snoop_hitm_count source2_snoop_none=$snoop_none_count"
    [[ $sample_count -gt 0 ]] || die "samples = 0!"
    if [[ $snoop_hit_count -gt 0 ]]; then
      clear_files "$perfdata" "$perfdump" "$logfile"
      return 0
    fi
  done

  clear_files "$perfdata" "$perfdump" "$logfile"
  die "no local shared-cache snoop HIT samples found!"
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
    arch_pebs_counter_group_stress)
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
    rdpmc_user_disable_0)
      rdpmc_user_disable 0
      ;;
    rdpmc_user_disable_1)
      rdpmc_user_disable 1
      ;;
    rdpmc_user_disable_2)
      rdpmc_user_disable 2
      ;;
    acr_cpuid)
      acr_cpuid_test
      ;;
    acr_format)
      acr_run_on_supported_pmus acr_format_test
      ;;
    acr_basic)
      acr_run_on_supported_pmus acr_basic_test
      ;;
    acr_ratio_to_prev)
      acr_run_on_supported_pmus acr_ratio_to_prev_test
      ;;
    acr_stat)
      acr_run_on_supported_pmus acr_stat_test
      ;;
    acr_reject_freq)
      acr_reject_freq_test
      ;;
    acr_reject_ppp)
      acr_reject_ppp_test
      ;;
    acr_reject_contiguity)
      acr_reject_contiguity_test
      ;;
    acr_stress)
      acr_run_on_supported_pmus acr_stress_test
      ;;
    pebs_mrt_local_ram)
      pebs_mrt_local_ram_test
      ;;
    pebs_mrt_snoop_hit)
      pebs_mrt_snoop_hit_test
      ;;
    esac
  return 0
}

while getopts :t:l:H arg; do
  case $arg in
    t)
      TEST_SCENARIO=$OPTARG
      ;;
    l)
      STRESS_TIMES=$OPTARG
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
