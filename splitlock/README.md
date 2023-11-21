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
2. Test if the locked instruction will trigger #AC.

## Expected result
All test results should show pass, no fail.
