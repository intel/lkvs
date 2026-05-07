#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Intel Corporation
#
# File:         pmu_cstate_tests.sh
#
# Description:  PMU CSTATE test script
#
#

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

# Server platforms support different core cstate and package cstate
perf_cstate_list_server() {
    local cpu_family=""
    cpu_family=$(lscpu | grep "^CPU family:" | awk '{print $3}')
    local cpu_model=""
    cpu_model=$(lscpu | grep Model: | awk '{print $2}')

    tc_out=$(turbostat -q --show idle sleep 1 2>&1)
    [[ -n "$tc_out" ]] || block_test "Did not get turbostat log"
    test_print_trc "turbostat tool output: $tc_out"
    tc_out_cstate_list=$(echo "$tc_out" | grep -E "^Busy%")

    # Check core cstate perf event
    perf_cstates=$(perf list | grep cstate | grep "Kernel PMU event")
    [[ -n "$perf_cstates" ]] || block_test "Did not get cstate events by perf list"
    test_print_trc "perf list shows cstate events: $perf_cstates"
    perf_core_cstate_num=$(perf list | grep "Kernel PMU event" | grep -c cstate_core)
    for ((i = 1; i <= perf_core_cstate_num; i++)); do
        perf_core_cstate=$(perf list | grep cstate_core | grep "Kernel PMU event" | sed -n "$i, 1p")
        if [[ $perf_core_cstate =~ c1 ]] && [[ $tc_out_cstate_list =~ CPU%c1 ]]; then
            test_print_trc "$perf_core_cstate is supported and aligned with turbostat"
        elif [[ $perf_core_cstate =~ c6 ]] && [[ $tc_out_cstate_list =~ CPU%c6 ]]; then
            test_print_trc "$perf_core_cstate is supported and aligned with turbostat"
        else
            die "perf list shows unexpected core_cstate event."
        fi
    done

    # Check pkgc2 and pkgc6 perf event
    perf_pkg_cstate_num=$(perf list | grep "Kernel PMU event" | grep -c cstate_pkg)
    for ((i = 1; i <= perf_pkg_cstate_num; i++)); do
        perf_pkg_cstate=$(perf list | grep cstate_pkg | grep "Kernel PMU event" | sed -n "$i, 1p")
        if [[ $perf_pkg_cstate =~ c2 ]] && [[ $tc_out_cstate_list =~ Pkg%pc2 ]]; then
            test_print_trc "$perf_pkg_cstate is supported and aligned with turbostat"
        elif [[ $perf_pkg_cstate =~ c6 ]] && [[ $tc_out_cstate_list =~ Pkg%pc6 ]]; then
            test_print_trc "$perf_pkg_cstate is supported and aligned with turbostat"
        else
            die "perf list shows unexpected pkg_cstate event."
        fi
    done
    # Check module c6 perf event for Atom core servers
    # Model ID: 175 is SRF, 221 is CWF
    # Family ID 19, Model ID 1: DMR
    if [[ $cpu_model -eq 175 ]] || [[ $cpu_model -eq 221 ]] || [[ $cpu_model -eq 1 && $cpu_family -eq 19 ]]; then
        perf_mc6=$(perf list | grep cstate_module | grep "Kernel PMU event")
        if [[ -n $perf_mc6 ]]; then
            test_print_trc "perf list shows cstate_module event: $perf_mc6"
            if [[ $perf_mc6 =~ c6 ]] && [[ $tc_out_cstate_list =~ Mod%c6 ]]; then
                test_print_trc "$perf_mc6 is supported and aligned with turbostat."
            else
                die "$perf_mc6 is not aligned with turbostat."
            fi
        else
            die "perf list does not show cstate_module event."
        fi
    fi
}

pmu_cstate_test() {
  case $TEST_SCENARIO in
    cstate_event_list)
      perf_cstate_list_server
      ;;
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

pmu_cstate_test
# Call teardown for passing case
exec_teardown
