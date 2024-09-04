#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Author:
#             Ammy Yi <ammy.yi@intel.com>
#
# History:
#             Feb. 2, 2024 - (Ammy Yi)Creation

# @desc This script verify telemetry test
# @returns Fail the test if return code is non-zero (value set not found)

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-t TESTCASE_ID] [-H]
  -t  TEST CASE ID
  -H  show this
__EOF
}

SYSFS_PATH="/sys/class/intel_pmt"

telem_sysfs_test() {
  do_cmd "ls $SYSFS_PATH | grep telem"
}

telem_dev_test() {
  do_cmd "ls $SYSFS_PATH | grep telem"
}

telem_sysfs_common_test() {
  ids=$(ls $SYSFS_PATH | grep telem)
  [[ -z $ids ]] && die "No telemetry device found!"
  for id in $ids; do
    do_cmd "cat $SYSFS_PATH/$id/guid"
    do_cmd "cat $SYSFS_PATH/$id/size"
    do_cmd "ls $SYSFS_PATH/$id | grep device"
    should_fail "echo 0 > $SYSFS_PATH/$id/guid"
    should_fail "echo 0 > $SYSFS_PATH/$id/size"
  done
}

telem_data_test() {
  offset=$1
  tel_bin="telemetry_tests"
  ids=$(ls $SYSFS_PATH | grep telem)
  [[ -z $ids ]] && die "No telemetry device found!"
  test_print_trc "ids=$ids!"
  for id in $ids; do
    test_print_trc "id=$id!"
    size=$(cat "$SYSFS_PATH"/"$id"/size)
    size=$((size - 1))
    do_cmd "ls $SYSFS_PATH/$id/telem"
    do_cmd "$tel_bin 1 $SYSFS_PATH/$id/telem $size $offset"
  done
}

pci_test() {
  do_cmd "lspci -knnv | grep -c intel_vsec"
}

unload_module() {
  # $1 is the driver module name
  local module_name=$1
  is_kmodule_builtin "$module_name" && skip_test
  load_unload_module.sh -c -d "$module_name" &&
    do_cmd "load_unload_module.sh -u -d $module_name"
}

load_module() {
  # $1 is the driver module name
  local module_name=$1
  is_kmodule_builtin "$module_name" && skip_test
  do_cmd "load_unload_module.sh -l -d $module_name" &&
    load_unload_module.sh -c -d "$module_name"
}

dmesg_check() {
  should_fail "extract_case_dmesg | grep BUG"
  should_fail "extract_case_dmesg | grep 'Call Trace'"
  should_fail "extract_case_dmesg | grep error"
}

telemetry_test() {
  case $TEST_SCENARIO in
  telem_sysfs)
    telem_sysfs_test
    ;;
  telem_dev)
    telem_dev_test
    ;;
  telem_sysfs_common)
    telem_sysfs_common_test
    ;;
  telem_data)
    telem_data_test 0
    ;;
  pci)
    pci_test
    ;;
  telem_driver)
    unload_module pmt_telemetry
    unload_module pmt_class
    load_module pmt_class
    load_module pmt_telemetry
    ;;
  esac
  dmesg_check
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

telemetry_test
# Call teardown for passing case
exec_teardown
