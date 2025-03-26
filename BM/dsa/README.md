# DSA(Data Streaming Accelerator) Test Cases

## Description
Intel DSA is a high-performance data copy and transformation accelerator that
will be integrated in SPR, targeted for optimizing streaming data movement and
transformation operations common with applications for high-performance storage,
networking, persistent memory, and various data processing applications. IAA is
a similar accelerator which is more focused on data encryption and decryption.
DSA and IAA share the same Linux Kernel driver “IDXD”

## dependencies
### Kenrel Configuration
Please check if `CONFIG_DMATEST=m` is configured.

### Kernel Commandline
Make sure the kernel commandline has the following options:
```
intel_iommu=on,sm_on
```

### BIOS dependencies
Please check if the following BIOS options are enabled:
```
EDKII -> Socket Configuration -> IIO Configuration -> Intel VT for Directed I/O (VT-d) -> Intel VT for Directed I/O -> Enable

EDKII -> Socket Configuration -> IIO Configuration -> Intel VT for Directed I/O (VT-d) ->Opt-out Illegal MSI Mitigation -> Enable
```

## Usage
IDXD is the DSA driver name and enabled after kernel 5.19, it is better to do tests
newer than that.

## Run
### Manually

Go through file tests-* , each line works as a single test.

### Automatically
Leverage `runtests` in the root folder:

```
cd lkvs
./runtests BM/dsa/tests-dsa1
```
## Expected result
All test results should show pass, no fail.

## accel-config
accel-config - configure and control DSA(data streaminng accelerator) subsystem
devices. The git repo is https://github.com/intel/idxd-config.git. 
`accel-config -h` and `accel-config --list-cmds` introduce how to use the tool.

#### compile
```
cd lkvs/tools/idxd-config
./autogen.sh

./configure CFLAGS='-g -O2' --prefix=/usr --sysconfdir=/etc --libdir=/usr/lib64 --enable-test=yes
make
make install
```

`--enable-test=yes` is required for all DSA and IAX related tests.
