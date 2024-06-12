#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2022 Intel Corporation
#
# File:         pmu_iommu_tests.sh
#
# Description:  IOMMU PMU test script
#
# Author(s):    Yongwei Ma<yongwei.ma@intel.com>
# Date:         06/11/2022
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

iommu_clocks_test() {
  logfile="temp.txt"
  event_value=0
  do_cmd "perf stat -e dmar/iommu_clocks/ -a sleep 1 2>&1|tee $logfile"
  event_value=$(grep dmar $logfile | awk '{print $1}')
  [[ $event_value -eq 0 ]] && die "event value is 0!!!"
}

iommu_all_basic_test() {
  dmr_list=$(ls /sys/devices/ | grep dmar)
  for dmr in $dmr_list; do
    event_list=$(ls /sys/devices/$dmr/events)
    for event in $event_list; do
      test_print_trc "$dmr/$event/"
      do_cmd "perf stat -e $dmr/$event/ -a sleep 1"
    done
  done
}

pmu_iommu_test() {
  case $TEST_SCENARIO in
    iommu_clocks)
      iommu_clocks_test
      ;;
    iommu_all_basic)
      iommu_all_basic_test
      ;;
    esac
  return 0
}

while getopts :t:w:H arg; do
  case $arg in
    t)
      TEST_SCENARIO=$OPTARG
      ;;
    w)
      WATCHDOG=$OPTARG
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

pmu_iommu_test
# Call teardown for passing case
exec_teardown
