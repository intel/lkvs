#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation
# Author: Yi Lai <yi1.lai@intel.com>
# @Desc  Common functions used in ras test suite

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

MCELOG_LOGFILE=/var/log/mcelog
MCA_BANK_NUM=$((0x$(rdmsr 0x179) & 0xFF)) # 0x179 is IA32_MCG_CAP
IA32_MCi_CTL2=$(rdmsr 0x280) # 0x280 is IA32_MCi_CTL2

# check mcelog service is properly configured and running
mcelog_config() {
  local daemon=0
  local logfile=0

  pgrep -x mcelog >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    test_print_trc "mcelog service is not running, start the service"
    /usr/sbin/mcelog --ignorenodev --daemon --logfile=${MCELOG_LOGFILE}
    exit 0
  fi
  for i in $(pgrep -a -x mcelog); do
    if [[ $i == *"--daemon"* ]]; then
      daemon=1
    elif [[ $i == *"--logfile=${MCELOG_LOGFILE}"* ]]; then
      logfile=1
    fi
  done
  if [ "$daemon" -eq 0 ] || [ "$logfile" -eq 0 ]; then
    test_print_trc "mcelog service is not properly configured, reload the service."
    kill -9 $(pgrep -x mcelog)
    /usr/sbin/mcelog --ignorenodev --daemon --logfile=${MCELOG_LOGFILE}
  fi
}

# disable MCE CMCI
disable_cmci() {
  for (( bank=0; bank<MCA_BANK_NUM; bank++ )); do
    msr_address=$((0x280 + bank))
		current_value=$(rdmsr -p 0 $msr_address)
    current_value_dec=$((0x$current_value))
    new_value_dec=$((current_value_dec & ~(1 << 30)))
    wrmsr -a $msr_address $new_value_dec # write to all processors
  done
}

# enable MCE CMCI
enable_cmci() {
  for ((bank=0; bank<MCA_BANK_NUM; bank++)); do
    msr_address=$((0x280 + bank))
    wrmsr -a $msr_address "0x${IA32_MCi_CTL2}"
  done
}
