#!/usr/bin/env bash
###############################################################################
# SPDX-License-Identifier: GPL-2.0-only                                       #
# Copyright (c) 2022 Intel Corporation.                                       #
#                                                                             #
# Common Bash Functions                                                       #
###############################################################################

# Check whether current user is root, if not, exit directly
root_check() {
  local user=""

  if command -v whoami &> /dev/null; then
    user=$(whoami)
  elif command -v id &> /dev/null; then
    user=$(id -nu)
  else
    user="${USER}"
  fi

  if [[ "${user}" != "root" ]]; then
    echo "LKVS must run with root privilege!"
    exit 1
  fi
}
root_check

TIME_FMT="%m%d_%H%M%S.%3N"

# Print trace log.
# Arguments:
#   $1: trace log
test_print_trc(){
  echo "|$(date +"$TIME_FMT")|TRACE|$1|"
}

# Print test warning message.
# Arguments:
#   $1: warning message
test_print_wrg(){
  caller_info="${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}:${FUNCNAME[1]}()"
  echo "|$(date +"$TIME_FMT")|WARNING| $caller_info - $*|" >&2
}

# Print test error message.
# Arguments:
#   $1: error message
test_print_err(){
  caller_info="${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}:${FUNCNAME[1]}()"
  echo "|$(date +"$TIME_FMT")|ERROR| $caller_info - $*|" >&2
}

# Execute teardown function. A teardown function should be registered
# before calling this function, for example:
#   teardown_handler="my_teardown_func"
#   do_cmd "my_test"
#   exec_teardown
# Globals:
#   teardown_handler
#   ?
# Returns:
#   Status code before execute teardown
teardown_handler=""
exec_teardown() {
  #Record the original return value before excuting teardown function
  local original_ret=$?

  # return if teardown function is not registered
  [[ -n "$teardown_handler" ]] || return $original_ret

  test_print_trc "-------- Teardown starts --------"
  test_print_trc "Teardown handler: $teardown_handler"
  eval "$teardown_handler" || test_print_err "Teardown failed"
  test_print_trc "-------- Teardown ends ---------"

  return $original_ret
}

# Wrapper function of executable object. If the return code of the executable
# is none-zero, do_cmd exits current process directly with the none-zero code.
# Argument:
#   $1: Executable object
do_cmd() {
  CMD=$*

  caller_info="${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}:${FUNCNAME[1]}()"
  test_print_trc "do_cmd() is called by $caller_info"
  test_print_trc "CMD=$CMD"

  eval "$CMD"
  RESULT=$?

  if [[ $RESULT -ne 0 ]]; then
    test_print_err "$CMD failed. Return code is $RESULT"
    if [[ $RESULT -eq 32 || $RESULT -eq 2 ]]; then
      test_print_trc "Return code $RESULT is reserved, change to 1"
      RESULT=1
    fi
    exec_teardown
    exit $RESULT
  fi
}

# Wrapper function of executable object. If the return code of executable object is 0,
# which is unexpected, should_fail exits current process directly with code 1.
# Arguments:
#   $1: Executable object
should_fail() {
  # execute a command and check if it fails, exit 1 if it passes
  CMD=$*

  caller_info="${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}:${FUNCNAME[1]}()"
  test_print_trc "should_fail() is called by $caller_info"
  test_print_trc "CMD=$CMD"

  if eval "$CMD"; then
    test_print_err "Command passes, but failed result is expected."
    exec_teardown
    exit 1
  else
    test_print_trc "Command fails as expected."
  fi
}

# Wrapper function to fail a test, accept a string to explain why the test fails.
# exec_teardown is called before failing the test.
# Arguments:
#   $1: Message to explain why the test is failed
die() {
  caller_info="${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}:${FUNCNAME[1]}()"
  test_print_err "FATAL: die() is called by $caller_info"
  test_print_err "FATAL: $*"
  exec_teardown
  exit 1
}

# Wrapper function to skip a test, accept a string
# to explain why test is skipped. exec_teardown
# is called before skipping the test.
# Arguments:
#   $1: Message to exaplain why the test is skipped
skip_test() {
  caller_info="${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}:${FUNCNAME[1]}()"
  test_print_wrg "skip_test() is called by $caller_info"
  test_print_wrg "SKIPPING TEST: $*"
  exec_teardown
  exit 0
}

# Wrapper function to block a test, it accepts a string
# to explain why test should be blocked. exec_teardown
# is called before blocking the test.
# Arguments:
#   $1: Message to exaplain why the test is blocked
block_test() {
  caller_info="${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}:${FUNCNAME[1]}()"
  test_print_err "block_test() is called by $caller_info"
  test_print_err "Result ====BLOCK==== : $*"
  exec_teardown
  exit 2
}

# Wrapper function to mark a test as not applicable,
# it accepts a string to explain why the test is not
# applicable. exec_teardown is called before exiting with 32.
# Arguments:
#   $1: Message to exaplain why the test is not applicable
na_test() {
  caller_info="${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}:${FUNCNAME[1]}()"
  test_print_wrg "na_test() is called by $caller_info"
  test_print_wrg "NA TEST: $*"
  exec_teardown
  exit 32
}

# Compare two files based on md5sum
# Arguments:
#   $1: File 1
#   $2: File 2
# Returns:
#   0 if md5sum of 2 files are same
#   1 if md5sum of 2 files are not same
compare_md5sum() {
  local file1=$1
  local file2=$2
  local file1_md5
  local file2_md5

  if ! file1_md5=$(md5sum "$file1" | cut -d' ' -f1); then
    test_print_err "Error getting md5sum of $file1"
    exit 1
  fi
  test_print_trc "$file1: $file1_md5"

  if ! file2_md5=$(md5sum "$file2" | cut -d' ' -f1); then
    test_print_err "Error getting md5sum of $file2"
    exit 1
  fi
  test_print_trc "$file2: $file2_md5"

  [[ "$file1_md5" == "$file2_md5" ]]
}

# Get kernel config value.
# Arguments:
#   $1: Kernel configuration option
# Returns:
#   0: read value successfully
#   1: no kconfigs file found on the system
# Output:
#   value of the Kernel config option, y,m or n
#   If no kconfigs file found, output is empty
get_kconfig() {
  local koption="$1"
  local value=""

  if [[ -r "/proc/config.gz" ]]; then
    value=$(zcat "/proc/config.gz" | grep -E "^$koption=" | cut -d'=' -f2)
  elif [[ -r "/boot/config-$(uname -r)" ]]; then
    value=$(grep -E "^$koption=" "/boot/config-$(uname -r)" | cut -d'=' -f2)
  elif [[ -r "/lib/modules/$(uname -r)/build/.config" ]]; then
    value=$(grep -E "^$koption=" "/lib/modules/$(uname -r)/build/.config" | cut -d'=' -f2)
  else
    test_print_wrg "No config file readable on this system"
    return 1
  fi

  [[ -n "$value" ]] || value="n"

  echo $value
}

# Test if specified kconfig options and value matche on current system.
# Arguments:
#   $1: Kconfig value
#   $2: Kconfig options
# Returns:
#   0: specified kconfig options and value match
#   1: invalue kconfig value(s) ro specified kconfig and value(s) does not match
test_kconfig() {
  local value="$1"
  local name="$2"

  if [[ ! "$value" =~ [ymn] ]]; then
    test_print_err "Invalid koption value!"
    return 1
  fi

  # For each expression between '|' separators
  if [[ $(get_kconfig "$name") != "$value" ]]; then
    test_print_err "$name does not match $value!"
    return 1
  else
    test_print_trc "$name matches with expect $value"
  fi
}

# Check if at least one kconfig in the list match the given value.
# Arguments:
#   $1: Kernel config option name
#   $2: Kernel config option value
# Returns:
#   0: match
#   1: not match
test_any_kconfig_match() {
  local names=$1
  local value=$2
  local name=""

  for name in $(echo "$names" | tr '|' ' '); do
    test_kconfig "$value" "$name" && return 0
  done

  test_print_err "None of $names matches value $value"

  return 1
}

# Check if driver is configured as built-in, looking in 'modules.builtin' file
# Arguments:
#   $2: Kernel module name
# Returns:
#   0 if it is configured as built-in
#   1 if it is not.
is_kmodule_builtin() {
  [[ $# -eq 1 ]] \
    || die "is_kmodule_builtin(): 1 and only 1 argument is required!"

  local kmodule=$1
  [[ -n $kmodule ]] || die "is_kmodule_builtin(): kmodule cannot be empty!"

  if grep -q -w "$kmodule" "/lib/modules/$(uname -r)/modules.builtin"; then
    return 0
  else
    local kmod
    kmod=$(echo "$kmodule" | tr '_' '-')
    grep -q -w "$kmod" "/lib/modules/$(uname -r)/modules.builtin"
    return $?
  fi
}

# To get instance number from dev node
# Arguments:
#   dev node like /dev/sda1, /dev/mmcblk0, etc
# Output:
#   instance number like '0', '1' etc
get_devnode_instance_num() {
  local devnode_entry=$1
  local inst_num
  inst_num=$(echo "$devnode_entry" | grep -oE "[[:digit:]]+$" ) || \
            die "Failed to get instance number for dev node entry $devnode_entry"
  echo "$inst_num"
}

# This function calculate file size in bytes based on input parameters
# Arguments:
#   $1: block size of the file, with unit
#   $2: block count of the file(optional, default value is 1)
# Output:
#   file size in byte on success
#   empty string on failure
# Usage:
#   calculate_size_in_bytes 18M
#   caclulate_size_in_bytes 18MB
#   caclulate_size_in_bytes 18M 2
#   caclulate_size_in_bytes 18MB 2
calculate_size_in_bytes() {
  local block_size=$1
  local block_count=${2:-1}
  local block_size_unit=""
  local block_size_num=""
  local file_size=""

  block_size_num=${block_size//[a-zA-Z]/}
  block_size_unit=${block_size//$block_size_num/}

  # Convert unit to bytes
  block_size=$(echo "$block_size_num * ${!block_size_unit}" | bc)
  file_size=$(echo "scale=0; ($block_size * $block_count)/1" | bc)

  echo "$file_size"
}

# Check specified pattern in dmesg
# Arguments:
#   $1: dmesg file
#   $2: pattern to check
# Output:
#   lines that contain the pattern
# Returns:
#   0: pattern found
#   1: pattern not found
dmesg_pattern_check() {
  local dmesg="$1"
  local pattern="$2"
  local lines

  [[ -f "$dmesg" ]] || die "dmesg file doesn't exist"

  lines=$(grep -E "$pattern" "$dmesg")
  echo "$lines"

  [[ -z "$lines" ]] || return 0

  return 1
}

# Get the directory path of the file
# that current code is located
# Output:
#   directory path
fdirname() {
  local index
  local path

  index=$(( ${#BASH_SOURCE[@]} - 1 ))
  path=${BASH_SOURCE[index]}

  dirname "$path"
}

# Write log content to log file
# Arguments:
#   -l: log content
#   -f: log file
#   -n: if specified, append a newline line (empty line)
#   -a: if specified, append the log to log file, otherwise overwrite log file
log2file() {
  local log
  local logfile
  local newline=0
  local append=0
  local OPTIND

  while getopts "l:f:na" opt; do
    case "$opt" in
      l)
        log=$OPTARG
        ;;
      f)
        logfile=$OPTARG
        ;;
      n)
        newline=1
        ;;
      a)
        append=1
        ;;
      \?)
        die "Invalid option: -$OPTARG";;
      :)
        die "Option -$OPTARG requires an argument.";;
    esac
  done

  if [[ "$append" == "1" ]]; then
    echo "$log" | tee -a "$logfile"
  else
    echo "$log" | tee "$logfile"
  fi

  if [[ "$newline" == "1" ]]; then
    echo "" | tee -a "$logfile"
  fi
}

# Run a test. Format the output of the test and write
# output to both *log* file and stdout.
# Arguments:
#   $*: cmdline of test case
runtest() {
  local result
  local start
  local stop
  local duration
  local code
  local logfile

  logfile="$(fdirname)/log"

  log2file -f "$logfile" -l "<<<test start - $*>>>" -a

  start=$(date +%s.%3N)
  set -o pipefail
  eval "$* | tee -a $logfile" &
  wait $!
  code=$?
  set +o pipefail
  stop=$(date +%s.%3N)
  duration=$(printf '%.3f' "$(bc <<< "$stop-$start")")

  case $code in
    0)
      result="[PASS]"
      ;;
    2)
      result="[SKIP]"
      ;;
    32)
      result="[NA]"
      ;;
    *)
      result="[FAIL]"
  esac

  log2file -f "$logfile" \
    -l "<<<test end - result: $result, cmdline: $*, duration: $duration>>>" \
    -a -n
}
