##!/bin/bash
# Some examples on how to trigger the cpuid and capture #VE.
# Register the kretprobe.
echo kretprobe > /sys/kernel/debug/tdx/tdx-tests

# Trigger the cpuid and capture #VE. The captured information is printed in dmesg.
echo trigger_cpuid 0x1f 0x0 0x0 0x0 > /sys/kernel/debug/tdx/tdx-tests

# Unregister the kretprobe.
echo unregister > /sys/kernel/debug/tdx/tdx-tests
