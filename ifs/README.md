# IFS(In Field Scan) Test Cases

## Description
```
IFS old name is SAF(Scan At Field ), now the old feature name "SAF" will not be
used anymore and use the name "IFS" instead.
IFS is a feature which allows software to periodically test for latent faults
in non-array portions of the Core.
```

## Usage
make
```
./ifs_tests.sh -m 0 -p all -n load_ifs
It loads ifs driver with ifs mode 0 without any exceptions.

./ifs_tests.sh -m 0 -p all -b 1 -n ifs_batch
It loads ifs batch 1 blob file with ifs mode 0 without any exceptions.
Blob file is located in /lib/firmware/intel/ifs_0/ff-mm-ss-01.scan
Please check "cat /proc/cpuinfo | head" output
ff means "cpu family" number in hexadecimal.
mm means "model" number in hexadecimal.
ss means "stepping" number in hexadecimal.
01 means batch 01.

./ifs_tests.sh -m 0 -p all -b 1 -n legacy_twice_run
It loads batch 1 and executes ifs_0 scan twice in all cpus.

./ifs_tests.sh -m 0 -p all -b 2 -n legacy_twice_run
It loads batch 2 and executes ifs_0 scan twice in all cpus.

./ifs_tests.sh -m 0 -p all -b 3 -n legacy_twice_run
It loads batch 3 and executes ifs_0 scan twice in all cpus.

./ifs_tests.sh -m 0 -p all -b 1 -n img_version
It will check image version output is same as MSR output.

./ifs_tests.sh -m 0 -p all -b 1 -n reload_ifs
It tests reloading the ifs module without issue.
```
