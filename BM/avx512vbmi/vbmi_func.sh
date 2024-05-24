#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation
# Author: Pengfei Xu <pengfei.xu@intel.com>
# Description: Test script to verify VBMI instruction

cd "$(dirname "$0")" 2>/dev/null || exit 1
# shellcheck disable=SC1091
source ../.env
# shellcheck disable=SC1091
source "ifs_common.sh"

usage() {
  cat <<__EOF
  usage: ./${0##*/}  [-n BIN_NAME][-p parameter][-h]
  -n  Test cpu bin name like vpmadd and so on
  -p  Test bin file parameter like "2 3 b" and so on
  -h  show This
__EOF
}

# Check test bin results should contain "RESULTS" and no "[fail]" in it
# Input: log path
# Return: 0 for true, otherwise false or die
log_common_check() {
  log=$1

  grep -q -i "\[FAIL\]" "$log" && die "$log contain [FAIL]"
  test_print_trc "Check $log pass, no [FAIL] in it"
}

# Show key test info in log
# Input:
# $1: log path
# $2: filter key info in log, "all" for w/o filter, other for filter key name
# Return: 0 for true, otherwise false or die
show_test_info() {
  local log=$1
  local key=$2
  local all="all"
  local key_info=""

  test_print_trc "Show $key info in $log:"
  if [[ "$key" == "$all" ]]; then
    key_info=$(cat "$log")
  else
    key_info=$(grep -i "$key" "$log")
  fi
  test_print_trc "$key_info"
  test_print_trc "$log end."
}

# Convert the number to binary and only get the low 8 bits
# Input: $1 the number which need convert
# Return low 8 bits with format "xxxx xxxx", otherwise false
convert_binary() {
  num=$1
  local gap=""
  local bin_num=""
  local bin_num_len=""
  local low_num=""
  local byte_num=""
  local i=0
  local j=0
  local end_point

  [ -n "$num" ] || die "Num is null:$num"
  bin_num=$(echo "obase=2;$num"|bc)
  bin_num_len=${#bin_num}
  if [ "$bin_num_len" -lt 4 ]; then
    low_num=${bin_num:0-$bin_num_len}
    end_point=$((4 - bin_num_len))
    for ((i=0; i<end_point; i++)); do
      low_num="0"${low_num}
    done
    byte_num="0000 "${low_num}
  elif [ "$bin_num_len" -lt 8 ]; then
    low_num=${bin_num:0-4}
    gap=$((bin_num_len-4))
    byte_num=${bin_num:0-$bin_num_len:$gap}" ""$low_num"
    end_point=$((4 - gap))
    for ((j=0; j<end_point; j++)); do
      byte_num="0"${byte_num}
    done
  else
    byte_num=${bin_num:0-8:4}" "${bin_num:0-4}
  fi
  test_print_trc "num:$num,binary:$bin_num,length:$bin_num_len,byte_num:$byte_num"
  BYTE_NUM="$byte_num"
}

# Input:
# $1: shift right num bits
# $2: the num need shift right
# Return shift right result low 8 bits with format "xxxx xxxx", otherwise false
shift_right() {
  local shift_num=$1
  local obj_num=$2
  local k=0

  for ((k=0;k<shift_num;k++));do
    obj_num=$(echo "$obj_num"/2|bc)
  done
  convert_binary "$obj_num"
  SHIFT_RIGHT_NUM=$BYTE_NUM
}

# Input:
# $1: shift left num bits
# $2: the num need shift left
# Return shift left result low 8 bits with format "xxxx xxxx", otherwise false
shift_left() {
  local shift_num=$1
  local obj_num=$2
  local n=0

  for ((n=0;n<shift_num;n++));do
    obj_num=$(echo "${obj_num} * 2" | bc)
  done
  convert_binary "$obj_num"
  SHIFT_LEFT_NUM=$BYTE_NUM
}

# Check vbmi test, instruction result is our expect.
# Input:
# $1: bin parameters
# $2: result log path
# Return: 0 for true, otherwise false or die
test_vbmi() {
  local parm=$1
  local log_path=$2
  local par1=""
  local par2=""
  local bin_par2=""
  local dec_par1=""
  local left_par1=""
  local dec_par2=""
  local part1=""
  local part2=""
  local expect_pp0=""
  local expect_pp1=""
  local gap=""

  par1=$(echo "$parm" | cut -d ' ' -f 1)
  par2=$(echo "$parm" | cut -d ' ' -f 2)
  dec_par1=$((0x$par1))
  dec_par2=$((0x$par2))
  convert_binary "$dec_par2"
  bin_par2="$BYTE_NUM"

  # part1 is checking high 3 bytes fill with 3 times bin_par2
  part1="$bin_par2"' '"$bin_par2"' '"$bin_par2"

  left_par1=$((dec_par1%64))
  if [ "$left_par1" -le 24 ]; then
    shift_right "$left_par1" "$dec_par2"
    part2="$SHIFT_RIGHT_NUM"
  elif [ "$left_par1" -lt 56 ]; then
    part2="0000 0000"
  else
    gap=$((64-left_par1))
    test_print_trc "shift_left gap:$gap, dec_par2:$dec_par2"
    shift_left "$gap" "$dec_par2"
    part2="$SHIFT_LEFT_NUM"
  fi
  test_print_trc "left_par1:$left_par1, dec_par1:$dec_par1, part2:$part2"
  expect_pp0="$part1"' '"$part2"
  test_print_trc "******expect_pp1[0](second half):$expect_pp0"
  expect_pp1="$part1"' '"$bin_par2"
  test_print_trc "******expect_pp1(first half):$expect_pp1"

  grep  "$expect_pp0" "$log_path" | grep -q "pp1\[0\]" \
    || die "Compare pp1[0] fail: not same as expect_pp0:$expect_pp0"
  test_print_trc "Check $log_path pass."
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
  local all="all"
  local log=""
  local bin=""

  [ -n "$bin_name" ] || die "File $bin_name was not exist"
  [ -n "$bin_parm" ] || die "parameter: $bin_parm was null"
  [ -d "$log_path" ] || mkdir -p "$log_path"
  bin=$(which "$bin_name")
  [[ -e "$bin" ]] || {
    die "bin:$bin does not exist"
  }

  bin_parm_name=$(echo "$bin_parm" | tr ' ' '_')
  if [ "$bin_parm" == "null" ]; then
    log="${log_path}/${bin_name}_${bin_parm_name}.log"
    eval "$bin > $log"
  else
    log="${log_path}/${bin_name}_${bin_parm_name}.log"
    eval "$bin $bin_parm > $log"
  fi

  [ -e "$log" ] || die "No $log file"
  case $name in
    vbmi)
      show_test_info "$log" "$all"
      log_common_check "$log"
      test_vbmi "$bin_parm" "$log"
      ;;
    *)
      show_test_info "$log" "$all"
      test_print_trc "No need extra check for $name"
      ;;
  esac
  return 0
}

main() {
  local func_name="vbmi"
  local random_par=""
  local a=""
  local b=""
  local ax=""
  local bx=""
  local times=10
  local t=1

  test_print_trc "Test $BIN_NAME, parameter: $PARM"

  if [ "$PARM" == "random" ]; then
    for((t=1;t<=times;t++)); do
      test_print_trc "******* $t round test:"
      ((a=RANDOM%256))
      ((b=RANDOM%256))
      ax=$(echo "obase=16;$a"|bc)
      bx=$(echo "obase=16;$b"|bc)
      random_par="$ax"' '"$bx"' '"b"
      cpu_func_parm_test "$BIN_NAME" "$random_par" "$func_name"
    done
  else
    cpu_func_parm_test "$BIN_NAME" "$PARM" "$func_name"
  fi
}

while getopts :n:p:h arg; do
  case $arg in
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
