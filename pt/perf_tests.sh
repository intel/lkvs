#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation

# Author:   Ammy Yi <ammy.yi@intel.com>
#
# History:  19. Dec, 2022 - (Ammy Yi)Creation


# @desc This script verify pt functional test with perf
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

result_check() {
  grep lost $perf_log
  [[ $? -eq 1 ]] || die "There is data lost during perf record!"
}

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


pwr_evt_test_w_itrace() {
  power_v=$(cat /sys/bus/event_source/devices/intel_pt/caps/power_event_trace)
  [[ $power_v -eq 0 ]] && na_test "power_event_trace is not supported in this platform"
  do_cmd "perf record -a -e intel_pt/pwr_evt,branch=0/ sleep 1 >& $perf_log"
  sleep 1
  sync
  sync
  do_cmd "perf script --itrace=p > $temp_log"
  if [[ $power_v -eq 0 ]]; then
    test_print_trc "Platform is not supported power_event_trace, will check --itrace=p is null!"
    [[ -s $temp_log ]] && die "$temp_log is not NULL!"
  elif [[ $power_v -eq 1 ]]; then
    test_print_trc "Platform is supported power_event_trace, will check --itrace=p is not null!"
    [[ -s $temp_log ]] || die "$temp_log is NULL!"
  fi
  result_check
  rm -f $perf_log
  rm -f $temp_log
}

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
  perf record -e intel_pt//u sleep 1 >& $perf_log
  result_check
  sleep 1
  sync
  sync
  do_cmd "perf script -D > $temp_log"
  #get TIP/FUP/TIPPGD higest address
  grep -E 'TIP|FUP|TIP.PGD|TIP.PGE' $temp_log | awk '{print $NF}'  | awk -F '0x' '{print $2}'> $p_log
  grep -E 'TIP|FUP|TIP.PGD|TIP.PGE' $temp_log | awk '{print $3}' > $ipbyte_log
  #decode ipbyte as ipbyte is bit 5,6,7
  #if 001b/010b/100b then use last IP
  #if 011b then IP payload extended
  #if FUP/TIP/TIP.PGE/TIP.PGD follow a PSB, then last IP as zero
  sync
  sync
  test_print_trc "check 011b as IP payload extended!"
  while read -r line
  do
    count=$((count + 1))
    ipbyte=$((16#${line}))
    ipbyte=$(echo "obase=2;${ipbyte}"|bc)
    ipbyte=$((2#${ipbyte}  >> 5))
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
  done < $ipbyte_log
  rm -f $temp_log
  rm -f $p_log
  rm -f $ipbyte_log
}

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
  perf record -e intel_pt//k sleep 1 >& $perf_log
  result_check
  sleep 1
  do_cmd "perf script -D > $temp_log"
  #get TIP/FUP/TIPPGD higest address
  grep -E 'TIP|FUP|TIP.PGD|TIP.PGE' $temp_log | awk '{print $NF}'  | awk -F '0x' '{print $2}'> $p_log
  grep -E 'TIP|FUP|TIP.PGD|TIP.PGE' $temp_log | awk '{print $3}' > $ipbyte_log
  #decode ipbyte as ipbyte is bit 5,6,7
  #if 001b/010b/100b then use last IP
  #if 011b then IP payload extended
  #if FUP/TIP/TIP.PGE/TIP.PGD follow a PSB, then last IP as zero
  sync
  sync
  test_print_trc "check 011b as IP payload extended!"
  while read -r line
  do
    count=$((count + 1))
    ipbyte=$((16#${line}))
    ipbyte=$(echo "obase=2;${ipbyte}"|bc)
    ipbyte=$((2#${ipbyte}  >> 5))
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
  done < $ipbyte_log
  test_print_trc "check PSB with last IP!"
  #001b, 010b, 100b once follow PSB will fail, since PSB will set last IP as 0
  grep -A 1 -w 'PSB' $temp_log \
    | grep -E 'TIP|FUP|TIP.PGD|TIP.PGE' \
    | awk '{print $3}' \
    > $ipbyte_log
  sync
  sync
  while read -r line
  do
    count=$((count + 1))
    ipbyte=$((16#${line}))
    ipbyte=$(echo "obase=2;${ipbyte}"|bc)
    ipbyte=$((2#${ipbyte}  >> 5))
    test_print_trc "ipbyte = $ipbyte"
    #count means line number for ipbyte found, addr means detailed address
    [[ $ipbyte -eq 1 || $ipbyte -eq 2 || $ipbyte -eq 4 ]] && die "Get address < 7f with kernel trace follow by PSB!"
  done < $ipbyte_log
  test_print_trc "cpl_kernel_test done!"
  rm -f $temp_log
  rm -f $p_log
  rm -f $ipbyte_log
}

time_cyc_test() {
  local cyc
  cyc=$(cat /sys/bus/event_source/devices/intel_pt/caps/psb_cyc)
  [[ $cyc -eq 0 ]] && block_test "Platform is not supported cyc "
  if [[ $cyc -eq 1 ]]; then
    test_print_trc "Platform is supported cyc, will check CYC package is found!"
    do_cmd "perf record -e intel_pt/cyc/ sleep 1 >& $perf_log"
    result_check
    sleep 1
    sync
    sync
    do_cmd "perf script -D > $temp_log"
    do_cmd "grep \"CYC 0x\" $temp_log"
    ##TODO will add more logic after confirm with Adrian
  fi
  rm -f $perf_log
  rm -f $temp_log
}

time_mtc_test() {
  local cyc
  cyc=$(cat /sys/bus/event_source/devices/intel_pt/caps/psb_cyc)
  [[ $cyc -eq 0 ]] && block_test "Platform is not supported cyc "
  if [[ $cyc -eq 1 ]]; then
    test_print_trc "Platform is supported cyc, will check CYC package will be disbaled if mtc is disabled!"
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

pebs_test() {
  local cyc
  perf record -e '{intel_pt/branch=0/,cycles/aux-output/ppp,instructions}' -c 1 -m,4 ls -lt / >& $perf_log
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

lbr_test() {
  local temp1_log="perf1.log"
  local temp2_log="perf2.log"
  do_cmd "perf record -e cycles:u,intel_pt//u -b sleep 1 >& $perf_log"
  result_check
  sleep 1
  sync
  sync
  do_cmd "perf script -F +brstack > $temp1_log"
  do_cmd "perf record -e cycles:u,intel_pt//u sleep 1 >& $perf_log"
  result_check
  sleep 1
  sync
  sync
  do_cmd "perf script -F +brstack > $temp2_log"
  count_1=$(awk 'END{print NR}' $temp1_log)
  count_2=$(awk 'END{print NR}' $temp2_log)
  [[ $count_1 -le $count_2 ]] && die "LBR is not working!!"
  rm -f $perf_log
  rm -f $temp1_log
  rm -f $temp2_log
}

mtopa_test() {
  topa_m=0
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

sample_test() {
  do_cmd "perf record --aux-sample=8192 -e '{intel_pt//u,branch-misses:u}' "\
         "sleep 1 >& $perf_log"
  result_check
  sleep 1
  sync
  sync
  rm -f $perf_log
}

user_m() {
  do_cmd  "perf record -e intel_pt//u -m1,128 uname >& $perf_log"
  result_check
  do_cmd  "perf record -e intel_pt//u -m1,128 uname >& $perf_log"
  result_check
}

kernel_m_test() {
  do_cmd  "perf record -e intel_pt//k -m1,128 uname >& $perf_log"
  result_check
  do_cmd  "perf record -e intel_pt//k -m1,128 uname >& $perf_log"
  result_check
}

miss_frequency_test() {
  times=10
  do_cmd "perf record -e intel_pt//u uname >& $perf_log"
  result_check
  sleep 1
  sync
  sync
  param="-F-comm,-tid,-period,-event,-dso,+addr,-cpu --ns"
  total_miss=$(perf script --itrace=bps${times} ${param} | grep -c ":")
  total=$(perf script --itrace=bp ${param} | grep -c ":")
  test_print_trc "total_miss = $total_miss"
  test_print_trc "toal = $total"
  diff=$((total-total_miss))
  [[ $diff -ne $times ]] && die "-s miss frequency is worng!"

}

virtual_lbr_test() {
  times=10
  do_cmd "perf record --aux-sample -e '{intel_pt//,cycles}:u' uname >& $perf_log"
  result_check
  sleep 1
  sync
  sync
  times=$(perf report | head -30 | grep -v 'Event count (approx.): 0' | grep -A 15 Event | grep -c '|')
  [[ $times -lt 2 ]] && die "no virtual lbr!"
}

lost_data_test() {
  #https://git.kernel.org/pub/scm/linux/kernel/git/tip/tip.git/commit/?h=perf/core&id=874fc35cdd55e2d46161901de43ec58ca2efc5fe
  #it is for some regression for data loss
  do_cmd "perf record -e intel_pt//u -m,8 uname >& $perf_log"
  result_check
}

notnt_test() {
  notnt=0
  do_cmd "notnt=$(cat /sys/bus/event_source/devices/intel_pt/caps/tnt_disable)"
  [[ $notnt -eq 0 ]] && block_test "tnt_disable is not supported in this platform"
  perfdata="notnt.log"
  do_cmd "perf record -e intel_pt/notnt/u uname >& $perf_log"
  perf report -D -i $perfdata
  [[ $(grep TNT $perfdata) -eq 0 ]] && die "Still get TNT!"
}

event_trace_test() {
  local event_trace
  event_trace=$(cat /sys/bus/event_source/devices/intel_pt/caps/event_trace)
  [[ $event_trace -eq 0 ]] && block_test "Platform is not supported event_trace "
  if [[ $event_trace -eq 1 ]]; then
    test_print_trc "Platform is supported event_trace, will check event_trace!"
    do_cmd "perf record -e intel_pt//u sleep 1 >& $perf_log"
    result_check
    sleep 1
    sync
    sync
    do_cmd "perf script --itrace=Ie > $temp_log"
    do_cmd "grep 'evt' $temp_log"
  fi
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
