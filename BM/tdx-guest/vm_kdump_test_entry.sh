#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2025 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  6, Jan., 2025 - Hongyu Ning - creation


# @desc This script is general legacy vm guest kdump test entry

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
  -r abs. path to single rpm file: kernel-img, kernel-devel or kernel-headers
  -h HELP info
EOF
}

while getopts :v:m:r:h arg; do
  case $arg in
    v)
      VCPU=$OPTARG
      ;;
    m)
      MEM=$OPTARG
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
# install kdump test kernel rpm in target VM guest OS image
./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d "$DEBUG" -t legacy -e tdx-guest -f tdx -x TD_RPM_INSTALL -c " " -p off -r "$RPM" || \
  die "Failed on kdump test kernel rpm install"
sleep 3
# prepare and trigger kdump in target VM guest OS image
./guest-test/guest.test_launcher.sh -v "$VCPU" -s 1 -m "$MEM" -d "$DEBUG" -t legacy -e tdx-guest -f tdx -x TD_KDUMP_START -c "crashkernel=1G-4G:256M,4G-64G:384M,64G-:512M" -p off || \
  die "Failed on trigger kdump"
sleep 3
# check kdump log generated in target VM guest OS image
./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 16 -d "$DEBUG" -t legacy -e tdx-guest -f tdx -x TD_KDUMP_CHECK -c " " -p off || \
  die "Failed on kdupm log check"