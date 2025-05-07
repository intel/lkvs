#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  30, May., 2024 - Hongyu Ning - creation


# @desc This script do basic TD dependency check in TDX host environment
#       test binary is based msr-tools from OS distros

###################### Variables ######################
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"
source common.sh

while getopts :t: arg; do
  case $arg in
    t)
      DEP_CASE=$OPTARG
      ;;
    *)
      test_print_err "Must supply an argument to -$OPTARG."
      exit 1
      ;;
  esac
done

###################### Functions ######################
seamrr_check() {
  #SEAMRR represents SEAM Ranger Register, which is used by the BIOS 
  #to help configure the SEAM memory range, where the TDX module is 
  #loaded and executed
  #bit 11 of IA32_SEAMRR_PHYS_MAS MSR is set, indicates SEAMRR is enabled correctly
  #check on that could basically tell the HW support and enabling successfuly of TDX
  if rdmsr 0x1401 -f 11:11 | grep 1; then
    test_print_trc "SEAMRR enabled correctly for further TDX SW enabling."
  else
    die "SEAMRR check FAIL."
    return 1
  fi
}

tdx_parameter_check() {
  #check if kernel module kvm_intel parameter tdx is Y
  #if yes, it indicates tdx enabled correctly on host kernel
  if [ -f "/sys/module/kvm_intel/parameters/tdx" ] && \
    [ "$(cat /sys/module/kvm_intel/parameters/tdx)" = "Y" ]; then
    test_print_trc "TDX enabled from host kernel KVM POV."
  else
    die "TDX kvm_intel module parameter check FAIL."
    return 1
  fi
}

tdx_module_check() {
  #check if tdx module is enabled successfully
  if [ -f "/sys/firmware/tdx/tdx_module/status" ] && \
    [ "$(cat "/sys/firmware/tdx/tdx_module/status")" = "initialized" ]; then
    test_print_trc "TDX module enabled successfully."
  else
    die "TDX module enable status check FAIL."
    return 1
  fi
}

qemu_tdx_cap_check() {
  #check if qemu has TDX capability
  if qemu-system-x86_64 -object help | grep -q "tdx-guest"; then
    test_print_trc "QEMU has TDX capability."
  else
    test_print_wrg "default QEMU qemu-system-x86_64 does not have TDX capability."
    test_print_wrg "if there is off-tree QEMU with TDX capability, please specify the path."
    die "QEMU TDX capability check FAIL."
    return 1
  fi
}

virtual_bios_tdx_check() {
  #no explicite way to check if virtual BIOS has TDX support
  #simply check if any OVMF_*.fd file exists globaly
  if find / -name "OVMF_*.fd" 2>/dev/null; then
    test_print_trc "Virtual BIOS has TDX support."
  else
    test_print_wrg "can't find any OVMF EDK2 BIOS file, please check if virtual BIOS has TDX support."
    die "Virtual BIOS TDX support check FAIL."
    return 1
  fi
}

mainline_kernel_check() {
  #no explicite way to check if Kernel under use is from mainline or not
  #simply check if kernel version contains "mainline" and greater then "5.10"
  if uname -r | grep -q "mainline" && \
    [ "$(uname -r | awk -F'.' '{print $1}')" -ge 5 ] && \
    [ "$(uname -r | awk -F'.' '{print $2}')" -ge 10 ]; then
    test_print_trc "Mainline kernel version is used."
  else
    test_print_wrg "Kernel version is not mainline or less than 5.10."
    die "Mainline kernel version check FAIL."
    return 1
  fi
}

###################### Do Works ######################
case "$DEP_CASE" in
  hw_dep_check)
    seamrr_check
    ;;
  other_dep_check1)
    tdx_parameter_check
    ;;
  other_dep_check2)
    tdx_module_check
    ;;
  other_dep_check3)
    qemu_tdx_cap_check
    ;;
  other_dep_check4)
    virtual_bios_tdx_check
    ;;
  other_warn_check)
    mainline_kernel_check
    ;;
  :)
    test_print_err "Must specify the attest case option by [-t]"
    exit 1
    ;;
  \?)
    test_print_err "Input test case option $DEP_CASE is not supported"
    exit 1
    ;;
esac