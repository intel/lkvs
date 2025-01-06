#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  16, Aug., 2024 - Hongyu Ning - creation


# @desc This script do kexec related test and check in Guest VM

###################### Variables ######################
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"
source common.sh

while getopts :v:m:k: arg; do
  case $arg in
    v)
      VCPU=$OPTARG
      ;;
    m)
      MEM=$OPTARG
      ;;
    k)
      KEXEC_CNT=$OPTARG
      ;;
    *)
      test_print_err "Must supply an argument to -$OPTARG."
      exit 1
      ;;
  esac
done

###################### Functions ######################
# function to load kexec target kenrel image and trigger kexec switch to target kernel
kexec_load_switch() {
  # stop systemd to avoid unexpected stuck
  systemctl stop systemd*
  # load kexec target kernel image and initrd, reuse kernel cmdline
  if ! kexec -d -l "/boot/vmlinuz-$(uname -r)" --initrd="/boot/initramfs-$(uname -r).img" --reuse-cmdline; then
    die "failed to load kexec target kernel image, test failed"
  else
    test_print_trc "kexec target kernel image loaded"
  fi
  sleep 5
  # trigger kexec switch to target kernel
  test_print_trc "kexec switch to target kernel triggered"
  kexec -d -e &
}

# function to check VCPU and MEMORY size in VM guest
vcpu_mem_check() {
  # check vcpu and socket number
  vcpu_vm=$(lscpu | grep "CPU(s)" | head -1 | awk '{print $2}')
  test_print_trc "vcpu_vm: $vcpu_vm"
  vcpu_offline=$(lscpu | grep "Off-line CPU(s)" | awk '{print $NF}')
  vcpu_online=$(lscpu | grep "On-line CPU(s)" | awk '{print $NF}')

  if [[ "$vcpu_vm" -ne "$VCPU" ]]; then
    die "Guest VM boot with vcpu: $vcpu_vm (expected $VCPU)"
  elif [[ -n "$vcpu_offline" ]]; then
    die "Guest VM boot with offline vcpu: $vcpu_offline"
  fi

  # check memory size
  mem_vm=$(grep "MemTotal" /proc/meminfo | awk '$3=="kB" {printf "%.0f\n", $2/(1024*1024)}')
  test_print_trc "mem_vm: $mem_vm"

  # $MEM less than or equal to 4GB need special memory size check
  if [[ $MEM -le 4 ]]; then
    if [[ $(( MEM / mem_vm )) -lt 1 ]] || [[ $(( MEM / mem_vm )) -gt 2 ]]; then
      die "Guest VM boot with memory: $mem_vm GB (expected $MEM GB)"
    fi
  # $MEM more than 4GB use general memory size check
  else
    if [[ $(( MEM / mem_vm )) -ne 1 ]]; then
      die "Guest VM boot with memory: $mem_vm GB (expected $MEM GB)"
    fi
  fi

  test_print_trc "Guest VM boot up successfully with config:"
  test_print_trc "vcpu $VCPU on-line $vcpu_online, memory $MEM GB"
}

###################### Do Works ######################
test_print_trc "start kexec test with vcpu: $VCPU, memory: $MEM, kexec_cnt: $KEXEC_CNT"

# do VCPU and MEM check
vcpu_mem_check || die "failed on vcpu_mem_check"

if [[ "$KEXEC_CNT" -gt 0 ]]; then
  # do kexec load and switch
  kexec_load_switch || die "failed on kexec_load_switch"
elif [[ "$KEXEC_CNT" -eq 0 ]]; then
  test_print_trc "Guest VM to shutdown after all kexec test completed"
  shutdown now || die "failed to shutdown Guest VM in final test loop"
else
  die "unsupported kexec test cycle count: $KEXEC_CNT"
fi