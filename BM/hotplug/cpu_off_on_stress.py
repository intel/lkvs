#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation

""" 
This script performs CPU offline/online stress test for the specified number of cycles.
Prerequisties:
Install the avocado framework and the required dependencies with below command:
    git clone git://github.com/avocado-framework/avocado.git
    cd avocado
    pip install .
"""

import subprocess
import time
import os

from avocado.core.nrunner.runnable import Runnable

__author__ = "Wendy Wang"
__copyright__ = "GPL-2.0-only"
__license__ = "GPL version 2"

# Determine the directory of the current script
script_dir = os.path.dirname(os.path.abspath(__file__)) 

# Construce relative paths to the common.sh file
common_sh_path = os.path.join(script_dir, '../../common/common.sh')

class ShellCommandRunnable(Runnable):
    def __init__(self, command):
        self.command = command
        self.stdout = None
        self.stderr = None
    
    def run(self):
        try:
            result = subprocess.run(self.command, shell=True, check=True, capture_output=True, text=True, executable='/bin/bash')
            self.stdout = result.stdout
            self.stderr = result.stderr
            print(f"command '{self.command}' executed successfully.")
        
            return result.returncode
        except subprocess.CalledProcessError as e:
            self.stderr = e.stderr
            self.stdout = e.stdout
            print (f"Error occurred: {self.stderr}")
            return e.returncode

def get_online_cpu_count():
    try:
        # Run 'lscpu' and filter out the number of online CPUs
        lscpu_command = "lscpu | grep 'On-line CPU' | awk '{print $NF}'"
        result = ShellCommandRunnable(lscpu_command)

        # Run the command
        return_code = result.run()
        if return_code != 0:
            raise Exception ("Failed to get CPU count")
        
        if result.stdout is None:
            raise Exception ("No output from lscpu command")
        
        cpu_range = result.stdout.strip().split('-')
        print(f"cpu range: {cpu_range}")
        if len(cpu_range) == 2:
            return int(cpu_range[1]) + 1 
        else:
            return 1 # Only one CPU available
    except Exception as e:
        print (f"Error getting cpu count:{e}")
        return 0

def check_dmesg_error():
    result = ShellCommandRunnable(f"source {common_sh_path} && extract_case_dmesg")
    result.run()
    dmesg_log = result.stdout

    # Check any failure, error, bug in the dmesg log when stress is running
    if dmesg_log and any(keyword in dmesg_log for keyword in ["fail","error","Call Trace","Bug","error"]):
        return dmesg_log
    return None

def cpu_off_on_stress(cycle):
    """Perform CPU offline/online stress test for the specified number of cycles"""
    try:        
        cpu_num = get_online_cpu_count()
        if cpu_num == 0:
            raise Exception("On-line CPU is not available.")
        
        print (f"The max CPU number is: {cpu_num}")

        # Start stress test cycle
        for i in range(1, cycle + 1):
            print(f"CPUs offline online stress cycle {i}")

            for cpu_id in range(cpu_num):
                if cpu_id == 0:
                    continue
                print(f"Offline CPU{cpu_id}")
                # Bring CPUs offline
                result = ShellCommandRunnable(f"echo 0 > /sys/devices/system/cpu/cpu{cpu_id}/online")
                result_code = result.run()
                if result_code != 0:
                    raise Exception(f"Failed to bring CPU{cpu_id} offline")
            
            time.sleep(1)
            
            for cpu_id in range(cpu_num):
                if cpu_id == 0:
                    continue           
                print(f"Online CPU{cpu_id}")     
                # Bring CPUs online
                result = ShellCommandRunnable(f"echo 1 > /sys/devices/system/cpu/cpu{cpu_id}/online")
                result_code = result.run()
                if result_code != 0:
                    raise Exception(f"Failed to bring CPU{cpu_id} online")

    except Exception as e:
        print(f"Error during CPU stress testing:{e}")

    # Check dmesg log
    dmesg_log = check_dmesg_error()
    if dmesg_log:
        print(f"Kernel dmesg shows failure after CPU offline/online stress: {dmesg_log}")
        raise Exception("Kernel dmesg show failure")
    else:
        print("Kernel dmesg shows Okay after CPU offline/online stress.")

    
if __name__== '__main__':
    cpu_off_on_stress(5)
