#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2025 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  6, Jan., 2025 - Hongyu Ning - creation


# @desc This script is general vm guest kexec test entry

###################### Variables ######################
source common.sh
DEBUG=on

###################### Functions ######################
# helper function
usage() {
  cat <<-EOF
  usage: ./${0##*/}
  -v number of vcpus
  -m memory size in GB
  -k pos-integer value for normal kexec test cycle count
  -r abs. path to single rpm file: kernel-img, kernel-devel or kernel-headers
  -h HELP info
EOF
}

while getopts :v:m:k:r:h arg; do
  case $arg in
    v)
      VCPU=$OPTARG
      ;;
    m)
      MEM=$OPTARG
      ;;
    k)
      KEXEC_CNT=$OPTARG
      ;;
    r)
      RPM=$OPTARG
      ;;
    h)
      usage && exit 0
      ;;
    *)
      test_print_err "Must supply an argument to -$OPTARG."
      exit 1
      ;;
  esac
done

###################### Do Works ######################
# install kexec test kernel rpm in target VM guest OS image
./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d "$DEBUG" -t legacy -e tdx-guest -f tdx \
  -x TD_RPM_INSTALL -c " " -p off -r "$RPM" || \
  die "Failed on kexec test kernel rpm install"
sleep 3
# prepare and trigger kexec in target VM guest OS image
./guest-test/guest.test_launcher.sh -v "$VCPU" -s 1 -m "$MEM" -d "$DEBUG" -t legacy -e tdx-guest -f tdx \
  -x VM_KEXEC_"$VCPU"C_"$MEM"G_CYCLE_"$KEXEC_CNT" -c "console= accept_memory=lazy" -p off -k "$KEXEC_CNT" || \
  die "Failed on kexec test"