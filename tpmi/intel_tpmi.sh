#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation
# Description:  Test script for Intel_TPMI(Topology Aware Register and PM Capsule Interface)
# driver which is supported on both Intel® server platforms: GRANITERAPIDS and is
# compatible with subsequent server platforms
# @Author   wendy.wang@intel.com
# @History  Created May 06 2024 - Created

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

TPMI_DRIVER_PATH="/sys/module/intel_vsec_tpmi/drivers/auxiliary"
TPMI_DEBUGFS_PATH="/sys/kernel/debug"

: "${CASE_NAME:=""}"

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-t TESTCASE_ID] [-H]
  -t  TEST CASE ID
  -H  show this
__EOF
}

get_vsec_oobmsm_device() {
  dev_lines=$(lspci -d 8086:09a7 | wc -l 2>&1)
  if [[ $dev_lines == 0 ]]; then
    dev_lines=$(lspci -d 8086:09a1 | wc -l 2>&1)
  fi
  [[ "$dev_lines" -ne 0 ]] || block_test "Did not detect tpmi pci device."
}

unload_module() {
  # $1 is the driver module name
  local module_name=$1
  is_kmodule_builtin "$module_name" && skip_test
  load_unload_module.sh -c -d "$module_name" &&
    do_cmd "load_unload_module.sh -u -d $module_name"
}

load_module() {
  # $1 is the driver module name
  local module_name=$1
  is_kmodule_builtin "$module_name" && skip_test
  do_cmd "load_unload_module.sh -l -d $module_name" &&
    load_unload_module.sh -c -d "$module_name"
}

tpmi_driver_interface() {
  test_print_trc "Check intel_vsec_tpmi driver interface:"

  [[ -d "$TPMI_DRIVER_PATH":intel_vsec_tpmi ]] ||
    die "intel_vsec_tpmi driver SYSFS does not exist!"

  lines=$(ls "$TPMI_DRIVER_PATH":intel_vsec_tpmi 2>&1)
  for line in $lines; do
    test_print_trc "$line"
  done
}

tpmi_debugfs_interface() {
  local socket_num
  local tpmi_debugfs_instance
  local tpmi_debugfs_instance_num
  local tpmi_pci_device

  socket_num=$(lscpu | grep "Socket(s)" | awk -F " " '{print $2}' 2>&1)
  test_print_trc "Check how many socket the system supports: $socket_num"

  tpmi_debugfs_instance=$(ls "$TPMI_DEBUGFS_PATH" | grep "tpmi-*" 2>&1)
  tpmi_debugfs_instance_num=$(ls "$TPMI_DEBUGFS_PATH" | grep -c "tpmi-*" 2>&1)
  test_print_trc "Check how many intel_vesc_tpmi debugfs instance:"
  test_print_trc "$tpmi_debugfs_instance"

  get_vsec_oobmsm_device

  test_print_trc "Check tpmi pci device:"
  tpmi_pci_device=$(lspci -d 8086:09a7 2>&1)
  test_print_trc "$tpmi_pci_device"

  if [[ -n "$tpmi_debugfs_instance" ]] && [[ -n "$tpmi_pci_device" ]] &&
    [[ "$socket_num" -eq "$tpmi_debugfs_instance_num" ]] &&
    [[ "$socket_num" -eq "$dev_lines" ]]; then
    test_print_trc "intel_vsec_tpmi 09a7 debugfs file exist and instance number is correct"
  elif [[ -z "$tpmi_pci_device" ]]; then
    tpmi_pci_device=$(lspci -d 8086:09a1 2>&1)
    socket_num=$((socket_num * 2))
    if [[ -n "$tpmi_debugfs_instance" ]] && [[ -n "$tpmi_pci_device" ]] &&
      [[ "$socket_num" -eq "$tpmi_debugfs_instance_num" ]] &&
      [[ "$socket_num" -eq "$dev_lines" ]]; then
      test_print_trc "intel_vsec_tpmi debugfs file exist and instance number is correct"
    else
      die "intel_vsec_tpmi 09a1 debugfs file and instance number is not correct!"
    fi
  else
    die "intel_vsec_tpmi debugfs is not correct!"
  fi

  lines=$(ls -A "$TPMI_DEBUGFS_PATH"/tpmi-* 2>&1)
  for line in $lines; do
    test_print_trc "$line"
  done
}

# PFS: PM Feature Structure
dump_pfs_pm_feature_list() {
  local expected_tpmi_id="0x80 0x00 0x01 0x02 0x03 0x04 0x05 0x0a 0x06 0x0c 0x0d 0x81 0xfd 0xfe 0xff"
  local test_tpmi_id=""
  local line_num=""
  local dev_name=""
  local pfs_item=""

  get_vsec_oobmsm_device

  test_print_trc "Dump PM Feature Structure:"
  for ((i = 1; i <= dev_lines; i++)); do
    dev_name=$(lspci -d 8086:09a7 | awk -F " " '{print $1}' | sed -n "$i, 1p")
    [[ -e "$TPMI_DEBUGFS_PATH"/tpmi-0000:"$dev_name"/pfs_dump ]] ||
      block_test "tpmi debugfs pfs_dump does not exist."
    test_print_trc "The $TPMI_DEBUGFS_PATH/tpmi-0000:$dev_name/pfs_dump is:"
    cat "$TPMI_DEBUGFS_PATH"/tpmi-0000:"$dev_name"/pfs_dump 2>&1
  done

  test_print_trc "Check if all the PFS TPMI_ID are expected:"
  # Calculate the tpmi debugfs device lines num
  for ((i = 1; i <= dev_lines; i++)); do
    dev_name=$(lspci -d 8086:09a7 | awk -F " " '{print $1}' | sed -n "$i, 1p")

    # Calculate the TPMI_ID lines num
    line_num=$(awk 'END { print NR}' "$TPMI_DEBUGFS_PATH"/tpmi-0000:"$dev_name"/pfs_dump 2>&1)
    # Calculate if the pfs_dump shows the duplicated features
    pfs_item=$(uniq -c "$TPMI_DEBUGFS_PATH"/tpmi-0000:"$dev_name"/pfs_dump | wc -l 2>&1)
    [[ $pfs_item -eq 17 ]] || die "$TPMI_DEBUGFS_PATH/tpmi-0000:$dev_name/pfs_dump \
shows feature list is not align with spec."

    # Check each TPMI_ID in PFS dump
    for ((j = 3; j <= line_num; j++)); do
      test_tpmi_id=$(awk '{print $1}' "$TPMI_DEBUGFS_PATH"/tpmi-0000:"$dev_name"/pfs_dump 2>&1 |
        sed -n "$j, 1p")
      if [[ $expected_tpmi_id =~ $test_tpmi_id ]]; then
        test_print_trc "PFS TPMI_ID $test_tpmi_id in tpmi-0000:$dev_name is detected."
      else
        die "PFS TPMI_ID $test_tpmi_id in tpmi-0000:$dev_name is not detected."
      fi
    done
  done
}

dump_pfs_lock_disable_status() {
  local line_num=""
  local dev_name=""
  local disabled_status=""

  get_vsec_oobmsm_device

  test_print_trc "Check intel_vsec_tpmi dump_pfs lock and disable status:"
  for ((i = 1; i <= dev_lines; i++)); do
    dev_name=$(lspci -d 8086:09a7 | awk -F " " '{print $1}' | sed -n "$i, 1p")
    if [[ -n "$dev_name" ]]; then
      [[ -e "$TPMI_DEBUGFS_PATH"/tpmi-0000:"$dev_name"/pfs_dump ]] ||
        block_test "tpmi debugfs pfs_dump does not exist."
      test_print_trc "The $TPMI_DEBUGFS_PATH/tpmi-0000:$dev_name/pfs_dump is:"
      cat "$TPMI_DEBUGFS_PATH"/tpmi-0000:"$dev_name"/pfs_dump 2>&1

      disabled_status=$(awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' "$TPMI_DEBUGFS_PATH"/tpmi-0000:"$dev_name"/pfs_dump |
        grep "disabled")
      test_print_trc "Filtered pfs_dump disabled_status: $disabled_status"

      if [[ -n "$disabled_status" ]] && [[ $disabled_status =~ Y ]]; then
        die "intel_vsec_tpmi pfs dump shows there is pm feature disabled!"
      elif [[ -n "$disabled_status" ]] && [[ $disabled_status =~ U ]]; then
        die "intel_vsec_tpmi pfs dump shows Unknown disabled status."
      else
        test_print_trc "intel_vsec_tpmi PM features pfs_dump shows disabled status is OK"
      fi

    else
      dev_name=$(lspci -d 8086:09a1 | awk -F " " '{print $1}' | sed -n "$i, 1p")

      [[ -e "$TPMI_DEBUGFS_PATH"/tpmi-"$dev_name"/pfs_dump ]] ||
        block_test "tpmi debugfs pfs_dump does not exist."
      test_print_trc "The $TPMI_DEBUGFS_PATH/tpmi-$dev_name/pfs_dump is:"
      cat "$TPMI_DEBUGFS_PATH"/tpmi-"$dev_name"/pfs_dump 2>&1

      disabled_status=$(awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' "$TPMI_DEBUGFS_PATH"/tpmi-"$dev_name"/pfs_dump |
        grep "disabled")
      test_print_trc "Filtered pfs_dump disabled_status: $disabled_status"

      if [[ -n "$disabled_status" ]] && [[ $disabled_status =~ Y ]]; then
        die "intel_vsec_tpmi pfs dump shows there is pm feature disabled!"
      elif [[ -n "$disabled_status" ]] && [[ $disabled_status =~ U ]]; then
        die "intel_vsec_tpmi pfs dump shows Unknown disabled status."
      else
        test_print_trc "intel_vsec_tpmi PM features pfs_dump shows disabled status is OK"
      fi
    fi
  done
}

#All the tpmi_id pm features' mem_dump should show non-zero value
tpmi_id_mem_value_read() {
  local id=$1
  local dev_name=""
  local mem_value=""

  get_vsec_oobmsm_device

  test_print_trc "Check TPMI_ID PM feature's mem_dump value:"
  for ((i = 1; i <= dev_lines; i++)); do

    dev_name=$(lspci -d 8086:09a7 | awk -F " " '{print $1}' | sed -n "$i, 1p" 2>&1)
    if [[ -n "$dev_name" ]]; then
      test_print_trc "$TPMI_DEBUGFS_PATH/tpmi-0000:$dev_name/tpmi-id-$id/mem_dump is:"
      if [[ -e "$TPMI_DEBUGFS_PATH/tpmi-0000:$dev_name/tpmi-id-$id/mem_dump" ]]; then
        cat "$TPMI_DEBUGFS_PATH"/tpmi-0000:"$dev_name"/tpmi-id-"$id"/mem_dump
      else
        die "$TPMI_DEBUGFS_PATH/tpmi-0000:$dev_name/tpmi-id-$id/mem_dump does not exist."
      fi
      mem_value=$(cut -d ] -f 2 "$TPMI_DEBUGFS_PATH"/tpmi-0000:"$dev_name"/tpmi-id-"$id"/mem_dump 2>&1 |
        sed -n '/[1-9a-fA-F]/p')
      if [[ -z "$mem_value" ]]; then
        die "The tpmi-0000:$dev_name tpmi-id-$id pm feature mem_value is not expected"
      else
        test_print_trc "The tpmi-0000:$dev_name tpmi-id-$id pm feature mem_value is non-zero."
      fi

    else
      dev_name=$(lspci -d 8086:09a1 | awk -F " " '{print $1}' | sed -n "$i, 1p")
      test_print_trc "$TPMI_DEBUGFS_PATH/tpmi-$dev_name/tpmi-id-$id/mem_dump is:"
      if [[ -e "$TPMI_DEBUGFS_PATH/tpmi-$dev_name/tpmi-id-$id/mem_dump" ]]; then
        cat "$TPMI_DEBUGFS_PATH"/tpmi-"$dev_name"/tpmi-id-"$id"/mem_dump
      else
        die "$TPMI_DEBUGFS_PATH/tpmi-$dev_name/tpmi-id-$id/mem_dump does not exist."
      fi
      mem_value=$(cut -d ] -f 2 "$TPMI_DEBUGFS_PATH"/tpmi-"$dev_name"/tpmi-id-"$id"/mem_dump 2>&1 |
        sed -n '/[1-9a-fA-F]/p')
      if [[ -z "$mem_value" ]]; then
        die "The tpmi-$dev_name tpmi-id-$id pm feature mem_value is not expected"
      else
        test_print_trc "The tpmi-$dev_name tpmi-id-$id pm feature mem_value is non-zero."
      fi
    fi
  done
}

mem_write_read() {
  local dev_name=""
  local mem_ori=""
  local mem_aft=""

  get_vsec_oobmsm_device

  test_print_trc "Check mem_write and mem_dump:"
  for ((i = 1; i <= dev_lines; i++)); do
    dev_name=$(lspci -d 8086:09a7 | awk -F " " '{print $1}' | sed -n "$i, 1p")
    if [[ -n "$dev_name" ]]; then
      test_print_trc "Choose tpmi-id-02 UFS feature to check mem_write and mem_dump for device $dev_name:"
      mem_ori=$(cat $TPMI_DEBUGFS_PATH/tpmi-0000:"$dev_name"/tpmi-id-02/mem_dump | grep "00000020" | head -1 | awk '{print $2}')
      test_print_trc "The tpmi-id-02 feature instance 0 mem original value at 0x0020 is: $mem_ori"
      test_print_trc "Will write 0x1234 to tpmi-id-02 UFS feature instance 0 with mem address 0x0020"
      do_cmd "echo 0,0x20,0x1234 > $TPMI_DEBUGFS_PATH/tpmi-0000:$dev_name/tpmi-id-02/mem_write"

      test_print_trc "Confirm if mem_write successful:"
      mem_aft=$(cat $TPMI_DEBUGFS_PATH/tpmi-0000:"$dev_name"/tpmi-id-02/mem_dump | grep "00000020" | head -1 | awk '{print $2}')
      test_print_trc "The tpmi-id-02 UFS feature mem value after writing 0x1234 at 0x0020 is: $mem_aft"
      if [[ "$mem_aft" == 00001234 ]]; then
        test_print_trc "mem_write is successful."
      else
        die "mem_dump is not expected after mem_write: $mem_aft"
      fi

      test_print_trc "Recover mem_dump to the original value:"
      do_cmd "echo 0,0x20,0x$mem_ori > $TPMI_DEBUGFS_PATH/tpmi-0000:$dev_name/tpmi-id-02/mem_write"

    else
      dev_name=$(lspci -d 8086:09a1 | awk -F " " '{print $1}' | sed -n "$i, 1p")

      test_print_trc "Choose tpmi-id-02 UFS feature to check mem_write and mem_dump for device $dev_name:"
      mem_ori=$(cat $TPMI_DEBUGFS_PATH/tpmi-"$dev_name"/tpmi-id-02/mem_dump | grep "00000020" | head -1 | awk '{print $2}')
      test_print_trc "The tpmi-id-02 feature instance 0 mem original value at 0x0020 is: $mem_ori"
      test_print_trc "Will write 0x1234 to tpmi-id-02 UFS feature instance 0 with mem address 0x0020"
      do_cmd "echo 0,0x20,0x1234 > $TPMI_DEBUGFS_PATH/tpmi-$dev_name/tpmi-id-02/mem_write"

      test_print_trc "Confirm if mem_write successful:"
      mem_aft=$(cat $TPMI_DEBUGFS_PATH/tpmi-"$dev_name"/tpmi-id-02/mem_dump | grep "00000020" | head -1 | awk '{print $2}')
      test_print_trc "The tpmi-id-02 UFS feature mem value after writing 0x1234 at 0x0020 is: $mem_aft"
      if [[ "$mem_aft" == 00001234 ]]; then
        test_print_trc "mem_write is successful."
      else
        die "mem_dump is not expected after mem_write: $mem_aft"
      fi

      test_print_trc "Recover mem_dump to the original value:"
      do_cmd "echo 0,0x20,0x$mem_ori > $TPMI_DEBUGFS_PATH/tpmi-$dev_name/tpmi-id-02/mem_write"

    fi
  done
}

dmesg_check() {
  local dmesg_log

  dmesg_log=$(extract_case_dmesg)

  if echo "$dmesg_log" | grep -iE "fail|Call Trace|error"; then
    die "Kernel dmesg shows failure: $dmesg_log"
  else
    test_print_trc "Kernel dmesg shows Okay."
  fi
  should_fail "extract_case_dmesg | grep Unsupported"
}

intel_tpmi_test() {
  case $TEST_SCENARIO in
  tpmi_remove_all_drivers)
    unload_module intel_rapl_tpmi
    unload_module isst_tpmi
    unload_module isst_tpmi_core
    unload_module isst_if_mmio
    unload_module intel_uncore_frequency_tpmi
    unload_module intel_vsec_tpmi
    unload_module intel_vsec
    load_module intel_vsec
    load_module intel_vsec_tpmi
    load_module intel_rapl_tpmi
    load_module isst_if_mmio
    load_module isst_tpmi_core
    load_module isst_tpmi
    load_module intel_uncore_frequency_tpmi
    ;;
  tpmi_sysfs)
    tpmi_driver_interface
    ;;
  tpmi_debugfs)
    tpmi_debugfs_interface
    ;;
  pm_feature_list)
    dump_pfs_pm_feature_list
    ;;
  dump_pfs_locked_disabled_status)
    dump_pfs_lock_disable_status
    ;;
  mem_value_00)
    tpmi_id_mem_value_read 00
    ;;
  mem_value_01)
    tpmi_id_mem_value_read 01
    ;;
  mem_value_02)
    tpmi_id_mem_value_read 02
    ;;
  mem_value_03)
    tpmi_id_mem_value_read 03
    ;;
  mem_value_04)
    tpmi_id_mem_value_read 04
    ;;
  mem_value_05)
    tpmi_id_mem_value_read 05
    ;;
  mem_value_0a)
    tpmi_id_mem_value_read 0a
    ;;
  mem_value_06)
    tpmi_id_mem_value_read 06
    ;;
  mem_value_0c)
    tpmi_id_mem_value_read 0c
    ;;
  mem_value_0d)
    tpmi_id_mem_value_read 0d
    ;;
  mem_value_80)
    tpmi_id_mem_value_read 80
    ;;
  mem_value_81)
    tpmi_id_mem_value_read 81
    ;;
  mem_value_fd)
    tpmi_id_mem_value_read fd
    ;;
  mem_value_fe)
    tpmi_id_mem_value_read fe
    ;;
  mem_value_ff)
    tpmi_id_mem_value_read ff
    ;;
  mem_write_read)
    mem_write_read
    ;;
  esac
  dmesg_check
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

intel_tpmi_test
