# DSA(Data Streaming Accelerator) Test Cases

## Description
```
Intel DSA is a high-performance data copy and transformation accelerator that
will be integrated in SPR, targeted for optimizing streaming data movement and
transformation operations common with applications for high-performance storage,
networking, persistent memory, and various data processing applications. IAA is
a similar accelerator which is more focused on data encryption and decryption.
DSA and IAA share the same Linux Kernel driver “IDXD”
```

## Usage
```
IDXD is the DSA driver name and enabled after kernel 5.19, it is better to do tests
newer than that.

./dsa_user.sh -t check_dsa_driver
IDXD driver is for both dsa and iaa, check if the driver is loaded.
./dsa_user.sh -t check_dsa0_device
After the driver is loaded, devices are enabled under /sys/bus/dsa/devices.
./dsa_user.sh -t check_shared_mode
If SVM(Shared Virtual Memory) is supported, the pasid_enabled is 1. If it is 0,
the shared mode is not confgurable.
```

## Expected result
```
All test results should show pass, no fail.
```

## accel-config
```
accel-config - configure and control DSA(data streaminng accelerator) subsystem
devices. The git repo is https://github.com/intel/idxd-config.git. 
accel-config -h and accel-config --list-cmds introduce how to use the tool.
```
