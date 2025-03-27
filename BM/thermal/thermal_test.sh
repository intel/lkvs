#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation
# Description:  Test script for x86_pkg_temp_thermal interrupts and
# throttling cases which is supported on both Intel® platforms
# @Author   wendy.wang@intel.com
# @History  Created Feb 13, 2023 - Created

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

THERMAL_PATH="/sys/class/thermal"
NUM_CPUS=$(lscpu | grep "On-line CPU(s) list" | awk -F "-" '{print $NF}' 2>&1)

# stress tool is required to run thermal cases
if which stress 1>/dev/null 2>&1; then
  stress --help 1>/dev/null || block_test "Failed to run stress tool,
please check stress tool error message."
else
  block_test "stress tool is required to run ISST cases,
please get it from latest upstream kernel-tools."
fi

# taskset tool is required to run thermal cases
if which taskset 1>/dev/null 2>&1; then
  taskset --help 1>/dev/null || block_test "Failed to run taskset tool,
please check tool error message."
else
  block_test "taskset tool is required to run thermal cases,
please get it from latest upstream kernel-tools."
fi

# Function to check x86_pkg_temp_thermal throttling case
thermal_throttling() {
  local thermal_zones=""

  for file in /sys/class/thermal/thermal_zone*; do
    thermal_zones="$thermal_zones ${file: -1}"
  done

  interrupt_before=$(cat /sys/kernel/debug/pkg_temp_thermal/pkg_thres_interrupt 2>&1)
  test_print_trc "thermal_zone lists: $thermal_zones"
  for i in $thermal_zones; do
    pkg=$(cat "$THERMAL_PATH/thermal_zone${i}/type" 2>&1)

    if [[ "$pkg" = "x86_pkg_temp" ]]; then
      cur_temp=$(cat "$THERMAL_PATH/thermal_zone${i}/temp" 2>&1)
      test_print_trc "cur_temp: $cur_temp"

      low=$((cur_temp - 500))
      high=$((cur_temp + 500))

      do_cmd "echo $low >$THERMAL_PATH/thermal_zone${i}/trip_point_0_temp"
      do_cmd "echo $high >$THERMAL_PATH/thermal_zone${i}/trip_point_1_temp"

      cpus=$(("$NUM_CPUS" + 1))
      taskset -c 0-"$NUM_CPUS" stress -c "$cpus" -t 20 &
      stress_pid=$!
      [[ -n "$stress_pid" ]] || block_test "stress is not launched."
      sleep 10

      cur_temp=$(cat "$THERMAL_PATH/thermal_zone${i}/temp" 2>&1)
      test_print_trc "cur_temp: $cur_temp"

      interrupt_after=$(cat "/sys/kernel/debug/pkg_temp_thermal/pkg_thres_interrupt" 2>&1)

      test_print_trc "Interrupts before: $interrupt_before, Interrupts after: $interrupt_after"
      [[ -z "$stress_pid" ]] || do_cmd "kill -9 $stress_pid"
      if [[ "$interrupt_after" -gt "$interrupt_before" ]]; then
        test_print_trc "Package thermal interrupts increased after setting trip_point_temp threshhold"
      else
        die "Package thermal interrupts did not increase after setting trip_point_temp threshhold"
      fi
    else
      test_print_trc "Thermal zone: $pkg does not support to set thermal throttling"
    fi
  done
}

# Function to test x86_pkg_temp thermal interrupts increasing
pkg_interrupts() {
  local pkg_thermal=""
  local temp=""
  local temp_high=""
  local time_init=0

  # Get initial interrupts value
  interrupt_array_init=$(grep "Thermal event interrupts" /proc/interrupts |
    tr -d "a-zA-Z:" | awk '{$1=$1;print}')
  if [[ -n "$interrupt_array_init" ]]; then
    test_print_trc "thermal_interrupt_array_init: $interrupt_array_init"
  else
    die "Thermal event interrupts is not detected."
  fi

  # Check x86_pkg_temp thermal zone and trigger its temperature increasing
  lines_number=$(cat "$THERMAL_PATH"/thermal_zone*/type | wc -l)
  lines=$(("$lines_number" - 1))
  for ((i = 0; i <= lines; i++)); do
    pkg_thermal=$(grep x86_pkg_temp "$THERMAL_PATH"/thermal_zone"$i"/type 2>&1)
    if [[ -n "$pkg_thermal" ]]; then
      test_print_trc "Thermal_zone_number with type of x86_pkg_temp: $i"
      break
    fi
  done
  [[ -z "$pkg_thermal" ]] && block_test "Did not detect x86_pkg_temp thermal zone."

  temp=$(cat "$THERMAL_PATH"/thermal_zone"$i"/temp 2>&1)
  test_print_trc "Currently x86_pkg_temp available temp shows $temp"
  [[ "$(echo "$temp <= 0" | bc)" -eq 1 ]] && block_test \
    "Test machine x86_pkg_temp is not enabled correctly."
  temp_high=$(("$temp" + 10))
  do_cmd "echo $temp_high > $THERMAL_PATH/thermal_zone$i/trip_point_1_temp"
  test_print_trc "temp_high: $temp_high"

  while [[ $time_init -le 200 ]]; do
    cpus=$(("$NUM_CPUS" + 1))
    taskset -c 0-"$NUM_CPUS" stress -c "$cpus" -t 30 &
    stress_pid=$!
    [[ -n "$stress_pid" ]] || block_test "stress is not launched."
    sleep 10
    temp_cur=$(cat "$THERMAL_PATH"/thermal_zone"$i"/temp 2>&1)
    test_print_trc "temp_cur: $temp_cur"
    [[ $temp_cur -gt $temp_high ]] && break
    time_init=$(("$time_init" + 1))
  done
  [[ $temp_cur -gt $temp_high ]] || die "The CPU doesn't heat up as expected."

  # Check if the x86_pkg_thermal interrupts increased
  interrupt_array_later=$(grep "Thermal event interrupts" /proc/interrupts |
    tr -d "a-zA-Z:" | awk '{$1=$1;print}')
  [[ -n "$interrupt_array_later" ]] || block_test "Did not get interrupts after workload"
  test_print_trc "thermal_interrupt_array_later: $interrupt_array_later"
  for i in $(seq 1 "$NUM_CPUS"); do
    interrupt_later=$(echo "$interrupt_array_later" | cut -d " " -f "$i")
    interrupt_init=$(echo "$interrupt_array_init" | cut -d " " -f "$i")
    test_print_trc "thermal_interrupt_later: $interrupt_later"
    test_print_trc "thermal_interrupt_init: $interrupt_init"
    [[ $interrupt_later -lt $interrupt_init ]] && die "x86 package thermal interrupts did not increase"
  done
  test_print_trc "x86 package thermal interrupts increased"
}

thermal_test() {
  case $TEST_SCENARIO in
  check_thermal_throttling)
    thermal_throttling
    ;;
  check_pkg_interrupts)
    pkg_interrupts
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

thermal_test
