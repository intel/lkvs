# Release Notes for Intel® TPMI (Topology Aware Register and PM Capsule
# Interface) UFS (Uncore Frequency Scaling) driver test cases

The cases are designed for Intel® TPMI (Topology Aware Register and PM Capsule
Interface) UFS (Uncore Frequency Scaling) driver on
Intel® GRANITERAPIDS and further server platforms.

The prerequisites to run UFS cases:
- User needs stress tool

You can run the cases one by one, e.g. command

```
./tpmi_ufs.sh -t check_ufs_unbind_bind
```
You also can run the cases together with runtests command, e.g.

```
cd ..
./runtests -f ufs/tests -o logfile
```

These are the basic cases for TPMI UFS driver, if you have good idea to
improve UFS cases, you are welcomed to send us the patches, thanks!
