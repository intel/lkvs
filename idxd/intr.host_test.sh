#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# @desc This script verify idxd interrupts
# @returns Fail the test if return code is non-zero

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env
source ../common/common.sh

# helper function
usage() {
	cat <<-EOF
	usage: ./${0##*/}
	-m workqueue mode, dedicated or shared
	-i times of iteriration
	-t number of thread
	-h HELP info
EOF
}

while getopts :m:i:t: arg; do
	case $arg in
		m)
			wq_mode=$OPTARG
		;;
		i)
			iterations=$OPTARG
		;;
		t)
			threads=$OPTARG
		;;
		h)
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

./remove_iaa_crypto.sh
rmmod idxd_vdev
rmmod idxd
if [ $? != 0 ]; then
	die "Faile to rmmod idxd"
fi
modprobe idxd

# parse dsa0 pcie bus:device.function
domain=`ls -l /sys/bus/dsa/devices/dsa0 | awk -F '/' '{print $(NF - 1)}' | awk -F ':' '{print $1}'`
bus=`ls -l /sys/bus/dsa/devices/dsa0 | awk -F '/' '{print $(NF - 1)}' | awk -F ':' '{print $2}'`
dev_func=`ls -l /sys/bus/dsa/devices/dsa0 | awk -F '/' '{print $(NF - 1)}' | awk -F ':' '{print $3}'`
dbdf="$domain:$bus:$dev_func"
bdf="$bus:$dev_func"

# turn on and clear the trace event for irq vector
echo > /sys/kernel/debug/tracing/trace
echo 1 > /sys/kernel/debug/tracing/events/irq_vectors/vector_config/enable

# config and enable work queue
if [ "$wq_mode" = "dedicated" ]; then
	./accel_config.sh config-wq --group-id=0 --mode="dedicated" --name="wq0.0" --type="kernel" --driver-name="dmaengine" --priority=10 --wq-size=16 --block-on-fault=1 dsa0/wq0.0
elif [ "$wq_mode" = "shared" ]; then
	./accel_config.sh config-wq --group-id=0 --mode="shared" --name="wq0.0" --type="kernel" --driver-name="dmaengine" --priority=10 --wq-size=16 --block-on-fault=1 --threshold=16 dsa0/wq0.0
else
	die "Unknown wq mode: $wq_mode"
fi
./accel_config.sh config-engine dsa0/engine0.0 --group-id=0
./accel_config.sh enable-device dsa0
./accel_config.sh enable-wq dsa0/wq0.0

# parse the dynamically allocated irq number, vector number, cpu index, lapic index and the value in interrupt remapping table
irq_assigned=`cat /sys/kernel/debug/tracing/trace | awk 'END {print}' | awk -F ' ' '{print $6}' | awk -F '=' '{print $2}'`
vector_assigned=`cat /sys/kernel/debug/tracing/trace | awk 'END {print}' | awk -F ' ' '{print $7}' | awk -F '=' '{print $2}'`
cpu_assigned=`cat /sys/kernel/debug/tracing/trace | awk 'END {print}' | awk -F ' ' '{print $8}' | awk -F '=' '{print $2}'`
lapic_assigned=`cat /sys/kernel/debug/tracing/trace | awk 'END {print}' | awk -F ' ' '{print $9}' | awk -F 'x' '{print $2}'`
lapic_assigned=`echo ${lapic_assigned:2}`
vector_in_irte=`cat /sys/kernel/debug/iommu/intel/ir_translation_struct | grep "$bdf $lapic_assigned" | awk -F ' ' '{print $4}'`
vector_in_irte="0x$vector_in_irte"
vector_in_irte=`echo $((vector_in_irte))` # hex to decimal

# do dmatest to generate interrupts
modprobe dmatest
echo 2000 > /sys/module/dmatest/parameters/timeout
echo $iterations > /sys/module/dmatest/parameters/iterations
echo $threads > /sys/module/dmatest/parameters/threads_per_chan
echo "" > /sys/module/dmatest/parameters/channel
echo 0 > /sys/module/dmatest/parameters/polled
echo 1 > /sys/module/dmatest/parameters/run
cat /sys/module/dmatest/parameters/wait

# parse the actual irq number and count
irq_num=`cat /proc/interrupts | grep "$dbdf" | grep "idxd-portal" | awk -F ' ' '{print $1}' | awk -F ':' '{print $1}'`
irq_count=`cat /proc/interrupts | grep "$dbdf" | grep "idxd-portal" | awk -F ' ' -v n=$(($cpu_assigned+2)) '{print $n}'`

# unload and disable work queue
rmmod dmatest
./accel_config.sh disable-wq dsa0/wq0.0
./accel_config.sh disable-device dsa0

# turn off and clear the trace event for irq vector
echo 0 > /sys/kernel/debug/tracing/events/irq_vectors/vector_config/enable
echo > /sys/kernel/debug/tracing/trace

# check result
if [ "$vector_assigned" != "$vector_in_irte" ]; then
	die "allocated vector $vector_assigned is different with $vector_in_irte in interrupt remapping table"
fi

if [ "$irq_assigned" != "$irq_num" ]; then
	die "allocated irq $irq_assigned is different with $irq_num"
fi

if [ "$irq_count" != "$iterations" ]; then
	die "actual irq count $irq_count is not $iterations"
fi

echo "$wq_mode wq: intr test passed!"

exit 0
