# Linux Kernel Validation Suite

The Linux Kernel Validation Suite (LKVS) is a Linux Kernel test suite. It is a working project created by the Intel Core Linux Kernel Val Team. The purpose is to improve the quality of Intel-contributed Linux Kernel code. Furthermore, it shows the customer how to use or validate the features.

[BM(Bare Metal)](BM/README.md) involves testing on physical machines without any hypervisor or virtualization software.

[KVM (Kernel-based Virtual Machine)](KVM/README.md) is a virtualization technology for Linux that allows running multiple virtual machines (VMs) on a single physical host. It leverages the Linux kernel to provide virtualization capabilities, enabling efficient and secure isolation between VMs. KVM test cases involve testing various aspects of virtualization, including VM creation, management, and functionality.

More details please refer to following.

## BM Features
  * [AMX](BM/amx/README.md)
  * [avx512vbmi](BM/avx512vbmi/README.md)
  * [cet(Control flow Enhancement Technology)](BM/cet/README.md)
  * [CMPccXADD](BM/cmpccxadd/README.md)
  * [cstate](BM/cstate/README.md)
  * [DSA](BM/dsa/README.md)
  * [FRED](BM/fred/README.md) (in progress)
  * [guest-test](BM/guest-test/README.md)
  * [idxd](BM/idxd/README.md) (TODO)
  * [IFS(In Field Scan)](BM/ifs/README.md)
  * [ISST](BM/isst/README.md)
  * [PMU](BM/pmu/README.md)
  * [pstate](BM/pstate/README.md)
  * [Intel_PT](BM/pt/README.md)
  * [RAPL](BM/rapl/README.md)
  * [SDSI](BM/sdsi/README.md)
  * [splitlock](BM/splitlock/README.md)
  * [tdx-compliance](BM/tdx-compliance/README.md)
  * [tdx-guest](BM/tdx-guest/README.md)
  * [tdx-osv-sanity](BM/tdx-osv-sanity/README.md) (TODO)
  * [telemetry](BM/telemetry/README.md)
  * [Intel_TH(Trace Hub)](BM/th/README.md)
  * [thermal](BM/thermal/README.md)
  * [topology](BM/topology/README.md)
  * [tpmi](BM/tpmi/README.md)
  * [ufs](BM/ufs/README.md)
  * [UMIP(User-Mode Instruction Prevention)](BM/umip/README.md)
  * [workload-xsave](BM/workload-xsave/README.md)
  * [xsave](BM/xsave/README.md)

## KVM Features
(TODO)

## Scenario
it's a collection of specific test files selected for particular scenario, for example, tests designed for GraniteRapids + OpenEuler OS platform:
  * [scenario_file](scenario/gnr-oe)
refer to the [scenario documentation](/scenario/README.md) for more details

# Report a problem

Submit an [issue](https://github.com/intel/lkvs/issues) or initiate a discussion.

# Contribute rule

## Coding style
Any pull request are welcomed, the canonical patch format please refer to the Kernel [patches submitting](https://www.kernel.org/doc/html/latest/process/submitting-patches.html)

# Contact
Yi Sun <yi.sun@intel.com>

* BM sub-module
Yi Sun <yi.sun@intel.com>

* KVM sub-module
Xudong Hao <xudong.hao@intel.com>

# License
See [LICENSE](https://github.com/intel/lkvs/blob/main/LICENSE) for details.
