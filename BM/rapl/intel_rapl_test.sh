#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation
# Description:  Test script for Intel_RAPL(Running Average Power Limiting)
# driver which is supported on both Intel® client and server platforms
# @Author   wendy.wang@intel.com
# @History  Created Jan 05 2023 - Created

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

RAPL_SYSFS_PATH="/sys/class/powercap"
CPU_SYSFS="/sys/devices/system/cpu"
NUM_CPU_PACKAGES=$(lscpu | grep "Socket(s)" | awk '{print $2}')

RAPL_TIME_UNIT=0   #Micro-second (us)
RAPL_ENERGY_UNIT=0 #Micro-Joules (uJ)
RAPL_POWER_UNIT=0  #Watts

MSR_RAPL_POWER_UNIT="0x606"
MSR_PKG_POWER_LIMIT="0x610"
MSR_PKG_ENERGY_STATUS="0x611"
MSR_DRAM_ENERGY_STATUS="0x619"
MSR_PP0_ENERGY_STATUS="0x639"
MSR_PP1_ENERGY_STATUS="0x641"
MSR_PLATFORM_ENERGY_STATUS="0X64D"

GPU_LOAD="glxgears"
GPU_LOAD_ARG="-display :1"

declare -A CPU_TOPOLOGY

# Turbostat tool is required to run RAPL cases
if which turbostat 1>/dev/null 2>&1; then
  turbostat sleep 1 1>/dev/null || block_test "Failed to run turbostat tool,
please check turbostat tool error message."
else
  block_test "Turbostat tool is required to run RAPL cases,
please get it from latest upstream kernel-tools."
fi

# stress tool is required to run RAPL cases
if which stress 1>/dev/null 2>&1; then
  stress --help 1>/dev/null || block_test "Failed to run stress tool,
please check stress tool error message."
else
  block_test "stress tool is required to run RAPL cases,
please get it from latest upstream kernel-tools."
fi

# perf tool is required to run RAPL cases
if which perf 1>/dev/null 2>&1; then
  perf list 1>/dev/null || block_test "Failed to run perf tool,
please check perf tool error message."
else
  block_test "perf tool is required to run RAPL cases,
please get it from latest upstream kernel-tools."
fi

# Read value from MSR
# Input:
#     $1: Bit range to be read
#     $2: MSR Address
#     $3: (Optional) Select processor - default 0
# Output:
#   MSR_VAL: Value obtain from MSR
read_msr() {
  local fld=$1
  local reg=$2
  local cpu=$3

  : "${cpu:=0}"

  [[ -z $fld || $fld =~ [0-9]+:[0-9]+ ]] || die "Incorrect field format!"
  [[ -n $reg ]] || die "Unable to read register information"

  MSR_VAL=""

  if [[ $fld == "" ]]; then
    MSR_VAL=$(rdmsr -p "$cpu" "$reg")
  else
    MSR_VAL=$(rdmsr -p "$cpu" -f "$fld" "$reg")
  fi

  [[ -n $MSR_VAL ]] || die "Unable to read data from MSR $reg!"
  test_print_trc "Read MSR \"$reg\": value = \"$MSR_VAL\""
}

# Write value to MSR
# Input:
#     $1: ["h:l"] Bit range to be written into MSR
#     $2: MSR Address
#     $3: Value to be written (Hex: Start with 0x, Dec: Numbers)
#     $4: (Optional) Select processor - default 0
write_msr() {
  local fld=$1
  local reg=$2
  local val=$3
  local cpu=$4

  : "${cpu:=0}"

  [[ $# -ge 3 ]] || die "Invalid input parameters!"

  # Check input value
  [[ $val =~ ^0x[0-9a-fA-F]+$ || $val =~ ^[0-9]+$ ]] || die "Invalid input value!"

  # Prepare input value in binary form
  [[ $fld == "" ]] && fld="0:63"
  st=$(echo "$fld" | cut -d":" -f2)
  en=$(echo "$fld" | cut -d":" -f1)
  bit_range=$((en - st + 1))
  [[ $bit_range -lt 0 ]] && die "Bit range is incorrect!"

  bin_val=$(perl -e "printf \"%b\", $val")
  [[ ${#bin_val} -le $bit_range ]] || die "Input value is greater the field range!"

  # Add zero padding on input binary value
  while [[ ${#bin_val} -lt $bit_range ]]; do
    bin_val="0$bin_val"
  done

  bin_val=$(echo "$bin_val" | rev)

  # Read register value and overwrite input value to form new register value
  read_msr "" "$reg"
  reg_val=$(perl -e "printf \"%064b\", 0x$MSR_VAL" | rev)
  new_val=$(echo "${reg_val:0:st}""$bin_val""${reg_val:$((st + ${#bin_val}))}" | rev)
  new_val=$(perl -e "printf \"%016x\n\", $((2#$new_val))")

  # write back to the register
  do_cmd "wrmsr -p \"$cpu\" \"$reg\" 0x$new_val"
}

# Read total energy comsumption from MSR
# Input:
#     $1: Select Processor
#     $2: Select Domain
# Output:
#   CUR_ENERGY: Current energy obtain from MSR
get_total_energy_consumed_msr() {
  local cpu=$1
  local domain=$2
  local reg=""

  [[ $# -eq 2 ]] || die "Invalid number of parameters - $#"
  [[ $RAPL_ENERGY_UNIT != 0 ]] || read_rapl_unit

  domain=$(echo "$domain" | awk '{print tolower($0)}')
  case $domain in
  pkg)
    reg=$MSR_PKG_ENERGY_STATUS
    ;;
  core)
    reg=$MSR_PP0_ENERGY_STATUS
    ;;
  uncore)
    reg=$MSR_PP1_ENERGY_STATUS
    ;;
  dram)
    reg=$MSR_DRAM_ENERGY_STATUS
    ;;
  *)
    die "Invalid Power Domain"
    ;;
  esac

  read_msr "31:0" "$reg" "$cpu"
  CUR_ENERGY=$(echo "$((16#$MSR_VAL)) * $RAPL_ENERGY_UNIT" | bc)
  CUR_ENERGY=${CUR_ENERGY%.*}
  test_print_trc "Total $domain Energy: $CUR_ENERGY uj"
}

# Read total energy comsumption from SYSFS
# Input:
#     $1: Select Package
#     $2: Select Domain
# Output:
#   CUR_ENERY: Current energy obtained from SYSFS
get_total_energy_consumed_sysfs() {
  local pkg=$1
  local domain=$2

  domain=$(echo "$domain" | awk '{print tolower($0)}')
  get_domain_path "$pkg" "$domain"

  local energy_path="$DOMAIN_PATH/energy_uj"
  [[ -f $energy_path ]] || die "Unable to find the energy data in SYSFS"
  CUR_ENERGY=$(cat "$energy_path")
  test_print_trc "Package-$pkg - Total $domain Energy: $CUR_ENERGY uj"
}

# Calculate power consumption over a set period
# Input:
#     $1: Energy measurement method (MSR or SYSFS)
#     $2: Select CPU package
#     $3: Select power domain
#     $4: (Optional) Measurement duration (Default: 15s)
get_power_consumed() {
  local method=$1
  local pkg=$2
  local domain=$3
  local duration=$4

  : "${duration:=15}"

  [[ $# -ge 3 ]] || die "Invalid parameters!"

  method=$(echo "$method" | awk '{print tolower($0)}')
  domain=$(echo "$domain" | awk '{print tolower($0)}')

  [[ $pkg -le $NUM_CPU_PACKAGES ]] || die "Package number is out of range!"
  [[ $domain =~ (pkg|core|uncore|dram) ]] || die "Invalid power domain!"

  case $method in
  msr)
    cpu=$(echo "${CPU_TOPOLOGY[$pkg]}" | cut -d" " -f1)
    get_total_energy_consumed_msr "$cpu" "$domain"
    energy_b4=$CUR_ENERGY

    sleep "$duration"

    get_total_energy_consumed_msr "$cpu" "$domain"
    energy_af=$CUR_ENERGY
    ;;
  sysfs)
    get_total_energy_consumed_sysfs "$pkg" "$domain"
    energy_b4=$CUR_ENERGY

    sleep "$duration"

    get_total_energy_consumed_sysfs "$pkg" "$domain"
    energy_af=$CUR_ENERGY
    ;;
  turbostat)
    columns="CPU,PkgWatt,CorWatt,GFXWatt,RAMWatt"
    do_cmd "turbostat --quiet --show $columns -o ts.log sleep $duration"
    test_print_trc "Turbostat log:"
    cat ts.log

    res=$(grep -e "^-" ts.log | awk '{print $2,$3,$4}' | head -1)
    test_print_trc "Supported Domain zone columns from turbostat log: $res"
    [[ -n $res ]] || die "No result is obtained from turbostat!"

    case $domain in
    pkg)
      CUR_POWER=$(echo "$res" | awk '{print $1}')
      ;;
    core)
      CUR_POWER=$(echo "$res" | awk '{print $2}')
      ;;
    uncore)
      CUR_POWER=$(echo "$res" | awk '{print $3}')
      ;;
    dram)
      CUR_POWER=$(echo "$res" | awk '{print $4}')
      ;;
    *)
      die "Invalid Power Domain!"
      ;;
    esac
    return 0
    ;;
  *)
    die "Invalid Measurement Method!"
    ;;
  esac
  CUR_POWER=$(echo "scale=6;($energy_af - $energy_b4) / $duration / 10^6" | bc)
  test_print_trc "Package-$pkg $domain Power = $CUR_POWER Watts"
}

get_power_consumed_server() {
  local method=$1
  local pkg=$2
  local domain=$3
  local duration=$4

  : "${duration:=15}"

  [[ $# -ge 3 ]] || die "Invalid parameters!"

  method=$(echo "$method" | awk '{print tolower($0)}')
  domain=$(echo "$domain" | awk '{print tolower($0)}')

  [[ $pkg -le $NUM_CPU_PACKAGES ]] || die "Package number is out of range!"
  [[ $domain =~ (pkg|dram) ]] || die "Invalid power domain!"

  case $method in
  msr)
    cpu=$(echo "${CPU_TOPOLOGY[$pkg]}" | cut -d" " -f1)
    get_total_energy_consumed_msr "$cpu" "$domain"
    energy_b4=$CUR_ENERGY

    sleep "$duration"

    get_total_energy_consumed_msr "$cpu" "$domain"
    energy_af=$CUR_ENERGY
    ;;
  sysfs)
    get_total_energy_consumed_sysfs "$pkg" "$domain"
    energy_b4=$CUR_ENERGY

    sleep "$duration"

    get_total_energy_consumed_sysfs "$pkg" "$domain"
    energy_af=$CUR_ENERGY
    ;;
  turbostat)
    columns="CPU,PkgWatt,RAMWatt"
    do_cmd "turbostat --quiet --show $columns -o ts.log sleep $duration"
    test_print_trc "Turbostat log:"
    cat ts.log

    res=$(grep -e "^-" ts.log | awk '{print $2,$3}' | head -1)
    test_print_trc "Supported Domain zone columns from turbostat log: $res"
    [[ -n $res ]] || die "No result is obtained from turbostat!"

    case $domain in
    pkg)
      CUR_POWER=$(echo "$res" | awk '{print $1}')
      test_print_trc "Pkg current power: $CUR_POWER"
      ;;
    dram)
      CUR_POWER=$(echo "$res" | awk '{print $2}')
      test_print_trc "Dram current power: $CUR_POWER"
      ;;
    *)
      die "Invalid Power Domain!"
      ;;
    esac
    return 0
    ;;
  *)
    die "Invalid Measurement Method!"
    ;;
  esac
  CUR_POWER=$(echo "scale=6;($energy_af - $energy_b4) / $duration / 10^6" | bc)
  test_print_trc "Package-$pkg $domain Power = $CUR_POWER Watts"
}

# Get the corresponding domain SYSFS path
# Input:
#     $1: Select CPU Package
#     $2: Select Power Domain
# Output:
#     DOMAIN_PATH: SYSFS PATH for the select domain
get_domain_path() {
  local pkg=$1
  local domain=$2

  DOMAIN_PATH="$RAPL_SYSFS_PATH/intel-rapl:$pkg"

  [[ -d $DOMAIN_PATH ]] || die "RAPL PKG Path does not exist!"

  domain=$(echo "$domain" | awk '{print tolower($0)}')

  case $domain in
  pkg)
    DOMAIN_PATH="$RAPL_SYSFS_PATH/intel-rapl:$pkg"
    ;;
  core)
    DOMAIN_PATH="$DOMAIN_PATH:0"
    ;;
  uncore)
    DOMAIN_PATH="$DOMAIN_PATH:1"
    ;;
  dram)
    DOMAIN_PATH="$DOMAIN_PATH/intel-rapl:$pkg:0"
    ;;
  *)
    die "Invalid Power Domain!"
    ;;
  esac
}

# Enable power limit from sysfs
# Inputs:
#      $1: Select CPU package
#      $2: Select Domain
#      $3: Select state (0=disable, 1=enable)
enable_power_limit() {
  local pkg=$1
  local domain=$2
  local state=$3

  [[ $# -ge 3 ]] || die "Invalid inputs!"

  domain=$(echo "$domain" | awk '{print tolower($0)}')
  get_domain_path "$pkg" "$domain"

  do_cmd "echo \"$state\" > \"$DOMAIN_PATH/enabled\""
}

power_limit_unlock_check() {
  # domain name should be PKG or PP0
  declare -u domain=$1
  local power_limit_unlock=""

  do_cmd "turbostat --debug -o ts.log sleep 2"
  test_print_trc "Turbostat log to check power limit unlock status:"
  cat ts.log
  power_limit_unlock=$(grep UNlocked ts.log |
    grep MSR_"$domain"_POWER_LIMIT)
  test_print_trc "RAPL test domain name: MSR_${domain}_POWER_LIMIT"
  if [[ -n $power_limit_unlock ]]; then
    test_print_trc "RAPL $domain Power limit is unlocked"
  else
    block_test "RAPL $domain Power limit is locked by BIOS, block this case."
  fi
  return 0
}

# Enable power limit from sysfs
# Inputs:
#      $1: Select CPU package
#      $2: Select Domain
#      $3: Select Power Limit
#      $4: Select Time Windows
set_power_limit() {
  local pkg=$1
  local domain=$2
  local limit=$3
  local time_win=$4

  domain=$(echo "$domain" | awk '{print tolower($0)}')
  test_print_trc "The RAPL pkg name is: $pkg"
  test_print_trc "The RAPL domain name is: $domain"
  get_domain_path "$pkg" "$domain"

  do_cmd "echo \"$time_win\" > \"$DOMAIN_PATH/constraint_0_time_window_us\""
  do_cmd "echo \"$limit\" > \"$DOMAIN_PATH/constraint_0_power_limit_uw\""
}

# Create workloads on the specified domain
# Input:
#   $1: Select Domain
# Output:
#   LOAD_PID: PID of the test workload
create_test_load() {
  local domain=$1

  domain=$(echo "$domain" | awk '{print tolower($0)}')
  case $domain in
  pkg | core)
    cpu_avail=$(grep processor /proc/cpuinfo | tail -1 | awk '{print $NF}')
    cpu_test=$(("$cpu_avail" + 1))
    do_cmd "stress -c $cpu_test -t 60 > /dev/null &"
    ;;
  uncore)
    which "$GPU_LOAD" &>/dev/null || die "glxgears does not exist"
    do_cmd "$GPU_LOAD $GPU_LOAD_ARG > /dev/null &"
    ;;
  dram)
    mem_avail=$(grep MemAvailable /proc/meminfo | awk -F " " '{print $2}')
    mem_test=$(echo "$mem_avail"/10000000 | bc)
    do_cmd "stress --vm $mem_test --vm-bytes 1024M -t 30 > /dev/null &"
    ;;
  *)
    die "Invalid domain!"
    ;;
  esac

  LOAD_PID=$!
}

# Clear all workload from system
clear_all_test_load() {
  for load in "stress" "$GPU_LOAD"; do
    for pid in $(pgrep "$load"); do
      do_cmd "kill -9 $pid"
    done
  done
}

# Read the scaling factors for the respective RAPL value.
read_rapl_unit() {
  read_msr "3:0" "$MSR_RAPL_POWER_UNIT"
  RAPL_POWER_UNIT=$(echo "scale=12; 1 / 2^$((16#$MSR_VAL))" | bc)
  test_print_trc "RAPL Power Unit = $RAPL_POWER_UNIT Watts"

  read_msr "12:8" "$MSR_RAPL_POWER_UNIT"
  RAPL_ENERGY_UNIT=$(echo "scale=12; 1 / 2^$((16#$MSR_VAL)) * 10^6" | bc)
  test_print_trc "RAPL Energy Unit = $RAPL_ENERGY_UNIT uj"

  read_msr "19:16" "$MSR_RAPL_POWER_UNIT"
  RAPL_TIME_UNIT=$(echo "scale=12; 1 / 2^$((16#$MSR_VAL)) * 10^6" | bc)
  test_print_trc "RAPL Time Unit = $RAPL_TIME_UNIT micro-seconds"
}

# Build CPU Package Topology
# Output:
#   CPU_TOPOLOGY: an array of packages each containing a list of CPUs
build_cpu_topology() {
  CPU_TOPOLOGY=()

  for ((i = 0; i < NUM_CPU_PACKAGES; i++)); do
    CPU_TOPOLOGY+=([$i]="")
  done

  for topo in $(grep . $CPU_SYSFS/cpu*/topology/physical_package_id); do
    pkg=$(echo "$topo" | cut -d":" -f2)
    cpu=$(echo "$topo" | cut -d"/" -f6)
    CPU_TOPOLOGY[$pkg]+="${cpu:3} "
  done

  for pkg in "${!CPU_TOPOLOGY[@]}"; do
    test_print_trc "Package $pkg has CPUs: ${CPU_TOPOLOGY[$pkg]}"
  done
}

# Check if the target machine is a server platform
is_server_platform() {
  local rc

  grep "dram" $RAPL_SYSFS_PATH/intel-rapl:*/name 2>&1
  rc=$?

  [[ $rc -eq 0 ]] && {
    NAMES=$(grep -E "package-([0-9]{1})" $RAPL_SYSFS_PATH/intel-rapl:*/name)
    PKG_NUM=$(awk -F- '{print $3}' <<<"$NAMES" | sort -n | tail -n1)
    MAX_PKG_NUM=$((PKG_NUM + 1))
    DIE_NUM=$(awk -F- '{print $NF}' <<<"$NAMES" | sort -n | tail -n1)
    MAX_DIE_NUM=$((DIE_NUM + 1))
  }

  return $rc
}

# RAPL_XS_FUNC_CHK_INTERFACE
rapl_check_interface() {
  test_print_trc "Check SYSFS - \"$RAPL_SYSFS_PATH\"intel-rapl..."
  [[ -d "$RAPL_SYSFS_PATH"/intel-rapl ]] ||
    die "Intel-RAPL SYSFS does not exist!"
  lines=$(grep . "$RAPL_SYSFS_PATH"/intel-rapl*/* 2>&1 |
    grep -v "Is a directory" | grep -v "No data available")
  for line in $lines; do
    test_print_trc "$line"
  done
}

# RAPL_XS_FUNC_CHK_PKG_DOMAIN
rapl_check_pkg_domain() {
  local domain_path="$RAPL_SYSFS_PATH/intel-rapl:"
  test_print_trc "Check SYSFS - \"$domain_path\"X..."

  if is_server_platform; then
    for ((i = 0; i < MAX_PKG_NUM; i++)); do
      for ((j = 0; j < MAX_DIE_NUM; j++)); do
        [[ -d "$domain_path""$i" ]] ||
          die "Intel-RAPL package domain folder does not exist!"
        grep -q "package-${i}-die-${j}" "${domain_path}${i}/name" ||
          test_print_trc "This server does not support package-${i}-die-${j}!"
      done
    done
  else
    for ((i = 0; i < NUM_CPU_PACKAGES; i++)); do
      [[ -d "$domain_path""$i" ]] ||
        die "Intel-RAPL package domain folder does not exist!"
      grep -q "package-${i}" "${domain_path}${i}/name" ||
        die "Intel-RAPL package domain name does not match!"
    done
  fi
  test_print_trc "\"$domain_path\"X existed!"
}

# RAPL_XS_FUNC_CHK_PSYS_DOMAIN
rapl_check_psys_domain() {
  local domain_path="$RAPL_SYSFS_PATH/intel-rapl:"
  test_print_trc "Check Platform domain sysfs - ${domain_path}X..."
  [[ -d "${domain_path}1" ]] ||
    block_test "Intel-RAPL Platform domain folder does not exist!"

  grep -q "psys" "${domain_path}1/name" ||
    block_test "Intel-RAPL Platform domain (aka Psys) does not exit!"
  test_print_trc "${domain_path}1/name psys file exists"
}

# RAPL_XS_FUNC_CHK_PP0_DOMAIN
rapl_check_pp0_domain() {
  local domain_path="$RAPL_SYSFS_PATH/intel-rapl:"
  test_print_trc "Check SYSFS - \"$domain_path\"X:0..."
  for ((i = 0; i < NUM_CPU_PACKAGES; i++)); do
    [[ -d "$domain_path""$i":0 ]] ||
      block_test "Intel-RAPL CPU domain folder does not exist!"
    grep -q "core" "${domain_path}${i}:0/name" ||
      block_test "Intel-RAPL CPU domain name does not match!"
  done
  test_print_trc "\"$domain_path\"X:0 existed!"
}

# RAPL_XS_FUNC_CHK_PP1_DOMAIN
rapl_check_pp1_domain() {
  local domain_path="$RAPL_SYSFS_PATH/intel-rapl:"
  test_print_trc "Check SYSFS - \"$domain_path\"X:1..."
  for ((i = 0; i < NUM_CPU_PACKAGES; i++)); do
    [[ -d "$domain_path""$i":1 ]] ||
      block_test "Intel-RAPL Graphic domain folder does not exist!"
    grep -q "uncore" "${domain_path}${i}:1/name" ||
      block_test "Intel-RAPL Graphic domain name does not match!"
  done
  test_print_trc "\"$domain_path\"X:1 existed!"
}

# RAPL_XS_FUNC_CHK_DRAM_DOMAIN
rapl_check_dram_domain() {
  domain_name=$(cat /sys/class/powercap/intel-rapl:*/*/name)
  test_print_trc "RAPL Domain name: $domain_name"
  [[ "$domain_name" =~ dram ]] ||
    block_test "intel_rapl DRAM domain folder does not exist!"
  test_print_trc "DRAM domain exists"
}

# RAPL_XS_FUNC_CHK_PKG_ENERGY_STATUS_MSR
rapl_check_pkg_energy_status_msr() {
  local pkg_energy_status_msr

  pkg_energy_status_msr=$(read_msr "" "$MSR_PKG_ENERGY_STATUS")
  test_print_trc "read_msr \"\" $MSR_PKG_ENERGY_STATUS"
  echo "$pkg_energy_status_msr"
  pkg_energy_status_msr=$(echo "$pkg_energy_status_msr" | awk -F"\"" END'{print $4}')
  pkg_energy_status_msr_10=$((16#${pkg_energy_status_msr}))

  if [[ "$pkg_energy_status_msr_10" -eq 0 ]]; then
    die "Your system failed to enable PKG RAPL ENERGY STATUS MSR: 0x611"
  fi
  test_print_trc "Your system enabled PKG RAPL ENERGY STATUS MSR 0x611 \
successfully: $pkg_energy_status_msr"
}

# RAPL_XS_FUNC_CHK_PSYS_ENERGY_STATUS_MSR
rapl_check_psys_domain_msr() {
  local psys_domain_msr

  psys_domain_msr=$(read_msr "31:0" "$MSR_PLATFORM_ENERGY_STATUS")
  test_print_trc "read_msr \"31:0\" $MSR_PLATFORM_ENERGY_STATUS"
  echo "$psys_domain_msr"
  psys_domain_msr=$(echo "$psys_domain_msr" | awk -F"\"" END'{print $4}')
  psys_domain_msr_10=$((16#${psys_domain_msr}))

  if [[ "$psys_domain_msr_10" -eq 0 ]]; then
    die "Your system failed to enable Platform RAPL Domain MSR: 0x64D"
  fi
  test_print_trc "Your system enabled Platform RAPL Domain MSR 0x64D \
successfully: $psys_domain_msr"
}

# RAPL_XS_FUNC_CHK_PKG_POWER_LIMIT_MSR
rapl_check_pkg_power_limit_msr() {
  local pkg_power_limit_msr

  pkg_power_limit_msr=$(read_msr "23:0" "$MSR_PKG_POWER_LIMIT")
  test_print_trc "The Package RAPL POWER LIMIT MSR 0x610 \"23:0\" shows value: $pkg_power_limit_msr"
  pkg_power_limit_msr=$(echo "$pkg_power_limit_msr" | awk -F"\"" END'{print $4}')
  pkg_power_limit_msr_10=$((16#${pkg_power_limit_msr}))

  if [[ "$pkg_power_limit_msr_10" -eq 0 ]]; then
    die "Your system failed to enable PKG RAPL POWER LIMIT MSR: 0x610"
  fi
  test_print_trc "Your system enabled PKG RAPL POWER LIMIT MSR 0x610 \
successfully: $pkg_power_limit_msr"
}

# Initialize RAPL
init_rapl() {
  clear_all_test_load
  read_rapl_unit
  build_cpu_topology
}

# intel_rapl power test function
# Input:
#    $1: Domain to be tested
rapl_power_check() {
  local domain=$1
  local cpu=""
  local power_limit_ori=""
  local power_limit_up=""
  local power_limit_down=100
  local power_limit_after=""
  local time_ori=""
  local limit=""
  local pl=$2
  local rc=""
  local sp=""

  domain=$(echo "$domain" | awk '{print tolower($0)}')
  [[ -n $domain ]] || "Please specify RAPL domain to be tested!"
  [[ $domain =~ (pkg|core|uncore|dram) ]] ||
    die "Invalid RAPL domain. Must be pkg|core|uncore|dram."

  if [[ $CHECK_ENERGY -eq 1 ]]; then
    for ((pkg = 0; pkg < NUM_CPU_PACKAGES; pkg++)); do
      cpu=$(echo "${CPU_TOPOLOGY[$pkg]}" | cut -d" " -f1)
      get_total_energy_consumed_msr "$cpu" "$domain"
      msr_energy=$CUR_ENERGY

      get_total_energy_consumed_sysfs "$pkg" "$domain"
      sysfs_energy=$CUR_ENERGY

      test_print_trc "MSR: $msr_energy, SYSFS: $sysfs_energy"

      diff=$(echo "scale=3;$msr_energy / $sysfs_energy * 100" | bc)
      diff=${diff%.*}
      [[ $diff -le 105 && $diff -ge 95 ]] ||
        die "The delta between MSR and SYSFS is exceeding 5% range: $diff"
    done
  elif [[ $CHECK_POWER_LOAD -eq 1 ]]; then
    # create display :1 for graphic tests
    if [[ $domain == "uncore" ]]; then
      do_cmd "startx -- :1 &> /dev/null &"
      sleep 5
    fi

    if is_server_platform; then
      for ((pkg = 0; pkg < NUM_CPU_PACKAGES; pkg++)); do
        sleep 20
        get_power_consumed_server "turbostat" "$pkg" "$domain" "$MEASURE_INTERVAL"
        [[ -n "$CUR_POWER" ]] || die "Fail to get current power(before)."
        power_b4=$CUR_POWER

        create_test_load "$domain"

        sleep 2
        get_power_consumed_server "turbostat" "$pkg" "$domain" "$MEASURE_INTERVAL"
        [[ -n "$CUR_POWER" ]] || die "Fail to get current power(after)."
        power_af=$CUR_POWER

        test_print_trc "Package-$pkg: $domain Power before workload: $power_b4 Watts"
        test_print_trc "Package-$pkg: $domain Power after workload: $power_af Watts"

        diff=$(echo "scale=3;$power_af / $power_b4 * 100" | bc)
        diff=${diff%.*}
        test_print_trc "Package-$pkg: $domain Power is increased by $diff percentage!"

        [[ $diff -gt 100 ]] || die "Package-$pkg: $domain no significant power increase after workload!"
        # Kill the workload if has
        clear_all_test_load
      done
    else
      for ((pkg = 0; pkg < NUM_CPU_PACKAGES; pkg++)); do
        sleep 20
        get_power_consumed "turbostat" "$pkg" "$domain" "$MEASURE_INTERVAL"
        [[ -n "$CUR_POWER" ]] || die "Fail to get current power(before)."
        power_b4=$CUR_POWER

        create_test_load "$domain"

        sleep 2
        get_power_consumed "turbostat" "$pkg" "$domain" "$MEASURE_INTERVAL"
        [[ -n "$CUR_POWER" ]] || die "Fail to get current power(after)."
        power_af=$CUR_POWER

        test_print_trc "Package-$pkg: $domain Power before workload: $power_b4 Watts"
        test_print_trc "Package-$pkg: $domain Power after workload: $power_af Watts"

        diff=$(echo "scale=3;$power_af / $power_b4 * 100" | bc)
        diff=${diff%.*}
        test_print_trc "Package-$pkg: $domain Power is increased by $diff percentage!"

        [[ $diff -gt 100 ]] || die "Package-$pkg: $domain no significant power increase after workload!"
        # Kill the workload if has
        clear_all_test_load
      done
    fi
  elif [[ $CHECK_POWER_LIMIT -eq 1 ]]; then
    # Judge whether power limit is unlocked or not in BIOS
    # Skip this case if BIOS locked pkg or core power limit change

    if power_limit_unlock_check "$domain"; then
      for ((pkg = 0; pkg < NUM_CPU_PACKAGES; pkg++)); do
        # Save the original power limit and time value
        get_domain_path "$pkg" "$domain"
        client_domain=$(cat "$DOMAIN_PATH"/name)
        [[ "$client_domain" != psys ]] || break
        test_print_trc "Original $domain sysfs path: $DOMAIN_PATH"
        power_limit_ori="$(cat "$DOMAIN_PATH"/constraint_0_power_limit_uw)"
        time_ori="$(cat "$DOMAIN_PATH"/constraint_0_power_limit_uw)"
        test_print_trc "Original $domain power limit: $power_limit_ori uwatts"

        # Set the power limit and time value
        echo "Received power limit test value: $pl percentage"
        limit=$(("$pl" * "$power_limit_ori" / 100))
        test_print_trc "Real Power limit test value: $limit uwatts"
        power_limit_up=$((10 * "$power_limit_ori" / 100))
        time_win=1000000
        set_power_limit "$pkg" "$domain" "$limit" "$time_win"

        # Run workload to get rapl domain power watt after setting power limit
        create_test_load "$domain"
        sleep 2

        if is_server_platform; then
          sp=$(("$pkg" + 3))
          do_cmd "turbostat --quiet --show Package,Core,PkgWatt -o tc.log sleep 1"
          test_print_trc "Server turbostat log:"
          cat tc.log
          if [[ $NUM_CPU_PACKAGES -eq 1 ]]; then
            power_limit_after="$(awk '{print $2}' tc.log | sed '/^\s*$/d' |
              sed -n ''"$sp"',1p')"
          else
            power_limit_after="$(awk '{print $3}' tc.log | sed '/^\s*$/d' |
              sed -n ''"$sp"',1p')"
          fi
          test_print_trc "Server power limit after: $power_limit_after"
          [[ -n "$power_limit_after" ]] ||
            die "Fail to get current power from server turbostat"
          power_limit_after="$(echo "scale=2;$power_limit_after * 1000000" | bc)"
        else
          get_power_consumed_server "turbostat" "$pkg" "$domain" "$MEASURE_INTERVAL"
          test_print_trc "$domain power after setting limit: $CUR_POWER watts"
          [[ -n "$CUR_POWER" ]] || die "Fail to get current power from turbostat"
          power_limit_after="$(echo "scale=2;$CUR_POWER * 1000000" | bc)"
        fi
        power_limit_after="${power_limit_after%.*}"
        clear_all_test_load

        # Restore the power limit value to origin
        set_power_limit "$pkg" "$domain" "$power_limit_ori" "$time_ori"

        test_print_trc "Original power limit value: $power_limit_ori uwatts"
        test_print_trc "Configured power limit value: $limit uwatts"
        test_print_trc "After setting power limit value: $power_limit_after uwatts"
        delta=$(("$limit" - "$power_limit_after"))
        if [[ $delta -lt 0 ]]; then
          delta=$((0 - "$delta"))
        fi
        test_print_trc "The delta power after setting limit: $delta uwatts"

        # The accepted pkg watts error range is 100 uwatts to 10% of TDP
        if [[ "$delta" -gt "$power_limit_down" ]] &&
          [[ "$delta" -lt "$power_limit_up" ]]; then
          test_print_trc "Setting RAPL $domain rapl power limit to $pl is PASS"
        else
          die "The power gap after setting limit to $pl percentage: $delta uwatts"
        fi
      done
    else
      block_test "$domain power limit is locked by BIOS, block this case."
    fi
  else
    die "Test type is empty! Please specific energy or power tests!"
  fi
}

# Function to check any error after power limit change and rapl control enable
enable_rapl_control() {
  domain_num=$(ls /sys/class/powercap/ | grep -c intel-rapl:)
  [[ -n "$domain_num" ]] || block_test "intel-rapl sysfs is not available."

  for ((i = 1; i <= domain_num; i++)); do
    domain_name=$(ls /sys/class/powercap/ | grep intel-rapl: | sed -n "$i,1p")
    # Change each domain's power limit setting then enable the RAPL control

    default_power_limit=$(cat /sys/class/powercap/"$domain_name"/constraint_0_max_power_uw)
    if [[ "$default_power_limit" -eq 0 ]]; then
      continue
    else
      test_power_limit=$(("$default_power_limit" - 2000000))
      test_print_trc "Test power limit is: $test_power_limit uw"
    fi
    do_cmd "echo $test_power_limit > /sys/class/powercap/$domain_name/constraint_0_power_limit_uw"
    do_cmd "echo 1 > /sys/class/powercap/$domain_name/enabled"
    enabled_knob=$(cat /sys/class/powercap/"$domain_name"/enabled)
    # Recover the default constraint_0_power_limit_uw setting
    do_cmd "echo $default_power_limit > /sys/class/powercap/$domain_name/constraint_0_power_limit_uw"
    if [[ "$enabled_knob" -eq 1 ]]; then
      test_print_trc "Enabling RAPL control for $domain_name is PASS after power limit change."
    else
      die "Enabling RAPL control for $domain_name is Fail after power limit change"
    fi
  done
}

# Function to compare supported domain names among sysfs, perf and turbostat tool
rapl_perf_name_compare() {
  local driver_name=$1

  sysfs_names=$(cat /sys/class/powercap/"$driver_name":*/name 2>&1)
  test_print_trc "sysfs domain name: $sysfs_names"
  perf_names=$(perf list | grep energy 2>&1)
  test_print_trc "Perf event name: $perf_names"
  energy_event_sysfs=$(ls /sys/devices/power/events/ 2>&1)
  test_print_trc "Perf sysfs events:$energy_event_sysfs"
  turbostat_names=$(turbostat -q --show power sleep 1 2>&1)
  test_print_trc "Turbostat log: $turbostat_names"

  sysfs_rapl_num=$(cat /sys/class/powercap/"$driver_name":*/name | wc -l 2>&1)
  perf_name_num=$(perf list | grep -c energy 2>&1)
  # Take RAPL sysfs domain as base, if perf energy name number
  # Is not aligned with sysfs, then fail the case
  [[ -n "$sysfs_names" ]] || block_test "RAPL sysfs does not exist: $sysfs_names"
  [[ -n "$perf_names" ]] || block_test "Did not get RAPL event by perf list:\
  $energy_event_sysfs"
  if [[ "$sysfs_rapl_num" -eq "$perf_name_num" ]]; then
    test_print_trc "RAPL domain number is aligned between sysfs and perf"
  else
    # Here will not die because perf list cannot display --per-socket energy value on server
    # So the rapl domain cannot compare between perf list tool and sysfs on server, only
    # Print the message, but not fail.
    test_print_trc "RAPL domain number is not aligned between sysfs and perf. \
sysfs shows: $sysfs_names, perf event shows:$perf_names"
  fi

  # Check sysfs,perf,turbostat tool RAPL domain name, take sysfs as base
  for ((i = 1; i <= sysfs_rapl_num; i++)); do
    sysfs_name=$(cat /sys/class/powercap/"$driver_name":*/name | sed -n "$i,1p")
    test_print_trc "RAPL Domain test name: $sysfs_name"
    if [[ $sysfs_name =~ package ]] && [[ $perf_names =~ pkg ]] &&
      [[ $turbostat_names =~ PkgWatt ]]; then
      test_print_trc "Package domain name is aligned among sysfs,perf and turbostat tool"
    elif [[ $sysfs_name =~ core ]] && [[ $perf_names =~ core ]] &&
      [[ $turbostat_names =~ CorWatt ]]; then
      test_print_trc "Core domain name is aligned among sysfs,perf and turbostat tool"
    elif [[ $sysfs_name =~ uncore ]] && [[ $perf_names =~ gpu ]] &&
      [[ $turbostat_names =~ GFXWatt ]]; then
      test_print_trc "Uncore(GFX) domain name is aligned among sysfs,perf and turbostat tool"
    elif [[ $sysfs_name =~ dram ]] && [[ $perf_names =~ ram ]] &&
      [[ $turbostat_names =~ RAMWatt ]]; then
      test_print_trc "Dram domain name is aligned among sysfs,perf and turbostat tool"
    elif [[ $sysfs_name =~ psys ]] && [[ $perf_names =~ psys ]]; then
      test_print_trc "Turbostat will not show psys, but sysfs and perf shows up, it's expected."
    else
      die "There is a domain name exception among sysfs, perf and turbostat comparing\
sysfs names: $sysfs_names, perf names: $perf_names, turbostat_name: $turbostat_names"
    fi
  done
}

# Function to check supported domain energy joules between sysfs and perf tool
# when workload is running
rapl_perf_energy_compare() {
  local driver_name=$1
  local load=$2
  local load=$3
  local option
  local j=0
  local p=0
  local pkg0=package-0
  local pkg1=package-1

  sysfs_names=$(cat /sys/class/powercap/"$driver_name":*/name 2>&1)
  sysfs_rapl_num=$(cat /sys/class/powercap/"$driver_name":*/name | wc -l 2>&1)
  perf_names=$(perf list | grep energy 2>&1)
  perf_name_num=$(perf list | grep -c energy 2>&1)
  [[ -n $sysfs_names ]] || block_test "Please check if rapl driver loaded or not."
  [[ -n $perf_names ]] || block_test "Did not get RAPL event by perf list"

  # Read MSR RAW data before sleep
  # Package MSR is: 0x611
  # Core MSR is: 0x639
  # Psys MSR is: 0x64d
  # Dram MSR is: 0x619
  for ((i = 1; i <= sysfs_rapl_num; i++)); do
    sysfs_name=$(cat /sys/class/powercap/"$driver_name":*/name | sed -n "$i,1p" 2>&1)
    if [[ $sysfs_name =~ package ]]; then
      msr_raw_bf=$(rdmsr -f 31:0 $MSR_PKG_ENERGY_STATUS)
      test_print_trc "$sysfs_name MSR RAW value before: $msr_raw_bf"
    elif [[ $sysfs_name =~ core ]]; then
      msr_raw_bf=$(rdmsr -f 31:0 $MSR_PP0_ENERGY_STATUS)
      test_print_trc "$sysfs_name MSR RAW value before: $msr_raw_bf"
    elif [[ $sysfs_name =~ psys ]]; then
      msr_raw_bf=$(rdmsr -f 31:0 $MSR_PLATFORM_ENERGY_STATUS)
      test_print_trc "$sysfs_name MSR RAW value before: $msr_raw_bf"
    elif [[ $sysfs_name =~ dram ]]; then
      msr_raw_bf=$(rdmsr -f 31:0 $MSR_DRAM_ENERGY_STATUS)
      test_print_trc "$sysfs_name MSR RAW value before: $msr_raw_bf"
    fi
  done

  load=$(echo "$load" | awk '{print tolower($0)}')
  case $load in
  pkg | core)
    cpu_avail=$(grep processor /proc/cpuinfo | tail -1 | awk '{print $NF}')
    cpu_test=$(("$cpu_avail" + 1))
    do_cmd "stress -c $cpu_test -t 60 > /dev/null &"
    ;;
  uncore)
    which "$GPU_LOAD" &>/dev/null || die "glxgears does not exist"
    do_cmd "$GPU_LOAD $GPU_LOAD_ARG > /dev/null &"
    ;;
  dram)
    which "stress" &>/dev/null || die "stress does not exist"
    mem_avail=$(grep MemAvailable /proc/meminfo | awk -F " " '{print $2}')
    mem_test=$(echo "$mem_avail"/10000000 | bc)
    do_cmd "stress --vm $mem_test --vm-bytes 1024M -t 30 > /dev/null &"
    ;;
  *)
    test_print_trc "Will not run workload but idle!"
    do_cmd "sleep 20"
    ;;
  esac

  LOAD_PID=$!

  # Read sysfs energy value before sleep
  sysfs_energy_uj_bf=$(cat /sys/class/powercap/"$driver_name":*/energy_uj 2>&1)
  test_print_trc "Sysfs energy events before:$sysfs_energy_uj_bf"
  # Sleep 20 seconds to capture the RAPL energy value
  for ((i = 1; i <= perf_name_num; i++)); do
    perf_name=$(echo "$perf_names" | awk '{print $1}' | sed -n "$i, 1p" 2>&1)
    test_print_trc "perf event name: $perf_name"
    option="$option -e $perf_name"
    test_print_trc "option name: $option"
  done
  do_cmd "perf stat -o out.txt --per-socket $option sleep 20"
  sysfs_energy_uj_af=$(cat /sys/class/powercap/"$driver_name":*/energy_uj 2>&1)

  # Print the logs after sleep
  test_print_trc "Sysfs domain name after: $sysfs_names"
  test_print_trc "Sysfs energy events after: $sysfs_energy_uj_af"
  test_print_trc "Perf energy events log:"
  do_cmd "cat out.txt"
  # Kill the workload if has
  clear_all_test_load

  # Calculate each energy delta in past 20 seconds idle, the unit is Joules
  for ((i = 1; i <= sysfs_rapl_num; i++)); do
    sysfs_name=$(cat /sys/class/powercap/"$driver_name":*/name | sed -n "$i,1p" 2>&1)
    sysfs_energy_uj_bf_per_domain=$(echo "$sysfs_energy_uj_bf" | sed -n "$i,1p")
    test_print_trc "Sysfs energy uj before for domain name $sysfs_name is: $sysfs_energy_uj_bf_per_domain"
    sysfs_energy_uj_af_per_domain=$(echo "$sysfs_energy_uj_af" | sed -n "$i,1p")
    test_print_trc "Sysfs energy uj after for domain name $sysfs_name is: $sysfs_energy_uj_af_per_domain"
    if [[ $sysfs_name =~ package ]]; then
      msr_raw_af=$(rdmsr -f 31:0 $MSR_PKG_ENERGY_STATUS)
      test_print_trc "$sysfs_name MSR RAW value after: $msr_raw_af"
    elif [[ $sysfs_name =~ core ]]; then
      msr_raw_af=$(rdmsr -f 31:0 $MSR_PP0_ENERGY_STATUS)
      test_print_trc "$sysfs_name MSR RAW value after: $msr_raw_af"
    elif [[ $sysfs_name =~ psys ]]; then
      msr_raw_af=$(rdmsr -f 31:0 $MSR_PLATFORM_ENERGY_STATUS)
      test_print_trc "$sysfs_name MSR RAW value after: $msr_raw_af"
    elif [[ $sysfs_name =~ dram ]]; then
      msr_raw_af=$(rdmsr -f 31:0 $MSR_DRAM_ENERGY_STATUS)
      test_print_trc "$sysfs_name MSR RAW value after: $msr_raw_af"
    fi
    sysfs_energy_delta_uj=$(echo "scale=2; $sysfs_energy_uj_af_per_domain-$sysfs_energy_uj_bf_per_domain" | bc)
    test_print_trc "Sysfs energy delta ujoules for $sysfs_name is: $sysfs_energy_delta_uj"
    sysfs_energy_delta_j=$(echo "scale=2; $sysfs_energy_delta_uj/1000000" | bc)
    test_print_trc "Sysfs energy delta joules for $sysfs_name is: $sysfs_energy_delta_j"

    # Calculate perf energy delta, which is directly reading from perf log
    if ! counter=$(grep energy out.txt | awk '{print $3}'); then
      block_test "Did not get energy $sysfs_name counter: $counter"
    else
      [[ $sysfs_name =~ dram ]] &&
        perf_energy_j=$(grep energy-ram out.txt | grep S$j | awk '{print $3}' 2>&1) &&
        j=$(("$j" + 1))
      # Use j variable to judge how many dram domain name, initial value is 0
      [[ $sysfs_name == "$pkg0" ]] &&
        perf_energy_j=$(grep "energy-pkg" out.txt | grep S0 | awk '{print $3}' 2>&1)
      [[ $sysfs_name == "$pkg1" ]] &&
        perf_energy_j=$(grep "energy-pkg" out.txt | grep S1 | awk '{print $3}' 2>&1)
      [[ $sysfs_name =~ core ]] &&
        perf_energy_j=$(grep "energy-cores" out.txt | grep S0 | awk '{print $3}' 2>&1)
      [[ $sysfs_name =~ uncore ]] &&
        perf_energy_j=$(grep "energy-gpu" out.txt | grep S0 | awk '{print $3}' 2>&1)
      [[ $sysfs_name =~ psys ]] &&
        perf_energy_j=$(grep "energy-psys" out.txt | grep S$p | awk '{print $3}' 2>&1) &&
        p=$(("$p" + 1))
      # Use p variable to judge how many psys domain name, initial value is 0
      # Perf tool will display 1,000 for 1000, so need to remove ","
      perf_energy_j_modify=${perf_energy_j/,/}
      test_print_trc "Perf energy joules for $sysfs_name is: $perf_energy_j_modify"
    fi

    # Compare the sysfs_energy and perf_energy value
    energy_delta_j=$(awk -v x="$sysfs_energy_delta_j" -v y="$perf_energy_j_modify" \
      'BEGIN{printf "%.1f\n", x-y}')
    test_print_trc "The domain $sysfs_name energy delta joules between sysfs and perf event is:$energy_delta_j"

    #Set the error deviation is 20% of sysfs energy Joules
    energy_low_j=$(echo "scale=2; 20*$sysfs_energy_delta_j/100" | bc)
    energy_low_j=$(echo "scale=2; $sysfs_energy_delta_j-$energy_low_j" | bc)
    test_print_trc "The low energy error deviation is:$energy_low_j"
    energy_high_j=$(echo "scale=2; $sysfs_energy_delta_j+$energy_low_j" | bc)
    test_print_trc "The high energy error deviation is:$energy_high_j"
    if [[ $(echo "$perf_energy_j_modify < $energy_high_j" | bc -l) ]] &&
      [[ $(echo "$perf_energy_j_modify > $energy_low_j" | bc -l) ]]; then
      test_print_trc "The domain $sysfs_name energy delta between sysfs and perf event \
is within 20% of sysfs energy joules gap"
    elif [[ $(echo "$perf_energy_j_modify == 0" | bc -l) ]]; then
      test_print_trc "The domain $sysfs_name energy shows 0, if GFX related, it may be expected"
    else
      die "The domain $sysfs_name energy delta between sysfs and perf event is \
beyond 20% of sysfs energy joules gap: $energy_delta_j"
    fi
  done
}

# Function to check supported domain energy joules between sysfs and turbostat tool
# when workload is running
rapl_turbostat_energy_compare() {
  local driver_name=$1
  local load=$2
  local load=$3
  local j=3
  local pkg0=package-0
  local pkg1=package-1
  local corename=core
  local uncorename=uncore
  local dramname=dram
  local psysname=psys

  sysfs_names=$(cat /sys/class/powercap/"$driver_name":*/name 2>&1)
  sysfs_rapl_num=$(cat /sys/class/powercap/"$driver_name":*/name | wc -l 2>&1)
  [[ -n $sysfs_names ]] || block_test "Please check if rapl driver loaded or not"

  # Read MSR RAW data before sleep
  # Package MSR is: 0x611
  # Core MSR is: 0x639
  # Psys MSR is: 0x64d
  # Dram MSR is: 0x619
  for ((i = 1; i <= sysfs_rapl_num; i++)); do
    sysfs_name=$(cat /sys/class/powercap/"$driver_name":*/name | sed -n "$i,1p" 2>&1)
    if [[ $sysfs_name =~ package ]]; then
      msr_raw_bf=$(rdmsr -f 31:0 $MSR_PKG_ENERGY_STATUS)
      test_print_trc "$sysfs_name MSR RAW value before: $msr_raw_bf"
    elif [[ $sysfs_name =~ core ]]; then
      msr_raw_bf=$(rdmsr -f 31:0 $MSR_PP0_ENERGY_STATUS)
      test_print_trc "$sysfs_name MSR RAW value before: $msr_raw_bf"
    elif [[ $sysfs_name =~ psys ]]; then
      msr_raw_bf=$(rdmsr -f 31:0 $MSR_PLATFORM_ENERGY_STATUS)
      test_print_trc "$sysfs_name MSR RAW value before: $msr_raw_bf"
    elif [[ $sysfs_name =~ dram ]]; then
      msr_raw_bf=$(rdmsr -f 31:0 $MSR_DRAM_ENERGY_STATUS)
      test_print_trc "$sysfs_name MSR RAW value before: $msr_raw_bf"
    fi
  done

  load=$(echo "$load" | awk '{print tolower($0)}')
  case $load in
  pkg | core)
    cpu_avail=$(grep processor /proc/cpuinfo | tail -1 | awk '{print $NF}')
    cpu_test=$(("$cpu_avail" + 1))
    do_cmd "stress -c $cpu_test -t 60 > /dev/null &"
    ;;
  uncore)
    which "$GPU_LOAD" &>/dev/null || die "glxgears does not exist"
    do_cmd "$GPU_LOAD $GPU_LOAD_ARG > /dev/null &"
    ;;
  dram)
    which "stress" &>/dev/null || die "stress does not exist"
    mem_avail=$(grep MemAvailable /proc/meminfo | awk -F " " '{print $2}')
    mem_test=$(echo "$mem_avail"/10000000 | bc)
    do_cmd "stress --vm $mem_test --vm-bytes 1024M -t 90 > /dev/null &"
    ;;
  *)
    test_print_trc "Will not run workload but idle!"
    do_cmd "sleep 20"
    ;;
  esac

  LOAD_PID=$!

  # Read sysfs energy value before sleep
  sysfs_energy_uj_bf=$(cat /sys/class/powercap/"$driver_name":*/energy_uj 2>&1)
  test_print_trc "Sysfs energy events before:$sysfs_energy_uj_bf"

  # Sleep 20 seconds to capture the RAPL energy value
  tc_out=$(turbostat -q --show power -i 1 sleep 20 2>&1)
  sysfs_energy_uj_af=$(cat /sys/class/powercap/"$driver_name":*/energy_uj 2>&1)

  # Print the logs after sleep
  test_print_trc "Sysfs domain name after: $sysfs_names"
  test_print_trc "Sysfs energy events after: $sysfs_energy_uj_af"
  test_print_trc "Turbostat output: $tc_out"
  # Kill the workload if has
  [[ -z "$LOAD_PID" ]] || do_cmd "kill -9 $LOAD_PID"

  # Calculate each energy delta in past 20 seconds idle, the unit is Joules
  for ((i = 1; i <= sysfs_rapl_num; i++)); do
    sysfs_name=$(cat /sys/class/powercap/"$driver_name":*/name | sed -n "$i,1p" 2>&1)
    sysfs_energy_uj_bf_per_domain=$(echo "$sysfs_energy_uj_bf" | sed -n "$i,1p")
    test_print_trc "Sysfs energy uj before for domain name $sysfs_name is: $sysfs_energy_uj_bf_per_domain"
    sysfs_energy_uj_af_per_domain=$(echo "$sysfs_energy_uj_af" | sed -n "$i,1p")
    test_print_trc "Sysfs energy uj after for domain name $sysfs_name is: $sysfs_energy_uj_af_per_domain"
    if [[ $sysfs_name =~ package ]]; then
      msr_raw_af=$(rdmsr -f 31:0 $MSR_PKG_ENERGY_STATUS)
      test_print_trc "$sysfs_name MSR RAW value after: $msr_raw_af"
    elif [[ $sysfs_name =~ core ]]; then
      msr_raw_af=$(rdmsr -f 31:0 $MSR_PP0_ENERGY_STATUS)
      test_print_trc "$sysfs_name MSR RAW value after: $msr_raw_af"
    elif [[ $sysfs_name =~ psys ]]; then
      msr_raw_af=$(rdmsr -f 31:0 $MSR_PLATFORM_ENERGY_STATUS)
      test_print_trc "$sysfs_name MSR RAW value after: $msr_raw_af"
    elif [[ $sysfs_name =~ dram ]]; then
      msr_raw_af=$(rdmsr -f 31:0 $MSR_DRAM_ENERGY_STATUS)
      test_print_trc "$sysfs_name MSR RAW value after: $msr_raw_af"
    fi
    sysfs_energy_delta_uj=$(echo "scale=2; $sysfs_energy_uj_af_per_domain-$sysfs_energy_uj_bf_per_domain" | bc)
    test_print_trc "Sysfs energy delta ujoules for $sysfs_name is: $sysfs_energy_delta_uj"
    sysfs_energy_delta_j=$(echo "scale=2; $sysfs_energy_delta_uj/1000000" | bc)
    test_print_trc "Sysfs energy delta joules for $sysfs_name is: $sysfs_energy_delta_j"

    # Calculate energy delta from turbostat tool, which unit is Watts
    # Joules=Watts * Seconds
    [[ -n "$tc_out" ]] || block_test "Did not get turbostat log"
    if [[ $sysfs_name == "$pkg0" ]]; then
      turbostat_watts=$(echo "$tc_out" | awk '{print $3}' | sed '/^$/d' | sed -n '3,1p' 2>&1)
      test_print_trc "Turbostat watts for $sysfs_name is: $turbostat_watts"
    elif [[ $sysfs_name == "$pkg1" ]]; then
      turbostat_watts=$(echo "$tc_out" | awk '{print $3}' | sed '/^$/d' | sed -n '4,1p' 2>&1)
      test_print_trc "Turbostat watts for $sysfs_name is: $turbostat_watts"
    elif [[ $sysfs_name == "$corename" ]]; then
      turbostat_watts=$(echo "$tc_out" | awk '{$1 = "";print $0}' | sed '/^$/d' |
        awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' |
        grep "CorWatt" | awk -F " " '{print $3}')
      test_print_trc "Turbostat watts for $sysfs_name is: $turbostat_watts"
    elif [[ $sysfs_name == "$uncorename" ]]; then
      turbostat_watts=$(echo "$tc_out" | awk '{$1 = "";print $0}' | sed '/^$/d' |
        awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' |
        grep "GFXWatt" | awk -F " " '{print $3}')
      test_print_trc "Turbostat watts for $sysfs_name is: $turbostat_watts"
    elif [[ $sysfs_name == "$dramname" ]]; then
      turbostat_watts=$(echo "$tc_out" | awk '{$1 = "";print $0}' | sed '/^$/d' |
        awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' |
        grep "RAMWatt" | awk -F " " -v p=$j '{print $p}')
      j=$(("$j" + 1))
      test_print_trc "Turbostat watts for $sysfs_name is: $turbostat_watts"
    elif [[ "$sysfs_name" == "$psysname" ]]; then
      test_print_trc "The turbostat tool does not support $sysfs_name energy value."
      break
    else
      die "Turbostat tool did not find matched RAPL domain name."
    fi
    turbostat_joules=$(echo "scale=2; $turbostat_watts*20" | bc)
    test_print_trc "Turbostat joules for $sysfs_name is: $turbostat_joules"

    # Compare the sysfs_energy and turbostat tool energy value
    energy_delta_j=$(awk -v x="$sysfs_energy_delta_j" -v y="$turbostat_joules" \
      'BEGIN{printf "%.1f\n", x-y}')
    test_print_trc "The domain $sysfs_name energy delta joules between sysfs\
and turbostat tool is:$energy_delta_j"

    # Set the error deviation is 20% of sysfs energy Joules
    energy_low_j=$(echo "scale=2; 20*$sysfs_energy_delta_j/100" | bc)
    energy_low_j=$(echo "scale=2; $sysfs_energy_delta_j-$energy_low_j" | bc)
    test_print_trc "The low energy error deviation is:$energy_low_j"
    energy_high_j=$(echo "scale=2; $sysfs_energy_delta_j+$energy_low_j" | bc)
    test_print_trc "The high energy error deviation is:$energy_high_j"
    if [[ $(echo "$turbostat_joules < $energy_high_j" | bc -l) ]] &&
      [[ $(echo "$turbostat_joules > $energy_low_j" | bc -l) ]]; then
      test_print_trc "The domain $sysfs_name energy delta between sysfs and turbostat tool \
is within 20% of sysfs energy joules gap"
    elif [[ $(echo "$turbostat_joules == 0" | bc -l) ]]; then
      test_print_trc "The domain $sysfs_name energy shows 0, if GFX related, it may be expected"
    else
      die "The domain $sysfs_name energy delta between sysfs and turbostat tool is \
beyond 20% of sysfs energy joules gap: $energy_delta_j"
    fi
  done
}

# Function to verify if 0x601 (PL4) will change after RAPL control enable and disable
# Also PL1/PL2 power limit value change will not impact PL4
# Meanwhile judge if RAPL control disable expected or not
# PL1 is mapping constraint_0 (long term)
# PL2 is mapping constraint_1 (short term)
# PL4 is mapping constraint_2 (peak power)
# Linux does not support PL3
rapl_control_enable_disable_pl() {
  local pl_id=$1

  domain_num=$(ls /sys/class/powercap/ | grep -c intel-rapl:)
  [[ -n "$domain_num" ]] || block_test "intel-rapl sysfs is not available."

  for ((i = 1; i <= domain_num; i++)); do
    domain_name=$(ls /sys/class/powercap/ | grep intel-rapl: | sed -n "$i,1p")
    test_print_trc "------Testing domain name: $domain_name------"

    # Read default PL4, PL1, PL2 value
    pl4_default=$(rdmsr 0x601)
    [[ -n "$pl4_default" ]] && test_print_trc "PL4 value before RAPL Control enable and disable: $pl4_default"

    pl1_default=$(cat /sys/class/powercap/"$domain_name"/constraint_0_max_power_uw)
    [[ -n "$pl1_default" ]] && test_print_trc "PL1 value before RAPL Control enable and disable: $pl1_default"

    pl2_default=$(cat /sys/class/powercap/"$domain_name"/constraint_1_max_power_uw)
    [[ -n "$pl2_default" ]] && test_print_trc "PL2 value before RAPL Control enable and disable: $pl2_default"

    # Enable RAPL control
    do_cmd "echo 1 > /sys/class/powercap/$domain_name/enabled"
    enabled_knob=$(cat /sys/class/powercap/"$domain_name"/enabled)
    if [[ "$enabled_knob" -eq 1 ]]; then
      test_print_trc "Enabling RAPL control for $domain_name is PASS"
    else
      die "Enabling RAPL control for $domain_name is Fail"
    fi

    # Change each domain's $pl_id power limit setting then enable the RAPL control
    default_power_limit=$(cat /sys/class/powercap/"$domain_name"/constraint_"$pl_id"_max_power_uw)
    [[ -n "$default_power_limit" ]] && test_print_trc "Domain $domain_name's constraint_'$pl_id'_max_power_uw \
default value is: $default_power_limit"
    # Use package PL1 to judge SUT is client or Server
    # Usually the largest PL1 for Client Desktop is 125 Watts, Client mobile PL1 will be 9/15/45/65 Watts etc.
    pl1_edge=$(cat /sys/class/powercap/intel-rapl/intel-rapl:0/constraint_0_max_power_uw)
    [[ -n "$pl1_edge" ]] || block_test "Package PL1 power value is not available."
    if [[ $pl1_edge -le 125000000 ]]; then
      test_print_trc "The SUT should be client:"
      if [[ "$default_power_limit" -eq 0 ]]; then
        test_power_limit=$(("$default_power_limit" + 10000000))
        test_print_trc "Test power limit is: $test_power_limit uw"
      else
        test_power_limit=$(("$default_power_limit" - 5000000))
        [[ $test_power_limit -lt 0 ]] && test_power_limit=0
        test_print_trc "Test power limit is: $test_power_limit uw"
      fi
    else
      test_print_trc "The SUT should be server:"
      if [[ "$default_power_limit" -eq 0 ]]; then
        test_power_limit=$(("$default_power_limit" + 100000000))
        test_print_trc "Test power limit is: $test_power_limit uw"
      else
        test_power_limit=$(("$default_power_limit" - 100000000))
        [[ $test_power_limit -lt 0 ]] && test_power_limit=0
        test_print_trc "Test power limit is: $test_power_limit uw"
      fi
    fi
    [[ -d /sys/class/powercap/"$domain_name"/constraint_"$pl_id"_power_limit_uw ]] &&
      echo "$test_power_limit" >/sys/class/powercap/"$domain_name"/constraint_"$pl_id"_power_limit_uw

    # Recover the default constraint_$pl_id_power_limit_uw setting
    [[ -d /sys/class/powercap/"$domain_name"/constraint_"$pl_id"_power_limit_uw ]] &&
      echo "$default_power_limit" >/sys/class/powercap/"$domain_name"/constraint_"$pl_id"_power_limit_uw

    # Disable RAPL control
    do_cmd "echo 0 > /sys/class/powercap/$domain_name/enabled"
    disabled_knob=$(cat /sys/class/powercap/"$domain_name"/enabled)

    # Get Enable power limit value by reading 0x610 bit 15
    enable_power_limit=$(rdmsr 0x610 -f 15:15)
    test_print_trc "Enable RAPL Limit shows: $enable_power_limit"

    # Check if RAPL control disable works as expected
    if [[ $disabled_knob -eq 0 ]]; then
      test_print_trc "RAPL Control is not expected to be set to 0."
    elif [[ $enable_power_limit -eq 0 ]]; then
      die "System allows to disable PL, while writing RAPL control disable fail."
    else
      # Trying to manually write 0x610 bit 15 to 0
      # If it can't be set then you are OK as system is not allowing to disable PL1.
      # But wrmsr can write bit 15 to 0 and enabled is still 1, then this is a bug
      change_bit15=$(wrmsr 0x610 $(($(rdmsr -d 0x610) & ~(1 << 15))))
      test_print_trc "Verify if 0x610 bit 15 can be set to 0: $change_bit15"
      read_bit15=$(rdmsr 0x610 -f 15:15)
      if [[ $read_bit15 -eq 0 ]]; then
        die "0x610 bit 15 can change to 0, while RAPL control disable still 1."
      else
        test_print_trc "0x610 bit 15 cannot change to 0, so RAPL control enable shows 1 is expected."
      fi
    fi

    # Check if PL4 value changed after RAPL control enable and disable
    pl4_test=$(rdmsr 0x601)
    test_print_trc "PL4 value after RAPL Control enable and disable: $pl4_test"
    if [[ "$pl4_test" == "$pl4_default" ]]; then
      test_print_trc "PL4 shows the same value as default after RAPL Control enable and disable"
    else
      die "PL4 value changed after RAPL Control enable and disable: $pl4_test"
    fi

    # Check if PL1 value changed after RAPL control enable and disable
    pl1_recovered=$(cat /sys/class/powercap/"$domain_name"/constraint_0_max_power_uw)
    if [[ -z "$pl1_default" ]]; then
      test_print_trc "constraint_0_max_power_uw is not available for $domain_name"
    elif [[ "$pl1_recovered" == "$pl1_default" ]]; then
      test_print_trc "PL1 shows the same value as default after RAPL Control enable and disable"
    else
      die "PL1 value changed after RAPL Control enable and disable: $pl1_recovered"
    fi

    # Check if PL2 value changed after RAPL control enable and disable
    pl2_recovered=$(cat /sys/class/powercap/"$domain_name"/constraint_1_max_power_uw)
    if [[ -z "$pl2_default" ]]; then
      test_print_trc "constraint_1_max_power_uw is not available for $domain_name"
    elif [[ "$pl2_recovered" == "$pl2_default" ]]; then
      test_print_trc "PL2 shows the same value as default after RAPL Control enable and disable"
    else
      die "PL2 value changed after RAPL Control enable and disable: $pl2_recovered"
    fi

    # Re-enable RAPL control
    do_cmd "echo 1 > /sys/class/powercap/$domain_name/enabled"

  done
}

# Function to change 0x601 (PL4) value and RAPL control enable and disable
# Meanwhile judge if RAPL control disable expected or not
rapl_control_enable_disable_pl4() {
  local test_pl4=$1

  domain_num=$(ls /sys/class/powercap/ | grep -c intel-rapl:)
  [[ -n "$domain_num" ]] || block_test "intel-rapl sysfs is not available."

  for ((i = 1; i <= domain_num; i++)); do
    domain_name=$(ls /sys/class/powercap/ | grep intel-rapl: | sed -n "$i,1p")
    test_print_trc "------Testing domain name: $domain_name------"
    ori_pl4=$(rdmsr 0x601)

    # Read default PL4, PL1, PL2 value
    pl4_default=$(cat /sys/class/powercap/"$domain_name"/constraint_2_max_power_uw)
    [[ -n "$pl4_default" ]] && test_print_trc "PL4 value before RAPL Control enable and disable: $pl4_default"

    pl1_default=$(cat /sys/class/powercap/"$domain_name"/constraint_0_max_power_uw)
    [[ -n "$pl1_default" ]] && test_print_trc "PL1 value before RAPL Control enable and disable: $pl1_default"

    pl2_default=$(cat /sys/class/powercap/"$domain_name"/constraint_1_max_power_uw)
    [[ -n "$pl2_default" ]] && test_print_trc "PL2 value before RAPL Control enable and disable: $pl2_default"

    # Enable RAPL control
    do_cmd "echo 1 > /sys/class/powercap/$domain_name/enabled"
    enabled_knob=$(cat /sys/class/powercap/"$domain_name"/enabled)
    if [[ "$enabled_knob" -eq 1 ]]; then
      test_print_trc "Enabling RAPL control for $domain_name is PASS"
    else
      die "Enabling RAPL control for $domain_name is Fail"
    fi

    # Write a low value to 0x601 then enable the RAPL control
    # Only cover on Client platform
    # Low value will be written 0
    # High value will be written
    do_cmd "wrmsr 0x601 $test_pl4"

    # Disable RAPL control
    do_cmd "echo 0 > /sys/class/powercap/$domain_name/enabled"
    disabled_knob=$(cat /sys/class/powercap/"$domain_name"/enabled)

    # Get Enable power limit value by reading 0x610 bit 15
    enable_power_limit=$(rdmsr 0x610 -f 15:15)
    test_print_trc "Enable RAPL Limit shows: $enable_power_limit"

    # Check if RAPL control disable works as expected
    if [[ $disabled_knob -eq 0 ]]; then
      test_print_trc "RAPL Control is not expected to be set to 0, so 1 is PASS."
    elif [[ $enable_power_limit -eq 0 ]]; then
      die "System allows to disable PL, while writing RAPL control disable fail."
    else
      # Trying to manually write 0x610 bit 15 to 0
      # If it can't be set then you are OK as system is not allowing to disable PL1.
      # But wrmsr can write bit 15 to 0 and enabled is still 1, then this is a bug
      change_bit15=$(wrmsr 0x610 $(($(rdmsr -d 0x610) & ~(1 << 15))))
      test_print_trc "Verify if 0x610 bit 15 can be set to 0: $change_bit15"
      read_bit15=$(rdmsr 0x610 -f 15:15)
      if [[ $read_bit15 -eq 0 ]]; then
        die "0x610 bit 15 can change to 0, while RAPL control disable still 1."
      else
        test_print_trc "0x610 bit 15 cannot change to 0, so RAPL control enable shows 1 is expected."
      fi
    fi

    # Check if PL4 value changed after RAPL control enable and disable
    pl4_recovered=$(cat /sys/class/powercap/"$domain_name"/constraint_2_max_power_uw)
    test_print_trc "PL4 value after RAPL Control enable and disable: $pl4_recovered"
    if [[ -z "$pl4_recovered" ]]; then
      test_print_trc "constraint_2_max_power_uw is not available for $domain_name"
    elif [[ "$pl4_recovered" == "$pl4_default" ]]; then
      test_print_trc "PL4 shows the same value as default after RAPL Control enable and disable"
    else
      die "PL4 value changed after RAPL Control enable and disable: $pl4_recovered"
    fi

    # Check if PL1 value changed after RAPL control enable and disable
    pl1_recovered=$(cat /sys/class/powercap/"$domain_name"/constraint_0_max_power_uw)
    if [[ -z "$pl1_default" ]]; then
      test_print_trc "constraint_0_max_power_uw is not available for $domain_name"
    elif [[ "$pl1_recovered" == "$pl1_default" ]]; then
      test_print_trc "PL1 value after RAPL Control enable and disable:$pl1_recovered"
      test_print_trc "PL1 shows the same value as default after RAPL Control enable and disable"
    else
      die "PL1 value changed after RAPL Control enable and disable: $pl1_recovered"
    fi

    # Check if PL2 value changed after RAPL control enable and disable
    pl2_recovered=$(cat /sys/class/powercap/"$domain_name"/constraint_1_max_power_uw)
    if [[ -z "$pl2_default" ]]; then
      test_print_trc "constraint_1_max_power_uw is not available for $domain_name"
    elif [[ "$pl2_recovered" == "$pl2_default" ]]; then
      test_print_trc "PL2 value after RAPL Control enable and disable:$pl2_recovered"
      test_print_trc "PL2 shows the same value as default after RAPL Control enable and disable"
    else
      die "PL2 value changed after RAPL Control enable and disable: $pl2_recovered"
    fi

    # Re-enable RAPL control
    do_cmd "echo 1 > /sys/class/powercap/$domain_name/enabled"

    # Re-cover the 0x601 original setting
    do_cmd "wrmsr 0x601 $ori_pl4"

  done
}

: "${CHECK_ENERGY:=0}"
: "${CHECK_POWER_LOAD:=0}"
: "${CHECK_POWER_LIMIT:=0}"

intel_rapl_test() {
  case $TEST_SCENARIO in
  check_sysfs)
    rapl_check_interface
    ;;
  check_pkg_domain)
    rapl_check_pkg_domain
    ;;
  check_psys_domain)
    rapl_check_psys_domain
    ;;
  check_pp0_domain)
    rapl_check_pp0_domain
    ;;
  check_pp1_domain)
    rapl_check_pp1_domain
    ;;
  check_dram_domain)
    rapl_check_dram_domain
    ;;
  check_pkg_domain_msr)
    rapl_check_pkg_energy_status_msr
    ;;
  check_psys_domain_msr)
    rapl_check_psys_domain_msr
    ;;
  check_pkg_power_limit_msr)
    rapl_check_pkg_power_limit_msr
    ;;
  check_pkg_energy_status)
    CHECK_ENERGY=1
    rapl_power_check pkg
    ;;
  check_pkg_energy_status_with_workload)
    CHECK_POWER_LOAD=1
    rapl_power_check pkg
    ;;
  check_pkg_power_limit_75)
    CHECK_POWER_LIMIT=1
    rapl_power_check pkg 75
    ;;
  check_pkg_power_limit_50)
    CHECK_POWER_LIMIT=1
    rapl_power_check pkg 50
    ;;
  check_pp0_energy_status)
    CHECK_ENERGY=1
    rapl_power_check core
    ;;
  check_pp0_energy_status_with_workload)
    CHECK_POWER_LOAD=1
    rapl_power_check core
    ;;
  check_dram_energy_status)
    CHECK_ENERGY=1
    rapl_power_check dram
    ;;
  check_dram_energy_status_with_workload)
    CHECK_POWER_LOAD=1
    rapl_power_check dram
    ;;
  check_pp1_energy_status)
    CHECK_ENERGY=1
    rapl_power_check uncore
    ;;
  check_rapl_control_after_power_limit_change)
    enable_rapl_control
    ;;
  sysfs_perf_name_compare)
    rapl_perf_name_compare intel-rapl
    ;;
  sysfs_perf_energy_compare_workload_server)
    rapl_perf_energy_compare intel-rapl pkg dram
    ;;
  sysfs_perf_energy_compare_workload_client)
    rapl_perf_energy_compare intel-rapl pkg uncore
    ;;
  sysfs_turbostat_energy_compare_workload_server)
    rapl_turbostat_energy_compare intel-rapl pkg dram
    ;;
  sysfs_turbostat_energy_compare_workload_client)
    rapl_turbostat_energy_compare intel-rapl pkg uncore
    ;;
  rapl_control_enable_disable_pl1)
    rapl_control_enable_disable_pl 0
    ;;
  rapl_control_enable_disable_pl2)
    rapl_control_enable_disable_pl 1
    ;;
  rapl_control_enable_disable_pl4)
    rapl_control_enable_disable_pl 2
    ;;
  rapl_control_pl4_low_value)
    rapl_control_enable_disable_pl4 0
    ;;
  rapl_control_pl4_high_value)
    rapl_control_enable_disable_pl4 0x500
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

init_rapl
intel_rapl_test
