#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation
# Author: Pengfei Xu <pengfei.xu@intel.com>
# @Desc  Test script to verify Intel CET functionality

cd "$(dirname "$0")" 2>/dev/null && source ../.env

readonly NULL="null"
readonly CONTAIN="contain"

TEST_MOD="cet_ioctl"
TEST_MOD_KO="${TEST_MOD}.ko"
KO_FILE="./cet_driver/${TEST_MOD_KO}"

export OFFLINE_CPUS=""
export teardown_handler="cet_teardown"

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

# Reserve for taerdown, present no change for cpu test
cet_teardown() {
  [[ -z "$OFFLINE_CPUS" ]] || {
    set_cpus_on_off "$OFFLINE_CPUS" || test_print_err "Set offline $OFFLINE_CPUS"
  }

  check_mod=$(lsmod | grep "$TEST_MOD")
  [[ -z "$check_mod" ]] || {
    test_print_trc "rmmod $TEST_MOD"
    rmmod "$KO_FILE"
  }
}

load_cet_driver() {
  local ker_ver=""
  local check_mod=""

  pat=$(pwd)
  echo "pat:$pat"
  [[ -e "$KO_FILE" ]] || block_test "No $TEST_MOD_KO exist, please make it first"
  mod_info=$(modinfo "$KO_FILE")
  ker_ver=$(uname -r)
  if [[ "$mod_info" == *"$ker_ver"* ]]; then
    test_print_trc "$TEST_MOD_KO matched with current kernel version:$ker_ver"
  else
    block_test "$TEST_MOD_KO didn't match kernel ver:$ker_ver; modinfo:$mod_info"
  fi
  check_mod=$(lsmod | grep "$TEST_MOD")
  if [[ -z "$check_mod" ]]; then
    test_print_trc "No $TEST_MOD loaded, will load $TEST_MOD"
    do_cmd "insmod $KO_FILE"
  else
    test_print_trc "$TEST_MOD is already loaded."
  fi
}

# Check test used time cycles in log, and print 2 test logs gap rate
# $1: 1st test log file
# $2: 2nd test log file
# $3: test log folder path
# Return: 0 for true, otherwise false or die
cet_perf_compare() {
  local file1=$1
  local file2=$2
  local path=$3
  local key_word="RESULTS"
  local cycle1=""
  local cycle2=""
  local gap=""
  local gap_rate=""
  local result=""
  local gap_upper="0.6"
  local gap_lower="-2.0"

  cycle1=$(grep "$key_word"  "${path}/${file1}" |  cut -d ':' -f 4)
  cycle2=$(grep "$key_word" "${path}/${file2}"  | cut -d ':' -f 4)
  test_print_trc "$file1 used cycles $cycle1"
  test_print_trc "$file2 used cycles $cycle2"
  gap=$(echo "$cycle1 - $cycle2" | bc)
  gap_rate=$(echo "scale=4;$gap/$cycle1" | bc)
  test_print_trc "$file1 and $file2 gap rate:$gap_rate"
  result=$(echo "$gap_rate > $gap_lower && $gap_rate < $gap_upper" | bc)
  [[ $result -eq 1 ]] || {
    test_print_wrg "gap: $gap_rate is not in the range:$gap_lower ~ $gap_upper"
    return 1
  }
}

bin_parm_test() {
  local bin_name=$1
  local bin_parm=$2
  local log_path=/tmp/$3

  [[ -n "$bin_name" ]] || die "File $bin_name does not exist"
  [[ -d "$log_path" ]] || mkdir -p "$log_path"
  bin=$(which "$bin_name")
  [[ -e "$bin" ]] || {
    die "bin:$bin does not exist"
  }

  bin_parm_name=$(echo "$bin_parm" | tr ' ' '_')
  if [[ "$bin_parm" == "null" ]]; then
    log="${log_path}/${bin_name}_${bin_parm_name}.log"
    $bin > "$log"
  else
    log="${log_path}/${bin_name}_${bin_parm_name}.log"
    $bin "${bin_parm}" > "$log" || {
      test_print_err "Failed to run $bin $bin_parm ret:$?"
      return 1
    }
  fi

  [[ -e "$log" ]] || die "No $log file"

  return 0
}

dmesg_check() {
  local key=$1
  local key_parm=$2
  local dmesg_file=""

  dmesg_file=$(extract_case_dmesg -f)
  verify_key=$(grep -i "$key" "$dmesg_file")
  case $key_parm in
    "$CONTAIN")
      if [[ -z "$verify_key" ]]; then
        die "No $key found in dmesg when test $BIN_NAME, fail."
      else
        test_print_trc "$key found in dmesg, pass."
      fi
      ;;
    "$NULL")
      if [[ -z "$verify_key" ]]; then
        test_print_trc "No $key in dmesg when test $BIN_NAME, pass."
      else
        die "$key found in dmesg when test $BIN_NAME, fail."
      fi
      ;;
    *)
      block_test "Invalid key_parm:$key_parm"
      ;;
  esac
}

cet_shstk_check() {
  local bin_name=$1
  local bin_parm=$2
  local name=$3
  local ssp=""
  local bp_add=""
  local sp=""
  local obj_log="${bin_name}.txt"

  bin=$(which "$bin_name")
  if [[ -e "$bin" ]]; then
    test_print_trc "Find bin:$bin"
  else
    die "bin:$bin does not exist"
  fi

  bin_output_dmesg "$bin" "$bin_parm"
  sleep 1
  case $name in
    cet_ssp)
      ssp=$(echo "$BIN_OUTPUT" \
            | grep "ssp" \
            | tail -1 \
            | awk -F "*ssp=0x" '{print $2}' \
            | cut -d ' ' -f 1)
      bp_add=$(echo "$BIN_OUTPUT" \
              | grep "ssp" \
              | tail -1 \
              | awk -F ":0x" '{print $2}' \
              | cut -d ' ' -f 1)
      [[ -n "$ssp" ]] || na_test "platform not support cet ssp check"
      do_cmd "objdump -d $bin > $obj_log"
      sp=$(grep -A1  "<shadow_stack_check>$" "$obj_log" \
            | tail -n 1 \
            | awk '{print $1}' \
            | cut -d ':' -f 1)
      if [[ "$ssp" == *"$sp"* ]]; then
        test_print_trc "sp:$sp is same as ssp:$ssp, pass"
      else
        test_print_wrg "sp:$sp is not same as ssp:$ssp"
        test_print_trc "clear linux compiler changed sp"
      fi
      if [[ "$bp_add" == "$ssp" ]] ; then
        test_print_trc "bp+1:$bp_add is same as ssp:$ssp, pass"
      else
        die "bp+1:$bp_add is not same as ssp:$ssp"
      fi
    ;;
    *)
      block_test "Invalid name:$name in cet_shstk_check"
    ;;
  esac
}

cet_dmesg_check() {
  local bin_name=$1
  local bin_parm=$2
  local key=$3
  local key_parm=$4
  local verify_key=""

  bin_output_dmesg "$bin_name" "$bin_parm"
  sleep 1
  verify_key=$(echo "$BIN_DMESG" | grep -i "$key")
  case $key_parm in
    "$CONTAIN")
      if [[ -z "$verify_key" ]]; then
        die "No $key found in dmesg:$BIN_DMESG when executed $bin_name $bin_parm, fail."
      else
        test_print_trc "$key found in dmesg:$BIN_DMESG, pass."
      fi
      ;;
    "$NULL")
      if [[ -z "$verify_key" ]]; then
        test_print_trc "No $key in dmesg:$BIN_DMESG when test $bin_name $bin_parm, pass."
      else
        die "$key found in dmesg when test $bin_name $bin_parm:$BIN_DMESG, fail."
      fi
      ;;
    *)
      block_test "Invalid key_parm:$key_parm"
      ;;
  esac
}

cet_tests() {
  local bin_file=""
  local legacy="legacy"

  # Absolute path of BIN_NAME
  bin_file=$(which "$BIN_NAME")
  test_print_trc "Test bin:$bin_file $PARM, $TYPE:check dmesg $KEYWORD"
  case $TYPE in
    cp_test)
      cet_dmesg_check "$bin_file" "$PARM" "$KEYWORD" "$CONTAIN"
      ;;
    kmod_ibt_illegal)
      load_cet_driver
      cet_dmesg_check "$bin_file" "$PARM" "$KEYWORD" "$CONTAIN"
      ;;
    kmod_ibt_legal)
      load_cet_driver
      cet_dmesg_check "$bin_file" "$PARM" "$KEYWORD" "$NULL"
      ;;
    no_cp)
      cet_dmesg_check "$bin_file" "$PARM" "$KEYWORD" "$NULL"
      ;;
    cet_ssp)
      cet_shstk_check "$bin_file" "$PARM" "$TYPE"
      ;;
    specific_cpu_perf)
      local cpus=""
      local cpu_num=""
      local err_num=0
      local cet_compare_path="/tmp/${TYPE}"

      cpus=$(cut -d "-" -f 2 "${CPU_SYSFS_FOLDER}/present")
      if [[ "$PARM" == "random" ]]; then
        cpu_num=$(shuf -i 0-"$cpus" -n 1)
      elif [[ "$PARM" -ge 0 && "$PARM" -le "$cpus" ]]; then
        cpu_num=$PARM
      else
        block_test "Invalid CPU NUM in PARM:$PARM"
      fi

      # Check cpu and kernel enable user space SHSTK really first
      bin_parm_test "$BIN_NAME" "0" "$TYPE" || {
          ((err_num++))
      }
      check_fail=$(grep "FAIL" "$cet_compare_path/${BIN_NAME}_0.log")
      [[ -z "$check_fail" ]] || {
        test_print_wrg "Found FAIL in $BIN_NAME 0 output:$check_fail"
        block_test "CET user space SHSTK could not be enabled!"
      }
      [[ "$err_num" -eq 0 ]] || die "Test cpu 0 $BIN_NAME failed!"

      # CPU 0 must be 1, so do not check cpu 0
      [[ "$cpu_num" -eq 0 ]] || {
        cpu_num_on_off=$(cat "${CPU_SYSFS_FOLDER}/cpu${cpu_num}/online")
        [[ "$cpu_num_on_off" == "1" ]] || OFFLINE_CPUS="$cpu_num"
        set_specific_cpu_on_off "1" "$cpu_num"
      }

      last_dmesg_timestamp
      bin_parm_test "$BIN_NAME" "$i" "$TYPE" || {
        ((err_num++))
      }
      bin_parm_test "${BIN_NAME}_${legacy}" "$i" "$TYPE" || {
        ((err_num++))
      }
      cet_perf_compare "${BIN_NAME}_${i}.log" \
        "${BIN_NAME}_${legacy}_${i}.log" "$cet_compare_path" || {
        test_print_err "CPU$i met $BIN_NAME perf regression!"
        ((err_num++))
      }
      [[ "$err_num" -eq 0 ]] || die "All cpu cet test with err_cnt:$err_num"
      dmesg_check "control protection" "$NULL"
      dmesg_check "Call Trace" "$NULL"
      dmesg_check "segfault" "$NULL"
      ;;
    all_cpu_perf)
      local cet_compare_path="/tmp/${TYPE}"
      local err_num=0
      local check_fail=""

      # Check cpu and kernel enable user space SHSTK really first
      bin_parm_test "$BIN_NAME" "0" "$TYPE" || {
          ((err_num++))
      }
      check_fail=$(grep "FAIL" "$cet_compare_path/${BIN_NAME}_0.log")
      [[ -z "$check_fail" ]] || {
        test_print_wrg "Found FAIL in $BIN_NAME 0 output:$check_fail"
        block_test "CET user space SHSTK could not be enabled!"
      }
      [[ "$err_num" -eq 0 ]] || die "Test cpu 0 $BIN_NAME failed!"

      last_dmesg_timestamp
      OFFLINE_CPUS=$(cat "${CPU_SYSFS_FOLDER}/offline")
      online_all_cpu
      cpus=$(cut -d "-" -f 2 "${CPU_SYSFS_FOLDER}/present")

      for((i=0;i<=cpus;i++)); do
        bin_parm_test "$BIN_NAME" "$i" "$TYPE" || {
          ((err_num++))
        }
        bin_parm_test "${BIN_NAME}_${legacy}" "$i" "$TYPE" || {
          ((err_num++))
        }
        cet_perf_compare "${BIN_NAME}_${i}.log" \
          "${BIN_NAME}_${legacy}_${i}.log" "$cet_compare_path" || {
          test_print_err "CPU$i met $BIN_NAME perf regression!"
          ((err_num++))
        }
      done
      [[ "$err_num" -eq 0 ]] || die "All cpu cet test with err_cnt:$err_num"
      dmesg_check "control protection" "$NULL"
      dmesg_check "Call Trace" "$NULL"
      dmesg_check "segfault" "$NULL"
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
exec_teardown
