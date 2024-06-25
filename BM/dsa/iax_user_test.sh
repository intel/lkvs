#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2021 Intel Corporation
#
# Description:  Call iaa_test to run iax user test

DIRNAME=$(dirname "$0")
IAX_DIR=$DIRNAME
CONFIG_DIR="$IAX_DIR/configs"
ACCFG=/usr/bin/accel-config
TEST_DIR=/usr/libexec/accel-config/test
IAXTEST=$TEST_DIR/iaa_test

source "$DIRNAME/../common/common.sh"

############################# FUNCTIONS #######################################

# Global variables
export SIZE_1=1
export SIZE_16=16
export SIZE_32=32
export SIZE_64=64
export SIZE_128=128
export SIZE_256=256
export SIZE_512=512
export SIZE_1K=1024
export SIZE_2K=2048
export SIZE_4K=4096
export SIZE_16K=16384
export SIZE_32K=32768
export SIZE_64K=65536
export SIZE_128K=131072
export SIZE_256K=262144
export SIZE_512K=524288
export SIZE_1M=1048576
export SIZE_2M=2097152
export EXIT_FAILURE=1
export EXIT_SKIP=77
TESTDIR=/usr/share/accel-config/test
BINDIR=/usr/bin

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-c CONFIG_NAME] [-g GUEST_ONLY] [-o OPCODE] [-w WQ_MODE] [-h]
  -c  iax config file
  -g  set 1 if guest
  -o  test opcoce
  -w  shared mode or dedicated mode work queue
  -h  show this
__EOF
}

# translate opcode to name
# $1 opcode
#
opcode2name()
{
  local opcode="$1"
  case $opcode in
    0x42)
      echo "Decompress"
      ;;
    0x43)
      echo "Compress"
      ;;
    0x44)
      echo "CRC64"
      ;;
    0x48)
      echo "Zdecompress32"
      ;;
    0x49)
      echo "Zdecompress16"
      ;;
    0x4c)
      echo "Zcompress32"
      ;;
    0x4d)
      echo "Zcompress16"
      ;;
    0x50)
      echo "Scan"
      ;;
    0x51)
      echo "Set Membership"
      ;;
    0x52)
      echo "Extract"
      ;;
    0x53)
      echo "Select"
      ;;
    0x54)
      echo "RLE Burst"
      ;;
    0x55)
      echo "Find Unique"
      ;;
    0x56)
      echo "Expand"
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

# Check if accel-config and iaa_test installed and worked.
function checking_test_precondition()
{
  # ACCFG
  if [ -f "$BINDIR/accel-config" ] && [ -x "$BINDIR/accel-config" ]; then
    export ACCFG="$BINDIR"/accel-config
    test_print_trc "accfg1:$ACCFG"
  else
    test_print_trc "Couldn't find an accel-config binary"
    exit "$EXIT_FAILURE"
  fi

  # IAXTEST
  if [ -f "$IAXTEST" ] && [ -x "$IAXTEST" ]; then
    export IAXTEST=$IAXTEST
    test_print_trc "iax_test1:$IAXTEST"
  elif [ -f "$TESTDIR/iaa_test" ] && [ -x "$TESTDIR/iaa_test" ]; then
    export IAXTEST="$IAXTEST"
    test_print_trc "iax_test2:$IAXTEST"
  else
    test_print_trc "Couldn't find an iaa_test binary"
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
  iax_disable_wq
  # CONFIGS
  if [ -f "$CONFIG_DIR/${CONFIG_NAME}.conf" ]; then
    export CONFIG1=$CONFIG_DIR/${CONFIG_NAME}.conf
  else
    test_print_trc "Can't find config file $CONFIG_DIR/$CONFIG_NAME.conf"
    exit "$EXIT_FAILURE"
  fi
  configurable=$(cat /sys/bus/dsa/devices/iax1/configurable)
  if [ "$configurable" ]; then
    do_cmd "$ACCFG" load-config -c "$CONFIG1"
  fi
}

# Disable all active devices iax/iax and enabled wqs.
# Use accel-config tool to disable the device and wq.
disable_all() {
  test_print_trc "Start to disable the device and wq"
  for device_type in 'dsa' 'iax'; do
    # Kernel before 5.13 has iax and iax bus. Because of ABI change, iax
    # bus is removed. All devices are in /sys/bus/dsa/devices.
    if [ -d /sys/bus/iax ] && [ $device_type == 'iax' ]; then
      IAX_DEVICE_PATH="/sys/bus/iax/devices"
    else
      IAX_DEVICE_PATH="/sys/bus/dsa/devices"
    fi
    # Get available devices
    for device_path in "${IAX_DEVICE_PATH}"/"${device_type}"* ; do
      [[ $(echo "$device_path" | grep -c '!') -eq 0 ]] && {
	# Get wqs and disable it if the status is enabled
        for wqp in "${device_path}"/wq* ; do
          [[ $( cat "${wqp}"/state ) == "enabled" ]] && {
            wq=${wqp##"${IAX_DEVICE_PATH}"/}
            test_print_trc "info:disable wq $wq"
            "$ACCFG" disable-wq "${wq}"
            echo "-1" > "${wqp}"/group_id
          }
          done
		# Disable device
        [[ $( cat "${device_path}"/state ) == "enabled" ]] && {
          test_print_trc "info:disable ${device_path##"${IAX_DEVICE_PATH}"/}"
          "$ACCFG" disable-device "${device_path##"${IAX_DEVICE_PATH}"/}"
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

iax_disable_wq() {
  iaa_dev_id="0cfe"
  num_iaa=$(lspci -d:${iaa_dev_id} | wc -l)

  for ((i = 1; i < num_iaa * 2; i += 2)); do
    echo disable wq iax${i}/wq${i}.0
    accel-config disable-wq iax${i}/wq${i}.0

    echo disable iaa iax${i}
    accel-config disable-device iax${i}
  done
}

iax_user_teardown(){
  if [ "$GUEST_ONLY" == "0" ]; then
    disable_all
    reset_idxd
    iax_disable_wq
  fi
}

# Test operation with a given opcode
# $1: opcode (e.g. 0x0 for No-op)
# $2: flag (optional, default 0x3 for BOF on, 0x2 for BOF off)
#
test_op()
{
  local opcode="$1"
  local flag="$2"
  local wq_mode="$3"
  local op_name
  op_name=$(opcode2name "$opcode")
  local wq_mode_name
  local xfer_size

  wq_mode_name=$(wq_mode2name "$wq_mode")
  test_print_trc "Performing $wq_mode_name WQ $op_name testing"
  case $opcode in
  0x44)
    for xfer_size in $SIZE_1 $SIZE_4K $SIZE_64K $SIZE_1M $SIZE_2M; do
      test_print_trc "Testing $xfer_size bytes"
      "$IAXTEST" -w "$wq_mode" -l "$xfer_size" \
	  -o "$opcode" -1 "0x8000" -f "$flag" t200 -v
    done
    for xfer_size in $SIZE_1 $SIZE_4K $SIZE_64K $SIZE_1M $SIZE_2M; do
      test_print_trc "Testing $xfer_size bytes"
      "$IAXTEST" -w "$wq_mode" -l "$xfer_size" \
      -o "$opcode" -1 "0x4000" -f "$flag" t200 -v
    done
    ;;
    0x42|0x43|0x48|0x49|0x4c|0x4d)
    for xfer_size in $SIZE_4K $SIZE_64K $SIZE_1M $SIZE_2M; do
      test_print_trc "Testing $xfer_size bytes"
      do_cmd "$IAXTEST" -w "$wq_mode" -l "$xfer_size" \
        -o "$opcode" -f "$flag" t200 -v
    done
    ;;
    0x50|0x52|0x53|0x56)
      test_print_trc "Testing $SIZE_512 bytes"
      do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_512" -2 "0x7c" \
        -3 "$SIZE_128" -o "$opcode" -f "$flag" t200 -v

      test_print_trc "Testing $SIZE_1K bytes"
      do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_1K" -2 "0x7c" \
        -3 "$SIZE_256" -o "$opcode" -f "$flag" t200 -v

      test_print_trc "Testing $SIZE_4K bytes"
      do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_4K" -2 "0x7c" \
        -3 "$SIZE_1K" -o "$opcode" -f "$flag" t200 -v

      test_print_trc "Testing $SIZE_64K bytes"
      do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_64K" -2 "0x7c" \
        -3 "$SIZE_16K" -o "$opcode" -f "$flag" t200 -v

      test_print_trc "Testing $SIZE_1M bytes"
      do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_1M" -2 "0x7c" \
        -3 "$SIZE_256K" -o "$opcode" -f "$flag" t200 -v

      test_print_trc "Testing $SIZE_2M bytes"
      do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_2M" -2 "0x7c" \
        -3 "$SIZE_512K" -o "$opcode" -f "$flag" t200 -v
      ;;
      0x51|0x55)
        test_print_trc "Testing $SIZE_512 bytes"
        do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_512" -2 "0x38" \
          -3 "$SIZE_256" -o "$opcode" -f "$flag" t200 -v

	test_print_trc "Testing $SIZE_1K bytes"
        do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_1K" -2 "0x38" \
	  -3 "$SIZE_512" -o "$opcode" -f "$flag" t200 -v

        test_print_trc "Testing $SIZE_4K bytes"
	do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_4K" -2 "0x38" \
	  -3 "$SIZE_2K" -o "$opcode" -f "$flag" t200 -v

	test_print_trc "Testing $SIZE_64K bytes"
	do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_64K" -2 "0x38" \
	  -3 "$SIZE_32K" -o "$opcode" -f "$flag" t200 -v

	test_print_trc "Testing $SIZE_1M bytes"
	do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_1M" -2 "0x38" \
	  -3 "$SIZE_512K" -o "$opcode" -f "$flag" t200 -v

	test_print_trc "Testing $SIZE_2M bytes"
	do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_2M" -2 "0x38" \
	  -3 "$SIZE_1M" -o "$opcode" -f "$flag" t200 -v
	;;
      0x54)
        test_print_trc "Testing $SIZE_512 bytes"
	do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_512" -2 "0x1c" \
	  -3 "$SIZE_512" -o "$opcode" -f "$flag" t200 -v

	test_print_trc "Testing $SIZE_1K bytes"
	do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_1K" -2 "0x1c" \
	  -3 "$SIZE_1K" -o "$opcode" -f "$flag" t200 -v

	test_print_trc "Testing $SIZE_4K bytes"
	do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_4K" -2 "0x1c" \
	  -3 "$SIZE_4K" -o "$opcode" -f "$flag" t200 -v

	test_print_trc "Testing $SIZE_32K bytes"
	do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_32K" -2 "0x1c" \
	  -3 "$SIZE_32K" -o "$opcode" -f "$flag" t200 -v

	test_print_trc "Testing $SIZE_64K bytes"
	do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_64K" -2 "0x1c" \
	  -3 "$SIZE_64K" -o "$opcode" -f "$flag" t200 -v

	test_print_trc "Testing $SIZE_128K bytes"
	do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_128K" -2 "0x1c" \
	  -3 "$SIZE_128K" -o "$opcode" -f "$flag" t200 -v

	test_print_trc "Testing $SIZE_32 bytes"
	do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_32" -2 "0x3c" \
	  -3 "$SIZE_16" -o "$opcode" -f "$flag" t200 -v

	test_print_trc "Testing $SIZE_64 bytes"
	do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_64" -2 "0x3c" \
	  -3 "$SIZE_32" -o "$opcode" -f "$flag" t200 -v

	test_print_trc "Testing $SIZE_128 bytes"
	do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_128" -2 "0x3c" \
	  -3 "$SIZE_64" -o "$opcode" -f "$flag" t200 -v

	test_print_trc "Testing $SIZE_256 bytes"
	do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_256" -2 "0x3c" \
	  -3 "$SIZE_128" -o "$opcode" -f "$flag" t200 -v

	test_print_trc "Testing $SIZE_512 bytes"
	do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_512" -2 "0x3c" \
	  -3 "$SIZE_256" -o "$opcode" -f "$flag" t200 -v

	test_print_trc "Testing $SIZE_1K bytes"
	do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_1K" -2 "0x3c" \
	  -3 "$SIZE_512" -o "$opcode" -f "$flag" t200 -v

	test_print_trc "Testing $SIZE_64 bytes"
	do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_64" -2 "0x7c" \
	  -3 "$SIZE_16" -o "$opcode" -f "$flag" t200 -v

	test_print_trc "Testing $SIZE_128 bytes"
	do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_128" -2 "0x7c" \
          -3 "$SIZE_32" -o "$opcode" -f "$flag" t200 -v

        test_print_trc "Testing $SIZE_256 bytes"
        do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_256" -2 "0x7c" \
          -3 "$SIZE_64" -o "$opcode" -f "$flag" t200 -v

        test_print_trc "Testing $SIZE_512 bytes"
        do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_512" -2 "0x7c" \
          -3 "$SIZE_128" -o "$opcode" -f "$flag" t200 -v

        test_print_trc "Testing $SIZE_1K bytes"
        do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_1K" -2 "0x7c" \
          -3 "$SIZE_256" -o "$opcode" -f "$flag" t200 -v

        test_print_trc "Testing $SIZE_2K bytes"
        do_cmd "$IAXTEST" -w "$wq_mode" -l "$SIZE_2K" -2 "0x7c" \
          -3 "$SIZE_512" -o "$opcode" -f "$flag" t200 -v
     ;;
   esac
}

iax_user_test() {

  load_idxd_module
  # skip if no pasid support as iax_test does not support operation w/o pasid yet.
  [ ! -f "/sys/bus/dsa/devices/iax1/pasid_enabled" ] && test_print_trc "No SVM support" && exit "$EXIT_SKIP"

  checking_test_precondition

  if [ "$GUEST_ONLY" == "0" ]; then
    load_config
    case $CONFIG_NAME in
      2g2q_user_2)
        "$ACCFG" enable-device "iax1"
        "$ACCFG" enable-wq "iax1/wq1.1"
        "$ACCFG" enable-wq "iax1/wq1.4"
        ;;
      *)
        die "Invalid config file name!"
        ;;
      esac
  fi

  for flag in 0x0 0x1; do
    test_print_trc "Testing with 'block on fault' flag ON OFF"
    test_op "$OPCODE" "$flag" "$WQ_MODE"
  done

  return 0
}

################################ DO THE WORK ##################################

CONFIG_NAME="2g2q_user_2"
GUEST_ONLY="0"
OPCODE="0x00"
WQ_MODE="0"

while getopts :c:g:o:w:h arg; do
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
    w)
      WQ_MODE=$OPTARG
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

iax_user_test
#teardown_handler="iax_user_teardown"
exec_teardown
