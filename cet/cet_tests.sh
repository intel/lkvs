#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation
# @Desc  Test script to verify Intel CET functionality

cd "$(dirname $0)" 2>/dev/null; source ../.env

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-t TEST_TYPE][-n BIN_NAME][-p parameter][-k KEYWORD][-h]
  -t  Test type like cp_test
  -n  Test cpu bin name like shstk_cp and so on
  -p  PARM like null
  -k  Keyword for dmesg checking like "control protection"
  -h  show This
__EOF
}

cet_dmesg_check() {
  local bin_name=$1
  local bin_parm=$2
  local verify_cp=""

  bin_output_dmesg "$BIN_NAME" "$PARM"
  verify_cp=$(echo "$BIN_DMESG" | grep -i "$KEYWORD")
  if [[ -z "$verify_cp" ]]; then
    die "No $KEYWORD found in dmesg:$BIN_DMESG when executed $BIN_NAME $PARM"
  else
    test_print_trc "$KEYWORD found in dmesg:$BIN_DMESG, pass."
  fi
}

cet_tests() {
  case $TYPE in
    cp_test)
      test_print_trc "Test bin:$BIN_NAME $PARM, $TYPE:check dmesg $KEYWORD"
      cet_dmesg_check "$BIN_NAME" "$PARM"
      ;;
    *)
      usage
      block_test "Invalid TYPE:$TYPE"
      ;;
  esac
}

while getopts :t:n:p:k:h arg; do
  case $arg in
    t)
      TYPE=$OPTARG
      ;;
    n)
      BIN_NAME=$OPTARG
      ;;
    p)
      PARM=$OPTARG
      ;;
    k)
      KEYWORD=$OPTARG
      ;;
    h)
      usage
      exit 0
      ;;
    *)
      usage
      die "Option -$OPTARG requires an argument."
      ;;
  esac
done

cet_tests
