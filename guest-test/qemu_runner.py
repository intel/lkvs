#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  12, Sep., 2023 - Hongyu Ning - creation


# @desc This script get variables and applicable qemu_config
#       from qemu_get_config.py and launch VM through QEMU
# @ params source 1: global variables and qemu_config from qemu_get_config.py
# @ params source 2: override variables from test_params.py

###################### Lib and Module ######################
import subprocess as sp
from qemu_get_config import *
from test_params import *
from signal import signal, SIGPIPE, SIG_DFL

###################### Variables ######################
# all variables imported from qemu_get_config and test_params

###################### Functions ######################
# all work done in qemu_get_config.py

###################### Do Works ######################
# igore SIGPIPE in case of broken pipe errno 32 case
signal(SIGPIPE, SIG_DFL)
# launch legacy common vm based on vm_type config
if vm_type == "legacy":
  command = '{} {}'.format(qemu_img, vm_cfg)
  sp.run(command, shell=True)

# launch tdx vm based on vm_type config
if vm_type == "tdx":
  command = '{} {} {}'.format(qemu_img, vm_cfg, tdx_cfg)
  sp.run(command, shell=True)

# launch tdxio vm based on vm_type config
if vm_type == "tdxio":
  command = '{} {} {} {}'.format(qemu_img, vm_cfg, tdx_cfg, tdxio_cfg)
  sp.run(command, shell=True)
