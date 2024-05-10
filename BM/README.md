[BM(Bare Metal)](README.md) involves testing on physical machines without any hypervisor or virtualization software.

## Features
  * [AMX](amx/README.md)
  * [cet(Control flow Enhancement Technology)](cet/README.md)
  * [cstate](cstate/README.md)
  * [DSA](dsa/README.md)
  * [FRED](fred/README.md) (in progress)
  * [guest-test](guest-test/README.md)
  * [idxd](idxd/README.md) (TODO)
  * [IFS(In Field Scan)](ifs/README.md)
  * [ISST](isst/README.md)
  * [PMU](pmu/README.md)
  * [pstate](pstate/README.md)
  * [Intel_PT](pt/README.md)
  * [RAPL](rapl/README.md)
  * [SDSI](sdsi/README.md)
  * [splitlock](splitlock/README.md)
  * [tdx-compliance](tdx-compliance/README.md)
  * [tdx-guest](tdx-guest/README.md)
  * [tdx-osv-sanity](tdx-osv-sanity/README.md) (TODO)
  * [telemetry](telemetry/README.md)
  * [Intel_TH(Trace Hub)](th/README.md)
  * [thermal](thermal/README.md)
  * [topology](topology/README.md)
  * [tpmi](tpmi/README.md)
  * [ufs](ufs/README.md)
  * [UMIP(User-Mode Instruction Prevention)](umip/README.md)
  * [workload-xsave](workload-xsave/README.md)
  * [xsave](xsave/README.md)

# Compile from sources
## Compile the whole project (NOT recommended)

Usually, it needs various dependencies if you're trying to compile the whole project locally.
```
git clone https://github.com/intel/lkvs.git
cd lkvs/BM
make
```

Each sub-project should detail its particular way, if any. There are some known dependency issues.
### Known dependency issue locally
* Overall general dependence check
Please check the "Run Tests" section -d functionality below for general dependency checks on hardware, etc. (like kernel support, BIOS setting, Glibc support...).

* Intel PT
Cases of Intel PT need a 3rd part library libipt.
```
export GIT_SSL_NO_VERIFY=true
git clone http://github.com/intel/libipt.git
cd libipt && cmake . && make install
```

* UMIP
The UMIP test has 32-bit compatibility tests and requires 32-bit Glibc to be installed for compilation. However, 32-bit Glibc support is not mandatory on Linux OS.

#### Install 32-bit architect
##### Ubuntu OS
```
dpkg --add-architecture i386
dpkg --print-foreign-architectures
apt-get update
apt-get install gcc-11 make libelf1 gcc-multilib g++-multilib
```
##### Other OSs
Do not support 32-bit architect on other distributions.

#### Make the driver for cet_driver:
##### Ubuntu OS
For Ubuntu and so on deb package related OS:
```
dpkg -i linux-xxx-image_TARGET_VERSION.deb
dpkg -i linux-xxx-headers_TARGET_VERSION.deb
dpkg -i linux-xxx-dev_TARGET_VERSION.deb
dpkg -i linux-xxx-tools_TARGET_VERSION.deb

Boot up with target kernel version.
cd cet/cet_driver
make
```

##### CentOS/OpenEuler/Anolis
For CentOS and so on rpm package related OS:
Install the devel and headers package for target kernel and boot up
with target kernel.
```
rpm -ivh --force kernel-TARGET_VERSION.rpm
rpm -ivh --force kernel-devel-TARGET_VERSION.rpm
rpm -ivh --force kernel-headers-TARGET_VERSION.rpm

Boot up with target kernel version.
cd cet_driver
make
```

## Alternativly compile the whole project with Docker
```
make docker_image
make docker_make
```
Note. If you're behind a proxy, please export the local env variable `https_proxy` before executing `make`
```
export https_proxy=https://proxy-domain:port
```
## Compile a single test case
** This is the recommended way **

```
cd lkvs/BM/<test>
make
```

# Run tests

There're two ways to run the tests.

## Binary/Shell directly

Normally, there're one or more executable binaries or scirpts in a sub-project, once it is compiled successfully. The easiest way is to run them directly.

## Case runner

**runtests** is a straightforward test runner that can execute a single or a set of test cases and redirect the log.

There are 2 ways to pass test to **runtests**, add point 3 and 4 for general dependence check:
  1. `-c`: Pass test cmdline.
  2. `-f <component/tests*>`: the `tests*` file under each component folder records the detailed test cmd lines.
  3. `-d <compoent/tests*>`: the `tests*` file under each component folder records the detailed test cmd lines.
  4. `-d <tests-server|tests-client>`: tests-server or tests-client for all features dependence

Output of tests can be saved in a file using `-o` option.

Examples:

```
$ ./runtests -f <cmdfile>
$ ./runtests -f <cmdfile> -o <logfile>
$ ./runtests -c <cmdline>
$ ./runtests -c <cmdline> -o <logfile>
$ ./runtests -d <cmdfile>
$ ./runtests -d <tests-server|tests-client>
```

# Contribute rule
## Naming Rules
### Feature Names
The folders located in the root directory are referred to as "features." When naming a feature, please follow the following rule:
* Use a unified format for the feature name: <lowercase>-<info>
e.g. :cet, cstate, tdx-compliance, tdx-osv-sanity.

### Tests File:
* Use the file name 'tests' for default `tests` if only one tests is needed.
* Use the filename 'guest-tests' for guest tests.

tests|tests-server|tests-client file sample:
```
# @hw_dep: test dependence command @ the reason if the test command fails(optional)
# @other_dep:
# @other_warn:
```

```
For example:
# @hw_dep: cpuid_check 7 0 0 0 c 7
or
# @hw_dep: cpuid_check 7 0 0 0 c 7 @ CPU doesn't support CET SHSTK CPUID.(EAX=07H,ECX=01H):ECX[bit 7]
```

```
Failure of the @hw_dep and @other_dep test dependency commands will prevent this feature (folder) testing.
@other_warn the dependency check does not prevent testing of this feature, it just does some dependency checks and gives the reason why the feature partially fails due to some dependencies.
```
### Entry Point of Guest Tests
Use feature.guest_test_executor.sh as the entry point for guest tests.
