#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation
# Description: Test script for Intel IFS(In Field SCAN) common function

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

# For SPR legacy IFS
readonly SCAN_STATUS="0x2c7"
readonly HASHES_STATUS="0x2c3"
readonly INTG_CAP="0x2d9"
readonly CHUNK_STAT="0x2c5"
readonly MOD_ID="0x2c8"
# Output value
export NOT_READY="600007f00"
export PASS_VALUE="7f80"
# Intel ifs module name
readonly IFS_NAME="intel_ifs"
readonly IFS_TRACE="/sys/kernel/debug/tracing/events/intel_ifs/enable"
readonly IFS_DEBUG_LOG="/sys/kernel/debug/tracing/trace"
# Judgement const value
readonly PASS="pass"
readonly UNTEST="untested"
readonly CONTAIN="contain"
readonly NE="not_equal"
readonly EQUAL="equal"
readonly NOT_CONTAIN="not_contain"
readonly REMOVED_INFO="Removed_cpus_list"
readonly CASE_NORM="normal_run"
readonly CASE_TWICE="second_run_wo_wait"
readonly SIBLINGS_FILE="/sys/devices/system/cpu/cpu*/topology/thread_siblings_list"
readonly OFFLINE_FILE="/sys/devices/system/cpu/offline"
readonly ARRAY="array"

export INTEL_FW="/lib/firmware/intel"

# New sysfsfile IFS_PATH will be updated in entry script: ifs_tests.sh
# Sample: /sys/devices/virtual/misc/intel_ifs_0|1|2 folder.
IFS_PATH=""
DETAILS="details"
STATUS="status"
RUN_TEST="run_test"
VERSION="image_version"
export BATCH="current_batch"
export BATCH_NUM=""
export ERR_ARRAYS="failed error segfault"
IFS_DMESG_OFFLINE="Other thread could not join"

# CPU_LIST and REMOVE_LIST should be all cpu lists
ALL_CPUS=""
CPU_LIST=""
REMOVE_LIST=""
export SIBLING_CPU=""
REMOVED_FILE="/tmp/removed"
SIBLINGS="/tmp/siblings"
TIME_FILE="/tmp/time_ifs"
export LAST_TIME_FILE="/tmp/time_ifs_bak"
TIME_FILE_RECORD="/tmp/time_ifs_record"
INTERVAL_TIME=1860
ERR_NUM=0
export TRUE="true"
export FALSE="false"
export IS_SPR="$TRUE"
export IS_ATOM=""
# NAME and LOG FILE will be updated in entry ifs_tests.sh
export NAME=""
LOG_FILE="/tmp/ifs_"
export LAST_LOG_FILE=""
IFS_DMESG=""
IFS_LOG=""
WARN_LOG=""
IFS_CSV=""
CPU_MODEL=""
FML=""
MODEL=""
STEPPING=""
BATCH_FILE=""

LOG_MAX_LINES="20"
# Test name for different IFS test cases
LOAD_IFS="load_ifs"
IFS_BATCH="ifs_batch"
IMG_VERSION="img_version"
IFS_OFFLINE="ifs_offline"

export teardown_handler="ifs_teardown"

# Reserve for taerdown, present no change for cpu test
ifs_teardown() {
  local off_cpu=""
  local cpu=""

  off_cpu=$(cat "$OFFLINE_FILE")
  [[ -z "$off_cpu" ]] || {
    # Only resume the cpus in REMOVE_LIST for test
    for cpu in $REMOVE_LIST; do
      test_print_trc " echo 1 | sudo tee /sys/devices/system/cpu/cpu${cpu}/online"
      echo 1 | sudo tee /sys/devices/system/cpu/cpu"$cpu"/online
    done
  }
  test_print_trc "cat $OFFLINE_FILE"
  cat $OFFLINE_FILE

  if [[ -e "${BATCH_FILE}_origin" ]]; then
    diff "${BATCH_FILE}_origin" "$BATCH_FILE" || {
      echo "cp -rf ${BATCH_FILE}_origin $BATCH_FILE"
      cp -rf "${BATCH_FILE}_origin" "$BATCH_FILE"
    }
  fi
}

online_all_cpu() {
   echo "online all cpu"
  local off_cpu=""
  local cpu=""
  # cpu start
  local cpu_s=""
  # cpu end
  local cpu_e=""
  local i=""

  off_cpu=$(cat "$OFFLINE_FILE")
  if [[ -z "$off_cpu" ]]; then
    test_print_trc "No cpu offline:$off_cpu"
  else
    for cpu in $(echo "$off_cpu" | tr ',' ' '); do
      if [[ "$cpu" == *"-"* ]]; then
        cpu_s=""
        cpu_e=""
        i=""
        cpu_s=$(echo "$cpu" | cut -d "-" -f 1)
        cpu_e=$(echo "$cpu" | cut -d "-" -f 2)
        for((i=cpu_s;i<=cpu_e;i++)); do
          do_cmd "echo 1 | sudo tee /sys/devices/system/cpu/cpu${i}/online"
        done
      else
        do_cmd "echo 1 | sudo tee /sys/devices/system/cpu/cpu${cpu}/online"
      fi
    done
    off_cpu=""
    off_cpu=$(cat "$OFFLINE_FILE")
    if [[ -z "$off_cpu" ]]; then
      test_print_trc "No offline cpu:$off_cpu after online all cpu"
    else
      block_test "There is offline cpu:$off_cpu after online all cpu!"
    fi
  fi
}

# Get the cpu model info, like spr sample: 06-8f-06
# Input: NA
# Output: 0 otherwise failure or die
get_cpu_model() {
  FML=$(grep -m 1 "family" /proc/cpuinfo | awk -F ":" '{printf "%02x",$2;}')
  MODEL=$(grep -m 1 "model" /proc/cpuinfo | awk -F ":" '{printf "%02x",$2;}')
  STEPPING=$(grep -m 1 "stepping" /proc/cpuinfo | awk -F ":" '{printf "%02x",$2;}')
  export CPU_MODEL="${FML}-${MODEL}-${STEPPING}"
}

# CPUID check ATOM, IS_ATOM=true, if no IS_ATOM=false
# CPUID EAX=0x1a, and then output EAX bit29 is 1:ATOM, bit29:0 not atom
# Input: NA
# Output: 0 for true otherwise failure or die
cpuid_check_atom() {
  local cpu_num=""
  local cpu_id=""
  local cpu_check=""
  local cpuid_check="cpuid_check"

  cpu_check=$(which "$cpuid_check")
  [[ -z "$cpu_check" ]] && {
    test_print_wrg "No $cpuid_check found, will not check ATOM by cpuid way"
    IS_ATOM="$FALSE"
    return 1
  }
  cpu_num=$(grep -c "processor" /proc/cpuinfo)
  cpu_id=$((cpu_num - 1))
  # Check if CPU0 is ATOM
  taskset -c 0 "$cpu_check" 1a 0 0 0 a 29 && {
    test_print_trc "CPU0 CPUID(EAX=0x1a),EAX bit29 is 1:ATOM"
    IS_ATOM="$TRUE"
    return 0
  }

  # Check max CPU ID is ATOM
  taskset -c "$cpu_id" "$cpu_check" 1a 0 0 0 a 29 && {
    test_print_trc "CPU num:$cpu_id CPUID(EAX=0x1a),EAX bit29 is 1:ATOM"
    IS_ATOM="$TRUE"
    return 0
  }

  IS_ATOM=$FALSE
  test_print_trc "IS_ATOM:$IS_ATOM"
}

# Check is it atom only platform, if yes, IS_ATOM=true, if no IS_ATOM=false
# Input: NA
# Output: 0 for true otherwise failure or die
is_atom() {
  [[ -z "$IS_ATOM" ]] && {
    test_print_trc "IS_ATOM:$IS_ATOM is null will check."
    cpuid_check_atom
  }
}

# Check file content should exist or not
# Input:$1 file name
#       $2 expected keyword
#       $3 judge: should contain or should not contain
# Output: 0 for success, other value for failure or die
check_file_content() {
  local file=$1
  local expect=$2
  local judge=$3
  local hw_err="Hardware Error"
  local hw_err_content=""
  local content=""
  local contain=""

  [[ -e "$file" ]] || block_test "$file doesn't exist!"

  # For $hw_err, only report warning
  hw_err_content=$(grep "$hw_err" "$file")
  [[ -z "$hw_err_content" ]] || {
    test_print_wrg "There is $hw_err:$hw_err_content"
  }

  content=$(grep -v "$hw_err" "$file")
  case $judge in
    "$CONTAIN")
      if [[ "$content" != *"$expect"* ]]; then
        die "$file content:$content does not include $expect!"
      else
        test_print_trc "$file content:$content contains expected:$expect"
      fi
      ;;
    "$NE")
      if [[ "$content" == "$expect" ]]; then
        die "$file content:$content should not be $expect"
      else
        test_print_trc "$file content:$content is not:$expect, pass"
      fi
      ;;
    "$NOT_CONTAIN")
      contain=$(grep -i "$expect" "$file")
      if [[ -n "$contain" ]]; then
        die "$file should not contain $expect:$contain"
      else
        test_print_trc "$file doesn't contain $expect as expected:$contain,pass"
      fi
      ;;
    *)
      block_test "Invalid parm:$judge in check file content"
      ;;
  esac
}

# Check dmesg should contain or not contain some key word
# Input $1: key word string
#       $2: not contain($NOT_CONTAIN) or contain($CONTAIN)
# Output: 0 otherwise failure or die
dmesg_check() {
  local key=$1
  local judge=$2

  extract_case_dmesg > "/tmp/${NAME}.txt"
  # Check key word by request
  check_file_content "/tmp/${NAME}.txt" "$key" "$judge"
}

dmesg_common_check() {
  extract_case_dmesg > "/tmp/${NAME}.log"
  # Check error info in dmesg log
  for err in $ERR_ARRAYS; do
    check_file_content "/tmp/${NAME}.log" "$err" "$NOT_CONTAIN"
  done
  check_file_content "/tmp/${NAME}.log" "Call Trace" "$NOT_CONTAIN"
}

cpu_full_load() {
  local cpu=$1
  local pid_dd=""
  local pid=""

  do_cmd "taskset -c $cpu dd if=/dev/zero of=/dev/null &"

  # pgrep could not get the target process
  pid_dd=$(ps -ef | grep dd | grep if \
                  | grep zero | grep of | grep dev \
                  | awk -F " " '{print $2}')

  test_print_trc "pid_dd:$pid_dd"
  # Not use do_cmd for sleep, because do_cmd show 2 lines print, too much print
  test_print_trc "sleep 4"
  sleep 4
  for pid in $pid_dd; do
    # Maybe kill will return failed with no such process, so don't use do_cmd
    test_print_trc "kill -9 $pid"
    kill -9 "$pid"
  done
}

# Enable driver intel_ifs if intel_ifs is not loaded
enable_ifs_module() {
  local ifs_info=""

  ifs_info=$(lsmod | grep "$IFS_NAME")
  if [[ -z "$ifs_info" ]]; then
    do_cmd "modprobe $IFS_NAME"
    ifs_info=$(modinfo $IFS_NAME 2>/dev/null | grep filename)
    [[ -z "$ifs_info" ]] && die "modprobe $IFS_NAME failed!"
  else
    test_print_trc "$IFS_NAME is loaded:$ifs_info"
  fi
}

enable_ifs_trace() {
  local ifs_info=""

  ifs_info=$(lsmod | grep "$IFS_NAME")
  [[ -z "$ifs_info" ]] && {
    test_print_trc "No $IFS_NAME module, will enable it."
    enable_ifs_module
  }
  if [[ -e "$IFS_TRACE" ]]; then
    do_cmd "echo 1 > $IFS_TRACE"
  else
    block_test "There is no $IFS_TRACE file existed!"
  fi

  # clear trace info
  do_cmd "cat /dev/null > $IFS_DEBUG_LOG"
}

# Wait up time to exceed more than 1800s
wait_up_time() {
  local up_sec=""
  local sleep_sec=""

  # uptime -p is not good, use /proc/uptime directly
  up_sec=$(awk -F. '{print $1}' /proc/uptime)
  if [[ "$up_sec" -lt "$INTERVAL_TIME" ]]; then
    sleep_sec=$((INTERVAL_TIME-up_sec))
    test_print_trc "up sec:$up_sec less than $INTERVAL_TIME, sleep $sleep_sec"
    do_cmd "sleep $sleep_sec"
  else
    test_print_trc "up sec:$up_sec is more than $INTERVAL_TIME, no need sleep"
  fi
}

record_time() {
  [[ -e "$TIME_FILE" ]] && cp -rf "$TIME_FILE" "$TIME_FILE_RECORD"

  date +%s > "$TIME_FILE"
  date +%Y-%m-%d_%H:%M:%S >> "$TIME_FILE"
}

# Each round test needs to wait INTERVAL TIME seconds to do next round
wait_next_time_test() {
  local time_sec=""
  local time_info=""
  local now_sec=""
  local gap_sec=""
  local sleep_sec=""

  if [[ -e "$TIME_FILE" ]]; then
    time_sec=$(cat $TIME_FILE | head -n 1)
    time_info=$(cat $TIME_FILE | tail -n 1)
    if [[ "$time_sec" -ge 0 ]] 2>/dev/null; then
        test_print_trc "$TIME_FILE content:$time_sec is a number."
    else
        test_print_wrg "$TIME_FILE content:$time_sec is not a number, ignore"
        return 0
    fi

    now_sec=$(date +%s)
    gap_sec=$((now_sec-time_sec))
    if [[ "$gap_sec" -lt "$INTERVAL_TIME" ]]; then
      sleep_sec=$((INTERVAL_TIME-gap_sec))
      test_print_trc "last:$time_sec,$time_info, now sec:$now_sec"
      do_cmd "sleep $sleep_sec"
    else
      test_print_trc "last:$time_sec,$time_info,now:$now_sec, $gap_sec>$INTERVAL_TIME"
    fi
  else
    test_print_trc "No $TIME_FILE, will not sleep for next time test."
  fi
}

# Update dependent first sibling cpus info in CPU_LIST file
# It's for all cpu list with different type of list
# Output: ALL_CPUS:all cpus, CPU_LIST: SIBLINGS cpus, REMOVE_LIST: removed cpus
get_depend_sibling_cpus() {
  local cpu_num=""
  local atom=""
  local server=""
  local remove_cpu=""

  REMOVE_LIST=""
  online_all_cpu
  cpu_num=$(grep -c processor /proc/cpuinfo)

  # Show all cpu list in one line, reason:echo could make them in 1 line!
  # Will use the ALL_CPUS to remove SIBLINGS cpu
  ALL_CPUS=$(echo $(seq 0 $((cpu_num - 1))))
  ALL_CPUS=" $ALL_CPUS "
  echo "$ALL_CPUS" > $SIBLINGS
  # atom used "-" and server used "," to isolate
  # Don't use $SIBLINGS_FILE, otherwise will fail the case due to *!
  atom=$(cat /sys/devices/system/cpu/cpu*/topology/thread_siblings_list \
        | grep "-" \
        | awk -F "-" '{print $NF}')
  # Don't use $SIBLINGS_FILE, otherwise will fail the case due to *!
  server=$(cat /sys/devices/system/cpu/cpu*/topology/thread_siblings_list \
          | grep "," \
          | awk -F "," '{print $NF}')
  REMOVE_LIST=" $atom $server "
  echo "$REMOVE_LIST" > "$REMOVED_FILE"
  # After sort with uniq number, saved the removed list in file
  REMOVE_LIST=$(sort -nu "$REMOVED_FILE")
  echo "$REMOVE_LIST" > "$REMOVED_FILE"
  for remove_cpu in $REMOVE_LIST; do
    sed -i s/" $remove_cpu "/' '/g $SIBLINGS
  done
  CPU_LIST=$(cat $SIBLINGS)
}

get_sibling_cpu() {
  local cpu=$1
  local sibling_cpus=""

  # Don't use $SIBLINGS_FILE, otherwise will fail the case due to *!
  sibling_cpus=$(cat /sys/devices/system/cpu/cpu*/topology/thread_siblings_list \
                | grep "^${cpu}\," \
                | tail -n 1)
  if [[ -n "$sibling_cpus" ]]; then
    SIBLING_CPU=$(echo "$sibling_cpus" | cut -d "," -f 2)
  else
    sibling_cpus=$(cat /sys/devices/system/cpu/cpu*/topology/thread_siblings_list \
                  | grep "\,${cpu}" \
                  | tail -n 1)
    if [[ -z "$sibling_cpus" ]]; then
      test_print_wrg "Could not get the sibling_cpu for $cpu, is it atom core?"
      SIBLING_CPU=""
    else
      SIBLING_CPU=$(echo "$sibling_cpus" | cut -d "," -f 1)
    fi
  fi
}

# List specific cpus with fill "1-1 or 0-4 or 0,2,5 or all" cpus in CPU_LIST
# If for all, will also list REMOVE_LIST.
list_cpus() {
  local cpus=$1
  local start=""
  local cpu_num=""
  local end=""
  local i=""

  test_print_trc "Will test cpus:$cpus"
  case $cpus in
    all)
      get_depend_sibling_cpus
      ;;
    ran)
      cpu_num=$(grep -c processor /proc/cpuinfo)
      # From v6.4-rc2, commit e59e74dc48a3: Remove CPU0 hotplug option
      # So will not offline cpu0
      CPU_LIST=$(shuf -i 1-$((cpu_num-1)) -n 1)
      # In this situation CPU_LIST will only has 1 cpu num value
      get_sibling_cpu "$CPU_LIST"
      REMOVE_LIST="$SIBLING_CPU"

      # If SIBLING_CPU equal to 0, will set CPU_LIST to 1 and get sibling again
      if [[ "$SIBLING_CPU" == "0" ]]; then
        test_print_wrg "Get sibling cpu to 0:$SIBLING_CPU, set 1 to get again!"
        CPU_LIST=1
        get_sibling_cpu "$CPU_LIST"
        REMOVE_LIST="$SIBLING_CPU"
      fi
      ;;
    *","*)
      CPU_LIST=$(echo "$cpus" | tr "," " ")
      ;;
    *"-"*)
      start=$(echo "$cpus" | cut -d '-' -f 1)
      end=$(echo "$cpus" | cut -d '-' -f 2)
      for((i=start;i<=end;i++)); do
        CPU_LIST="$CPU_LIST $i"
      done
      ;;
    *)
      block_test "Invalid cpus:$cpus"
      ;;
  esac
}

# Offline cpu list in REMOVE_LIST
offline_cpu() {
  local cpu=""

  for cpu in $REMOVE_LIST; do
    do_cmd "echo 0 | sudo tee /sys/devices/system/cpu/cpu${cpu}/online"
  done

  do_cmd "cat $OFFLINE_FILE"
}

init_log() {
  local name=$1

  LOG_FILE="${LOG_FILE}${name}_$(date +%y%m%d-%H%M%S)"
  IFS_DMESG="$LOG_FILE.dmesg"
  IFS_LOG="$LOG_FILE.log"
  WARN_LOG="$LOG_FILE.warn"
  IFS_CSV="$LOG_FILE.csv"

  # Start to record log
  do_cmd "echo '$(date +%y%m%d-%H%M%S): $IFS_DEBUG_LOG as below:' > $IFS_LOG"
  do_cmd "echo '$(date +%y%m%d-%H%M%S): cpu warning list:' > $WARN_LOG"
  do_cmd "echo '#cpu,img_version,details,status,Before rdmsr $SCAN_STATUS,After rdmsr $SCAN_STATUS,'" \
    "'rdmsr $HASHES_STATUS,rdmsr $INTG_CAP,rdmsr $CHUNK_STAT,rdmsr $MOD_ID' > $IFS_CSV"
}

# Scan and dump the specific cpu
# Input $1: specific cpu num
#       $2: test name for some specific action before dump
# Return: 0 for pass other value for failure or die
dump_specific_cpu() {
  local cpu=$1
  local name=$2
  local msr_status=""
  local status=""
  local ver=""
  local details=""
  local msr_stat=""
  local msr_hash=""
  local one_line=""
  local cap=""
  local chunk=""
  local modid=""

  case $name in
    "$LOAD_IFS")
      ;;
    "$IFS_BATCH")
      ;;
    "$IMG_VERSION")
      ;;
    *)
      # Check specific cpu rdmsr $SCAN_STATUS before test
      msr_status=$(rdmsr -p "$cpu" "$SCAN_STATUS")
      do_cmd "echo $cpu > ${IFS_PATH}/${RUN_TEST}"
      ;;
  esac

  # Read the test result from rdmsr
  msr_stat=$(rdmsr -p "$cpu" "$SCAN_STATUS")
  msr_hash=$(rdmsr -p "$cpu" "$HASHES_STATUS")
  msr_hash="0x${msr_hash}"
  status=$(cat "$IFS_PATH"/"$STATUS")
  details=$(cat "$IFS_PATH"/"$DETAILS")
  ver=$(cat "$IFS_PATH"/"$VERSION")
  cap=$(rdmsr -p "$cpu" "$INTG_CAP")
  chunk=$(rdmsr -p "$cpu" "$CHUNK_STAT")
  modid=$(rdmsr -p "$cpu" "$MOD_ID")

  # Don't fill any space, otherwise it will cause for loop with error
  one_line="${cpu},${ver},${details},${status},${msr_status},${msr_stat},${msr_hash},\
${cap},${chunk},${modid}"
  echo "$one_line" >> "$IFS_CSV"
}

# Run scan test and dump each time test results in related files.
# Input $1: specific cpu num
# Return: 0 for true, otherwise false
dump_ifs_test() {
  local name=$1
  local cpu=""

  modprobe msr

  for cpu in $CPU_LIST; do
    dump_specific_cpu "$cpu" "$name"
  done

  if [[ -z "$REMOVE_LIST" ]]; then
    test_print_trc "No remove cpu list:$REMOVE_LIST, don't need scan and dump"
  elif [[ "$name" == "$IFS_OFFLINE" ]]; then
    test_print_trc "case:$name, will not scan offline cpus!"
  else
    test_print_trc "Will scan and dump remove cpu list:"
    do_cmd "echo '#$REMOVED_INFO' >> $IFS_CSV"
    for cpu in $REMOVE_LIST; do
      dump_specific_cpu "$cpu" "$name"
    done
  fi
}

# Check columns a and columns b value should be same
# $1: content: sample: 0,0x101,0x7f80,pass,600007f00,7f80,80000000008003e8,...
# $2: Column a
# $3: Column b
# $4: equal or not equal
# $5: case name
# Return 0 for pass, other value for failure or die
check_columns() {
  local line=$1
  local col_a=$2
  local col_b=$3
  local judge=$4
  local case=$5
  local cpu=""
  local a_val=""
  local b_val=""

  cpu=$(echo "$line" | cut -d "," -f 1)
  a_val=$(echo "$line" | cut -d "," -f "$col_a")
  b_val=$(echo "$line" | cut -d "," -f "$col_b")
  a_val=${a_val//0x/}
  b_val=${b_val//0x/}

  [[ "$cpu" -ge 0 ]] 2>/dev/null || {
    test_print_wrg "cpu:$cpu is not a number, skip!"
    return 0
  }

  case $judge in
    "$EQUAL")
      if [[ "$a_val" != "$b_val" ]]; then
        test_print_err "$case:cpu $cpu col$col_a:$a_val != col$col_b:$b_val"
        echo "[ERROR]:$case:cpu $cpu col$col_a:$a_val != col$col_b:$b_val" >> "$WARN_LOG"
        ((ERR_NUM++))
      fi
      ;;
    "$NE")
      if [[ "$a_val" == "$b_val" ]]; then
        test_print_err "$case:cpu $cpu col$col_a:$a_val == col$col_b:$b_val"
        echo "[ERROR]:$case:cpu $cpu col$col_a:$a_val == col$col_b:$b_val" >> "$WARN_LOG"
        ((ERR_NUM++))
      fi
      ;;
    "$CONTAIN")
      if [[ "$a_val" != *"$b_val"* ]]; then
        test_print_err "$case:cpu $cpu col$col_a:$a_val not contain col$col_b:$b_val"
        echo "[ERROR]:$case:cpu $cpu col$col_a:$a_val not contain col$col_b:$b_val" >> "$WARN_LOG"
        ((ERR_NUM++))
      fi
      ;;
    "*")
      block_test "Invalid parm in check columns"
      ;;
  esac
}

# Check columns a should equal to expected value
# $1: content: sample: 0,0x101,0x7f80,pass,600007f00,7f80,80000000008003e8,11...
# $2: Column a
# $3: Expected value
# $4: equal or not equal
# $5: case name
# Return 0 for pass, other value for failure or die
check_column_value() {
  local line=$1
  local col_a=$2
  local expect=$3
  local judge=$4
  local case=$5
  local cpu=""
  local a_val=""

  cpu=$(echo "$line" | awk -F "," '{print $1}')
  [[ "$cpu" -ge 0 ]] 2>/dev/null || {
    test_print_wrg "cpu:$cpu is not a number, skip!"
    return 0
  }
  a_val=$(echo "$line" | cut -d "," -f "$col_a")

  case $judge in
    "$EQUAL")
      if [[ "$a_val" != "$expect" ]]; then
        test_print_err "$case:cpu $cpu col$col_a:$a_val != expected:$expect"
        echo "[ERROR]:$case:cpu $cpu col$col_a:$a_val != expected:$expect" >> "$WARN_LOG"
        ((ERR_NUM++))
      fi
      ;;
    "$NE")
      if [[ "$a_val" == "$b_val" ]]; then
        test_print_err "$case:cpu $cpu col$col_a:$a_val == expected:$expect"
        echo "[ERROR]:$case:cpu $cpu col$col_a:$a_val == expected:$expect" >> "$WARN_LOG"
        ((ERR_NUM++))
      fi
      ;;
    "*")
      block_test "Invalid parm in check column value"
     ;;
  esac
}

# Check value Nth bit should be equal to char value
# $1: content: sample: 0x100007f00
# $2: column num
# $3: Nth bit  like above 9bit should be 1, start from right with 1
# $4: Expected value like 1
# $5: equal or not equal
# $6: case name
# Return 0 for pass, other value for failure or die
verify_bit_char() {
  local line=$1
  local col=$2
  local nth_bit=$3
  local exp_val=$4
  local judge=$5
  local case=$6
  local content=""
  local cpu=""
  local val=""

  cpu=$(echo "$line" | cut -d "," -f "1")
  content=$(echo "$line" | cut -d "," -f "$col")
  val=${content: 0-${nth_bit}: 1}
  [[ -z "$val" ]] && {
    test_print_trc "case:$case cpu:$cpu $content $nth_bit bit is null, use 0 instead"
  }

  case $judge in
    "$EQUAL")
      if [[ "$val" != "$exp_val" ]]; then
        test_print_wrg "case:$case cpu:$cpu $content $nth_bit bit is not $exp_val:$val"
        echo "[ERROR]:case:$case cpu:$cpu $content $nth_bit bit is not $exp_val:$val" >> "$WARN_LOG"
        ((ERR_NUM++))
      fi
      ;;
    *)
      block_test "Invalid parm:$judge in verify bit char function"
      ;;
  esac
}

# Check specific csv file, each cpu should meet the judgement
# $1: IFS csv file
# $2: case: Different case name will use different judgement
# Return 0 for pass or other valure for failure or die
check_ifs_csv() {
  local csv=$1
  local case=$2
  local lines=""
  local line=""
  local a_val=""
  local b_val=""

  [[ -e "$csv" ]] || block_test "There is no $csv file found!"

  grep -q "$REMOVED_INFO" "$csv" && {
    test_print_trc "$csv contains $REMOVED_INFO info, will ignore removed part!"
    lines=$(grep -m 1 "$REMOVED_INFO" -B 100000 "$csv")
  }
  lines=$(echo "$lines" | grep -v "^#")

  for line in $lines; do
    case $case in
      "$CASE_NORM")
        # Sample: 0,0x101,0x7f80,pass,600007f00,7f80,80000000008003e8,11,8080,
        #         80000000
        check_columns "$line" "3" "6" "$EQUAL" "$case"
        check_column_value "$line" "4" "$PASS" "$EQUAL" "$case"
        ;;
      "$CASE_TWICE")
        check_columns "$line" "3" "6" "$EQUAL" "$case"
        check_column_value "$line" "4" "$UNTEST" "$EQUAL" "$case"
        ;;
      "$IMG_VERSION")
        is_atom
        if [[ "$IS_ATOM" == "$TRUE" ]]; then
          test_print_trc "It's an atom CPU, should not check MSR:$MOD_ID"
        else
          check_columns "$line" "2" "10" "$CONTAIN" "$case"
        fi
        ;;
      "$IFS_OFFLINE")
        # Sample: 0,0x101,0x100007f00,pass,600007f00,100007f00,80000000008003e8,11,8080,
        #         80000000
        check_columns "$line" "3" "6" "$EQUAL" "$case"
        verify_bit_char "$line" "3" "9" "1" "$EQUAL" "$case"
        verify_bit_char "$line" "6" "9" "1" "$EQUAL" "$case"
        ;;
      *)
        block_test "Invalid parm in check_ifs_csv function."
        ;;
    esac
  done
  test_print_trc "Check $case for $csv finished, ERR_NUM:$ERR_NUM"
}

# Check some special IFS dmesg info
# Input $1: case name
#       $2: cpus list
# Output: 0 otherwise failure or die
check_ifs_dmesg() {
  local case=$1
  local cpus=$2
  local cpu=""

  case $case in
    "$IFS_OFFLINE")
      if [[ "$cpus" == "all" ]]; then
        test_print_trc "cat $IFS_DMESG | awk -F ']' '{print $2}' | grep '$IFS_DMESG_OFFLINE' > ${IFS_DMESG}.filter"
        awk -F "]" '{print $2}' "$IFS_DMESG" | grep "$IFS_DMESG_OFFLINE" >  "${IFS_DMESG}.filter"
        for cpu in $CPU_LIST; do
          check_file_content "${IFS_DMESG}.filter" "$cpu" "$CONTAIN"
        done
      else
        test_print_trc "Not all cpus:$cpus, will not check ifs dmesg for $case"
      fi
      ;;
    *)
      test_print_trc "No special dmesg check for ifs case:$case"
      ;;
  esac
}

# Check is it SPR platform, if yes, IS_SPR=true, if no IS_SPR=false
# Input: NA
# Output: 0 for true otherwise failure or die
is_spr() {
  # If platform is not SPR, IFS will use different test way than SPR
  get_cpu_model
  if [[ "$FML" == "06" ]]; then
    if [[ "$MODEL" == *"8f"* ]]; then
      test_print_trc "CPU model is 8f:$MODEL, it's SPR CPU, IS_SPR set true."
      IS_SPR="$TRUE"
    else
      test_print_trc "CPU model is not 8f:$MODEL, not SPR, IS_SPR set false."
      IS_SPR="$FALSE"
    fi
  else
    test_print_wrg "CPU family is not 06:$FML, IS_SPR set false"
    IS_SPR="$FALSE"
  fi
}

# ifs array scan test with couple of sibling cpu, trace no more than 20 lines
# Input $1: cpu num to scan
#       $2: sibling cpu will offline
# Output: 0 otherwise failure or die
ifs_array_off_sib_test() {
  local cpu=$1
  local off_cpu=$2
  local check=""
  local log=""
  local line_num=""

  [[ -z "$off_cpu" ]] && skip_test "No off_cpu:$off_cpu in array sib test."
  # Clean the trace first
  do_cmd "cat /dev/null > $IFS_DEBUG_LOG"

  # Don't use $SIBLINGS_FILE, otherwise will fail the case due to *!
  check=$(cat /sys/devices/system/cpu/cpu*/topology/thread_siblings_list \
        | grep "$cpu" \
        | grep "$off_cpu")

  if [[ -z "$check" ]]; then
    block_test "Input cpu:$$cpu and $off_cpu are not sibling in $SIBLINGS_FILE"
  fi
  do_cmd "echo 0 | sudo tee /sys/devices/system/cpu/cpu${off_cpu}/online"
  do_cmd "echo $cpu > ${IFS_PATH}/${RUN_TEST}"
  # Online the offline cpu after test
  do_cmd "echo 1 | sudo tee /sys/devices/system/cpu/cpu${off_cpu}/online"

  log=$(cat $IFS_DEBUG_LOG | grep "\-" | grep "\.")
  line_num=$(cat $IFS_DEBUG_LOG | grep "\-" | grep -c "\.")
  if [[ "$line_num" -gt "$LOG_MAX_LINES" ]]; then
    test_print_wrg "IFS ARRAY off sibling cpu tries:$line_num > $LOG_MAX_LINES:$log"
  else
    test_print_trc "IFS ARRAY off sibling cpu no more than $LOG_MAX_LINES tries, pass:$log"
  fi
}

# ifs array scan test, offline CPU and scan should failed as expected
# Input $1: cpu num will offline and then scan
# Output: 0 otherwise failure or die
ifs_array_off_cpu_scan() {
  local off_cpus=$1
  local ifs_func=$2
  local off_cpu=""
  local key_word="cannot test on the offline cpu"
  local ret=""

  [[ -z "$off_cpus" ]] && skip_test "No off_cpus:$off_cpus"
  for off_cpu in $off_cpus; do
    do_cmd "echo 0 | sudo tee /sys/devices/system/cpu/cpu${off_cpu}/online"
    test_print_trc "echo $off_cpu > ${IFS_PATH}/${RUN_TEST}"
    # Negative test and could not use do_cmd
    echo "$off_cpu" > "$IFS_PATH"/"$RUN_TEST"
    # Need to check echo > command return value
    ret="$?"
    if [[ "$ret" -eq 0 ]]; then
      die "Run cpu $off_cpu IFS ARRAY test should fail but passed:$ret"
    else
      test_print_trc "Run cpu $off_cpu IFS ARRAY negative test failed as expected:$ret"
    fi
    # Online the offline cpu after test
    do_cmd "echo 1 | sudo tee /sys/devices/system/cpu/cpu${off_cpu}/online"
  done
  dmesg_common_check
  if [[ "$ifs_func" == "$ARRAY" ]]; then
    dmesg_check "$key_word" "$CONTAIN"
  else
    test_print_wrg "Invalid IFS func:$ifs_func, will not check keyword dmesg."
  fi
}

# ifs array scan test, fully load CPU and ifs scan should pass
# Input $1: cpu num will load 100% and scan
# Output: 0 otherwise failure or die
ifs_array_cpu_fullload_scan() {
  local cpus=$1
  local cpu=""

  for cpu in $cpus; do
    cpu_full_load "$cpu"
    # Wait the cpu load 100%
    sleep 1
    echo "$cpu" > "$IFS_PATH"/"$RUN_TEST"
    # Need to check echo > command return value
    ret="$?"
    if [[ "$ret" -eq 0 ]]; then
      test_print_trc "Run cpu:$cpu full load IFS ARRAY test pass:$ret"
    else
      die "Run cpu:$cpu full load IFS ARRAY test failed:$ret"
    fi
    dmesg_common_check
    sleep 3
  done
}

# Do array bist scan with interrupt in target CPU without issue
# Input $1: cpu num will load 100% and scan
# Output: 0 otherwise failure or die
array_int_test() {
  local cpu=$1
  # Will sleep 28s
  local sec="28"
  # Child pid
  local cpid=""
  local pid=""

  # Create one child pid to do sleep 30 for kill
  do_cmd "taskset -c $cpu sleep $sec &"
  # Need ps -ef not pgrep!
  cpid=$(ps -ef | grep -v "grep" | grep  "sleep $sec" | awk -F " " '{print $2}')
  for pid in $cpid; do
    test_print_trc "Will echo $cpu > ${IFS_PATH}/${RUN_TEST}; kill -INT $pid"
    # Will not use do_cmd, because the scan time is very short(<10ms)!
    echo "$cpu" > "${IFS_PATH}/${RUN_TEST}"
    kill -INT "$pid"
    check_file_content "${IFS_PATH}/${STATUS}" "$PASS" "$CONTAIN"
  done
}

ifs_scan_loop() {
  local cpu_num=$1
  local times=$2
  local binary=$3
  local bin=""
  local result=""
  local failed_num=0

  if [[ -n "$binary" ]]; then
    bin=$(which "$binary")
    [[ -z "$bin" ]] && block_test "No $binary found for path of bin:$bin"
  fi

  for ((i=1; i<=times; i++)); do
    test_print_trc "Scan loop times:$i"
    # If there is bin app, execute the app in target CPU
    [[ -n "$bin" ]] && {
      taskset -c "$cpu_num" "$bin" &
    }
    echo "$cpu_num" > "${IFS_PATH}/${RUN_TEST}"
    result=""
    result=$(cat "$IFS_PATH"/${STATUS})
    echo "CPU:$cpu_num $IFS_PATH/status: $result Details: $(cat "$IFS_PATH"/${DETAILS})"
    if [[ "$result" != "$PASS" ]]; then
      ((failed_num++))
    fi
  done

  if [[ "$failed_num" -eq 0 ]]; then
    test_print_trc "$IFS_PATH|$bin test all passed, failed cases num:$failed_num."
  else
    die "$IFS_PATH|$bin test contained failed cases, failed num:$failed_num, please check."
  fi
}

# Get the batch file name with platform cpu info
# Input $1: mode num 0|1
#       $2: batch num 1|2|3
# Output: 0 otherwise failure or die
get_batch_file() {
  local mode_num=$1
  local batch_num=$2

  get_cpu_model
  # Sample: /lib/firmware/intel/ifs_0/06-8f-06-01.scan for SPR
  export BATCH_FILE="${INTEL_FW}/ifs_${mode_num}/${CPU_MODEL}-0${batch_num}.scan"
}
