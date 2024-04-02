#!/usr/bin/env bash
###############################################################################
# SPDX-License-Identifier: GPL-2.0-only                                       #
# Copyright (c) 2022 Intel Corporation.                                       #
#                                                                             #
# Common Bash Functions                                                       #
###############################################################################

BIN_OUTPUT=""
BIN_DMESG=""
BIN_RET=""
export LAST_DMESG_TIMESTAMP=""

readonly CPU_SYSFS_FOLDER="/sys/devices/system/cpu"

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

  echo "$value"
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

# Record last timestamp in dmesg and store the value in variable
# LAST_DMESG_TIMESTAMP. The value is refered in function extract_case_dmesg.
last_dmesg_timestamp() {
  LAST_DMESG_TIMESTAMP=$(dmesg | tail -n1 | awk -F "]" '{print $1}' | tr -d "[]")
  test_print_trc "recorded dmesg timestamp: $LAST_DMESG_TIMESTAMP"
}

# Extract dmesg generated since the recorded dmesg timestamp
# Output:
#   if "-f" option is specified, the output will be path of a
#   temporary file in which the dmesg is stored. Otherwise
#   the output will be the dmesg content.
extract_case_dmesg() {
  local tempfile
  local dmesg

  if [[ -z "$LAST_DMESG_TIMESTAMP" ]]; then
    return
  fi

  if [[ "$1" == "-f" ]]; then
    tempfile=$(mktemp -p /tmp XXXXXX)
  fi

  dmesg=$(dmesg | tac | grep -m 1 "$LAST_DMESG_TIMESTAMP" -B 1000000 | tac)
  if [[ -z "$dmesg" ]]; then
    # dmesg of this test case is too long. Ring buffer cannot hold all of them,
    # in this case, we capture all remained dmesg.
    dmesg=$(dmesg)
  fi

  if [[ -n "$tempfile" ]]; then
    grep -v "$LAST_DMESG_TIMESTAMP" <<< "$dmesg"  > "$tempfile"
    echo "$tempfile"
  else
    grep -v "$LAST_DMESG_TIMESTAMP" <<< "$dmesg"
  fi
}

# Set specific CPU online or offline
# $1: 0|1, 0 means online cpu, 1 means offline cpu
# $2: cpu_num, it should be in the range of 0 - max_cpu
set_specific_cpu_on_off()
{
  local on_off=$1
  local cpu_num=$2
  local max_cpu=""
  local cpu_state=""

  # Consider the CPU offline situation for max_cpu
  max_cpu=$(cut -d "-" -f 2 "${CPU_SYSFS_FOLDER}/present")

  # v6.4-rc2: e59e74dc48a309cb8: x86/topology: Remove CPU0 hotplug option
  [[ "$cpu_num" -eq 0 ]] && {
    test_print_trc "v6.4-rc2: e59e74dc48a309cb8: Remove CPU0 hotplug option, skip cpu0 action"
    return 0
  }

  [[ "$cpu_num" -lt 0 || "$cpu_num" -gt "$max_cpu" ]] && {
    block_test "Invalid cpu_num:$cpu_num, it's not in the range: 0 - $max_cpu"
  }

  if [[ "$on_off" == "1" || "$on_off" == "0"  ]]; then
    test_print_trc "echo $on_off > ${CPU_SYSFS_FOLDER}/cpu${cpu_num}/online"
    echo "$on_off" > "$CPU_SYSFS_FOLDER"/cpu"$cpu_num"/online
    ret=$?
    [[ "$ret" -eq 0 ]] || {
      test_print_err "Failed to set cpu$cpu_num to $on_off, ret:$ret not 0"
      return $ret
    }
    cpu_state=$(cat "$CPU_SYSFS_FOLDER"/cpu"$cpu_num"/online)
    if [[ "$cpu_state" != "$on_off" ]]; then
      test_print_err "Failed to set cpu$cpu_num to $on_off, cpu state:$cpu_state"
      return 2
    fi
  else
    test_print_err "Invalid on_off:$on_off, it should be 0 or 1"
    return 2
  fi

  return 0
}

# Set specific CPU online or offline
# $1: 0|1, 0 means online cpu, 1 means offline cpu
# $2: cpus: sample: 11,22-27,114 same format in /sys/devices/system/cpu/offline 
set_cpus_on_off()
{
  local on_off=$1
  local target_cpus=$2
  local cpu=""
  local cpu_start=""
  local cpu_end=""
  local i=""

  if [[ -n "$target_cpus" ]]; then
    for cpu in $(echo "$target_cpus" | tr ',' ' '); do
      if [[ "$cpu" == *"-"* ]]; then
        cpu_start=""
        cpu_end=""
        i=""
        cpu_start=$(echo "$cpu" | cut -d "-" -f 1)
        cpu_end=$(echo "$cpu" | cut -d "-" -f 2)
        for((i=cpu_start;i<=cpu_end;i++)); do
          set_specific_cpu_on_off "$on_off" "$i" || return $?
        done
      else
        set_specific_cpu_on_off "$on_off" "$cpu" || return $?
      fi
    done
  fi

  return 0
}

online_all_cpu()
{
  local off_cpus=""

  test_print_trc "Online all CPUs:"
  off_cpus=$(cat "${CPU_SYSFS_FOLDER}/offline")
  set_cpus_on_off "1" "$off_cpus" || {
    block_test "Online all CPUs with ret:$? not 0!" 
  }
  off_cpus=$(cat "${CPU_SYSFS_FOLDER}/offline")
  if [[ -z "$off_cpus" ]]; then
    test_print_trc "All CPUs are online."
  else
    block_test "There is offline cpu:$off_cpus after online all cpu!"
  fi
}

# Check specified pattern in dmesg
# Arguments:
#   $1: bin name
#   $2: parm to execute the binary
# Output:
#   BIN_DMESG: the dmesg info of binary execution
#   BIN_OUTPUT: the output of the binary execution
#   BIN_RET: return value of the binary execution
bin_output_dmesg() {
  local bin_name=$1
  local parm=$2
  local dmesg_file=""
  local bin_file=""

  BIN_OUTPUT=""
  BIN_RET=""
  BIN_DMESG=""
  last_dmesg_timestamp
  bin_file=$(which "$bin_name" 2>/dev/null)
  [[ -n "$bin_file" ]] || block_test "No $bin_name in lkvs, have you compiled it?"
  test_print_trc "$bin_file $parm"
  BIN_OUTPUT=$("$bin_file" "$parm" 2>/dev/null)
  BIN_RET=$?
  dmesg_file=$(extract_case_dmesg -f)
  BIN_DMESG=$(cat "$dmesg_file")
  export BIN_OUTPUT
  export BIN_RET
  export BIN_DMESG
}
