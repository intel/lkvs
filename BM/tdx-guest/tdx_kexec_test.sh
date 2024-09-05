#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  16, Aug., 2024 - Hongyu Ning - creation


# @desc This script do kexec related test and check in TDX Guest VM

###################### Variables ######################
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"
source common.sh

while getopts :v:m:o:k:s: arg; do
  case $arg in
    v)
      VCPU=$OPTARG
      ;;
    m)
      MEM=$OPTARG
      ;;
    o)
      MEM_DRAIN=$OPTARG
      ;;
    k)
      KEXEC_CNT=$OPTARG
      ;;
    s)
      KEXEC_SSH=$OPTARG
      ;;
    *)
      test_print_err "Must supply an argument to -$OPTARG."
      exit 1
      ;;
  esac
done

###################### Functions ######################
# function to check unaccepted memory and do mem drain
memory_drain() {
  # check unaccepted memory
  unaccepted_mem=$(grep "naccepted" /proc/meminfo | awk '{print $2}')
  # drain memory if unaccepted memory is not zero
  if [[ "$unaccepted_mem" -gt 0 ]]; then
    tail /dev/zero
  elif [[ "$unaccepted_mem" -eq 0 ]]; then
    test_print_trc "unaccepted memory is zero now"
  else
    die "unaccepted memory check failed with unaccepted mem: $unaccepted_mem"
  fi
}

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

# function to check VCPU and MEMORY size in TDX guest
vcpu_mem_check() {
  # check vcpu and socket number
  vcpu_td=$(lscpu | grep "CPU(s)" | head -1 | awk '{print $2}')
  test_print_trc "vcpu_td: $vcpu_td"

  if [[ "$vcpu_td" -ne "$VCPU" ]]; then
    die "Guest TD VM boot with vcpu: $vcpu_td (expected $VCPU)"
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
  test_print_trc "vcpu $VCPU, memory $MEM GB"
}

# function to free memory by clear memory page caches
clear_mem_cache() {
  test_print_trc "Start to clear memory page caches"
  sync
  sleep 1
  # free page cache, dentries and inodes
  echo 3 > /proc/sys/vm/drop_caches
  test_print_trc "Free memory by clear memory page caches done"
}

# function to increase swap space for more virtual memory
increase_swap_space() {
  test_print_trc "Start to increase swap space"
  # create swap file with 2GB size
  dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  test_print_trc "Increase swap space done"
}

###################### Do Works ######################
if [[ "$KEXEC_SSH" != "yes" ]]; then
  test_print_trc "start kexec test with vcpu: $VCPU, memory: $MEM, mem_drain: $MEM_DRAIN, kexec_cnt: $KEXEC_CNT, kexec_ssh: $KEXEC_SSH"
  # do memory_drain if $MEM_DRAIN option enabled "yes"
  if [[ "$MEM_DRAIN" == "yes" ]]; then
    test_print_trc "start memory drain before kexec test"
    memory_drain
  elif [[ "$MEM_DRAIN" == "no" ]]; then
    if [[ "$KEXEC_CNT" -ne 0 ]]; then
      test_print_trc "skip memory drain before kexec test"
    fi
  else
    die "unsupported memory drain option: $MEM_DRAIN"
  fi

  #do memory_drain in final test loop even if $MEM_DRAIN not enabled
  if [[ "$KEXEC_CNT" -eq 0 ]] && [[ "$MEM_DRAIN" == "no" ]]; then
    test_print_trc "Start memory drain in final test loop in case of no mem_drain before kexec test"
    memory_drain
    unaccepted_mem=$(grep "naccepted" /proc/meminfo | awk '{print $2}')
    if [[ "$unaccepted_mem" -gt 0 ]]; then
      die "unaccepted memory is not drained: $unaccepted_mem"
    elif [[ "$unaccepted_mem" -eq 0 ]]; then
      test_print_trc "unaccepted memory is zero now"
    else
      die "unaccepted memory check failed with unaccepted mem: $unaccepted_mem"
    fi
  fi

  # do VCPU and MEM check
  vcpu_mem_check || die "failed on vcpu_mem_check"

  # do kexec load and switch
  if [[ "$KEXEC_CNT" -gt 0 ]]; then
    if [[ "$MEM_DRAIN" == "yes" ]]; then
      clear_mem_cache || die "failed on clear_mem_cache"
      sleep 3
      increase_swap_space || die "failed on increase_swap_space"
      sleep 3
    elif [[ "$MEM_DRAIN" == "no" ]]; then
      kexec_load_switch || die "failed on kexec_load_switch"
    fi
  elif [[ "$KEXEC_CNT" -eq 0 ]]; then
    test_print_trc "skip kexec load and switch in final test loop"
    test_print_trc "TDVM to shutdown after all kexec test completed"
    shutdown now || die "failed to shutdown TDVM in final test loop"
  else
    die "unsupported kexec test cycle count: $KEXEC_CNT"
  fi
else # $KEXEC_SSH == "yes", run kexec via ssh standalone to bypass abnormal kexec stuck
  test_print_trc "run kexec_load_switch via ssh standalone"
  sleep 5
  kexec_load_switch || die "failed on kexec_load_switch ssh standalone"
fi
