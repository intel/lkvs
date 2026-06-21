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
RASDAEMON_DB=""

# Detect rasdaemon DB path from the running process
detect_rasdaemon_db() {
  [ -n "$RASDAEMON_DB" ] && return

  local pid
  pid=$(pgrep -x rasdaemon)
  if [ -n "$pid" ]; then
    RASDAEMON_DB=$(ls -l /proc/"$pid"/fd 2>/dev/null | grep -m1 'ras-mc_event.db' | awk '{print $NF}')
  fi

  [ -n "$RASDAEMON_DB" ] || die "Cannot detect rasdaemon DB path (is rasdaemon running with --record?)"
}

# --- MCE logging backend abstraction ---

# Detect MCE logging backend: mcelog or rasdaemon
# Prefers rasdaemon (modern). Can be overridden by setting MCE_BACKEND env var.
detect_mce_backend() {
  if [ -n "$MCE_BACKEND" ]; then
    return
  fi
  if command -v rasdaemon &>/dev/null; then
    MCE_BACKEND="rasdaemon"
  elif command -v mcelog &>/dev/null; then
    MCE_BACKEND="mcelog"
  else
    die "No MCE logging backend found (mcelog or rasdaemon)"
  fi
}

# Ensure MCE logging daemon is running and properly configured
mce_config() {
  detect_mce_backend
  case $MCE_BACKEND in
  mcelog)
    local daemon=0
    local logfile=0
    local mcelog_bin
    mcelog_bin=$(command -v mcelog) || die "mcelog not found in PATH"

    if ! pgrep -x mcelog >/dev/null 2>&1; then
      test_print_trc "mcelog service is not running, start the service"
      "$mcelog_bin" --ignorenodev --daemon --logfile=${MCELOG_LOGFILE}
      return 0
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
      "$mcelog_bin" --ignorenodev --daemon --logfile=${MCELOG_LOGFILE}
    fi
    ;;
  rasdaemon)
    if ! systemctl is-active --quiet rasdaemon; then
      systemctl cat rasdaemon &>/dev/null || die "rasdaemon.service not found (run 'make install' in BM/ras/)"
      test_print_trc "rasdaemon is not running, starting service"
      systemctl start rasdaemon || die "Failed to start rasdaemon"
    fi
    detect_rasdaemon_db
    test_print_trc "rasdaemon DB path: ${RASDAEMON_DB}"
    ;;
  esac
}

# Clear MCE log records before test execution
mce_log_clear() {
  case $MCE_BACKEND in
  mcelog)
    cat /dev/null > "${MCELOG_LOGFILE}"
    ;;
  rasdaemon)
    sqlite3 "${RASDAEMON_DB}" "DELETE FROM mce_record;" 2>/dev/null
    ;;
  esac
}

# Check if a pattern exists in MCE log
# Usage: mce_log_check "PATTERN"
mce_log_check() {
  local pattern="$1"
  case $MCE_BACKEND in
  mcelog)
    grep -q "$pattern" "${MCELOG_LOGFILE}"
    ;;
  rasdaemon)
    sqlite3 "${RASDAEMON_DB}" "SELECT * FROM mce_record;" | grep -q "$pattern"
    ;;
  esac
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
