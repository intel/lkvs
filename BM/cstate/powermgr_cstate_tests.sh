#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation
# @Author   wendy.wang@intel.com
# @Desc     Test script to verify Intel CPU Core Cstate functionality
# @History  Created Nov 01 2022 - Created

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

CPU_SYSFS_PATH="/sys/devices/system/cpu"
CPU_BUS_SYSFS_PATH="/sys/bus/cpu/devices/"
CPU_IDLE_SYSFS_PATH="/sys/devices/system/cpu/cpuidle"
PKG_CST_CTL="0xe2"
MSR_PKG2="0x60d"
MSR_PKG6="0x3f9"

current_cpuidle_driver=$(cat "$CPU_IDLE_SYSFS_PATH"/current_driver)

# Turbostat tool is required to run core cstate cases
if which turbostat 1>/dev/null 2>&1; then
  turbostat sleep 1 1>/dev/null || block_test "Failed to run turbostat tool,
please check turbostat tool error message."
else
  block_test "Turbostat tool is required to run CSTATE cases,
please get it from latest upstream kernel-tools."
fi

# Perf tool is required to run this cstate perf cases
if which perf 1>/dev/null 2>&1; then
  perf list 1>/dev/null || block_test "Failed to run perf tool,
please check perf tool error message."
else
  block_test "perf tool is required to run CSTATE cases,
please get it from latest upstream kernel-tools."
fi

# Function to verify if Intel_idle driver refer to BIOS _CST table
test_cstate_table_name() {
  local cstate_name=""
  local name=""

  cstate_name=$(cat "$CPU_SYSFS_PATH"/cpu0/cpuidle/state*/name)
  name=$(echo "$cstate_name" | grep ACPI)
  if [[ -n $name ]]; then
    test_print_trc "$cstate_name"
    die "Intel_idle driver refers to ACPI cstate table."
  else
    test_print_trc "$cstate_name"
    test_print_trc "Intel_idle driver refers to BIOS _CST table."
  fi
}

# Function to verify if current idle driver is intel_idle
check_intel_idle() {
  [[ $current_cpuidle_driver == "intel_idle" ]] || {
    block_test "If the platform does not support Intel_Idle driver yet, \
please ignore this test case."
  }
}

# Function to switch each core cstate
test_cstate_switch_idle() {
  local usage_before=()
  local usage_after=()
  local cpus=""
  local states=""
  local cpu_num=""

  cpus=$(ls "$CPU_BUS_SYSFS_PATH" | xargs)
  cpu_num=$(lscpu | grep "^CPU(s)" | awk '{print $2}')

  if [[ -n "$cpus" ]]; then
    for cpu in $cpus; do
      states=$(ls "$CPU_BUS_SYSFS_PATH"/"$cpu"/cpuidle | grep state | xargs)
      if [[ -n "$states" ]]; then
        for state in $states; do
          # Disable stateX of cpuX
          echo 1 >"${CPU_SYSFS_PATH}/${cpu}/cpuidle/${state}/disable"
        done
      else
        die "fail to get state node for $cpu"
      fi
    done
  else
    die "fail to get cpu sysfs directory"
  fi

  for state in $states; do
    test_print_trc ------ loop for "$state" ------

    # Count usage of the stateX of cpuX before enable stateX
    i=0
    while [[ "$i" != "$cpu_num" ]]; do
      usage_before[$i]=$(cat "$CPU_SYSFS_PATH"/cpu"${i}"/cpuidle/"$state"/usage)
      [[ -n ${usage_before[$i]} ]] || die "fail to count usage_before of $state of cpu${i}"
      i=$(("$i" + 1))
    done

    # Enable stateX of cpuX
    for cpu in $cpus; do
      echo 0 >"${CPU_SYSFS_PATH}/${cpu}/cpuidle/${state}/disable"
    done

    # Sleep and wait for entry of the state
    sleep 30

    # Count usage of the stateX for cpuX after enable stateX
    i=0
    while [[ "$i" != "$cpu_num" ]]; do
      usage_after[$i]=$(cat "$CPU_SYSFS_PATH"/cpu"${i}"/cpuidle/"$state"/usage)
      [[ -n ${usage_after[$i]} ]] || die "fail to count usage_after of $state of cpu${i}"
      i=$(("$i" + 1))
    done

    # Compare the usage to see if the cpuX enter stateX
    i=0
    while [[ "$i" != "$cpu_num" ]]; do
      if [[ ${usage_after[${i}]} -gt ${usage_before[${i}]} ]]; then
        test_print_trc "cpu${i} enter $state successfully"
      else
        die "cpu${i} fail to enter $state"
      fi
      i=$(("$i" + 1))
    done
  done
}

test_cstate_switch_intel_idle() {
  check_intel_idle
  test_cstate_switch_idle
}

# The Core C7 is only supported on Intel® Client platform
# This function is to check Core C7 residency during runtime
judge_cc7_residency_during_idle() {
  columns="Core,CPU%c1,CPU%c6,CPU%c7"
  turbostat_output=$(turbostat -i 10 --quiet \
    --show $columns sleep 10 2>&1)
  test_print_trc "$turbostat_output"
  CC7_val=$(echo "$turbostat_output" | grep -E "^-" | awk '{print $4}')
  test_print_trc "CPU Core C7 residency :$CC7_val"
  [[ $CC7_val == "0.00" ]] && die "CPU Core C7 residency is not available."

  # Judge whether CC7 residency is available during idle
  turbostat_CC7_value=$(echo "scale=2; $CC7_val > 0.00" | bc)
  [[ $turbostat_CC7_value -eq 1 ]] ||
    die "Did not get CPU Core C7 residency during idle \
when $current_cpuidle_driver is running."
  test_print_trc "CPU Core C7 residency is available during idle \
when $current_cpuidle_driver is running"
}

# The Core C7 is only supported on Intel® Client platforms
# This function is to check Core C7 residency for S2idle path
judge_cc7_residency_during_s2idle() {
  columns="Core,CPU%c1,CPU%c6,CPU%c7"
  turbostat_output=$(
    turbostat --show $columns \
      rtcwake -m freeze -s 15 2>&1
  )
  turbostat_output=$(grep "CPU%c7" -A1 <<<"$turbostat_output")
  test_print_trc "$turbostat_output"
  CC7_val=$(echo "$turbostat_output" | grep -E "^-" | awk '{print $4}')
  test_print_trc "CPU Core C7 residency :$CC7_val"
  [[ $CC7_val == "0.00" ]] && die "CPU Core C7 residency is not available."

  # Judge whether CC7 residency is available during idle
  turbostat_CC7_value=$(echo "scale=2; $CC7_val > 0.00" | bc)
  [[ $turbostat_CC7_value -eq 1 ]] ||
    die "Did not get CPU Core C7 residency during S2idle \
when $current_cpuidle_driver is running"
  test_print_trc "CPU Core C7 residency is available during S2idle \
when $current_cpuidle_driver is running."
}

# The Core C6 is the deepest cstate on Intel® Server platforms
test_server_all_cpus_deepest_cstate() {
  local unexpected_cstate=0.00

  columns="sysfs,CPU%c1,CPU%c6"
  turbostat_output=$(turbostat -i 10 --quiet \
    --show $columns sleep 10 2>&1)
  test_print_trc "Turbostat log: $turbostat_output"
  all_deepest_cstate=$(echo "$turbostat_output" |
    awk '{for(i=0;++i<=NF;)a[i]=a[i]?a[i] FS $i:$i} END{for(i=0;i++<=NF;)print a[i]}' | grep "CPU%c6")
  test_print_trc "The deepest core cstate is: $all_deepest_cstate"
  if [[ -z $all_deepest_cstate ]]; then
    block_test "The CPUs cstate is not available."
  elif [[ $all_deepest_cstate =~ $unexpected_cstate ]] && [[ ! "$all_deepest_cstate" == *"100.00"* ]]; then
    test_print_trc "Getting CPU C6 state by reading MSR 0x3fd:"
    rdmsr -a 0x3fd
    die "The CPU Core did not enter the deepest cstate!"
  else
    test_print_trc "All the CPUs core enter the deepest cstate!"
  fi
}

# Verify if the ATOM server platform CPUs can enter the MC6 state
test_server_all_cpus_mc6() {
  local unexpected_cstate=0.00
  local cpu_model=""

  cpu_model=$(lscpu | grep Model: | awk '{print $2}')
  if [[ $cpu_model -eq 175 ]] || [[ $cpu_model -eq 221 ]]; then
    columns="sysfs,CPU%c1,CPU%c6,Mod%c6"
    turbostat_output=$(turbostat -i 10 --quiet \
      --show $columns sleep 10 2>&1)
    test_print_trc "Turbostat log: $turbostat_output"
    all_mc6_cstate=$(echo "$turbostat_output" |
      awk '{for(i=0;++i<=NF;)a[i]=a[i]?a[i] FS $i:$i} END{for(i=0;i++<=NF;)print a[i]}' | grep "Mod%c6")
    test_print_trc "The MC6 cstate is: $all_mc6_cstate"
    if [[ -z $all_mc6_cstate ]]; then
      block_test "The CPUs cstate is not available."
    elif [[ $all_mc6_cstate =~ $unexpected_cstate ]] && [[ ! "$all_mc6_cstate" == *"100.00"* ]]; then
      test_print_trc "Getting CPU MC6 state by reading MSR 0x664:"
      rdmsr -a 0x664
      die "The CPU did not enter the MC6 cstate!"
    else
      test_print_trc "All the CPUs enter the MC6 cstate!"
    fi
  else
    skip_test "SUT does not support module cstate."
  fi
}

# The Core C6 is only supported on Intel® Server platform
# This function is to check Core C6 residency during runtime
judge_cc6_residency_during_idle() {
  columns="Core,CPU%c1,CPU%c6"
  turbostat_output=$(turbostat -i 10 --quiet \
    --show $columns sleep 10 2>&1)
  test_print_trc "Turbostat log: $turbostat_output"
  CC6_val=$(echo "$turbostat_output" | grep -E "^-" | awk '{print $3}')
  test_print_trc "CPU Core C6 residency :$CC6_val"
  [[ -n $CC6_val ]] || die "CPU Core C6 residency is not available."

  # Judge whether CC6 residency is available during idle
  turbostat_CC6_value=$(echo "scale=2; $CC6_val > 0.00" | bc)
  if [[ $turbostat_CC6_value -eq 1 ]]; then
    test_print_trc "CPU Core C6 residency is available \
during idle when $current_cpuidle_driver is running"
  else
    die "Did not get CPU Core C6 residency during idle \
when $current_cpuidle_driver is running"
  fi
}

test_cpu_core_c7_residency_intel_idle() {
  check_intel_idle
  judge_cc7_residency_during_idle
}

test_cpu_core_c7_residency_intel_s2idle() {
  check_intel_idle
  judge_cc7_residency_during_s2idle
}

test_cpu_core_c6_residency_intel_idle() {
  check_intel_idle
  judge_cc6_residency_during_idle
}

cc_state_disable_enable() {
  local cc=$1
  local setting=$2

  for ((i = 0; i < cpu_num; i++)); do
    # Find Core Cx state
    cc_num=$(grep . /sys/devices/system/cpu/cpu0/cpuidle/state*/name |
      sed -n "/$cc$/p" | awk -F "/" '{print $8}' | cut -c 6)
    test_print_trc "Core $cc state name is: $cc_num"
    [[ -n "$cc_num" ]] || block_test "Did not get Core $cc state."
    # Change Core Cx state
    do_cmd "echo $setting > /sys/devices/system/cpu/cpu$i/cpuidle/state$cc_num/disable"
    deeper=$(("$cc_num" + 1))
    # Change deeper Core Cx state
    for ((j = deeper; j < state_num; j++)); do
      do_cmd "echo $setting > /sys/devices/system/cpu/cpu$i/cpuidle/state$j/disable"
    done
  done
}

disable_cc_check_pc() {
  local cc=$1
  local pc_y=$2
  local pc_n=$3
  local cpu_num=""
  local columns=""

  cpu_num=$(lscpu | grep "^CPU(s)" | awk '{print $2}')
  state_num=$(ls "$CPU_BUS_SYSFS_PATH"/cpu0/cpuidle | grep -c state)
  columns="Pkg%pc2,Pkg%pc3,Pkg%pc6,Pkg%pc7,Pkg%pc8,Pkg%pc9,Pk%pc10"

  cc_state_disable_enable "$cc" 1

  # Check Package Cstates, CC10 disable--> expect PC8 only
  # CC8 and deeper disable--> PC6 only
  tc_out=$(turbostat -q --show $columns -i 1 sleep 20 2>&1)
  [[ -n "$tc_out" ]] || die "Did not get turbostat log"
  test_print_trc "turbostat tool output: $tc_out"
  pc_y_res=$(echo "$tc_out" |
    awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' |
    grep "$pc_y" | awk -F " " '{print $3}')
  pc_n_res=$(echo "$tc_out" |
    awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' |
    grep "$pc_n" | awk -F " " '{print $3}')
  [[ -n "$pc_y_res" ]] || die "Did not get $pc_y state."
  [[ -n "$pc_n_res" ]] || die "Did not get $pc_n state."
  if [[ $(echo "scale=2; $pc_y_res > 0.00" | bc) -eq 1 ]] && [[ $pc_n_res == "0.00" ]]; then
    cc_state_disable_enable "$cc" 0
    test_print_trc "Expected to get $pc_y only when disable $cc and deeper state.\
$pc_y residency: $pc_y_res; $pc_n residency: $pc_n_res"
  else
    cc_state_disable_enable "$cc" 0
    die "Did not get $pc_y residency after disable $cc and deeper states. \
$pc_y residency: $pc_y_res; $pc_n residency: $pc_n_res"
  fi
}

# perf tool listed cstate is based on kernel MSRs, turbostat tool listed
# cstate is based on user space MSRs, these two outputs should be aligned
# also client and server platforms support different core and pkg cstates.
perf_client_cstate_list() {
  tc_out=$(turbostat -q --show idle sleep 1 2>&1)
  [[ -n "$tc_out" ]] || block_test "Did not get turbostat log"
  test_print_trc "turbostat tool output: $tc_out"
  tc_out_cstate_list=$(echo "$tc_out" | grep -E "^POLL")

  perf_cstates=$(perf list | grep cstate)
  [[ -n "$perf_cstates" ]] || block_test "Did not get cstate events by perf list"
  test_print_trc "perf list shows cstate events: $perf_cstates"
  perf_core_cstate_num=$(perf list | grep -c cstate_core)
  for ((i = 1; i <= perf_core_cstate_num; i++)); do
    perf_core_cstate=$(perf list | grep cstate_core | sed -n "$i, 1p")
    if [[ $perf_core_cstate =~ c1 ]] && [[ $tc_out_cstate_list =~ CPU%c1 ]]; then
      test_print_trc "$perf_core_cstate is supported and aligned with turbostat"
    elif [[ $perf_core_cstate =~ c6 ]] && [[ $tc_out_cstate_list =~ CPU%c6 ]]; then
      test_print_trc "$perf_core_cstate is supported and aligned with turbostat"
    elif [[ $perf_core_cstate =~ c7 ]] && [[ $tc_out_cstate_list =~ CPU%c7 ]]; then
      test_print_trc "$perf_core_cstate is supported and aligned with turbostat"
    else
      die "perf list shows unexpected core_cstate event."
    fi
  done

  perf_pkg_cstate_num=$(perf list | grep -c cstate_pkg)
  for ((i = 1; i <= perf_pkg_cstate_num; i++)); do
    perf_pkg_cstate=$(perf list | grep cstate_pkg | sed -n "$i, 1p")
    if [[ $perf_pkg_cstate =~ c2 ]] && [[ $tc_out_cstate_list =~ Pkg%pc2 ]]; then
      test_print_trc "$perf_pkg_cstate is supported and aligned with turbostat"
    elif [[ $perf_pkg_cstate =~ c3 ]] && [[ $tc_out_cstate_list =~ Pkg%pc3 ]]; then
      test_print_trc "$perf_pkg_cstate is supported and aligned with turbostat"
    elif [[ $perf_pkg_cstate =~ c6 ]] && [[ $tc_out_cstate_list =~ Pkg%pc6 ]]; then
      test_print_trc "$perf_pkg_cstate is supported and aligned with turbostat"
    elif [[ $perf_pkg_cstate =~ c7 ]] && [[ $tc_out_cstate_list =~ Pkg%pc7 ]]; then
      test_print_trc "$perf_pkg_cstate is supported and aligned with turbostat"
    elif [[ $perf_pkg_cstate =~ c8 ]] && [[ $tc_out_cstate_list =~ Pkg%pc8 ]]; then
      test_print_trc "$perf_pkg_cstate is supported and aligned with turbostat"
    elif [[ $perf_pkg_cstate =~ c9 ]] && [[ $tc_out_cstate_list =~ Pkg%pc9 ]]; then
      test_print_trc "$perf_pkg_cstate is supported and aligned with turbostat"
    elif [[ $perf_pkg_cstate =~ c10 ]] && [[ $tc_out_cstate_list =~ Pk%pc10 ]]; then
      test_print_trc "$perf_pkg_cstate is supported and aligned with turbostat"
    else
      die "perf list shows unexpected pkg_cstate event."
    fi
  done
}

override_residency_latency() {
  local idle_debugfs="/sys/kernel/debug/intel_idle"
  test_print_trc "Will override state3 with new target residency:100 us,new exit latency value\
to 30 us:"
  [[ -e "$idle_debugfs"/control ]] || block_test "Intel idle debugfs file does not exist"
  do_cmd "echo 3:100:30 > $idle_debugfs/control"

  test_print_trc "Switch to the default intel idle driver"
  do_cmd "echo > $idle_debugfs/control"

  test_print_trc "Change two changes together"
  do_cmd "echo 1:0:10 3:100:30 > $idle_debugfs/control"

  test_print_trc "Switch to the default intel idle driver"
  do_cmd "echo > $idle_debugfs/control"
}

# Server platforms support different core cstate and package cstate
perf_server_cstate_list() {
  tc_out=$(turbostat -q --show idle sleep 1 2>&1)
  [[ -n "$tc_out" ]] || block_test "Did not get turbostat log"
  test_print_trc "turbostat tool output: $tc_out"
  tc_out_cstate_list=$(echo "$tc_out" | grep -E "^POLL")

  perf_cstates=$(perf list | grep cstate)
  [[ -n "$perf_cstates" ]] || block_test "Did not get cstate events by perf list"
  test_print_trc "perf list shows cstate events: $perf_cstates"
  perf_core_cstate_num=$(perf list | grep -c cstate_core)
  for ((i = 1; i <= perf_core_cstate_num; i++)); do
    perf_core_cstate=$(perf list | grep cstate_core | sed -n "$i, 1p")
    if [[ $perf_core_cstate =~ c1 ]] && [[ $tc_out_cstate_list =~ CPU%c1 ]]; then
      test_print_trc "$perf_core_cstate is supported and aligned with turbostat"
    elif [[ $perf_core_cstate =~ c6 ]] && [[ $tc_out_cstate_list =~ CPU%c6 ]]; then
      test_print_trc "$perf_core_cstate is supported and aligned with turbostat"
    else
      die "perf list shows unexpected core_cstate event."
    fi
  done

  perf_pkg_cstate_num=$(perf list | grep -c cstate_pkg)
  for ((i = 1; i <= perf_pkg_cstate_num; i++)); do
    perf_pkg_cstate=$(perf list | grep cstate_pkg | sed -n "$i, 1p")
    if [[ $perf_pkg_cstate =~ c2 ]] && [[ $tc_out_cstate_list =~ Pkg%pc2 ]]; then
      test_print_trc "$perf_pkg_cstate is supported and aligned with turbostat"
    elif [[ $perf_pkg_cstate =~ c6 ]] && [[ $tc_out_cstate_list =~ Pkg%pc6 ]]; then
      test_print_trc "$perf_pkg_cstate is supported and aligned with turbostat"
    else
      die "perf list shows unexpected pkg_cstate event."
    fi
  done
}

# Verify if server cstate_core or cstate_pkg pmu event updates during idle
perf_server_cstat_update() {
  local cstate_name=$1

  perf_cstates=$(perf list | grep "$cstate_name" 2>&1)
  perf_cstates_num=$(perf list | grep -c "$cstate_name" 2>&1)
  [[ -n $perf_cstates ]] || block_test "Did not get $cstate_name event by perf list"

  # Sleep 20 seconds to capture the cstate counter update
  for ((i = 1; i <= perf_cstates_num; i++)); do
    perf_cstate=$(echo "$perf_cstates" | awk '{print $1}' | sed -n "$i, 1p" 2>&1)
    test_print_trc "perf event name: $perf_cstate"
    option="$option -e $perf_cstate"
    test_print_trc "option name: $option"
  done
  do_cmd "perf stat -o out.txt --per-socket $option sleep 20"
  test_print_trc "$cstate_name perf events log:"
  do_cmd "cat out.txt"
  perf_cstates_sockets=$(grep cstate out.txt | awk '{print $NF}' | wc -l 2>&1)

  if ! counter=$(grep cstate out.txt | awk '{print $3}'); then
    block_test "Did not get $cstate_name perf event: $counter"
  else
    for ((i = 1; i <= perf_cstates_sockets; i++)); do
      perf_cstat_counter=$(grep cstate out.txt | awk '{print $3}' | sed -n "$i, 1p" 2>&1)
      perf_cstat_name=$(grep cstate out.txt | awk '{print $4}' | sed -n "$i, 1p" 2>&1)
      if [[ $perf_cstat_counter -eq 0 ]]; then
        die "$perf_cstat_name event counter shows 0"
      else
        test_print_trc "$perf_cstat_name event counter is updated"
      fi
    done
  fi
}

# Function to check if the server platform can enter the runtime PC2 state
# by reading the data using the turbostat tool
runtime_pc2_entry() {
  local pc2_val=""
  local time_to_enter_pc2=10
  local pkg_limit=""

  # Judge if the deeper pkg cstate is supported
  do_cmd "turbostat --debug -o tc.out sleep 1"
  pkg_limit=$(grep "pkg-cstate-limit=0" tc.out)

  if [[ -n $pkg_limit ]]; then
    block_test "The platform does not support deeper pkg cstate."
  fi

  pkg_cst_ctl=$(rdmsr -a $PKG_CST_CTL 2>/dev/null)

  msr_pkg2_before=$(rdmsr -a $MSR_PKG2 2>/dev/null)
  test_print_trc "MSR_PKG_C2_RESIDENCY before: $msr_pkg2_before"

  sleep $time_to_enter_pc2

  columns="Core,CPU,CPU%c1,CPU%c6,Pkg%pc2,Pkg%pc6"
  turbostat_output=$(turbostat -i 10 --quiet --show $columns sleep 10 2>&1)
  test_print_trc "turbostat log: $turbostat_output"

  pc2_val=$(echo "$turbostat_output" | awk '/^-/{print $5}')
  msr_pkg2_after=$(rdmsr -a $MSR_PKG2 2>/dev/null)
  test_print_trc "MSR_PKG_C2_RESIDENCY after: $msr_pkg2_after"

  [[ -n $pc2_val ]] || block_test "PC2 was not detected by the turbostat tool.
Please check the turbostat tool version or if the BIOS has disabled Pkg cstate."
  test_print_trc "PC2 residency for all CPUs: $pc2_val"
  test_print_trc "MSR_PKG_CST_CONFIG_CONTROL: $pkg_cst_ctl"

  if [ "$(echo "scale=2; $pc2_val > 0.01" | bc)" -eq 1 ]; then
    test_print_trc "The system successfully enters the runtime PC2 state."
  else
    die "The system fails to enter the runtime PC2 state."
  fi
}

# Function to check if the server platform can enter the runtime PC6 state
# by reading the data using the turbostat tool
runtime_pc6_entry() {
  local pc6_residency=""
  local time_to_enter_pc6=10
  local pkg_limit=""

  # Judge if the deeper pkg cstate is supported
  do_cmd "turbostat --debug -o tc.out sleep 1"
  pkg_limit=$(grep "pkg-cstate-limit=0" tc.out)

  if [[ -n $pkg_limit ]]; then
    block_test "The platform does not support deeper pkg cstate."
  fi

  # Read MSR_PKG_CST_CONFIG_CONTROL: 0xe2
  pkg_cst_ctl=$(rdmsr -a $PKG_CST_CTL 2>/dev/null)

  # Read MSR_PKG_C6_RESIDENCY: 0x3f9
  msr_pkg6_before=$(rdmsr -a $MSR_PKG6 2>/dev/null)
  test_print_trc "MSR_PKG_C6_RESIDENCY before: $msr_pkg6_before"

  sleep $time_to_enter_pc6

  # Check PC6 residency after idling for the specified time
  columns="Core,CPU,CPU%c1,CPU%c6,Pkg%pc2,Pkg%pc6"
  turbostat_output=$(turbostat -i 10 --quiet --show $columns sleep 10 2>&1)
  test_print_trc "turbostat log: $turbostat_output"
  pc6_residency=$(echo "$turbostat_output" | grep -E "^-" | awk '{print $6}')
  msr_pkg6_after=$(rdmsr -a $MSR_PKG6 2>/dev/null)
  test_print_trc "MSR_PKG_C6_RESIDENCY after: $msr_pkg6_after"

  [ -z "$pc6_residency" ] && die "Did not receive PC6 data from the turbostat tool.
Please check the turbostat tool version or if the BIOS has disabled Pkg cstate."
  test_print_trc "PC6 residency for all CPUs: $pc6_residency"
  test_print_trc "MSR_PKG_CST_CONFIG_CONTROL: $pkg_cst_ctl"

  if [ "$(echo "scale=2; $pc6_residency > 0.01" | bc)" -eq 1 ]; then
    test_print_trc "The system has entered the runtime PC6 state."
  else
    die "The system has failed to enter the runtime PC6 state."
  fi
}

# Function to check runtime PC6 residency and stability
runtime_pc6_residency() {
  local pkg_limit=""

  # Judge if the deeper pkg cstate is supported
  do_cmd "turbostat --debug -o tc.out sleep 1"
  pkg_limit=$(grep "pkg-cstate-limit=0" tc.out)

  if [[ -n $pkg_limit ]]; then
    block_test "The platform does not support deeper pkg cstate."
  fi

  pkg_cst_ctl=$(rdmsr -a $PKG_CST_CTL 2>/dev/null)

  for ((i = 1; i <= 10; i++)); do
    columns="Core,CPU,CPU%c1,CPU%c6,Pkg%pc2,Pkg%pc6"
    turbostat_output=$(turbostat -i 10 --quiet --show $columns sleep 10 2>&1)
    test_print_trc "turbostat log: $turbostat_output"
    pc6_res=$(echo "$turbostat_output" | awk '/^-/{print $6}')

    if (($(echo "$pc6_res > 90.01" | bc -l))); then
      test_print_trc "Cycle $i: The system enters runtime PC6 state with good residency (>90%)"
    elif (($(echo "$pc6_res > 70.01" | bc -l))); then
      test_print_trc "Cycle $i: The system enters runtime PC6 state but with less than 90% residency"
    elif (($(echo "$pc6_res > 5.01" | bc -l))); then
      die "Cycle $i: The system enters runtime PC6 state with low residency"
    else
      die "Cycle $i: The system fails to enter runtime PC6 state or the residency is extremely low"
    fi
  done
}

# Function to do CPU offline and online short stress
cpu_off_on_stress() {
  local cycle=$1
  local dmesg_log

  last_dmesg_timestamp

  cpu_num=$(lscpu | grep "On-line CPU" | awk '{print $NF}' | awk -F "-" '{print $2}')
  [ -n "$cpu_num" ] || block_test "On-line CPU is not available."
  test_print_trc "The max CPU number is: $cpu_num "

  for ((i = 1; i <= cycle; i++)); do
    test_print_trc "CPUs offline online stress cycle$i"
    for ((j = 1; j <= cpu_num; j++)); do
      do_cmd "echo 0 > /sys/devices/system/cpu/cpu$j/online"
    done
    sleep 1
    for ((j = 1; j <= cpu_num; j++)); do
      do_cmd "echo 1 > /sys/devices/system/cpu/cpu$j/online"
    done
  done

  dmesg_log=$(extract_case_dmesg)
  if echo "$dmesg_log" | grep -iE "fail|Call Trace|error|BUG|err"; then
    die "Kernel dmesg shows failure after CPU offline/online stress: $dmesg_log"
  else
    test_print_trc "Kernel dmesg shows Okay after CPU offline/online stress."
  fi
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

core_cstate_test() {
  case $TEST_SCENARIO in
  verify_cstate_name)
    test_cstate_table_name
    ;;
  verify_cstate_switch)
    test_cstate_switch_intel_idle
    ;;
  verify_client_core_c7_residency_during_runtime)
    test_cpu_core_c7_residency_intel_idle
    ;;
  verify_client_core_c7_residency_during_s2idle)
    test_cpu_core_c7_residency_intel_s2idle
    ;;
  verify_client_pkg6_by_disabling_cc8)
    disable_cc_check_pc C8 Pkg%pc6 Pkg%pc8
    ;;
  verify_client_pkg8_by_disabling_cc10)
    disable_cc_check_pc C10 Pkg%pc8 Pk%pc10
    ;;
  verify_cstate_list_by_perf)
    perf_client_cstate_list
    ;;
  verify_residency_latency_override)
    override_residency_latency
    ;;
  verify_server_core_cstate6_residency)
    test_cpu_core_c6_residency_intel_idle
    ;;
  verify_server_all_cores_cstate6)
    test_server_all_cpus_deepest_cstate
    ;;
  verify_server_all_cpus_mc6)
    test_server_all_cpus_mc6
    ;;
  verify_server_cstate_list)
    perf_server_cstate_list
    ;;
  verify_server_perf_core_cstat_update)
    perf_server_cstat_update cstate_core
    ;;
  verify_server_perf_pkg_cstat_update)
    perf_server_cstat_update cstate_pkg
    ;;
  verify_server_perf_module_cstat_update)
    perf_server_cstat_update cstate_module
    ;;
  verify_server_pc2_entry)
    runtime_pc2_entry
    ;;
  verify_server_pc6_entry)
    runtime_pc6_entry
    ;;
  verify_server_pc6_residency)
    runtime_pc6_residency
    ;;
  verify_cpu_offline_online_stress)
    cpu_off_on_stress 5
    ;;
  *)
    block_test "Wrong Case Id is assigned: $CASE_ID"
    ;;
  esac
}

core_cstate_test
