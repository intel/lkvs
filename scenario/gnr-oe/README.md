## Features Supported

Below are the test cases for new features on the Intel GNR platform in OpenEuler (referred to as OE) OS. Please note that the specific test content for each feature can be found in the relevant content under the BM directory, which will not be repeated here. We believe that these test cases are a subset of all related feature tests there.

* tests-avx512vbmi
* tests-cet
* tests-cstate
* tests-edac
* tests-iax
* tests-ifs
* tests-isst
* tests-rapl
* tests-sdsi
* tests-topology
* tests-tpmi
* tests-ufs
* tests-umip
* tests-xsave

Tested with [OpenEuler 24.03 LTS](https://www.openeuler.org/zh/download/?version=openEuler%2024.03%20LTS)

## Dependencies
### tests-topology
* hwloc.x86_64 package
```
yum install hwloc
```

* cpuid tool

### tests-sdsi
* intel_sdsi tool
Build and install from the kernel source code: `tools/arch/x86/intel_sdsi/intel_sdsi.c`

### tests-isst
* intel-speed-select
stress-ng.x86_64
```
yum install stress-ng
ln -s /usr/bin/stress-ng /usr/bin/stress
```

### tests-cstate
perf.x86_64 package
```
yum install perf
```

## Known Issues
### Tools Missing
* cpuid
(workaround: copy from CentOS 9)

* rdmsr-tool

* Kernel Features Missing
gcc missing AMX FP16 support
(workaround: compile tmul.c with gcc13+ and copy the binary into OE)

* Kernel idxd driver missing SVA support
(resulting in DSA/IAX not working)

* CET
OE kernel does NOT configuure CONFIG_X86_USER_SHADOW_STACK=y, resulting in CET SHSTK not working.
