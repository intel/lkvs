#!/bin/bash -Ex
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# @desc This script prepare and run $TESTCASE in for feature idxd intr

###################### Functions ######################
## $FEATURE specific Functions ##

###################### Do Works ######################
## common works example ##
cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

# parse dsa0 pcie bus:device.function
domain=$(readlink /sys/bus/dsa/devices/dsa0 | awk -F '/' '{print $(NF - 1)}' | awk -F ':' '{print $1}')
bus=$(readlink /sys/bus/dsa/devices/dsa0 | awk -F '/' '{print $(NF - 1)}' | awk -F ':' '{print $2}')
dev_func=$(readlink /sys/bus/dsa/devices/dsa0 | awk -F '/' '{print $(NF - 1)}' | awk -F ':' '{print $3}')
dbdf="$domain:$bus:$dev_func"
vendor_id=$(lspci -n -s "${dbdf}" | awk -F ' ' '{print $NF}' | awk -F ':' '{print $1}')
device_id=$(lspci -n -s "${dbdf}" | awk -F ' ' '{print $NF}' | awk -F ':' '{print $2}')
echo "PCI dev info: ${dbdf} ${vendor_id} ${device_id}"

bind_vfio()
{
  modprobe vfio-pci
  echo "${dbdf}" > /sys/bus/pci/drivers/idxd/unbind
  echo "${vendor_id} ${device_id}" > /sys/bus/pci/drivers/vfio-pci/new_id
}

unbind_vfio()
{
  echo "${vendor_id} ${device_id}" > /sys/bus/pci/drivers/vfio-pci/remove_id
  echo "${dbdf}" > /sys/bus/pci/drivers/vfio-pci/unbind
  echo 1 > "/sys/bus/pci/devices/${dbdf}/reset"
  echo "${dbdf}" > /sys/bus/pci/drivers/idxd/bind
  rmmod vfio-pci
}

# helper function
usage() {
  cat <<-EOF
  usage: ./${0##*/}
  -x testcase pass to test_executor, INTR_PT_DSA_DWQ_1 or INTR_PT_DSA_SWQ_1
  -r path of rootfs(guest os) image
  -h HELP info
EOF
}

# get args for QEMU boot configurable parameters
while getopts :x:r:h arg; do
  case $arg in
  x)
    TESTCASE=$OPTARG
  ;;
  r)
    ROOTFS=$OPTARG
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

bind_vfio

python3 make_qemu_config.py -t vfio_pt -c 4 -m 8192 -d "$dbdf" -r "$ROOTFS"

../guest-test/guest.test_launcher.sh -e idxd -f intr -x "$TESTCASE" -p off -i ../idxd/common.json -j ../idxd/qemu.config.json

unbind_vfio
