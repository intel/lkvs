#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

# @desc This script prepare and run $TESTCASE in for $FEATURE intr
# in VM; please note, $FEATURE name and subfolder name under guest-test
# must be the exactly same, here FEATURE=intr

###################### Variables ######################
## common variables example ##
SCRIPT_DIR_LOCAL="$( cd "$( dirname "$0" )" && pwd )"
echo "$SCRIPT_DIR_LOCAL"
# get test scenario config for $FEATURE tdx test_executor
source "$SCRIPT_DIR_LOCAL"/../guest-test/test_params.py
## end of common variables example ##

###################### Functions ######################
## $FEATURE specific Functions ##

###################### Do Works ######################
## common works example ##
cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env
source ../common/common.sh

# get test_executor common functions:
source "$lkvs_root"/guest-test/guest.test_executor.sh

GUEST_TEST_DIR="/root/guest-test/"
## $FEATURE specific code path ##
# select test_functions by $TESTCASE
case "$TESTCASE" in
	INTR_PT_DSA_DWQ_1)
		rm -rf common.sh
		wget https://raw.githubusercontent.com/intel/lkvs/main/common/common.sh
		sshpass -e ssh -p "$PORT" -o StrictHostKeyChecking=no root@localhost << EOF
		rm -rf $GUEST_TEST_DIR
		mkdir $GUEST_TEST_DIR
EOF

		sshpass -e scp -P "$PORT" -o StrictHostKeyChecking=no ./common.sh root@localhost:"$GUEST_TEST_DIR"
		sshpass -e scp -P "$PORT" -o StrictHostKeyChecking=no ./accel_config.sh root@localhost:"$GUEST_TEST_DIR"
		test_print_trc "Guest VM test script prepare complete"

		echo 1 > /sys/kernel/debug/tracing/tracing_on
		echo 1 > /sys/kernel/debug/tracing/events/kvm/kvm_pi_irte_update/enable

		sshpass -e ssh -p "$PORT" -o StrictHostKeyChecking=no root@localhost << EOF
		cd $GUEST_TEST_DIR
		echo 1 > /sys/kernel/debug/tracing/events/irq_vectors/vector_config/enable
		./accel_config.sh config-wq --group-id=0 --mode="dedicated" --name="wq0.0" --type="kernel" --driver-name="dmaengine" --priority=10 --wq-size=16 dsa0/wq0.0
		./accel_config.sh config-engine dsa0/engine0.0 --group-id 0
		./accel_config.sh enable-device dsa0
		./accel_config.sh enable-wq dsa0/wq0.0
		modprobe dmatest
		echo 2000 > /sys/module/dmatest/parameters/timeout
		echo 100 > /sys/module/dmatest/parameters/iterations
		echo 1 > /sys/module/dmatest/parameters/threads_per_chan
		echo "" > /sys/module/dmatest/parameters/channel
		echo 0 > /sys/module/dmatest/parameters/polled
		echo 1 > /sys/module/dmatest/parameters/run
		cat /sys/module/dmatest/parameters/wait

		echo "Guest trace event:"
		cat /sys/kernel/debug/tracing/trace
		echo "Interrupt statistics:"
		cat /proc/interrupts | grep idxd-portal
EOF

		guest_irq_assigned=`sshpass -e ssh -p $PORT -o StrictHostKeyChecking=no root@localhost << EOF | awk 'END {print}' | awk -F ' ' '{print $6}' | awk -F '=' '{print $2}'
		cat /sys/kernel/debug/tracing/trace
EOF`

		guest_vector_assigned=`sshpass -e ssh -p $PORT -o StrictHostKeyChecking=no root@localhost << EOF | awk 'END {print}' | awk -F ' ' '{print $7}' | awk -F '=' '{print $2}'
		cat /sys/kernel/debug/tracing/trace
EOF`

		guest_cpu_assigned=`sshpass -e ssh -p $PORT -o StrictHostKeyChecking=no root@localhost << EOF | awk 'END {print}' | awk -F ' ' '{print $8}' | awk -F '=' '{print $2}'
		cat /sys/kernel/debug/tracing/trace
EOF`

		guest_irq_num=`sshpass -e ssh -p $PORT -o StrictHostKeyChecking=no root@localhost << EOF | grep idxd-portal | tail -n1 | awk -F ' ' '{print $1}' | awk -F ':' '{print $1}'
		cat /proc/interrupts
EOF`

		guest_irq_count=`sshpass -e ssh -p $PORT -o StrictHostKeyChecking=no root@localhost << EOF | grep idxd-portal | tail -n1 | awk -F ' ' -v n=$(($guest_cpu_assigned+2)) '{print $n}'
		cat /proc/interrupts
EOF`

		echo "Host trace event:"
		cat /sys/kernel/debug/tracing/trace
		echo "Interrupt remapping table:"
		cat /sys/kernel/debug/iommu/intel/ir_translation_struct | grep "00:01.0"

		host_cpu_assigned=`cat /sys/kernel/debug/tracing/trace | awk 'END {print}' | awk -F ' ' '{print $17}' | awk -F ',' '{print $1}'`
		host_vector_assigned=`cat /sys/kernel/debug/tracing/trace | awk 'END {print}' | awk -F ' ' '{print $21}' | awk -F ',' '{print $1}'`
		host_vector_assigned=`echo $((host_vector_assigned))` # hex to decimal
		host_vector_in_irte=`cat /sys/kernel/debug/iommu/intel/ir_translation_struct | grep "00:01.0" | awk 'END {print}' | awk -F ' ' '{print $5}'`

		echo 0 > /sys/kernel/debug/tracing/events/kvm/kvm_pi_irte_update/enable

		sshpass -e ssh -p "$PORT" -o StrictHostKeyChecking=no root@localhost << EOF
		rmmod dmatest
		cd $GUEST_TEST_DIR
		./accel_config.sh disable-wq dsa0/wq0.0
		./accel_config.sh disable-device dsa0
EOF

		if [ "$guest_irq_assigned" != "$guest_irq_num" ]; then
			test_print_err "guest_irq_assigned $guest_irq_assigned not equal to guest_irq_num $guest_irq_num"
			die "Failed on $TESTCASE"
		fi

		if [ "$guest_vector_assigned" != "$host_vector_assigned" ]; then
			test_print_err "guest_vector_assigned $guest_vector_assigned not equal to host_vector_assigned $host_vector_assigned"
			die "Failed on $TESTCASE"
		fi

		if [ "$guest_cpu_assigned" != "$host_cpu_assigned" ]; then
			test_print_err "guest_cpu_assigned $guest_cpu_assigned not equal to host_cpu_assigned $host_cpu_assigned"
			die "Failed on $TESTCASE"
		fi

		if [ "$guest_irq_count" != "100" ]; then
			test_print_err "guest_irq_count $guest_irq_count not equal to 100"
			die "Failed on $TESTCASE"
		fi

		if [[ $GCOV == "off" ]]; then
			guest_test_close
		fi
	;;
	INTR_PT_DSA_SWQ_1)
		rm -rf common.sh
		wget https://raw.githubusercontent.com/intel/lkvs/main/common/common.sh
		sshpass -e ssh -p "$PORT" -o StrictHostKeyChecking=no root@localhost << EOF
		rm -rf $GUEST_TEST_DIR
		mkdir $GUEST_TEST_DIR
EOF

		sshpass -e scp -P "$PORT" -o StrictHostKeyChecking=no ./common.sh root@localhost:"$GUEST_TEST_DIR"
		sshpass -e scp -P "$PORT" -o StrictHostKeyChecking=no ./accel_config.sh root@localhost:"$GUEST_TEST_DIR"
		test_print_trc "Guest VM test script prepare complete"

		echo 1 > /sys/kernel/debug/tracing/tracing_on
		echo 1 > /sys/kernel/debug/tracing/events/kvm/kvm_pi_irte_update/enable

		sshpass -e ssh -p "$PORT" -o StrictHostKeyChecking=no root@localhost << EOF
		cd $GUEST_TEST_DIR
		echo 1 > /sys/kernel/debug/tracing/events/irq_vectors/vector_config/enable
		./accel_config.sh config-wq --group-id=0 --mode=shared --name="wq0.0" --type="kernel" --driver-name="dmaengine" --priority=10 --wq-size=16 --threshold=2 dsa0/wq0.0
		./accel_config.sh config-engine dsa0/engine0.0 --group-id 0
		./accel_config.sh enable-device dsa0
		./accel_config.sh enable-wq dsa0/wq0.0
		modprobe dmatest
		echo 2000 > /sys/module/dmatest/parameters/timeout
		echo 100 > /sys/module/dmatest/parameters/iterations
		echo 1 > /sys/module/dmatest/parameters/threads_per_chan
		echo "" > /sys/module/dmatest/parameters/channel
		echo 0 > /sys/module/dmatest/parameters/polled
		echo 1 > /sys/module/dmatest/parameters/run
		cat /sys/module/dmatest/parameters/wait

		echo "Guest trace event:"
		cat /sys/kernel/debug/tracing/trace
		echo "Interrupt statistics:"
		cat /proc/interrupts | grep idxd-portal
EOF

		guest_irq_assigned=`sshpass -e ssh -p $PORT -o StrictHostKeyChecking=no root@localhost << EOF | awk 'END {print}' | awk -F ' ' '{print $6}' | awk -F '=' '{print $2}'
		cat /sys/kernel/debug/tracing/trace
EOF`

		guest_vector_assigned=`sshpass -e ssh -p $PORT -o StrictHostKeyChecking=no root@localhost << EOF | awk 'END {print}' | awk -F ' ' '{print $7}' | awk -F '=' '{print $2}'
		cat /sys/kernel/debug/tracing/trace
EOF`

		guest_cpu_assigned=`sshpass -e ssh -p $PORT -o StrictHostKeyChecking=no root@localhost << EOF | awk 'END {print}' | awk -F ' ' '{print $8}' | awk -F '=' '{print $2}'
		cat /sys/kernel/debug/tracing/trace
EOF`

		guest_irq_num=`sshpass -e ssh -p $PORT -o StrictHostKeyChecking=no root@localhost << EOF | grep idxd-portal | tail -n1 | awk -F ' ' '{print $1}' | awk -F ':' '{print $1}'
		cat /proc/interrupts
EOF`

		guest_irq_count=`sshpass -e ssh -p $PORT -o StrictHostKeyChecking=no root@localhost << EOF | grep idxd-portal | tail -n1 | awk -F ' ' -v n=$(($guest_cpu_assigned+2)) '{print $n}'
		cat /proc/interrupts
EOF`

		echo "Host trace event:"
		cat /sys/kernel/debug/tracing/trace
		echo "Interrupt remapping table:"
		cat /sys/kernel/debug/iommu/intel/ir_translation_struct
		host_cpu_assigned=`cat /sys/kernel/debug/tracing/trace | awk 'END {print}' | awk -F ' ' '{print $17}' | awk -F ',' '{print $1}'`
		host_vector_assigned=`cat /sys/kernel/debug/tracing/trace | awk 'END {print}' | awk -F ' ' '{print $21}' | awk -F ',' '{print $1}'`
		host_vector_assigned=`echo $((host_vector_assigned))` # hex to decimal
		host_vector_in_irte=`cat /sys/kernel/debug/iommu/intel/ir_translation_struct | grep "00:01.0" | awk 'END {print}' | awk -F ' ' '{print $5}'`

		echo 0 > /sys/kernel/debug/tracing/events/kvm/kvm_pi_irte_update/enable

		sshpass -e ssh -p "$PORT" -o StrictHostKeyChecking=no root@localhost << EOF
		rmmod dmatest
		cd $GUEST_TEST_DIR
		./accel_config.sh disable-wq dsa0/wq0.0
		./accel_config.sh disable-device dsa0
EOF

		if [ "$guest_irq_assigned" != "$guest_irq_num" ]; then
			test_print_err "guest_irq_assigned $guest_irq_assigned not equal to guest_irq_num $guest_irq_num"
			die "Failed on $TESTCASE"
		fi

		if [ "$guest_vector_assigned" != "$host_vector_assigned" ]; then
			test_print_err "guest_vector_assigned $guest_vector_assigned not equal to host_vector_assigned $host_vector_assigned"
			die "Failed on $TESTCASE"
		fi

		if [ "$guest_cpu_assigned" != "$host_cpu_assigned" ]; then
			test_print_err "guest_cpu_assigned $guest_cpu_assigned not equal to host_cpu_assigned $host_cpu_assigned"
			die "Failed on $TESTCASE"
		fi

		if [ "$guest_irq_count" != "100" ]; then
			test_print_err "guest_irq_count $guest_irq_count not equal to 100"
			die "Failed on $TESTCASE"
		fi

		if [[ $GCOV == "off" ]]; then
			guest_test_close
		fi
	;;
	:)
		test_print_err "Must specify the test scenario option by [-t]"
		usage && exit 1
	;;
	\?)
		test_print_err "Input test case option $TESTCASE is not supported"
		usage && exit 1
	;;
esac
