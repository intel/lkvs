#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  15, Nov., 2023 - Hongyu Ning - creation


# @desc This script do basic internet BW test in TDX Guest VM
#       test tool based on speedtest-cli

###################### Variables ######################
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"
source common.sh
ID=0
DOWNLOAD=0
DOWNLOAD_DATA=0
UPLOAD=0
UPLOAD_DATA=0
RETRY_ID=3
RETRY_DL=3
RETRY_UL=3

###################### Functions ######################
float_num_compare() {
  if awk -v n1="$1" -v n2="$2" 'BEGIN {if (n1>n2) exit 0; exit 1}'
  then
    return 0
  else
    return 1
  fi
}

###################### Do Works ######################
# prepare speedtest-cli
if [ ! "$(which speedtest-cli)" ]; then
  dnf install -y speedtest-cli > /dev/null
  apt install -y speedtest-cli > /dev/null
else
  test_print_trc "speedtest-cli prerequisites is ready for use"
  test_print_trc "TDVM internet BW test is starting now..."
fi

# get nearest server ID for test
while [[ "$RETRY_ID" -gt 0 ]]; do
  ID=$(speedtest-cli --list | awk -F')' 'NR==2 {print $1; exit}')
  if [[ "$ID" =~ ^[0-9]+$ ]]; then
    if [ "$ID" -gt 0 ]; then
      test_print_trc "BW test server ID: $ID @RETRY: $RETRY_ID"
      break
    fi
  fi
  RETRY_ID=$((RETRY_ID-1))
  if [[ "$RETRY_ID" -eq 0 ]]; then
    test_print_err "BW test get server failed"
    exit 1
  fi
done

# get download bandwidth
while [[ "$RETRY_DL" -gt 0 ]]; do
  test_print_trc "BW download test start @RETRY: $RETRY_DL"
  DOWNLOAD=$(speedtest-cli --single --bytes --simple --server "$ID" | awk -F':' 'NR==2 {print $2; exit}')
  DOWNLOAD_DATA=$(echo "$DOWNLOAD" | awk '{print $1; exit}')
  if float_num_compare "$DOWNLOAD_DATA" "1"; then
    test_print_trc "BW test PASS with download result: $DOWNLOAD"
    break
  fi
  RETRY_DL=$((RETRY_DL-1))
  if [[ "$RETRY_DL" -eq 0 ]]; then
    test_print_trc "BW test FAIL with download result: $DOWNLOAD"
    exit 1
  fi
done

# get upload bandwidth
while [[ "$RETRY_UL" -gt 0 ]]; do
  test_print_trc "BW upaload test start @RETRY: $RETRY_UL"
  UPLOAD=$(speedtest-cli --single --bytes --simple --server "$ID" | awk -F':' 'NR==3 {print $2; exit}')
  UPLOAD_DATA=$(echo "$UPLOAD" | awk '{print $1; exit}')
  if float_num_compare "$UPLOAD_DATA" "0.1"; then
    test_print_trc "BW test PASS with upload result: $UPLOAD"
    break
  fi
  RETRY_UL=$((RETRY_UL-1))
  if [[ "$RETRY_UL" -eq 0 ]]; then
    test_print_trc "BW test FAIL with upload result: $UPLOAD"
    exit 1
  fi
done