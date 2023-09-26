#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation
# Description:  Test script for Intel® CPU Topology
# @Author   wendy.wang@intel.com
# @History  Created Sep 26 2023 - Created

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

: "${CASE_NAME:=""}"

usage() {
  cat <<__EOF
  usage: ./${0##*/} [-t TESTCASE_ID] [-H]
  -t  TEST CASE ID
  -H  show this
__EOF
}

# cpuid tool is required to run cases
cpuid 1>/dev/null 2>&1 || block_test "cpuid tool is required to \
run cases, please install it by command: sudo apt install cpuid or \
sudo dnf install cpuid."

# Function to check numa nodes align with packages
# This is for server platform only
numa_nodes_compare_with_package() {
  local numa_nodes
  local cpuinfo_nodes

  cpuinfo_nodes=$(lscpu | grep NUMA 2>&1)
  [[ -n $cpuinfo_nodes ]] || block_test "NUMA nodes info is not available from lscpu."
  test_print_trc "SUT NUMA nodes info from lscpu shows: $cpuinfo_nodes"

  numa_nodes=$(grep . /sys/devices/system/node/node*/cpulist 2>&1)
  [[ -n $numa_nodes ]] || block_test "NUMA nodes sysfs files is not available."
  test_print_trc "SUT NUMA nodes sysfs info: $numa_nodes"
  nodes_lines=$(grep . /sys/devices/system/node/node*/cpulist | wc -l 2>&1)

  for ((i = 1; i <= nodes_lines; i++)); do
    node_cpu_list=$(echo "$numa_nodes" | sed -n "$i, 1p" | awk -F ":" '{print $2}')
    node_num=$(lscpu | grep "$node_cpu_list" | awk -F " " '{print $2}')
    test_print_trc "node num: $node_num"
    test_print_trc "NUMA $node_num sysfs show cpu list: $node_cpu_list"
    cpu_num=$(echo "$node_cpu_list" | awk -F "-" '{print $1}')
    test_print_trc "cpu num for pkg cpu list:$cpu_num"
    pkg_cpu_list=$(grep . /sys/devices/system/cpu/cpu"$cpu_num"/topology/package_cpus_list)
    [[ -n "$pkg_cpu_list" ]] || block_test "CPU Topology sysfs for package_cpus_list is not available."
    test_print_trc "CPU$cpu_num located Package cpu list is: $pkg_cpu_list"
    if [ "$node_cpu_list" = "$pkg_cpu_list" ]; then
      test_print_trc "NUMA $node_num cpu list is aligned with package cpu list"
    else
      die "NUMA $node_num cpu list is NOT aligned with package cpu list"
    fi
  done
}

# Function to verify thread number per core
thread_per_core() {
  smt_enable=$(cat /sys/devices/system/cpu/smt/active)
  threads_per_core=$(lscpu | grep "Thread(s) per core" | awk '{print $4}')

  if [[ $smt_enable -eq 1 ]] && [[ $threads_per_core -eq 2 ]]; then
    test_print_trc "SMT is enabled, Thread(s) per core is 2, it's expected."
  elif [[ $smt_enable -eq 1 ]] && [[ $threads_per_core -eq 1 ]]; then
    die "SMT is enabled, Thread(s) per core is 1, it's not expected"
  elif [[ $smt_enable -eq 0 ]] && [[ $threads_per_core -eq 1 ]]; then
    test_print_trc "SMT is not enabled, Thread(s) per core is 1, it's expected."
  elif [[ $smt_enable -eq 0 ]] && [[ $threads_per_core -eq 1 ]]; then
    die "SMT is not enabled, Thread(s) per core is 2, it's not expected"
  else
    die "Unknown SMT status"
  fi
}

# Function to verify cores number per socket
core_per_socket() {
  cores_per_socket_sys=$(grep ^"core id" /proc/cpuinfo | sort -u | wc -l)
  test_print_trc "sysfs shows cores per socket: $cores_per_socket_sys"
  socket_num_lscpu_parse=$(lscpu -b -p=Socket | grep -v '^#' | sort -u | wc -l)
  cores_per_socket_raw_lscpu=$(lscpu -b -p=Core,Socket | grep -v '^#' | sort -u | wc -l)
  cores_per_socket_lscpu=$(("$cores_per_socket_raw_lscpu" / "$socket_num_lscpu_parse"))
  test_print_trc "lscpu parse shows cores per socket: $cores_per_socket_lscpu"
  cores_per_socket=$(lscpu | grep "Core(s) per socket" | awk '{print $4}')
  test_print_trc "lscpu shows cores per socket: $cores_per_socket"
  core_per_socket_topo=$(grep . /sys/devices/system/cpu/cpu*/topology/core_id |
    awk -F ":" '{print $2}' | sort -u | wc -l)
  test_print_trc "CPU topology sysfs shows cores per socket: $core_per_socket_topo"

  if [[ $cores_per_socket_sys -eq $cores_per_socket_lscpu ]] &&
    [[ $cores_per_socket_sys -eq $cores_per_socket ]] &&
    [[ $cores_per_socket_sys -eq $core_per_socket_topo ]]; then
    test_print_trc "cores per sockets is aligned between sysfs and lscpu"
  elif [[ $cores_per_socket_sys -eq $cores_per_socket_lscpu ]] &&
    [[ $cores_per_socket_sys -ne $cores_per_socket ]]; then
    die "lscpu output for cores per socket is wrong."
  elif [[ $cores_per_socket_sys -eq $cores_per_socket_lscpu ]] &&
    [[ $core_per_socket_topo -ne $cores_per_socket ]]; then
    die "lscpu output for cores per socket is wrong."
  else
    die "cores per sockets is not aligned between sysfs and lscpu"
  fi
}

# Function to verify socket number align between sysfs and lspci
socket_num() {
  numa_num=$(lscpu | grep "NUMA node(s)" | awk '{print $3}')
  test_print_trc "lspci shows numa node num: $numa_num"
  sockets_num_lspci=$(lscpu | grep "Socket(s)" | awk '{print $2}')
  test_print_trc "lspci shows socket number: $sockets_num_lspci"
  sockets_num_sys=$(grep "physical id" /proc/cpuinfo | sort -u | wc -l)
  test_print_trc "sysfs shows socket number: $sockets_num_sys"
  socket_num_topo_sysfs=$(grep . /sys/devices/system/cpu/cpu*/topology/physical_package_id |
    awk -F ":" '{print $2}' | sort -u | wc -l)
  [[ -n "$socket_num_topo_sysfs" ]] || block_test "CPU Topology sysfs for physical_package_id is not available."
  test_print_trc "topology sysfs shows socket number: $socket_num_topo_sysfs"

  if [[ $sockets_num_lspci -eq $sockets_num_sys ]] &&
    [[ $socket_num_topo_sysfs -eq $sockets_num_lspci ]] &&
    [[ $sockets_num_sys -eq $numa_num ]]; then
    test_print_trc "socket number is aligned between lspci and sysfs"
  else
    die "socket number is not aligned between lspci and sysfs"
  fi
}

# Function to verify thread, core, module level type and bit_width_index
# Other level type has not been covered yet.
level_type() {
  thread_type=$(cpuid -l 0x1f -s 0 | grep "level type" | sort -u | awk -F "=" '{print $2}' | awk '{print $1}')
  test_print_trc "0x1f leaf's subleaf 0 shows $thread_type level type"
  bit_width_index_0=$(cpuid -l 0x1f -s 0 | grep width | sort -u | wc -l)
  test_print_trc "0x1f leaf's subleaf 0 bit width line: $bit_width_index_0"
  core_type=$(cpuid -l 0x1f -s 1 | grep "level type" | sort -u | awk -F "=" '{print $2}' | awk '{print $1}')
  test_print_trc "0x1f leaf's subleaf 1 shows $core_type level type"
  bit_width_index_1=$(cpuid -l 0x1f -s 1 | grep width | sort -u | wc -l)
  test_print_trc "0x1f leaf's subleaf 1 bit width line: $bit_width_index_1"
  module_type=$(cpuid -l 0x1f -s 2 | grep "level type" | sort -u | awk -F "=" '{print $2}' | awk '{print $1}')
  test_print_trc "0x1f leaf's subleaf 2 shows $module_type level type"
  bit_width_index_2=$(cpuid -l 0x1f -s 2 | grep width | sort -u | wc -l)
  test_print_trc "0x1f leaf's subleaf 2 bit width line: $bit_width_index_2"
  invalid_type_sub3=$(cpuid -l 0x1f -s 3 | grep "level type" | sort -u | awk -F "=" '{print $2}' | awk '{print $1}')
  test_print_trc "0x1f leaf's subleaf 3 shows $invalid_type_sub3 level type"
  bit_width_index_3=$(cpuid -l 0x1f -s 3 | grep width | sort -u | wc -l)
  test_print_trc "0x1f leaf's subleaf 3 bit width line: $bit_width_index_3"
  invalid_type_sub4=$(cpuid -l 0x1f -s 4 | grep "level type" | sort -u | awk -F "=" '{print $2}' | awk '{print $1}')
  test_print_trc "0x1f leaf's subleaf 4 shows $invalid_type_sub4 level type"

  if [[ $thread_type == thread ]] && [[ $bit_width_index_0 -eq 1 ]]; then
    test_print_trc "CPUID: level type: thread is correctly detected, and all threads bit width are aligned"
  else
    die "CPUID: level type: thread is not correctly detected or bit width is not aligned"
  fi

  if [[ $core_type == core ]] && [[ $bit_width_index_1 -eq 1 ]]; then
    test_print_trc "CPUID: level type: core is correctly detected, and all cores bit width are aligned"
  else
    die "CPUID: level type: core is not correctly detected or bit width is not aligned"
  fi

  if [[ $module_type == module ]] && [[ $invalid_type_sub3 == invalid ]] &&
    [[ $invalid_type_sub4 == invalid ]] && [[ $bit_width_index_2 -eq 1 ]] &&
    [[ $bit_width_index_3 -eq 1 ]]; then
    test_print_trc "CPUID: module and invalid level type are detected, and bit width are aligned."
  elif [[ $module_type == invalid ]] && [[ $invalid_type_sub3 == invalid ]] &&
    [[ $bit_width_index_3 -eq 1 ]]; then
    test_print_trc "CPUID: platform does not support module, and invalid level type is detected,
bit width of level & previous levels are aligned."
  else
    die "CPUID: unexpected level type."
  fi
}

cpu_topology_test() {
  case $TEST_SCENARIO in
  numa_nodes_compare)
    numa_nodes_compare_with_package
    ;;
  verify_thread_per_core)
    thread_per_core
    ;;
  verify_cores_per_socket)
    core_per_socket
    ;;
  verify_socket_num)
    socket_num
    ;;
  verify_level_type)
    level_type
    ;;
  esac
  return 0
}

while getopts :t:H arg; do
  case $arg in
  t)
    TEST_SCENARIO=$OPTARG
    ;;
  H)
    usage && exit 0
    ;;
  \?)
    usage
    die "Invalid Option -$OPTARG"
    ;;
  :)
    usage
    die "Option -$OPTARG requires an argument."
    ;;
  esac
done

cpu_topology_test
