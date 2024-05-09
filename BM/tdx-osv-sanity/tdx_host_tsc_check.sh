#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  30, Oct., 2023 - Hongyu Ning - creation


# @desc This script do basic can provide basic TDX host check

###################### Variables ######################
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"

# host machine tsc clock freq
HOST_TSC=0

###################### Functions ######################
tdx_flag_check(){
  dmesg | grep -i "tdx" | grep -i "initialized" || \
    die "host machine TDX enabling failed, please check"
}

tdx_tsc_check(){
  HOST_TSC_INFO=$(dmesg | grep -i "tsc" | grep -i "detected")
  test_print_trc "TSC value info: $HOST_TSC_INFO"
  TSC_RAW=$(cpuid -rl 0x15 -1)
  TSC_EAX=${TSC_RAW#*eax=}
  TSC_EAX=${TSC_EAX%% *}
  TSC_EBX=${TSC_RAW#*ebx=}
  TSC_EBX=${TSC_EBX%% *}
  TSC_ECX=${TSC_RAW#*ecx=}
  TSC_ECX=${TSC_ECX%% *}
  TSC_EDX=${TSC_RAW#*edx=}
  TSC_EDX=${TSC_EDX%% *}
  HOST_TSC=$((TSC_ECX * TSC_EBX / TSC_EAX))
}

###################### Do Works ######################
cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

# check TDX flag
tdx_flag_check
# check TSC value on host
tdx_tsc_check