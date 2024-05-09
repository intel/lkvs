#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation
# Description:  Test script for Intel® On Demand driver
# driver which is supported on Intel® server platforms
# @Author   wendy.wang@intel.com
# @History  Created May 15 2023 - Created

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

SDSI_DRIVER_PATH="/sys/module/intel_sdsi/drivers/auxiliary"
SDSI_DRIVER_NODE_PATH="/sys/bus/auxiliary/devices"
[[ -n $SDSI_DRIVER_NODE_PATH ]] || block_test "SDSi driver node is not available."
SOCKET_NUM=$(lscpu | grep "Socket(s)" | awk -F " " '{print $2}' 2>&1)
[[ -n $SOCKET_NUM ]] || block_test "Socket number is not available."

: "${CASE_NAME:=""}"

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-t TESTCASE_ID] [-H]
  -t  TEST CASE ID
  -H  show this
__EOF
}

sdsi_unbind_bind() {
  for ((i = 0; i < "$SOCKET_NUM"; i++)); do
    test_print_trc "Do intel_vsec.sdsi.$i unbind"
    do_cmd "echo intel_vsec.sdsi.$i > /sys/bus/auxiliary/drivers/intel_sdsi/unbind"
    test_print_trc "Do intel_vsec.sdsi.$i bind"
    do_cmd "echo intel_vsec.sdsi.$i > /sys/bus/auxiliary/drivers/intel_sdsi/bind"
  done
}

sdsi_driver_interface() {
  test_print_trc "Check Intel_SDSi driver interface:"

  [[ -d "$SDSI_DRIVER_PATH":intel_sdsi ]] ||
    die "intel sdsi driver sysfs does not exist!"

  lines=$(ls "$SDSI_DRIVER_PATH":intel_sdsi 2>&1)
  for line in $lines; do
    test_print_trc "$line"
  done
}

# intel_sdsi user space tool is required to run cases
if which intel_sdsi 1>/dev/null 2>&1; then
  intel_sdsi -l 1>/dev/null || block_test "Failed to run intel_sdsi tool,
please check tool error message."
else
  block_test "intel_sdsi tool is required to run cases,
please get it from latest upstream kernel tools: tools/arch/x86/intel_sdsi/intel_sdsi.c"
fi

# Hex read SDSi sysfs attribute files:registers,state_certificate
# Meter_telemetry feature only supports on GNR and further platforms
sdsi_sysfs_attribute() {
  local attri=$1

  legacy_model_list="143 207"
  model=$(sed -n '/model/p' /proc/cpuinfo | head -1 | awk '{print $3}' 2>&1)
  if [[ "$attri" == meter_certificate ]] && [[ $legacy_model_list =~ $model ]]; then
    block_test "Legacy platform does not support meter_certificate sysfs"
  fi

  test_print_trc "Check how many sockets the system supports: $SOCKET_NUM"

  test_print_trc "Check Intel SDSi $attri sysfs:"
  for ((i = 0; i < "$SOCKET_NUM"; i++)); do
    attri=$(ls "$SDSI_DRIVER_NODE_PATH"/intel_vsec.sdsi."$i" | grep "$attri" 2>&1)
    if [[ "$attri" != "" ]]; then
      test_print_trc "The $attri file for intel_vsec.sdsi.$i is available:"
      do_cmd "xxd $SDSI_DRIVER_NODE_PATH/intel_vsec.sdsi.$i/$attri"
    else
      die "The $attri file for intel_vsec.sdsi.$i is not available."
    fi
  done
}

sdsi_driver_node_per_socket() {
  local sdsi_node

  test_print_trc "Check how many socket the system supports: $SOCKET_NUM"
  sdsi_node=$(ls "$SDSI_DRIVER_NODE_PATH" | grep -c sdsi 2>&1)
  test_print_trc "Check Intel_SDSi driver node number: $sdsi_node"
  if [[ "$sdsi_node" = "$SOCKET_NUM" ]]; then
    test_print_trc "intel_sdsi driver node per socket exist!"
  else
    die "intel_sdsi driver node per socket does not exist!"
  fi

  lines=$(ls -A "$SDSI_DRIVER_NODE_PATH"/intel_vsec.sdsi.* 2>&1)
  for line in $lines; do
    test_print_trc "$line"
  done
}

available_sdsi_devices() {
  local sdsi_device

  sdsi_device=$(intel_sdsi -l)
  if [[ -n "$sdsi_device" ]]; then
    test_print_trc "Available SDSi devices:"
    test_print_trc "$sdsi_device"
  else
    die "Fails to get sdsi devices: $sdsi_device"
  fi
}

sdsi_ppin() {
  local read_reg
  local ppin

  for ((j = 0; j < "$SOCKET_NUM"; j++)); do
    if read_reg=$(intel_sdsi -d "$j" -i); then
      ppin=$(echo "$read_reg" | grep PPIN | awk -F ":" '{print $2}')
      test_print_trc "PPIN value: $ppin"
      if [[ -n "$ppin" ]]; then
        test_print_trc "SDSI PPIN is available: $ppin"
      else
        die "SDSI PPIN is not available: $ppin"
      fi
    else
      die "$read_reg"
    fi
  done
}

nvram_content_err() {
  local auth_info
  local auth_err

  for ((j = 0; j < "$SOCKET_NUM"; j++)); do
    auth_info=$(intel_sdsi -d "$j" -i)
    test_print_trc "SDSi register info shows: $auth_info"
    if auth_info=$(intel_sdsi -d "$j" -i); then
      auth_err_lines=$(echo "$auth_info" | grep -c "Err Sts")
      for ((i = 1; i <= "$auth_err_lines"; i++)); do
        auth_err=$(echo "$auth_info" | grep "Err Sts" | awk -F ":" '{print $2}')
        test_print_trc "NVRAM Content Authorization Err Status: $auth_err"
        if [[ "$auth_err" =~ Error ]]; then
          die "NVRAM Content Authorization shows Error"
        else
          test_print_trc "Content Authorization Error Status shows Okay"
        fi
      done
    else
      die "$auth_info"
    fi
  done
}

feature_enable() {
  local auth_info
  local feature_enable
  local model

  # For Intel On Demand feature, SAPPHIRERAPIDS(CPU model: 143),
  # EMERALDRAPIDS(CPU model: 207) are legacy platforms,on which
  # Only On Demand feature is supported.
  legacy_model_list="143 207"
  legacy_feature=Demand
  status=Disabled

  model=$(sed -n '/model/p' /proc/cpuinfo | head -1 | awk '{print $3}' 2>&1)

  for ((j = 0; j < "$SOCKET_NUM"; j++)); do
    auth_info=$(intel_sdsi -d "$j" -i)
    test_print_trc "SDSi register info shows: $auth_info"
    if auth_info=$(intel_sdsi -d "$j" -i); then
      for x in Demand Attestation Metering; do
        feature_enable=$(echo "$auth_info" | grep "$x" | awk -F ":" '{print $2}')
        test_print_trc "Feature $x: $feature_enable"
        if [[ "$feature_enable" =~ $status ]] && [[ $legacy_model_list =~ $model ]] &&
          [[ $x =~ $legacy_feature ]]; then
          die "SDSi feature $x is Disabled."
        elif [[ "$feature_enable" =~ $status ]] && [[ $legacy_model_list =~ $model ]]; then
          test_print_trc "SDSi feature $x Disabled is expected for the legacy platform."
        elif [[ "$feature_enable" =~ $status ]]; then
          die "SDSi feature $x is Disabled."
        else
          test_print_trc "The SDSi feature $x is Enabled."
        fi
      done
    else
      die "$auth_info"
    fi
  done
}

# Metering telemetry case only supported on GRANITERAPIDS and further platforms
read_meter_tele() {
  local read_tele

  for ((j = 0; j < "$SOCKET_NUM"; j++)); do
    test_print_trc "Reading SDSi metering telemetry for socket $j"
    if ! read_tele=$(intel_sdsi -d "$j" -m); then
      die "Failed to read SDSi metering telemetry for socket $j: $read_tele"
    else
      test_print_trc "$read_tele"
    fi
  done
}

stress_read_reg() {
  local read_reg
  test_print_trc "Repeat reading SDSi register for 30 cycles:"
  for ((j = 0; j < "$SOCKET_NUM"; j++)); do
    for ((i = 1; i <= 30; i++)); do
      read_reg=$(intel_sdsi -d "$j" -i)
      if ! read_reg=$(intel_sdsi -d "$j" -i); then
        die "Repeat reading SDSi register for socket $j cycles $i Fails"
      else
        test_print_trc "Repeat reading SDSi register for socket $j cycle $i PASS"
      fi
    done
  done
  test_print_trc "$read_reg"
}

# The prerequisite of this case is do AKC and CAP provisioning
# AKC: Authentication Key Certificate
# CAP: Capability Activation Payload
stress_read_lic() {
  local read_lic
  test_print_trc "Repeat reading SDSi state certificate for 30 cycles:"
  for ((j = 0; j < "$SOCKET_NUM"; j++)); do
    for ((i = 1; i <= 30; i++)); do
      if ! read_lic=$(intel_sdsi -d "$j" -s); then
        die "Repeat reading SDSi license for socket $j cycle $i Fails"
      else
        test_print_trc "Repeat reading SDSi state certificate for socket $j cycle $i PASS"
      fi
    done
  done
  test_print_trc "$read_lic"
}

stress_read_tele() {
  local read_tele
  test_print_trc "Repeat reading SDSi metering telemetry for 30 cycles:"
  for ((j = 0; j < "$SOCKET_NUM"; j++)); do
    for ((i = 1; i <= 30; i++)); do
      if ! read_tele=$(intel_sdsi -d "$j" -m); then
        die "Repeat reading SDSi metering telemetry for socket $j cycle $i Fails"
      else
        test_print_trc "Repeat reading metering telemetry for socket $j cycle $i PASS"
      fi
    done
  done
  test_print_trc "$read_tele"
}

intel_sdsi_test() {
  case $TEST_SCENARIO in
  driver_unbind_bind)
    sdsi_unbind_bind
    ;;
  sdsi_sysfs)
    sdsi_driver_interface
    ;;
  sdsi_per_socket)
    sdsi_driver_node_per_socket
    ;;
  sysfs_register_attri)
    sdsi_sysfs_attribute registers
    ;;
  sysfs_certificate_attri)
    sdsi_sysfs_attribute state_certificate
    ;;
  sysfs_telemetry_attri)
    sdsi_sysfs_attribute meter_certificate
    ;;
  sdsi_devices)
    available_sdsi_devices
    ;;
  sdsi_ppin)
    sdsi_ppin
    ;;
  nvram_content_err_check)
    nvram_content_err
    ;;
  enable_status)
    feature_enable
    ;;
  read_meter_telemetry)
    read_meter_tele
    ;;
  stress_reading_reg)
    stress_read_reg
    ;;
  stress_reading_lic)
    stress_read_lic
    ;;
  stress_reading_tele)
    stress_read_tele
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

intel_sdsi_test
