#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation
# Description:  Test script for Intel® TPMI (Topology Aware Register and PM Capsule
# Interface) UFS (Uncore Frequency Scaling) driver which is supported on
# Intel® GRANITERAPIDS and further server platforms
# @Author   wendy.wang@intel.com
# @History  Created May 17 2023 - Created

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

UFS_DRIVER_PATH="/sys/bus/auxiliary/drivers/intel_uncore_frequency_tpmi"
UFS_DEVICE_PATH="/sys/bus/auxiliary/devices"
UFS_SYSFS_PATH="/sys/devices/system/cpu/intel_uncore_frequency"
UFS_ATTR="current_freq_khz  initial_max_freq_khz domain_id fabric_cluster_id
initial_min_freq_khz  max_freq_khz  min_freq_khz package_id"

# stress tool is required to run TPMI UFS cases
if which stress 1>/dev/null 2>&1; then
  stress --help 1>/dev/null || block_test "Failed to run stress tool,
please check stress tool error message."
else
  block_test "stress tool is required to run UFS cases,
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

ufs_unbind_bind() {
  local instance_num
  local instance_dev

  instance_num=$(ls "$UFS_DRIVER_PATH" | grep -c intel_vsec.tpmi-uncore)
  test_print_trc "instance num: $instance_num"
  for ((i = 1; i <= instance_num; i++)); do
    instance_dev=$(ls "$UFS_DRIVER_PATH/" | grep intel_vsec.tpmi-uncore |
      sed -n "$i,1p" 2>&1)
    test_print_trc "Doing $instance_dev unbind"
    do_cmd "echo $instance_dev > $UFS_DRIVER_PATH/unbind"
    test_print_trc "Doing $instance_dev bind"
    do_cmd "echo $instance_dev > $UFS_DRIVER_PATH/bind"
  done
}

ufs_device_per_package() {
  local ufs_device

  test_print_trc "Check TPMI_UFS device:"

  [[ -d "$UFS_DEVICE_PATH" ]] ||
    die "TPMI auxiliary device does not exist!"

  ufs_device=$(ls "$UFS_DEVICE_PATH" | grep -c "intel_vsec.tpmi-uncore" 2>&1)
  test_print_trc "TPMI_UFS device number: $ufs_device"
  pkg_num=$(lscpu | grep Socket | awk -F ":" '{print $2}' 2>&1)
  test_print_trc "Package number: $pkg_num"

  if [ "$ufs_device" -eq "$pkg_num" ]; then
    test_print_trc "TPMI_UFS device number is aligned with Package number."
  else
    die "TPMI_UFS device instance number is not aligned with Package number."
  fi

  test_print_trc "Print TPMI_UFS driver interface and device list:"
  lines=$(grep . "$UFS_DEVICE_PATH"/intel_vsec.tpmi-uncore.*/* 2>&1 |
    grep -v "Is a directory" | grep -v "Permission denied")
  for line in $lines; do
    test_print_trc "$line"
  done
}

ufs_sysfs_attr() {
  local attr
  local per_die_num

  per_die_num=$(ls "$UFS_SYSFS_PATH" | grep -c uncore)
  [[ "$per_die_num" = 0 ]] && block_test "Uncore number is 0"

  test_print_trc "Check TPMI_UFS driver sysfs attribute:"
  for ((i = 1; i <= per_die_num; i++)); do
    per_die=$(ls "$UFS_SYSFS_PATH" | grep uncore | sed -n "$i,1p")
    for attr in $UFS_ATTR; do
      sysfs_verify f "$UFS_SYSFS_PATH"/"$per_die"/"$attr" ||
        die "$attr does not exist under $per_die!"
    done
  done

  if ! lines=$(ls "$UFS_SYSFS_PATH"); then
    die "intel_uncore_frequency_tpmi driver sysfs does not exist!"
  else
    for line in $lines; do
      test_print_trc "$line"
    done
  fi
}

ufs_init_min_max_value() {
  [[ -d "$UFS_SYSFS_PATH" ]] || die "$UFS_SYSFS_PATH does not exist"
  per_die_num=$(ls "$UFS_SYSFS_PATH" | grep -c uncore)
  test_print_trc "Uncore number: $per_die_num"
  [[ "$per_die_num" = 0 ]] && block_test "Uncore number is 0"
  for ((i = 1; i <= per_die_num; i++)); do
    per_die=$(ls "$UFS_SYSFS_PATH" | grep uncore | sed -n "$i,1p")
    init_min=$(cat $UFS_SYSFS_PATH/"$per_die"/initial_min_freq_khz)
    [[ -n "$init_min" ]] || block_test "initial_min_freq_khz is not available"
    init_max=$(cat $UFS_SYSFS_PATH/"$per_die"/initial_max_freq_khz)
    [[ -n "$init_max" ]] || block_test "initial_max_freq_khz is not available"
    do_cmd "grep . $UFS_SYSFS_PATH/$per_die/*"
    if [ "$init_min" -ne 0 ] && [ "$init_max" -ne 0 ]; then
      test_print_trc "$per_die shows UFS initial min freq and initial max freq value non-zero."
    else
      die "$per_die shows UFS initial uncore freq value is not correct."
      do_cmd "grep . $UFS_SYSFS_PATH/$per_die/*"
    fi
  done
}

min_equals_to_max() {
  # Test Uncore freq is based on per die, this function is to set
  # Min_freq_khz to the same value of initial_max_freq_khz
  [[ -d "$UFS_SYSFS_PATH" ]] || die "$UFS_SYSFS_PATH does not exist"
  per_die_num=$(ls "$UFS_SYSFS_PATH" | grep -c uncore)
  test_print_trc "Uncore number: $per_die_num"
  [[ "$per_die_num" = 0 ]] && block_test "Uncore number is 0"
  for ((i = 1; i <= per_die_num; i++)); do
    per_die=$(ls "$UFS_SYSFS_PATH" | grep uncore | sed -n "$i,1p")

    init_max=$(cat $UFS_SYSFS_PATH/"$per_die"/initial_max_freq_khz)
    [[ -n "$init_max" ]] || block_test "initial_max_freq_khz is not available"
    default_min=$(cat $UFS_SYSFS_PATH/"$per_die"/min_freq_khz)
    do_cmd "echo $init_max > $UFS_SYSFS_PATH/$per_die/min_freq_khz"
    test_print_trc "Test frequency is: $init_max khz"
    test_print_trc "Test $per_die Uncore freq: Set min_freq_khz equals to \
the initial_max_freq_khz."
    do_cmd "grep . $UFS_SYSFS_PATH/$per_die/*"

    # Run memory stress using stress tool
    mem_avail=$(grep MemAvailable /proc/meminfo | awk -F " " '{print $2}')
    mem_test=$(echo "$mem_avail"/20000000 | bc)
    test_print_trc "Will run memory stress with $mem_test vm workers for $per_die"
    do_cmd "stress --vm $mem_test --vm-bytes 1024M -t 90 &"
    stress_pid=$!

    sleep 30
    # Get uncore current_freq_khz after mem stress running 30 seconds
    current_freq=$(cat $UFS_SYSFS_PATH/"$per_die"/current_freq_khz)
    test_print_trc "$per_die current freq is: $current_freq khz"

    sleep 5
    # Kill stress threads
    [ -n "$stress_pid" ] && do_cmd "kill -9 $stress_pid"

    # Recover min_freq_khz to the default value
    test_print_trc "Recover $per_die min_freq_khz to the default value:"
    do_cmd "echo $default_min > $UFS_SYSFS_PATH/$per_die/min_freq_khz"
    do_cmd "grep . $UFS_SYSFS_PATH/$per_die/*"

    # Uncore Current freq should equal to the max freq
    if [ "$current_freq" -eq "$init_max" ]; then
      test_print_trc "$per_die shows Uncore current freq $current_freq equals to \
the max test freq $init_max khz"
    else
      die "$per_die shows Ucore current freq $current_freq is beyond \
the max test freq $init_max khz"
    fi
  done
}

max_equals_to_min() {
  # Test Uncore freq is based on per die, this function is to set
  # Max_freq_khz to the same value of initial_min_freq_khz
  [[ -d "$UFS_SYSFS_PATH" ]] || die "$UFS_SYSFS_PATH does not exist"
  per_die_num=$(ls "$UFS_SYSFS_PATH" | grep -c uncore)
  test_print_trc "Uncore number: $per_die_num"
  [[ "$per_die_num" = 0 ]] && block_test "Uncore number is 0"
  for ((i = 1; i <= per_die_num; i++)); do
    per_die=$(ls "$UFS_SYSFS_PATH" | grep uncore | sed -n "$i,1p")

    init_min=$(cat $UFS_SYSFS_PATH/"$per_die"/initial_min_freq_khz)
    [[ -n "$init_min" ]] || block_test "initial_min_freq_khz is not available"
    default_max=$(cat $UFS_SYSFS_PATH/"$per_die"/max_freq_khz)
    do_cmd "echo $init_min > $UFS_SYSFS_PATH/$per_die/max_freq_khz"
    test_print_trc "Test frequency is: $init_min khz"
    test_print_trc "Test $per_die Uncore freq: Set max_freq_khz equals to \
the initial_min_freq_khz."
    do_cmd "grep . $UFS_SYSFS_PATH/$per_die/*"

    # Run memory stress using stress tool
    mem_avail=$(grep MemAvailable /proc/meminfo | awk -F " " '{print $2}')
    mem_test=$(echo "$mem_avail"/20000000 | bc)
    test_print_trc "Will run memory stress with $mem_test vm workers for $per_die"
    do_cmd "stress --vm $mem_test --vm-bytes 1024M -t 90 &"
    stress_pid=$!

    sleep 30
    # Get uncore current_freq_khz after mem stress running 30 seconds
    current_freq=$(cat $UFS_SYSFS_PATH/"$per_die"/current_freq_khz)
    test_print_trc "$per_die current freq is: $current_freq khz"

    sleep 5
    # Kill stress threads
    [ -n "$stress_pid" ] && do_cmd "kill -9 $stress_pid"

    # Recover max_freq_khz to the default value
    test_print_trc "Recover $per_die max_freq_khz to the default value:"
    do_cmd "echo $default_max > $UFS_SYSFS_PATH/$per_die/max_freq_khz"
    do_cmd "grep . $UFS_SYSFS_PATH/$per_die/*"

    # Uncore Current freq should be less than the max freq
    if [ "$current_freq" -eq "$init_min" ]; then
      test_print_trc "$per_die shows Uncore current freq $current_freq equals to \
the max test freq $init_min khz"
    else
      die "$per_die shows Uncore current freq $current_freq is beyond \
the max test freq $init_min khz"
    fi
  done
}

min_max_dynamic() {
  local test_freq

  # Test Uncore freq is based on per die, this function is to set test freq to
  # current_freq_khz value + 100000 khz
  [[ -d "$UFS_SYSFS_PATH" ]] || die "$UFS_SYSFS_PATH does not exist"
  per_die_num=$(ls "$UFS_SYSFS_PATH" | grep -c uncore)
  test_print_trc "Uncore number: $per_die_num"
  [[ "$per_die_num" = 0 ]] && block_test "Uncore number is 0"
  for ((i = 1; i <= per_die_num; i++)); do
    per_die=$(ls "$UFS_SYSFS_PATH" | grep uncore | sed -n "$i,1p")

    # Test freq will be default current_freq + 100 Mhz
    default_current_freq=$(cat $UFS_SYSFS_PATH/"$per_die"/current_freq_khz)
    [[ -n "$default_current_freq" ]] || block_test "current_freq_khz is not available."
    test_freq=$(("$default_current_freq" + 100000))
    test_print_trc "Test frequency is: $test_freq khz"
    # Save default init min and init max freq value
    default_min=$(cat $UFS_SYSFS_PATH/"$per_die"/min_freq_khz)
    default_max=$(cat $UFS_SYSFS_PATH/"$per_die"/max_freq_khz)
    # Set min freq and max to test freq
    do_cmd "echo $test_freq > $UFS_SYSFS_PATH/$per_die/min_freq_khz"
    do_cmd "echo $test_freq > $UFS_SYSFS_PATH/$per_die/max_freq_khz"
    test_print_trc "Test $per_die Uncore freq: Set min_freq_khz and max_freq_khz \
equals to current_freq_khz + 100000 khz"
    do_cmd "grep . $UFS_SYSFS_PATH/$per_die/*"

    # Run memory stress using stress tool
    mem_avail=$(grep MemAvailable /proc/meminfo | awk -F " " '{print $2}')
    mem_test=$(echo "$mem_avail"/20000000 | bc)
    test_print_trc "Will run memory stress with $mem_test vm workers for $per_die"
    do_cmd "stress --vm $mem_test --vm-bytes 1024M -t 90 &"
    stress_pid=$!

    sleep 30
    # Get uncore current_freq_khz after mem stress running 30 seconds
    current_freq=$(cat $UFS_SYSFS_PATH/"$per_die"/current_freq_khz)
    test_print_trc "$per_die current freq is: $current_freq khz"

    sleep 5
    # Kill stress threads
    [ -n "$stress_pid" ] && do_cmd "kill -9 $stress_pid"

    # Recover the min_freq_khz and max_freq_khz
    test_print_trc "Recover $per_die default min_freq_khz and max_freq_khz values:"
    do_cmd "echo $default_min > $UFS_SYSFS_PATH/$per_die/min_freq_khz"
    do_cmd "echo $default_max > $UFS_SYSFS_PATH/$per_die/max_freq_khz"
    do_cmd "grep . $UFS_SYSFS_PATH/$per_die/*"

    # Uncore Current freq should equal to the test freq
    if [ "$current_freq" -eq "$test_freq" ]; then
      test_print_trc "$per_die shows Uncore current freq $current_freq equals to \
min and max test freq $test_freq khz"
    else
      die "$per_die shows Uncore current freq $current_freq is beyond \
min and max test freq $test_freq khz"
    fi
  done
}

pkg_max_min_freq_change() {
  [[ -d "$UFS_SYSFS_PATH" ]] || die "$UFS_SYSFS_PATH does not exist"
  pkg_num=$(ls "$UFS_SYSFS_PATH" | grep -c package)
  test_print_trc "Package number: $pkg_num"
  [[ "$pkg_num" = 0 ]] && block_test "Package number is 0"

  # All the packages initial_max_freq_khz and initial_min_freq_khz are same at boot
  # So set test_max_freq and test_min_freq by referring any package
  pkg0=$(ls "$UFS_SYSFS_PATH" | grep package | sed -n "1,1p" 2>&1)
  [[ -n "$pkg0" ]] || block_test "UFS package knob is not available."

  # Check pkg initial_max_freq_khz and initial_min_freq_khz is non-zero
  initial_max_freq=$(cat $UFS_SYSFS_PATH/"$pkg0"/initial_max_freq_khz)
  [[ -n "$initial_max_freq" ]] || block_test "initial_max_freq_khz for $pkg0 is not available."
  [[ "$initial_max_freq" -eq 0 ]] && die "initial_max_freq_khz for $pkg0 is zero."
  initial_min_freq=$(cat $UFS_SYSFS_PATH/"$pkg0"/initial_min_freq_khz)
  [[ -n "$initial_min_freq" ]] || block_test "initial_min_freq_khz for $pkg0 is not available."
  [[ "$initial_min_freq" -eq 0 ]] && die "initial_min_freq_khz for $pkg0 is zero."

  # Save default init min init max freq value
  default_min=$(cat $UFS_SYSFS_PATH/"$pkg0"/min_freq_khz)
  [[ -n "$default_min" ]] || block_test "default_min for $pkg0 is not available."
  default_max=$(cat $UFS_SYSFS_PATH/"$pkg0"/max_freq_khz)
  [[ -n "$default_max" ]] || block_test "default_max for $pkg0 is not available."

  # Set test_max_freq to initial_max_freq_khz - 200MHz
  # Set test_min_freq to initial_min_freq_khz + 200MHz
  test_max_freq=$(("$initial_max_freq" - 200000))
  test_print_trc "Test max freq is: $test_max_freq khz"
  test_min_freq=$(("$initial_min_freq" + 200000))
  test_print_trc "Test min freq is: $test_min_freq khz"

  # Change max_freq_khz and min_freq_khz by package
  for ((i = 1; i <= pkg_num; i++)); do
    per_pkg=$(ls "$UFS_SYSFS_PATH" | grep package | sed -n "$i,1p")

    # Set min freq and max to test freq
    do_cmd "echo $test_max_freq > $UFS_SYSFS_PATH/$per_pkg/max_freq_khz"
    do_cmd "echo $test_min_freq > $UFS_SYSFS_PATH/$per_pkg/min_freq_khz"
    test_print_trc "Setting $per_pkg max_freq and min_freq to initial_max_freq - 200000 khz \
  and initial_min_freq + 200000 khz"
    do_cmd "grep . $UFS_SYSFS_PATH/*/max_freq_khz"
    do_cmd "grep . $UFS_SYSFS_PATH/*/min_freq_khz"
  done

  # All the uncore max_freq_khz knobs under related pkg should be set to the same value as pkg.
  for ((i = 1; i <= pkg_num; i++)); do
    per_pkg=$(ls "$UFS_SYSFS_PATH" | grep package | sed -n "$i,1p")
    max_freq_lines=$(grep . $UFS_SYSFS_PATH/*/max_freq_khz | wc -l)
    for ((j = 1; j <= max_freq_lines; j++)); do
      actual_max_freq_per_line=$(cat $UFS_SYSFS_PATH/*/max_freq_khz | sed -n "$j,1p")
      test_print_trc "The max_freq_khz for line $j: $actual_max_freq_per_line khz"
      if [[ $actual_max_freq_per_line -eq $test_max_freq ]]; then
        test_print_trc "$actual_max_freq_per_line is expected "
      else
        # Recover the default setting
        do_cmd "echo $default_max > $UFS_SYSFS_PATH/$per_pkg/max_freq_khz"
        die "There is unexpected max_freq_khz after per pkg change."
      fi
    done
  done

  # All the uncore min_freq_khz knobs under related pkg should be set to the same value as pkg.
  for ((i = 1; i <= pkg_num; i++)); do
    per_pkg=$(ls "$UFS_SYSFS_PATH" | grep package | sed -n "$i,1p")
    min_freq_lines=$(grep . $UFS_SYSFS_PATH/*/min_freq_khz | wc -l)
    for ((k = 1; k <= min_freq_lines; k++)); do
      actual_min_freq_per_line=$(cat $UFS_SYSFS_PATH/*/min_freq_khz | sed -n "$k,1p")
      test_print_trc "The min_freq_khz for line $k: $actual_min_freq_per_line khz"
      if [[ $actual_min_freq_per_line -eq $test_min_freq ]]; then
        test_print_trc "$actual_min_freq_per_line is expected "
      else
        # Recover the default setting
        do_cmd "echo $default_min > $UFS_SYSFS_PATH/$per_pkg/min_freq_khz"
        die "There is unexpected min_freq_khz after per pkg change."
      fi
    done
  done

  # Recover the default setting
  for ((i = 1; i <= pkg_num; i++)); do
    per_pkg=$(ls "$UFS_SYSFS_PATH" | grep package | sed -n "$i,1p")
    do_cmd "echo $default_max > $UFS_SYSFS_PATH/$per_pkg/max_freq_khz"
    do_cmd "echo $default_min > $UFS_SYSFS_PATH/$per_pkg/min_freq_khz"
    test_print_trc "Setting $per_pkg max_freq and min_freq to default value."
    do_cmd "grep . $UFS_SYSFS_PATH/*/max_freq_khz"
    do_cmd "grep . $UFS_SYSFS_PATH/*/min_freq_khz"
  done
}

tpmi_ufs_test() {
  case $TEST_SCENARIO in
  check_ufs_unbind_bind)
    ufs_unbind_bind
    ;;
  check_ufs_device)
    ufs_device_per_package
    ;;
  check_ufs_sysfs_attr)
    ufs_sysfs_attr
    ;;
  check_ufs_init_min_max_value)
    ufs_init_min_max_value
    ;;
  check_ufs_min_equals_to_max)
    min_equals_to_max
    ;;
  check_ufs_max_equals_to_min)
    max_equals_to_min
    ;;
  check_ufs_current_dynamic)
    min_max_dynamic
    ;;
  check_per_pkg_min_max_change)
    pkg_max_min_freq_change
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

tpmi_ufs_test
