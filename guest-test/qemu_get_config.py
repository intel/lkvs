#!/usr/bin/python3

# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  7, Sep., 2023 - Hongyu Ning - creation


# @desc This script read qemu config from qemu.config.json
#       and pass to qemu runner for vm launching
# @ params source 1: general params exported from tdx.config
# @ params source 2: test scenario config from tdx.test_params.sh

###################### Lib and Module ######################
import os
from pathlib import Path
import json
from test_params import *
import argparse

###################### Variables ######################

# read from qemu.config.json format for all raw qemu vm config
cwd = Path(os.getcwd())
if cwd.stem == "guest-test":
  try:
    JSON
  except NameError:
    # default qemu.config.json under guest-test
    common_config = Path(f"{os.getcwd()}/common.json").read_text()
    raw_config = Path(f"{os.getcwd()}/qemu.config.json").read_text()
  else:
    # customized qemu.confg.xxx.json located by JSON under guest-test folder
    common_config = Path(os.path.join(f"{os.getcwd()}/", JSON_C)).read_text()
    raw_config = Path(os.path.join(f"{os.getcwd()}/", JSON_Q)).read_text()
else:
  exit(1)

image_config = json.loads(common_config)
qemu_config = json.loads(raw_config)

# pre-config G-list variables' values confirmed by common.json
kernel_img = image_config["kernel_img"]
initrd_img = image_config["initrd_img"]
bios_img = image_config["bios_img"]
qemu_img = image_config["qemu_img"]
guest_img = image_config["guest_img"]
guest_img_format = image_config["guest_img_format"]
boot_pattern = image_config["boot_pattern"]
guest_root_passwd = image_config["guest_root_passwd"]
port = PORT
port_tel = port - 1000

# print above G-list variables to test_launcher.sh to export for global shell scripts access
# NOTICE!! DON'T interrupt before any of the following print to avoid mis-behaviors
print(kernel_img, initrd_img, bios_img, qemu_img, guest_img, guest_img_format, boot_pattern, guest_root_passwd) # shell awk $1-$8
# NOTICE!! DON'T interrupt before any of the above print to avoid mis-behaviors

# end of G-list variables handling

# pre-config O-list variables' values could be override by test_params.py if passed in
# test_params.py is generated by test_launcher.sh for both qemu_runner.py and test_executor.sh
# O-list variables default value from qemu.config.json
vm_type = qemu_config["common"]["vm_type"]
if 'PMU' in dir():
  pmu = PMU
else:
  pmu = qemu_config["common"]["pmu"]

if 'VCPU' in dir():
  cpus = VCPU
else:
  cpus = qemu_config["common"]["cpus"]

if 'SOCKETS' in dir():
  sockets = SOCKETS
else:
  sockets = qemu_config["common"]["sockets"]

if 'MEM' in dir():
  mem = MEM
else:
  mem = qemu_config["common"]["mem"]

if 'CMDLINE' in dir():
  cmdline = CMDLINE
else:
  cmdline = qemu_config["common"]["cmdline"]

if 'DEBUG' in dir():
  debug = DEBUG
else:
  debug = qemu_config["common"]["debug"]

if 'TESTCASE' in dir():
  testcase = TESTCASE
else:
  print("No TESTCASE info found, can't run any test!")
  exit(1)

# O-list variables override value handling with args passed options, not used in framework, keep it for customization
params_o_list = argparse.ArgumentParser()

params_o_list.add_argument('--vmtype', type=str, help='vm_type to test, valid value [legacy/tdx/tdxio]')
params_o_list.add_argument('--pmu', type=str, help='vm pmu enable, valid value [on/off]')
params_o_list.add_argument('--archpebs', type=str, help='vm arch-pebs enable, valid value [on/off]')
params_o_list.add_argument('--cachetopo', type=str, help='vm x-l2-cache-topo set, valid value [core/cluster]')
params_o_list.add_argument('--cpus', type=int, help='vm total virtual cpu number, pay attention to equation of cpus & sockets/dies/clusters/cores/threads')
params_o_list.add_argument('--sockets', type=int, help='vm total sockets number')
params_o_list.add_argument('--dies', type=int, help='vm total dies number')
params_o_list.add_argument('--clusters', type=int, help='vm total clusters number')
params_o_list.add_argument('--cores', type=int, help='vm total cores number per socket')
params_o_list.add_argument('--threads', type=int, help='vm total threads number per core')
params_o_list.add_argument('--mem', type=int, help='vm total memory size in GB')
params_o_list.add_argument('--cmdline', type=str, help='vm extra command line options')
params_o_list.add_argument('--debug', type=str, help='tdx vm debug enable, valid value [on/off]')
params_o_list.add_argument('--testcase', type=str, help='testcase to run in vm')

args = params_o_list.parse_args()

# NOTICE!! O-list veriables' value will be override if passed through above args option
if args.vmtype is not None:
  vm_type = args.vmtype
if args.pmu is not None:
  pmu = args.pmu
if args.cpus is not None:
  cpus = args.cpus
if args.sockets is not None:
  sockets = args.sockets
if args.mem is not None:
  mem = args.mem
if args.cmdline is not None:
  cmdline = args.cmdline
if args.debug is not None:
  debug = args.debug
if args.testcase is not None:
  testcase = args.testcase

# end of O-list variables handling

# update all cfg_var_x with G-list variables (default values from qemu.config.json) and O-list variables (could be override by passed in value)
# NOTICE!! in case of any cfg_var_x update in qemu.config.json, need to revise following code accordingly
qemu_config["vm"]["cfg_var_1"] = qemu_config["vm"]["cfg_var_1"].replace("$VM_TYPE", vm_type).replace("$PORT", str(port))
qemu_config["vm"]["cfg_var_2"] = qemu_config["vm"]["cfg_var_2"].replace("$PMU", pmu)
qemu_config["vm"]["cfg_var_3"] = qemu_config["vm"]["cfg_var_3"].replace("$VCPU", str(cpus)).replace("$SOCKETS", str(sockets))
qemu_config["vm"]["cfg_var_4"] = qemu_config["vm"]["cfg_var_4"].replace("$MEM", str(mem))
# bypass -kernel config option in case it's not provided
if os.path.isfile(kernel_img):
  qemu_config["vm"]["cfg_var_5"] = qemu_config["vm"]["cfg_var_5"].replace("$KERNEL_IMG", kernel_img)
else:
  qemu_config["vm"]["cfg_var_5"] = ""
# bypass -initrd config option in case it's not provided
if os.path.isfile(initrd_img):
  qemu_config["vm"]["cfg_var_6"] = qemu_config["vm"]["cfg_var_6"].replace("$INITRD_IMG", initrd_img)
else:
  qemu_config["vm"]["cfg_var_6"] = ""

qemu_config["vm"]["cfg_var_7"] = qemu_config["vm"]["cfg_var_7"].replace("$PORT", str(port))
qemu_config["vm"]["cfg_var_8"] = qemu_config["vm"]["cfg_var_8"].replace("$GUEST_IMG", guest_img).replace("$IMG_FORMAT", guest_img_format)
# bypass -append config option in case -kernel option not used
if os.path.isfile(kernel_img):
  qemu_config["vm"]["cfg_var_9"] = qemu_config["vm"]["cfg_var_9"].replace("$CMDLINE", cmdline)
else:
  qemu_config["vm"]["cfg_var_9"] = ""
# bypass -bios config option in case it's not provided, default seabios to use
if os.path.isfile(bios_img):
  qemu_config["vm"]["cfg_var_10"] = qemu_config["vm"]["cfg_var_10"].replace("$BIOS_IMG", bios_img)
else:
  qemu_config["vm"]["cfg_var_10"] = ""

qemu_config["vm"]["cfg_var_11"] = qemu_config["vm"]["cfg_var_11"].replace("$PORT_TEL", str(port_tel))

qemu_config["tdx"]["cfg_var_1"] = qemu_config["tdx"]["cfg_var_1"].replace("$DEBUG", debug)
qemu_config["tdx"]["cfg_var_2"] = qemu_config["tdx"]["cfg_var_2"].replace("$MEM", str(mem))

# end of all cfg_var_x update handling

###################### Functions ######################
def get_sub_keys(d, key):
  """
  Recursively get all 2nd-level keys in a dictionary.
  """
  if isinstance(d, dict):
    for k, v in d.items():
      if isinstance(v, dict):
        if k == key:
          for k2 in v.keys():
            yield k2

def print_sub_keys(l, key):
  """
  Recursively get each 2nd-level key.
  """
  print("Key %s has sub-keys:" %(key))
  for i in l:
    print(i)

def get_sub_cfgs(l, key, result=""):
  """
  Recursively collect all 2nd-level key cfg string.
  """
  for i in l:
    result += qemu_config[key][i]
  return result

###################### Do Works ######################
#common_keys = list(get_sub_keys(qemu_config, "common"))
vm_keys = list(get_sub_keys(qemu_config, "vm"))
tdx_keys = list(get_sub_keys(qemu_config, "tdx"))
tdxio_keys = list(get_sub_keys(qemu_config, "tdxio"))

#print_sub_keys(vm_keys, "vm")
if vm_type == "legacy":
  vm_cfg = get_sub_cfgs(vm_keys, "vm")
  print("HERE're all the vm configs to launch legacy vm:")
  print("#### qemu config option, part 1 ####")
  print(vm_cfg)

#print_sub_keys(tdx_keys, "tdx")
if vm_type == "tdx":
  vm_cfg = get_sub_cfgs(vm_keys, "vm")
  tdx_cfg = get_sub_cfgs(tdx_keys, "tdx")
  print("HERE're all the tdx configs to launch tdx vm:")
  print("#### qemu config option, part 1 ####")
  print(vm_cfg)
  print("#### qemu config option, part 2 ####")
  print(tdx_cfg)

#print_sub_keys(tdxio_keys, "tdxio")
if vm_type == "tdxio":
  vm_cfg = get_sub_cfgs(vm_keys, "vm")
  tdx_cfg = get_sub_cfgs(tdx_keys, "tdx")
  tdxio_cfg = get_sub_cfgs(tdxio_keys, "tdxio")
  print("HERE're all the tdx configs to launch tdxio vm:")
  print("#### qemu config option, part 1 ####")
  print(vm_cfg)
  print("#### qemu config option, part 2 ####")
  print(tdx_cfg)
  print("#### qemu config option, part 3 ####")
  print(tdxio_cfg)