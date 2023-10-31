#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  24, Aug., 2023 - Hongyu Ning - creation


# @desc This script do basic TD guest booting check in TDX Guest VM

###################### Variables ######################
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"
source common.sh

while getopts :c: arg; do
  case $arg in
    c)
      HOST_TSC=$OPTARG
      ;;
    *)
      test_print_err "Must supply an argument to -$OPTARG."
      exit 1
      ;;
  esac
done

###################### Functions ######################
tdx_tsc_check(){
  GUEST_TSC_INFO=$(dmesg | grep -i "tsc" | grep -i "detected")
  test_print_trc "TSC value info: $GUEST_TSC_INFO"
  which cpuid || dnf install -y cpuid
  cpuid -1 | grep -i "tsc"
  TSC_RAW=$(cpuid -rl 0x15 -1)
  TSC_EAX=${TSC_RAW#*eax=}
  TSC_EAX=${TSC_EAX%% *}
  TSC_EBX=${TSC_RAW#*ebx=}
  TSC_EBX=${TSC_EBX%% *}
  TSC_ECX=${TSC_RAW#*ecx=}
  TSC_ECX=${TSC_ECX%% *}
  TSC_EDX=${TSC_RAW#*edx=}
  TSC_EDX=${TSC_EDX%% *}
  GUEST_TSC=$((TSC_ECX * TSC_EBX / TSC_EAX))
}

###################### Do Works ######################
# check TSC value on guest
tdx_tsc_check

if [ "$GUEST_TSC" -ne "$HOST_TSC" ]; then
  die "TD guest boot with TSC $GUEST_TSC, not equal to host TSC $HOST_TSC"
else
  test_print_trc "TD Guest TSC value equal to Host TSC."
  test_print_trc "TSC value check on TD guest complete."
fi