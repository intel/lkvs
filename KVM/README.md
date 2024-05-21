[KVM (Kernel-based Virtual Machine)](KVM/README.md) is a virtualization technology for Linux that allows running multiple virtual machines (VMs) on a single physical host. It leverages the Linux kernel to provide virtualization capabilities, enabling efficient and secure isolation between VMs. KVM test cases involve testing various aspects of virtualization, including VM creation, management, and functionality.

More details please refer to following.

## KVM Features
  * [demo](demo/README.md)
(TODO)


Contributions quick start guide
------------------------

1) Fork this repo on github
2) Create a new topic branch for your work
3) Create a new test provider file in your virt test repo,
   like:

::

    cp io-github-autotest-qemu.ini myprovider.ini
::

    [provider]
    uri: file:///home/foo/lkvs
    [qemu]
    subdir: KVM/qemu/
You can optionally delete temporarily the
`io-github-autotest-qemu.ini` file, just so you don't have test
conflicts. Then you can develop your new test code, run it
using virt test, and commit your changes.

4) Make sure you have [inspektor installed](https://github.com/autotest/inspektor#inspektor)
5) Run:

::

    inspekt checkall --disable-style E501,E265,W601,E402,E722,E741 --no-license-check

6) Fix any problems
7) Push your changes and submit a pull request
8) That's it.

