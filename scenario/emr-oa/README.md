## Features Supported

Below are the test cases for new features on the Intel EMR platform in OpenAnolis (referred to as OA) OS. Please note that the specific test content for each feature can be found in the relevant content under the BM directory, which will not be repeated here. We believe that these test cases are a subset of all related feature tests there.

[TODO tests list]
* tests-dsa

Tested with [Anolis OS 23.1 LTS](https://mirrors.openanolis.cn/anolis/23/isos/GA/x86_64/AnolisOS-23.1-x86_64-dvd.iso)

## Dependencies
### tests-topology
* hwloc.x86_64 package
```
yum install hwloc
```

* cpuid tool

### tests-cstate
perf.x86_64 package
```
yum install perf
```
### tests-pstate and tests-rapl
* turbostat tool version 2024.xx.xx is required,
recompile from the latest mainline kernel source code: `tools/power/x86/turbostat/turbostat.c`

* stress-ng.x86_64
```
yum install stress-ng
ln -s /usr/bin/stress-ng /usr/bin/stress
```

## Known Issues
### Tools Missing
* cpuid
(workaround: copy from CentOS 9)

* rdmsr-tool
