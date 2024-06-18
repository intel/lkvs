[KVM (Kernel-based Virtual Machine)](KVM/README.md) is a virtualization technology for Linux that allows running multiple virtual machines (VMs) on a single physical host. It leverages the Linux kernel to provide virtualization capabilities, enabling efficient and secure isolation between VMs. KVM test cases involve testing various aspects of virtualization, including VM creation, management, and functionality.

More details please refer to following.

## KVM Features
  * [TDX](https://github.com/intel/tdx-linux)


## How to run KVM test
lkvs KVM is a seperate test provider for avocado/avocado-vt.

1) Install avocado and avocado-vt
```
    pip install --user avocado-framework
    pip install --user git+https://github.com/avocado-framework/avocado-vt
```    
2) Download lkvs in test machine
```
    git clone https://github.com/intel/lkvs.git
```
3) Create a new test provider file for lkvs test repo, put the file
   in the installed test provider folder. like:
```
    cat /root/avocado/data/avocado-vt/virttest/test-providers.d/myprovider.ini
```

```
    [provider]
    uri: file:///home/foo/lkvs
    [qemu]
    subdir: KVM/qemu/
```
4) Setup test into the real avocado-vt configuration file
```
    avocado vt-bootstrap
    avocado list |grep myprovider
```
   For example: avocado-vt type_specific.myprovider.boot_td

5) Run test
```
    avocado run boot_td
```

## Contributions quick start guide

1) Fork this repo on github
2) Create a new topic branch for your work
3) Create a new test provider file in your virt test repo,
   like:
```
    cp io-github-autotest-qemu.ini myprovider.ini
```

```
    [provider]
    uri: file:///home/foo/lkvs
    [qemu]
    subdir: KVM/qemu/
```
You can optionally delete temporarily the
`io-github-autotest-qemu.ini` file, just so you don't have test
conflicts. Then you can develop your new test code, run it
using virt test, and commit your changes.

4) Make sure you have [inspektor installed](https://github.com/autotest/inspektor#inspektor)
5) Run:
```
    inspekt checkall --disable-style E501,E265,W601,E402,E722,E741 --no-license-check
```
6) Fix any problems
7) Push your changes and submit a pull request
8) That's it.

