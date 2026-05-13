#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation
# Description:  Test script for Intel EDAC drivers (i10nm_edac and imh_edac)
# EDAC: Error Detection and Correction
# @Author  Yi Lai  yi1.lai@intel.com


cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

EDAC_BUS="/sys/bus/edac"

: "${CASE_NAME:=""}"

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-t TESTCASE_ID] [-H]
  -t  TEST CASE ID
  -H  show this
__EOF
}

# Detect CPU family to determine EDAC driver variant and debugfs path
# Family 19 (0x13): IMH - Diamond Rapids (DMR) and future IMH platforms
# Family 6: i10nm - ICX, SPR, EMR, GNR, SRF, CWF and other 10nm+ server platforms
get_edac_debug_path() {
  get_cpu_model
  case $FML in
    13)
      MC="imh"
      EDAC_DEBUG_PATH="/sys/kernel/debug/edac/imh_test/addr"
      ;;
    *)
      MC="i10nm"
      EDAC_DEBUG_PATH="/sys/kernel/debug/edac/i10nm_test/addr"
      ;;
  esac
  LOG="${PWD}/dmesg.decoding.via.debugfs.${MC}_edac.log"
  [[ -f "$LOG" ]] && rm -f "$LOG"
}

edac_addr_decode() {
  local MARKER dmesg_output

  if [[ -w /dev/kmsg ]]; then
    MARKER="EDAC_CHECK_MARKER_$(date +%s%N)"
    echo "$MARKER" > /dev/kmsg
  fi

  echo 0x12345 > "$EDAC_DEBUG_PATH"

  if [[ -w /dev/kmsg ]]; then
    dmesg_output=$(dmesg | sed -n "/$MARKER/,\$p" | grep -v "$MARKER")
  else
    dmesg_output=$(dmesg | tail -n 100)
  fi

  if echo "$dmesg_output" | grep -q -e "ADDR 0x12345"; then
    test_print_trc "EDAC address decode successfully"
  else
    die "Failed to decode EDAC address"
  fi
}

edac_test_error_inject() {
  local MARKER
  local TOLM=2
  local SIZE_KB SIZE_GB tmp_addr_file addr_low addr_high

  SIZE_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
  SIZE_GB=$((SIZE_KB / 1024 / 1024))
  tmp_addr_file="${PWD}/einj_edac.txt"
  > "$tmp_addr_file"

  for ((i = 0; i < (SIZE_GB + TOLM) * 4; i += 4)); do
    addr_low=$(head -c 32 /dev/urandom | md5sum | head -c 7)
    addr_high=$(printf "%x" "$i")
    echo "0x${addr_high}${addr_low}" >> "$tmp_addr_file"
  done

  if [[ -w /dev/kmsg ]]; then
    MARKER="EDAC_INJECT_MARKER_$(date +%s%N)"
    echo "$MARKER" > /dev/kmsg
  fi

  while read -r addr; do
    echo "$addr" > "$EDAC_DEBUG_PATH"
  done < "$tmp_addr_file"

  if [[ -w /dev/kmsg ]]; then
    dmesg | sed -n "/$MARKER/,\$p" | grep -v "$MARKER" >> "$LOG"
  else
    dmesg | tail -n 1000 >> "$LOG"
  fi
  rm -f "$tmp_addr_file"
}

edac_test_error_inject_iomem() {
  local MARKER
  local PAGESIZE=4096
  local NUM_TESTADDR=40
  local RANGE_SIZE_THR=500
  local tmp_addr_file iomem_tmp URANDOM
  local start_addr end_addr rand_addr test_pfn_base test_pfn test_addr

  tmp_addr_file="${PWD}/einj_iomem.txt"
  iomem_tmp="${PWD}/iomem_tmp"
  > "$tmp_addr_file"

  URANDOM=$(od -An -N4 -t uL /dev/urandom | tr -d " ")
  grep "System RAM" /proc/iomem | cut -d ':' -f1 > "$iomem_tmp"

  while read -r line; do
    start_addr=$((16#$(echo "$line" | awk -F '-' '{print $1}')))
    end_addr=$((16#$(echo "$line" | awk -F '-' '{print $2}')))
    # skip address < 1MB
    ((start_addr < 0x100000)) && continue
    # skip small memory areas (<500MB)
    (((end_addr - start_addr) < (RANGE_SIZE_THR * 0x100000))) && continue

    rand_addr=$((start_addr + URANDOM % (end_addr - start_addr)))
    if ((rand_addr + NUM_TESTADDR * PAGESIZE > end_addr)); then
      rand_addr=$start_addr
    fi
    test_pfn_base=$((rand_addr / PAGESIZE))
    for ((i = 1; i <= NUM_TESTADDR; i++)); do
      test_pfn=$((test_pfn_base + i))
      test_addr=$((test_pfn * PAGESIZE))
      ((test_addr > end_addr)) && break
      printf "0x%lx\n" "$test_addr" >> "$tmp_addr_file"
    done
  done < "$iomem_tmp"

  if [[ -w /dev/kmsg ]]; then
    MARKER="EDAC_INJECT_IOMEM_MARKER_$(date +%s%N)"
    echo "$MARKER" > /dev/kmsg
  fi

  while read -r addr; do
    echo "$addr" > "$EDAC_DEBUG_PATH"
  done < "$tmp_addr_file"

  if [[ -w /dev/kmsg ]]; then
    dmesg | sed -n "/$MARKER/,\$p" | grep -v "$MARKER" >> "$LOG"
  else
    dmesg | tail -n 1000 >> "$LOG"
  fi
  rm -f "$tmp_addr_file" "$iomem_tmp"
}

edac_mc_index_change() {
  local mc_count
  mc_count=$(grep -oE "EDAC MC[0-9]+:" "$LOG" | sort -u | wc -l)
  if ((mc_count > 1)); then
    test_print_trc "Decoding log contains $mc_count unique Memory Controller entries"
  else
    die "Decoding log contains only $mc_count Memory Controller entry"
  fi
}

edac_mc_check_populated() {
  local mc_indices sorted_mc_indices populated_indexes sorted_populated
  local SYSFS_EDAC_MC_DIR="/sys/devices/system/edac/mc"

  mc_indices=($(grep -oE "EDAC MC[0-9]+:" "$LOG" | sort -u | grep -oE "[0-9]+"))
  sorted_mc_indices=($(printf "%s\n" "${mc_indices[@]}" | sort -n))

  [[ -d "$SYSFS_EDAC_MC_DIR" ]] || die "EDAC mc structure not found under $SYSFS_EDAC_MC_DIR"

  populated_indexes=()
  for size_file in "$SYSFS_EDAC_MC_DIR"/mc*/size_mb; do
    [[ -r "$size_file" ]] || continue
    local size num mc_dir
    size=$(cat "$size_file" 2>/dev/null)
    if [[ -n "$size" ]] && ((size > 0)); then
      mc_dir=$(dirname "$size_file")
      num=$(basename "$mc_dir" | tr -d 'mc')
      populated_indexes+=("$num")
    fi
  done

  [[ ${#populated_indexes[@]} -gt 0 ]] || die "No populated memory controllers found"
  sorted_populated=($(printf "%s\n" "${populated_indexes[@]}" | sort -n))

  test_print_trc "Populated MCs from sysfs: ${sorted_populated[*]}"
  test_print_trc "Decoded MCs from log: ${sorted_mc_indices[*]}"

  if [[ "${sorted_mc_indices[*]}" == "${sorted_populated[*]}" ]]; then
    test_print_trc "All populated Memory Controllers successfully triggered errors"
  else
    die "Mismatch between populated MCs and decoded MCs"
  fi
}

edac_test() {
  case $TEST_SCENARIO in
  check_edac_bus)
    if [[ ! -d "$EDAC_BUS" ]]; then
      die "EDAC bus is not found"
    fi
    edac_devices=$(ls "$EDAC_BUS"/devices/ 2>/dev/null)
    if [[ -n "$edac_devices" ]]; then
      test_print_trc "EDAC bus is found with devices: $edac_devices"
    else
      die "EDAC bus exists but no EDAC devices are registered"
    fi
    ;;
  check_edac_driver)
    test_print_trc "Check Intel ${MC}_edac driver"
    if ! lsmod | grep -q "${MC}_edac"; then
      test_print_trc "${MC}_edac not loaded, attempting to load"
      modprobe "${MC}_edac" || die "Failed to load ${MC}_edac driver"
    fi
    if lsmod | grep -q "${MC}_edac"; then
      test_print_trc "Intel ${MC}_edac driver is loaded"
    else
      die "Intel ${MC}_edac driver is not loaded"
    fi
    ;;
  edac_addr_decode)
    edac_addr_decode
    ;;
  edac_mc_index_change)
    edac_test_error_inject
    edac_mc_index_change
    ;;
  edac_mc_check_populated)
    edac_test_error_inject_iomem
    edac_mc_check_populated
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

get_edac_debug_path
edac_test
