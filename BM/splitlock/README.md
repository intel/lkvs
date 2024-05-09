# SPLIT LOCK

## Description
A split lock is any atomic operation whose operand crosses two cache lines.
Since the operand spans two cache lines and the operation must be atomic,
the system locks the bus while the CPU accesses the two cache lines.

A bus lock is acquired through either split locked access to writeback (WB)
memory or any locked access to non-WB memory. This is typically thousands of
cycles slower than an atomic operation within a cache line. It also disrupts
performance on other cores and brings the whole system to its knees.

## Usage
make
./sl_test
1. Linux kernel driver will export the split_lock_detect flag to /proc/cpuinfo
   if hardware supports this feature.
2. Test if the locked instruction will trigger #AC. If no split_lock_detect is
   not set by default or it is split_lock_detect=warn, #AC will be triggered.
   The boot parameter could also be set as fatal or ratelimit(ratelimit:1 max
   ratelimit:1000). If split_lock_detect=fatal, split lock test will output
   "Caught SIGBUS/#AC" in console.
   For more, please refer to handle_bus_lock in arch/x86/kernel/cpu/intel.c.
Examples of exception in dmesg:
x86/split lock detection: #AC: sl_test/4354 took a split_lock trap at address: 0x401231
x86/split lock detection: #DB: sl_test/5137 took a bus_lock trap at address: 0x4011f5

## Expected result
All test results should show pass, no fail.
