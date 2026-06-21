#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation
# Author: Yi Lai <yi1.lai@intel.com>
# @Desc  Test script to verify EINJ v2 (ACPI Error Injection) CE memory error injection

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

LOG="${PWD}/dmesg_einjv2.log"
tmp_addr_file="${PWD}/einj_v2.txt"
iomem_tmp="${PWD}/iomem_v2_tmp"

PAGESIZE=4096
NUM_TESTADDR=20
RANGE_SIZE_THR_MB=500
EINJ_DIR="/sys/kernel/debug/apei/einj"

cleanup() { rm -f "$tmp_addr_file" "$iomem_tmp" || true; }
trap cleanup EXIT

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-t TESTCASE_ID] [-H]
  -t  TEST CASE ID
  -H  show this
__EOF
}

# Generate test addresses from System RAM ranges
generate_test_addresses() {
  [[ -f "$LOG" ]] && rm -f "$LOG"
  : >"$tmp_addr_file"

  local URANDOM
  URANDOM=$(od -An -N4 -t uL /dev/urandom | tr -d " ")

  grep -E "System RAM" /proc/iomem | cut -d ':' -f1 >"$iomem_tmp"
  test_print_trc "Generating test addresses from System RAM ranges"

  while read -r line; do
    local start_addr end_addr rand_addr test_pfn_base test_pfn test_addr
    start_addr=$((16#$(echo "$line" | awk -F '-' '{print $1}')))
    end_addr=$((16#$(echo "$line" | awk -F '-' '{print $2}')))

    # skip address < 1MB
    ((start_addr < 0x100000)) && continue
    # skip small memory areas (<500MB)
    (((end_addr - start_addr) < (RANGE_SIZE_THR_MB * 0x100000))) && continue

    rand_addr=$((start_addr + URANDOM % (end_addr - start_addr)))
    if ((rand_addr + NUM_TESTADDR * PAGESIZE > end_addr)); then
      rand_addr=$start_addr
    fi

    test_pfn_base=$((rand_addr / PAGESIZE))
    for ((i = 1; i <= NUM_TESTADDR; i++)); do
      test_pfn=$((test_pfn_base + i))
      test_addr=$((test_pfn * PAGESIZE))
      ((test_addr > end_addr)) && break
      printf "0x%lx\n" "$test_addr" >>"$tmp_addr_file"
    done
  done <"$iomem_tmp"

  [[ -s "$tmp_addr_file" ]] || die "No valid test addresses generated"
}

# Prepare EINJv2 interface
prepare_einj_v2() {
  if [[ ! -d "$EINJ_DIR" ]]; then
    mountpoint -q /sys/kernel/debug || mount -t debugfs debugfs /sys/kernel/debug || true
  fi
  [[ -d "$EINJ_DIR" ]] || die "EINJv2 interface not available at $EINJ_DIR"

  pushd "$EINJ_DIR" >/dev/null || die "Failed to pushd to $EINJ_DIR"
  [[ -r available_error_type ]] || die "EINJv2 'available_error_type' not readable"

  if grep -qw "V2_0x00000002" available_error_type; then
    echo "V2_0x00000002" >error_type
  else
    popd >/dev/null || return
    die "Required EINJv2 error type 'V2_0x00000002' not available"
  fi

  # Configure EINJ v2 parameters
  [[ -w param2 ]] && echo 0xfffffffffffff000 >param2
  [[ -w component_id0 ]] && echo 0x1 >component_id0
  [[ -w component_syndrome0 ]] && echo 0x4 >component_syndrome0
  [[ -w component_id1 ]] && echo 0x2 >component_id1
  [[ -w component_syndrome1 ]] && echo 0x4 >component_syndrome1
  [[ -w flags ]] && echo 0xa >flags
  [[ -w notrigger ]] && echo 0 >notrigger
  popd >/dev/null || return
}

# Inject errors and verify SystemAddress in dmesg
inject_and_verify() {
  pushd "$EINJ_DIR" >/dev/null || die "Failed to pushd to $EINJ_DIR"

  while read -r addr; do
    local iter_marker output sys_addr
    iter_marker="EINJ_V2_MARKER_${addr}_$(date +%s%N)"
    if [[ -w /dev/kmsg ]]; then
      echo "$iter_marker" >/dev/kmsg
    fi

    echo "$addr" >param1
    echo 1 >error_inject
    sleep 1

    if [[ -w /dev/kmsg ]]; then
      output=$(dmesg | sed -n "/$iter_marker/,\$p" | grep -v "$iter_marker" || true)
    else
      output=$(dmesg | tail -n 20)
    fi
    echo "$output" >>"$LOG"

    sys_addr=$(echo "$output" | grep -Eo "SystemAddress:0x[0-9a-fA-F]+" | head -n 1 | cut -d: -f2 || true)

    if [[ -n "$sys_addr" ]]; then
      if ((addr != sys_addr)); then
        popd >/dev/null || return
        die "Address mismatch: injected $addr, reported $sys_addr"
      fi
      test_print_trc "Injected $addr matched dmesg SystemAddress"
    else
      popd >/dev/null || return
      die "No SystemAddress found in dmesg for injected address $addr"
    fi
  done <"$tmp_addr_file"

  popd >/dev/null || return
  test_print_trc "All EINJv2 injections verified successfully"
}

einjv2_test() {
  case $TEST_SCENARIO in
  einjv2_memory)
    generate_test_addresses
    prepare_einj_v2
    inject_and_verify
    ;;
  esac
}

while getopts :t:H arg; do
  case $arg in
  t)
    TEST_SCENARIO=$OPTARG
    ;;
  H)
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

einjv2_test
