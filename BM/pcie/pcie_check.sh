#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
#
# History:  28, Jun., 2024 - Hongyu Ning - creation


# @desc This script do basic pcie capability check with lspci and 
# BM/tools/pcie/pcie_check.c
# pcie Gen4, Gen5 and Gen6 covered
# ref spec: PCI-SIG PCI Express® Base Specification Revision 6.0.1 on 29 August 2022

###################### Variables ######################
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"

###################### Functions ######################
# function to check if PCI bridge exists
pci_bridge_device_check() {
  local pci_bridge_device
  local dev
  pci_bridge_device=$(lspci -nnv | grep -wE "PCI bridge" | grep -iv "pci-to-pci" | awk '{print $1}')
  pci_bridge_device=$(echo -e $pci_bridge_device)
  IFS=" " read -ra pci_bridge_array <<< "$pci_bridge_device"
  for dev in "${pci_bridge_array[@]}"
    do
      if [[ -z "$dev" ]]; then
        die "No PCI bridge device found"
      fi
      test_print_trc "PCI bridge device found: $dev"
    done
}

# function on convert decimal into binary based on input digits argument
# example: decimal_to_binary 5 4, covert decimal 5 into binary of 4 digits
decimal_to_binary() {
  local decimal
  local digits
  decimal=$1
  digits=$2
  digits=$((digits+1))
  echo "obase=2; $decimal" | bc | tail -c "$digits"
}

# function on convert hex into decimal
hex_to_decimal() {
  local hex
  hex=$1
  hex=$(echo $hex | sed 's/^0x//i' | tr 'a-f' 'A-F')
  echo "ibase=16; $hex" | bc
}

# function on PCIe Max Link Speed check, support gen4, gen5 and gen6
# with arguments of gen4, gen5 or gen6
pci_max_link_speed() {
  local gen
  local dev
  local reg
  gen=$1
  dev="${2#[0-9][0-9][0-9][0-9]:}"
  # check Link Capabilities Register section 7.5.3.6 in spec
  reg=$(pcie_check i 10 c 4 | grep "$dev" | grep -o 'reg_value:[0-9a-f]*' | sed 's/reg_value://')
  if [[ "$gen" = "gen5" ]]; then
    if [[ "$reg" -eq 5 ]]; then
      test_print_trc "PCI bridge: $dev, PCIe Max Link Speed is: 32GT/s"
      echo "return: 32"
    elif [[ "$reg" -eq 4 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Max Link Speed is: 16GT/s, expect 32GT/s"
      echo "return: 16"
    elif [[ "$reg" -eq 3 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Max Link Speed is: 8GT/s, expect 32GT/s"
      echo "return: 8"
    elif [[ "$reg" -eq 2 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Max Link Speed is: 5GT/s, expect 32GT/s"
      echo "return: 5"
    elif [[ "$reg" -eq 1 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Max Link Speed is: 2.5GT/s, expect 32GT/s"
      echo "return: 2.5"
    else
      reg=$(decimal_to_binary "$reg" 4)
      test_print_wrg "PCI bridge: $dev, PCIe Max Link Speed registers value $reg"
      echo "return: 0"
    fi
  elif [[ "$gen" = "gen6" ]]; then
    if [[ "$reg" -eq 6 ]]; then
      test_print_trc "PCI bridge: $dev, PCIe Max Link Speed is: 64GT/s"
      echo "return: 64"
    elif [[ "$reg" -eq 5 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Max Link Speed is: 32GT/s, expect 64GT/s"
      echo "return: 32"
    elif [[ "$reg" -eq 4 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Max Link Speed is: 16GT/s, expect 64GT/s"
      echo "return: 16"
    elif [[ "$reg" -eq 3 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Max Link Speed is: 8GT/s, expect 64GT/s"
      echo "return: 8"
    elif [[ "$reg" -eq 2 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Max Link Speed is: 5GT/s, expect 64GT/s"
      echo "return: 5"
    elif [[ "$reg" -eq 1 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Max Link Speed is: 2.5GT/s, expect 64GT/s"
      echo "return: 2.5"
    else
      reg=$(decimal_to_binary "$reg" 4)
      test_print_wrg "PCI bridge: $dev, PCIe Max Link Speed registers value $reg"
      echo 0
    fi
  elif [[ "$gen" = "gen4" ]]; then
    if [[ "$reg" -eq 4 ]]; then
      test_print_trc "PCI bridge: $dev, PCIe Max Link Speed is: 16GT/s"
      echo "return: 16"
    elif [[ "$reg" -eq 3 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Max Link Speed is: 8GT/s, expect 16GT/s"
      echo "return: 8"
    elif [[ "$reg" -eq 2 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Max Link Speed is: 5GT/s, expect 16GT/s"
      echo "return: 5"
    elif [[ "$reg" -eq 1 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Max Link Speed is: 2.5GT/s, expect 16GT/s"
      echo "return: 2.5"
    else
      reg=$(decimal_to_binary "$reg" 4)
      test_print_wrg "PCI bridge: $dev, PCIe Max Link Speed registers value $reg"
      echo "return: 0"
    fi
  else
    die "PCIe Max Link Speed check failed, invalid gen argument $gen"
  fi
}

# function on PCIe Current Link Speed check, support gen4, gen5 and gen6
# with arguments of gen4, gen5 or gen6
pci_current_link_speed() {
  local gen
  local dev
  local reg
  gen=$1
  dev="${2#[0-9][0-9][0-9][0-9]:}"
  # check Link Status Register section 7.5.3.8 in spec
  reg=$(pcie_check i 10 12 4 | grep "$dev" | grep -o 'reg_value:[0-9a-f]*' | sed 's/reg_value://')
  if [[ "$gen" = "gen5" ]]; then
    if [[ "$reg" -eq 5 ]]; then
      test_print_trc "PCI bridge: $dev, PCIe Current Link Speed is: 32GT/s"
      echo "return: 32"
    elif [[ "$reg" -eq 4 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Current Link Speed is: 16GT/s (downgraded)"
      echo "return: 16"
    elif [[ "$reg" -eq 3 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Current Link Speed is: 8GT/s (downgraded)"
      echo "return: 8"
    elif [[ "$reg" -eq 2 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Current Link Speed is: 5GT/s (downgraded)"
      echo "return: 5"
    elif [[ "$reg" -eq 1 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Current Link Speed is: 2.5GT/s (downgraded)"
      echo "return: 2.5"
    else
      reg=$(decimal_to_binary "$reg" 4)
      test_print_wrg "PCI bridge: $dev, PCIe Current Link Speed registers value $reg"
      echo "return: 0"
    fi
  elif [[ "$gen" = "gen6" ]]; then
    if [[ "$reg" -eq 6 ]]; then
      test_print_trc "PCI bridge: $dev, PCIe Current Link Speed is: 64GT/s"
      echo "return: 64"
    elif [[ "$reg" -eq 5 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Current Link Speed is: 32GT/s (downgraded)"
      echo "return: 32"
    elif [[ "$reg" -eq 4 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Current Link Speed is: 16GT/s (downgraded)"
      echo "return: 16"
    elif [[ "$reg" -eq 3 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Current Link Speed is: 8GT/s (downgraded)"
      echo "return: 8"
    elif [[ "$reg" -eq 2 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Current Link Speed is: 5GT/s (downgraded)"
      echo "return: 5"
    elif [[ "$reg" -eq 1 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Current Link Speed is: 2.5GT/s (downgraded)"
      echo "return: 2.5"
    else
      reg=$(decimal_to_binary "$reg" 4)
      test_print_wrg "PCI bridge: $dev, PCIe Current Link Speed registers value $reg"
      echo "return: 0"
    fi
  elif [[ "$gen" = "gen4" ]]; then
    if [[ "$reg" -eq 4 ]]; then
      test_print_trc "PCI bridge: $dev, PCIe Current Link Speed is: 16GT/s"
      echo "return: 16"
    elif [[ "$reg" -eq 3 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Current Link Speed is: 8GT/s (downgraded)"
      echo "return: 8"
    elif [[ "$reg" -eq 2 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Current Link Speed is: 5GT/s (downgraded)"
      echo "return: 5"
    elif [[ "$reg" -eq 1 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Current Link Speed is: 2.5GT/s (downgraded)"
      echo "return: 2.5"
    else
      reg=$(decimal_to_binary "$reg" 4)
      test_print_wrg "PCI bridge: $dev, PCIe Current Link Speed registers value $reg"
      echo "return: 0"
    fi
  else
    die "PCIe Current Link Speed check failed, invalid gen argument $gen"
  fi
}

# function on PCIe Supported Link Speed check, support gen4, gen5 and gen6
# with arguments of gen4, gen5 or gen6
pci_supported_link_speed() {
  local gen
  local dev
  local reg
  gen=$1
  dev="${2#[0-9][0-9][0-9][0-9]:}"
  # check Link Capabilities 2 Register section
  # 8 bits vector, bit 0 is reserved, so need to remove it
  reg=$(pcie_check i 10 2c 8 | grep "$dev" | grep -o 'reg_value:[0-9a-f]*' | sed 's/reg_value://')
  reg=$(hex_to_decimal "$reg")
  if [[ "$gen" = "gen5" ]]; then
    if [[ "$reg" -eq 62 ]]; then
      test_print_trc "PCI bridge: $dev, PCIe Supported Link Speeds: 2.5-32GT/s"
      echo "return: 2.5-32GT/s"
    elif [[ "$reg" -eq 30 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Supported Link Speeds: 2.5-16GT/s, expect 2.5-32GT/s"
      echo "return: 2.5-16GT/s"
    elif [[ "$reg" -eq 14 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Supported Link Speeds: 2.5-8GT/s, expect 2.5-32GT/s"
      echo "return: 2.5-8GT/s"
    elif [[ "$reg" -eq 6 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Supported Link Speeds: 2.5-5GT/s, expect 2.5-32GT/s"
      echo "return: 2.5-5GT/s"
    elif [[ "$reg" -eq 2 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Supported Link Speeds: 2.5GT/s, expect 2.5-32GT/s"
      echo "return: 2.5GT/s"
    else
      test_print_wrg "PCI bridge: $dev, PCIe Supported Link Speeds registers value $reg"
      echo "return: 0"
    fi
  elif [[ "$gen" = "gen6" ]]; then
    if [[ "$reg" -eq 126 ]]; then
      test_print_trc "PCI bridge: $dev, PCIe Supported Link Speeds: 2.5-64GT/s"
      echo "return: 2.5-64GT/s"
    elif [[ "$reg" -eq 62 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Supported Link Speeds: 2.5-32GT/s, expect 2.5-64GT/s"
      echo "return: 2.5-32GT/s"
    elif [[ "$reg" -eq 30 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Supported Link Speeds: 2.5-16GT/s, expect 2.5-64GT/s"
      echo "return: 2.5-16GT/s"
    elif [[ "$reg" -eq 14 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Supported Link Speeds: 2.5-8GT/s, expect 2.5-64GT/s"
      echo "return: 2.5-8GT/s"
    elif [[ "$reg" -eq 6 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Supported Link Speeds: 2.5-5GT/s, expect 2.5-64GT/s"
      echo "return: 2.5-5GT/s"
    elif [[ "$reg" -eq 2 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Supported Link Speeds: 2.5GT/s, expect 2.5-64GT/s"
      echo "return: 2.5GT/s"
    else
      test_print_wrg "PCI bridge: $dev, PCIe Supported Link Speeds registers value $reg"
      echo "return: 0"
    fi
  elif [[ "$gen" = "gen4" ]]; then
    if [[ "$reg" -eq 30 ]]; then
      test_print_trc "PCI bridge: $dev, PCIe Supported Link Speeds: 2.5-16GT/s"
      echo "return: 2.5-16GT/s"
    elif [[ "$reg" -eq 14 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Supported Link Speeds: 2.5-8GT/s, expect 2.5-16GT/s"
      echo "return: 2.5-8GT/s"
    elif [[ "$reg" -eq 6 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Supported Link Speeds: 2.5-5GT/s, expect 2.5-16GT/s"
      echo "return: 2.5-5GT/s"
    elif [[ "$reg" -eq 2 ]]; then
      test_print_wrg "PCI bridge: $dev, PCIe Supported Link Speeds: 2.5GT/s, expect 2.5-16GT/s"
      echo "return: 2.5GT/s"
    else
      test_print_wrg "PCI bridge: $dev, PCIe Supported Link Speeds registers value $reg"
      echo "return: 0"
    fi
  else
    die "PCIe Supported Link Speed check failed, invalid gen argument $gen"
  fi
}

# function on PCIe Target Link Speed check, support gen4, gen5 and gen6
# with arguments of gen4, gen5 or gen6
pci_target_link_speed() {
  local gen
  local dev
  local reg
  gen=$1
  dev="${2#[0-9][0-9][0-9][0-9]:}"
  # check Link Control 2 Register section
  reg=$(pcie_check i 10 30 4 | grep "$dev" | grep -o 'reg_value:[0-9a-f]*' | sed 's/reg_value://')
  if [[ "$gen" = "gen5" ]]; then
    if [[ "$reg" -eq 5 ]]; then
      test_print_trc "PCI bridge: $dev, PCIe Target Link Speed is: 32GT/s"
      echo "return: 32"
    else
      reg=$(decimal_to_binary "$reg" 4)
      test_print_wrg "PCI bridge: $dev, PCIe Target Link Speed registers value $reg"
      echo "return: 0"
    fi
  elif [[ "$gen" = "gen6" ]]; then
    if [[ "$reg" -eq 6 ]]; then
      test_print_trc "PCI bridge: $dev, PCIe Target Link Speed is: 64GT/s"
      echo "return: 64"
    else
      reg=$(decimal_to_binary "$reg" 4)
      test_print_wrg "PCI bridge: $dev, PCIe Target Link Speed registers value $reg"
      echo "return: 0"
    fi
  elif [[ "$gen" = "gen4" ]]; then
    if [[ "$reg" -eq 4 ]]; then
      test_print_trc "PCI bridge: $dev, PCIe Target Link Speed is: 16GT/s"
      echo "return: 16"
    else
      reg=$(decimal_to_binary "$reg" 4)
      test_print_wrg "PCI bridge: $dev, PCIe Target Link Speed registers value $reg"
      echo "return: 0"
    fi
  else
    die "PCIe Target Link Speed check failed, invalid gen argument $gen"
  fi
}

###################### Do Works ######################
cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

# run pre-check
pci_bridge_device_check

# run pcie capability check
pci_bridge_device=0
dev=0
gen=$1
max_speed=0
support_speed=0
target_speed=0
passed=0
failed=0

pci_bridge_device=$(lspci -nnv | grep -wE "PCI bridge" | grep -iv "pci-to-pci" | awk '{print $1}')
pci_bridge_device=$(echo -e $pci_bridge_device)
IFS=" " read -ra pci_bridge_array <<< "$pci_bridge_device"
for dev in "${pci_bridge_array[@]}"
  do
    max_speed_result=$(pci_max_link_speed $gen $dev)
    echo $max_speed_result
    max_speed=$(echo $max_speed_result | grep -o 'return: .*' | sed 's/return: //')
    current_speed_result=$(pci_current_link_speed $gen $dev)
    echo $current_speed_result
    support_speed_result=$(pci_supported_link_speed $gen $dev)
    echo $support_speed_result
    support_speed=$(echo $support_speed_result | grep -o 'return: .*' | sed 's/return: //')
    target_speed_result=$(pci_target_link_speed $gen $dev)
    echo $target_speed_result
    target_speed=$(echo $target_speed_result | grep -o 'return: .*' | sed 's/return: //')
    if [[ "$gen" != "gen4" && "$gen" != "gen5" && "$gen" != "gen6" ]]; then
      die "Invalid gen argument $gen"
    elif [[ "$gen" = "gen4" ]]; then
      # check if max speed is 16GT/s, support speed is 2.5-16GT/s and target speed is 16GT/s
      # bypass current link speed check as it may be downgraded due to various reasons
      if [[ "$max_speed" -eq 16 && "$support_speed" = "2.5-16GT/s" && "$target_speed" -eq 16 ]]; then
        test_print_trc "PCI bridge: $dev, PCIe Gen4 capability check passed"
        passed=1
        continue
      fi
    elif [[ "$gen" = "gen5" ]]; then
      # check if max speed is 32GT/s, support speed is 2.5-32GT/s and target speed is 32GT/s
      # bypass current link speed check as it may be downgraded due to various reasons
      if [[ "$max_speed" -eq 32 && "$support_speed" = "2.5-32GT/s" && "$target_speed" -eq 32 ]]; then
        test_print_trc "PCI bridge: $dev, PCIe Gen5 capability check passed"
        passed=1
        continue
      fi
    elif [[ "$gen" = "gen6" ]]; then
      # check if max speed is 64GT/s, support speed is 2.5-64GT/s and target speed is 64GT/s
      # bypass current link speed check as it may be downgraded due to various reasons
      if [[ "$max_speed" -eq 64 && "$support_speed" = "2.5-64GT/s" && "$target_speed" -eq 64 ]]; then
        test_print_trc "PCI bridge: $dev, PCIe Gen6 capability check passed"
        passed=1
        continue
      fi
    fi
    test_print_wrg "PCI bridge: $dev, PCIe $gen capability check failed"
    failed=1
  done

if [[ "$passed" -eq 1 && "$failed" -eq 0 ]]; then
  test_print_trc "PCIe $gen capability check test completed successfully"
elif [[ "$failed" -eq 1 ]]; then
  die "PCIe $gen capability check failed after all PCI bridge devices checked"
fi