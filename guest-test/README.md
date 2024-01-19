# KVM/QEMU based Guest VM auto test framework

## Description
A simple auto guest VM test framework for several types of VM launched by KVM/QEMU.
Types of VM supported includes: legacy, tdx, tdxio may extend in future for specific type of VMs.

In fact, the main differences among above VM types are QEMU config parameters.

As QEMU config parameters may vary from version to version. The current implementation is QEMU version 7.2.0 based with tdx, tdxio special feature support.

The qemu.config.json and common test framework code need to change along with new QEMU update

![image](https://github.com/intel/lkvs/assets/58062922/23152a3e-7255-4984-9a2d-c0a3f30efd6a)


## Limitaion
Each test execution will launch a new VM and run specific test scripts/binaries in guest VM. Test log will be captured from QEMU launching VM to test scripts/binaries execution in guest VM, until VM launched being shutdown properly or pkilled on purpose in abnormal test status.

No multi-VMs test scenarios covered/supported.

In any case of issue debugging, please refer to above test log with VM QEMU config info and launch VM and debug issues manually running test scripts/binaries.

A prepared Guest OS Image (qcow2 or raw image format) is requried with preset root account and password, several values/parameters in common.json highly depend on Guest OS Image, please accomodate accordingly.

## Usage
### common.json and qemu.config.json description
common.json parameters are basic test info setup might only need revision, it's single level keys based, includes following info:
- "kernel_img": [mandatory] /abs/path/to/vmlinuz file or bzImage file of target VM guest kernel
- "initrd_img": [optional] /abs/path/to/initrd file or initramfs file of target VM guest kernel
- "bios_img": [legacy vm optional, tdx/tdxio vm mandatory] /abs/path/to/ovmf file or other bios file of target VM guest bios
- "qemu_img": [mandatory] /abs/path/to/qemu-kvm or qemu-system-x86_64 file to boot target VM guest
- "guest_img": [mandatory] /abs/path/to/VM guest OS image with qcow2 format or raw image format
- "guest_img_format": [mandatory] value range in [qcow2/raw], guest os image file type qcow2 or raw image
- "boot_pattern": [mandatory] Guest OS booting pattern shows bootup completed, depends on Guest OS image provided
- "guest_root_passwd": [mandatory] Guest OS root account password

with QEMU emulator version 7.2 support, qemu.config.json parameters are fully aligned to it, and grouped in 4 by 1st-level-keys: "common", "vm", "tdx", "tdxio".

group "common" includes all configurable values to be passed to group "vm", "tdx", "tdxio"
2nd-level-keys info:
- "vm_type": [mandatory] value range in [legacy/tdx/tdxio], VM type to test includes legacy vm, tdx vm or tdxio vm
- "pmu": [mandatory] value range in [on/off], qemu config -cpu pmu=on or -cpu pmu=off
- "cpus": [mandatory] value range in [1 ~ maximum vcpu number], qemu config -smp cpus=$VCPU
- "sockets": [mandatory] value range in [1 ~ maximum sockets number], qemu config -smp sockets=$SOCKETS
- "mem": [mandatory] value range in [1 ~ maximum mem size in GB], qemu config -m memory size in GB
- "cmdline": [optional] value range in [guest kernel paramter extra string], qemu config -append extra command line parameters to pass to VM guest kernel
- "debug": [mandatory] value range in [on/off], qemu config -object tdx-guest,debug=on or -object tdx-guest,debug=off

group "vm" includes all legacy vm launch qemu config options, which can be used to launch legacy vm standalone or as base part to launch tdx vm

group "vm" 2nd-level-keys could be bypassed if not provided (file not exists)
"cfg_var_6", "cfg_var_10" could be bypassed separately, "cfg_var_5" & "cfg_var_9" could be bypassed in pair

group "tdx" includes tdx vm specific qemu config options, which is used to launch tdx vm (with group "vm" as base) or as a based part to launch tdxio vm

group "tdxio" includes tdxio/tdx-connect vm specific qemu config options, which is used to launch tdxio/tdx-connect vm (with group "vm" + "tdx" as base)

note about qemu.config.json:
- no changes allowed on 1st-level-keys hierarchy
- cfg_x part is allowed to extend freely based on needs
- cfg_var_x part is allowed to revise/extend too, please remember to keep changes specifically aligned in qemu_get_config.py

### guest.test_launcher description
main test entrance, with following key args can be passed to override the values in qemu.config.json
  - `-v` $VCPU number of vcpus
  - `-s` $SOCKETS number of sockets
  - `-m` $MEM memory size in GB
  - `-d` $DEBUG debug on/off
  - `-t` $VM_TYPE vm_type legacy/tdx/tdxio
  - `-f` $FEATURE feature sub-folder for new feature vm test extension
  - `-x` $TESTCASE testcase pass to test_executor
  - `-c` $CMDLINE guest kernel extra commandline
  - `-p` $PMU guest pmu off/on
  - `-g` $GCOV code coverage test mode off/on
  - `-i` $JSON_C file path under guest-test to standalone common.json file
  - `-j` $JSON_Q file path under guest-test to standalone qemu.config.json file

above key args will be recorded in a fresh new test_params.py for further import/source purpose accross python and shell scripts

by enter each test, qemu_get_config.py will be called to get following pre-set parameters from common.json
  - $KERNEL_IMG values passed by group "common" key "kernel_img"
  - $INITRD_IMG values passed by group "common" key "initrd_img"
  - $BIOS_IMG values passed by group "common" key "bios_img"
  - $QEMU_IMG values passed by group "common" key "qemu_img"
  - $GUEST_IMG values passed by group "common" key "guest_img"
  - $GUEST_IMG_FORMAT values passed by group "common" key "guest_img_format"
  - $BOOT_PATTERN values passed by group "common" key "boot_pattern"
  - $SSHPASS values passed by group "common" key "guest_root_passwd"

call guest.qemu_runner.sh and wait for $BOOT_PATTERN (shows VM boot up completed and ready for login) during VM boot
  - $BOOT_PATTERN is selected based on following CentOS Stream 8/9 boot log example: "*Kernel*on*an*x86_64*"

  boot log example quoted:
  ```
    CentOS Stream 9
    Kernel 6.5.0-rc5-next-20230809-next-20230809 on an x86_64
    Activate the web console with: systemctl enable --now cockpit.socket
    CentOS-9 login:
  ```

if $BOOT_PATTERN found, call guest.test_executor.sh with proper $TESTCASE to be executed in VM Guest, and shutdown VM after test compelted

if $BOOT_PATTERN not found, several VM life-cycles management logic applied to handle boot failure in different stages

if $ERR_STRx found, handle the error info accordingly (err_handlers)

no matter what, in the end, pkill VM process to avoid any potential test step failures above

Note: by deault, $GCOV is off, if $GCOV is on, above VM life-cycles management logic will be bypassed to keep VM process alive for gcov code coverage data collection

### guest.qemu_runner description
VM boot engine, with parames exported from qemu_get_config.py and test scenario config sourced from test_params.py

before VM boot, for $VM_TYPE tdx or tdxio, tdx_pre_check and tdx_module_check will be called to make sure basic environment is ready for TDX/TDXIO launching

VM boot is triggered by qemu_runner.py based on $VM_TYPE, with proper qemu config options applied

### guest.test_executor description
guest VM test execution basic framework implemented in guerst.test_executor.sh, such as
  - guest_test_prepare, function based on sshpass to scp common.sh and test_script.sh to Guest VM
  - guest_test_source_code, function based on sshpass to scp source_code_dir and compile test_binary in Guest VM
  - guest_test_entry, function based on sshpass to execute test_script.sh and potential script params in Guest VM
  - guest_test_close, function based on sshpass to close VM

## How to add new feature test
as described above, if simply add new TCs to run based on current common.json and qemu.config.json format, just need to implement it in $FEATURE.test_executor.sh under guest-test/$FEATURE subfolder,
please leverage reference code "common variables example" and "common works example" in tdx/tdx.test_executor.sh, further implement "$FEATURE specific Functions" and "$FEATURE specific code path",
common functions of guest.test_executor.sh should be good enough to prepare/run/close new $FEATURE specific tests implemented in $FEATURE.test_executor.sh;

it's allowed to customize and pass $FEATURE standalone common.json and qemu.config.json, please refer to ### common.json and qemu.config.json description and ### guest.test_launcher description for quick rule reference

furthermore, if common.json and qemu.config.json format will be revised due to feature changes on QEMU implementation, please update qemu_get_config.py accordingly
