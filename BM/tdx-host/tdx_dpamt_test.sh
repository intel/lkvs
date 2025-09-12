#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2025 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
# History:  10, Jun., 2025 - Hongyu Ning - creation

# @desc This script is top level TDX KVM host dynamic pamt test
# @functions provided:
#  #   - basic pamt prerequisites check
#  #   - launch TDVM or legacy VM
#  #   - shutdown TDVM or legacy VM
#  #   - dynamic pamt functional check

###################### Variables ######################
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"

# Guest OS root account password for sshpass usage
# This should be set to the actual password of the guest OS root account
SSHPASS="guest_os_root_password"
export SSHPASS
GUEST_IMAGE_1="/guest/os/image/in_use/guest-os.xx.1.img"
GUEST_IMAGE_2="/guest/os/image/in_use/guest-os.xx.2.img"
GUEST_IMAGE_3="/guest/os/image/in_use/guest-os.xx.3.img"
GUEST_IMAGE_4="/guest/os/image/in_use/guest-os.xx.4.img"
GUEST_IMAGE_5="/guest/os/image/in_use/guest-os.xx.5.img"

###################### Functions ######################
# helper function
usage() {
  cat <<-EOF
  usage: ./${0##*/}
  -t testcase number to run
  -h HELP info
EOF
}

# function to do basic TDX KVM host enabling check
tdx_basic_check(){
  #check if TDX KVM host is booted with TDX enabled
  dmesg | grep -i "tdx" | grep -iq "module initialized" || \
  die "TDX KVM host not booted with TDX enabled, \
  please check host kernel tdx enabling setup."
  test_print_trc "TDX module initialized correctly"
  #check if TDX KVM host is booted with TDX enabled
  if [ "$(cat /sys/module/kvm_intel/parameters/tdx)" = "Y" ]; then
    test_print_trc "TDX KVM host booted with TDX enabled"
  else
    die "TDX KVM host not booted with TDX enabled, \
    please check host kernel tdx enabling setup."
  fi
}

# function to do basic TDX KVM host dynamic pamt check
pamt_basic_check() {
  # check if TDX KVM host is booted with pamt enabled
  dmesg | grep -i "tdx" | grep -iq "enable dynamic pamt" || \
  die "TDX KVM host not booted with dynamic pamt enabled, \
  please check host kernel pamt enabling setup."
  test_print_trc "TDX KVM host booted with dynamic pamt enabled" 
  # check /proc/meminfo TDX field exists and value is zero
  grep -iq "tdx" /proc/meminfo || \
  die "TDX KVM host not booted with /proc/meminfo tdx field, \
  please check host kernel tdx enabling setup."
  local tdx_meminfo
  tdx_meminfo=$(grep -i "tdx:" /proc/meminfo | awk '{print $2}')
  if [ "$tdx_meminfo" -eq 0 ]; then
    test_print_trc "TDX KVM host /proc/meminfo tdx field value is zero"
  else
    die "TDX KVM host /proc/meminfo tdx field value is not zero, \
    please check host kernel pamt enabling setup."
  fi
}

# functiont to check and return pamt value in /proc/meminfo
pamt_meminfo_tdx(){
  local tdx_meminfo
  tdx_meminfo=$(grep -i "tdx:" /proc/meminfo | awk '{print $2}')
  if [ -z "$tdx_meminfo" ]; then
    die "TDX KVM host /proc/meminfo tdx field not found, \
    please check host kernel pamt enabling setup."
  else
    echo "$tdx_meminfo"
  fi
}

# function to shutdown TDVM or legacy VM with port number passed in
vm_shutdown(){
  local PORT="$1"
  local VM_PROC="$2"
  local TIMEOUT=300
  local INTERVAL=2
  local ELAPSED=0
  if [ -z "$PORT" ]; then
    die "Port number not provided for TDVM shutdown."
  fi
  # Shutdown TDVM with the given port number
  sshpass -e ssh -p "$PORT" -o StrictHostKeyChecking=no root@localhost << EOF
    systemctl reboot --reboot-argument=now
EOF

  # Wait for VM shutdown fully complete within TIMEOUT seconds
  while [ $ELAPSED -lt $TIMEOUT ]; do
    if ! pgrep -f "${VM_PROC}_${PORT}" > /dev/null; then
      test_print_trc "TDVM ${VM_PROC}_${PORT} has exited after ${ELAPSED} seconds."
      return 0
    fi
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
  done

  test_print_wrg "TDVM ${VM_PROC}_${PORT} can't exit after shutdown timeout ${TIMEOUT} seconds."
  return 1
}

# function to check TDVM or legacy VM is fully launched for ssh accessible
vm_up_check() {
  local PORT="$1"
  local TIMEOUT=300
  local INTERVAL=2
  local ELAPSED=0
  while [ $ELAPSED -lt $TIMEOUT ]; do
    if sshpass -e ssh -p "$PORT" -o StrictHostKeyChecking=no -o ConnectTimeout=2 root@localhost "echo SSH_OK" 2>/dev/null | grep -q "SSH_OK"; then
      test_print_trc "VM is up on port ${PORT} after ${ELAPSED} seconds."
      break
    fi
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
  done

  if [ $ELAPSED -ge $TIMEOUT ]; then
    die "VM is not up on port ${PORT} after ${TIMEOUT} seconds"
  fi
}

###################### Do Works #######################
cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env

## PART 0: prepare test prerequisites ##
if [ ! "$(which sshpass)" ]; then
  dnf install -y sshpass > /dev/null
  apt install -y sshpass > /dev/null
else
  test_print_trc "sshpass prerequisites is ready for use"
fi

while getopts :t:h arg; do
  case $arg in
    t)
      TESTCASE=$OPTARG
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

case $TESTCASE in
  # basic KVM host TDX enabling check
  0)
    tdx_basic_check;
    ;;
  # basic KVM host dynamic pamt check
  1)
    tdx_basic_check;
    pamt_basic_check;
    ;;
  # 1 TDVM of 1 VCPU and 1GB MEM launch & shutdown, with dpamt check
  2)
    tdx_basic_check;
    pamt_basic_check;
    # create VM launching log dir under /tmp/
    mkdir -p /tmp/tdpamt_2/
    # launch TDVM with 1 vCPU, 1GB memory and port 10021
    ./qemu_dpamt.sh 1 1 10021 $GUEST_IMAGE_1 > /tmp/tdpamt_2/tdvm.1.log 2>&1 &
    test_print_trc "tdvm 1 launched, VM boot log at /tmp/tdpamt_2/tdvm.1.log"
    # wait for TDVM fully launched for ssh accessible
    vm_up_check 10021
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is still zero after TDVM launch, \
      please check host kernel pamt enabling setup."
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after TDVM lauched"
    fi
    # shutdown TDVM
    vm_shutdown 10021 "td_pamt" || die "Failed to shutdown TDVM"
    sleep 2
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      test_print_trc "TDX KVM host /proc/meminfo tdx field value is zero after TDVM shutdown"
    else
      die "TDX KVM host /proc/meminfo tdx field value is not zero after TDVM shutdown, \
      please check host kernel pamt enabling setup."
    fi
    ;;
  # 1 TDVM of 1 VCPU and 4GB MEM launch & shutdown, with dpamt check
  3)
    tdx_basic_check;
    pamt_basic_check;
    # create VM launching log dir under /tmp/
    mkdir -p /tmp/tdpamt_3/
    # launch TDVM with 1 vCPU, 4GB memory and port 10021
    ./qemu_dpamt.sh 1 4 10021 $GUEST_IMAGE_1 > /tmp/tdpamt_3/tdvm.1.log 2>&1 &
    test_print_trc "tdvm 1 launched, VM boot log at /tmp/tdpamt_3/tdvm.1.log"
    # wait for TDVM fully launched for ssh accessible
    vm_up_check 10021
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is still zero after TDVM launch, \
      please check host kernel pamt enabling setup."
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after TDVM lauched"
    fi
    # shutdown TDVM
    vm_shutdown 10021 "td_pamt" || die "Failed to shutdown TDVM"
    sleep 2
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      test_print_trc "TDX KVM host /proc/meminfo tdx field value is zero after TDVM shutdown"
    else
      die "TDX KVM host /proc/meminfo tdx field value is not zero after TDVM shutdown, \
      please check host kernel pamt enabling setup."
    fi
    ;;
  # 1 TDVM of 1 VCPU and 96GB MEM launch & shutdown, with dpamt check
  4)
    tdx_basic_check;
    pamt_basic_check;
    # create VM launching log dir under /tmp/
    mkdir -p /tmp/tdpamt_4/
    # launch TDVM with 1 vCPU, 96GB memory and port 10021
    ./qemu_dpamt.sh 1 96 10021 $GUEST_IMAGE_1 > /tmp/tdpamt_4/tdvm.1.log 2>&1 &
    test_print_trc "tdvm 1 launched, VM boot log at /tmp/tdpamt_4/tdvm.1.log"
    # wait for TDVM fully launched for ssh accessible
    vm_up_check 10021
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is still zero after TDVM launch, \
      please check host kernel pamt enabling setup."
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after TDVM lauched"
    fi
    # shutdown TDVM
    vm_shutdown 10021 "td_pamt" || die "Failed to shutdown TDVM"
    sleep 2
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      test_print_trc "TDX KVM host /proc/meminfo tdx field value is zero after TDVM shutdown"
    else
      die "TDX KVM host /proc/meminfo tdx field value is not zero after TDVM shutdown, \
      please check host kernel pamt enabling setup."
    fi
    ;;
  # 2 TDVMs of 1 VCPU and 1GB MEM launch & shutdown, with dpamt check
  5)
    tdx_basic_check;
    pamt_basic_check;
    # create VM launching log dir under /tmp/
    mkdir -p /tmp/tdpamt_5/
    # launch TDVM1 with 1 vCPU, 1GB memory and port 10021
    ./qemu_dpamt.sh 1 1 10021 $GUEST_IMAGE_1 > /tmp/tdpamt_5/tdvm.1.log 2>&1 &
    test_print_trc "tdvm 1 launched, VM boot log at /tmp/tdpamt_5/tdvm.1.log"
    # launch TDVM2 with 1 vCPU, 1GB memory and port 10022
    ./qemu_dpamt.sh 1 1 10022 $GUEST_IMAGE_2 > /tmp/tdpamt_5/tdvm.2.log 2>&1 &
    test_print_trc "tdvm 2 launched, VM boot log at /tmp/tdpamt_5/tdvm.2.log"
    # wait for all TDVMs fully launched for ssh accessible
    vm_up_check 10021
    vm_up_check 10022
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is still zero after TDVMs launch, \
      please check host kernel pamt enabling setup."
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after TDVMs lauched"
    fi
    # shutdown TDVM1
    vm_shutdown 10021 "td_pamt" || die "Failed to shutdown TDVM1"
    sleep 2
    # check if TDX KVM host /proc/meminfo tdx field value is not zero since TDVM2 is still alive
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM1 shutdown"
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM1 shutdown"
    fi
    # shutdown TDVM2
    vm_shutdown 10022 "td_pamt" || die "Failed to shutdown TDVM2"
    sleep 2
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      test_print_trc "TDX KVM host /proc/meminfo tdx field value is zero after TDVM2 shutdown"
    else
      die "TDX KVM host /proc/meminfo tdx field value is not zero $tdx_meminfo after TDVM2 shutdown, \
      please check host kernel pamt enabling setup."
    fi
    ;;
  # 2 TDVMs of 1 VCPU and 4GB MEM launch & shutdown, with dpamt check
  6)
    tdx_basic_check;
    pamt_basic_check;
    # create VM launching log dir under /tmp/
    mkdir -p /tmp/tdpamt_6/
    # launch TDVM1 with 1 vCPU, 4GB memory and port 10021
    ./qemu_dpamt.sh 1 4 10021 $GUEST_IMAGE_1 > /tmp/tdpamt_6/tdvm.1.log 2>&1 &
    test_print_trc "tdvm 1 launched, VM boot log at /tmp/tdpamt_6/tdvm.1.log"
    # launch TDVM2 with 1 vCPU, 4GB memory and port 10022
    ./qemu_dpamt.sh 1 4 10022 $GUEST_IMAGE_2 > /tmp/tdpamt_6/tdvm.2.log 2>&1 &
    test_print_trc "tdvm 2 launched, VM boot log at /tmp/tdpamt_6/tdvm.2.log"
    # wait for all TDVMs fully launched for ssh accessible
    vm_up_check 10021
    vm_up_check 10022
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is still zero after TDVMs launch, \
      please check host kernel pamt enabling setup."
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after TDVMs lauched"
    fi
    # shutdown TDVM1
    vm_shutdown 10021 "td_pamt" || die "Failed to shutdown TDVM1"
    sleep 2
    # check if TDX KVM host /proc/meminfo tdx field value is not zero since TDVM2 is still alive
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM1 shutdown"
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM1 shutdown"
    fi
    # shutdown TDVM2
    vm_shutdown 10022 "td_pamt" || die "Failed to shutdown TDVM2"
    sleep 2
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      test_print_trc "TDX KVM host /proc/meminfo tdx field value is zero after TDVM2 shutdown"
    else
      die "TDX KVM host /proc/meminfo tdx field value is not zero $tdx_meminfo after TDVM2 shutdown, \
      please check host kernel pamt enabling setup."
    fi
    ;;
  # 2 TDVMs of 1 VCPU and 96GB MEM launch & shutdown, with dpamt check
  7)
    tdx_basic_check;
    pamt_basic_check;
    # create VM launching log dir under /tmp/
    mkdir -p /tmp/tdpamt_7/
    # launch TDVM1 with 1 vCPU, 96GB memory and port 10021
    ./qemu_dpamt.sh 1 96 10021 $GUEST_IMAGE_1 > /tmp/tdpamt_7/tdvm.1.log 2>&1 &
    test_print_trc "tdvm 1 launched, VM boot log at /tmp/tdpamt_7/tdvm.1.log"
    # launch TDVM2 with 1 vCPU, 96GB memory and port 10022
    ./qemu_dpamt.sh 1 96 10022 $GUEST_IMAGE_2 > /tmp/tdpamt_7/tdvm.2.log 2>&1 &
    test_print_trc "tdvm 2 launched, VM boot log at /tmp/tdpamt_7/tdvm.2.log"
    # wait for all TDVMs fully launched for ssh accessible
    vm_up_check 10021
    vm_up_check 10022
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is still zero after TDVMs launch, \
      please check host kernel pamt enabling setup."
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after TDVMs lauched"
    fi
    # shutdown TDVM1
    vm_shutdown 10021 "td_pamt" || die "Failed to shutdown TDVM1"
    sleep 2
    # check if TDX KVM host /proc/meminfo tdx field value is not zero since TDVM2 is still alive
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM1 shutdown"
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM1 shutdown"
    fi
    # shutdown TDVM2
    vm_shutdown 10022 "td_pamt" || die "Failed to shutdown TDVM2"
    sleep 2
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      test_print_trc "TDX KVM host /proc/meminfo tdx field value is zero after TDVM2 shutdown"
    else
      die "TDX KVM host /proc/meminfo tdx field value is not zero $tdx_meminfo after TDVM2 shutdown, \
      please check host kernel pamt enabling setup."
    fi
    ;;
  # [negative] 1 VPCU and 1GB MEM legacy VM launch and dpamt check
  8)
    tdx_basic_check;
    pamt_basic_check;
    # create VM launching log dir under /tmp/
    mkdir -p /tmp/tdpamt_8/
    # launch legacy VM with 1 vCPU, 1GB memory and port 10021
    ./qemu_legacy.sh 1 1 10021 > /tmp/tdpamt_8/vm.1.log 2>&1 &
    test_print_trc "legacy VM launched, VM boot log at /tmp/tdpamt_8/vm.1.log"
    # wait for legacy VM fully launched for ssh accessible
    vm_up_check 10021
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      test_print_trc "TDX KVM host /proc/meminfo tdx field value is zero after legacy VM lauched"
    else
      die "TDX KVM host /proc/meminfo tdx field value is not zero after legacy VM lauched, \
      please check host kernel pamt enabling setup."
    fi
    # shutdown legacy VM
    vm_shutdown 10021 "vm" || die "Failed to shutdown legacy VM"
    sleep 2
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      test_print_trc "TDX KVM host /proc/meminfo tdx field value is zero after legacy VM shutdown"
    else
      die "TDX KVM host /proc/meminfo tdx field value is not zero after legacy VM shutdown, \
      please check host kernel pamt enabling setup."
    fi
    ;;
  # [negative] 1 VCPU and 1GB TDVM and legacy VM launch and dpamt check
  9)
    tdx_basic_check;
    pamt_basic_check;
    # create VM launching log dir under /tmp/
    mkdir -p /tmp/tdpamt_9/
    # launch TDVM with 1 vCPU, 1GB memory and port 10021
    ./qemu_dpamt.sh 1 1 10021 $GUEST_IMAGE_1 > /tmp/tdpamt_9/tdvm.1.log 2>&1 &
    test_print_trc "tdvm launched, VM boot log at /tmp/tdpamt_9/tdvm.1.log"
    # launch legacy VM with 1 vCPU, 1GB memory and port 10022
    ./qemu_legacy.sh 1 1 10022 > /tmp/tdpamt_9/vm.1.log 2>&1 &
    test_print_trc "legacy VM launched, VM boot log at /tmp/tdpamt_9/vm.1.log"
    # wait for TDVM and legacy VM fully launched for ssh accessible
    vm_up_check 10021
    vm_up_check 10022
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is still zero after TDVM launch, \
      please check host kernel pamt enabling setup."
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after TDVM lauched"
    fi
    # shutdown TDVM
    vm_shutdown 10021 "td_pamt" || die "Failed to shutdown TDVM"
    sleep 2
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      test_print_trc "TDX KVM host /proc/meminfo tdx field value is zero after TDVM shutdown"
    else
      die "TDX KVM host /proc/meminfo tdx field value is not zero after TDVM shutdown, \
      please check host kernel pamt enabling setup."
    fi
    # shutdown legacy VM
    vm_shutdown 10022 "vm" || die "Failed to shutdown legacy VM"
    sleep 2
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      test_print_trc "TDX KVM host /proc/meminfo tdx field value is zero after legacy VM shutdown"
    else
      die "TDX KVM host /proc/meminfo tdx field value is not zero after legacy VM shutdown, \
      please check host kernel pamt enabling"
    fi
    ;;
  # [stress] TDVM 1 1 VCPU and 1GB MEM, TDVM2 1 VCPU and 96GB, launch and shutdown 10 times, check dpamt accordingly
  10)
    tdx_basic_check;
    pamt_basic_check;
    # create VM launching log dir under /tmp/
    mkdir -p /tmp/tdpamt_10/
    # 10 repeat times while loop
    for i in {1..10}; do
      test_print_trc "Start TDVM1 and TDVM2 launch and dpamt check, repeat times: $i"
      # launch TDVM1 with 1 vCPU, 1GB memory and port 10021
      ./qemu_dpamt.sh 1 1 10021 $GUEST_IMAGE_1 > /tmp/tdpamt_10/tdvm.1.log 2>&1 &
      test_print_trc "tdvm 1 launched, VM boot log at /tmp/tdpamt_10/tdvm.1.log"
      # launch TDVM2 with 1 vCPU, 96GB memory and port 10022
      ./qemu_dpamt.sh 1 96 10022 $GUEST_IMAGE_2 > /tmp/tdpamt_10/tdvm.2.log 2>&1 &
      test_print_trc "tdvm 2 launched, VM boot log at /tmp/tdpamt_10/tdvm.2.log"
      # wait for all TDVMs fully launched for ssh accessible
      vm_up_check 10021
      vm_up_check 10022
      # check if TDX KVM host /proc/meminfo tdx field value is zero
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is still zero after TDVMs launch, \
        please check host kernel pamt enabling setup."
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after TDVMs lauched"
      fi
      # shutdown TDVM1
      vm_shutdown 10021 "td_pamt" || die "Failed to shutdown TDVM1"
      sleep 2
      # check if TDX KVM host /proc/meminfo tdx field value is not zero since TDVM2 is still alive
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM1 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM1 shutdown"
      fi
      # shutdown TDVM2
      vm_shutdown 10022 "td_pamt" || die "Failed to shutdown TDVM2"
      sleep 2
      # check if TDX KVM host /proc/meminfo tdx field value is zero
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is zero after TDVM2 shutdown"
      else
        die "TDX KVM host /proc/meminfo tdx field value is not zero $tdx_meminfo after TDVM2 shutdown, \
        please check host kernel pamt enabling setup."
      fi
    done
    ;;
  # [stress] TDVM1 1 VCPU and 1GB MEM, TDVM2 1 VCPU and 4GB MEM, TDVM3 1 VCPU and 8GB MEM
  # TDVM4 1 VCPU and 32GB MEM, TDVM5 1 VCPU and 96GB MEM, create and shutdown 10 times, check dpamt accordinlgy
  11)
    tdx_basic_check;
    pamt_basic_check;
    # create VM launching log dir under /tmp/
    mkdir -p /tmp/tdpamt_11/
    # 10 repeat times while loop
    for i in {1..10}; do
      test_print_trc "Start TDVM1, TDVM2, TDVM3, TDVM4 and TDVM5 launch and dpamt check, repeat times: $i"
      # launch TDVM1 with 1 vCPU, 1GB memory and port 10021
      ./qemu_dpamt.sh 1 1 10021 $GUEST_IMAGE_1 > /tmp/tdpamt_11/tdvm.1.log 2>&1 &
      test_print_trc "tdvm 1 launched, VM boot log at /tmp/tdpamt_11/tdvm.1.log"
      # launch TDVM2 with 1 vCPU, 4GB memory and port 10022
      ./qemu_dpamt.sh 1 4 10022 $GUEST_IMAGE_2 > /tmp/tdpamt_11/tdvm.2.log 2>&1 &
      test_print_trc "tdvm 2 launched, VM boot log at /tmp/tdpamt_11/tdvm.2.log"
      # launch TDVM3 with 1 vCPU, 8GB memory and port 10023
      ./qemu_dpamt.sh 1 8 10023 $GUEST_IMAGE_3 > /tmp/tdpamt_11/tdvm.3.log 2>&1 &
      test_print_trc "tdvm 3 launched, VM boot log at /tmp/tdpamt_11/tdvm.3.log"
      # launch TDVM4 with 1 vCPU, 32GB memory and port 10024
      ./qemu_dpamt.sh 1 32 10024 $GUEST_IMAGE_4 > /tmp/tdpamt_11/tdvm.4.log 2>&1 &
      test_print_trc "tdvm 4 launched, VM boot log at /tmp/tdpamt_11/tdvm.4.log"
      # launch TDVM5 with 1 vCPU, 96GB memory and port 10025
      ./qemu_dpamt.sh 1 96 10025 $GUEST_IMAGE_5 > /tmp/tdpamt_11/tdvm.5.log 2>&1 &
      test_print_trc "tdvm 5 launched, VM boot log at /tmp/tdpamt_11/tdvm.5.log"
      # wait for all TDVMs fully launched for ssh accessible
      vm_up_check 10021
      vm_up_check 10022
      vm_up_check 10023
      vm_up_check 10024
      vm_up_check 10025
      # check if TDX KVM host /proc/meminfo tdx field value is zero
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is still zero after all TDVMs launch, \
        please check host kernel pamt enabling setup."
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after all TDVMs lauched"
      fi
      # shutdown all TDVMs one by one
      vm_shutdown 10021 "td_pamt" || die "Failed to shutdown TDVM1"
      sleep 2
      # check if TDX KVM host /proc/meminfo tdx field value is not zero since TDVM2, TDVM3, TDVM4 and TDVM5 are still alive
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM1 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM1 shutdown"
      fi
      vm_shutdown 10022 "td_pamt" || die "Failed to shutdown TDVM2"
      sleep 2
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM2 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM2 shutdown"
      fi
      vm_shutdown 10023 "td_pamt" || die "Failed to shutdown TDVM3"
      sleep 2
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM3 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM3 shutdown"
      fi
      vm_shutdown 10024 "td_pamt" || die "Failed to shutdown TDVM4"
      sleep 2
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM4 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM4 shutdown"
      fi
      vm_shutdown 10025 "td_pamt" || die "Failed to shutdown TDVM5"
      sleep 2
      # check if TDX KVM host /proc/meminfo tdx field value is zero
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is zero after all TDVMs shutdown"
      else
        die "TDX KVM host /proc/meminfo tdx field value is not zero $tdx_meminfo after all TDVMs shutdown, \
        please check host kernel pamt enabling setup."
      fi
    done
    ;;
  # [stress] TDVM 1 1 VCPU and 1GB MEM, TDVM2 1 VCPU and 96GB, launch and shutdown 100 cycles, check dpamt accordingly
  12)
    tdx_basic_check;
    pamt_basic_check;
    # create VM launching log dir under /tmp/
    mkdir -p /tmp/tdpamt_12/
    # 100 repeat times while loop
    for i in {1..100}; do
      test_print_trc "Start TDVM1 and TDVM2 launch and dpamt check, repeat times: $i"
      # launch TDVM1 with 1 vCPU, 1GB memory and port 10021
      ./qemu_dpamt.sh 1 1 10021 $GUEST_IMAGE_1 > /tmp/tdpamt_12/tdvm.1.log 2>&1 &
      test_print_trc "tdvm 1 launched, VM boot log at /tmp/tdpamt_12/tdvm.1.log"
      # launch TDVM2 with 1 vCPU, 96GB memory and port 10022
      ./qemu_dpamt.sh 1 96 10022 $GUEST_IMAGE_2 > /tmp/tdpamt_12/tdvm.2.log 2>&1 &
      test_print_trc "tdvm 2 launched, VM boot log at /tmp/tdpamt_12/tdvm.2.log"
      # wait for all TDVMs fully launched for ssh accessible
      vm_up_check 10021
      vm_up_check 10022
      # check if TDX KVM host /proc/meminfo tdx field value is zero
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is still zero after TDVMs launch, \
        please check host kernel pamt enabling setup."
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after TDVMs lauched"
      fi
      # shutdown TDVM1
      vm_shutdown 10021 "td_pamt" || die "Failed to shutdown TDVM1"
      sleep 2
      # check if TDX KVM host /proc/meminfo tdx field value is not zero since TDVM2 is still alive
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM1 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM1 shutdown"
      fi
      # shutdown TDVM2
      vm_shutdown 10022 "td_pamt" || die "Failed to shutdown TDVM2"
      sleep 2
      # check if TDX KVM host /proc/meminfo
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is zero after TDVM2 shutdown"
      else
        die "TDX KVM host /proc/meminfo tdx field value is not zero $tdx_meminfo after TDVM2 shutdown, \
        please check host kernel pamt enabling setup."
      fi
    done
    ;;
  # [stress] TDVM1 1 VCPU and 1GB MEM, TDVM2 1 VCPU and 4GB MEM, TDVM3 1 VCPU and 8GB MEM
  # TDVM4 1 VCPU and 32GB MEM, TDVM5 1 VCPU and 96GB MEM, create and shutdown 100 cycles, check dpamt accordinlgy
  13)
    tdx_basic_check;
    pamt_basic_check;
    # create VM launching log dir under /tmp/
    mkdir -p /tmp/tdpamt_13/
    # 100 repeat times while loop
    for i in {1..100}; do
      test_print_trc "Start TDVM1, TDVM2, TDVM3, TDVM4 and TDVM5 launch and dpamt check, repeat times: $i"
      # launch TDVM1 with 1 vCPU, 1GB memory and port 10021
      ./qemu_dpamt.sh 1 1 10021 $GUEST_IMAGE_1 > /tmp/tdpamt_13/tdvm.1.log 2>&1 &
      test_print_trc "tdvm 1 launched, VM boot log at /tmp/tdpamt_13/tdvm.1.log"
      # launch TDVM2 with 1 vCPU, 4GB memory and port 10022
      ./qemu_dpamt.sh 1 4 10022 $GUEST_IMAGE_2 > /tmp/tdpamt_13/tdvm.2.log 2>&1 &
      test_print_trc "tdvm 2 launched, VM boot log at /tmp/tdpamt_13/tdvm.2.log"
      # launch TDVM3 with 1 vCPU, 8GB memory and port 10023
      ./qemu_dpamt.sh 1 8 10023 $GUEST_IMAGE_3 > /tmp/tdpamt_13/tdvm.3.log 2>&1 &
      test_print_trc "tdvm 3 launched, VM boot log at /tmp/tdpamt_13/tdvm.3.log"
      # launch TDVM4 with 1 vCPU, 32GB memory and port 10024
      ./qemu_dpamt.sh 1 32 10024 $GUEST_IMAGE_4 > /tmp/tdpamt_13/tdvm.4.log 2>&1 &
      test_print_trc "tdvm 4 launched, VM boot log at /tmp/tdpamt_13/tdvm.4.log"
      # launch TDVM5 with 1 vCPU, 96GB memory and port 10025
      ./qemu_dpamt.sh 1 96 10025 $GUEST_IMAGE_5 > /tmp/tdpamt_13/tdvm.5.log 2>&1 &
      test_print_trc "tdvm 5 launched, VM boot log at /tmp/tdpamt_13/tdvm.5.log"
      # wait for all TDVMs fully launched for ssh accessible
      vm_up_check 10021
      vm_up_check 10022
      vm_up_check 10023
      vm_up_check 10024
      vm_up_check 10025
      # check if TDX KVM host /proc/meminfo tdx field value is zero
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is still zero after all TDVMs launch, \
        please check host kernel pamt enabling setup."
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after all TDVMs lauched"
      fi
      # shutdown all TDVMs one by one
      vm_shutdown 10021 "td_pamt" || die "Failed to shutdown TDVM1"
      sleep 2
      # check if TDX KVM host /proc/meminfo tdx field value is not zero since TDVM2, TDVM3, TDVM4 and TDVM5 are still alive
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM1 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM1 shutdown"
      fi
      vm_shutdown 10022 "td_pamt" || die "Failed to shutdown TDVM2"
      sleep 2
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM2 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM2 shutdown"
      fi
      vm_shutdown 10023 "td_pamt" || die "Failed to shutdown TDVM3"
      sleep 2
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM3 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM3 shutdown"
      fi
      vm_shutdown 10024 "td_pamt" || die "Failed to shutdown TDVM4"
      sleep 2
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM4 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM4 shutdown"
      fi
      vm_shutdown 10025 "td_pamt" || die "Failed to shutdown TDVM5"
      sleep 2
      # check if TDX KVM host /proc/meminfo tdx field value is zero
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is zero after all TDVMs shutdown"
      else
        die "TDX KVM host /proc/meminfo tdx field value is not zero $tdx_meminfo after all TDVMs shutdown, \
        please check host kernel pamt enabling setup."
      fi
    done
    ;;
  *)
    test_print_err "Invalid testcase number: $TESTCASE"
    usage && exit 1
    ;;
esac
# end of script