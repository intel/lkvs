#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2025 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  17, Jun., 2025 - Hongyu Ning - creation


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

###################### Do Works ######################
case "$DEP_CASE" in
  hw_dep_check)
    seamrr_check
    ;;
  other_dep_check1)
    tdx_parameter_check
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