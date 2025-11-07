# IFS(In-Field Scan) Test Cases

## Description
In-Field Scan has a roadmap of capabilities that will be included on current and future processors. Scan-at-Field (SAF) and Array Built In Self Test (BIST) are the first two features within the In-Field Scan family, and both are available on 5th Gen Intel® Xeon® processors.

For more explanation about IFS please see the link:
https://www.intel.com/content/www/us/en/support/articles/000099537/processors/intel-xeon-processors.html

## Pre-requisite
### Total Memory Encryption (TME)
The SAF feature of IFS requires the processor to reserve secure memory for loading scan test images. The Array BIST feature does not have this requirement. The SAF flow is dependent on the platform's ability to access the Processor Reserve Memory Region (PRMRR). To enable the PRMRR, the Total Memory Encryption (TME) feature must be enabled in the BIOS.

For BIOS setup references:
```
Socket Configuration - Processor Configuration - Memory Encryption (TME)
Socket Configuration - Processor Configuration - IFS - Enable SAF
```
### Scan Test images
The SAF tests the logic, caches, and arrays on the core by using scan test images. Array BIST for on-core caches and arrays which does not require a test image.
After download scan test images:
1. Create a directory named: **ifs_0** within the /lib/firmware/intel/
2. Extract the downloaded scan test images (ff-mm-ss-xx.scan) into the folder

ff-mm-ss-xx.scan:  (For example, SPR ifs image file sample:06-af-03-01.scan)
  ff: CPU family number in hexadecimal
  mm: CPU model number in hexadecimal
  ss: CPU stepping number in hexadecimal
  xx: scan files number in hexadecimal

### Kernel Configuration
```
CONFIG_X86_PLATFORM_DEVICES = y
CONFIG_INTEL_IFS = m
```

## How to check if IFS ready for testing?
Check ifs dependency:
```
modprobe intel_ifs
cd ..; ./runtests -d ifs/tests
```
or run below case directly:
```
modprobe intel_ifs
ifs_tests.sh -m 0 -p all -b 1 -n ifs_batch
```
If it passes, all cases can be tested.

**Scan at Field cases**
```
./ifs_tests.sh -m 0 -p all -n load_ifs
It loads ifs driver with ifs mode 0 without any exceptions.

./ifs_tests.sh -m 0 -p all -b 1 -n ifs_batch
It loads ifs batch 1 blob file with ifs mode 0 without any exceptions.

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

**Array BIST cases**
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
