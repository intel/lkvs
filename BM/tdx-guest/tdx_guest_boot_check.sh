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

while getopts :v:s:m: arg; do
  case $arg in
    v)
      VCPU=$OPTARG
      ;;
    s)
      SOCKETS=$OPTARG
      ;;
    m)
      MEM=$OPTARG
      ;;
    *)
      test_print_err "Must supply an argument to -$OPTARG."
      exit 1
      ;;
  esac
done

###################### Do Works ######################
# check vcpu and socket number
vcpu_td=$(lscpu | grep "CPU(s)" | head -1 | awk '{print $2}')
vcpu_offline=$(lscpu | grep "Off-line CPU(s)" | awk '{print $NF}')
vcpu_online=$(lscpu | grep "On-line CPU(s)" | awk '{print $NF}')
sockets_td=$(lscpu | grep "Socket(s)" | awk '{print $2}')
test_print_trc "vcpu_td: $vcpu_td"
test_print_trc "sockets_td: $sockets_td"

if [[ "$vcpu_td" -ne "$VCPU" ]]; then
  die "Guest TD VM boot with vcpu: $vcpu_td (expected $VCPU)"
elif [[ -n "$vcpu_offline" ]]; then
  die "Guest TD VM boot with offline vcpu: $vcpu_offline"
fi

if [[ "$sockets_td" -ne "$SOCKETS" ]]; then
  die "Guest TD VM boot with sockets: $sockets_td (expected $SOCKETS)"
fi

# check memory size
mem_td=$(grep "MemTotal" /proc/meminfo | awk '$3=="kB" {printf "%.0f\n", $2/(1024*1024)}')
test_print_trc "mem_td: $mem_td"

# $MEM less than or equal to 4GB need special memory size check
if [[ $MEM -le 4 ]]; then
  if [[ $(( MEM / mem_td )) -lt 1 ]] || [[ $(( MEM / mem_td )) -gt 2 ]]; then
    die "Guest TD VM boot with memory: $mem_td GB (expected $MEM GB)"
  fi
# $MEM more than 4GB use general memory size check
else
  if [[ $(( MEM / mem_td )) -ne 1 ]]; then
    die "Guest TD VM boot with memory: $mem_td GB (expected $MEM GB)"
  fi
fi

test_print_trc "Guest TD VM boot up successfully with config:"
test_print_trc "vcpu $VCPU on-line $vcpu_online, socket $SOCKETS, memory $MEM GB"