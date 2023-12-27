#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  24, Aug., 2023 - Hongyu Ning - creation


# @desc This script is top level of Guest VM test
# @ PART 0: prepare test prerequisites
# @ PART 1: get params from qemu_get_config.py and script args, generate test_params.py
# @ PART 2: launch qemu_runner along with test_executor/err_handlers
# @ PART 3: err_handlers
# @ PART 4: timeout control in case of tdvm boot up failure/test failure
# @ PART 5: clean up at test execution ends

###################### Variables ######################
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"

# code coverage test mode on/off, default off
# can be override by -g parameter
# in case of on, keep VM alive for gcov data collection
GCOV="off"
# timeout control in case of TD VM booting hang
SECONDS=0
TIMEOUT=900
# EXEC_FLAG=0 shows test_executor being called
EXEC_FLAG=1

# ERR_STR and ERR_FLAG definition
# for any unexpected error/warning/call trace handling
# unchecked MSR access error
ERR_STR1="*unchecked MSR access error*"
ERR_FLAG1=0
# unexpected #VE error
ERR_STR2="*Unexpected #VE*"
ERR_FLAG2=0
# general BUG info
ERR_STR3="*BUG:*"
ERR_FLAG3=0
# general WARNING info
ERR_STR4="*WARNING:*"
ERR_FLAG4=0
# general Call Trace info
ERR_STR5="*Call Trace:*"
ERR_FLAG5=0
#

###################### Functions ######################
# helper function
usage() {
  cat <<-EOF
NOTE!! args passed here will override params in json config file
  usage: ./${0##*/}
  -v number of vcpus
  -s number of sockets
  -m memory size in GB
  -d debug on/off (resive to true/false in new qemu)
  -t vm_type legacy/tdx/tdxio
  -f feature (subfolder) to test
  -x testcase pass to test_executor
  -c guest kernel extra commandline
  -p guest pmu off/on
  -g [optional, default off] code coverage test mode off/on
  -i [optional] path under guest-test to standalone common.json file
  -j [optional] path under guest-test to standalone qemu.config.json file
  -h HELP info
EOF
}

guest_kernel_check() {
  sshpass -e ssh -p "$PORT" -o StrictHostKeyChecking=no root@localhost << EOF
    echo "$VM_TYPE VM guest kernel under test:"
    uname -r
EOF
}

guest_kernel_shutdown() {
  sshpass -e ssh -p "$PORT" -o StrictHostKeyChecking=no root@localhost << EOF
    echo "$VM_TYPE VM guest kernel shutdown now"
    if [[ "$VM_TYPE" = "legacy" ]]; then
      shutdown now
    else
      systemctl reboot --reboot-argument=now
    fi
EOF
}

###################### Do Works ######################
cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

## PART 0: prepare test prerequisites ##
if [ ! "$(which sshpass)" ]; then
  dnf install -y sshpass > /dev/null
  apt install -y sshpass > /dev/null
else
  test_print_trc "sshpass prerequisites is ready for use"
  test_print_trc "VM test is starting now..."
fi

## PART 1: get params from qemu.cfg.json and script args ##
# generate a unified random port number in one test cycle
PORT=$(shuf -i 10010-10900 -n 1)
# generate test_params.py based on script args
echo PORT="$PORT" > "$SCRIPT_DIR"/test_params.py

# 1.1 get test scenario config related params from script args
# append following params in above fresh new test_params.py
# used across test_launcher.sh, qemu_runner.py, test_executor.sh

# get args for QEMU boot configurable parameters
while getopts :v:s:m:d:t:f:x:c:p:g:i:j:h arg; do
  case $arg in
    v)
      VCPU=$OPTARG
      echo VCPU="$VCPU" >> "$SCRIPT_DIR"/test_params.py
      ;;
    s)
      SOCKETS=$OPTARG
      echo SOCKETS="$SOCKETS" >> "$SCRIPT_DIR"/test_params.py
      ;;
    m)
      MEM=$OPTARG
      echo MEM="$MEM" >> "$SCRIPT_DIR"/test_params.py
      ;;
    d)
      DEBUG=$OPTARG
      echo DEBUG="\"$DEBUG\"" >> "$SCRIPT_DIR"/test_params.py
      ;;
    t)
      VM_TYPE=$OPTARG
      echo VM_TYPE="\"$VM_TYPE\"" >> "$SCRIPT_DIR"/test_params.py
      ;;
    f)
      FEATURE=$OPTARG
      echo FEATURE="\"$FEATURE\"" >> "$SCRIPT_DIR"/test_params.py
      ;;
    x)
      TESTCASE=$OPTARG
      echo TESTCASE="\"$TESTCASE\"" >> "$SCRIPT_DIR"/test_params.py
      ;;
    c)
      CMDLINE=$OPTARG
      echo CMDLINE="\"$CMDLINE\"" >> "$SCRIPT_DIR"/test_params.py
      ;;
    p)
      PMU=$OPTARG
      echo PMU="\"$PMU\"" >> "$SCRIPT_DIR"/test_params.py
      ;;
    g)
      GCOV=$OPTARG
      echo GCOV="\"$GCOV\"" >> "$SCRIPT_DIR"/test_params.py
      ;;
    i)
      JSON_C=$OPTARG
      echo JSON_C="\"$JSON_C\"" >> "$SCRIPT_DIR"/test_params.py
      ;;
    j)
      JSON_Q=$OPTARG
      echo JSON_Q="\"$JSON_Q\"" >> "$SCRIPT_DIR"/test_params.py
      ;;
    h)
      usage && exit 0
      ;;
    :)
      test_print_err "Must supply an argument to -$OPTARG."
      usage && exit 1
      ;;
    \?)
      test_print_err "Invalid Option -$OPTARG ignored."
      usage && exit 1
      ;;
  esac
done


# 1.2 get general parameter config from qemu.cfg.json
# all general parameter exported for qemu_runner and test_executor
# $KERNEL_IMG $INITRD_IMG $BIOS_IMG $QEMU_IMG $GUEST_IMG
# $GUEST_IMG_FORMAT $BOOT_PATTERN $SSHPASS $PORT

#global_variable
output=$(python3 "$SCRIPT_DIR"/qemu_get_config.py)
KERNEL_IMG=$(echo "$output" | awk '{print $1; exit}')
INITRD_IMG=$(echo "$output" | awk '{print $2; exit}')
BIOS_IMG=$(echo "$output" | awk '{print $3; exit}')
QEMU_IMG=$(echo "$output" | awk '{print $4; exit}')
GUEST_IMG=$(echo "$output" | awk '{print $5; exit}')
GUEST_IMG_FORMAT=$(echo "$output" | awk '{print $6; exit}')
BOOT_PATTERN=$(echo "$output" | awk '{print $7; exit}')
SSHPASS=$(echo "$output" | awk '{print $8; exit}')

test_print_trc "KERNEL_IMG $KERNEL_IMG"
test_print_trc "INITRD_IMG $INITRD_IMG"
test_print_trc "BIOS_IMG $BIOS_IMG"
test_print_trc "QEMU_IMG $QEMU_IMG"
test_print_trc "GUEST_IMG $GUEST_IMG"
test_print_trc "GUEST_IMG_FORMAT $GUEST_IMG_FORMAT"
test_print_trc "BOOT_PATTERN $BOOT_PATTERN"
test_print_trc "SSHPASS $SSHPASS"
test_print_trc "PORT $PORT"

export KERNEL_IMG
export INITRD_IMG
export BIOS_IMG
export QEMU_IMG
export GUEST_IMG
export GUEST_IMG_FORMAT
export BOOT_PATTERN
export SSHPASS
export PORT
export GCOV

## PART 2: launch qemu_runner ##
# launch qemu_runner along with err_handlers/test_executor
# 2.1 boot TD VM via qemu_runner with params
# exported from qemu_get_config.py & sourced from test_params.py
# 2.2 check TD VM boot $BOOT_PATTERN, then run test by test_executor
# 2.3 check TD VM boot $ERR_STRs, then run corresponding err_handler ($ERR_FLAGs)
# 2.4 break while loop if reach $TIMEOUT seconds (in case of TD VM boot hang)

cd "$SCRIPT_DIR" || die "fail to switch to $SCRIPT_DIR"
rm -rf /root/.ssh/known_hosts
while read -r line; do
  echo "[${VM_TYPE}_vm]: $line"
  # within $TIMEOUT but bypass the very first 2 seconds to avoid unexpected $BOOT_PATTERN match (from parameter handling logic)
  if [[ $SECONDS -lt $TIMEOUT ]] && [[ $SECONDS -ge 2 ]]; then
    if [[ "$line" == @($BOOT_PATTERN) ]] && [[ $EXEC_FLAG -ne 0 ]]; then
      test_print_trc "VM_TYPE: $VM_TYPE, VCPU: $VCPU, SOCKETS: $SOCKETS, MEM: $MEM, DEBUG: $DEBUG, PMU: $PMU, CMDLINE: $CMDLINE, \
      FEATURE: $FEATURE, TESTCASE: $TESTCASE, SECONDS: $SECONDS"
      EXEC_FLAG=0
      if ! ./guest.test_executor.sh; then EXEC_FLAG=1 && break; fi # break while read loop in case of guest.test_executor.sh test failure
    # err_handlers string matching
    elif [[ "$line" == @($ERR_STR1) ]]; then
      test_print_err "There is $ERR_STR1, test is not fully PASS"
      ERR_FLAG1=1
    elif [[ "$line" == @($ERR_STR2) ]]; then
      test_print_err "There is $ERR_STR2, test failed"
      ERR_FLAG2=1
    elif [[ "$line" == @($ERR_STR3) ]] && [[ $line != *"DEBUG"* ]]; then
      test_print_wrg "There is $ERR_STR3, please check"
      ERR_FLAG3=1
    elif [[ "$line" == @($ERR_STR4) ]]; then
      test_print_wrg "There is $ERR_STR4, please check"
      ERR_FLAG4=1
    elif [[ "$line" == @($ERR_STR5) ]]; then
      test_print_wrg "There is $ERR_STR5, please check"
      ERR_FLAG5=1
    fi
    # end of err_handlers string matching
  elif [[ $SECONDS -ge $TIMEOUT ]]; then # break while read loop in case of TD VM boot timeout (no $BOOT_PATTERN found)
    break
  fi
done < <(
  if [ "$GCOV" == "off" ]; then
    # keep timeout process run foreground for direct script execution correctness
    # handle timeout effect case SIGTERM impact on terminal no type-in prompt issue
    timeout --foreground "$TIMEOUT" ./guest.qemu_runner.sh || reset
  else
    test_print_trc "${VM_TYPE}vm_$PORT keep alive for gcov data collection" && ./guest.qemu_runner.sh
  fi
)

## PART 3: err_handlers error management
# unexpected error/bug/warning/call trace handling
if [ $ERR_FLAG3 -ne 0 ]; then
  test_print_wrg "$VM_TYPE VM test hit $ERR_STR3, please check |WARNING| in test log for more info"
fi

if [ $ERR_FLAG4 -ne 0 ]; then
  test_print_wrg "$VM_TYPE VM test hit $ERR_STR4, please check |WARNING| in test log for more info"
fi

if [ $ERR_FLAG5 -ne 0 ]; then
  test_print_wrg "$VM_TYPE VM test hit $ERR_STR5, please check |WARNING| in test log for more info"
fi

# handle error/bug in the end to avoid missing above warning/call trace info
if [ $ERR_FLAG1 -ne 0 ]; then
  die "$VM_TYPE VM test failed with $ERR_STR1, please check |ERROR| in test log for more info"
fi

if [ $ERR_FLAG2 -ne 0 ]; then
  die "$VM_TYPE VM test failed with $ERR_STR2, please check |ERROR| in test log for more info"
fi
# end of err_handlers error management

## PART 4: timeout control in case of tdvm boot up failure/test failure ##
# sleep 3 seconds before starting VM life-cycles management logic
sleep 3

# VM life-cycles management step 1
# check if TDVM is still up via guest_kernel_check function, non-zero return value indicates TDVM is not accessible
# TDVM not acccessible cases:
# a. TDVM is already closed after test
# b. TDVM boot up stuck at some point
# VM life-cycles management step 2
# non-zero return value of TD VM not accessible handling
# time count between 3 and $TIMEOUT is expected case a
# - handling: nothing to do, since TDVM is closed after test
# time count great or equal than $TIMEOUT is case b
# - handling: kill the tdvm_$PORT process since it's stuck
# time count less or qual than 3 is case b
# - handling: nothing to do, die for TDVM boot early failure, likely qemu config issue
if ! guest_kernel_check; then
  if [ "$SECONDS" -gt 3 ] && [ "$SECONDS" -lt "$TIMEOUT" ] && [ "$EXEC_FLAG" -eq 0 ]; then
    test_print_trc "$VM_TYPE VM test complete..."
  elif [ "$SECONDS" -ge "$TIMEOUT" ] && [ "$GCOV" == "on" ]; then
    pkill "${VM_TYPE}vm_$PORT"
    die "TEST TIMEOUT!!!!!!!!!!!!"
  elif [ "$GCOV" == "off" ] && [ "$EXEC_FLAG" -eq 1 ]; then
    pkill "${VM_TYPE}vm_$PORT"
    die "$VM_TYPE VM test seems fail at beginning, please check test log"
  fi
# guest_kernel_check function zero return value shows TDVM is still accessible handling
# handling: no matter why it's still accessible, close it by guest_kernel_shutdown function
elif [ "$GCOV" == "off" ]; then
  if guest_kernel_shutdown; then
    test_print_trc "$VM_TYPE VM is still up"
    test_print_trc "time: $SECONDS"
    test_print_trc "SSHPASS: $SSHPASS"
    test_print_trc "PORT: $PORT"
    test_print_trc "$VM_TYPE VM closed"
    # must die here since TDVM should be closed and not accessible if test complete all correctly
    # else it's due to test die before reaching final close point guest_test_close function
    die "$VM_TYPE VM test fail, please check test log"
  fi
else # [ $GCOV == "on" ] || [ guest_kernel_check return 0 ]
  test_print_trc "${VM_TYPE}vm_$PORT keep alive for gcov data collection"
  test_print_trc "'ssh -p $PORT root@localhost' with PASSWORD '$SSHPASS' to login and get data"
fi

## PART 5: clean up at test execution ends, kill tdvm_$PORT process if it's still up ##
# VM life-cycles management step 3
# Kill the tdvm_$PORT process in case above ssh command close not accessible due to network or other issues
if [ "$GCOV" == "off" ]; then
  if [ ! "$(pgrep "${VM_TYPE}vm_$PORT")" ] && [ $EXEC_FLAG -eq 0 ]; then
    test_print_trc "$VM_TYPE VM test complete all correctly..."
  else # [ ${VM_TYPE}vm_$PORT process is still up ] || [ $EXEC_FLAG -eq 1 ]
    pkill "${VM_TYPE}vm_$PORT"
    test_print_wrg "${VM_TYPE}vm_$PORT process is still up, kill it since test expected to end here"
    die "$VM_TYPE VM test fail, please check test log"
  fi
else # [ $GCOV == "on" ]
  if [ $EXEC_FLAG -eq 0 ]; then
    test_print_trc "$VM_TYPE VM test complete all correctly..."
    test_print_trc "Please shutdown $VM_TYPE VM after gcov collect completed"
  else
    test_print_err "$VM_TYPE VM test fail, please check test log"
    test_print_trc "Please shutdown $VM_TYPE VM after gcov collect or debug completed"
    die "$VM_TYPE VM test fail, please check test log"
  fi
fi