#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2025 Intel Corporation

# Author:   Hongyu Ning <hongyu.ning@intel.com>
# History:  13, Jun., 2025 - Hongyu Ning - creation

# @desc simple script to launch TDVMs in different configurations
# @ $1 CPU number
# @ $2 Memory size in GB
# @ $3 PORT number for ssh forwarding
# @ $4 GUEST_IMAGE for VM launching
# @note detailed qemu configuration to be revised based on qemu TDVM launching requirements

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR"

# TDX guest kernel
KERNEL_IMAGE="/guest/kernel/in_use/vmlinuz-xxx-yyy-zzz"

# OVMF
BIOS_IMAGE="/ovmf/in_use/OVMF.xx_yy_zz.fd"

# QEMU
QEMU_IMAGE="/qemu/in_use/qemu-system-x86_64.xx_yy_zz"

# Common test parameter
CPUS=$1
MEM=$2
PORT=$3
GUEST_IMAGE=$4
CID=$(( "$PORT" - 10000 ))
TELNET=$(( "$PORT" - 1000 ))

# All dynamic TDX pre-check work will be done in tdx_dpamt_test.sh


# TDVM launching
"${QEMU_IMAGE}" \
  -accel kvm \
  -no-reboot \
  -name process=td_pamt_"${PORT}",debug-threads=on \
  -cpu host,host-phys-bits,pmu=off \
  -smp cpus="${CPUS}" \
  -m "${MEM}"G \
  -object '{"qom-type":"tdx-guest","id":"tdx","sept-ve-disable":true}' \
  -object memory-backend-ram,id=ram1,size="${MEM}"G \
  -machine q35,hpet=off,kernel_irqchip=split,confidential-guest-support=tdx,memory-backend=ram1 \
  -bios "${BIOS_IMAGE}" \
  -nographic \
  -vga none \
  -device virtio-net-pci,netdev=mynet0,mac=00:16:3E:68:08:FF,romfile= \
  -netdev user,id=mynet0,hostfwd=tcp::"${PORT}"-:22 \
  -device vhost-vsock-pci,guest-cid="${CID}" \
  -chardev stdio,id=mux,mux=on,signal=off \
  -device virtio-serial,romfile= \
  -device virtconsole,chardev=mux \
  -serial chardev:mux \
  -monitor chardev:mux \
  -drive file="${GUEST_IMAGE}",if=virtio,format=raw \
  -kernel "${KERNEL_IMAGE}" \
  -append "root=/dev/vda3 ro console=hvc0 earlyprintk=ttyS0 earlyprintk l1tf=off nokaslr efi=debug mce=off accept_memory=lazy" \
  -monitor pty \
  -monitor telnet:127.0.0.1:"${TELNET}",server,nowait \
  -machine hpet=off \
  -nodefaults