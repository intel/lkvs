# Release Notes for x86_pkg_temp_thermal test cases

The thermal cases are designed for Intel® Architecture-based platforms
to cover x86_pkg_temp_thermal throttling and interrupts cases by running
stress workload.

The prerequisites to run thermal cases:
- User needs taskset and stress tools

thermal-tests file collects two cases for x86_pkg_temp_thermal driver
You can run the cases one by one, e.g. command

```
./thermal_test.sh -t check_thermal_throttling
```
You also can run the cases together with runtests command, e.g.

```
cd ..
./runtests -f thermal/thermal-tests -o logfile
```

These are two basic cases for x86_pkg_temp_thermal driver, If you have good idea to 
improve the cases, you are welcomed to send us the patches, thanks!
