#!/bin/bash
###############################################################################
# SPDX-License-Identifier: GPL-2.0-only                                       #
# Copyright (c) 2024 Intel Corporation.                                       #
# For general check like KCONFIG, CPU family model stepping                   #
###############################################################################

# shellcheck source=/dev/null
cd "$(dirname "$0")" 2>/dev/null && source ../.env

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-t TEST_TYPE][-k KCONFIG or keywrod][-p parm][-h]
  -t  Test type, i.e., kconfig | fms | dmesg | turbostat | module
  -k  KCONFIG name like CONFIG_XXX or keyword
  -p  PARM for test
        option for dmesg check
        fms list file for fms check
        module name for module check
  -h  show This
__EOF
}

general_test() {
  case $TYPE in
  kconfig)
    config_name=$(echo "$KEYWORD" | cut -d '=' -f1)
    config_val=$(echo "$KEYWORD" | cut -d '=' -f2)
    test_any_kconfig_match "$config_name" "$config_val"
    ;;
  # family model stepping check
  fms)
    get_cpu_model
    check_fms_list "$PARM"
    ;;
  dmesg)
    key1=$(echo "$KEYWORD" | awk -F '&' '{print $1}')
    key2=$(echo "$KEYWORD" | awk -F '&' '{print $2}') \
    key3=$(echo "$KEYWORD" | awk -F '&' '{print $3}')
    full_dmesg_check "$PARM" "$key1" "$key2" "$key3" || return $?
    ;;
  turbostat)
    check_turbostat_ver
    ;;
  module)
    check_module "$PARM"
    ;;
  *)
    die "Invalid TYPE:$TYPE"
    ;;
  esac
}

while getopts :t:p:k:h arg; do
  case $arg in
  t)
    TYPE=$OPTARG
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

general_test
