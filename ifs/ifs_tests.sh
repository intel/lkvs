#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation
# Author: Pengfei Xu <pengfei.xu@intel.com>
# Description: Test script to verify Intel IFS(In Field SCAN) functionality

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

source "ifs_common.sh"

basic_usage() {
  cat <<-EOF >&2
  In Field Scan tests:
  usage: ./${0##*/} -m <para list>
   -m: mode number, like 0 means: /sys/devices/virtual/misc/intel_ifs_0/ folder
   -b: batch file like: /lib/firmware/intel/ifs_0/06-8f-06-01|02.scan
   -p: list of all cpu processor to test (all means all cpus)
   -n: case name to only check ifs csv file
   -f: csv file to only check ifs csv file
   -n: test Name
EOF
}

# ifs scan test in different test ways and record all dumps and info in logs.
# Output: NA
# Return: 0 for pass or other vaule for failure or die
run_ifs_tests() {
  local err=""

  [[ -z "$NAME" ]] && block_test "There is no ifs test name:$NAME"

  is_spr
  if [[ "$IS_SPR" == "$TRUE" ]]; then
    test_print_trc "it's SPR CPU, interval time:1860."
    export INTERVAL_TIME=1860
  elif [[ "$IS_SPR" == "$FALSE" ]]; then
    test_print_trc "CPU is not SPR, interval time:2."
    export INTERVAL_TIME=2
  else
    test_print_wrg "IS_SPR is not true or false!!! Set interval time:1860! DDT BUG!"
    export INTERVAL_TIME=1860
  fi

  is_atom
  [[ "$IS_ATOM" == "$TRUE" ]] && {
    if [[ "$BATCH_NUM" -eq 3 ]]; then
      skip_test "It's an atom CPU, no batch blob 3 files to test in BKC."
    fi
  }

  case $NAME in
    "$LOAD_IFS")
      modprobe -r "$IFS_NAME"
      enable_ifs_trace
      check_file_content "${IFS_PATH}/${BATCH}" "none" "$CONTAIN"
      check_file_content "${IFS_PATH}/${VERSION}" "none" "$CONTAIN"
      init_log "$NAME"
      dump_ifs_test "$NAME"
      ;;
    ifs_batch)
      modprobe -r "$IFS_NAME"
      enable_ifs_trace
      check_file_content "${IFS_PATH}/${BATCH}" "none" "$CONTAIN"
      check_file_content "${IFS_PATH}/${VERSION}" "none" "$CONTAIN"
      # Load the batch
      if [[ -e "${IFS_PATH}/${BATCH}" ]]; then
        do_cmd "echo $BATCH_NUM > ${IFS_PATH}/${BATCH}"
        check_file_content "${IFS_PATH}/${BATCH}" "$BATCH_NUM" "$CONTAIN"
        check_file_content "${IFS_PATH}/${VERSION}" "none" "$NE"
      else
        test_print_wrg "No ${IFS_PATH}/${BATCH} file, is it 5.15 or old ifs kernel?"
      fi
      init_log "$NAME"
      dump_ifs_test "$NAME"
      ;;
    "$IMG_VERSION")
      modprobe -r "$IFS_NAME"
      enable_ifs_trace
      check_file_content "${IFS_PATH}/${BATCH}" "none" "$CONTAIN"
      check_file_content "${IFS_PATH}/${VERSION}" "none" "$CONTAIN"
      # Load the batch
      if [[ -e "${IFS_PATH}/${BATCH}" ]]; then
        do_cmd "echo $BATCH_NUM > ${IFS_PATH}/${BATCH}"
        check_file_content "${IFS_PATH}/${BATCH}" "$BATCH_NUM" "$CONTAIN"
        check_file_content "${IFS_PATH}/${VERSION}" "none" "$NE"
      else
        test_print_wrg "No ${IFS_PATH}/${BATCH} file, is it 5.15 or old ifs kernel?"
      fi
      init_log "$NAME"
      dump_ifs_test "$NAME"
      check_ifs_csv "$IFS_CSV" "$NAME"
      ;;
    legacy_twice_run)
      online_all_cpu
      modprobe -r "$IFS_NAME"
      enable_ifs_trace
      do_cmd "echo $BATCH_NUM > ${IFS_PATH}/${BATCH}"
      # Need to wait after boot up 1800s, then could test ifs
      wait_up_time
      # At least sleep 2 for common situation
      do_cmd "sleep 2"
      # Execute normal scan test in first round and need to wait cooling time
      test_print_trc "***** Will run 1st round normal scan: *****"
      init_log "${CASE_NORM}_${BATCH_NUM}"
      LAST_LOG_FILE=$LOG_FILE
      wait_next_time_test
      # Save last time action time, follow test should be done in 60s
      [[ -e "$TIME_FILE" ]] && do_cmd "cp -rf $TIME_FILE $LAST_TIME_FILE"
      # Record time before test to avoid platform hang in test
      record_time
      dump_ifs_test "$NAME"
      # Check ifs csv before LOG_FILE name was changed
      check_ifs_csv "$IFS_CSV" "$CASE_NORM"

      # Execute the second round scan test in short time
      test_print_trc "***** Will run 2nd round scan in short time: *****"
      do_cmd "sleep 2"
      sleep 2
      init_log "$CASE_TWICE"
      dump_ifs_test "$NAME"
      # Record the end time after test which is the real correct end time record
      record_time
      # If it's not SPR, quick run twice should skip the check.
      is_spr
      if [[ "$IS_SPR" == "$TRUE" ]]; then
        test_print_trc "it's SPR CPU, check twice quick run csv"
        check_ifs_csv "$IFS_CSV" "$CASE_TWICE"
      elif [[ "$IS_SPR" == "$FALSE" ]]; then
        test_print_trc "CPU is not SPR, skip twice quick run csv check"
      else
        # Will not block test and still want to finish the test!
        test_print_wrg "IS_SPR:$IS_SPR is not true or false! Check twice quick run csv! DDT BUG!"
        check_ifs_csv "$IFS_CSV" "$CASE_TWICE"
      fi
      ;;
    "$IFS_OFFLINE")
      online_all_cpu
      is_atom
      [[ "$IS_ATOM" == "$TRUE" ]] && {
        skip_test "It's an atom CPU, no sibling CPU for ifs testing."
      }
      modprobe -r "$IFS_NAME"
      enable_ifs_trace
      do_cmd "echo $BATCH_NUM > ${IFS_PATH}/${BATCH}"
      init_log "${NAME}_${BATCH_NUM}"

      offline_cpu

      dump_ifs_test "$NAME"
      check_ifs_csv "$IFS_CSV" "$NAME"
      ;;
    dump)
      test_print_trc "***** Will scan and dump all cpus: *****"
      init_log "$NAME"
      [[ -e "$TIME_FILE" ]] && do_cmd "cp -rf $TIME_FILE $LAST_TIME_FILE"
      record_time
      dump_ifs_test "$NAME"
      # Record the end time after test which is the real correct end time record
      record_time
      ;;
    *)
      block_test "Invalid NAME:$NAME for test number."
      ;;
  esac

  cat "$IFS_DEBUG_LOG" > "$IFS_LOG"
  extract_case_dmesg > "$IFS_DMESG"

  [[ -z "$LAST_LOG_FILE" ]] || do_cmd "cat ${LAST_LOG_FILE}* 2>/dev/null"

  do_cmd "cat $IFS_LOG"
  do_cmd "cat $WARN_LOG"
  do_cmd "cat $IFS_CSV"

  # Check special IFS dmesg info, it's different than common "Call Trace" check
  check_ifs_dmesg "$NAME" "$PROCESSOR"

  if [[ -n "$LAST_LOG_FILE" ]]; then
    ls -ltrha "$LAST_LOG_FILE"* 2>/dev/null
  else
    do_cmd "ls -ltrha ${LOG_FILE}* 2>/dev/null"
  fi

  # Check error number in dump csv file
  if [[ "$ERR_NUM" -gt 0 ]]; then
    die "ERR_NUM:$ERR_NUM is great than 0, please check!"
  else
    test_print_trc "ERR_NUM:$ERR_NUM is 0, pass!"
  fi

  # Check error info in dmesg log
  for err in $ERR_ARRAYS; do
    check_file_content "$IFS_DMESG" "$err" "$NOT_CONTAIN"
  done
  check_file_content "$IFS_DMESG" "Call Trace" "$NOT_CONTAIN"
}

# Make sure ifs batch file is wrong and get unexpected result as expected
# Input: NA
# Return: 0 for pass or other vaule for failure or die
load_err_batch_test() {
  modprobe -r "$IFS_NAME"
  enable_ifs_trace
  # Load the wrong batch file
  if [[ -e "${IFS_PATH}/${BATCH}" ]]; then
    test_print_trc "echo $BATCH_NUM > ${IFS_PATH}/${BATCH} with error as expected"
    echo "$BATCH_NUM" > "$IFS_PATH"/"$BATCH"
    check_file_content "${IFS_PATH}/${BATCH}" "$BATCH_NUM" "$NE"
    check_file_content "${IFS_PATH}/${VERSION}" "none" "$CONTAIN"
  else
    test_print_wrg "No ${IFS_PATH}/${BATCH} file, is it 5.15 or old ifs kernel?"
  fi
  extract_case_dmesg > "/tmp/${NAME}.log"
  # Check error info in dmesg log
  for err in $ERR_ARRAYS; do
    check_file_content "/tmp/${NAME}.log" "$err" "$NOT_CONTAIN"
  done
  check_file_content "/tmp/${NAME}.log" "Call Trace" "$NOT_CONTAIN"
}

test_ifs() {
  local cpu=""

  case $MODE in
    0|1|2)
      IFS_PATH="/sys/devices/virtual/misc/intel_ifs_${MODE}"
      enable_ifs_trace
      [[ -e "$IFS_PATH" ]] || block_test "No ifs sysfs:$IFS_PATH"
      ;;
    check_csv)
      test_print_trc "***** Only check ifs csv: *****"
      check_ifs_csv "$FILE" "$CASE"
      [[ "$ERR_NUM" -eq 0 ]] || die "ERR_NUM:$ERR_NUM is not 0"
      # This case will not continue after check csv is finished
      return "$ERR_NUM"
      ;;
    pass)
      IFS_PATH="/sys/devices/virtual/misc/intel_ifs_0"
      test_print_trc "No ifs sys in this test, set ifs_0 as default:$IFS_PATH"
      ;;
    *)
      block_test "Invalid MODE:$MODE for $IFS_PATH"
      ;;
  esac

  list_cpus "$PROCESSOR"

  case $NAME in
    "reload_ifs")
      modprobe -r "$IFS_NAME"
      enable_ifs_module
      # Load the batch
      if [[ -e "${IFS_PATH}/${BATCH}" ]]; then
        do_cmd "echo $BATCH_NUM > ${IFS_PATH}/${BATCH}"
        check_file_content "${IFS_PATH}/${BATCH}" "$BATCH_NUM" "$CONTAIN"
        check_file_content "${IFS_PATH}/${VERSION}" "none" "$NE"
      else
        test_print_wrg "No ${IFS_PATH}/${BATCH} file, is it 5.15 or old ifs kernel?"
      fi
      modprobe -r "$IFS_NAME"
      enable_ifs_trace
      dmesg_common_check
      ;;
    "load_ifs_array")
      modprobe -r "$IFS_NAME"
      enable_ifs_module
      if [[ -e "${IFS_PATH}/${STATUS}" ]]; then
        check_file_content "${IFS_PATH}/${STATUS}" "untested" "$CONTAIN"
        check_file_content "${IFS_PATH}/${DETAILS}" "0x0" "$CONTAIN"
      else
        die "No ${IFS_PATH}/${STATUS} file for IFS ARRAY_BIST test!"
      fi
      ;;
    "ifs_array_scan")
      modprobe -r "$IFS_NAME"
      enable_ifs_trace
      online_all_cpu

      # Do the ifs array bist scan
      for cpu in $ALL_CPUS; do
        do_cmd "echo $cpu > ${IFS_PATH}/${RUN_TEST}"
        check_file_content "${IFS_PATH}/${STATUS}" "$PASS" "$CONTAIN"
      done
      test_print_trc "Check $IFS_DEBUG_LOG as below:"
      cat "$IFS_DEBUG_LOG"
      dmesg_common_check
      ;;
    "ifs_array_off_sib")
      modprobe -r "$IFS_NAME"
      enable_ifs_trace
      online_all_cpu

      is_atom
      if [[ "$IS_ATOM" == "$TRUE" ]]; then
        skip_test "It's an atom CPU, no sibling cpu to test ifs."
      else
        for((i=1;i<=TIMES;i++)); do
          # Here PROCESSOR should be only set to ran for ifs_array_off_sib test!
          list_cpus "$PROCESSOR"
          test_print_trc "  -> $i round IFS ARRAY cpu:$CPU_LIST scan, off sib cpu:$REMOVE_LIST:"
          [[ -z "$REMOVE_LIST" ]] && skip_test "No sibling offline CPU:$REMOVE_LIST for array off sib."
          ifs_array_off_sib_test "$CPU_LIST" "$REMOVE_LIST"
        done
      fi
      ;;
    "load_err_zero_batch")
      # Backup the origin batch file
      get_batch_file "$MODE" "$BATCH_NUM"
      # For teardown, delete useless origin file first
      do_cmd "rm -rf ${BATCH_FILE}_origin"
      [[ -e "$BATCH_FILE" ]] || block_test "No batch $BATCH_FILE file exist!"
      do_cmd "cp -rf $BATCH_FILE ${BATCH_FILE}_origin"

      # Created one error batch file by dd, zero file doesn't need to backup
      do_cmd "dd if=/dev/zero of=$BATCH_FILE bs=1M count=126"

      load_err_batch_test

      test_print_trc "Resume the batch file!"
      do_cmd "cp -rf ${BATCH_FILE}_origin $BATCH_FILE"
      ;;
    "load_err_random_batch")
      # Backup the origin batch file
      get_batch_file "$MODE" "$BATCH_NUM"
      # For teardown, delete useless origin file first
      do_cmd "rm -rf ${BATCH_FILE}_origin"
      [[ -e "$BATCH_FILE" ]] || block_test "No batch $BATCH_FILE file exist!"
      do_cmd "cp -rf $BATCH_FILE ${BATCH_FILE}_origin"

      # Created one error batch file by dd
      do_cmd "dd if=/dev/urandom of=$BATCH_FILE bs=1M count=126"
      # Backup error batch for issue debug
      do_cmd "cp -rf $BATCH_FILE ${BATCH_FILE}_random_error"

      load_err_batch_test
      test_print_trc "Resume the batch file!"
      do_cmd "cp -rf ${BATCH_FILE}_origin $BATCH_FILE"
      ;;
    "ifs_array_offran")
      enable_ifs_trace

      is_atom
      if [[ "$IS_ATOM" == "$TRUE" ]]; then
        test_print_trc "It's an atom CPU, will not test cpu offline for ifs."
      else
        for((i=1;i<=TIMES;i++)); do
          list_cpus "$PROCESSOR"
          test_print_trc "  -> $i round IFS ARRAY offline cpu:$CPU_LIST scan negative test:"
          ifs_array_off_cpu_scan "$CPU_LIST" "$ARRAY"
        done
      fi
      ;;
    "ifs_array_cpuran_fullload")
      enable_ifs_trace

      for((i=1;i<=TIMES;i++)); do
        list_cpus "$PROCESSOR"
        test_print_trc "  -> $i round IFS ARRAY cpu:$CPU_LIST load 100% scan test:"
        for cpu in $CPU_LIST; do
          ifs_array_cpu_fullload_scan "$cpu"
        done
      done
      ;;
    "msr_array")
      is_atom
      if [[ "$IS_ATOM" == "$TRUE" ]]; then
        # atom srf array bist msr should check 0x2d7 in spec
        do_cmd "rdmsr -a 0x2d7"
      elif [[ "$IS_ATOM" == "$FALSE" ]]; then
        # Xeon or big core platform should check 0x105 in spec
        do_cmd "rdmsr -a 0x105"
      else
        # No test to do and block the test as DDT BUG.
        block_test "IS_ATOM:$IS_ATOM is not true or false! DDT BUG!"
      fi
      ;;
    "ifs_legacy_array")
      local ifs_0="/sys/devices/virtual/misc/intel_ifs_0"

      enable_ifs_trace
      online_all_cpu
      # Load the batch for legacy scan needed
      if [[ -e "${ifs_0}/${BATCH}" ]]; then
        do_cmd "echo $BATCH_NUM > ${ifs_0}/${BATCH}"
        check_file_content "${ifs_0}/${BATCH}" "$BATCH_NUM" "$CONTAIN"
        check_file_content "${ifs_0}/${VERSION}" "none" "$NE"
      else
        test_print_wrg "No ${ifs_0}/${BATCH} file, is it 5.15 or old ifs kernel?"
      fi

      # Do the legacy and ARRAY_BIST scan test quickly in same CPU without issue
      for((i=1;i<=TIMES;i++)); do
        list_cpus "$PROCESSOR"
        test_print_trc "  -> $i round IFS legacy & ARRAY scan both in cpu:$CPU_LIST:"
        for cpu in $CPU_LIST; do
          # IFS legacy scan
          do_cmd "echo $cpu > ${ifs_0}/${RUN_TEST}"
          check_file_content "${ifs_0}/${STATUS}" "$PASS" "$CONTAIN"
          # IFS ARRAY_BIST scan
          do_cmd "echo $cpu > ${IFS_PATH}/${RUN_TEST}"
          check_file_content "${IFS_PATH}/${STATUS}" "$PASS" "$CONTAIN"
        done
      done

      test_print_trc "Check $IFS_DEBUG_LOG as below:"
      cat "$IFS_DEBUG_LOG"
      dmesg_common_check
      ;;
    "array_interrupt")
      enable_ifs_trace
      online_all_cpu
      for((i=1;i<=TIMES;i++)); do
        list_cpus "$PROCESSOR"
        test_print_trc "  -> $i round IFS ARRAY & interrupt test in cpu:$CPU_LIST:"
        for cpu in $CPU_LIST; do
          array_int_test "$cpu"
        done
      done
      test_print_trc "Check $IFS_DEBUG_LOG as below:"
      cat "$IFS_DEBUG_LOG"
      dmesg_common_check
      ;;
    "ifs_loop")
      modprobe -r "$IFS_NAME"
      enable_ifs_trace

      test_print_trc "echo $BATCH_NUM > /sys/devices/virtual/misc/intel_ifs_0/${BATCH}"
      echo "$BATCH_NUM" > "/sys/devices/virtual/misc/intel_ifs_0/${BATCH}"
      ifs_scan_loop "$CPU_LIST" "$TIMES"
      ;;
    "ifs_app_loop")
      modprobe -r "$IFS_NAME"
      enable_ifs_trace

      test_print_trc "echo $BATCH_NUM > /sys/devices/virtual/misc/intel_ifs_0/${BATCH}"
      echo "$BATCH_NUM" > "/sys/devices/virtual/misc/intel_ifs_0/${BATCH}"
      ifs_scan_loop "$CPU_LIST" "$TIMES" "$APP"
      ;;
    *)
      # If it's not above test name, will use run_ifs_tests way
      run_ifs_tests
      ;;
  esac
}

# Default value
: "${MODE:="0"}"
: "${BATCH_NUM:="1"}"
# cpus like 1-1 or 0-4 or 0,2,5 or ran or all types
: "${PROCESSOR:="1-1"}"
: "${NAME:="legacy_twice_run"}"
: "${TIMES:="10"}"

while getopts :a:m:p:b:i:o:n:t:f:c:h arg; do
  case $arg in
    a)
      APP=$OPTARG
      ;;
    m)
      MODE=$OPTARG
      ;;
    p)
      # PROCESSOR should fill 1-1 or 0-4 or 0,2,5 or all types
      PROCESSOR=$OPTARG
      ;;
    b)
      BATCH_NUM=$OPTARG
      ;;
    n)
      NAME=$OPTARG
      ;;
    t)
      TIMES=$OPTARG
      ;;
    f)
      FILE=$OPTARG
      ;;
    h)
      usage
      exit 2
      ;;
    *)
      usage
      die "Option -$OPTARG requires an argument."
      ;;
  esac
done

test_ifs
exec_teardown
