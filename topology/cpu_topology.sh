#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2023 Intel Corporation
# Description:  Test script for Intel® CPU Topology
# @Author   wendy.wang@intel.com
# @History  Created Sep 26 2023 - Created

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

TYPE_VALUE=""
HYBRID_VALUE=""
LL3_VALUE=""
DIE_VALUE=""
SNC_VALUE=""
LL3_PER_SOCKET=""

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

# Function to check the hybrid true or false
get_hybrid_sku() {
  local hybrid_type
  local cmd_output

  hybrid_type=$(cpuid -l 0x07 | grep hybrid | sort -u | awk '{print $NF}')

  case $hybrid_type in
  true)
    cmd_output="hybrid true"
    HYBRID_VALUE="true"
    test_print_trc "Current CPU is hybrid true"
    ;;
  false)
    cmd_output="hybrid false"
    HYBRID_VALUE="false"
    test_print_trc "Current CPU is hybrid false"
    ;;
  *)
    cmd_output=$hybrid_type
    block_test "Unkown hybrid SKU"
    return 1
    ;;
  esac
  do_cmd "echo $cmd_output"
  return 0
}

# Function to check core type: Core or Atom or Pcore Only
get_core_type() {
  local cpu_id=$1
  local core_type
  core_type=$(cpuid -l 0x1a | grep -A 3 "CPU $cpu_id" | tail -n 1 | awk '{print $5}')
  local cmd_output

  case $core_type in
  Core)
    TYPE_VALUE="Core"
    cmd_output="Intel Core"
    test_print_trc "Current CPU is $cmd_output"
    ;;
  Atom)
    TYPE_VALUE="Atom"
    cmd_output="Intel Atom"
    test_print_trc "Current CPU is $cmd_output"
    ;;
  "(0)")
    TYPE_VALUE="0x0"
    cmd_output="Intel Pcore only"
    test_print_trc "Current CPU is $cmd_output"
    ;;
  *)
    cmd_output=$core_type
    block_test "Unknown CPU Core Type"
    return 1
    ;;
  esac
  do_cmd "echo $cmd_output"
  return 0
}

# Function to check if the ecore have L3 Cache
get_ecore_wo_llc() {
  local cpu_list_wo_llc

  cpu_list_wo_llc=$(cpuid -l 0x04 -s 3 | grep -B 2 "no more caches")
  if [[ -n $cpu_list_wo_llc ]]; then
    LL3_VALUE="false"
    test_print_trc "SKU has CPUs no L3 Cache" && return 0 || return 1
  else
    LL3_VALUE="true"
    test_print_trc "All CPUs have L3 Cache" && return 1 || return 0
  fi
}

# Function to check if the CPU supports Die level type
get_die_level_type() {
  local die_type

  die_type=$(cpuid -l 0x1f -s 3 | grep "die" | sort -u | awk '{print $4}')
  if [[ -n $die_type ]]; then
    DIE_VALUE="true"
    test_print_trc "CPU supports Die level type" && return 0 || return 1
  else
    DIE_VALUE="false"
    test_print_trc "CPU does not support Die level type" && return 1 || return 0
  fi
}

# Function to check if SNC is enabled or not
get_snc_disable() {
  local socket_num

  socket_num=$(lscpu | grep "Socket(s)" | awk '{print $NF}')
  test_print_trc "Sockets number: $socket_num"
  numa_nodes=$(lscpu | grep "NUMA node(s)" | awk '{print $NF}')
  test_print_trc "NUMA Nodes: $numa_nodes"

  if [[ $numa_nodes -eq $socket_num ]]; then
    SNC_VALUE="disabled"
    test_print_trc "CPU SNC is disabled" && return 0 || return 1
  else
    SNC_VALUE="enabled"
    test_print_trc "CPU SNC is enabled" && return 1 || return 0
  fi
}

get_lstopo_outputs() {
  test_print_trc "Enable the sched_domain verbose"
  do_cmd "echo Y > /sys/kernel/debug/sched/verbose"

  numa_num=$(lscpu | grep "NUMA node(s)" | awk '{print $3}')
  test_print_trc "lspci shows numa node num: $numa_num"

  sched_domain_names=$(grep . /sys/kernel/debug/sched/domains/cpu0/domain*/name | awk -F ":" '{print $NF}')
  test_print_trc "CPU0 sched_domain names: $sched_domain_names"
  sched_domain_proc=$(cat /proc/schedstat)
  [[ -n "$sched_domain_names" ]] || block_test "sched_domain debugfs is not available, need to check \
  /proc/schedstat: $sched_domain_proc"

  test_print_trc "Will run lstopo --no-io command to get topology outputs"
  lstopo --no-io 1>/dev/null 2>&1 || block_test "Please install hwloc-gui.x86_64 package to get lstopo tool"
  do_cmd "lstopo --no-io > topology.log"
  test_print_trc "lstopo output:"
  do_cmd "cat topology.log"
}

# Function to check how many L3 cache per package,
# or if the package supports multiple die
get_ll3_num() {
  local pkg_num
  local llc_num

  test_print_trc "Check if the platform supports multiple LLC in one package:"
  lstopo --no-io 1>/dev/null 2>&1 || block_test "Please install hwloc-gui.x86_64 package to get lstopo tool"
  do_cmd "lstopo -v --no-io > topology_verbose.log"

  if [[ -f topology_verbose.log ]]; then
    pkg_num=$(grep Package topology_verbose.log | grep depth | awk -F ":" '{print $2}' | sed 's/^ *//' | awk '{print $1}')
    test_print_trc "Package number is: $pkg_num"
    llc_num=$(grep L3Cache topology_verbose.log | grep depth | awk -F ":" '{print $2}' | sed 's/^ *//' | awk '{print $1}')
    test_print_trc "L3 Cache number is: $llc_num"
  else
    block_test "topology_verbose.log is not available."
  fi

  if [[ $llc_num -gt $pkg_num ]]; then
    LL3_PER_SOCKET="yes"
    test_print_trc "CPU supports multiple L3 Cache per package." && return 0 || return 1
  else
    LL3_PER_SOCKET="no"
    test_print_trc "CPU supports 1 L3 Cache per package." && return 1 || return 0
  fi
}

# Function to disable sched_domain debug verbose after testing
disable_sched_domain_debug() {
  test_print_trc "Disable the sched_domain verbose"
  do_cmd "echo N > /sys/kernel/debug/sched/verbose"
}

# Function to do generic sched_domain names check
# By automatically detect the core type and cache support
generic_sched_domain_names() {
  local cpu_last
  local i=0
  local j
  local k=0
  local h=0
  local names_bf=""
  local names_af=""
  local names_bf_array=()
  local names_af_array=()
  local smt_enable
  cpu_last=$(cpuid -l 0x1f | grep "CPU" | tail -1 | sed 's/:$//' | awk '{print $NF}')

  smt_enable=$(cat /sys/devices/system/cpu/smt/active)

  # Enable sched_domain debug verbose and print the lstopo logs
  # Get CPU capability covering L3 cache, Die level type, SNC
  get_lstopo_outputs
  get_ecore_wo_llc
  get_die_level_type
  get_snc_disable
  get_ll3_num
  test_print_trc

  # We need to go though all the cpus and filter out the CPUs with different sched_domain
  for ((i = 0; i <= cpu_last; i++)); do
    # Get cpu$i's sched_domain name list, and put in array
    names_lines=$(grep . /sys/kernel/debug/sched/domains/cpu$i/domain*/name | wc -l)
    if [[ $names_lines -eq 1 ]]; then
      names_af=$(grep . /sys/kernel/debug/sched/domains/cpu$i/domain*/name)
      test_print_trc "CPU$i shows sched_domain name: $names_af"
    else
      names_af=$(grep . /sys/kernel/debug/sched/domains/cpu$i/domain*/name | awk -F ":" '{print $2}')
      test_print_trc "CPU$i shows sched_domain name: $names_af"
    fi
    names_af_array=($names_af)
    test_print_trc "Names_af_array value: ${names_af_array[*]}"
    for ((k = 0; k < ${#names_af_array[@]}; k++)); do
      if [[ "${names_bf_array[k]}" != "${names_af_array[k]}" ]]; then
        test_print_trc
        test_print_trc "###### CPU$i sched_domain name check ######"

        # Get each sched_domain name and verify
        names_count=$(grep . /sys/kernel/debug/sched/domains/cpu$i/domain*/name | awk -F ":" '{print $2}' | wc -l)
        j=0
        while [ $j -le "$names_count" ]; do
          h=$((j + 1))
          name_j=$(echo "$names_af" | sed -n "$h,1p")
          # Check if SMT is enabled and supported
          # Only Pcore type has chance to support SMT
          # So the condition is: Pcore, SMT enable
          get_hybrid_sku $i
          get_core_type $i

          # Test sched_domain0
          if [[ $j -eq 0 ]]; then
            if [[ $name_j == SMT ]] && [[ $smt_enable -eq 1 ]] && [[ $TYPE_VALUE != Atom ]]; then
              test_print_trc "CPU$i sched_domain$j name $name_j is expected."
            elif [[ $name_j == SMT ]] && [[ $smt_enable -ne 1 ]]; then
              disable_sched_domain_debug
              die "CPU$i sched_domain$j name $name_j is NOT expected as SMT is disabled"
            elif [[ $name_j == SMT ]] && [[ $TYPE_VALUE == Atom ]]; then
              disable_sched_domain_debug
              die "CPU$i sched_domain$j name $name_j is NOT expected as Atom type"
            # Check if CLS is enabled and supported
            # CLS: cpus share L2 cache, in other word, there are multiple CPUs under L2 cache by lstopo
            # Only hybrid false + Pcore only SKU, will have cores sharing the same L2 cache
            elif [[ $name_j == CLS ]] && [[ $TYPE_VALUE == Atom ]]; then
              test_print_trc "CPU$i sched_domain$j name $name_j is expected as Atom type."
            # For multiple Dies SKU
            elif [[ $HYBRID_VALUE == false ]] && [[ $name_j == CLS ]] &&
              [[ $TYPE_VALUE == 0x0 ]] && [[ $DIE_VALUE == true ]]; then
              test_print_trc "CPU$i sched_domain$j name $name_j is expected."
            elif [[ $name_j == CLS ]]; then
              disable_sched_domain_debug
              die "CPU$i sched_domain$j name $name_j is on unknown SKU."
            elif [[ $name_j == MC ]] && [[ $TYPE_VALUE != Atom ]]; then
              test_print_trc "CPU$i sched_domain$j name $name_j is expected on SMT disable Pcore"
            else
              disable_sched_domain_debug
              die "CPU$i sched_domain$j name shows $name_j is on unknown SKU."
            fi
            # Test sched_domain1 if supports
          elif [[ $j -lt $names_count ]] && [[ $j -eq 1 ]]; then
            # When all the CPUs share L3 cache, then PKG sched_domain will duplicate with MC
            if [[ -z $name_j ]] && [[ $HYBRID_VALUE == true ]] && [[ $LL3_VALUE == true ]]; then
              test_print_trc "CPU$i sched_domain$j name does not exist is expected on CPUs sharing LL3 SKU."
            elif [[ $name_j == MC ]]; then
              test_print_trc "CPU$i sched_domain$j name $name_j is expected on most SKU."
            elif [[ $name_j == PKG ]] && [[ $HYBRID_VALUE == true ]] && [[ $LL3_VALUE == false ]]; then
              test_print_trc "CPU$i sched_domain$j name $name_j is expected on CPUs lack of LL3 SKU."
            else
              disable_sched_domain_debug
              die "CPU$i sched_domain$j name $name_j is on unknown SKU."
            fi
            # Test sched_domain2 if supports
          elif [[ $j -lt $names_count ]] && [[ $j -eq 2 ]]; then
            # Server SKU will not have PKG sched_domain name, but NUMA
            if [[ $name_j == NUMA ]] && [[ $HYBRID_VALUE == false ]] && [[ $DIE_VALUE == false ]]; then
              test_print_trc "CPU$i sched_domain$j name $name_j is expected on Server"
            # SKU with multiple Dies will have sched_domain name: DIE
            elif [[ $name_j == DIE ]] && [[ $HYBRID_VALUE == false ]] && [[ $DIE_VALUE == true ]] &&
              [[ $SNC_VALUE == disabled ]]; then
              test_print_trc "CPU$i sched_domain$j name $name_j is expected on SNC disabled CBB topology Server"
            # Server which have muliple LL3 per package will support DIE sched_domain
            elif [[ $name_j == DIE ]] && [[ $HYBRID_VALUE == false ]] && [[ $LL3_PER_SOCKET == yes ]]; then
              test_print_trc "CPU$i sched_domain$j name $name_j is expected on SNC disabled multiple LL3 SKU per package"
            # Client with hybrid SKU will support PKG sched_domain
            elif [[ $name_j == PKG ]] && [[ $HYBRID_VALUE == true ]]; then
              test_print_trc "CPU$i sched_domain$j name $name_j is expected on hybrid Client SKU"
            else
              disable_sched_domain_debug
              die "CPU$i sched_domain$j name $name_j is on unknown SKU."
            fi
            # Test sched_domain3 if supports
          elif [[ $j -lt $names_count ]] && [[ $j -eq 3 ]]; then
            if [[ $name_j == NUMA ]] && [[ $HYBRID_VALUE == false ]] &&
              [[ $LL3_PER_SOCKET == yes ]] && [[ $SNC_VALUE == disabled ]]; then
              test_print_trc "CPU$i sched_domain$j name $name_j is expected on SNC disabled multiple LL3 SKU per package"
            elif [[ $name_j == NUMA ]] && [[ $HYBRID_VALUE == false ]] &&
              [[ $DIE_VALUE == yes ]] && [[ $SNC_VALUE == disabled ]]; then
              test_print_trc "CPU$i sched_domain$j name $name_j is expected on SNC disabled multiple die SKU"
            elif [[ $name_j == NUMA ]] && [[ $HYBRID_VALUE == false ]] &&
              [[ $SNC_VALUE == enabled ]]; then
              test_print_trc "CPU$i sched_domain$j name $name_j is expected on SNC enabled SKU"
            else
              disable_sched_domain_debug
              die "CPU$i sched_domain$j name $name_j is on unknown SKU."
            fi
          # Test sched_domain4 if supports
          elif [[ $j -lt $names_count ]] && [[ $j -eq 4 ]]; then
            if [[ $name_j == NUMA ]] && [[ $HYBRID_VALUE == false ]] &&
              [[ $LL3_PER_SOCKET == yes ]] && [[ $SNC_VALUE == enabled ]]; then
              test_print_trc "CPU$i sched_domain$j name $name_j is expected on SNC enabled multiple LL3 SKU per package"
            elif [[ $name_j == NUMA ]] && [[ $HYBRID_VALUE == false ]] &&
              [[ $DIE_VALUE == yes ]] && [[ $SNC_VALUE == enabled ]]; then
              test_print_trc "CPU$i sched_domain$j name $name_j is expected on SNC enabled multiple die SKU"
            elif [[ $name_j == NUMA ]] && [[ $HYBRID_VALUE == false ]] &&
              [[ $DIE_VALUE == no ]] && [[ $SNC_VALUE == enabled ]]; then
              test_print_trc "CPU$i sched_domain$j name $name_j is expected on SNC enabled SKU"
            else
              disable_sched_domain_debug
              die "CPU$i sched_domain$j name $name_j is on unknown SKU."
            fi
          fi
          j=$((j + 1))
        done
      fi
    done
    if [[ $names_lines -eq 1 ]]; then
      names_bf=$(grep . /sys/kernel/debug/sched/domains/cpu$i/domain*/name)
      test_print_trc "CPU$i shows sched_domain name: $names_bf"
    else
      names_bf=$(grep . /sys/kernel/debug/sched/domains/cpu$i/domain*/name | awk -F ":" '{print $2}')
      test_print_trc "CPU$i shows sched_domain name: $names_bf"
    fi
    names_bf_array=($names_bf)
    test_print_trc "Names_bf_array value: ${names_bf_array[*]}"
  done
  disable_sched_domain_debug
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
  verify_sched_domain_names)
    generic_sched_domain_names
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
