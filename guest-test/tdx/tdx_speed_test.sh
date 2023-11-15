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

###################### Functions ######################
float_num_compare() {
  if awk -v n1="$1" -v n2="1" 'BEGIN {if (n1>n2) exit 0; exit 1}'
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
ID=$(speedtest-cli --list | awk -F')' 'NR==2 {print $1; exit}')
if [ "$ID" -gt 0 ]; then
  test_print_trc "BW test server ID: $ID"
else
  test_print_err "BW test get server failed"
  exit 1
fi

# get download bandwidth
DOWNLOAD=$(speedtest-cli --single --bytes --simple --server "$ID" | awk -F':' 'NR==2 {print $2; exit}')
DOWNLOAD_DATA=$(echo "$DOWNLOAD" | awk '{print $1; exit}')
if float_num_compare "$DOWNLOAD_DATA"; then
  test_print_trc "BW test download result: $DOWNLOAD"
else
  test_print_trc "BW test download result: $DOWNLOAD"
  test_print_err "BW test download test failed"
  exit 1
fi

# get upload bandwidth
UPLOAD=$(speedtest-cli --single --bytes --simple --server "$ID" | awk -F':' 'NR==3 {print $2; exit}')
UPLOAD_DATA=$(echo "$UPLOAD" | awk '{print $1; exit}')
if float_num_compare "$UPLOAD_DATA"; then
  test_print_trc "BW test upload result: $UPLOAD"
else
  test_print_trc "BW test upload result: $UPLOAD"
  test_print_err "BW test upload test failed"
  exit 1
fi