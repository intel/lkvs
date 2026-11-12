#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation
# Author: Yi Lai <yi1.lai@intel.com>
# @Desc  Test script to verify Intel Bitfix Filter (BFF) reset driver
#        (drivers/edac/intel-bff.c) behavior on Diamond Rapids.
#
# TEST_SCENARIO values:
#   bff_support_check       - MSR enumeration + intel_bff module load check
#   bff_yellow              - baseline: yellow status on bank 3
#   bff_bank_coverage       - yellow status on every bank in dmr_mcbanks[]
#   bff_unsupported_bank    - negative: yellow status on an unmapped bank
#   bff_uc_ignored          - negative: UC bit set, TES must be ignored
#   bff_frequent_overflow   - two yellow overflows on same <cpu,bank>
#                             within the 10-minute BFF_OVERFLOW_INTERVAL

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env
source ./ras_common.sh

MCE_INJECT_DIR="./mce-inject/test"
BFF_INJECT_DIR="./bff_inject"

# IA32_MCG_CAP (0x179) bit 11: MCG_TES_P - threshold-based error status supported
MCG_CAP_MSR=0x179
MCG_TES_P_BIT=11
# IA32_CORE_CAPS (0xcf) bit 9: BFF_RESET capability
CORE_CAPS_MSR=0xcf
BFF_RESET_BIT=9

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-t TESTCASE_ID] [-H]
  -t  TEST CASE ID
  -H  show this
__EOF
}

# Write a unique marker to kmsg and echo it back, so callers can scope
# dmesg checks to only the output produced after this call.
mark_dmesg() {
  local marker
  marker="BFF_TEST_MARKER_$$_$(date +%s%N)"
  [[ -w /dev/kmsg ]] && echo "$marker" >/dev/kmsg
  echo "$marker"
}

# Get dmesg output produced strictly after a given marker.
# Usage: capture_dmesg_since <marker>
capture_dmesg_since() {
  local marker="$1"
  dmesg | sed -n "/$marker/,\$p" | grep -v "$marker" || true
}

load_mce_inject() {
  modprobe mce-inject || die "Failed to load mce-inject module"
}

# Inject an MCE from a given file and print the dmesg output produced by it.
# Usage: inject_mce_file <file>
inject_mce_file() {
  local file="$1"
  local marker
  marker=$(mark_dmesg)
  mce-inject "$file" || die "mce-inject $file failed"
  # bff_mce_notify() runs on a deferred workqueue, not synchronously with the
  # injection, so wait briefly before reading dmesg to avoid racing it.
  sleep 0.5
  capture_dmesg_since "$marker"
}

bff_test() {
  case $TEST_SCENARIO in
  bff_support_check)
    # Verify MSR enumeration and driver load state for the BFF reset feature.
    local mcg_cap core_caps

    mcg_cap=$(rdmsr $MCG_CAP_MSR) || die "Failed to read IA32_MCG_CAP"
    if (( ! ( (0x$mcg_cap >> MCG_TES_P_BIT) & 1 ) )); then
      die "IA32_MCG_CAP bit $MCG_TES_P_BIT (MCG_TES_P) is not set; threshold-based error status not supported on this platform"
    fi
    test_print_trc "IA32_MCG_CAP reports MCG_TES_P supported"

    core_caps=$(rdmsr $CORE_CAPS_MSR) || die "Failed to read IA32_CORE_CAPS"
    if (( ! ( (0x$core_caps >> BFF_RESET_BIT) & 1 ) )); then
      die "IA32_CORE_CAPS bit $BFF_RESET_BIT (BFF_RESET) is not set; bitfix filter reset not supported on this platform"
    fi
    test_print_trc "IA32_CORE_CAPS reports BFF_RESET supported"

    if ! lsmod | grep -qw intel_bff && [[ ! -d /sys/module/intel_bff ]]; then
      die "intel_bff module is not loaded"
    fi
    test_print_trc "intel_bff module is loaded"
    ;;

  bff_yellow)
    mce_config
    mce_log_clear # Clear previous MCE records

    # Load mce-inject module
    modprobe mce-inject || die "Failed to load mce-inject module"

    # Inject corrected-yellow MCE
    mce-inject ./mce-inject/test/corrected-yellow || die "mce-inject corrected-yellow failed"

    # Verify dmesg reports machine check events
    if ! dmesg | grep -q "Machine check events logged"; then
      die "dmesg does not contain 'Machine check events logged'"
    fi
    test_print_trc "dmesg confirms machine check events logged"

    # Verify MCE log reports yellow threshold status
    if ! mce_log_check "Threshold based error status: yellow"; then
      die "MCE log does not contain yellow threshold status"
    fi
    test_print_trc "MCE log confirms yellow threshold status"
    ;;

  bff_bank_coverage)
    # Verify every bank in dmr_mcbanks[] (drivers/edac/intel-bff.c) triggers
    # a bitfix filter reset/report when a yellow-status error is logged.
    load_mce_inject

    local bank output
    for bank in 1 2 3 6 13 17; do
      if [[ $bank -eq 3 ]]; then
        output=$(inject_mce_file "${MCE_INJECT_DIR}/corrected-yellow")
      else
        output=$(inject_mce_file "${BFF_INJECT_DIR}/corrected-yellow-bank${bank}")
      fi
      echo "$output" | grep -q "Machine check events logged" ||
        die "Bank $bank: dmesg missing 'Machine check events logged'"
      echo "$output" | grep -q "bitfix filter overflowed" ||
        die "Bank $bank: dmesg missing BFF overflow report"
      test_print_trc "Bank $bank: BFF overflow correctly reported"
    done
    ;;

  bff_unsupported_bank)
    # Bank 4 is not in dmr_mcbanks[]; the BFF driver must ignore it.
    load_mce_inject

    local output
    output=$(inject_mce_file "${BFF_INJECT_DIR}/corrected-yellow-bank4")
    echo "$output" | grep -q "Machine check events logged" ||
      die "dmesg missing 'Machine check events logged'"
    if echo "$output" | grep -q "bitfix filter overflowed"; then
      die "Unsupported bank 4 unexpectedly triggered a BFF overflow report"
    fi
    test_print_trc "Bank 4 (unsupported) correctly produced no BFF overflow report"
    ;;

  bff_uc_ignored)
    # Uncorrected (UC) bit set: the BFF driver bails out before checking TES
    load_mce_inject

    local output
    output=$(inject_mce_file "${BFF_INJECT_DIR}/uncorrected-yellow-poll")
    if echo "$output" | grep -q "bitfix filter overflowed"; then
      die "Uncorrected error unexpectedly triggered a BFF overflow report"
    fi
    test_print_trc "Uncorrected (UC) error correctly ignored by BFF driver"
    ;;

  bff_frequent_overflow)
    # A second injection on the same bff_id within BFF_OVERFLOW_INTERVAL (10
    # minutes) must escalate to WARN ("...overflowed frequently").
    load_mce_inject

    local output1 output2
    output1=$(inject_mce_file "${MCE_INJECT_DIR}/corrected-yellow")
    echo "$output1" | grep -q "bitfix filter overflowed" ||
      die "First injection: dmesg missing BFF overflow report"

    test_print_trc "Waiting 10s before second injection (must stay within the 10-minute BFF_OVERFLOW_INTERVAL)"
    sleep 10

    output2=$(inject_mce_file "${MCE_INJECT_DIR}/corrected-yellow")
    echo "$output2" | grep -q "overflowed frequently" ||
      die "Second injection within interval did not escalate to 'overflowed frequently'"
    test_print_trc "Second injection correctly escalated to WARN (overflowed frequently)"
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

bff_test
