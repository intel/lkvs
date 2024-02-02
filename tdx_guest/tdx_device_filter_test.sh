#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  22, Jan., 2024 - Hongyu Ning - creation


# @desc This script do device filter tests in TDX Guest VM

###################### Variables ######################
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"
source common.sh

while getopts :t: arg; do
  case $arg in
    t)
      FILTER_CASE=$OPTARG
      ;;
    *)
      test_print_err "Must supply an argument to -$OPTARG."
      exit 1
      ;;
  esac
done

###################### Functions ######################
acpi_allow_check() {
  ACPI_TABLE=$1
  if [[ -f "/sys/firmware/acpi/tables/$ACPI_TABLE" ]]; then
    test_print_trc "ACPI table: $ACPI_TABLE exists"
    return 0
  else
    test_print_trc "No ACPI table: $ACPI_TABLE found"
    return 1
  fi
}

###################### Do Works ######################
case "$FILTER_CASE" in
  ALLOW_ACPI)
    if acpi_allow_check "WAET"; then
      test_print_trc "WAET ACPI table allowed as expected"
    else
      die "ACPI table WAET allow test failed"
    fi
    ;;
  BLOCK_ACPI)
    if ! acpi_allow_check "WAET" && dmesg | grep -i "WAET" | grep -i "ignoring"; then
      test_print_trc "WAET ACPI table blocked as expected"
    else
      die "ACPI table WAET block test failed"
    fi
    ;;
  NO_CCFILTER)
    if dmesg | grep -i "Disabled TDX guest filter support"; then
      test_print_trc "TDX device fitler disabled for debug purpose"
    else
      die "TDX device filter not disabled"
    fi
    if acpi_allow_check "WAET"; then
      test_print_trc "WAET ACPI table allowed since device filter disabled"
    else
      die "Device filter disabled can't work as expected, WAET ACPI table still blocked"
    fi
    ;;
  :)
    test_print_err "Must specify the memory case option by [-t]"
    exit 1
    ;;
  \?)
    test_print_err "Input test case option $MEM_CASE is not supported"
    exit 1
    ;;
esac