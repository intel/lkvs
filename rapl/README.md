# Release Notes for Running Average Power Limiting test cases

The RAPL cases are designed for intel_rapl driver on Intel® Architecture-based platforms.
Considering Intel® Server and Client platforms have different rapl domains.
So created two tests files to distinguish the cases running on different test units.

The prerequisites to run the RAPL cases:
- User needs turbostat, stress, perf tools

tests-client file collects the cases for Intel® client platforms
You can run the cases one by one, e.g. command

```
./intel_rapl_test.sh -t check_sysfs
```
You also can run the cases together with runtests command, e.g.

```
cd ..
./runtests -f rapl/tests-client -o logfile
```

tests-server file collects the cases for Intel® server platforms.

These are the basic cases for Intel_RAPL driver, If you have good idea to 
improve cstate cases, you are welcomed to send us the patches, thanks!
