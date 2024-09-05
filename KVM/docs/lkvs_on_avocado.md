### Table of Contents:
* [1. Introduction](#introduction)
* [2. Host environment](#host-environemt)
* [3. Installation](#installation)
* [4. Configuration](#configuration)
* [5. Run Test](#run-test)
* [6. Test Result and Log Analysis](#test-result-and-log-analysis)
* [7. Update](#update)

<!-- headings -->
<a id="introduction"></a>
# 1. Introduction

[Avocado](https://github.com/avocado-framework/avocado) is a framework with a set of tools and libraries to help with automated testing on Linux platform. It provides test case management, execution and result generation. [Avocado-VT](https://github.com/avocado-framework/avocado-vt) is a compatibility plugin that let you execute virtualization related tests, with all conveniences provided by Avocado. While it's a default case provider, we can define our own case provider - [github-lkvs](https://github.com/intel/lkvs/tree/main/KVM).

<a id="host-environment"></a>
# 2. Host environment

Skip the details of host environment, enable TDX host BIOS, build and install TDX supported kernel, qemu and TDVF, reboot host with TDX module initialized successfully .

Install and start libvirtd to setup the default bridge virbr0 on host.

```bash
dnf install libvirt libvirt-daemon
systemctl start libvirtd
# Check if libvirtd service is active and running
systemctl status libvirtd
# Check virbr0 on host
ip ad|grep virbr0
```

**Attention**: Reconfigure libvirtd to disable timeout, comment or remove below line in /usr/lib/systemd/system/libvirtd.service

```bash
#Environment=LIBVIRTD_ARGS="--timeout 120"
```

Then reload and restart service

```bash
# Reload and restart libvirtd service
systemctl daemon-reload
systemctl restart libvirtd
# Check if libvirtd service is active and running
systemctl status libvirtd
# Check virbr0 on host
ip ad|grep virbr0
```

**Dependent package**: arping

Redhat/Centos:

```bash
dnf install iputils
```

Ubuntu:

```bash
apt install arping
```
<a id="installation"></a>
# 3. Installation

## 3.1 Avocado and Avocado-vt

### 3.1.1 Install framework

#### 3.1.1.1 Redhat/Centos

```bash
pip install --user avocado-framework
pip install --user git+https://github.com/avocado-framework/avocado-vt
```

#### 3.1.1.2 Ubuntu

```bash
apt install python3-full
python3 -m venv /root/.local/
/root/.local/bin/pip3 install avocado-framework
/root/.local/bin/pip3 install git+https://github.com/avocado-framework/avocado-vt

# Modify /etc/environment , add /root/.local/bin to variable PATH
root@inspur-209:~# cat /etc/environment
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin:/root/.local/bin"
# Relogin OS to make the new $PATH work
```

### 3.1.2 Install cases from default provider

We can skip image downloading if you plan to use your customized images when do testing.

```bash
avocado vt-bootstrap --vt-type qemu
```

### 3.1.3 Check

```
# It depends on the python version, take python3.9 as an example
[root@localhost ~]# ls /root/.local/lib/python3.9/site-packages/    
aexpect                                           avocado_vt
aexpect-1.7.0.dist-info                           netifaces-0.11.0.dist-info
avocado                                           netifaces.cpython-39-x86_64-linux-gnu.so
avocado_framework-106.0.dist-info                 virttest
avocado_framework_plugin_vt-104.0-py3.9.egg-info
[root@localhost ~]# ls /root/avocado/data/avocado-vt/backends/qemu/cfg/
base.cfg    guest-hw.cfg  host.cfg      subtests.cfg  tests-shared.cfg
cdkeys.cfg  guest-os.cfg  machines.cfg  tests.cfg     virtio-win.cfg
[root@localhost ~]# avocado list
```

## 3.2 LKVS

### 3.2.1 Install framework

```bash
mkdir /home/test
cd /home/test
git clone https://github.com/intel/lkvs.git
# Create the test provider file myprovider.ini as following for lkvs test repo 
cat > /root/avocado/data/avocado-vt/virttest/test-providers.d/myprovider.ini << EOF
[provider]
uri: file:///home/test/lkvs
[qemu]
subdir: KVM/qemu
EOF
```

### 3.2.2 Install cases from new provider lkvs

```bash
avocado vt-bootstrap --vt-type qemu
```

### 3.2.3 Available test cases

Attention: Select appropriate test set according to your software stack and your test objective

```bash
# To get all available cases from provider(lkvs)
avocado list |grep myprovider
# For tdx cases, string td/tdx can be found in case name
avocado list |grep myprovider|grep td
[root@localhost ~]# avocado list |grep myprovider|grep td
avocado-vt type_specific.myprovider.td_boot_multimes.one_socket.one_cpu
avocado-vt type_specific.myprovider.td_boot_multimes.one_socket.four_cpu
avocado-vt type_specific.myprovider.td_boot_multimes.two_socket.four_cpu
avocado-vt type_specific.myprovider.td_boot_multimes.4vm_20times.four_cpu
avocado-vt type_specific.myprovider.x86_cpu_flags.tdvm.tsc_deadline.default
avocado-vt type_specific.myprovider.x86_cpu_flags.tdvm.tsc_deadline.disable
avocado-vt type_specific.myprovider.tdx_max_guests.max
avocado-vt type_specific.myprovider.tdx_max_guests.out_max
avocado-vt type_specific.myprovider.x86_cpuid.tdvm.avx512_fp16
avocado-vt type_specific.myprovider.x86_cpuid.tdvm.serialize
avocado-vt type_specific.myprovider.x86_cpuid.tdvm.tsxldtrk
avocado-vt type_specific.myprovider.x86_cpuid.tdvm.avx_vnni
......
```
<a id="configuration"></a>
# 4. Configuration

## 4.1 Guest image

### 4.1.1 Guest Login

**Do following configuration in guest image**

* Set password "123456" for user "root".
* Enable password login: check /etc/ssh/sshd_config.d/ in guest image, if `PasswordAuthentication no` is set in any of the cfg files, change it to `PasswordAuthentication yes` or just remove it, then restart sshd/ssh service.
Redhat/Centos:`systemctl restart sshd`, Ubuntu:`systemctl restart ssh`.
* To avoid garbled text for terminal, modify $HOME/.inputrc(create one if it doesn't exist), add "set enable-bracketed-paste 0" into it, and dnf/apt install ncurses-term

### 4.1.2 TD boot

Prepare your guest image well, make sure it can be boot as td guest with your host kernel/qemu, for example: add "clearcpuid=mtrr" to guest kernel cmdline to match the latest developing tree(It depends on your software stack).

## 4.2 Config file

Copy this template [tdx_temp.cfg](tdx_temp.cfg) to /root/avocado/data/avocado-vt/backends/qemu/cfg/

### 4.2.1 Guest OS

We need to set the guest OS in config file, here is the example in tdx_temp.cfg.

Note: The default supported Ubuntu OS is old, but we can just use it, no problem, guest image and "shell prompt" will be redefined in next section

```bash
#For RHEL9 guest
only RHEL.9
#For Ubuntu guest
#only Linux.Ubuntu.14.04.3-server.x86_64
```

### 4.2.2 Shell prompt

To login guest, we need a shell prompt, which is a wildcards for guest image login, it depends on the guest OS.

In tdx_temp.cfg, shell prompt for RHEL9 and Ubuntu24.04 like below, choose(or make your own prompt) one according to your guest OS.

```bash
#For RHEL9.4 guest
shell_prompt = "^\[.*\][\#\$]\s*$"
#For Ubuntu24.04 guest
#shell_prompt = "^.*@.*:.*[\#\$]\s*$"
```

### 4.2.3 QEMU

Modify tdx_temp.cfg, check "qemu_binary", set this variable to absolute path of qemu binary.

### 4.2.4 TDVF

Modify tdx_temp.cfg, check "bios_path", set this variable to the absolute path of TDVF.

### 4.2.5 Guest image

Location: Prepare guest image, put it at /root/avocado/data/avocado-vt/images/

Name & Format:

Modify tdx_temp.cfg, check `image_name` and `image_format`, `image_name`+`image_format` should be the absolute path of guest image.

If the image format is raw, name the image xxx.raw, if the image format is qcow2, name the image xxx.qcow2

For example, the absolute path is `/root/avocado/data/avocado-vt/images/rhel-guest-image-9.4-20240419.25.x86_64.qcow2`:

```bash
image_name = /root/avocado/data/avocado-vt/images/rhel-guest-image-9.4-20240419.25.x86_64
image_format = qcow2
```

### 4.2.6 Test cases

#### 4.2.6.1 Sanity Test Set

The test cases in tdx_temp.cfg is a sanity test set, for your reference.

You can choose other available cases by modifying `@run_test`.

Attention: Because of known issues, some cases out of this sanity test set may be not supported by the kernel/qemu you are using.

```bash
variants:
    - @pre_test:
    - @run_test:
        # Test cases
        only tdx_basic td_disable_ept multi_vms.1td_1vm multi_vms.2td.4vcpu tsc_freq.tdvm.default tsc_freq.tdvm.settsc td_huge_resource td_huge_resource.max_vcpus
    - @post_check:
pre_test, post_check:
    iterations = 1
no pre_test
no post_check
```
<a id="run-test"></a>
# 5. Run Test
```bash
avocado run --vt-config /root/avocado/data/avocado-vt/backends/qemu/cfg/tdx_temp.cfg
```
<a id="est-result-and-log-analysis"></a>
# 6. Test Result and Log Analysis

An example of test result is like following:
```
JOB ID     : bebf72e872125523172294d72166774bfc2d32a6
JOB LOG    : /root/avocado/job-results/job-2024-09-04T09.53-bebf72e/job.log
 (1/9) type_specific.myprovider.tsc_freq.tdvm.default: STARTED
 (1/9) type_specific.myprovider.tsc_freq.tdvm.default:  PASS (64.47 s)
 (2/9) type_specific.myprovider.tsc_freq.tdvm.settsc: STARTED
 (2/9) type_specific.myprovider.tsc_freq.tdvm.settsc:  PASS (63.79 s)
 (3/9) type_specific.myprovider.multi_vms.1td_1vm: STARTED
 (3/9) type_specific.myprovider.multi_vms.1td_1vm:  PASS (77.49 s)
 (4/9) type_specific.myprovider.multi_vms.2td.4vcpu: STARTED
 (4/9) type_specific.myprovider.multi_vms.2td.4vcpu:  PASS (77.78 s)
 (5/9) type_specific.myprovider.td_disable_ept: STARTED
 (5/9) type_specific.myprovider.td_disable_ept:  PASS (16.73 s)
 (6/9) type_specific.myprovider.td_huge_resource.half: STARTED
 (6/9) type_specific.myprovider.td_huge_resource.half:  PASS (87.92 s)
 (7/9) type_specific.myprovider.td_huge_resource.max_vcpus: STARTED
 (7/9) type_specific.myprovider.td_huge_resource.max_vcpus:  PASS (119.16 s)
 (8/9) type_specific.myprovider.td_huge_resource.out_max_vcpus: STARTED
 (8/9) type_specific.myprovider.td_huge_resource.out_max_vcpus:  FAIL: Test was expected to fail, but it didn't (60.15 s)
 (9/9) type_specific.myprovider.tdx_basic: STARTED
 (9/9) type_specific.myprovider.tdx_basic:  PASS (61.42 s)
RESULTS    : PASS 8 | ERROR 0 | FAIL 1 | SKIP 0 | WARN 0 | INTERRUPT 0 | CANCEL 0
JOB TIME   : 635.91 s

Test summary:
8-type_specific.myprovider.td_huge_resource.out_max_vcpus: FAIL
```

All the logs can be found in `/root/avocado/job-results/job-2024-09-04T09.53-bebf72e/`, in test-results folder, all the test cases can be found, below log can be found in each case's result folder:

+ debug.log: test parameters, framework processes, test steps, test result and traceback
+ session logs: detailed test steps
+ monitor log: qemu monitor log
+ serial log: guest serial log

<a id="update"></a>
# 7. Update
```bash
# Check your python version, take python3.9 as an example
rm -rf /root/.local/lib/python3.9/site-packages/

# Redhat/Centos
pip install --user avocado-framework
pip install --user git+https://github.com/avocado-framework/avocado-vt

# Ubuntu
python3 -m venv /root/.local/
/root/.local/bin/pip3 install avocado-framework
/root/.local/bin/pip3 install git+https://github.com/avocado-framework/avocado-vt

# lkvs
cd /home/test/lkvs/
git pull
# install new case
avocado vt-bootstrap --vt-type qemu
```
