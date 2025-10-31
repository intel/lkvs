#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation

# Author:   Ammy Yi <ammy.yi@intel.com>
#
# History:  19. Dec, 2022 - (Ammy Yi)Creation
#           29. Mar, 2024 - wendy.wang@intel.com Updated

# @desc This script verify Processor Trace functional test with perf tool
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

perf_log="perf_record.log"
temp_log="perf.log"

# Perf tool is required to run this processor trace cases
if which perf 1>/dev/null 2>&1; then
  perf list 1>/dev/null || block_test "Failed to run perf tool,
please check perf tool error message."
else
  block_test "perf tool is required to run processor trace cases,
please get it from latest upstream kernel-tools."
fi

result_check() {
  grep lost $perf_log
  [[ $? -eq 1 ]] || die "Data loss occurs during the perf record!"
}

# Function to filter MTC (Mini Time Counter) and TSC (Time-Stamp Counter) packages
filter_package_test() {
  do_cmd "perf record -e intel_pt/mtc=0,tsc=0/ sleep 1 >& $perf_log"
  sleep 1
  sync
  sync
  do_cmd "perf script -D > $temp_log"
  should_fail "grep \"MTC 0x\" $temp_log"
  should_fail "grep \"TSC 0x\" $temp_log"
  result_check
  rm -f $perf_log
  rm -f $temp_log
}

# Function to check control flow packages when branch disable
# TNT: Taken-Not-Taken
# TIP: Target IP Package
# FUP: Flow Update Package
disable_branch_test() {
  do_cmd "perf record -e intel_pt/branch=0/ sleep 1 >& $perf_log"
  sleep 1
  sync
  sync
  do_cmd "perf script -D > $temp_log"
  should_fail "grep \"TNT 0x\" $temp_log"
  should_fail "grep \"TIP 0x\" $temp_log"
  should_fail "grep \"FUP 0X\" $temp_log"
  result_check
  rm -f $perf_log
  rm -f $temp_log
}

# Function to check control flow packages when branch and PT both disable
disable_branch_w_pt_test() {
  do_cmd "perf record -e intel_pt/pt=0,branch=0/ sleep 1 >& $perf_log"
  sleep 1
  sync
  sync
  do_cmd "perf script -D > $temp_log"
  should_fail "grep \"TNT 0x\" $temp_log"
  should_fail "grep \"TIP 0x\" $temp_log"
  should_fail "grep \"FUP 0x\" $temp_log"
  result_check
  rm -f $perf_log
  rm -f $temp_log
}

# Function to check power event trace
pwr_evt_test() {
  do_cmd "power_v=$(cat /sys/bus/event_source/devices/intel_pt/caps/power_event_trace)"
  [[ $power_v -eq 0 ]] && na_test "power_event_trace is not supported in this platform"
  if [[ $power_v -eq 1 ]]; then
    do_cmd "perf record -a -e intel_pt/pwr_evt/ sleep 1 >& $perf_log"
    sleep 1
    sync
    sync
    do_cmd "perf script -D > $temp_log"
    result_check
    rm -f $perf_log
    rm -f $temp_log
  fi
}

# Function to check power event trace when branch is disabled
pwr_evt_test_wo_branch() {
  do_cmd "power_v=$(cat /sys/bus/event_source/devices/intel_pt/caps/power_event_trace)"
  [[ $power_v -eq 0 ]] && na_test "power_event_trace is not supported in this platform"
  if [[ $power_v -eq 1 ]]; then
    do_cmd "perf record -a -e intel_pt/pwr_evt,branch=0/ sleep 1 >& $perf_log"
    sleep 1
    sync
    sync
    do_cmd "perf script -D > $temp_log"
    result_check
    rm -f $perf_log
    rm -f $temp_log
  fi
}

# Function to check power event trace with itrace information is aligned
pwr_evt_test_w_itrace() {
  power_v=$(cat /sys/bus/event_source/devices/intel_pt/caps/power_event_trace)
  [[ $power_v -eq 0 ]] && na_test "power_event_trace is not supported in this platform"
  do_cmd "perf record -a -e intel_pt/pwr_evt,branch=0/ sleep 1 >& $perf_log"
  sleep 1
  sync
  sync
  do_cmd "perf script --itrace=p > $temp_log"
  if [[ $power_v -eq 0 ]]; then
    test_print_trc "Platform does not support power_event_trace, will check if --itrace=p is null!"
    [[ -s $temp_log ]] && die "$temp_log is not NULL!"
  elif [[ $power_v -eq 1 ]]; then
    test_print_trc "Platform supports power_event_trace, will check if --itrace=p is not null!"
    [[ -s $temp_log ]] || die "$temp_log is NULL!"
  fi
  result_check
  rm -f $perf_log
  rm -f $temp_log
}

# CPL: current privilege level
# PSB: Package Stream Boundary, which acts as 'heartbeats' that are generated
# at regular interval (e.g. every 4K trace packet bytes)
# TIP: Target IP Package
# FUP: Flow Update Package
# TIP.PGD: Target IP Package with Global Destination
# TIP.PGE: Target IP Package with Global Entry
# Function to check PT generated trace packages in user space
cpl_user_test() {
  #save package address logs
  local p_log="package.log"
  #save first bytes of packages for decode address
  local ipbyte_log="ip.log"
  local ipbyte
  local count=0
  local addr
  local length

  rm -f $perf_log
  perf record -e intel_pt//u sleep 1 >&$perf_log
  result_check
  sleep 1
  sync
  sync
  do_cmd "perf script -D > $temp_log"
  #get TIP/FUP/TIPPGD highest address
  grep -E 'TIP|FUP|TIP.PGD|TIP.PGE' $temp_log | awk '{print $NF}' | awk -F '0x' '{print $2}' >$p_log
  grep -E 'TIP|FUP|TIP.PGD|TIP.PGE' $temp_log | awk '{print $3}' >$ipbyte_log
  #decode ipbyte as ipbyte is bit 5,6,7
  #if 001b/010b/100b then use last IP
  #if 011b then IP payload extended
  #if FUP/TIP/TIP.PGE/TIP.PGD follow a PSB, then last IP as zero
  sync
  sync
  test_print_trc "check 011b as IP payload extended!"
  while read -r line; do
    count=$((count + 1))
    ipbyte=$((16#${line}))
    ipbyte=$(echo "obase=2;${ipbyte}" | bc)
    ipbyte=$((2#${ipbyte} >> 5))
    #count means line number for ipbyte found, addr means detailed address
    #011b IP payload will extern as [47]bit
    if [[ $ipbyte -eq 3 ]]; then
      addr=$(sed -n ${count}p $p_log)
      length=${#addr}
      if [[ $length -eq 12 ]]; then
        [[ ${addr} > "7fffffffffff" ]] && die "Get address > 7fffffffffff with user trace!"
      fi
      if [[ $length -eq 16 ]]; then
        [[ ${addr} > "7fffffffffffffff" ]] && die "Get address > 7fffffffffffffff with user trace!"
      fi
    fi
  done <$ipbyte_log
  rm -f $temp_log
  rm -f $p_log
  rm -f $ipbyte_log
}

# Function to check PT generated trace packages in kernel space
cpl_kernel_test() {
  #save package address logs
  local p_log="package.log"
  #save first bytes of packages for decode address
  local ipbyte_log="ip.log"
  local ipbyte
  local count=0
  local addr
  local length
  rm -f $perf_log
  perf record -e intel_pt//k sleep 1 >&$perf_log
  result_check
  sleep 1
  do_cmd "perf script -D > $temp_log"
  #get TIP/FUP/TIPPGD higest address
  grep -E 'TIP|FUP|TIP.PGD|TIP.PGE' $temp_log | awk '{print $NF}' | awk -F '0x' '{print $2}' >$p_log
  grep -E 'TIP|FUP|TIP.PGD|TIP.PGE' $temp_log | awk '{print $3}' >$ipbyte_log
  #decode ipbyte as ipbyte is bit 5,6,7
  #if 001b/010b/100b then use last IP
  #if 011b then IP payload extended
  #if FUP/TIP/TIP.PGE/TIP.PGD follow a PSB, then last IP as zero
  sync
  sync
  test_print_trc "check 011b as IP payload extended!"
  while read -r line; do
    count=$((count + 1))
    ipbyte=$((16#${line}))
    ipbyte=$(echo "obase=2;${ipbyte}" | bc)
    ipbyte=$((2#${ipbyte} >> 5))
    #count means line number for ipbyte found, addr means detailed address
    #011b IP payload will extern as [47]bit
    if [[ $ipbyte -eq 3 ]]; then
      addr=$(sed -n ${count}p $p_log)
      length=${#addr}
      if [[ $length -eq 12 ]]; then
        # shellcheck disable=SC2071
        [[ ${addr} < "800000000000" ]] && die "Get address < 7f with kernel trace!"
      fi
      if [[ $length -eq 16 ]]; then
        # shellcheck disable=SC2071
        [[ ${addr} < "8000000000000000" ]] && die "Get address < 7f with kernel trace!"
      fi
    fi
  done <$ipbyte_log
  test_print_trc "check PSB with last IP!"
  #001b, 010b, 100b once follow PSB will fail, since PSB will set last IP as 0
  grep -A 1 -w 'PSB' $temp_log |
    grep -E 'TIP|FUP|TIP.PGD|TIP.PGE' |
    awk '{print $3}' \
      >$ipbyte_log
  sync
  sync
  while read -r line; do
    count=$((count + 1))
    ipbyte=$((16#${line}))
    ipbyte=$(echo "obase=2;${ipbyte}" | bc)
    ipbyte=$((2#${ipbyte} >> 5))
    test_print_trc "ipbyte = $ipbyte"
    #count means line number for ipbyte found, addr means detailed address
    [[ $ipbyte -eq 1 || $ipbyte -eq 2 || $ipbyte -eq 4 ]] && die "Get address < 7f with kernel trace follow by PSB!"
  done <$ipbyte_log
  test_print_trc "cpl_kernel_test done!"
  rm -f $temp_log
  rm -f $p_log
  rm -f $ipbyte_log
}

# CYC: Cycle Counter, which package provide periodic indication of the
# number of the processor core clock cycles that pass between packets
# Function to check if the CYC package is supported and detected.
time_cyc_test() {
  local cyc

  cyc=$(cat /sys/bus/event_source/devices/intel_pt/caps/psb_cyc)
  [[ $cyc -eq 0 ]] && block_test "Platform is not supported cyc "
  if [[ $cyc -eq 1 ]]; then
    test_print_trc "Platform supports CYC, will check if CYC package is found!"
    do_cmd "perf record -e intel_pt/cyc/ sleep 1 >& $perf_log"
    result_check
    sleep 1
    sync
    sync
    if [[ $(perf report -D | grep -c 'CYC 0x') -eq 0 ]]; then
      die "CYC package is not found!"
    else
      test_print_trc "CYC package is detected."
    fi
  fi
  rm -f $perf_log
  rm -f $temp_log
}

# MTC: Mini Time Counter, which package provide periodic indication of
# the passing of wall-clock time
# CYC: Cycle Counter, which package provide periodic indication of the
# number of the processor core clock cycles that pass between packets.
# Function to check if the CYC will be disabled if MTC is disabled in perf
time_mtc_test() {
  local cyc
  cyc=$(cat /sys/bus/event_source/devices/intel_pt/caps/psb_cyc)
  [[ $cyc -eq 0 ]] && block_test "Platform does not support Cycle Counter package"
  if [[ $cyc -eq 1 ]]; then
    test_print_trc "Platform supports CYC, and check if \
the CYC package will be disabled if MTC is disabled!"
    do_cmd "perf record -e intel_pt/mtc=0/ sleep 1 >& $perf_log"
    result_check
    sleep 1
    sync
    sync
    do_cmd "perf script -D > $temp_log"
    should_fail "grep \"CYC 0x\" $temp_log"
    should_fail "grep \"MTC 0x\" $temp_log"
  fi
  rm -f $perf_log
  rm -f $temp_log
}

# Function to check if the CYC package is disabled by default
time_full_test() {
  local cyc
  cyc=$(cat /sys/bus/event_source/devices/intel_pt/caps/psb_cyc)
  [[ $cyc -eq 0 ]] && block_test "Platform does not support Cycle Counter package"
  if [[ $cyc -eq 1 ]]; then
    test_print_trc "Platform supports CYC, will check if CYC package is disabled by default"
    do_cmd "perf record -e intel_pt//u sleep 1 >& $perf_log"
    result_check
    sleep 1
    sync
    sync
    do_cmd "perf script -D > $temp_log"
    should_fail "grep \"CYC 0x\" $temp_log"
    ##TODO will add more logic after confirming with Adrian
  fi
  rm -f $perf_log
  rm -f $temp_log
}

# PEBS: Precise Event-Based Sampling
# Function to record and filter PT's branch events, cycles, and instructions
# while executing uname command
pebs_test() {
  # Check the supportnness of PEBS
  # When both CPUID.07H.0.EBX[25] and IA32_PERF_CAPABILITIES.PEBS_OUTPUT_PT_AVAIL
  # (bit[16] of MSR 0x345) are set as 1, then PEBS extensions would be supported by CPU
  do_cmd "cpuid_check 7 0 0 0 b 25"
  cpuid_ret=$?
  bit16=$(rdmsr 0x345 -f 16:16)
  if [[ cpuid_ret -eq 0 || bit16 -eq 0 ]] then
    block_test "PEBS is not supported in this platform"
  fi

  perf record -e '{intel_pt/branch=0/,cycles/aux-output/ppp,instructions}' -c 128 -m,4 uname >&$perf_log
  result_check
  sleep 1
  sync
  sync
  do_cmd "perf script -D | grep -w 'B.P'> $temp_log"
  rm -f $perf_log
  rm -f $temp_log
}

trace_teardown() {
  rm -f "$HOME/.perfconfig"
}

# LBR: Last Branch Record, which refers to a stack of records that contain
# information about the most recent branches that the processor has taken.
# This includes information such as the source and destination addresses
# of branch instructions
# This function is to check the number of branch stack information lines of
# two perf.data files
lbr_test() {
  local temp1_log="perf1.log"
  local temp2_log="perf2.log"

  do_cmd "perf record -e cycles:u,intel_pt//u -b sleep 1 >& $perf_log"
  result_check
  sleep 1
  sync
  sync
  # Command to generate a script from perf.data file
  # and filter out the branch stack information
  do_cmd "perf script -F +brstack > $temp1_log"
  do_cmd "perf record -e cycles:u,intel_pt//u sleep 1 >& $perf_log"
  result_check
  sleep 1
  sync
  sync
  do_cmd "perf script -F +brstack > $temp2_log"
  count_1=$(awk 'END{print NR}' $temp1_log)
  count_2=$(awk 'END{print NR}' $temp2_log)
  [[ $count_1 -le $count_2 ]] && die "Last Branch Record is not working!!"
  rm -f $perf_log
  rm -f $temp1_log
  rm -f $temp2_log
}

# Function to check Intel PT's multiple topa entries
# topa: Table of Physical Adress
mtopa_test() {
  local topa_m=0

  do_cmd "topa_m=$(cat /sys/bus/event_source/devices/intel_pt/caps/topa_multiple_entries)"
  [[ $topa_m -eq 0 ]] && block_test "topa_multiple_entries is not supported in this platform"
  if [[ $topa_m -eq 1 ]]; then
    do_cmd "perf record -e intel_pt//u sleep 1 >& $perf_log"
    result_check
    sleep 1
    sync
    sync
    rm -f $perf_log
  fi
}

# Function to check Intel PT's auxiliary samples
# specified to the branch misses events
sample_test() {
  do_cmd "perf record --aux-sample=8192 -e '{intel_pt//u,branch-misses:u}' " \
    "sleep 1 >& $perf_log"
  result_check
  sleep 1
  sync
  sync
  rm -f $perf_log
}

# Function to check Intel Processor Trace's user events
# by perf tool for multiple cycles
# Note: the -m option is making the buffers small, case may fail with data is lost.
user_m_test() {
  do_cmd "perf record -e intel_pt//u -m,256 uname >& $perf_log"
  result_check
  do_cmd "perf record -e intel_pt//u -m,256 uname >& $perf_log"
  result_check
}

# Function to check Intel Processor Trace's kernel events
# by perf tool for multiple cycles
# Note: the -m option is making the buffers small, case may fail with data is lost.
kernel_m_test() {
  do_cmd "perf record -e intel_pt//k -m,256 uname >& $perf_log"
  result_check
  do_cmd "perf record -e intel_pt//k -m,256 uname >& $perf_log"
  result_check
}

# Function to verify the miss frequency of specified events
miss_frequency_test() {
  local times=10
  local param="-F-comm,-tid,-period,-event,-dso,+addr,-cpu --ns"

  do_cmd "perf record -e intel_pt//u uname >& $perf_log"
  result_check
  sleep 1
  sync
  sync

  total_miss=$(perf script --itrace=bps${times} ${param} | grep -c ":")
  total=$(perf script --itrace=bp ${param} | grep -c ":")
  test_print_trc "total_miss = $total_miss"
  test_print_trc "toal = $total"
  diff=$((total - total_miss))
  [[ $diff -ne $times ]] && die "-s miss frequency is wrong!"
}

# Function to verify the virtual LBR (Last Branch Record)
virtual_lbr_test() {
  local times=10

  do_cmd "perf record --aux-sample -e '{intel_pt//,cycles}:u' uname >& $perf_log"
  result_check
  sleep 1
  sync
  sync
  times=$(perf report | head -30 | grep -v 'Event count (approx.): 0' | grep -A 15 Event | grep -c '|')
  [[ $times -lt 2 ]] && die "no virtual Last Branch Record!"
}

# Function to check if there is data lost during perf record
lost_data_test() {
  #https://git.kernel.org/pub/scm/linux/kernel/git/tip/tip.git/commit/?h=perf/core&id=874fc35cdd55e2d46161901de43ec58ca2efc5fe
  #it is for some regression for data loss
  do_cmd "perf record -e intel_pt//u -m,8 uname >& $perf_log"
  result_check
}

# Function to check COFI (Change of flow instruction) tracing model
# control flow: TNT (Taken/Not-taken) package
# Expect to not get TNT when TNT is disabled
notnt_test() {
  touch nontnt.log
  local notnt=""

  do_cmd "notnt=$(cat /sys/bus/event_source/devices/intel_pt/caps/tnt_disable)"
  [[ $notnt -eq 0 ]] && block_test "tnt_disable is not supported in this platform"

  do_cmd "perf record -o nontnt.log -e intel_pt/notnt/u uname >& $perf_log"

  if [[ $(perf report -D -i nontnt.log | grep -c "TNT") -ne 0 ]]; then
    die "Still get TNT package when tnt is disabled!"
  else
    test_print_trc "Did not get TNT package when tnt is disabled."
  fi
}

# Function to check if event trace is supported and detected.
event_trace_test() {
  local event_trace

  event_trace=$(cat /sys/bus/event_source/devices/intel_pt/caps/event_trace)
  [[ $event_trace -eq 0 ]] && block_test "Platform does not support event_trace "
  if [[ $event_trace -eq 1 ]]; then
    test_print_trc "Platform supports event_trace, will check event_trace!"
    do_cmd "perf record -e intel_pt/event/u sleep 1 >& $perf_log"
    result_check
    sleep 1
    sync
    sync
    do_cmd "perf script --itrace=Ie > $temp_log"
    if [[ -s $temp_log ]]; then
      do_cmd "grep 'evt' $temp_log"
    else
      test_print_trc "$temp_log is empty"
    fi
  fi
  rm -f $perf_log
  rm -f $temp_log
}

# Function to check if tracestop is supported and detected.
tracestop_test() {
  local path
  path=$(pwd)
  path=$path"/sort_test"
  do_cmd "perf record -e intel_pt//u '--filter=tracestop main @ $path' sort_test >& $perf_log"
  result_check
  rm -f $perf_log
}

# Function to check trace filter with main count
tracefilter_test() {
  local path
  path=$(pwd)
  path=$path"/sort_test"
  do_cmd "perf record -e intel_pt//u '--filter=filter main @ $path' sort_test >& $perf_log"
  result_check
  sleep 1
  sync
  sync
  do_cmd "perf script --itrace=ibxwe | tail > $temp_log"
  count_e=$(grep -c main $temp_log)
  count_cbr=$(grep -c "cbr" $temp_log)
  count_p=$(grep -c "branch" $temp_log)
  test_print_trc "count_e=$count_e, count_cbr=$count_cbr, count_p=$count_p"
  [[ $count_e -eq $count_p ]] || die "main count is not right, trace filter with main is failed!"
  should_fail "sed -n $count_p'p' $temp_log | grep unknown"
  rm -f $perf_log
  rm -f $temp_log
}

# Function to check kernel level trace filter with __sched samples
filter_kernel_test() {
  do_cmd "perf record --kcore -e intel_pt//k --filter 'filter __schedule' -a  -- sleep 0.1 >& $perf_log"
  result_check
  do_cmd "perf script --itrace=b | tail > $temp_log"
  cat $temp_log
  count_e=$(grep -c "__schedule" "$temp_log")
  count_p=$(wc -l <"$temp_log")
  test_print_trc "count_e = $count_e count_p=$count_p"
  [[ $count_e -eq $count_p ]] || die "__sched count is not right, trace filter with __schedule for kernel is failed!"
  rm -f "$perf_log"
  rm -f "$temp_log"
}

# Function to check if trace filter with __sched for kernel is supported and detected.
filter_kernel_cpu_test() {
  rm perfdata -rf
  do_cmd "perf record --kcore -e intel_pt// --filter 'filter __schedule / __schedule' -a  -- sleep 1 >& $perf_log"
  result_check
  sleep 1
  sync
  sync
  do_cmd "perf script --itrace=ibxwpe | tail > $temp_log"
  count_e=$(grep -c "__sched" $temp_log)
  count_cbr=$(grep -c "cbr" $temp_log)
  count_p=$(awk 'END{print NR}' $temp_log)
  test_print_trc "count_e = $count_e count_cbr=$count_cbr count_p=$count_p"

  [[ $count_e -eq $count_p ]] || die "__sched count is not right, trace filter with __sched for kernel is failed!"
  should_fail "sed -n $count_p'p' $temp_log | grep unknown"
  rm perfdata -rf
  rm -f $perf_log
  rm -f $temp_log
}

perftest() {
  case $TEST_SCENARIO in
  fp)
    filter_package_test
    ;;
  disablebranch)
    disable_branch_test
    ;;
  pt)
    disable_branch_w_pt_test
    ;;
  pwr_evt)
    pwr_evt_test
    ;;
  pwr_evt_branch)
    pwr_evt_test_wo_branch
    ;;
  pwr_evt_itrace)
    pwr_evt_test_w_itrace
    ;;
  user)
    cpl_user_test
    ;;
  kernel)
    cpl_kernel_test
    ;;
  cyc)
    time_cyc_test
    ;;
  mtc)
    time_mtc_test
    ;;
  time_full)
    time_full_test
    ;;
  pebs)
    pebs_test
    ;;
  lbr)
    lbr_test
    ;;
  mtopa)
    mtopa_test
    ;;
  sample)
    sample_test
    ;;
  user_m)
    user_m_test
    ;;
  kernel_m)
    kernel_m_test
    ;;
  miss_frequency)
    miss_frequency_test
    ;;
  virtual_lbr)
    virtual_lbr_test
    ;;
  lost_data)
    lost_data_test
    ;;
  notnt)
    notnt_test
    ;;
  event_trace)
    event_trace_test
    ;;
  trace_stop)
    tracestop_test
    ;;
  trace_filter)
    tracefilter_test
    ;;
  trace_filter_kernel)
    filter_kernel_test
    ;;
  trace_filter_kernel_cpu)
    filter_kernel_cpu_test
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

perftest
# Call teardown for passing case
exec_teardown
