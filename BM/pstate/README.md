# Release Notes for Intel Pstate cases

The cpufreq driver is a generic CPU frequency scaling driver that provides a framework 
for managing the CPU frequency, while Intel_Pstate driver is a specific CPU frequency
for Intel® Architecture-based processors. These drivers are specifically optimized for 
Intel_pstate and rely on the cpufreq sysfs attributes for configuration.

The tests file contains the cases that are applicable to both Intel® client and Server platforms.
At present, the tests do not cover non-HWP mode, but are exclusively designed for Hardware P-state mode.
HWP stands for Hardware-controlled Performance States, For more information on the HWP specifiction, 
please consult the Intel® Software Developer's Manual.

You can run the cases one by one, e.g. command

```
./intel_pstate_tests.sh -t verify_sysfs_atts
```
You also can run the cases together with runtests command, e.g.

```
cd ..
./runtests -f pstate/tests -o logfile
```

These are the basic cases for CPU pstates, If you have good idea to 
improve pstate cases, you are welcomed to send us the patches, thanks!
