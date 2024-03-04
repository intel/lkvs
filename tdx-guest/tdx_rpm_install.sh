#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  27, Feb., 2024 - Hongyu Ning - creation


# @desc script do kernel related rpm install

###################### Variables ######################
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"
source common.sh
RPM_FILE=$1

###################### Do Works ######################
# check rpm file type: kernel image, kernel devel or kernel headers
if [[ -f "$RPM_FILE" ]]; then
  test_print_trc "rpm file for test: $RPM_FILE"
else
  die "no rpm file for test"
fi

# for kernel-devel rpm, remove old devel package and install new one
if grep "\-devel\-" "$RPM_FILE" > /dev/null; then
  if rpm -q kernel-devel > /dev/null; then
    old_devel=$(rpm -q kernel-devel | tail -1)
    yum remove -y "$old_devel"
  fi

  if ! rpm -ivh "$RPM_FILE"; then
    die "Failed to install kernel-devel $RPM_FILE"
  else
    test_print_trc "kernel-devel $RPM_FILE installed successfully"
  fi
fi

# for kernel-headers rpm, remove old headers package and install new one
if grep "\-headers\-" "$RPM_FILE" > /dev/null; then
  if rpm -q kernel-headers > /dev/null; then
    old_headers=$(rpm -q kernel-headers)
    yum remove -y "$old_headers"
  fi

  if ! rpm -ivh "$RPM_FILE"; then
    die "Failed to install kernel-headers $RPM_FILE"
  else
    test_print_trc "kernel-headers $RPM_FILE installed successfully"
  fi

  # annobin, gcc, glibc-devel, glibc-headers, libxcrypt-devel be removed along
  # with above yum remove -y "$old_headers"
  # install them back
  dnf install -y annobin
fi

if ! grep "\-devel\-" "$RPM_FILE" > /dev/null && ! grep "\-headers\-" "$RPM_FILE" > /dev/null; then
  if [[ $(rpm -q kernel | wc -l) -gt 2 ]]; then
    old_kernel=$(rpm -q kernel | tail -1)
    yum remove -y "$old_kernel"
  fi

  if ! rpm -ivh --force "$RPM_FILE"; then
    die "Failed to install kernel-img $RPM_FILE"
  else
    test_print_trc "kernel-img $RPM_FILE installed successfully"
  fi
  # set it as default-kernel
  kernel_img=$(ls -rt /boot/vmlinuz-* | tail -1)
  grubby --set-default "$kernel_img"
  grubby --default-kernel
  test_print_trc "default kernel setup complete"
fi