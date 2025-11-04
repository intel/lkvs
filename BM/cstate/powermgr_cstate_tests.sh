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
  turbostat -q sleep 1 1>/dev/null || block_test "Failed to run turbostat tool,
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

# msr-tools is required to run this cstate pc case
if which rdmsr 1>/dev/null 2>&1; then
  test_print_trc "rdmsr tool is available."
else
  block_test "msr-tools is required to run CSTATE cases."
fi

# stress tool is required to run cstate cases
if which stress 1>/dev/null 2>&1; then
  stress --help 1>/dev/null || block_test "Failed to run stress tool,
please check stress tool error message."
else
  block_test "stress tool is required to run cstate cases,
please get it from latest upstream kernel-tools."
fi

# This function is used to kill stress process if it is still running.
# We do this to release cpu resource.
do_kill_pid() {
  [[ $# -ne 1 ]] && die "You must supply 1 parameter"
  local upid="$1"
  upid=$(ps -e | awk '{if($1~/'"$upid"'/) print $1}')
  [[ -n "$upid" ]] && do_cmd "kill -9 $upid"
}

# Function to check tuned.service is enabled or disabled
# This may impact the cpu frequency when a workload is running
check_tuned_service() {
  # Check the status of tuned.service using systemctl
  if systemctl is-enabled --quiet tuned.service; then
    test_print_trc "tuned.service is enabled, which may change the performance profile and impact the CPU frequency,\
please consider disabling it with the command: 'sudo systemctl disable tuned.service', then reboot the system."
  else
    test_print_trc "tuned.service is disabled, so it will not impact the CPU frequency."
  fi
}

# Function to check if there is any package and core power limitation being asserted
# When CPU Frequency is lower than the expected value.
power_limit_check() {
  pkg_power_limitation_log=$(rdmsr -p 1 0x1b1 -f 11:11 2>/dev/null)
  test_print_trc "The power limitation log from package thermal status 0x1b1 bit 11 is: \
$pkg_power_limitation_log"

  core_power_limitation_log=$(rdmsr -p 1 0x19c -f 11:11 2>/dev/null)
  test_print_trc "The power limitation log from IA32 thermal status 0x19c bit 11 is: \
$core_power_limitation_log"

  hwp_cap_value=$(rdmsr -a 0x771)
  test_print_trc "MSR HWP Capabilities shows: $hwp_cap_value"

  hwp_req_value=$(rdmsr -a 0x774)
  test_print_trc "MSR HWP Request shows: $hwp_req_value"

  core_perf_limit_reason=$(rdmsr -a 0x64f 2>/dev/null)
  test_print_trc "The core perf limit reasons msr 0x64f value is: $core_perf_limit_reason"

  if [ "${pkg_power_limitation_log}" == "1" ] && [ "${core_power_limitation_log}" == "1" ]; then
    return 0
  else
    return 1
  fi
}

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

  perf_cstates=$(perf list | grep cstate | grep "Kernel PMU event")
  [[ -n "$perf_cstates" ]] || block_test "Did not get cstate events by perf list"
  test_print_trc "perf list shows cstate events: $perf_cstates"
  perf_core_cstate_num=$(perf list | grep "Kernel PMU event" | grep -c cstate_core)
  for ((i = 1; i <= perf_core_cstate_num; i++)); do
    perf_core_cstate=$(perf list | grep "Kernel PMU event" | grep cstate_core | sed -n "$i, 1p")
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

  perf_pkg_cstate_num=$(perf list | grep "Kernel PMU event" | grep -c cstate_pkg)
  for ((i = 1; i <= perf_pkg_cstate_num; i++)); do
    perf_pkg_cstate=$(perf list | grep "Kernel PMU event" | grep cstate_pkg | sed -n "$i, 1p")
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
  tc_out_cstate_list=$(echo "$tc_out" | grep -E "POLL")

  perf_cstates=$(perf list | grep cstate | grep "Kernel PMU event")
  [[ -n "$perf_cstates" ]] || block_test "Did not get cstate events by perf list"
  test_print_trc "perf list shows cstate events: $perf_cstates"
  perf_core_cstate_num=$(perf list | grep "Kernel PMU event" | grep -c cstate_core)
  for ((i = 1; i <= perf_core_cstate_num; i++)); do
    perf_core_cstate=$(perf list | grep "Kernel PMU event" | grep cstate_core | sed -n "$i, 1p")
    if [[ $perf_core_cstate =~ c1 ]] && [[ $tc_out_cstate_list =~ CPU%c1 ]]; then
      test_print_trc "$perf_core_cstate is supported and aligned with turbostat"
    elif [[ $perf_core_cstate =~ c6 ]] && [[ $tc_out_cstate_list =~ CPU%c6 ]]; then
      test_print_trc "$perf_core_cstate is supported and aligned with turbostat"
    else
      die "perf list shows unexpected core_cstate event."
    fi
  done

  perf_pkg_cstate_num=$(perf list | grep "Kernel PMU event" | grep -c cstate_pkg)
  for ((i = 1; i <= perf_pkg_cstate_num; i++)); do
    perf_pkg_cstate=$(perf list | grep "Kernel PMU event" | grep cstate_pkg | sed -n "$i, 1p")
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

  perf_cstates=$(perf list | grep "Kernel PMU event" | grep "$cstate_name" 2>&1)
  perf_cstates_num=$(perf list | grep "Kernel PMU event" | grep -c "$cstate_name" 2>&1)
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

# Function to check if the deepest PC6 counter is available after CPU offline and online
offline_cpu_pc() {
  local pc=$1
  local pc_ori=""
  local pc_af=""
  local cpus_num=""

  cpus_num=$(lscpu | grep "On-line CPU(s) list" | awk -F "-" '{print $NF}' 2>&1)

  test_print_trc "Reading the deepest Package cstate counter before CPU offline"
  pc_ori=$(rdmsr "$pc" 2>&1)
  dec_pc_ori=$((16#$pc_ori))
  if [[ -n "$dec_pc_ori" ]]; then
    test_print_trc "The deepest Package cstate counter before CPU offline is available: $dec_pc_ori"
  else
    die "The deepest Package cstate counter before CPU offline is not available: $dec_pc_ori"
  fi

  # Offline all the CPUs except CPU0
  for ((i = 1; i <= cpus_num; i++)); do
    do_cmd "echo 0 > /sys/devices/system/cpu/cpu$i/online"
  done

  # Read the deepest Package cstate counter residency after CPU offline
  test_print_trc "Reading the deepest Package cstate counter after CPU offline"
  pc_res_bf=$(rdmsr "$pc" 2>&1)
  dec_pc_res_bf=$((16#$pc_res_bf))
  test_print_trc "The deepest Package cstate counter after CPU offline: $dec_pc_res_bf"
  sleep 20
  pc_res_af=$(rdmsr "$pc" 2>&1)
  dec_pc_res_af=$((16#$pc_res_af))
  test_print_trc "The deepest Package cstate counter after CPU offline and idle: $dec_pc_res_af"

  # Online all the CPUs
  for ((i = 1; i <= cpus_num; i++)); do
    do_cmd "echo 1 > /sys/devices/system/cpu/cpu$i/online"
  done

  # Check if the PC6 counter is updated after CPU offline, if offline CPUs are stucked in C1
  # PC6 will not be available
  if [[ -n "$dec_pc_res_bf" ]] && [[ -n "$dec_pc_res_af" ]] && ((dec_pc_res_af > dec_pc_res_bf)); then
    test_print_trc "The deepest Package cstate counter is updated after CPU offline"
  else
    die "The deepest Package cstate counter after CPU offline is not updated."
  fi

  # Recheck the PC6 counter after CPUs online
  test_print_trc "Reading the deepest Package cstate counter after CPU online"
  pc_af=$(rdmsr "$pc" 2>&1)
  dec_pc_af=$((16#$pc_af))
  if [[ -n "$pc_af" ]] && ((dec_pc_af > dec_pc_ori)); then
    test_print_trc "The deepest Package cstate counter after CPU online is updated: $dec_pc_af"
  else
    die "The deepest Package cstate counter after CPU online is not updated: $dec_pc_af"
  fi
}

# Function to check the core cstae residency after CPU1 offline and online
# Server CC1 residency MSR: 0x660, CC6 residency MSR: 0x3fd, TSC MSR: 0x10
ccstate_res_offline_online() {
  local tcs=$1
  local cc1=$2
  local cc6=$3

  tsc_bf=$(rdmsr -p 1 "$tcs" 2>&1)
  cc1_bf=$(rdmsr -p 1 "$cc1" 2>&1)
  cc6_bf=$(rdmsr -p 1 "$cc6" 2>&1)

  tsc_bf_dec=$((16#$tsc_bf))
  cc1_bf_dec=$((16#$cc1_bf))
  cc6_bf_dec=$((16#$cc6_bf))
  test_print_trc "tsc before counter: $tsc_bf_dec"
  test_print_trc "cc1 before counter: $cc1_bf_dec"
  test_print_trc "cc6 before counter: $cc6_bf_dec"

  # Offline CPU1
  do_cmd "echo 0 > /sys/devices/system/cpu/cpu1/online"

  test_print_trc "Sleep 10 seconds:"
  sleep 10

  # Online CPU1
  do_cmd "echo 1 > /sys/devices/system/cpu/cpu1/online"

  tsc_af=$(rdmsr -p 1 "$tcs" 2>&1)
  cc1_af=$(rdmsr -p 1 "$cc1" 2>&1)
  cc6_af=$(rdmsr -p 1 "$cc6" 2>&1)

  tsc_af_dec=$((16#$tsc_af))
  cc1_af_dec=$((16#$cc1_af))
  cc6_af_dec=$((16#$cc6_af))
  test_print_trc "tsc after counter: $tsc_af_dec"
  test_print_trc "cc1 after counter: $cc1_af_dec"
  test_print_trc "cc6 after counter: $cc6_af_dec"

  # Check the residency of CPU1 C1 and CPU1 C6
  # Expect CC6 residency is larger than 90%, CC1 residency is less than 10%
  tsc_delta=$((tsc_af_dec - tsc_bf_dec))
  cc1_delta=$((cc1_af_dec - cc1_bf_dec))
  cc6_delta=$((cc6_af_dec - cc6_bf_dec))
  cc1_res=$((cc1_delta * 100 / tsc_delta))
  cc6_res=$((cc6_delta * 100 / tsc_delta))
  test_print_trc "CPU1 C1 residency: $cc1_res%"
  test_print_trc "CPU1 C6 residency: $cc6_res%"

  if [[ "$cc1_res" -lt 10 ]]; then
    test_print_trc "CPU1 C1 residency is less than 10%"
  else
    die "CPU1 C1 residency is not less than 10%."
  fi

  if [[ "$cc6_res" -gt 90 ]]; then
    test_print_trc "CPU1 C6 residency is larger than 90%"
  else
    die "CPU1 C6 residency is not larger than 90%."
  fi
}

# Function to check one CPU turbo freqency when other CPUs are in active idle state
verify_single_cpu_freq() {
  local stress_pid=""
  local cpu_stat=""
  local max_freq=""
  local current_freq=""
  local delta=0
  local turbo_on=""
  local states=()
  local cpu_no_turbo_mode="/sys/devices/system/cpu/intel_pstate/no_turbo"

  # Get the CPUs num and the deepest idle cstate number
  cpus_num=$(lscpu | grep "On-line CPU(s) list" | awk '{print $NF}' | awk -F "-" '{print $2}')

  # Use a while loop with read -a to read the output into the array
  while IFS= read -r line; do
    states+=("$line")
  done < <(grep . /sys/devices/system/cpu/cpu0/cpuidle/state*/name | awk -F "/" '{print $(NF-1)}')

  length=${#states[@]}

  turbo_on=$(cat "$cpu_no_turbo_mode")

  test_print_trc "Executing stress -c 1 -t 90 & in background"
  taskset -c 0 stress -c 1 -t 90 &
  stress_pid=$!

  cpu_stat_debug=$(turbostat -i 1 sleep 1 2>&1)
  test_print_trc "Turbostat debug output is:"
  test_print_trc "$cpu_stat_debug"
  cpu_stat=$(turbostat -q -i 1 sleep 1 2>&1)
  test_print_trc "Turbostat output is:"
  test_print_trc "$cpu_stat"

  if [[ "$turbo_on" -eq 0 ]]; then
    max_freq=$(echo "$cpu_stat_debug" |
      grep "MHz max turbo" | tail -n 1 | awk '{print $5}')
    test_print_trc "Max_freq_turbo_On: $max_freq"
  else
    max_freq=$(echo "$cpu_stat_debug" |
      grep "base frequency" |
      awk '{print $5}')
    test_print_trc "Max_freq_turbo_off: $max_freq"
  fi

  current_freq=$(echo "$cpu_stat" |
    awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' |
    grep "Bzy_MHz" | awk -F " " '{print $3}')
  do_cmd "do_kill_pid $stress_pid"
  test_print_trc "current freq: $current_freq"
  test_print_trc "max freq: $max_freq"

  [[ -n "$max_freq" ]] || {
    echo "$cpu_stat"
    die "Cannot get the max freq"
  }
  [[ -n "$current_freq" ]] || {
    echo "$cpu_stat"
    die "Cannot get current freq"
  }
  delta=$(awk -v x="$max_freq" -v y="$current_freq" \
    'BEGIN{printf "%.1f\n", x-y}')
  test_print_trc "Delta freq between max_freq and current_freq is:$delta MHz"

  # Enable all the CPUs idle cstate
  for ((i = 0; i < length; i++)); do
    for ((j = 0; j <= cpus_num; j++)); do
      do_cmd "echo 0 > grep . /sys/devices/system/cpu/cpu$j/cpuidle/state$i/disable"
    done
  done

  if [[ $(echo "$delta > 100" | bc) -eq 1 ]]; then
    if power_limit_check; then
      test_print_trc "The package and core power limitation is asserted."
      test_print_trc "$current_freq is lower than $max_freq with power limitation assert"
    else
      test_print_trc "The package and core power limitation is NOT assert."
      check_tuned_service
      die "$current_freq is lower than $max_freq without power limitation assert"
    fi
  else
    test_print_trc "checking single cpu freq when other CPUs are in idle: PASS"
  fi
}

# Function to verify the turbo frequency of a single CPU
# when all CPUs are in P0, L1, C1, or C1E states
turbo_freq_when_idle() {
  local cpu_num=""
  local states=()
  local idle_state=$1

  # Get the CPUs num and the deepest idle cstate number
  cpus_num=$(lscpu | grep "On-line CPU(s) list" | awk '{print $NF}' | awk -F "-" '{print $2}')

  # Use a while loop with read -a to read the output into the array
  while IFS= read -r line; do
    states+=("$line")
  done < <(grep . /sys/devices/system/cpu/cpu0/cpuidle/state*/name | awk -F "/" '{print $(NF-1)}')

  length=${#states[@]}
  test_print_trc "The deepest core cstate num is: $length"

  # Enable the idle state for all the CPUs
  # If test idle state is POLL/C1/C1E, then disable all the other deeper idle cstate
  if [[ "$idle_state" == POLL ]]; then
    for ((i = 1; i < length; i++)); do
      for ((j = 0; j <= cpus_num; j++)); do
        do_cmd "echo 1 > grep . /sys/devices/system/cpu/cpu$j/cpuidle/state$i/disable"
      done
    done
  elif [[ "$idle_state" == C1 ]]; then
    for ((i = 2; i < length; i++)); do
      for ((j = 0; j <= cpus_num; j++)); do
        do_cmd "echo 1 > grep . /sys/devices/system/cpu/cpu$j/cpuidle/state$i/disable"
      done
    done
  elif [[ "$idle_state" == C1E ]]; then
    if grep -q 'C1E' /sys/devices/system/cpu/cpu0/cpuidle/state*/name; then
      for ((i = 3; i < length; i++)); do
        for ((j = 0; j <= cpus_num; j++)); do
          do_cmd "echo 1 > grep . /sys/devices/system/cpu/cpu$j/cpuidle/state$i/disable"
        done
      done
    else
      block_test "The C1E state is not present"
    fi
  fi

  # Run a 100% stress workload exclusively on CPU0 and verify the turbo frequency
  # If the turbo frequency does not meet the expected value
  # Then determine whether a thermal limitation has been reached
  verify_single_cpu_freq
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
  verify_offline_cpu_deepest_pc)
    offline_cpu_pc 0x3f9
    ;;
  verify_ccstate_res_offline_online)
    ccstate_res_offline_online 0x10 0x660 0x3fd
    ;;
  verify_turbo_freq_in_default)
    verify_single_cpu_freq
    ;;
  verify_turbo_freq_in_poll)
    turbo_freq_when_idle POLL
    ;;
  verify_turbo_freq_in_c1)
    turbo_freq_when_idle C1
    ;;
  verify_turbo_freq_in_c1e)
    turbo_freq_when_idle C1E
    ;;
  *)
    block_test "Wrong Case Id is assigned: $CASE_ID"
    ;;
  esac
}

core_cstate_test
