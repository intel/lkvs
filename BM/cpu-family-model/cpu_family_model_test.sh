#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation
# @Desc Verify Intel CPU family/model CPUID matches the expected platform
#       definition added in arch/x86/include/asm/intel-family.h.
#
# Given `-p <platform>` it runs all checks
# (cpuinfo vendor/family/model, cpuid synthesized family/model, and
# optionally the intel-family.h macro when `-s <linux-src>` is passed)
# in one go and reports overall PASS / FAIL / BLOCK.

cd "$(dirname "$0")" 2>/dev/null || exit 1
# shellcheck source=/dev/null
source ../.env

: "${PLATFORM:=""}"
: "${SOURCE_PATH:=""}"

# ----------------------------------------------------------------------
# Platform database
#
# Format:
#   PLATFORM|DESCRIPTION|EXPECTED_VENDOR|EXPECTED_FAMILY_DEC|EXPECTED_FAMILY_HEX|EXPECTED_MODEL_DEC|EXPECTED_MODEL_HEX|KERNEL_MACRO|KERNEL_IFM
#
# Notes:
#   - /proc/cpuinfo reports family/model in decimal.
#   - cpuid utility reports raw and synthesized values.
#   - intel-family.h defines the synthesized CPUID via IFM(family, model).
#   - CWF: family synth = 0x6  / 6,  model synth = 0xdd / 221
#   - DMR: family synth = 0x13 / 19, model synth = 0x1  / 1
# ----------------------------------------------------------------------
PLATFORM_DB=$(cat <<'EOF'
DMR|Diamond Rapids|GenuineIntel|19|0x13|1|0x01|INTEL_DIAMONDRAPIDS_X|IFM(19, 0x01)
CWF|Clearwater Forest|GenuineIntel|6|0x06|221|0xDD|INTEL_ATOM_DARKMONT_X|IFM(6, 0xDD)
EOF
)

usage() {
  cat <<__EOF
  usage: ./${0##*/} -p PLATFORM [-s LINUX_SOURCE_PATH] [-l] [-h]
  -p  platform to test (e.g. DMR, CWF). Use -l to list supported platforms.
  -s  Path to Linux kernel source tree. When supplied, additionally
      verify the corresponding INTEL_* macro definition in
      arch/x86/include/asm/intel-family.h.
  -l  List supported platforms and their expected CPUID values.
  -h  Show this help.
__EOF
}

###################### Helpers ######################

list_platforms() {
  echo "$PLATFORM_DB" | awk -F'|' '
  BEGIN {
    printf "%-8s %-24s %-12s %-10s %-10s %-10s %-10s %-32s %-16s\n",
           "Platform", "Description", "Vendor", "FamilyDec", "FamilyHex",
           "ModelDec", "ModelHex", "KernelMacro", "KernelIFM"
    printf "%-8s %-24s %-12s %-10s %-10s %-10s %-10s %-32s %-16s\n",
           "--------", "-----------", "------", "---------", "---------",
           "--------", "--------", "-----------", "---------"
  }
  {
    printf "%-8s %-24s %-12s %-10s %-10s %-10s %-10s %-32s %-16s\n",
           $1, $2, $3, $4, $5, $6, $7, $8, $9
  }'
}

# Retrieve the record for a given platform code from PLATFORM_DB.
# $1: platform code (case insensitive)
get_platform_record() {
  local platform="$1"
  echo "$PLATFORM_DB" | awk -F'|' -v p="$platform" '
    toupper($1) == toupper(p) { print; found=1 }
    END { if (!found) exit 1 }
  '
}

# Read a value from /proc/cpuinfo.
# $1: awk key regex, e.g. '^cpu family[ \t]*$'
get_cpuinfo_value() {
  local key_regex="$1"
  awk -F: -v key_regex="$key_regex" '
    $1 ~ key_regex {
      value=$2
      gsub(/^[ \t]+|[ \t]+$/, "", value)
      print value
      exit
    }
  ' /proc/cpuinfo
}

# Parse the first numeric decimal (from a "(N)" suffix) on the first
# line of `cpuid -1 -l 0x01` containing the given literal substring.
# $1: literal substring, e.g. '(family synth)' or '(model synth)'
parse_cpuid_field_dec() {
  local needle="$1"
  cpuid -1 -l 0x01 2>/dev/null | awk -v needle="$needle" '
    index($0, needle) {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^\([0-9]+\)$/) {
          gsub(/[()]/, "", $i)
          print $i
          exit
        }
      }
    }'
}

###################### Main check ######################

cpu_family_model_test() {
  [[ -n "$PLATFORM" ]] || { usage; die "Platform is required (-p). Use -l to list supported platforms."; }

  local record
  record="$(get_platform_record "$PLATFORM")" || \
    block_test "Unsupported platform code: $PLATFORM. Use -l to list supported platforms."

  local platform_code platform_desc exp_vendor
  local exp_family exp_family_hex exp_model exp_model_hex
  local kernel_macro kernel_ifm

  IFS='|' read -r \
    platform_code platform_desc exp_vendor \
    exp_family exp_family_hex \
    exp_model exp_model_hex \
    kernel_macro kernel_ifm <<< "$record"

  test_print_trc "Platform      : $platform_code ($platform_desc)"
  test_print_trc "Kernel release: $(uname -r)"
  test_print_trc "Expected vendor : $exp_vendor"
  test_print_trc "Expected family : $exp_family / $exp_family_hex"
  test_print_trc "Expected model  : $exp_model / $exp_model_hex"
  test_print_trc "Kernel macro    : $kernel_macro $kernel_ifm"

  local fail=0

  # ---- /proc/cpuinfo checks ----
  local runtime_vendor runtime_family runtime_model
  runtime_vendor="$(get_cpuinfo_value '^vendor_id[ \t]*$')"
  runtime_family="$(get_cpuinfo_value '^cpu family[ \t]*$')"
  runtime_model="$(get_cpuinfo_value '^model[ \t]*$')"

  if [[ -z "$runtime_vendor" || -z "$runtime_family" || -z "$runtime_model" ]]; then
    die "Failed to parse vendor_id / cpu family / model from /proc/cpuinfo."
  fi

  local runtime_family_hex runtime_model_hex
  runtime_family_hex="$(printf '0x%X' "$runtime_family")"
  runtime_model_hex="$(printf '0x%02X' "$runtime_model")"

  test_print_trc "Runtime vendor_id : $runtime_vendor"
  test_print_trc "Runtime cpu family: $runtime_family / $runtime_family_hex"
  test_print_trc "Runtime model     : $runtime_model / $runtime_model_hex"

  if [[ "$runtime_vendor" == "$exp_vendor" ]]; then
    test_print_trc "/proc/cpuinfo vendor : PASS"
  else
    test_print_err "/proc/cpuinfo vendor : FAIL, expected '$exp_vendor', got '$runtime_vendor'"
    fail=1
  fi

  if [[ "$runtime_family" == "$exp_family" ]]; then
    test_print_trc "/proc/cpuinfo family : PASS"
  else
    test_print_err "/proc/cpuinfo family : FAIL, expected $exp_family/$exp_family_hex, got $runtime_family/$runtime_family_hex"
    fail=1
  fi

  if [[ "$runtime_model" == "$exp_model" ]]; then
    test_print_trc "/proc/cpuinfo model  : PASS"
  else
    test_print_err "/proc/cpuinfo model  : FAIL, expected $exp_model/$exp_model_hex, got $runtime_model/$runtime_model_hex"
    fail=1
  fi

  # ---- cpuid utility checks ----
  if ! command -v cpuid >/dev/null 2>&1; then
    block_test "cpuid utility is required. Install via 'apt install cpuid' or 'dnf install cpuid'."
  fi

  local cpuid_output
  cpuid_output="$(cpuid -1 -l 0x01 2>/dev/null || true)"
  [[ -n "$cpuid_output" ]] || block_test "Failed to run 'cpuid -1 -l 0x01'."

  local family_synth model_synth
  family_synth="$(parse_cpuid_field_dec '(family synth)')"
  model_synth="$(parse_cpuid_field_dec '(model synth)')"

  if [[ -z "$family_synth" || -z "$model_synth" ]]; then
    die "Failed to parse synthesized family/model from cpuid output."
  fi

  local family_synth_hex model_synth_hex
  family_synth_hex="$(printf '0x%X' "$family_synth")"
  model_synth_hex="$(printf '0x%02X' "$model_synth")"

  test_print_trc "cpuid family synth: $family_synth / $family_synth_hex"
  test_print_trc "cpuid model synth : $model_synth / $model_synth_hex"

  if [[ "$family_synth" == "$exp_family" ]]; then
    test_print_trc "cpuid family synth   : PASS"
  else
    test_print_err "cpuid family synth   : FAIL, expected $exp_family/$exp_family_hex, got $family_synth/$family_synth_hex"
    fail=1
  fi

  if [[ "$model_synth" == "$exp_model" ]]; then
    test_print_trc "cpuid model synth    : PASS"
  else
    test_print_err "cpuid model synth    : FAIL, expected $exp_model/$exp_model_hex, got $model_synth/$model_synth_hex"
    fail=1
  fi

  # ---- optional kernel source header check ----
  if [[ -n "$SOURCE_PATH" ]]; then
    local header="${SOURCE_PATH%/}/arch/x86/include/asm/intel-family.h"
    if [[ ! -f "$header" ]]; then
      test_print_err "intel-family.h : FAIL, not found under $SOURCE_PATH"
      fail=1
    else
      local line
      line="$(grep -nE "^[[:space:]]*#define[[:space:]]+${kernel_macro}[[:space:]]+" "$header" || true)"
      if [[ -z "$line" ]]; then
        test_print_err "intel-family.h : FAIL, macro $kernel_macro not found in $header"
        fail=1
      elif echo "$line" | grep -Fq "$kernel_ifm"; then
        test_print_trc "intel-family.h       : PASS ($line)"
      else
        test_print_err "intel-family.h : FAIL, expected '$kernel_macro $kernel_ifm', got '$line'"
        fail=1
      fi
    fi
  fi

  if [[ $fail -ne 0 ]]; then
    die "$platform_code CPUID does not match expected $kernel_macro $kernel_ifm"
  fi

  test_print_trc "$platform_code CPUID matches expected $kernel_macro $kernel_ifm"
  return 0
}

while getopts :p:s:lh arg; do
  case $arg in
    p)
      PLATFORM=$OPTARG
      ;;
    s)
      SOURCE_PATH=$OPTARG
      ;;
    l)
      list_platforms
      exit 0
      ;;
    h)
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

cpu_family_model_test
# Call teardown for passing case
exec_teardown
