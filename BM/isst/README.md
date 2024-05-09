# Release Notes for Intel® Speed Select Technology test cases

Intel® Speed Select Technology: a collection of features improve performance 
and optimizes the total cost of ownership (TCO) by proving more control 
over the CPU performance.

The isst cases are designed for Intel® Architecture-based server platforms,
supported beginning from Cascade lake, then Cooper lake, Icelake and future platforms

The prerequisites to run the ISST cases:
- The server CPU supports the ISST feature
- BIOS enabled Dynamic SST-PP setting
- User needs intel-speed-select, turbostat, stress tools

tests file collects the cases for Intel® server platforms where assume SUT supports
SST perf profile level 0,3,4, users can add other SST-PP level cases
for the futhur platforms who may support full SST-PP levels 0,1,2,3,4

You can run the cases one by one, e.g. command

```
./intel_sst.sh -t isst_info
```
You also can run the cases together with runtests command, e.g.

```
cd ..
./runtests -f isst/tests -o logfile
```

These are the basic cases for ISST testing, If you have good idea to 
improve cases, you are welcomed to send us the patches, thanks!
