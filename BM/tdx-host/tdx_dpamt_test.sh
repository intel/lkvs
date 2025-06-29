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

# functiont to do basic TDX KVM host enabling check
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
  die "TDX KVM host not booted with TDX enabled, \
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
  if [ -z "$PORT" ]; then
    die "Port number not provided for TDVM shutdown."
  fi
  # Shutdown TDVM with the given port number
  sshpass -e ssh -p "$PORT" -o StrictHostKeyChecking=no root@localhost << EOF
    systemctl reboot --reboot-argument=now
EOF
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
    # launch TDVM with 1 vCPU, 1GB memory and port 10021
    ./qemu_dpamt.sh 1 1 10021 $GUEST_IMAGE_1 &
    sleep 10
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is still zero after TDVM launch, \
      please check host kernel pamt enabling setup."
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after TDVM lauched"
    fi
    # shutdown TDVM
    vm_shutdown 10021 || die "Failed to shutdown TDVM"
    sleep 10
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
    # launch TDVM with 1 vCPU, 4GB memory and port 10021
    ./qemu_dpamt.sh 1 4 10021 $GUEST_IMAGE_1 &
    sleep 20
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is still zero after TDVM launch, \
      please check host kernel pamt enabling setup."
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after TDVM lauched"
    fi
    # shutdown TDVM
    vm_shutdown 10021 || die "Failed to shutdown TDVM"
    sleep 10
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
    # launch TDVM with 1 vCPU, 96GB memory and port 10021
    ./qemu_dpamt.sh 1 96 10021 $GUEST_IMAGE_1 &
    sleep 60
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is still zero after TDVM launch, \
      please check host kernel pamt enabling setup."
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after TDVM lauched"
    fi
    # shutdown TDVM
    vm_shutdown 10021 || die "Failed to shutdown TDVM"
    sleep 10
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
    # launch TDVM1 with 1 vCPU, 1GB memory and port 10021
    ./qemu_dpamt.sh 1 1 10021 $GUEST_IMAGE_1 &
    # launch TDVM2 with 1 vCPU, 1GB memory and port 10022
    ./qemu_dpamt.sh 1 1 10022 $GUEST_IMAGE_2 &
    # wait for TDVMs to be launched
    sleep 20
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is still zero after TDVMs launch, \
      please check host kernel pamt enabling setup."
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after TDVMs lauched"
    fi
    # shutdown TDVM1
    vm_shutdown 10021 || die "Failed to shutdown TDVM1"
    sleep 10
    # check if TDX KVM host /proc/meminfo tdx field value is not zero since TDVM2 is still alive
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM1 shutdown"
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM1 shutdown"
    fi
    # shutdown TDVM2
    vm_shutdown 10022 || die "Failed to shutdown TDVM2"
    sleep 10
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
    # launch TDVM1 with 1 vCPU, 4GB memory and port 10021
    ./qemu_dpamt.sh 1 4 10021 $GUEST_IMAGE_1 &
    # launch TDVM2 with 1 vCPU, 4GB memory and port 10022
    ./qemu_dpamt.sh 1 4 10022 $GUEST_IMAGE_2 &
    # wait for TDVMs to be launched
    sleep 30
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is still zero after TDVMs launch, \
      please check host kernel pamt enabling setup."
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after TDVMs lauched"
    fi
    # shutdown TDVM1
    vm_shutdown 10021 || die "Failed to shutdown TDVM1"
    sleep 10
    # check if TDX KVM host /proc/meminfo tdx field value is not zero since TDVM2 is still alive
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM1 shutdown"
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM1 shutdown"
    fi
    # shutdown TDVM2
    vm_shutdown 10022 || die "Failed to shutdown TDVM2"
    sleep 10
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
    # launch TDVM1 with 1 vCPU, 96GB memory and port 10021
    ./qemu_dpamt.sh 1 96 10021 $GUEST_IMAGE_1 &
    # launch TDVM2 with 1 vCPU, 96GB memory and port 10022
    ./qemu_dpamt.sh 1 96 10022 $GUEST_IMAGE_2 &
    # wait for TDVMs to be launched
    sleep 60
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is still zero after TDVMs launch, \
      please check host kernel pamt enabling setup."
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after TDVMs lauched"
    fi
    # shutdown TDVM1
    vm_shutdown 10021 || die "Failed to shutdown TDVM1"
    sleep 10
    # check if TDX KVM host /proc/meminfo tdx field value is not zero since TDVM2 is still alive
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM1 shutdown"
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM1 shutdown"
    fi
    # shutdown TDVM2
    vm_shutdown 10022 || die "Failed to shutdown TDVM2"
    sleep 10
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
    # launch legacy VM with 1 vCPU, 1GB memory and port 10021
    ./qemu_legacy.sh 1 1 10021 &
    sleep 10
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      test_print_trc "TDX KVM host /proc/meminfo tdx field value is zero after legacy VM lauched"
    else
      die "TDX KVM host /proc/meminfo tdx field value is not zero after legacy VM lauched, \
      please check host kernel pamt enabling setup."
    fi
    # shutdown legacy VM
    vm_shutdown 10021 || die "Failed to shutdown legacy VM"
    sleep 10
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
    # launch TDVM with 1 vCPU, 1GB memory and port 10021
    ./qemu_dpamt.sh 1 1 10021 $GUEST_IMAGE_1 &
    # launch legacy VM with 1 vCPU, 1GB memory and port 10022
    ./qemu_legacy.sh 1 1 10022 &
    # wait for TDVM and legacy VM to be launched
    sleep 10
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      die "TDX KVM host /proc/meminfo tdx field value is still zero after TDVM launch, \
      please check host kernel pamt enabling setup."
    else
      test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after TDVM lauched"
    fi
    # shutdown TDVM
    vm_shutdown 10021 || die "Failed to shutdown TDVM"
    sleep 10
    # check if TDX KVM host /proc/meminfo tdx field value is zero
    tdx_meminfo=$(pamt_meminfo_tdx)
    if [ "$tdx_meminfo" -eq 0 ]; then
      test_print_trc "TDX KVM host /proc/meminfo tdx field value is zero after TDVM shutdown"
    else
      die "TDX KVM host /proc/meminfo tdx field value is not zero after TDVM shutdown, \
      please check host kernel pamt enabling setup."
    fi
    # shutdown legacy VM
    vm_shutdown 10022 || die "Failed to shutdown legacy VM"
    sleep 10
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
    # 10 repeat times while loop
    for i in {1..10}; do
      test_print_trc "Start TDVM1 and TDVM2 launch and dpamt check, repeat times: $i"
      # launch TDVM1 with 1 vCPU, 1GB memory and port 10021
      ./qemu_dpamt.sh 1 1 10021 $GUEST_IMAGE_1 > /dev/null 2>&1 &
      # launch TDVM2 with 1 vCPU, 96GB memory and port 10022
      ./qemu_dpamt.sh 1 96 10022 $GUEST_IMAGE_2 > /dev/null 2>&1 &
      # wait for TDVM1 and TDVM2 to be launched
      sleep 60
      # check if TDX KVM host /proc/meminfo tdx field value is zero
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is still zero after TDVMs launch, \
        please check host kernel pamt enabling setup."
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after TDVMs lauched"
      fi
      # shutdown TDVM1
      vm_shutdown 10021 || die "Failed to shutdown TDVM1"
      sleep 10
      # check if TDX KVM host /proc/meminfo tdx field value is not zero since TDVM2 is still alive
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM1 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM1 shutdown"
      fi
      # shutdown TDVM2
      vm_shutdown 10022 || die "Failed to shutdown TDVM2"
      sleep 10
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
    # 10 repeat times while loop
    for i in {1..10}; do
      test_print_trc "Start TDVM1, TDVM2, TDVM3, TDVM4 and TDVM5 launch and dpamt check, repeat times: $i"
      # launch TDVM1 with 1 vCPU, 1GB memory and port 10021
      ./qemu_dpamt.sh 1 1 10021 $GUEST_IMAGE_1 > /dev/null 2>&1 &
      # launch TDVM2 with 1 vCPU, 4GB memory and port 10022
      ./qemu_dpamt.sh 1 4 10022 $GUEST_IMAGE_2 > /dev/null 2>&1 &
      # launch TDVM3 with 1 vCPU, 8GB memory and port 10023
      ./qemu_dpamt.sh 1 8 10023 $GUEST_IMAGE_3 > /dev/null 2>&1 &
      # launch TDVM4 with 1 vCPU, 32GB memory and port 10024
      ./qemu_dpamt.sh 1 32 10024 $GUEST_IMAGE_4 > /dev/null 2>&1 &
      # launch TDVM5 with 1 vCPU, 96GB memory and port 10025
      ./qemu_dpamt.sh 1 96 10025 $GUEST_IMAGE_5 > /dev/null 2>&1 &
      # wait for all TDVMs to be launched
      sleep 60
      # check if TDX KVM host /proc/meminfo tdx field value is zero
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is still zero after all TDVMs launch, \
        please check host kernel pamt enabling setup."
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after all TDVMs lauched"
      fi
      # shutdown all TDVMs one by one
      vm_shutdown 10021 || die "Failed to shutdown TDVM1"
      sleep 10
      # check if TDX KVM host /proc/meminfo tdx field value is not zero since TDVM2, TDVM3, TDVM4 and TDVM5 are still alive
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM1 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM1 shutdown"
      fi
      vm_shutdown 10022 || die "Failed to shutdown TDVM2"
      sleep 10
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM2 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM2 shutdown"
      fi
      vm_shutdown 10023 || die "Failed to shutdown TDVM3"
      sleep 10
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM3 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM3 shutdown"
      fi
      vm_shutdown 10024 || die "Failed to shutdown TDVM4"
      sleep 10
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM4 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM4 shutdown"
      fi
      vm_shutdown 10025 || die "Failed to shutdown TDVM5"
      sleep 10
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
    # 100 repeat times while loop
    for i in {1..100}; do
      test_print_trc "Start TDVM1 and TDVM2 launch and dpamt check, repeat times: $i"
      # launch TDVM1 with 1 vCPU, 1GB memory and port 10021
      ./qemu_dpamt.sh 1 1 10021 $GUEST_IMAGE_1 > /dev/null 2>&1 &
      # launch TDVM2 with 1 vCPU, 96GB memory and port 10022
      ./qemu_dpamt.sh 1 96 10022 $GUEST_IMAGE_2 > /dev/null 2>&1 &
      # wait for TDVM1 and TDVM2 to be launched
      sleep 60
      # check if TDX KVM host /proc/meminfo tdx field value is zero
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is still zero after TDVMs launch, \
        please check host kernel pamt enabling setup."
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after TDVMs lauched"
      fi
      # shutdown TDVM1
      vm_shutdown 10021 || pkill td_pamt_10021 || die "Failed to shutdown TDVM1"
      sleep 10
      # check if TDX KVM host /proc/meminfo tdx field value is not zero since TDVM2 is still alive
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM1 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM1 shutdown"
      fi
      # shutdown TDVM2
      vm_shutdown 10022 || pkill td_pamt_10022 || die "Failed to shutdown TDVM2"
      sleep 10
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
    # 100 repeat times while loop
    for i in {1..100}; do
      test_print_trc "Start TDVM1, TDVM2, TDVM3, TDVM4 and TDVM5 launch and dpamt check, repeat times: $i"
      # launch TDVM1 with 1 vCPU, 1GB memory and port 10021
      ./qemu_dpamt.sh 1 1 10021 $GUEST_IMAGE_1 > /dev/null 2>&1 &
      # launch TDVM2 with 1 vCPU, 4GB memory and port 10022
      ./qemu_dpamt.sh 1 4 10022 $GUEST_IMAGE_2 > /dev/null 2>&1 &
      # launch TDVM3 with 1 vCPU, 8GB memory and port 10023
      ./qemu_dpamt.sh 1 8 10023 $GUEST_IMAGE_3 > /dev/null 2>&1 &
      # launch TDVM4 with 1 vCPU, 32GB memory and port 10024
      ./qemu_dpamt.sh 1 32 10024 $GUEST_IMAGE_4 > /dev/null 2>&1 &
      # launch TDVM5 with 1 vCPU, 96GB memory and port 10025
      ./qemu_dpamt.sh 1 96 10025 $GUEST_IMAGE_5 > /dev/null 2>&1 &
      # wait for all TDVMs to be launched
      sleep 60
      # check if TDX KVM host /proc/meminfo tdx field value is zero
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is still zero after all TDVMs launch, \
        please check host kernel pamt enabling setup."
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field is $tdx_meminfo after all TDVMs lauched"
      fi
      # shutdown all TDVMs one by one
      vm_shutdown 10021 || pkill td_pamt_10021 || die "Failed to shutdown TDVM1"
      sleep 10
      # check if TDX KVM host /proc/meminfo tdx field value is not zero since TDVM2, TDVM3, TDVM4 and TDVM5 are still alive
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM1 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM1 shutdown"
      fi
      vm_shutdown 10022 || pkill td_pamt_10022 || die "Failed to shutdown TDVM2"
      sleep 10
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM2 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM2 shutdown"
      fi
      vm_shutdown 10023 || pkill td_pamt_10023 || die "Failed to shutdown TDVM3"
      sleep 10
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM3 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM3 shutdown"
      fi
      vm_shutdown 10024 || pkill td_pamt_10024 || die "Failed to shutdown TDVM4"
      sleep 10
      tdx_meminfo=$(pamt_meminfo_tdx)
      if [ "$tdx_meminfo" -eq 0 ]; then
        die "TDX KVM host /proc/meminfo tdx field value is zero after TDVM4 shutdown"
      else
        test_print_trc "TDX KVM host /proc/meminfo tdx field value is $tdx_meminfo after TDVM4 shutdown"
      fi
      vm_shutdown 10025 || pkill td_pamt_10025 || die "Failed to shutdown TDVM5"
      sleep 10
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