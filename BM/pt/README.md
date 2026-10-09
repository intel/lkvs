# PT

Intel Processor Trace (Intel PT) is an extension of Intel Architecture that
captures information about software execution using dedicated hardware facilities
that cause only minimal performance perturbation to the software being traced.

## Build Tips

Need prepare intel-pt.h and libipt.so for building PT related cases.
You can get them in https://github.com/intel/libipt.

1. git clone https://github.com/intel/libipt
2. cd libipt
3. mkdir build && cd build
4. cmake ../
5. make
6. make install

```
# Disable branch and check no TIP/FUP/TNT.
./branch

# User mode trace check
./cpl 1

# Kernel mode trace check
./cpl 2

# ToPA usage check: a full trace buffer has to stop the trace once it is
# full, a snapshot buffer has to wrap around and keep tracing.
./bat_ipt 1 0

# Packet check in full trace mode, tracing the calling task, with user
# space excluded (mode 1) or kernel space excluded (mode 2).
./bat_ipt 3 1

# Packet check in snapshot mode, without any privilege level filter.
./bat_ipt 4 0

# The same packet check in full trace mode, repeated for every CPU.
./bat_ipt 5 0

# Check if psb package there.
./psb

# Check reserved bit cannot be set.
./negative_test

# Non root user do full trace check.
./nonroot_test 1

# Non root user do snapshot trace check.
./nonroot_test 2
```

## Expected result

All test results should show pass, no fail.

Note that bat_ipt reads the trace status out of the RTIT MSRs, so it needs
to run as root with the msr driver available. It loads the driver itself.

Usage for perf_tests.sh:

1. Make sure latest perf is there.
2. Run case as 
```
./perf_tests.sh -t <case name>
```
