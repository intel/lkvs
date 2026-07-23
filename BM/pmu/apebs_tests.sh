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

clear_files() {
  for i in "$@"; do
    [[ -f $i ]] && test_print_trc "Remove file: $i" && rm "$i"
  done;
}

lbr_test() {
  level=$1
  perfdata="pebs.data"
  logfile="temp.txt"
  perf record -o "$perfdata" -b -e cycles:"$level" -a sleep 1 2> "$logfile"
  sample_count=$(grep "sample" $logfile | awk '{print $10}' | tr -cd "0-9")
  count=$(perf report -D -i $perfdata| grep -c "branch stack")
  clear_files $perfdata $logfile
  test_print_trc "sample_count = $sample_count; count = $count"
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  [[ $sample_count -eq $count ]] || die "samples does not match!"
}

pebs_event_test() {
  local event_name=$1
  local level=$2
  perfdata="pebs.data"
  logfile="temp.txt"
  clear_files $perfdata $logfile
  event="${event_name}:$level"
  benchmark="sleep 1"
  perf record -o "$perfdata" -e "$event" -a $benchmark 2>&1|tee "$logfile"
  sample_count=$(grep "sample" $logfile | awk '{print $10}' | tr -cd "0-9")
  count=$(perf report -D -i $perfdata | grep -A 1 "$event_name" | grep "SAMPLE events" | awk '{print $3}')
  clear_files $perfdata $logfile
  test_print_trc "sample_count = $sample_count; count = $count"
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  [[ $sample_count -eq $count ]] || die "samples does not match!"
}

pebs_gp_counter_test() {
  pebs_event_test "branches" "$1"
}

pebs_fixed_counter_test() {
  pebs_event_test "instructions" "$1"
}

adaptive_pebs_msr_test() {
  # MSR_IA32_PERF_CAPABILITIES(0x345) bit 14 indicates adaptive PEBS support.
  bit_14=$(rdmsr 0x345 -f 14:14)
  test_print_trc "MSR IA32_PERF_CAPABILITIES(0x345) bit 14 is: $bit_14"
  [[ $bit_14 -eq 1 ]] || die "Adaptive PEBS msr bit is not set!"
}

xmm_test() {
  level=$1
  perfdata="pebs.data"
  logfile="temp.txt"
  simdfile="simd.txt"
  local reg_type=0
  local xmm_arg=""
  local xmm_count=0
  perf record -I? 2>&1|tee $simdfile
  grep 'XMM0-15' $simdfile > /dev/null && reg_type=0
  grep 'XMM0 XMM1' $simdfile > /dev/null && reg_type=1
  if [[ $reg_type -eq 0 ]]; then
    xmm_arg="XMM"
    mul=$((2 * 16))
  elif [[ $reg_type -eq 1 ]]; then
    xmm_arg=$(tr ' ,:()' '\n' < $simdfile | awk '
      { tok=toupper($0) }
      tok ~ /^XMM[0-9]+$/ && !seen[tok]++ { list = list ? list "," tok : tok }
      END { print list }
    ')
    xmm_count=$(echo "$xmm_arg" | tr ',' '\n' | wc -l)
    mul=$((2 * xmm_count))
  fi

  test_print_trc "XMM arg: $xmm_arg, mul: $mul"
  perf record -o $perfdata -I${xmm_arg} -e cycles:"$level" -C 0 sleep 1 2>&1|tee $logfile
  sample_count=$(grep "sample" $logfile | awk '{print $10}' | tr -cd "0-9")
  count=$(perf report -D -i $perfdata| grep -c "XMM")
  clear_files $perfdata $logfile $simdfile
  test_print_trc "before sample_count = $sample_count; count = $count"
  sample_count=$((sample_count * mul))
  test_print_trc "after sample_count = $sample_count; count = $count"
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  [[ $sample_count -eq $count ]] || die "samples does not match!"
}

pebs_gpr_test() {
  level=$1
  perfdata="pebs.data"
  logfile="temp.txt"
  regfile="reg.txt"
  reportfile="report.txt"
  gpr_regs=()
  gpr_csv=""
  clear_files $perfdata $logfile $regfile $reportfile

  event="cycles:$level"
  benchmark="sleep 1"

  perf record -I? 2>&1|tee "$regfile"
  gpr_csv=$(tr ' ,:()' '\n' < $regfile | awk '
    {
      tok=toupper($0)
      if (tok == "" || tok == "SSP")
        next
      if (tok ~ /^(R[0-9]+|[ABCD]X|[SD]I|BP|SP|IP|FLAGS|[CDEFGS]S)$/ && !seen[tok]++)
        list = list ? list "," tok : tok
    }
    END { print list }
  ')

  [ -z "$gpr_csv" ] && die "The system doesn't expose supported GPR registers in perf -I? output!"
  IFS=',' read -r -a gpr_regs <<< "$gpr_csv"
  test_print_trc "Detected GPR list: $gpr_csv"

  perf record -o "$perfdata" -I"${gpr_csv}" -e "$event" -C 0 $benchmark 2>&1|tee "$logfile"
  sample_count=$(grep "sample" $logfile | awk '{print $10}' | tr -cd "0-9")
  perf report -D -i "$perfdata" > "$reportfile"
  count=0
  for reg in "${gpr_regs[@]}"; do
    reg_count=$(grep -v events "$reportfile" | grep -c "\. ${reg} ")
    count=$((count + reg_count))
  done
  gpr_total=${#gpr_regs[@]}
  test_print_trc "sample_count = $sample_count; gpr_total = $gpr_total; count = $count"
  sample_count=$((sample_count * gpr_total))
  test_print_trc "expected_gpr_records = $sample_count"
  clear_files $perfdata $logfile $regfile $reportfile
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  [[ $sample_count -eq $count ]] || die "samples does not match!"
}

ip_test() {
  level=$1
  perfdata="pebs.data"
  logfile="temp.txt"
  clear_files $perfdata $logfile

  event="cycles:$level"
  benchmark="sleep 1"

  perf record -o "$perfdata" -e "$event" -a $benchmark 2>&1|tee "$logfile"
  sample_count=$(grep "sample" $logfile | awk '{print $10}' | tr -cd "0-9")
  ip_count=$(perf script -i "$perfdata" -F ip | awk '$1 ~ /^[0-9a-fA-F]+$/ {c++} END {print c+0}')
  nonzero_ip_count=$(perf script -i "$perfdata" -F ip | awk '$1 ~ /^[0-9a-fA-F]+$/ && $1 != "0" && $1 != "0000000000000000" {c++} END {print c+0}')
  clear_files $perfdata $logfile
  test_print_trc "sample_count = $sample_count; ip_count = $ip_count; nonzero_ip_count = $nonzero_ip_count"
  [[ $sample_count -eq 0 ]] && die "samples = 0!"
  [[ $sample_count -eq $ip_count ]] || die "sample count does not match EventingIP count!"
  [[ $ip_count -eq $nonzero_ip_count ]] || die "zero EventingIP was found in samples!"
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
  clear_files $perfdata $logfile
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
    gpr_1)
      pebs_gpr_test p
      ;;
    gpr_2)
      pebs_gpr_test P
      ;;
    gp_counter_1)
      pebs_gp_counter_test p
      ;;
    gp_counter_2)
      pebs_gp_counter_test P
      ;;
    fixed_counter_1)
      pebs_fixed_counter_test p
      ;;
    fixed_counter_2)
      pebs_fixed_counter_test P
      ;;
    adaptive_pebs_msr)
      adaptive_pebs_msr_test
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
