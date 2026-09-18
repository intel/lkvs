#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2018 Intel Corporation
# Author: Pengfei Xu <pengfei.xu@intel.com>
# Description: Test script to verify XSAVE function

cd "$(dirname "$0")" 2>/dev/null || exit 1
# shellcheck disable=SC1091
source ../.env

usage() {
  cat <<__EOF
  usage: ./${0##*/}  [-f FUNCTION][-n BIN_NAME][-p parameter][-h]
  -f  Test function like offset, bad_fpu
  -n  Test cpu bin name like xsave_test and so on
  -p  Test bin file parameter like 1088 and so on
  -h  show This
__EOF
}

# Check the offset of the first xstate component after the legacy region and
# XSAVE header should be 576 (512 legacy + 64 header) in dmesg if present.
xsave_offset_check() {
  local offset_check=""
  local offset_content=""

  offset_check=$(dmesg | grep "xstate_offset\[" | head -n 1)
  if [[ -z "$offset_check" ]]; then
    test_print_trc "No xstate offset to check"
  else
    offset_content=$(dmesg | grep "xstate_offset\[" | head -n 1 | grep 576)
    if [[ -n "$offset_content" ]]; then
      test_print_trc "first xstate_offset is 576, pass:$offset_check"
    else
      die "xstate_offset[2] is not 576:$offset_check"
    fi
  fi
}

# Execute cpu function binary program test and check success or fail
# $1: Binary program name to execute
# $2: Parameter need for binary test
# $3: Function name
# Return: 0 for true, otherwise false or die
cpu_func_parm_test() {
  local bin_name=$1
  local bin_parm=$2
  local name=$3
  local bin_parm_name=""
  local log_path="/tmp/$name"
  local call_trace="Call Trace"
  local log=""
  local bin=""
  local result=""

  [ -n "$bin_name" ] || die "Binary $bin_name was not exist"
  [ -n "$bin_parm" ] || die "parameter: $bin_parm was null"
  [ -d "$log_path" ] || mkdir -p "$log_path"
  bin=$(which "$bin_name")
  [[ -e "$bin" ]] || die "bin:$bin does not exist"

  bin_parm_name=$(echo "$bin_parm" | tr ' ' '_')
  log="${log_path}/${bin_name}_${bin_parm_name}.log"
  last_dmesg_timestamp
  if [ "$bin_parm" == "null" ]; then
    eval "$bin > $log"
  else
    eval "$bin $bin_parm > $log"
  fi

  [ -e "$log" ] || die "No $log file"
  test_print_trc "Show $bin_name result in $log:"
  test_print_trc "$(cat "$log")"
  result=$(grep -i "fail" "$log")
  [[ -z "$result" ]] || die "There is fail info in $log:$result"
  extract_case_dmesg | grep -q "$call_trace" && die "$call_trace found in dmesg"
  test_print_trc "Check $bin_name pass, no fail in log and no $call_trace"
}

main() {
  local func_name="xsave"

  case $FUNCTION in
    offset)
      xsave_offset_check
      ;;
    bad_fpu)
      cpu_func_parm_test "$BIN_NAME" "$PARM" "$func_name"
      full_dmesg_check "null" "Bad FPU" || die "Bad FPU found in dmesg"
      ;;
    *)
      usage && exit 1
      ;;
  esac
}

# Set the default FUNCTION as offset and PARM as null
: "${FUNCTION:="offset"}"
: "${PARM:="null"}"

while getopts :f:n:p:h arg; do
  case $arg in
    f)
      FUNCTION=$OPTARG
      ;;
    n)
      BIN_NAME=$OPTARG
      ;;
    p)
      PARM=$OPTARG
      ;;
    h)
      usage
      exit 0
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

main
