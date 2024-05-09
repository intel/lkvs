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
### ifs_0 scan test cases, it works on SPR(Sapphire Rapids) platform and future server
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

### ifs_1 array BIST(Board Integrated System Test), it works on EMR(Emerald Rapids) and future server
```
./ifs_tests.sh -m 1 -p all -n ifs_array_scan
It tests all cpu ifs_1 array BIST scan test.

./ifs_tests.sh -m 1 -p ran -n ifs_array_off_sib -t 10
It tests random cpu offline, and then ifs_1 scan the sibling cpu should fail as expected.

./ifs_tests.sh -m 1 -p ran -n ifs_array_offran -t 5
It tests the random cpu off line, and then ifs_1 scan this cpu should fail as expected.

./ifs_tests.sh -m 1 -p ran -n ifs_array_cpuran_fullload -t 10
It tests the random cpu with full load, and ifs_1 scan should pass.

./ifs_tests.sh -m 1 -p ran -b 1 -n ifs_loop -t 500
It tests the random cpu with ifs_1 scan 500 times, all the scan should pass.
```