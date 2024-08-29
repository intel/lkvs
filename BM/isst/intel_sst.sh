#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation
# Description:  Test script for Intel SST feature, which is supported on server platforms
# ISST:Intel Speed Select Technology
# PP: perf-profile
# CP: core-power
# BF: base-freq
# TF: turbo-freq
# @Author   wendy.wang@intel.com
# @History  Created Dec 05 2022 - Created

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

ISST_IF_MMIO_DRIVER_PATH="/sys/module/isst_if_mmio/drivers/pci"
ISST_IF_MBOX_PCI_DRIVER_PATH="/sys/module/isst_if_mbox_pci/drivers/pci"
CPU_SYSFS_PATH="/sys/devices/system/cpu"
COLUMNS="Package,Core,CPU,Busy%,Bzy_MHz,PkgWatt"

# Turbostat tool is required to run ISST cases
if which turbostat 1>/dev/null 2>&1; then
  turbostat sleep 1 1>/dev/null || block_test "Failed to run turbostat tool,
please check turbostat tool error message."
else
  block_test "Turbostat tool is required to run ISST cases,
please get it from latest upstream kernel-tools."
fi

# intel-speed-select tool is required to run ISST cases
if which intel-speed-select 1>/dev/null 2>&1; then
  intel-speed-select --info 1>/dev/null || block_test "Failed to run isst tool,
please check isst tool error message."
else
  block_test "intel-speed-select tool is required to run ISST cases,
please get it from latest upstream kernel-tools."
fi

# stress tool is required to run ISST cases
if which stress 1>/dev/null 2>&1; then
  stress --help 1>/dev/null || block_test "Failed to run stress tool,
please check stress tool error message"
else
  block_test "stress tool is required to run ISST cases,
please get it from latest upstream kernel-tools."
fi

: "${CASE_NAME:=""}"

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-t TESTCASE_ID] [-H]
  -t  TEST CASE ID
  -H  show this
__EOF
}

isst_legacy_driver_interface() {
  test_print_trc "Check ISST_IF_MMIO driver interface:"

  [[ -d "$ISST_IF_MMIO_DRIVER_PATH":isst_if_pci ]] ||
    die "ISST_IF_MMIO driver SYSFS does not exist!"

  lines=$(ls "$ISST_IF_MMIO_DRIVER_PATH":isst_if_pci 2>&1)
  for line in $lines; do
    test_print_trc "$line"
  done

  test_print_trc "Check ISST_IF_MBOX_PCI driver interface:"

  [[ -d "$ISST_IF_MBOX_PCI_DRIVER_PATH":isst_if_mbox_pci ]] ||
    die "ISST_IF_MBOX_PCI driver SYSFS does not exist!"

  lines=$(ls "$ISST_IF_MBOX_PCI_DRIVER_PATH":isst_if_mbox_pci 2>&1)
  for line in $lines; do
    test_print_trc "$line"
  done
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

power_limit_check() {
  pkg_power_limitation_log=$(rdmsr -p 1 0x1b1 -f 11:11 2>/dev/null)
  test_print_trc "The power limitation log from package thermal status 0x1b1 bit 11 is: \
$pkg_power_limitation_log"
  core_power_limitation_log=$(rdmsr -p 1 0x19c -f 11:11 2>/dev/null)
  test_print_trc "The power limitation log from IA32 thermal status 0x19c bit 11 is: \
$core_power_limitation_log"
  hwp_cap_value=$(rdmsr -a 0x771 2>/dev/null)
  test_print_trc "MSR HWP Capabilities shows: $hwp_cap_value"
  hwp_req_value=$(rdmsr -a 0x774 2>/dev/null)
  test_print_trc "MSR HWP Request shows: $hwp_req_value"

  core_perf_limit_reason=$(rdmsr -a 0x64f 2>/dev/null)
  test_print_trc "The core perf limit reasons msr 0x64f value is: $core_perf_limit_reason"
  if [ "$pkg_power_limitation_log" == "1" ] && [ "$core_power_limitation_log" == "1" ]; then
    return 0
  else
    return 1
  fi
}

# Function to check ISST features support status
isst_info() {
  do_cmd "intel-speed-select -o info.out -i"
  test_print_trc "The platform and driver capabilities are:"
  do_cmd "cat info.out"
  isst_pp_cap=$(grep SST-PP info.out | grep "not supported")
  isst_cp_cap=$(grep SST-CP info.out | grep "not supported")
  isst_bf_cap=$(grep SST-BF info.out | grep "not supported")
  isst_tf_cap=$(grep SST-TF info.out | grep "not supported")

  if [[ -z "$isst_pp_cap" ]] && [[ -z "$isst_cp_cap" ]] &&
    [[ -z "$isst_bf_cap" ]] && [[ -z "$isst_tf_cap" ]]; then
    test_print_trc "The ISST-PP, ISST-CP, ISST-BF, ISST-TF features are supported"
  else
    block_test "There is ISST feature not supported."
  fi
}

# Function to check isst lock status, if locked, then does not support the dynamic
# isst perf profile level change
isst_unlock_status() {
  expected_lock_status=unlocked
  do_cmd "intel-speed-select -o pp.out perf-profile get-lock-status"
  test_print_trc "The system lock status is:"
  do_cmd "cat pp.out"
  isst_lock_status=$(grep get-lock-status pp.out | awk -F ":" '{print $2}')
  isst_lock_status_num=$(grep get-lock-status pp.out | awk -F ":" '{print $2}' | wc -l)

  for ((i = 1; i <= isst_lock_status_num; i++)); do
    j=$(("$i" - 1))
    isst_lock_status_by_num=$(echo "$isst_lock_status" | sed -n "$i, 1p")
    if [ "$isst_lock_status_by_num" = "$expected_lock_status" ]; then
      test_print_trc "The system package $j isst lock status is: $isst_lock_status_by_num"
      test_print_trc "The system package $j is unlocked for different profiles change."
    else
      test_print_trc "The system package $j isst lock status is: $isst_lock_status_by_num"
      block_test "The system is locked for package $j, user may need to check BIOS to unlock."
    fi
  done
}

# Function to check if the isst perf profile config enable or not
isst_pp_config_enable() {
  expected_config_status=enabled
  do_cmd "intel-speed-select -o pp.out perf-profile get-config-enabled"
  test_print_trc "The system perf profile config enable status:"
  do_cmd "cat pp.out"

  isst_config_status=$(grep get-config-enabled pp.out | awk -F ":" '{print $2}')
  isst_config_status_num=$(grep get-config-enabled pp.out | awk -F ":" '{print $2}' | wc -l)

  for ((i = 1; i <= isst_config_status_num; i++)); do
    j=$(("$i" - 1))
    isst_config_status_by_num=$(echo "$isst_config_status" | sed -n "$i, 1p")
    if [ "$isst_config_status_by_num" = "$expected_config_status" ]; then
      test_print_trc "The system package $j isst config status is: $isst_config_status_by_num"
    else
      die "The system package $j isst config status is: $isst_config_status_by_num"
    fi
  done
}

# Function to do different supported perf profile levels change
# Input:
#        $1: select different perf profile level
isst_pp_level_change() {
  local level_id=$1
  do_cmd "intel-speed-select -o pp.out perf-profile get-config-current-level"
  test_print_trc "The system perf profile config current level info:"
  do_cmd "cat pp.out"

  cur_level=$(grep get-config-current_level pp.out | awk -F ":" '{print $2}')
  cur_level_num=$(grep get-config-current_level pp.out | awk -F ":" '{print $2}' | wc -l)

  test_print_trc "Will change the config level from $cur_level to $level_id:"
  do_cmd "intel-speed-select -o pp.out perf-profile set-config-level -l $level_id -o"
  test_print_trc "The system perf profile config level change log:"
  do_cmd "cat pp.out"

  set_tdp_level_status=$(grep set_tdp_level pp.out | awk -F ":" '{print $2}')
  set_tdp_level_status_num=$(grep set_tdp_level pp.out | awk -F ":" '{print $2}' | wc -l)

  for ((i = 1; i <= set_tdp_level_status_num; i++)); do
    j=$(("$i" - 1))
    set_tdp_level_status_by_num=$(echo "$set_tdp_level_status" | sed -n "$i, 1p")
    if [ "$set_tdp_level_status_by_num" = success ]; then
      test_print_trc "The system package $j set tdp level status is $set_tdp_level_status_by_num"
      test_print_trc "The system package $j set tdp level success."
    else
      test_print_trc "The system package $j set tdp level status is $set_tdp_level_status_by_num"
      die "The system package $j set tdp level fails"
    fi
  done

  test_print_trc "Confirm the changed config current level:"
  do_cmd "intel-speed-select -o pp.out perf-profile get-config-current-level"
  test_print_trc "The system perf profile config current level info:"
  do_cmd "cat pp.out"

  cur_level=$(grep get-config-current_level pp.out | awk -F ":" '{print $2}')
  cur_level_num=$(grep get-config-current_level pp.out | awk -F ":" '{print $2}' | wc -l)

  for ((i = 1; i <= cur_level_num; i++)); do
    j=$(("$i" - 1))
    cur_level_by_num=$(echo "$cur_level" | sed -n "$i, 1p")
    if [ "$cur_level_by_num" -eq "$level_id" ]; then
      test_print_trc "The system package $j config current level: $cur_level_by_num"
      test_print_trc "The system package $j config current level is $level_id after successfully setting"
    else
      test_print_trc "The system package $j config current level: $cur_level_by_num"
      die "The system package $j set tdp level fails"
    fi
  done

  test_print_trc "Recover the config level to the default setting: 0"
  do_cmd "intel-speed-select -o pp.out perf-profile set-config-level -l 0 -o"
}

# Function to do different supported perf profile levels change by cgroup v2 solution
# Input:
#        $1: select different perf profile level
isst_pp_level_change_cgroup() {
  local level_id=$1
  do_cmd "intel-speed-select -o pp.out perf-profile get-config-current-level"
  test_print_trc "The system perf profile config current level info:"
  do_cmd "cat pp.out"

  cur_level=$(grep get-config-current_level pp.out | awk -F ":" '{print $2}')
  cur_level_num=$(grep get-config-current_level pp.out | awk -F ":" '{print $2}' | wc -l)

  test_print_trc "Will change the config level from $cur_level to $level_id:"
  do_cmd "intel-speed-select -o pp.out -g perf-profile set-config-level -l $level_id"
  test_print_trc "The system perf profile config level change log:"
  do_cmd "cat pp.out"

  set_tdp_level_status=$(grep set_tdp_level pp.out | awk -F ":" '{print $2}')
  set_tdp_level_status_num=$(grep set_tdp_level pp.out | awk -F ":" '{print $2}' | wc -l)

  for ((i = 1; i <= set_tdp_level_status_num; i++)); do
    j=$(("$i" - 1))
    set_tdp_level_status_by_num=$(echo "$set_tdp_level_status" | sed -n "$i, 1p")
    if [ "$set_tdp_level_status_by_num" = success ]; then
      test_print_trc "The system package $j set tdp level status is $set_tdp_level_status_by_num"
      test_print_trc "The system package $j set tdp level success."
    else
      test_print_trc "The system package $j set tdp level status is $set_tdp_level_status_by_num"
      die "The system package $j set tdp level fails"
    fi
  done

  test_print_trc "Confirm the changed config current level:"
  do_cmd "intel-speed-select -o pp.out perf-profile get-config-current-level"
  test_print_trc "The system perf profile config current level info:"
  do_cmd "cat pp.out"

  cur_level=$(grep get-config-current_level pp.out | awk -F ":" '{print $2}')
  cur_level_num=$(grep get-config-current_level pp.out | awk -F ":" '{print $2}' | wc -l)

  for ((i = 1; i <= cur_level_num; i++)); do
    j=$(("$i" - 1))
    cur_level_by_num=$(echo "$cur_level" | sed -n "$i, 1p")
    if [ "$cur_level_by_num" -eq "$level_id" ]; then
      test_print_trc "The system package $j config current level: $cur_level_by_num"
      test_print_trc "The system package $j config current level is $level_id after successfully setting"
    else
      test_print_trc "The system package $j config current level: $cur_level_by_num"
      die "The system package $j set tdp level fails"
    fi
  done

  test_print_trc "Recover the config level to the default setting: 0"
  do_cmd "intel-speed-select -o pp.out -g perf-profile set-config-level -l 0"
}

# Function to check the base frequency alignment between sysfs and isst tool for each profile level
# Input:
#        $1: select different perf profile level
isst_base_freq_pp_level_change() {
  local level_id=$1

  test_print_trc "Recover the config level to the default setting: 0"
  do_cmd "intel-speed-select -o pp.out perf-profile set-config-level -l 0 -o"
  sleep 2
  # Read the base_freqency by default ISST perf-profile level
  base_freq_bf_khz=$(cat "$CPU_SYSFS_PATH"/cpu0/cpufreq/base_frequency 2>&1)
  base_freq_bf_mhz=$(echo "$base_freq_bf_khz/1000" | bc)
  [[ -n "$base_freq_bf_khz" ]] || block_test "Did not get base_frequency from sysfs"
  test_print_trc "The default CPU base frequency is: $base_freq_bf_mhz"

  # Change the PP level
  do_cmd "intel-speed-select -o pp.out perf-profile set-config-level -l $level_id -o"
  test_print_trc "The system perf profile level change status:"
  do_cmd "cat pp.out"

  # Read the base-frequency(MHz) of enabled CPUs from isst perf-profile info
  do_cmd "intel-speed-select -o pp_info.out perf-profile info"
  do_cmd "cat pp_info.out"
  sleep 5
  package_number=$(grep -c "die-0" pp_info.out)
  test_print_trc "Package number: $package_number"
  for ((i = 1; i <= "$package_number"; i++)); do
    enabled_cpu=$(grep -A 10 "perf-profile-level-$level_id" pp_info.out |
      grep "enable-cpu-list" | awk -F ":" '{print $2}' | awk -F "," '{print $1}' |
      sed -n "$i,1p")
    test_print_trc "The test enabled the cpu number is: $enabled_cpu"
    [[ -n "$enabled_cpu" ]] || block_test "Did not get enabled CPU number"

    # High PP level should have the new CPU base_freqency
    base_freq_af_khz=$(cat "$CPU_SYSFS_PATH"/cpu"$enabled_cpu"/cpufreq/base_frequency 2>&1)
    base_freq_af_mhz=$(echo "$base_freq_af_khz/1000" | bc)
    test_print_trc "The base_frequency_af read from sysfs:$base_freq_af_mhz"

    # Read the base-frequency(MHz) value from ISST log
    base_freq_tool=$(grep -A 10 "perf-profile-level-$level_id" pp_info.out |
      grep "base-frequency(MHz)" | awk -F ":" '{print $2}' | sed -n "$i,1p")
    [[ -n "$base_freq_tool" ]] || block_test "Did not get base-freq value from ISST log."
    test_print_trc "The base-frequency(MHz) read from ISST log of CPU$i:$base_freq_tool"

    # The base_freq reported from sysfs and isst tool should be the same value
    if [[ "$base_freq_af_mhz" -eq "$base_freq_tool" ]]; then
      test_print_trc "The CPU base frequency change from sysfs and isst tool are expected \
for PP Level $level_id change, the new CPU base frequency is: $base_freq_af_mhz"
    else
      die "The CPU base frequency change is NOT expected for PP Level $level_id change,\
the tool report: $base_freq_tool, the sysfs reports: $base_freq_af_mhz"
    fi
  done

  test_print_trc "Recover the config level to the default setting: 0"
  do_cmd "intel-speed-select -o pp.out perf-profile set-config-level -l 0 -o"
}

# Function to check isst core power feature enable and disable
isst_cp_enable_disable() {
  local expected_status=$1
  local action=$2
  local type=$3

  do_cmd "intel-speed-select -o cp.out core-power $action -p $type"
  test_print_trc "The system isst core power enable status:"
  do_cmd "cat cp.out"

  do_cmd "intel-speed-select -o cp.out core-power info"
  test_print_trc "The system isst core power info:"
  do_cmd "cat cp.out"

  isst_cp_status=$(grep clos-enable-status cp.out | awk -F ":" '{print $2}')
  isst_cp_status_num=$(grep clos-enable-status cp.out | awk -F ":" '{print $2}' | wc -l)
  isst_cp_pri_type=$(grep priority-type cp.out | awk -F ":" '{print $2}')

  for ((i = 1; i <= isst_cp_status_num; i++)); do
    j=$(("$i" - 1))
    isst_cp_status_by_num=$(echo "$isst_cp_status" | sed -n "$i, 1p")
    test_print_trc "Print clos-enable-status:$isst_cp_status_by_num"
    if [ "$isst_cp_status_by_num" = "$expected_status" ]; then
      test_print_trc "The system package $j isst core power status is: $isst_cp_status_by_num"
    else
      die "The system package $j isst core power status is: $isst_cp_status_by_num"
    fi
  done

  for ((i = 1; i <= isst_cp_status_num; i++)); do
    j=$(("$i" - 1))
    isst_cp_pri_type_by_num=$(echo "$isst_cp_pri_type" | sed -n "$i, 1p")
    test_print_trc "Print priority-type: $isst_cp_pri_type"
    if [ "$type" -eq 0 ] && [ "$isst_cp_pri_type_by_num" = "proportional" ]; then
      test_print_trc "The system package $j isst core power priority-type is $isst_cp_pri_type_by_num"
    elif [ "$type" -eq 1 ] && [ "$isst_cp_pri_type_by_num" = "ordered" ]; then
      test_print_trc "The system package $j isst core power priority-type is $isst_cp_pri_type_by_num"
    else
      die "The system package $j isst core power priority-type is not expected: $isst_cp_pri_type_by_num"
    fi
  done
}

# Function to set isst core power configuration for clos id and min freq
# Input:
#        $1: select different class of service ID
isst_cp_config_clos_min_set_get() {
  local clos_id=$1
  local min_khz=""
  min_khz=$(cat /sys/devices/system/cpu/cpu0/cpufreq/base_frequency 2>&1)
  [[ -n "$min_khz" ]] || block_test "Did not get base frequency from sysfs"
  min_mhz=$(("$min_khz" / 1000))
  do_cmd "intel-speed-select -o cp.out core-power config -n $min_mhz -c $clos_id"
  test_print_trc "The system isst core power config change to:"
  do_cmd "cat cp.out"

  do_cmd "intel-speed-select -o cp.out core-power get-config -c $clos_id"
  test_print_trc "The system isst core power get config:"
  do_cmd "cat cp.out"

  isst_clos_status=$(grep clos: cp.out | awk -F ":" '{print $2}')
  isst_cp_status=$(grep clos-min cp.out | awk -F ":" '{print $2}')
  isst_cp_status_num=$(grep clos-min cp.out | awk -F ":" '{print $2}' | wc -l)

  for ((i = 1; i <= isst_cp_status_num; i++)); do
    j=$(("$i" - 1))
    isst_cp_status_by_num=$(echo "$isst_cp_status" | sed -n "$i, 1p")
    isst_clos_status_by_num=$(echo "$isst_clos_status" | sed -n "$i, 1p")
    if [[ "$isst_cp_status_by_num" = "$min_mhz MHz" ]] && [[ "$isst_clos_status_by_num" = "$clos_id" ]]; then
      test_print_trc "The system package $j isst core power clos is: $isst_clos_status_by_num"
      test_print_trc "The system package $j isst core power clos min freq is: $isst_cp_status_by_num"
    else
      die "The system package $j isst core power clos is: $isst_clos_status_by_num, \
The system package $j isst core power clos min freq is: $isst_cp_status_by_num"
    fi
  done
}

# Function to set isst core power configuration for clos id and max freq
# Input:
#        $1: select different class of service ID
isst_cp_config_clos_max_set_get() {
  local clos_id=$1
  local max_khz=""
  max_khz=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>&1)
  [[ -n "$max_khz" ]] || block_test "Did not get scaling_max_freq from sysfs"
  max_mhz=$(("$max_khz" / 1000))
  do_cmd "intel-speed-select -o cp.out core-power config -m $max_mhz -c $clos_id"
  test_print_trc "The system isst core power config change to:"
  do_cmd "cat cp.out"

  do_cmd "intel-speed-select -o cp.out core-power get-config -c $clos_id"
  test_print_trc "The system isst core power get config:"
  do_cmd "cat cp.out"

  isst_clos_status=$(grep clos: cp.out | awk -F ":" '{print $2}')
  isst_cp_status=$(grep clos-max cp.out | awk -F ":" '{print $2}')
  isst_cp_status_num=$(grep clos-max cp.out | awk -F ":" '{print $2}' | wc -l)

  for ((i = 1; i <= isst_cp_status_num; i++)); do
    j=$(("$i" - 1))
    isst_cp_status_by_num=$(echo "$isst_cp_status" | sed -n "$i, 1p")
    isst_clos_status_by_num=$(echo "$isst_clos_status" | sed -n "$i, 1p")
    if [[ "$isst_cp_status_by_num" = "$max_mhz MHz" ]] && [[ "$isst_clos_status_by_num" = "$clos_id" ]]; then
      test_print_trc "The system package $j isst core power clos is: $isst_clos_status_by_num"
      test_print_trc "The system package $j isst core power clos max freq is: $isst_cp_status_by_num"
    else
      die "The system package $j isst core power clos is: $isst_clos_status_by_num, \
The system package $j isst core power clos max freq is: $isst_cp_status_by_num"
    fi
  done
}

# Function to set isst core power configuration for clos id and clos-proportional-priority
# Input:
#        $1: select different class of service ID
isst_cp_config_clos_prop_set_get() {
  local clos_id=$1
  local prop_pri=""
  prop_pri=10

  do_cmd "intel-speed-select -o cp.out core-power config -w $prop_pri -c $clos_id"
  test_print_trc "The system isst core power config change to:"
  do_cmd "cat cp.out"

  do_cmd "intel-speed-select -o cp.out core-power get-config -c $clos_id"
  test_print_trc "The system isst core power get config:"
  do_cmd "cat cp.out"

  isst_clos_status=$(grep clos: cp.out | awk -F ":" '{print $2}')
  isst_cp_status=$(grep clos-proportional-priority cp.out | awk -F ":" '{print $2}')
  isst_cp_status_num=$(grep clos-proportional-priority cp.out | awk -F ":" '{print $2}' | wc -l)

  for ((i = 1; i <= isst_cp_status_num; i++)); do
    j=$(("$i" - 1))
    isst_cp_status_by_num=$(echo "$isst_cp_status" | sed -n "$i, 1p")
    isst_clos_status_by_num=$(echo "$isst_clos_status" | sed -n "$i, 1p")
    if [[ "$isst_cp_status_by_num" = "$prop_pri" ]] && [[ "$isst_clos_status_by_num" = "$clos_id" ]]; then
      test_print_trc "The system package $j isst core power clos is: $isst_clos_status_by_num"
      test_print_trc "The system package $j isst core power clos proportional priority is: $isst_cp_status_by_num"
    else
      die "The system package $j isst core power clos is: $isst_clos_status_by_num, \
The system package $j isst core power clos proportional priority is: $isst_cp_status_by_num"
    fi
  done
}

# Function to set and get one CPU1 association
# Input:
#        $1: select different class of service ID
isst_cp_assoc_set_get() {
  local clos_id=$1

  do_cmd "intel-speed-select -o cp.out -c 1 core-power assoc -c $clos_id"
  test_print_trc "The system's CPU1 is associated to CLOS $clos_id"
  do_cmd "cat cp.out"

  isst_cp_assoc_status=$(grep assoc cp.out | awk -F ":" '{print $2}')
  if [[ "$isst_cp_assoc_status" = "success" ]]; then
    test_print_trc "The system's CPU1 is associated to CLOS $clos_id successfully"
  else
    die "The system's CPU1 is associated to CLOS $clos_id failed"
  fi

  do_cmd "intel-speed-select -o cp.out -c 1 core-power get-assoc"
  test_print_trc "The system's CPU1 is associated to CLOS $clos_id"
  do_cmd "cat cp.out"

  isst_cp_assoc_clos=$(grep clos cp.out | awk -F ":" '{print $2}')
  if [[ "$isst_cp_assoc_clos" = "$clos_id" ]]; then
    test_print_trc "The system's CPU1 gets core power association info."
  else
    die "The system's CPU1 failed to get core power association info"
  fi
}

# Function to set and get the max CPU association
# Input:
#        $1: select different class of service ID
isst_cp_max_cpu_assoc_set_get() {
  local clos_id=$1
  local max_cpu=""

  max_cpu=$(lscpu --online --extended | awk '{print $1}' | sed -n '$p' 2>&1)
  test_print_trc "The max cpu number is: $max_cpu"

  do_cmd "intel-speed-select -o cp.out -c $max_cpu core-power assoc -c $clos_id"
  test_print_trc "The system's CPU $max_cpu is associated to CLOS $clos_id"
  do_cmd "cat cp.out"

  isst_cp_assoc_status=$(grep assoc cp.out | awk -F ":" '{print $2}')
  if [[ "$isst_cp_assoc_status" = "success" ]]; then
    test_print_trc "The system's CPU $max_cpu is associated to CLOS $clos_id successfully"
  else
    die "The system's CPU $max_cpu is associated to CLOS $clos_id failed"
  fi

  do_cmd "intel-speed-select -o cp.out -c $max_cpu core-power get-assoc"
  test_print_trc "The system's CPU $max_cpu is associated to CLOS $clos_id"
  do_cmd "cat cp.out"

  isst_cp_assoc_clos=$(grep clos cp.out | awk -F ":" '{print $2}')
  if [[ "$isst_cp_assoc_clos" = "$clos_id" ]]; then
    test_print_trc "The system's CPU $max_cpu gets core power association info."
  else
    die "The system's CPU $max_cpu failed to get core power association info"
  fi
}

# This function will check the baseline base_freq is reachable before enabling isst_bf
isst_bf_baseline_test() {
  # Get base_freq from isst tool, the unit is MHz
  do_cmd "intel-speed-select -o pp.out perf-profile info -l 0"
  do_cmd "cat pp.out"
  base_freq_isst_raw=$(grep "base-frequency(MHz)" pp.out | awk -F ":" '{print $2}' | sed -n "1, 1p")
  base_freq_isst=$(echo "$base_freq_isst_raw*1000" | bc)
  test_print_trc "The base_freq from isst tool is: $base_freq_isst KHz"

  # Get base_freq from sysfs, the unit is KHz
  base_freq_sysfs=$(cat "$CPU_SYSFS_PATH"/cpu0/cpufreq/base_frequency 2>&1)
  [[ -n "$base_freq_sysfs" ]] || block_test "Did not get base frequency from sysfs"
  test_print_trc "The base_freq from sysfs is: $base_freq_sysfs KHz"

  if [ "$base_freq_sysfs" = "$base_freq_isst" ]; then
    test_print_trc "The base_freq from sysfs is aligned with isst tool"
  else
    die "The base_freq from sysfs is not match with isst tool"
  fi

  # Run stress to check if the system can reach the base_freq
  cpu_num=$(lscpu --online --extended | awk '{print $1}' | sed -n '$p' 2>&1)
  cpu_num_all=$(("$cpu_num" + 1))
  test_print_trc "The online CPUs number is:$cpu_num_all"

  # Add 100% workload for the online CPUs
  test_print_trc "Executing stress -c $cpu_num_all -t 90 & in background"
  do_cmd "stress -c $cpu_num_all -t 90 &"
  stress_pid=$!
  [[ -n "$stress_pid" ]] || block_test "stress is not launched."

  cpu_stat=$(turbostat -q --show $COLUMNS -i 10 sleep 10 2>&1)
  [[ -n "$cpu_stat" ]] || block_test "Did not get turbostat log"
  test_print_trc "Turbostat output when 100% workload stress running is:"
  echo -e "$cpu_stat"

  first_cpu_freq_temp=$(echo "$cpu_stat" |
    awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' |
    grep "Bzy_MHz" | awk -F " " '{print $3}')
  first_cpu_freq=$(echo "$first_cpu_freq_temp*1000" | bc)
  test_print_trc "The first CPU freq when stress is running: $first_cpu_freq KHz"
  last_cpu_freq_temp=$(echo "$cpu_stat" |
    awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' |
    grep "Bzy_MHz" | awk -F " " '{print $NF}')
  last_cpu_freq=$(echo "$last_cpu_freq_temp*1000" | bc)
  test_print_trc "The last CPU freq when stress is running: $last_cpu_freq KHz"

  first_delta=$(("$base_freq_sysfs" - "$first_cpu_freq"))
  test_print_trc "The first cpu freq between sysfs expected and turbostat reported is: $first_delta KHz"
  last_delta=$(("$base_freq_sysfs" - "$last_cpu_freq"))
  test_print_trc "The last cpu freq between sysfs expected and turbostat reported is: $last_delta KHz"
  core_delta=$(("$last_cpu_freq" - "$first_cpu_freq"))
  test_print_trc "Two core cpu freq delta is:$core_delta KHz"

  sleep 30
  # Kill stress thread
  [[ -z "$stress_pid" ]] || do_cmd "kill -9 $stress_pid"

  test_print_trc "Recover the config level to the default setting: 0"
  do_cmd "intel-speed-select -o pp.out perf-profile set-config-level -l 0 -o"

  # If the first or last CPU delta freq is larger than 100 MHz(100000Khz),
  # or two cores CPU delta freq is larger than 200 MHz,then check if thermal limitation is assert.
  # Otherwise, expect the delta value is within 100Mhz(100000Khz).
  if [[ $(echo "$first_delta > 100000" | bc) -eq 1 ]] ||
    [[ $(echo "$last_delta > 100000" | bc) -eq 1 ]] ||
    [[ $(echo "$core_delta > 200000" | bc) -eq 1 ]]; then
    if power_limit_check; then
      test_print_trc "The package and core power limitation is assert."
      test_print_trc "The average CPU freq gap is 100Mhz larger than expected base_freq \
with power limitation log observed."
    else
      test_print_trc "The package and core power limitation is not assert."
      check_tuned_service
      die "The CPUs base freq is 100Mhz larger than expected base_freq without power limitation assert."
    fi
  else
    test_print_trc "The CPUs base freq when 100% workload stress running: PASS"
  fi
}

# Function to check isst high priority base freq feature
# Input:
#        $1: select different perf profile level
isst_bf_freq_test() {
  local level_id=$1

  # Get the base_freq from sysfs, the unit is KHz
  base_freq_sysfs=$(cat "$CPU_SYSFS_PATH"/cpu0/cpufreq/base_frequency 2>&1)
  [[ -n "$base_freq_sysfs" ]] || block_test "Did not get base frequency from sysfs"
  test_print_trc "The base_freq from sysfs is: $base_freq_sysfs KHz"

  # Set SST Perf profile level to $level_id
  test_print_trc "Will change Perf profile config level to $level_id:"
  do_cmd "intel-speed-select -o pp.out perf-profile set-config-level -l $level_id -o"
  test_print_trc "The system perf profile config level change log:"
  do_cmd "cat pp.out"

  # Disable CPU turbo
  test_print_trc "Disable CPU Turbo"
  do_cmd "echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo"

  # Enable ISST base_freq feature, -a option is used to enable core power CLOS related parameters
  do_cmd "intel-speed-select -o bf.out base-freq enable -a"
  test_print_trc "Intel SST base_freq enable status:"
  do_cmd "cat bf.out"

  isst_bf_status=$(grep "enable" bf.out | awk -F ":" '{print $2}')
  isst_bf_status_num=$(grep "enable" bf.out | awk -F ":" '{print $2}' | wc -l)

  for ((i = 1; i <= isst_bf_status_num; i++)); do
    j=$(("$i" - 1))
    isst_bf_status_by_num=$(echo "$isst_bf_status" | sed -n "$i, 1p")
    if [ "$isst_bf_status_by_num" = "success" ]; then
      test_print_trc "The system package $j isst bf enable status is: $isst_bf_status_by_num"
    else
      die "The system package $j isst bf enable status is: $isst_bf_status_by_num"
    fi
  done

  # Get High and low priority base freq with perf profile level 0 from ISST tool
  do_cmd "intel-speed-select -o bf.out base-freq info -l 0"
  test_print_trc "Intel SST base_freq info with perf profile level 0:"
  do_cmd "cat bf.out"

  # Freq unit from ISST is: MHz
  hp_base_freq_isst=$(grep "high-priority-base-frequency(MHz)" bf.out | awk -F ":" '{print $2}' | sed -n "1, 1p")
  test_print_trc "The high priority base freq from ISST tool is: $hp_base_freq_isst MHz"

  lp_base_freq_isst=$(grep "low-priority-base-frequency(MHz)" bf.out | awk -F ":" '{print $2}' | sed -n "1, 1p")
  test_print_trc "The low priority base freq from ISST tool is: $lp_base_freq_isst MHz"

  # Get the actual package number which support base_freq feature
  hp_bf_cpus_num=$(grep "high-priority-cpu-list" bf.out | grep -v -c none)
  for ((i = 1; i <= hp_bf_cpus_num; i++)); do
    # Get two high priority CPUs on the same package
    hp_bf_cpus_2nd=$(grep "high-priority-cpu-list" bf.out | grep -v none | awk -F "," '{print $2}' | sed -n "$i, 1p")
    hp_bf_cpus_3rd=$(grep "high-priority-cpu-list" bf.out | grep -v none | awk -F "," '{print $3}' | sed -n "$i, 1p")
    # j below is used to check package number
    j=$(("$i" - 1))
    test_print_trc "The 2nd high priority cpu in package$j is: $hp_bf_cpus_2nd"
    test_print_trc "The 3rd high priority cpu in package$j is: $hp_bf_cpus_3rd"

    # Run stress on 2 high priority CPUs
    test_print_trc "Executing 100% workload stress on two high priority CPUs"
    do_cmd "taskset -c 0,$hp_bf_cpus_2nd,$hp_bf_cpus_3rd stress -c 3 -t 90 &"
    stress_pid=$!
    [[ -n "$stress_pid" ]] || block_test "stress is not launched."

    cpu_stat=$(turbostat -q -c 0,"$hp_bf_cpus_2nd","$hp_bf_cpus_3rd" --show "$COLUMNS" -i 10 sleep 10 2>&1)
    [[ -n "$cpu_stat" ]] || block_test "Did not get turbostat log"
    test_print_trc "Turbostat output when 100% workload stress running is:"
    echo -e "$cpu_stat"

    # Assume CPU0 is the low priority CPU
    actual_lp_cpu0_freq=$(echo "$cpu_stat" |
      awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' |
      grep "Bzy_MHz" | awk -F " " '{print $3}')
    test_print_trc "Package$j CPU0 as the low priority CPU actual base_freq during stress is: $actual_lp_cpu0_freq MHz"

    # Check if the 2nd and 3rd CPUs reached high priority base_freq
    actual_2nd_cpu_freq=$(echo "$cpu_stat" |
      awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' |
      grep "Bzy_MHz" | awk -F " " '{print $4}')
    test_print_trc "The 2nd CPU actual base_freq of package$j during stress is: $actual_2nd_cpu_freq MHz"

    actual_3rd_cpu_freq=$(echo "$cpu_stat" |
      awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' |
      grep "Bzy_MHz" | awk -F " " '{print $5}')
    test_print_trc "The 3rd CPU actual base_freq of package$j during stress is: $actual_3rd_cpu_freq MHz"

    delta_2nd_cpu=$(awk -v x="$hp_base_freq_isst" -v y="$actual_2nd_cpu_freq" \
      'BEGIN{printf "%.1f\n", x-y}')
    delta_3rd_cpu=$(awk -v x="$hp_base_freq_isst" -v y="$actual_3rd_cpu_freq" \
      'BEGIN{printf "%.1f\n", x-y}')

    sleep 30
    # Kill stress thread
    [[ -z "$stress_pid" ]] || do_cmd "kill -9 $stress_pid"

    # Disable isst base freq
    do_cmd "intel-speed-select base-freq disable -a"
    test_print_trc "Recover the default isst base freq setting:disable"

    # Recover the default SST Perf profile level to 0
    test_print_trc "Recover the config level to the default setting: 0"
    do_cmd "intel-speed-select -o pp.out perf-profile set-config-level -l 0 -o"

    # Enable CPU turbo
    test_print_trc "Enable CPU Turbo"
    do_cmd "echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo"

    # Set the error deviation is 100 MHz
    if [[ $(echo "$delta_2nd_cpu > 100" | bc) -eq 1 ]] ||
      [[ $(echo "$delta_3rd_cpu > 100" | bc) -eq 1 ]] ||
      [[ "$actual_lp_cpu0_freq" -ne "$lp_base_freq_isst" ]]; then
      #Invoking power limit check function
      if power_limit_check; then
        test_print_trc "The package$j and core power limitation is assert."
        test_print_trc "The 2nd and 3rd CPUs of package$j did not reach ISST HP base freq when power limitation assert."
      else
        test_print_trc "The package$j and core power limitation is not assert."
        check_tuned_service
        die "The 2nd and 3rd CPUs of package$j did not reach ISST HP base freq without power limitation assert."
      fi
    else
      test_print_trc "The isst high priority and low priority base freq of package$j reached \
expectation when stress is running."
    fi
  done
}

# Function to check isst high priority turbo freq feature
# Input:
#        $1: select different perf profile level
isst_tf_freq_test() {
  local level_id=$1

  # Make sure CPU turbo is enabled
  test_print_trc "Make sure CPU Turbo is enabled by default"
  do_cmd "echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo"

  # Set SST Perf profile level to $level_id
  test_print_trc "Will change Perf profile config level to $level_id:"
  do_cmd "intel-speed-select -o pp.out perf-profile set-config-level -l $level_id -o"
  test_print_trc "The system perf profile config level change log:"
  do_cmd "cat pp.out"

  # Make sure ISST TF is disabled at beginning
  do_cmd "intel-speed-select -c 8,9 turbo-freq disable -a"
  test_print_trc "Make sure the default isst turbo freq setting:disable"

  # Keep ISST TF disable to get base turbo freq when all CPUs running stress
  test_print_trc "Executing 100% workload on all CPUs to get the base turbo freq:"
  cpu_num=$(lscpu --online --extended | awk '{print $1}' | sed -n '$p')
  [[ -n "$cpu_num" ]] || block_test "Did not get online cpu list"
  all_cpus_num=$(("$cpu_num" + 1))
  do_cmd "stress -c $all_cpus_num -t 120 &"
  stress_pid=$!
  [[ -n "$stress_pid" ]] || block_test "stress is not launched."

  # List Core0 15 CPUs freq status by turbostat tool
  cpu_stat=$(turbostat -q -c 0-14 --show $COLUMNS -i 10 sleep 10 2>&1)
  [[ -n "$cpu_stat" ]] || block_test "Did not get turbostat log"
  test_print_trc "Turbostat output when 100% workload stress running with turbo enabled:"
  echo -e "$cpu_stat"
  # Take CPU8 and CPU9 to check the base turbo freq
  base_turbo_freq_cpu8=$(echo "$cpu_stat" |
    awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' |
    grep "Bzy_MHz" | awk -F " " '{print $11}')
  test_print_trc "The CPU8 base turbo freq is: $base_turbo_freq_cpu8 MHz"
  base_turbo_freq_cpu9=$(echo "$cpu_stat" |
    awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' |
    grep "Bzy_MHz" | awk -F " " '{print $12}')
  test_print_trc "The CPU9 base turbo freq is: $base_turbo_freq_cpu9 MHz"

  # Enable ISST TF Feature, -a option sets the CPUs to high and low priority
  # using Intel Speed Select Technology Core Power (Intel(R) SST-CP) features
  # The CPU numbers passed with “-c” arguments are marked as high priority, including its siblings.
  test_print_trc "Will enable CPU8 and CPU9 and their siblings as the high priority"
  do_cmd "intel-speed-select -o tf.out -c 8,9 turbo-freq enable -a"
  test_print_trc "Intel SST turbo_freq enable status:"
  do_cmd "cat tf.out"

  # Get ISST TF marked high priority freq, which is opportunistic, when there is
  # no thermal/power limitation, we have chance to meet, so we just take this number
  # as reference.
  do_cmd "intel-speed-select -o tf.out -c 0 turbo-freq info -l 0"
  opportunistic_hp_tf=$(grep "high-priority-max-frequency(MHz)" tf.out | awk -F ":" '{print $2}' | sed -n "1, 1p")

  # Execute hackbench workload on high priority CPUs: CPU8 and CPU9
  test_print_trc "Will execute hackbench workload on high priority CPUs: CPU8 and CPU9"
  do_cmd "taskset -c 8,9 perf bench -r 100 sched pipe &"
  perf_pid=$!
  [[ -n "$perf_pid" ]] || block_test "perf bench did not launch."

  # List Core0 15 CPUs freq status after enable ISST TF by turbostat tool
  cpu_stat=$(turbostat -q -c 0-14 --show $COLUMNS -i 10 sleep 10 2>&1)
  [[ -n "$cpu_stat" ]] || block_test "Did not get expected turbostat output."
  test_print_trc "Turbostat output when 100% workload stress and hackbench workload running:"
  echo -e "$cpu_stat"
  # Take CPU8 and CPU9 to check high priority turbo freq
  hp_turbo_freq_cpu8=$(echo "$cpu_stat" |
    awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' |
    grep "Bzy_MHz" | awk -F " " '{print $11}')
  test_print_trc "The high priority CPU8 turbo freq is: $hp_turbo_freq_cpu8 MHz"
  hp_turbo_freq_cpu9=$(echo "$cpu_stat" |
    awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' |
    grep "Bzy_MHz" | awk -F " " '{print $12}')
  test_print_trc "The high priority CPU9 turbo freq is: $hp_turbo_freq_cpu9 MHz"

  delta_cpu8=$(("$hp_turbo_freq_cpu8" - "$base_turbo_freq_cpu8"))
  test_print_trc "The CPU8 delta between high priority turbo freq vs. base turbo freq: $delta_cpu8 MHz"
  delta_cpu9=$(("$hp_turbo_freq_cpu9" - "$base_turbo_freq_cpu9"))
  test_print_trc "The CPU9 delta between high priority turbo freq vs. base turbo freq: $delta_cpu9 MHz"

  # Print the high priority turbo freq between opportunistic and real one
  hp_tf_gap_cpu8=$(("$opportunistic_hp_tf" - "$hp_turbo_freq_cpu8"))
  test_print_trc "The ISST HP TF gap between opportunistic vs. actual: $hp_tf_gap_cpu8 MHz"
  hp_tf_gap_cpu9=$(("$opportunistic_hp_tf" - "$hp_turbo_freq_cpu9"))
  test_print_trc "The ISST HP TF gap between opportunistic vs. actual: $hp_tf_gap_cpu9 MHz"

  sleep 30
  # Kill stress threads
  [[ -z "$stress_pid" ]] || do_cmd "kill -9 $stress_pid"

  sleep 30
  # Recover the isst turbo freq disable state
  do_cmd "intel-speed-select -c 8,9 turbo-freq disable -a"
  test_print_trc "Recover the default isst turbo freq setting: disable"

  # Recover the default SST Perf profile level to 0
  test_print_trc "Recover the config level to the default setting: 0"
  do_cmd "intel-speed-select -o pp.out perf-profile set-config-level -l 0 -o"

  # Expect the high priority CPUs turbo freq should at least 100Mhz larger than the base turbo freq
  if [[ $(echo "$delta_cpu8 < 100" | bc) -eq 1 ]] || [[ $(echo "$delta_cpu9 < 100" | bc) -eq 1 ]]; then
    test_print_trc "Will check power limit logs:"
    if power_limit_check; then
      test_print_trc "The package and core power limitation is assert."
      die "The test CPUs did not reach ISST HP turbo freq when power limitation assert."
    else
      test_print_trc "The package and core power limitation is not assert."
      check_tuned_service
      die "The test CPUs did not reach ISST HP turbo freq without power limitation assert."
    fi
  else
    test_print_trc "The isst high priority CPU turbo freq is reached expectation when bench is running."
  fi
}

isst_test() {
  case $TEST_SCENARIO in
  isst_legacy_driver_sysfs)
    isst_legacy_driver_interface
    ;;
  isst_cap)
    isst_info
    ;;
  isst_unlock_status)
    isst_unlock_status
    ;;
  isst_pp_config_enable_status)
    isst_pp_config_enable
    ;;
  isst_pp_config_level1_config)
    isst_pp_level_change 1
    ;;
  isst_pp_config_level2_config)
    isst_pp_level_change 2
    ;;
  isst_pp_config_level3_config)
    isst_pp_level_change 3
    ;;
  isst_pp_config_level4_config)
    isst_pp_level_change 4
    ;;
  isst_pp_config_level1_config_cgroup)
    isst_pp_level_change_cgroup 1
    ;;
  isst_pp_config_level2_config_cgroup)
    isst_pp_level_change_cgroup 2
    ;;
  isst_pp_config_level3_config_cgroup)
    isst_pp_level_change_cgroup 3
    ;;
  isst_pp_config_level4_config_cgroup)
    isst_pp_level_change_cgroup 4
    ;;
  isst_base_freq_pp_level1_change)
    isst_base_freq_pp_level_change 1
    ;;
  isst_base_freq_pp_level2_change)
    isst_base_freq_pp_level_change 2
    ;;
  isst_base_freq_pp_level3_change)
    isst_base_freq_pp_level_change 3
    ;;
  isst_base_freq_pp_level4_change)
    isst_base_freq_pp_level_change 4
    ;;
  isst_cp_enable_prop_type)
    isst_cp_enable_disable enabled enable 0
    ;;
  isst_cp_set_config_clos_min_0)
    isst_cp_config_clos_min_set_get 0
    ;;
  isst_cp_set_config_clos_min_1)
    isst_cp_config_clos_min_set_get 1
    ;;
  isst_cp_set_config_clos_min_2)
    isst_cp_config_clos_min_set_get 2
    ;;
  isst_cp_set_config_clos_min_3)
    isst_cp_config_clos_min_set_get 3
    ;;
  isst_cp_set_config_clos_max_0)
    isst_cp_config_clos_max_set_get 0
    ;;
  isst_cp_set_config_clos_max_1)
    isst_cp_config_clos_max_set_get 1
    ;;
  isst_cp_set_config_clos_max_2)
    isst_cp_config_clos_max_set_get 2
    ;;
  isst_cp_set_config_clos_max_3)
    isst_cp_config_clos_max_set_get 3
    ;;
  isst_cp_set_config_clos_prop_0)
    isst_cp_config_clos_prop_set_get 0
    ;;
  isst_cp_set_config_clos_prop_1)
    isst_cp_config_clos_prop_set_get 1
    ;;
  isst_cp_set_config_clos_prop_2)
    isst_cp_config_clos_prop_set_get 2
    ;;
  isst_cp_set_config_clos_prop_3)
    isst_cp_config_clos_prop_set_get 3
    ;;
  isst_cp_assoc_set_get_clos_0)
    isst_cp_assoc_set_get 0
    ;;
  isst_cp_assoc_set_get_clos_1)
    isst_cp_assoc_set_get 1
    ;;
  isst_cp_assoc_set_get_clos_2)
    isst_cp_assoc_set_get 2
    ;;
  isst_cp_assoc_set_get_clos_3)
    isst_cp_assoc_set_get 3
    ;;
  isst_cp_max_cpu_assoc_set_get_clos_0)
    isst_cp_max_cpu_assoc_set_get 0
    ;;
  isst_cp_max_cpu_assoc_set_get_clos_1)
    isst_cp_max_cpu_assoc_set_get 1
    ;;
  isst_cp_max_cpu_assoc_set_get_clos_2)
    isst_cp_max_cpu_assoc_set_get 2
    ;;
  isst_cp_max_cpu_assoc_set_get_clos_3)
    isst_cp_max_cpu_assoc_set_get 3
    ;;
  isst_cp_disable_prop_type)
    isst_cp_enable_disable disabled disable 0
    ;;
  isst_cp_enable_ordered_type)
    isst_cp_enable_disable enabled enable 1
    ;;
  isst_cp_disable_ordered_type)
    isst_cp_enable_disable disabled disable 1
    ;;
  isst_bf_baseline_freq_test)
    isst_bf_baseline_test
    ;;
  isst_bf_baseline_pp_1)
    isst_pp_level_change 1
    isst_bf_baseline_test
    ;;
  isst_bf_baseline_pp_2)
    isst_pp_level_change 2
    isst_bf_baseline_test
    ;;
  isst_bf_baseline_pp_3)
    isst_pp_level_change 3
    isst_bf_baseline_test
    ;;
  isst_bf_baseline_pp_4)
    isst_pp_level_change 4
    isst_bf_baseline_test
    ;;
  isst_hp_bf_freq_test_pp_level0)
    isst_bf_freq_test 0
    ;;
  isst_hp_bf_freq_test_pp_level1)
    isst_bf_freq_test 1
    ;;
  isst_hp_bf_freq_test_pp_level2)
    isst_bf_freq_test 2
    ;;
  isst_hp_bf_freq_test_pp_level3)
    isst_bf_freq_test 3
    ;;
  isst_hp_bf_freq_test_pp_level4)
    isst_bf_freq_test 4
    ;;
  isst_hp_tf_freq_test_pp_level0)
    isst_tf_freq_test 0
    ;;
  isst_hp_tf_freq_test_pp_level1)
    isst_tf_freq_test 1
    ;;
  isst_hp_tf_freq_test_pp_level2)
    isst_tf_freq_test 2
    ;;
  isst_hp_tf_freq_test_pp_level3)
    isst_tf_freq_test 3
    ;;
  isst_hp_tf_freq_test_pp_level4)
    isst_tf_freq_test 4
    ;;
  isst_hp_bf_freq_pp_level0_orderred_type_test)
    isst_cp_enable_disable enabled enable 1
    isst_bf_freq_test 0
    ;;
  isst_hp_bf_freq_pp_level1_orderred_type_test)
    isst_cp_enable_disable enabled enable 1
    isst_bf_freq_test 1
    ;;
  isst_hp_bf_freq_pp_level2_orderred_type_test)
    isst_cp_enable_disable enabled enable 1
    isst_bf_freq_test 2
    ;;
  isst_hp_bf_freq_pp_level3_orderred_type_test)
    isst_cp_enable_disable enabled enable 1
    isst_bf_freq_test 3
    ;;
  isst_hp_bf_freq_pp_level4_orderred_type_test)
    isst_cp_enable_disable enabled enable 1
    isst_bf_freq_test 4
    ;;
  isst_hp_tf_freq_pp_level0_ordered_type_test)
    isst_cp_enable_disable enabled enable 1
    isst_tf_freq_test 0
    ;;
  isst_hp_tf_freq_pp_level1_ordered_type_test)
    isst_cp_enable_disable enabled enable 1
    isst_tf_freq_test 1
    ;;
  isst_hp_tf_freq_pp_level2_ordered_type_test)
    isst_cp_enable_disable enabled enable 1
    isst_tf_freq_test 2
    ;;
  isst_hp_tf_freq_pp_level3_ordered_type_test)
    isst_cp_enable_disable enabled enable 1
    isst_tf_freq_test 3
    ;;
  isst_hp_tf_freq_pp_level4_ordered_type_test)
    isst_cp_enable_disable enabled enable 1
    isst_tf_freq_test 4
    ;;
  esac
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

isst_test
