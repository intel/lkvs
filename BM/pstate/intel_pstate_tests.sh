#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation
# @Author   wendy.wang@intel.com
# @Desc     Test script to verify intel_pstate driver functionality
# which is supported on both Intel® client and server platforms
# @History  Created Feb 25 2024 - Created

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

CPU_SYSFS_PATH="/sys/devices/system/cpu"
CPU_BUS_SYSFS_PATH="/sys/bus/cpu/devices/"
CPU_NO_TURBO_NODE="/sys/devices/system/cpu/intel_pstate/no_turbo"

CPU_PSTATE_SYSFS_PATH="/sys/devices/system/cpu/intel_pstate"
CPU_CPUFREQ_SYSFS_PATH="/sys/devices/system/cpu/cpu0/cpufreq"
CPU_PSTATE_ATTR="hwp_dynamic_boost max_perf_pct min_perf_pct no_turbo status"
CPU_CPUFREQ_ATTR="affected_cpus cpuinfo_max_freq cpuinfo_min_freq
  cpuinfo_transition_latency related_cpus scaling_available_governors
  scaling_cur_freq scaling_driver scaling_governor scaling_max_freq
  scaling_min_freq scaling_setspeed"
DEFAULT_SCALING_GOV=$(cat $CPU_SYSFS_PATH/cpu0/cpufreq/scaling_governor)

# rdmsr tool is required to run pstate cases
if which rdmsr 1>/dev/null 2>&1; then
  rdmsr -V 1>/dev/null || block_test "Failed to run rdmsr tool,
please check rdmsr tool error message."
else
  block_test "rdmsr-tool is required to run pstate cases,
please get it from latest upstream kernel-tools."
fi

# Turbostat tool is required to run pstate cases
if which turbostat 1>/dev/null 2>&1; then
  turbostat sleep 1 1>/dev/null || block_test "Failed to run turbostat tool,
please check turbostat tool error message."
else
  block_test "Turbostat tool is required to run pstate cases,
please get it from latest upstream kernel-tools."
fi

# stress tool is required to run pstate cases
if which stress 1>/dev/null 2>&1; then
  stress --help 1>/dev/null || block_test "Failed to run stress tool,
please check stress tool error message."
else
  block_test "stress tool is required to run pstate cases,
please get it from latest upstream kernel-tools."
fi

# x86_energy_perf_policy tool is required to run pstate cases
if which x86_energy_perf_policy 1>/dev/null 2>&1; then
  x86_energy_perf_policy 1>/dev/null || block_test "Failed to run 
x86_energy_perf_policy tool, please check the tool error message."
else
  block_test "x86_energy_perf_policy tool is required to run pstate cases,
please get it from latest upstream tools/power/x86/x86_energy_perf_policy."
fi

sysfs_verify() {
  [ $# -ne 2 ] && die "You must supply 2 parameters, ${0##*/} <TYPE> <PATH>"
  local TYPE="$1"
  local path="$2"
  # If TYPE is not d nor f, set it as e
  if [[ "$TYPE" != "d" ]] && [[ "$TYPE" != "f" ]]; then
    TYPE="e"
  fi

  test -$TYPE "$path" && test_print_trc "$path does exist"
}

intel_pstate_sysfs_attr() {
  local attr

  test_print_trc "Check intel_pstate driver sysfs attribute:"
  for attr in $CPU_PSTATE_ATTR; do
    sysfs_verify f "$CPU_PSTATE_SYSFS_PATH"/"$attr" ||
      die "$attr does not exist!"
  done

  if ! lines=$(ls "$CPU_PSTATE_SYSFS_PATH"); then
    die "intel_pstate sysfs file does not exist!"
  else
    for line in $lines; do
      test_print_trc "$line"
    done
  fi
}

# cpufreq is a generic CPU frequency scaling driver
cpufreq_sysfs_attr() {
  local attr

  test_print_trc "Check cpufreq driver sysfs attribute:"
  for attr in $CPU_CPUFREQ_ATTR; do
    sysfs_verify f "$CPU_CPUFREQ_SYSFS_PATH"/"$attr" ||
      die "$attr does not exist!"
  done

  if ! lines=$(ls "$CPU_CPUFREQ_SYSFS_PATH"); then
    die "cpufreq driver sysfs does not exist!"
  else
    for line in $lines; do
      test_print_trc "$line"
    done
  fi
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

# Function to change scaling_governor
# The scaling_available_governors will be: performance powersave
set_scaling_governor() {
  local mode=$1
  local cpus=""

  test_print_trc "The default scaling governor is: $DEFAULT_SCALING_GOV"

  # Validate mode parameter
  if [[ $mode != "performance" && $mode != "powersave" && $mode != "schedutil" ]]; then
    die "Invalid scaling govencrnor mode. Mode must be 'performance' or 'powersave' or 'schedutil'."
  fi

  # Get the number of CPUs
  cpus=$(ls -d "$CPU_BUS_SYSFS_PATH"/cpu* | wc -l)

  # Set scaling governor for each CPU
  for ((i = 0; i < cpus; i++)); do
    do_cmd "echo $mode >$CPU_SYSFS_PATH/cpu$i/cpufreq/scaling_governor"
  done
}

# This function is used to set intel_pstate to passive mode
set_intel_pstate_mode() {
  local mode=$1

  do_cmd "echo passive > $CPU_PSTATE_SYSFS_PATH/status"
}

# This function is used to kill stress process if it is still running.
# We do this to release cpu resource.
do_kill_pid() {
  [[ $# -ne 1 ]] && die "You must supply 1 parameter"
  local upid="$1"
  upid=$(ps -e | awk '{if($1~/'"$upid"'/) print $1}')
  [[ -n "$upid" ]] && do_cmd "kill -9 $upid"
}

# Function to set CPU Turbo
set_turbo_state() {
  local state=$1

  # Validate input state
  if [[ ! $state =~ ^(0|1)$ ]]; then
    die "Invalid state: $state. Only 0 or 1 allowed."
  fi

  if ! echo "$state" >"$CPU_NO_TURBO_NODE"; then
    # Failed to write, try to load msr module
    if ! modprobe msr; then
      die "Failed to load msr module."
    fi

    # Read the current turbo value
    turbo_value=$(rdmsr 0x1a0 -f 38:38)
    test_print_trc "turbo_value: $turbo_value"

    if [[ $turbo_value -eq $state ]]; then
      test_print_trc "Turbo state is already set to $state"
    else
      die "Failed to write $state to $CPU_NO_TURBO_NODE"
    fi
  fi
}

# Function to verify all the CPUs Frequency when 100% workload running
# With different scaling governor and turbo settings.
check_max_cores_freq() {
  local turbo_on_off=$1
  local mode=$2
  local cpus=""
  local stress_pid=""
  local cpu_stat=""
  local max_freq=""
  local current_freq=""
  local delta=0
  local turbo_on=""

  # enable or disable turbo according to the argument
  if [[ "$turbo_on_off" == "turbo" ]]; then
    set_turbo_state 0
  elif [[ "$turbo_on_off" == "nonturbo" ]]; then
    set_turbo_state 1
  else
    block_test "invalid value for CPU_NO_TURBO_NODE"
  fi

  # select which scaling governor mode to be set
  if [[ "$mode" == "powersave" ]]; then
    set_intel_pstate_mode "active"
    set_scaling_governor "powersave"
  elif [[ "$mode" == "performance" ]]; then
    set_intel_pstate_mode "active"
    set_scaling_governor "performance"
  elif [[ "$mode" == "passive_perf" ]]; then
    set_intel_pstate_mode "passive"
    set_scaling_governor "performance"
  elif [[ "$mode" == "passive_sched" ]]; then
    set_intel_pstate_mode "passive"
    set_scaling_governor "schedutil"
  else
    block_test "invalid mode for scaling governor"
  fi

  turbo_on=$(cat "$CPU_NO_TURBO_NODE")

  cpus=$(ls "$CPU_BUS_SYSFS_PATH" | grep cpu -c)
  stress -c "$cpus" -t 90 &
  stress_pid=$!
  cpu_stat_debug=$(turbostat -i 1 sleep 1 2>&1)
  test_print_trc "Turbostat debug output is:"
  test_print_trc "$cpu_stat_debug"
  cpu_stat=$(turbostat -q -i 1 sleep 1 2>&1)
  test_print_trc "Turbostat output is:"
  test_print_trc "$cpu_stat"

  hybrid_sku=$(echo "$cpu_stat_debug" | grep "MSR_SECONDARY_TURBO_RATIO_LIMIT" 2>&1)
  # The low power cpu on SoC die does not have the cache index3 directory
  # So use this cache index3 information to judge if SUT supports SoC die or not
  cache_index=$(grep . /sys/devices/system/cpu/cpu*/cache/index3/shared_cpu_list | sed -n '1p' |
    awk -F "-" '{print $NF}' 2>&1)
  cache_index=$(("$cache_index" + 1))
  test_print_trc "CPU number from cache index3: $cache_index"
  cpu_list=$(cpuid | grep -c "core type" 2>&1)
  test_print_trc "CPU number from cpuid: $cpu_list"

  if [[ "$turbo_on" -eq 0 ]]; then
    # For SoC die not supported Hybrid SKU
    if [[ -n "$hybrid_sku" ]] && [[ "$cache_index" = "$cpu_list" ]]; then
      pcore_max_turbo=$(echo "$cpu_stat_debug" | grep -A 2 "MSR_TURBO_RATIO_LIMIT" |
        sed -n "2, 1p" | awk '{print $5}' 2>&1)
      test_print_trc "The Pcore max turbo freq is: $pcore_max_turbo MHz"
      ecore_max_turbo=$(echo "$cpu_stat_debug" | grep -A 2 "MSR_SECONDARY_TURBO_RATIO_LIMIT" |
        sed -n "2, 1p" | awk '{print $5}' 2>&1)
      test_print_trc "The Ecore max turbo freq is: $ecore_max_turbo MHz"
      pcore_last=$(cat /sys/devices/system/cpu/types/intel_core_*/cpulist | cut -d - -f 2)
      pcore_1st=$(cat /sys/devices/system/cpu/types/intel_core_*/cpulist | cut -d - -f 1)
      pcore_online=$(("$pcore_last" - "$pcore_1st" + 1))
      test_print_trc "Pcore Online CPUs:$pcore_online"
      ecore_last=$(cat /sys/devices/system/cpu/types/intel_atom_*/cpulist | cut -d - -f 2)
      ecore_1st=$(cat /sys/devices/system/cpu/types/intel_atom_*/cpulist | cut -d - -f 1)
      ecore_online=$(("$ecore_last" - "$ecore_1st" + 1))
      test_print_trc "Ecore online CPUs:$ecore_online"
      cpus_online=$(("$pcore_online" + "$ecore_online"))
      test_print_trc "Online CPUs:$cpus_online"
      max_freq=$(echo "scale=2; ($pcore_max_turbo * $pcore_online + $ecore_max_turbo * $ecore_online) / \
      $cpus_online" | bc)
      test_print_trc "The expected average CPU max freq on Hybrid SKU: $max_freq MHz"

      # For SoC die supported Hybrid SKU
    elif [[ -n "$hybrid_sku" ]] && [[ "$cache_index" != "$cpu_list" ]]; then
      test_print_trc "SUT supports SoC die"
      pcore_max_turbo=$(echo "$cpu_stat_debug" | grep -A 2 "MSR_TURBO_RATIO_LIMIT" |
        sed -n "2, 1p" | awk '{print $5}' 2>&1)
      test_print_trc "The Pcore max turbo freq is: $pcore_max_turbo MHz"
      ecore_max_turbo=$(echo "$cpu_stat_debug" | grep -A 2 "MSR_SECONDARY_TURBO_RATIO_LIMIT" |
        sed -n "2, 1p" | awk '{print $5}' 2>&1)
      test_print_trc "The Ecore max turbo freq is: $ecore_max_turbo MHz"
      lp_cpu=$(("$cpu_list" - 1))
      lp_max_turbo_hex=$(rdmsr -p $lp_cpu -f 15:8 0x771)
      lp_max_turbo_dec=$((16#$lp_max_turbo_hex))
      lp_max_turbo_mhz=$(("$lp_max_turbo_dec" * 100))
      test_print_trc "The low power core max turbo freq is $lp_max_turbo_mhz MHz"
      pcore_last=$(cat /sys/devices/system/cpu/types/intel_core_*/cpulist | cut -d - -f 2)
      pcore_1st=$(cat /sys/devices/system/cpu/types/intel_core_*/cpulist | cut -d - -f 1)
      pcore_online=$(("$pcore_last" - "$pcore_1st" + 1))
      test_print_trc "Pcore Online CPUs:$pcore_online"
      ecore_last=$(cat /sys/devices/system/cpu/types/intel_atom_*/cpulist | cut -d - -f 2)
      # Remove 2 low power cores from ecore number
      ecore_last=$(("$ecore_last" - 2))
      ecore_1st=$(cat /sys/devices/system/cpu/types/intel_atom_*/cpulist | cut -d - -f 1)
      ecore_online=$(("$ecore_last" - "$ecore_1st" + 1))
      test_print_trc "Ecore online CPUs:$ecore_online"
      test_print_trc "LP core online number: 2"
      cpus_online=$(("$pcore_online" + "$ecore_online" + 2))
      test_print_trc "Online CPUs:$cpus_online"
      max_freq=$(echo "scale=2; ($pcore_max_turbo * $pcore_online + $ecore_max_turbo * \
      $ecore_online + $lp_max_turbo_mhz * 2) / $cpus_online" | bc)
      test_print_trc "The expected average CPU max freq on Hybrid SKU: $max_freq MHz"

      # For non-Hybrid SKU
    else
      max_freq=$(echo "$cpu_stat_debug" |
        grep "MHz max turbo" | head -n 1 | awk '{print $5}')
      test_print_trc "Max_freq_turbo_On on non-Hybrid SKU: $max_freq MHz"
    fi
  else
    max_freq=$(echo "$cpu_stat_debug" |
      grep "base frequency" |
      awk '{print $5}')
    test_print_trc "Max_freq_turbo_off: $max_freq MHz"
  fi

  current_freq=$(echo "$cpu_stat" |
    awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' |
    grep "Bzy_MHz" | awk -F " " '{print $2}')

  test_print_trc "current freq: $current_freq MHz"
  test_print_trc "expected max freq: $max_freq MHz"

  if [[ -n "$stress_pid" ]]; then
    do_cmd "do_kill_pid $stress_pid"
  fi

  [[ -n "$max_freq" ]] || {
    set_scaling_governor $DEFAULT_SCALING_GOV
    echo "$cpu_stat"
    die "Cannot get the max freq"
  }
  [[ -n "$current_freq" ]] || {
    set_scaling_governor $DEFAULT_SCALING_GOV
    echo "$cpu_stat"
    die "Cannot get current freq"
  }
  delta=$(awk -v x="$max_freq" -v y="$current_freq" \
    'BEGIN{printf "%.1f\n", x-y}')

  if [[ $(echo "$delta > 200" | bc) -eq 1 ]]; then
    if power_limit_check; then
      set_scaling_governor $DEFAULT_SCALING_GOV
      test_print_trc "The package and core power limitation is being asserted."
      test_print_trc "$current_freq is lower than $max_freq with power limitation asserted"
    else
      set_scaling_governor $DEFAULT_SCALING_GOV
      test_print_trc "The package and core power limitation is NOT being asserted."
      check_tuned_service
      die "$current_freq is lower than $max_freq without power limitation asserted"
    fi
  else
    set_scaling_governor $DEFAULT_SCALING_GOV
    test_print_trc "No thermal limitation, check all CPUs freq: PASS"
  fi
}

# Function to get max turbo frequency and base frequency from tubostat debug log
get_max_freq() {
  local turbo_state=""

  turbo_state=$(cat "$CPU_SYSFS_PATH"/intel_pstate/no_turbo) ||
    die "Failed to get turbo status"
  test_print_trc "Get cpu_state from turbostat:"
  cpu_stat=$(turbostat sleep 1 2>&1)
  test_print_trc "$cpu_stat"

  hybrid_sku=$(echo "$cpu_stat" | grep "MSR_SECONDARY_TURBO_RATIO_LIMIT")
  test_print_trc "Hybrid SKU status: $hybrid_sku"
  if [ "$turbo_state" -eq 0 ]; then
    if [ -n "$hybrid_sku" ]; then
      max_freq=$(echo "$cpu_stat" | grep -B 1 "MSR_SECONDARY_TURBO_RATIO_LIMIT" |
        head -1 | awk '{print $5}' 2>&1)
      test_print_trc "Max_freq_turbo_On on Hybrid SKU: $max_freq MHz"
    else
      max_freq=$(echo "$cpu_stat" | grep "max turbo" | awk 'END {print}' | awk '{print $5}')
      test_print_trc "Turbo is enabled, the supported max freq is:$max_freq MHz"
    fi
  else
    max_freq=$(echo "$cpu_stat" |
      grep "base frequency" |
      awk '{print $5}')
    test_print_trc "Turbo is disabled, the supported max freq is:$max_freq MHz"
  fi

  return 0
}

# Function to get turbostat logs
get_cpu_stat() {
  local cpu_stat=""

  columns="Core,CPU,Avg_MHz,Busy%,Bzy_MHz,PkgWatt"
  cpu_stat=$(turbostat -c 1 --show $columns -i 10 sleep 30 2>&1)
  echo "$cpu_stat"
}

# Function to get CPU frequency for tubo disable and enable
check_pstate_turbo() {
  local turbo_state=""
  local stress_pid=""
  local cpu_stat=""
  local cpu_freq_noturbo=""
  local cpu_freq_turbo=""

  # Save turbo state, after test has finished, restore it
  turbo_state=$(cat $CPU_SYSFS_PATH/intel_pstate/no_turbo)

  # Disable turbo mode
  test_print_trc "Disable turbo mode"
  do_cmd "echo 1 > $CPU_SYSFS_PATH/intel_pstate/no_turbo"
  test_print_trc "Executing stress -c 1 -t 90 & in background"
  taskset -c 1 stress -c 1 -t 90 &
  stress_pid=$!
  test_print_trc "Executing turbostat --show Core,CPU,Avg_MHz,Busy%,Bzy_MHz,PkgWatt -i 10 sleep 30 2>&1"
  cpu_stat=$(get_cpu_stat)
  echo -e "turbostat is:\n"
  echo -e "$cpu_stat\n"
  test_print_trc "Getting freq of cpu1 from turbostat"
  cpu_freq_noturbo=$(echo "$cpu_stat" | grep -E "^-" -A 2 | sed -n "2, 1p" | awk '{print $5}')
  test_print_trc "Actual max freq of cpu1 is: $cpu_freq_noturbo Mhz, \
when turbo mode is disabled and cpu1 has 100% workload"
  [ -n "$stress_pid" ] && do_cmd "do_kill_pid $stress_pid"

  # Enable turbo mode
  test_print_trc "Enable turbo mode"
  do_cmd "echo 0 > $CPU_SYSFS_PATH/intel_pstate/no_turbo"
  test_print_trc "Executing stress -c 1 -t 90 & in background"
  taskset -c 1 stress -c 1 -t 90 &
  stress_pid=$!
  test_print_trc "Executing turbostat --show Core,CPU,Avg_MHz,Busy%,Bzy_MHz,PkgWatt -i 10 sleep 30 2>&1"
  cpu_stat=$(get_cpu_stat)
  echo -e "turbostat is:\n"
  echo -e "$cpu_stat\n"
  test_print_trc "Getting cpu freq from turbostat"
  cpu_freq_turbo=$(echo "$cpu_stat" | grep -E "^-" -A 2 | sed -n "2, 1p" | awk '{print $5}')
  test_print_trc "Actual max freq of cpu1 is: $cpu_freq_turbo Mhz, \
when turbo mode is enabled and cpu1 has 100% workload"

  if [[ -n "$stress_pid" ]]; then
    do_cmd "do_kill_pid $stress_pid"
  fi

  # Restore the turbo setting
  echo "$turbo_state" >"$CPU_SYSFS_PATH"/intel_pstate/no_turbo

  if [[ $cpu_freq_noturbo -lt $cpu_freq_turbo ]]; then
    test_print_trc "CPU freq of cpu1 is larger when turbo is enabled than disabled, PASS"
    return 0
  else
    die "CPU freq of cpu1 is less when turbo is enabled than disabled, FAIL"
  fi
}

# $1: pct_type: min or max
# $2: value to change max/min_perf_pct
# $3: load_flag: indicate that if cpu should have 100% workload
check_perf_pct() {
  if [ $# -ne 3 ]; then
    die "You must supply 3 parameters"
  fi

  local pct_type="$1"
  local value="$2"
  local load_flag="$3"

  #Save scaling_governor setting of each cpu, so that we can restore it after the case has finished
  if [[ $pct_type != "min" && $pct_type != "max" ]]; then
    die "The first parameter - pct_type must be 'min' or 'max'"
  fi

  if [[ ! $value =~ ^[0-9]+$ || $value -lt 0 || $value -gt 100 ]]; then
    die "The second parameter - value must be a positive integer between 0 and 100"
  fi

  if [[ $load_flag != "1" && $load_flag != "0" ]]; then
    die "The third parameter - load_flag must be '1' or '0'"
  fi

  local pct_type_sysfs=""
  local org_value=""
  local new_value=""
  local cpu_stat=""
  local stress_pid=""

  # Save perf_pct_value before changing it
  pct_type_sysfs="${pct_type}_perf_pct"
  org_value=$(cat "$CPU_SYSFS_PATH/intel_pstate/$pct_type_sysfs")
  test_print_trc "The original $pct_type_sysfs value is $org_value, now setting it to $value"
  echo "$value" >"$CPU_SYSFS_PATH/intel_pstate/$pct_type_sysfs"
  new_value=$(cat "$CPU_SYSFS_PATH/intel_pstate/$pct_type_sysfs")
  test_print_trc "$pct_type_sysfs value has been set to $new_value"

  if [[ $load_flag == "1" ]]; then
    test_print_trc "Executing 'stress -c 1 -t 100 &' in background"
    taskset -c 1 stress -c 1 -t 100 &
    stress_pid=$!
  fi

  test_print_trc "Executing turbostat --show Core,CPU,Avg_MHz,Busy%,Bzy_MHz,PkgWatt -i 10 sleep 30 2>&1"
  cpu_stat=$(get_cpu_stat)
  echo -e "turbostat is:\n"
  echo -e "$cpu_stat\n"

  test_print_trc "Getting freq of cpu1 from turbostat"
  CPU_FREQ_CUR=$(echo "$cpu_stat" | grep -E "^-" -A 2 | sed -n "2, 1p" | awk '{print $5}')

  if [[ -n "$stress_pid" ]]; then
    do_cmd "do_kill_pid $stress_pid"
  fi

  # Covert Mhz to Khz.
  CPU_FREQ_CUR=$(echo "$CPU_FREQ_CUR * 1000" | bc)
  test_print_trc "Actual freq of cpu1 when $pct_type_sysfs has been set as $value is $CPU_FREQ_CUR Khz."

  #restore max_perf_pct or min_perf_pct every time.
  do_cmd "echo $org_value > $CPU_SYSFS_PATH/intel_pstate/$pct_type_sysfs"

  return 0
}

# $1: flag
# flag can be 1,performance and powersave.
# If flag=1: Restore scaling_governor setting. The setting is saved in global variable $GOVERNOR_STATES
# If flag=performance or powersave: It means we are intending to change scaling_governor setting.
change_governor() {
  if [ $# -ne 1 ]; then
    die "You must supply 1 parameter"
  fi

  local flag="$1"
  local cpus
  cpus=$(ls "$CPU_SYSFS_PATH" | grep "cpu[0-9]\+") || die "Failed to get CPUs from sysfs"

  if [ "$flag" = "1" ]; then
    # Restoring original governor settings from the global variable $GOVERNOR_STATES
    test_print_trc "Restoring scaling_governor settings"
    local cnt=0
    for cpu in $cpus; do
      if [ -n "${GOVERNOR_STATES[$cnt]}" ]; then
        echo "${GOVERNOR_STATES[$cnt]}" >"$CPU_SYSFS_PATH"/"$cpu"/cpufreq/scaling_governor
      fi
      cnt=$((cnt + 1))
    done
  elif [ "$flag" = "performance" ] || [ "$flag" = "powersave" ]; then
    # Changing scaling_governor setting to the specified mode
    test_print_trc "Changing scaling_governor setting to $flag"
    local current_governor
    for cpu in $cpus; do
      current_governor=$(cat "$CPU_SYSFS_PATH/$cpu/cpufreq/scaling_governor")
      GOVERNOR_STATES+=" $current_governor"
      echo "$flag" >"$CPU_SYSFS_PATH"/"$cpu"/cpufreq/scaling_governor
    done
  else
    die "The parameter must be '1', 'performance' or 'powersave'"
  fi
}

# $1: flag
# flag can be performance, balance_performance, balance_power and power.
# If flag=performance, balance_performance, balance_power or power:
# It means we are intending to change energy_performance_preference setting.
change_epp() {
  if [ $# -ne 1 ]; then
    die "You must supply 1 parameter"
  fi

  local flag="$1"
  local cpus
  cpus=$(ls "$CPU_SYSFS_PATH" | grep "cpu[0-9]\+") || die "Failed to get CPUs from sysfs"

  if [ "$flag" = "performance" ] || [ "$flag" = "balance_performance" ] ||
    [ "$flag" = "power" ] || [ "$flag" = "balance_power" ]; then
    test_print_trc "Changing energy_performance_preference setting to $flag"
    for cpu in $cpus; do
      do_cmd "echo $flag > $CPU_SYSFS_PATH/$cpu/cpufreq/energy_performance_preference"
      local epp_state
      epp_state=$(cat "$CPU_SYSFS_PATH/$cpu/cpufreq/energy_performance_preference")
      if [ "$flag" != "$epp_state" ]; then
        die "Failed to change energy_performance_preference setting to $flag"
      fi
    done
  else
    die "The parameter must be 'performance', 'balance_performance', 'balance_power' or 'power'"
  fi
}

# $1: actual_freq: The actual freq got by turbostat
# $2: cmp_freq:
# $3: compare_type: eq or gt
compare_freq() {
  if [ $# -ne 3 ]; then
    die "You must supply 3 parameters"
  fi

  local actual_freq="$1"
  local cmp_freq="$2"
  local cmp_type="$3"

  if ! [[ $actual_freq =~ ^[0-9]+$ ]]; then
    die "The first parameter -- actual_freq must be a positive integer"
  fi

  if ! [[ $cmp_freq =~ ^[0-9]+$ ]]; then
    die "The second parameter -- cmp_freq must be a positive integer"
  fi

  if [[ ! "$cmp_type" =~ ^(eq|gt)$ ]]; then
    die "The third parameter -- cmp_type must be eq or gt"
  fi

  case $cmp_type in
  eq)
    local expected_freq_high
    local expected_freq_low
    expected_freq_high=$((cmp_freq + 100000))
    expected_freq_low=$((cmp_freq - 100000))
    test_print_trc "Acceptable reference freq with 100000Khz error is: \
$expected_freq_low Khz to $expected_freq_high Khz"
    if [[ $actual_freq -lt $expected_freq_low || $actual_freq -gt $expected_freq_high ]]; then
      if [[ $actual_freq -lt $expected_freq_low && "$MSR_THERM_PL" == "c" ]]; then
        test_print_trc "Since RAPL limitation is working, actual freq of \
cpu1 may not reach the expected limitation"
      else
        die "The error between actual freq and expected freq is larger than 100 Mhz (100000Khz)"
      fi
    fi
    ;;
  gt)
    local expected_freq
    expected_freq=$((cmp_freq - 100000))
    test_print_trc "Acceptable reference freq with 100000Khz error is: $expected_freq"
    if [[ $actual_freq -le $expected_freq ]]; then
      die "The error between actual freq and expected freq is larger than 100 Mhz (100000Khz)"
    fi
    ;;
  esac
}

# Function to do CPUs hotplug
cpu_hotplug() {
  local online_cpu=""
  local cpuset_is_mounted=""

  online_cpu=$(grep -c "^processor" /proc/cpuinfo) || die "Failed to get online CPUs"

  # Hot unplug all logic CPUs except cpu0
  for ((cpu = 1; cpu < online_cpu; cpu++)); do
    test_print_trc "Hot unplug CPU$cpu"
    do_cmd "echo 0 > $CPU_SYSFS_PATH/cpu$cpu/online"
  done

  sleep 10

  # Hot plug all logic CPUs except cpu0
  for ((cpu = 1; cpu < online_cpu; cpu++)); do
    test_print_trc "Hot plug CPU$cpu"
    do_cmd "echo 1 > $CPU_SYSFS_PATH/cpu$cpu/online"
  done

  sleep 10

  # Restore cpuset setting if cpuset pseudo filesystem is mounted
  cpuset_is_mounted=$(grep "/sys/fs/cgroup/cpuset" /etc/mtab)
  if [ -n "$cpuset_is_mounted" ]; then
    cpu_nr=$((online_cpu - 1))
    # Find all cpuset.cpus file under that folder.
    lists=$(find /sys/fs/cgroup/cpuset/user.slice -name cpuset.cpus 2>/dev/null | sort)
    for setting in $lists; do
      test_print_trc "Write 0-$cpu_nr back to $setting"
      echo "0-$cpu_nr" >"$setting" || die "Failed to write 0-$cpu_nr back to $setting"
    done
  fi

  return 0
}

# Function to check Bzy_MHz before and after CPUs hotplug
cpu_hotplug_check() {
  local cpu_stat_before_hotplug=""
  local bzy_mhz_before=""
  local cpu_stat_after_hotplug=""
  local bzy_mhz_after=""
  local delta=0
  local columns=""

  columns="Core,CPU,Avg_MHz,Busy%,Bzy_MHz"

  test_print_trc "Read CPU states before hotplug CPU"
  cpu_stat_before_hotplug=$(turbostat --show $columns sleep 10 2>&1)
  test_print_trc "$cpu_stat_before_hotplug"

  if [ -z "$cpu_stat_before_hotplug" ]; then
    die "Cannot read CPU states before hotplug CPU, FAIL"
  fi
  bzy_mhz_before=$(echo "$cpu_stat_before_hotplug" | awk '/^-/ {print $5}')
  test_print_trc "Bzy_MHz before CPU hotplug is: $bzy_mhz_before"

  cpu_hotplug

  test_print_trc "Read CPU states after hotplug CPU"
  cpu_stat_after_hotplug=$(turbostat --show $columns sleep 10 2>&1)
  test_print_trc "$cpu_stat_after_hotplug"

  if [ -z "$cpu_stat_after_hotplug" ]; then
    die "Cannot read CPU states after hotplug CPU, FAIL"
  fi
  bzy_mhz_after=$(echo "$cpu_stat_after_hotplug" | awk '/^-/ {print $5}')
  test_print_trc "Bzy_MHz after CPU hotplug is: $bzy_mhz_after"

  delta=$((bzy_mhz_after - bzy_mhz_before))
  if [ ${delta#-} -gt 100 ]; then
    die "Bzy_MHz has changed more than 100Mhz after CPU hotplug, FAIL"
  fi
  test_print_trc "Hotplug CPU PASS"

  return 0
}

# Function to check HWP CAP and REQ before and after CPUs hotplug
hwp_cpu_hotplug_check() {
  local CAP_before_cpu_hotplug=""
  local REQ_before_cpu_hotplug=""
  local CAP_after_cpu_hotplug=""
  local REQ_after_cpu_hotplug=""

  test_print_trc "Read HWP CAP and HWP REQ before CPU hotplug"
  CAP_before_cpu_hotplug=$(rdmsr 0x771 2>/dev/null)
  if [ -z "$CAP_before_cpu_hotplug" ]; then
    die "Not get HWP CAP value before CPU hotplug, FAIL"
  fi
  test_print_trc "HWP CAP before is: $CAP_before_cpu_hotplug"
  REQ_before_cpu_hotplug=$(rdmsr 0x774 2>/dev/null)
  if [ -z "$REQ_before_cpu_hotplug" ]; then
    die "Not get HWP REQ before CPU hotplug, FAIL"
  fi
  test_print_trc "HWP REQ before is: $REQ_before_cpu_hotplug"

  cpu_hotplug

  test_print_trc "Read HWP CAP and HWP REQ after CPU hotplug"
  CAP_after_cpu_hotplug=$(rdmsr 0x771 2>/dev/null)
  if [ -z "$CAP_after_cpu_hotplug" ]; then
    die "Not get CAP after CPU hotplug, FAIL"
  fi
  test_print_trc "HWP CAP after is: $CAP_after_cpu_hotplug"
  REQ_after_cpu_hotplug=$(rdmsr 0x774 2>/dev/null)
  if [ -z "$REQ_after_cpu_hotplug" ]; then
    die "Not get REQ after CPU hotplug, FAIL"
  fi
  test_print_trc "HWP REQ after is: $REQ_after_cpu_hotplug"

  if [ "$REQ_before_cpu_hotplug" != "$REQ_after_cpu_hotplug" ]; then
    die "HWP REQ has changed after CPU hotplug"
  fi
  test_print_trc "HWP REQ and HWP CAP CPU hotplug case PASS"

  return 0
}

# $1:case_flag
check_epp_req() {
  local case_flag="$1"
  local ret_num=0
  local stress_pid=""
  local num_cpus=""
  local cpu_model=""

  cpu_model=$(lscpu | grep Model: | awk '{print $2}')
  test_print_trc "CPU Model is: $cpu_model"

  num_cpus=$(ls -d /sys/devices/system/cpu/cpu[0-9]* | wc -l) ||
    die "Failed to get cpus number from sysfs"
  test_print_trc "CPU numbers: $num_cpus"
  test_print_trc "Give all the CPUs 100% work load"
  stress -c "$num_cpus" -t 50 &
  stress_pid=$!

  case $case_flag in
  default)
    epp_req=0
    ;;

  performance)
    epp_req=0
    ;;
  # SPR will use 32 for balance_performance EPP value
  balance_performance)
    if [ "$cpu_model" == 143 ]; then
      epp_req=32
    else
      epp_req=128
    fi
    ;;

  balance_power)
    epp_req=192
    ;;

  power)
    epp_req=255
    ;;
  esac
  for ret_num in $(x86_energy_perf_policy --cpu all | grep "cpu" | grep -oP '\d+ (?=window)'); do
    test_print_trc "$ret_num"
    [ "$ret_num" == "$epp_req" ] || die "check_epp_req FAIL: it should be $epp_req, but $ret_num"
  done
  test_print_trc " check_epp_req PASS"

  if [[ -n "$stress_pid" ]]; then
    do_cmd "do_kill_pid $stress_pid"
  fi
}

# Function to check cpufreq when scaling_governor set to performance
# And max_perf_pct change to the min_perf_pct
check_governor_perf() {
  local actual_freq_orig=""
  local actual_freq_cur=""
  local min_perf_pct=""

  min_perf_pct=$(cat $CPU_SYSFS_PATH/intel_pstate/min_perf_pct)

  # Check actual CPU freq of CPU1 with different max_perf_pct setting under
  # performance scaling_governor setting
  # First min_perf_pct -> max_perf_pct, no need to restore scaling_governor setting
  test_print_trc "Now change scaling_governor to performance, change max_perf_pct to $min_perf_pct"
  do_cmd "change_governor performance"

  check_perf_pct max "$min_perf_pct" 1 || die
  actual_freq_orig="$CPU_FREQ_CUR"
  #Then 100 -> max_perf_pct, restore scaling_governor setting
  test_print_trc "Now change scaling_governor to performance, change max_perf_pct to 100"
  check_perf_pct max 100 1 || die

  do_cmd "change_governor 1"

  actual_freq_cur="$CPU_FREQ_CUR"
  test_print_trc "Actual_freq_cur:$actual_freq_cur"
  test_print_trc "Actual_freq_original:$actual_freq_orig"

  compare_freq "$actual_freq_cur" "$actual_freq_orig" gt ||
    die "Actual freq of cpu1 with max_perf_pct=100 is less than \
actual freq with max_perf_pct=$min_perf_pct, FAIL"
  test_print_trc "Actual freq of cpu1 with max_perf_pct=100 is larger than \
actual freq with max_perf_pct=$min_perf_pct, PASS"
}

# Function to check cpufreq when scaling_governor set to powersave
# And max_perf_pct change to the min_perf_pct
check_governor_powersave() {
  local actual_freq_orig=""
  local actual_freq_cur=""
  local min_perf_pct=""

  min_perf_pct=$(cat $CPU_SYSFS_PATH/intel_pstate/min_perf_pct)

  # Check actual CPU freq of CPU1 with different max_perf_pct setting under
  # powersave scaling_governor
  # First min_perf_pct -> max_perf_pct, no need to restore scaling_governor setting
  test_print_trc "Now change scaling_governor to powersave, change max_perf_pct to $min_perf_pct"
  do_cmd "change_governor powersave"

  check_perf_pct max "$min_perf_pct" 1 || die
  actual_freq_orig="$CPU_FREQ_CUR"
  # Then 100 -> max_perf_pct, restore scaling_governor setting
  test_print_trc "Now change scaling_governor to powersave, change max_perf_pct to 100"
  check_perf_pct max 100 1 || die

  do_cmd "change_governor 1"

  actual_freq_cur="$CPU_FREQ_CUR"
  test_print_trc "Actual_freq_cur:$actual_freq_cur"
  test_print_trc "Actual_freq_original:$actual_freq_orig"
  compare_freq "$actual_freq_cur" "$actual_freq_orig" gt ||
    die "Actual freq of cpu1 with max_perf_pct=100 is less than \
actual freq with max_perf_pct=$min_perf_pct, FAIL"
  test_print_trc "Actual freq of cpu1 with max_perf_pct=100 is larger than \
actual freq with max_perf_pct=$min_perf_pct, PASS"
}

# Function to check cpufreq when max_perf_pct is set to 50% of max_perf_pct
check_maxperfpct_50() {
  local pct=""
  local min_perf_pct=""
  local max_perf_pct=""
  local actual_freq_cur=""
  local platform_base_freq=""
  local expected_freq=""
  local max_freq=""

  min_perf_pct=$(cat $CPU_SYSFS_PATH/intel_pstate/min_perf_pct)
  max_perf_pct=$(cat $CPU_SYSFS_PATH/intel_pstate/max_perf_pct)

  cpu_stat=$(get_cpu_stat)
  echo -e "Original turbostat is:\n"
  echo -e "$cpu_stat\n"

  get_max_freq || block_test

  # max_pert_pct/2 -> max_perf_pct, CPU1 has 100% workload
  pct=$(("$max_perf_pct" / 2))
  [ "$pct" -lt "$min_perf_pct" ] && pct=$min_perf_pct
  test_print_trc "Now change scaling_governor to powersave, change max_perf_pct to $pct"
  do_cmd "change_governor powersave"
  check_perf_pct max "$pct" 1 || die
  do_cmd "change_governor 1"
  actual_freq_cur="$CPU_FREQ_CUR"
  test_print_trc "Actual_freq_cur: $actual_freq_cur KHz"
  platform_base_freq=$(echo "$cpu_stat" |
    grep "base frequency" |
    awk '{print $5}')
  # Covert float to integer
  platform_base_freq=${platform_base_freq%.*}
  echo "platform base freq: $platform_base_freq MHz"
  max_freq=${max_freq%.*}
  expected_freq=$(echo "scale=1;$max_freq * $pct / 100" | bc)
  # Covert float to integer
  expected_freq=${expected_freq%.*}
  echo "original expected freq: $expected_freq MHz"
  [ "$max_freq" -eq "$platform_base_freq" ] && expected_freq=$max_freq
  # Covert Mhz to Khz
  expected_freq=$(echo "$expected_freq * 1000" | bc)
  test_print_trc "Actual Expected_freq: $expected_freq KHz"
  compare_freq "$actual_freq_cur" "$expected_freq" eq ||
    die "Actual freq of cpu1 didn't reach the expected freq when \
max_perf_pct was changed from $max_perf_pct to $pct, FAIL"
  test_print_trc "Actual freq of cpu1 reached the expected freq when \
max_perf_pct was changed from $max_perf_pct to $pct, PASS"
}

# Function to check cpufreq when min_perf_pct is set to 50% of min_perf_pct
check_minperfpct_50() {
  local pct=""
  local min_perf_pct=""
  local max_perf_pct=""
  local actual_freq_cur=""
  local platform_base_freq=""
  local expected_freq=""
  local max_freq=""

  min_perf_pct=$(cat $CPU_SYSFS_PATH/intel_pstate/min_perf_pct)
  max_perf_pct=$(cat $CPU_SYSFS_PATH/intel_pstate/max_perf_pct)

  cpu_stat=$(get_cpu_stat)
  echo -e "Original turbostat is:\n"
  echo -e "$cpu_stat\n"

  get_max_freq || block_test

  # max_perf_pct/2 -> min_perf_pct, CPU1 has 100% workload
  pct=$(("$max_perf_pct" / 2))
  [ $pct -gt "$max_perf_pct" ] && pct=$max_perf_pct
  test_print_trc "Now change scaling_governor to powersave, change min_perf_pct to $pct"
  do_cmd "change_governor powersave"
  check_perf_pct min "$pct" 1 || die
  do_cmd "change_governor 1"
  actual_freq_cur="$CPU_FREQ_CUR"
  test_print_trc "Actual_freq_cur: $actual_freq_cur KHz"
  platform_base_freq=$(echo "$cpu_stat" |
    grep "base frequency" |
    awk '{print $5}')
  # Covert float to integer
  platform_base_freq=${platform_base_freq%.*}
  echo "platform base freq: $platform_base_freq MHz"
  max_freq=${max_freq%.*}
  expected_freq=$(echo "scale=1;$max_freq * $pct / 100" | bc)
  # Covert float to integer
  expected_freq=${expected_freq%.*}
  echo "original expected freq: $expected_freq MHz"
  [ "$max_freq" -eq "$platform_base_freq" ] && expected_freq=$max_freq
  # Covert Mhz to Khz
  expected_freq=$(echo "$expected_freq * 1000" | bc)
  # Covert float to integer
  test_print_trc "Actual Expected_freq: $expected_freq KHz"
  compare_freq "$actual_freq_cur" "$expected_freq" gt ||
    die "Actual freq of cpu1 is less than the expected freq when \
min_perf_pct was changed from $min_perf_pct to $pct, FAIL"
  test_print_trc "Actual freq of cpu1 reached the expected freq when \
min_perf_pct was changed from $min_perf_pct to $pct, PASS"
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

intel_pstate_test() {
  case $TEST_SCENARIO in
  verify_sysfs_atts)
    intel_pstate_sysfs_attr
    cpufreq_sysfs_attr
    ;;
  verify_turbo_enable_disable)
    check_pstate_turbo
    ;;
  verify_cpufreq_after_hotplug)
    cpu_hotplug_check
    ;;
  verify_hwp_cap_req_after_hotplug)
    hwp_cpu_hotplug_check
    ;;
  verify_default_gov_epp)
    change_governor performance || die
    change_epp performance || die
    check_epp_req default || die
    ;;
  verify_gov_perf_epp_perf)
    change_governor performance || die
    change_epp performance || die
    check_epp_req performance || die
    ;;
  verify_gov_powersave_epp_perf)
    change_governor powersave || die
    change_epp performance || die
    check_epp_req performance || die
    ;;
  verify_gov_powersave_epp_balance_perf)
    change_governor powersave || die
    change_epp balance_performance || die
    check_epp_req balance_performance || die
    ;;
  verify_gov_powersave_epp_balance_power)
    change_governor powersave || die
    change_epp balance_power || die
    check_epp_req balance_power || die
    ;;
  verify_gov_powersave_epp_power)
    change_governor powersave || die
    change_epp power || die
    check_epp_req power || die
    ;;
  verify_cpufreq_with_governor_perf)
    check_governor_perf
    ;;
  verify_cpufreq_with_governor_powersave)
    check_governor_powersave
    ;;
  verify_cpufreq_with_maxperfpct_50)
    check_maxperfpct_50
    ;;
  verify_cpufreq_with_minperfpct_50)
    check_minperfpct_50
    ;;
  verify_max_cpufreq_powersave_turbo)
    check_max_cores_freq turbo powersave
    ;;
  verify_max_cpufreq_perf_turbo)
    check_max_cores_freq turbo performance
    ;;
  verify_max_cpufreq_passive_perf_turbo)
    check_max_cores_freq turbo passive_perf
    ;;
  verify_max_cpufreq_passive_sched_turbo)
    check_max_cores_freq turbo passive_sched
    ;;
  verify_max_cpufreq_powersave_non_turbo)
    check_max_cores_freq nonturbo powersave
    ;;
  verify_max_cpufreq_perf_non_turbo)
    check_max_cores_freq nonturbo performance
    ;;
  *)
    block_test "Wrong Case Id is assigned: $CASE_ID"
    ;;
  esac
}

intel_pstate_test
