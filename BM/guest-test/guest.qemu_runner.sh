#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  24, Aug., 2023 - Hongyu Ning - creation


# @desc This script boots VM thru $QEMU_IMG (called by qemu_runner.py)
# @ params source 1: general params exported from qemu_get_config.py
# @ params source 2: test scenario config sourced from test_params.py

###################### Variables ######################
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"

###################### Functions ######################
# function to remove 0x and prefix useless 0 for hex data
version_check() {
  local version_raw=$1
  if [[ "$version_raw" = "0x00000000" ]]; then
    local version=0x0
  else
    local version_hex
    version_hex=${version_raw#0x}
    version_hex=${version_hex##+(0)}
    local version=$((16#$version_hex))
  fi
  echo "$version"
}

# function to do TDX/TDXIO VM launching basic pre-check
# list all the variables value
tdx_pre_check() {
  if [[ ! -f $KERNEL_IMG ]]; then
    test_print_wrg "Guest kernel not set in qemu.config.json file, \
    please make sure if it's correct!"
  else
    test_print_trc "TDX guest kernel to test: $KERNEL_IMG"
  fi

  if [[ ! -f $BIOS_IMG ]]; then
    test_print_wrg "In qemu.config.json file, need to set ovmf properly"
    die "Virtual BIOS does not exist..."
  else
    test_print_trc "BIOS to test: $BIOS_IMG"
  fi

  if [[ ! -f $QEMU_IMG ]]; then
    test_print_wrg "In qemu.config.json file, need to set qemu properly"
    die "QEMU does not exist..."
  else
    test_print_trc "QEMU to test: $QEMU_IMG"
  fi

  if [[ ! -f $GUEST_IMG ]]; then
    test_print_wrg "In qemu.config.json file, need to set guest OS img properly"
    die "Guest OS does not exist..."
  else
    test_print_trc "Guest OS image to test: $GUEST_IMG"
  fi

  if [[ $GUEST_IMG_FORMAT = "qcow2" ]]; then
    test_print_trc "Guest OS image format: qcow2"
  else
    test_print_trc "Guest OS image format: raw"
  fi

  test_print_trc "Guest OS root password: $SSHPASS"
  test_print_trc "TDX guest config: vcpu $VCPU, socket $SOCKETS, memory ${MEM}GB"
  test_print_trc "TDX guest extra config: debug $DEBUG, extra commandline: $CMDLINE"
  test_print_trc "TDX guest ssh forward port: $PORT"

  TDX_SYSFS_FILE="/sys/module/kvm_intel/parameters/tdx"
  if [[ -f "$TDX_SYSFS_FILE" ]]; then
    if [ "Y" != "$(cat $TDX_SYSFS_FILE)" ] ;then
      die "TDX not enabled as expected, please check"
    else
      test_print_trc "TDX enabled, try to launch TD VM now......"
    fi
  else
     die "kvm_intel module tdx params does not exist, plase check"
  fi
}

###################### Do Works ######################
cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

# get test scenario config for qemu_runner
source "$SCRIPT_DIR"/test_params.py

# do basic pre-check for TDX/TDXIO VM launching
if [[ $VM_TYPE == "tdx" ]] || [[ $VM_TYPE == "tdxio" ]]; then
  tdx_pre_check
fi

# launch VM by qemu via qemu_runner.py
test_print_trc "qemu_runner start to launch $VM_TYPE VM"
python3 "$SCRIPT_DIR"/qemu_runner.py
