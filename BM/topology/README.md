# Release Notes for Intel® CPU Topology test cases

The cases are designed for Intel® CPU Topology on
Intel® Architecture-based server and client platforms.

The prerequisites to run CPU Topology cases:
- cpuid tool, which can be installed by command below:
For Ubuntu or Debian-based systems:
sudo apt install cpuid
For CentOS or Fedora-based systems:
sudo dnf install cpuid

You can run the cases one by one, e.g. command

```
./cpu_topology.sh -t verify_thread_per_core
```
You also can run the cases together with runtests command, e.g.

```
cd ..
./runtests -f topology/tests-server -o logfile
```
Note：
For numa_nodes_compare case, it is designed based on SNC-disabled, so if your env
is SNC-enabled, this case should not be executed.

These are the basic cases for Intel® CPU Topology, If you have good idea to
improve CPU Topology cases, you are welcomed to send us the patches, thanks!
