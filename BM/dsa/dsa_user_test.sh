#!/usr/bin/env bash

#
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2021 Intel Corporation
#
# Description:  Call dsa_test to run dsa user test
DIRNAME=$(dirname "$0")
DSA_DIR="$PWD/$DIRNAME"
CONFIG_DIR="$DSA_DIR/configs"
ACCFG=/usr/bin/accel-config
TEST_DIR=/usr/libexec/accel-config/test
DSATEST=$TEST_DIR/dsa_test

source "$PWD/$DIRNAME/../common/common.sh"
############################# FUNCTIONS #######################################

# Global variables
export SIZE_1=1
export SIZE_512=512
export SIZE_1K=1024
export SIZE_4K=4096
export SIZE_64K=65536
export SIZE_1M=1048576
export SIZE_2M=2097152
export EXIT_FAILURE=1
export EXIT_SKIP=77

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-c CONFIG_NAME] [-g GUEST_ONLY] [-o OPCODE] [-h]
  -c  dsa config file
  -g  set 1 if guest
  -o  test opcoce
  -h  show this
__EOF
}

# translate opcode to name
# $1 opcode
#
opcode2name()
{
  local opcode="$1"
  dec_opcode=$((opcode))
  case $dec_opcode in
    "3")
      echo "MEMMOVE"
      ;;
    "4")
      echo "MEMFILL"
      ;;
    "5")
      echo "COMPARE"
      ;;
    "6")
      echo "COMPVAL"
      ;;
    "9")
      echo "DUALCAST"
      ;;
    *)
      echo "UNKNOWN"
      ;;
  esac
}

# translate WQ mode code to name
# $1 Wq mode code
#
wq_mode2name()
{
  local wq_mode="$1"
  dec_wq_mode=$((wq_mode))
  case $dec_wq_mode in
    "0")
      echo "dedicated"
      ;;
    "1")
      echo "shared"
      ;;
    *)
      echo "UNKNOWN"
      ;;
  esac
}

# Check if accel-config and dsa_test installed and worked.
function checking_test_precondition()
{
  # ACCFG
  if [ -f "$ACCFG" ] && [ -x "$ACCFG" ]; then
    test_print_trc "accfg1:$ACCFG"
  else
    test_print_trc "Couldn't find an accel-config binary"
    exit "$EXIT_FAILURE"
  fi

  # DSATEST
  if [ -f "$DSATEST" ] && [ -x "$DSATEST" ]; then
    test_print_trc "dsa_test1:$DSATEST"
  else
    test_print_trc "Couldn't find an dsa_test binary"
    exit "$EXIT_FAILURE"
  fi

  return 0
}

# If idxd module is not loaded, load it
load_idxd_module() {
  lsmod | grep -w -q "idxd" || {
    modprobe idxd
      sleep 1
  }
}

# load/unload drivers to make sure load config file successfully
reset_idxd()
{
  lsmod | grep -q "iaa_crypto" && {
    rmmod iaa_crypto
  }
  lsmod | grep -q "iax_crypto" && {
    rmmod iax_crypto
  }
  lsmod | grep -q "idxd_mdev" && {
    rmmod idxd_mdev
  }
  lsmod | grep -q "idxd_vdev" && {
    rmmod idxd_vdev
  }
  lsmod | grep -q "idxd_uacce" && {
    rmmod idxd_uacce
  }
  lsmod | grep -q "idxd" && {
    rmmod idxd
  }
  sleep 1
  modprobe idxd
  sleep 1
}

load_config()
{
  # CONFIGS
  if [ -f "$CONFIG_DIR/$CONFIG_NAME.conf" ]; then
    export CONFIG1=$DSA_DIR/configs/${CONFIG_NAME}.conf
  else
    test_print_trc "Can't find config file $CONFIG_DIR/configs/$CONFIG_NAME.conf"
    exit "$EXIT_FAILURE"
  fi
  configurable=$(cat /sys/bus/dsa/devices/dsa0/configurable)
  if [ "$configurable" ]; then
    do_cmd "$ACCFG" load-config -c "$CONFIG1"
  fi
}

# Disable all active devices dsa/iax and enabled wqs.
# Use accel-config tool to disable the device and wq.
disable_all() {
  test_print_trc "Start to disable the device and wq"
  for device_type in 'dsa' 'iax'; do
    # Kernel before 5.13 has dsa and iax bus. Because of ABI change, iax
    # bus is removed. All devices are in /sys/bus/das/devices.
    if [ -d /sys/bus/iax ] && [ $device_type == 'iax' ]; then
      DSA_DEVICE_PATH="/sys/bus/iax/devices"
    else
      DSA_DEVICE_PATH="/sys/bus/dsa/devices"
    fi
    # Get available devices
    for device_path in "${DSA_DEVICE_PATH}"/"${device_type}"* ; do
      [[ $(echo "$device_path" | grep -c '!') -eq 0 ]] && {
      # Get wqs and disable it if the status is enabled
        for wqp in "${device_path}"/wq* ; do
	  [[ $( cat "${wqp}"/state ) == "enabled" ]] && {
	    wq=${wqp##"${DSA_DEVICE_PATH}"/}
            test_print_trc "info:disable wq $wq"
	    "$ACCFG" disable-wq "${wq}"
	    echo "-1" > "${wqp}"/group_id
          }
        done
	# Disable device
	[[ $( cat "${device_path}"/state ) == "enabled" ]] && {
	  test_print_trc "info:disable ${device_path##"${DSA_DEVICE_PATH}"/}"
	  "$ACCFG" disable-device "${device_path##"${DSA_DEVICE_PATH}"/}"
	}
	# Remove group id of engine
	for engine in "${device_path}"/engine* ; do
	  echo -1 > "$engine"/group_id
	done
      }
    done
  done
  test_print_trc "disable_all is end"
}

dsa_user_teardown(){
  if [ "$GUEST_ONLY" == "0" ]; then
    disable_all
  fi
}

# Test operation with a given opcode
# $1: opcode (e.g. 0x3 for memmove)
# $2: flag (optional, default 0x3 for BOF on, 0x2 for BOF off)
#
test_op()
{
  local opcode="$1"
  local flag="$2"
  local op_name
  op_name=$(opcode2name "$opcode")
  local wq_mode_code
  local wq_mode_name
  local xfer_size

  for wq_mode_code in 0 1; do
    wq_mode_name=$(wq_mode2name "$wq_mode_code")
    test_print_trc "Performing $wq_mode_name WQ $op_name testing"
    for xfer_size in $SIZE_512 $SIZE_1K $SIZE_4K; do
      test_print_trc "Testing $xfer_size bytes"
      do_cmd "$DSATEST" -w "$wq_mode_code" -l "$xfer_size" -o "$opcode" \
	-f "$flag" t200 -v
    done
  done
}

# Test operation in batch mode with a given opcode
# $1: opcode (e.g. 0x3 for memmove)
# $2: flag (optional, default 0x3 for BOF on, 0x2 for BOF off)
#
test_op_batch()
{
  local opcode="$1"
  local flag="$2"
  local op_name
  op_name=$(opcode2name "$opcode")
  local wq_mode_code
  local wq_mode_name
  local xfer_size

  if [ "$opcode" == "0x2" ];then
    return 0
  fi

  for wq_mode_code in 0 1; do
    wq_mode_name=$(wq_mode2name "$wq_mode_code")
    test_print_trc "Performing $wq_mode_name WQ batched $op_name testing"
    for xfer_size in $SIZE_512 $SIZE_1K $SIZE_4K; do
      test_print_trc "Testing $xfer_size bytes"
      do_cmd "$DSATEST" -w "$wq_mode_code" -l "$xfer_size" -o 0x1 -b "$opcode" \
	-c 16 -f "$flag" t2000 -v
    done
  done
}

dsa_user_test() {

    reset_idxd
    # skip if no pasid support as dsa_test does not support operation w/o pasid yet.
    [ ! -f "/sys/bus/dsa/devices/dsa0/pasid_enabled" ] && test_print_trc "No SVM support" && exit "$EXIT_SKIP"

    checking_test_precondition

    if [ "$GUEST_ONLY" == "0" ]; then
      load_config
      case $CONFIG_NAME in
	1d2g2q_user)
	  "$ACCFG" enable-device "dsa0"
	  "$ACCFG" enable-wq "dsa0/wq0.0"
	  "$ACCFG" enable-wq "dsa0/wq0.1"
	  ;;
	1d4g8q_user)
	  "$ACCFG" enable-device "dsa0"
	  "$ACCFG" enable-wq "dsa0/wq0.0"
	  "$ACCFG" enable-wq "dsa0/wq0.1"
	  "$ACCFG" enable-wq "dsa0/wq0.2"
	  "$ACCFG" enable-wq "dsa0/wq0.3"
	  "$ACCFG" enable-wq "dsa0/wq0.4"
	  "$ACCFG" enable-wq "dsa0/wq0.5"
	  "$ACCFG" enable-wq "dsa0/wq0.6"
	  "$ACCFG" enable-wq "dsa0/wq0.7"
	  ;;
	4d4g4q_user)
	  for i in {0..6..2}
	  do
	    "$ACCFG" enable-device "dsa$i"
	    "$ACCFG" enable-wq "dsa$i/wq$i.0"
	  done
	  ;;
	4d16g32q_user)
	  for i in {0..6..2}
	  do
	    "$ACCFG" enable-device "dsa$i"
	    "$ACCFG" enable-wq "dsa$i/wq$i.0"
	    "$ACCFG" enable-wq "dsa$i/wq$i.1"
	    "$ACCFG" enable-wq "dsa$i/wq$i.2"
	    "$ACCFG" enable-wq "dsa$i/wq$i.3"
	    "$ACCFG" enable-wq "dsa$i/wq$i.4"
	    "$ACCFG" enable-wq "dsa$i/wq$i.5"
	    "$ACCFG" enable-wq "dsa$i/wq$i.6"
	    "$ACCFG" enable-wq "dsa$i/wq$i.7"
	  done
	  ;;
	8d8g8q_user)
	  for i in {0..14..2}
	  do
	    "$ACCFG" enable-device "dsa$i"
	    "$ACCFG" enable-wq "dsa$i/wq$i.0"
	  done
	  ;;
	8d32g64q_user)
	  for i in {0..14..2}
	  do
	    "$ACCFG" enable-device "dsa$i"
	    "$ACCFG" enable-wq "dsa$i/wq$i.0"
	    "$ACCFG" enable-wq "dsa$i/wq$i.1"
	    "$ACCFG" enable-wq "dsa$i/wq$i.2"
	    "$ACCFG" enable-wq "dsa$i/wq$i.3"
	    "$ACCFG" enable-wq "dsa$i/wq$i.4"
	    "$ACCFG" enable-wq "dsa$i/wq$i.5"
	    "$ACCFG" enable-wq "dsa$i/wq$i.6"
	    "$ACCFG" enable-wq "dsa$i/wq$i.7"
	  done
	  ;;
	*)
	  die "Invalid config file name!"
	  ;;
      esac
    fi

    for flag in 0x0 0x1; do
      test_print_trc "Testing with 'block on fault' flag ON OFF"
      test_op "$OPCODE" "$flag"
      test_op_batch "$OPCODE" "$flag"
    done

    return 0
}

################################ DO THE WORK ##################################

CONFIG_NAME="1d2g2q_user_1"
GUEST_ONLY="0"
OPCODE="0x03"

while getopts :c:g:o:h arg; do
  case $arg in
    c)
      CONFIG_NAME=$OPTARG
      ;;
    g)
      GUEST_ONLY=$OPTARG
      ;;
    o)
      OPCODE=$OPTARG
      ;;
    h)
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

dsa_user_test
#teardown_handler="dsa_user_teardown"
exec_teardown
