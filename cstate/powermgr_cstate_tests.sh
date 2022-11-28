#!/bin/bash
## SPDX-License-Identifier: GPL-2.0
# @Author   wendy.wang@intel.com
# @Desc     Test script to verify Intel Core Cstate functionality
# @History  Created Nov 01 2022 - Created

cd "$(dirname $0)" 2>/dev/null
source ../.env
source common.sh

CPU_SYSFS_PATH="/sys/devices/system/cpu"
CPU_BUS_SYSFS_PATH="/sys/bus/cpu/devices/"
CPU_IDLE_SYSFS_PATH="/sys/devices/system/cpu/cpuidle"

current_cpuidle_driver=$(cat "$CPU_IDLE_SYSFS_PATH"/current_driver)

#Turbostat tool is required to run core cstate cases
turbostat sleep 1 1>/dev/null 2>&1 || skip_test "Turbostat tool is required to \
to run core cstate cases, please get it from latest upstream kernel-tools."

#Funtion to verify if Intel_idle driver refer to BIOS _CST table
test_cstate_table_name() {
    local cstate_name
    local name

    cstate_name=$(cat "$CPU_SYSFS_PATH"/cpu0/cpuidle/state*/name)
    name=$(echo "$cstate_name" | grep ACPI)
    if [[ -n $name ]]; then
        test_print_trc "$cstate_name"
        die "Intel_idle driver refers to ACPI cstate table."
    else
        test_print_trc "$cstate_name"
        test_print_trc "Intel_idle driver refers to BIOS _CST table."
    fi
}

#Funtion to verify if current idle driver is intel_idle
check_intel_idle() {
    [[ $current_cpuidle_driver == "intel_idle" ]] || {
        block_test "If the platform does not support Intel_Idle driver yet, \
    please ignore this test case"
    }
}

#Function to switch each core cstate
test_cstate_switch_idle() {
    local usage_before=()
    local usage_after=()
    local CPUS
    CPUS=$(ls "$CPU_BUS_SYSFS_PATH" | xargs)
    local cpu_num
    cpu_num=$(lscpu | grep "^CPU(s)" | awk '{print $2}')

    if [[ -n "$CPUS" ]]; then
        for cpu in $CPUS; do
            STATES=$(ls "${CPU_BUS_SYSFS_PATH}"/"${cpu}"/cpuidle | grep state | xargs)
            if [[ -n "$STATES" ]]; then
                for state in $STATES; do
                    # Disable stateX of cpuX
                    echo 1 >"${CPU_SYSFS_PATH}/${cpu}/cpuidle/${state}/disable"
                done
            else
                die "fail to get state node for $cpu"
            fi
        done
    else
        die "fail to get cpu sysfs directory"
    fi

    for state in $STATES; do
        test_print_trc ------ loop for "$state" ------

        # Count usage of the stateX of cpuX before enable stateX
        i=0
        while [[ "$i" != "$cpu_num" ]]; do
            usage_before[$i]=$(cat "${CPU_SYSFS_PATH}"/cpu"${i}"/cpuidle/"${state}"/usage)
            [[ -n ${usage_before[$i]} ]] || die "fail to count usage_before of $state of cpu${i}"
            i=$((i + 1))
        done

        # Enable stateX of cpuX
        for cpu in $CPUS; do
            echo 0 >"${CPU_SYSFS_PATH}/${cpu}/cpuidle/${state}/disable"
        done

        # Sleep and wait for entry of the state
        sleep 30

        # Count usage of the stateX for cpuX after enable stateX
        i=0
        while [[ "$i" != "$cpu_num" ]]; do
            usage_after[$i]=$(cat "${CPU_SYSFS_PATH}"/cpu"${i}"/cpuidle/"${state}"/usage)
            [[ -n ${usage_after[$i]} ]] || die "fail to count usage_after of $state of cpu${i}"
            i=$((i + 1))
        done

        # Compare the usage to see if the cpuX enter stateX
        i=0
        while [[ "$i" != "$cpu_num" ]]; do
            if [[ ${usage_after[${i}]} -gt ${usage_before[${i}]} ]]; then
                test_print_trc "cpu${i} enter $state successfully"
            else
                die "cpu${i} fail to enter $state"
            fi
            i=$((i + 1))
        done
    done
}

test_cstate_switch_intel_idle() {
    check_intel_idle
    test_cstate_switch_idle
}

#The Core C7 is only supported on Intel® Client platform
#This funtion is to check Core C7 residency during runtime
judge_cc7_residency_during_idle() {
    columns="Core,CPU%c1,CPU%c6,CPU%c7"
    turbostat_output=$(turbostat -i 10 --quiet \
        --show $columns sleep 10 2>&1)
    test_print_trc "$turbostat_output"
    CC7_val=$(echo "$turbostat_output" | grep -E "^-" | awk '{print $4}')
    test_print_trc "Core CPU C7 residency :$CC7_val"
    [[ $CC7_val == "0.00" ]] && die "CPU Core C7 residency is not available."

    # Judge whether CC7 residency is available during idle
    turbostat_CC7_value=$(echo "scale=2; $CC7_val > 0.00" | bc)
    [[ $turbostat_CC7_value -eq 1 ]] ||
        die "Did not get CPU Core C7 residency during idle \
when $current_cpuidle_driver is running."
    test_print_trc "CPU Core C7 residency is available during idle \
when $current_cpuidle_driver is running"
}

#The Core C7 is only supported on Intel® Client platforms
#This funtion is to check Core C7 residency for S2idle path
judge_cc7_residency_during_s2idle() {
    columns="Core,CPU%c1,CPU%c6,CPU%c7"
    turbostat_output=$(
        turbostat --show $columns \
            rtcwake -m freeze -s 15 2>&1
    )
    turbostat_output=$(grep "CPU%c7" -A1 <<<"$turbostat_output")
    test_print_trc "$turbostat_output"
    CC7_val=$(echo "$turbostat_output" | grep -E "^-" | awk '{print $4}')
    test_print_trc "Core CPU C7 residency :$CC7_val"
    [[ $CC7_val == "0.00" ]] && die "CPU Core C7 residency is not available."

    # Judge whether CC7 residency is available during idle
    turbostat_CC7_value=$(echo "scale=2; $CC7_val > 0.00" | bc)
    [[ $turbostat_CC7_value -eq 1 ]] ||
        die "Did not get CPU Core C7 residency during S2idle \
when $current_cpuidle_driver is running"
    test_print_trc "CPU Core C7 residency is available during S2idle \
when $current_cpuidle_driver is running."
}

#The Core C6 is the deepest cstate on Intel® Server platforms
test_server_all_cpus_deepest_cstate() {
    local unexpected_cstate=0.00

    columns="sysfs,CPU%c1,CPU%c6"
    turbostat_output=$(turbostat -i 10 --quiet \
        --show $columns sleep 10 2>&1)
    test_print_trc "Turbostat log: $turbostat_output"
    all_deepest_cstate=$(echo "$turbostat_output" |
        awk '{for(i=0;++i<=NF;)a[i]=a[i]?a[i] FS $i:$i} END{for(i=0;i++<=NF;)print a[i]}' | grep "CPU%c6")
    test_print_trc "The deepest core cstate is: $all_deepest_cstate"
    if [[ $all_deepest_cstate =~ $unexpected_cstate ]]; then
        # test_print_trc "Getting CPU C6 state by reading MSR 0x3fd:"
        # rdmsr -a 0x3fd
        die "CPU core did not enter the deepest cstate!"
    else
        test_print_trc "All the CPU enter the deepest cstate!"
    fi
}

#The Core C6 is only supported on Intel® Server platform
#This funtion is to check Core C6 residency during runtime
judge_cc6_residency_during_idle() {
    columns="Core,CPU%c1,CPU%c6"
    turbostat_output=$(turbostat -i 10 --quiet \
        --show $columns sleep 10 2>&1)
    test_print_trc "Turbostat log: $turbostat_output"
    CC6_val=$(echo "$turbostat_output" | grep -E "^-" | awk '{print $3}')
    test_print_trc "CPU Core C6 residency :$CC6_val"
    [[ -n $CC6_val ]] || die "CPU Core C6 residency is not available."

    # Judge whether CC6 residency is available during idle
    turbostat_CC6_value=$(echo "scale=2; $CC6_val > 0.00" | bc)
    if [[ $turbostat_CC6_value -eq 1 ]]; then
        test_print_trc "CPU Core C6 residency is available \
during idle when $current_cpuidle_driver is running"
    else
        die "Did not get CPU Core C6 residency during idle \
when $current_cpuidle_driver is running"
    fi
}

test_cpu_core_c7_residency_intel_idle() {
    check_intel_idle
    judge_cc7_residency_during_idle
}

test_cpu_core_c7_residency_intel_s2idle() {
    check_intel_idle
    judge_cc7_residency_during_s2idle
}

test_cpu_core_c6_residency_intel_idle() {
    check_intel_idle
    judge_cc6_residency_during_idle
}

cc_state_disable_enable() {
    local cc=$1
    local setting=$2

    for ((i = 0; i < cpu_num; i++)); do
        #Find Core Cx state
        cc_num=$(grep . /sys/devices/system/cpu/cpu0/cpuidle/state*/name |
            sed -n "/$cc$/p" | awk -F "/" '{print $8}' | cut -c 6)
        test_print_trc "Core $cc state name is: $cc_num"
        [[ -n "$cc_num" ]] || block_test "Did not get Core $cc state."
        #Change Core Cx state
        do_cmd "echo $setting > /sys/devices/system/cpu/cpu$i/cpuidle/state$cc_num/disable"
        let deeper=$cc_num+1
        #Change deeper Core Cx state
        for ((j = deeper; j < state_num; j++)); do
            do_cmd "echo $setting > /sys/devices/system/cpu/cpu$i/cpuidle/state$j/disable"
        done
    done
}

disable_cc_check_pc() {
    local cc=$1
    local pc_y=$2
    local pc_n=$3
    local cpu_num
    local columns

    cpu_num=$(lscpu | grep "^CPU(s)" | awk '{print $2}')
    state_num=$(ls "${CPU_BUS_SYSFS_PATH}"/cpu0/cpuidle | grep -c state)
    columns="Pkg%pc2,Pkg%pc3,Pkg%pc6,Pkg%pc7,Pkg%pc8,Pkg%pc9,Pk%pc10"

    cc_state_disable_enable "$cc" 1

    #Check Package Cstates, CC10 disable--> expect PC8 only
    #CC8 and deeper disable--> PC6 only
    tc_out=$(turbostat -q --show $columns -i 1 sleep 20 2>&1)
    [[ -n "$tc_out" ]] || die "Did not get turbostat log"
    test_print_trc "turbostat tool output: $tc_out"
    pc_y_res=$(echo "$tc_out" |
        awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' |
        grep "$pc_y" | awk -F " " '{print $3}')
    pc_n_res=$(echo "$tc_out" |
        awk '{for(k=0;++k<=NF;)a[k]=a[k]?a[k] FS $k:$k} END{for(k=0;k++<NF;)print a[k]}' |
        grep "$pc_n" | awk -F " " '{print $3}')
    [[ -n "$pc_y_res" ]] || die "Did not get $pc_y state."
    [[ -n "$pc_n_res" ]] || die "Did not get $pc_n state."
    if [[ $(echo "scale=2; $pc_y_res > 0.00" | bc) -eq 1 ]] && [[ $pc_n_res == "0.00" ]]; then
        cc_state_disable_enable "$cc" 0
        test_print_trc "Expected to get $pc_y only when disable $cc and deeper state.\
$pc_y residency: $pc_y_res; $pc_n residency: $pc_n_res"
    else
        cc_state_disable_enable "$cc" 0
        die "Did not get $pc_y residency after disable $cc and deeper states. \
$pc_y residency: $pc_y_res; $pc_n residency: $pc_n_res"
    fi
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

core_cstate_test() {
    case $TEST_SCENARIO in
    verify_cstate_name)
        test_cstate_table_name
        ;;
    verify_cstate_switch)
        test_cstate_switch_intel_idle
        ;;
    verify_client_core_c7_residency_during_runtime)
        test_cpu_core_c7_residency_intel_idle
        ;;
    verify_client_core_c7_residency_during_s2idle)
        test_cpu_core_c7_residency_intel_s2idle
        ;;
    verify_client_pkg6_by_disabling_cc8)
        disable_cc_check_pc C8 Pkg%pc6 Pkg%pc8
        ;;
    verify_client_pkg8_by_disabling_cc10)
        disable_cc_check_pc C10 Pkg%pc8 Pk%pc10
        ;;
    verify_server_core_cstate6_residency)
        test_cpu_core_c6_residency_intel_idle
        ;;
    verify_server_all_cores_cstate6)
        test_server_all_cpus_deepest_cstate
        ;;
    *)
        block_test "Wrong Case Id is assigned: $CASE_ID"
        ;;
    esac
}

core_cstate_test
