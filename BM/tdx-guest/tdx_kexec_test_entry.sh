#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  15, Aug., 2024 - Hongyu Ning - creation


# @desc This script is general tdx guest kexec test entry

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
  -o memory drained option yes or no
  -k pos-integer value for normal kexec test cycle count
  -r abs. path to single rpm file: kernel-img, kernel-devel or kernel-headers
  -h HELP info
EOF
}

while getopts :v:m:o:k:r:h arg; do
  case $arg in
    v)
      VCPU=$OPTARG
      ;;
    m)
      MEM=$OPTARG
      ;;
    o)
      MEM_DRAIN=$OPTARG
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
# install kexec test kernel rpm in target TDX guest OS image
./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 16 -d "$DEBUG" -t tdx -e tdx-guest -f tdx \
  -x TD_RPM_INSTALL -c "accept_memory=lazy" -p off -r "$RPM" || \
  die "Failed on kexec test kernel rpm install"
sleep 3
# prepare and trigger kexec in target TDX guest OS image
if [[ "$MEM_DRAIN" == "yes" ]]; then
  ./guest-test/guest.test_launcher.sh -v "$VCPU" -s 1 -m "$MEM" -d "$DEBUG" -t tdx -e tdx-guest -f tdx \
    -x TD_KEXEC_MEM_DRAIN_"$VCPU"C_"$MEM"G_CYCLE_"$KEXEC_CNT" -c "accept_memory=lazy crashkernel=1G-4G:256M,4G-64G:384M,64G-:512M" -p off -o yes -k "$KEXEC_CNT" || \
    die "Failed on kexec test"
elif [[ "$MEM_DRAIN" == "no" ]]; then
  ./guest-test/guest.test_launcher.sh -v "$VCPU" -s 1 -m "$MEM" -d "$DEBUG" -t tdx -e tdx-guest -f tdx \
    -x TD_KEXEC_NO_MEM_DRAIN_"$VCPU"C_"$MEM"G_CYCLE_"$KEXEC_CNT" -c "accept_memory=lazy" -p off -o no -k "$KEXEC_CNT" || \
    die "Failed on kexec test"
else
  die "Invalid memory drained option"
fi
