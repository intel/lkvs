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
Usage for perf_tests.sh:

1. Make sure latest perf is there.
2. Run case as 
```
./perf_tests.sh -t <case name>
```
