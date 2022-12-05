# PT
Intel Processor Trace (Intel PT) is an extension of Intel Architecture that
captures information about software execution using dedicated hardware facilities
that cause only minimal performance perturbation to the software being traced.

## Build Tips
Need prepare intel-pt.h and libipt.so for building PT related cases.
You can get them in https://github.com/intel/libipt.

## Usage
Need libipt.so.2 and add it into LD_LIBRARY_PATH before running PT cases.
You can build libipt.so.2 in https://github.com/intel/libipt.

```
./branch
```
Disable branch and check no TIP/FUP/TNT.

```
./cpl 1
```
User mode trace check
```
./cpl 2
```
Kernel mode trace check

```
./psb
```
Check if psb package there.

```
./negative_test
```
Check reserved bit cannot be set.

```
./nonroot_test 1
```
Non root user do full trace check.
```
./nonroot_test 2
```
Non root user do snapshot trace check.

## Expected result
All test results should show pass, no fail.
