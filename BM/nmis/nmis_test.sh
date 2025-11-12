#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2025 Intel Corporation
# Author:   Farrah Chen <farrah.chen@intel.com>
# @Desc This script verify NMI Source tests

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env


: "${CASE_NAME:=""}"

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-t TESTCASE_ID] [-H]
  -t  TEST CASE ID
  -H  show this
__EOF
}

# Cmdline test: Check FRED and NMIS CPUID, verify if FRED is enabled, check if NMIS error
nmi_enable_test() {
  #CPUID.0x7.1.EAX[17] == 1
  do_cmd "cpuid_check 7 0 1 0 a 17"
  #CPUID.0x7.1.EAX[20] == 1
  do_cmd "cpuid_check 7 0 1 0 a 20"
  do_cmd "grep -q 'fred=on' '/proc/cmdline'"
  full_dmesg_check "contain" "Initialize FRED on CPU"
  full_dmesg_check "null" "NMI without source information! Disable source reporting."
}

# NMI Source check for IPI by NMI kselftest
nmis_ipi_test() {
    local ret=0
    nmi_enable_test
    general_test.sh -t kconfig -k "CONFIG_DEBUG_NMI_SELFTEST=y" || ret=1
    [ $ret -eq 1 ] || die "CONFIG_DEBUG_NMI_SELFTEST is not set in Kconfig, ipi test cannot be executed!"
    full_dmesg_check "contain" "NMI testsuite"
    full_dmesg_check "contain" "Good, all   2 testcases passed!"
    full_dmesg_check "null" "NMI without source information! Disable source reporting."
}

# Check NMI Source for local interrupts triggered by CPU through local vector table (LVT), such as PMI
nmis_pmi_test() {
    local cpu_num end before after
    nmi_enable_test
    grep NMI /proc/interrupts > /tmp/pmi_before
    perf top &> /dev/null &
    pid=$!
    sleep 5
    kill -9 $pid
    full_dmesg_check "null" "NMI without source information! Disable source reporting."

    grep NMI /proc/interrupts > /tmp/pmi_after
    cpu_num=$(grep -o -E '[0-9]+' /tmp/pmi_before | wc -l)
    local i=2
    end=$((cpu_num+1))

    for i in $(seq 2 $end)
    do
        before=$(awk '{print $'$i'}' /tmp/pmi_before)
        after=$(awk '{print $'$i'}' /tmp/pmi_after)
        if [ $after -le $before ]; then
            die "PMI test failed!"
        fi
    done
}

# NMI Source IPI backtrace test
nmis_ipi_bt_test() {
    local cpu_num end before after
    nmi_enable_test
    echo 1 > /proc/sysrq-trigger
    full_dmesg_check "contain" "Changing Loglevel"
    full_dmesg_check "contain" "Loglevel set to 1"
    grep NMI /proc/interrupts > /tmp/nmi_before
    echo l > /proc/sysrq-trigger
    full_dmesg_check "contain" "Show backtrace of all active CPUs"
    grep NMI /proc/interrupts > /tmp/nmi_after
    full_dmesg_check "null" "NMI without source information! Disable source reporting."

    cpu_num=$( grep -o -E '[0-9]+' /tmp/nmi_before | wc -l)
    local i=2
    local inc=0
    end=$((cpu_num+1))

    for i in $(seq 2 $end)
    do
        before=$(awk '{print $'$i'}' /tmp/nmi_before)
        after=$(awk '{print $'$i'}' /tmp/nmi_after)
        if [ $after -gt $before ]; then
            inc=$((inc+1))
        fi
    done

    if [ $inc -ne $((cpu_num - 1)) ]; then
        die "CPU backtrace IPI test failed!"
    fi
}

nmis_test() {
  case $TEST_SCENARIO in
    enabling)
      nmi_enable_test
      ;;
    ipi)
      nmis_ipi_test
      ;;
    pmi)
      nmis_pmi_test
      ;;
    ipi_bt)
      nmis_ipi_bt_test
      ;;
    *)
      echo "Invalid option"
      return 1
  esac
  return 0
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

nmis_test "$@"
# Call teardown for passing case
exec_teardown
