# Release Notes for Topology Aware Register and PM Capsule Interface test cases

The tpmi cases are designed to test the basic functionality of the intel_vsec 
and intel_tpmi driver modules on Intel® Architecture-based server platforms.
These cases are supported on the GRANITERAPIDS and will be compatibale with
subsequent platforms as well.


You can run the cases one by one, e.g. command

```
./intel_tpmi.sh -t pm_feature_list
```
You also can run the cases together with runtests command, e.g.

```
cd ..
./runtests -f tpmi/tests -o logfile
```

These are the basic cases for intel_vsec and intel_tpmi driver module, 
If you have good idea to improve cstate cases, you are welcomed to 
send us the patches, thanks!
