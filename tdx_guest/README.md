# tdx related tests description

## Latest Upstream Kernel applicable tests
### case implemented by tdx_guest_boot_check.sh
  - TD VM booting test with vcpu 1 sockets 1 and memory size 1 GB
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t tdx -f tdx -x TD_BOOT -c "accept_memory=lazy" -p off
  ```
  - TD VM booting test with vcpu 1 sockets 1 and memory size 16 GB
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 16 -d on -t tdx -f tdx -x TD_BOOT -c "accept_memory=lazy" -p off
  ```
  - TD VM booting test with vcpu 4 sockets 1 and memory size 4 GB
  ```
    ./guest-test/guest.test_launcher.sh -v 4 -s 1 -m 4 -d on -t tdx -f tdx -x TD_BOOT -c "accept_memory=lazy" -p off
  ```
  - TD VM booting test with vcpu 4 sockets 2 and memory size 4 GB
  ```
    ./guest-test/guest.test_launcher.sh -v 4 -s 2 -m 4 -d on -t tdx -f tdx -x TD_BOOT -c "accept_memory=lazy" -p off
  ```
  - TD VM booting test with vcpu 4 sockets 2 and memory size 96 GB
  ```
    ./guest-test/guest.test_launcher.sh -v 4 -s 2 -m 96 -d on -t tdx -f tdx -x TD_BOOT -c "accept_memory=lazy" -p off
  ```
  - TD VM booting test with vcpu 64 sockets 8 and memory size 96 GB
  ```
    ./guest-test/guest.test_launcher.sh -v 64 -s 8 -m 96 -d on -t tdx -f tdx -x TD_BOOT -c "accept_memory=lazy" -p off
  ```
  - TD VM booting test with vcpu 288 sockets 1 and memory size 1 GB
  ```
    ./guest-test/guest.test_launcher.sh -v 288 -s 1 -m 1 -d on -t tdx -f tdx -x TD_BOOT -c "accept_memory=lazy" -p off
  ```
  - TD VM booting test with vcpu 288 sockets 8 and memory size 96 GB
  ```
    ./guest-test/guest.test_launcher.sh -v 288 -s 8 -m 96 -d on -t tdx -f tdx -x TD_BOOT -c "accept_memory=lazy" -p off
  ```
  - TD VM booting test with vcpu 1 sockets 1 and memory size 16 GB and debug off
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d off -t tdx -f tdx -x TD_BOOT -c "accept_memory=lazy" -p off
  ```
  - Check if TDX guest kernel can boot in legacy VM configuration 1 VCPU 1 Socket 1GB Memory
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t legacy -f tdx -x TD_BOOT -c " " -p off
  ```
### case implemented by tdx_attest_check.sh
  - Check TDX Guest Attestation TD_REPORT Generation in ioctl design
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t tdx -f tdx -x TD_ATTEST_VERIFY_REPORT -c "accept_memory=lazy" -p off
  ```
  - TDX remote attestation TSM based Quote, ConfigFS attributes pre-check
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t tdx -f tdx -x TD_TSM_ATTEST_QUOTE_PRECHECK -c "accept_memory=lazy" -p off
  ```
  - TDX remote attestation TSM based Quote generation basic check, independent from QGS or other attestation support service
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t tdx -f tdx -x TD_TSM_ATTEST_QUOTE -c "accept_memory=lazy" -p off
  ```
  - TDX remote attestation TSM based Quote generation negative scenario check, no quote generated due to invalid arguments is expected
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t tdx -f tdx -x TD_TSM_ATTEST_QUOTE_NEG -c "accept_memory=lazy" -p off
  ```
### case implemented by tdx_speed_test.sh
  - Check network speed based on speedtest-cli, report error in case of very low network speed in TDVM
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t tdx -f tdx -x TD_NET_SPEED -c "accept_memory=lazy" -p off
  ```
### case implemented by tdx_mem_test.sh
  - Use ebizzy benchmark to validate TDX guest
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 16 -d on -t tdx -f tdx -x TD_MEM_EBIZZY_FUNC -c "accept_memory=lazy" -p off
  ```
  - Check lazy accept remained memory being fully accepted time consumed under 1VCPU 8G memory size with 1 stress-ng worker
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 8 -d on -t tdx -f tdx -x TD_MEM_ACPT_T_1C_8G_1W -c "accept_memory=lazy" -p off
  ```
  - Check lazy accept remained memory being fully accepted time consumed under 1VCPU 8G memory size with 32 stress-ng workers
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 8 -d on -t tdx -f tdx -x TD_MEM_ACPT_T_1C_8G_32W -c "accept_memory=lazy" -p off
  ```
  - Check lazy accept remained memory being fully accepted time consumed under 1VCPU 32G memory size with 1 stress-ng worker
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 32 -d on -t tdx -f tdx -x TD_MEM_ACPT_T_1C_32G_1W -c "accept_memory=lazy" -p off
  ```
  - Check lazy accept remained memory being fully accepted time consumed under 1VCPU 32G memory size with 32 stress-ng workers
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 32 -d on -t tdx -f tdx -x TD_MEM_ACPT_T_1C_32G_32W -c "accept_memory=lazy" -p off
  ```
  - Check lazy accept remained memory being fully accepted time consumed under 1VCPU 96G memory size with 1 stress-ng worker
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 96 -d on -t tdx -f tdx -x TD_MEM_ACPT_T_1C_96G_1W -c "accept_memory=lazy" -p off
  ```
  - Check lazy accept remained memory being fully accepted time consumed under 1VCPU 96G memory size with 32 stress-ng workers
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 96 -d on -t tdx -f tdx -x TD_MEM_ACPT_T_1C_96G_32W -c "accept_memory=lazy" -p of
  ```
  - Check lazy accept remained memory being fully accepted time consumed under 32VCPU 8G memory size with 32 stress-ng workers
  ```
    ./guest-test/guest.test_launcher.sh -v 32 -s 1 -m 8 -d on -t tdx -f tdx -x TD_MEM_ACPT_T_32C_8G_32W -c "accept_memory=lazy" -p off
  ```
  - Check lazy accept remained memory being fully accepted time consumed under 32VCPU 8G memory size with 256 stress-ng workers
  ```
    ./guest-test/guest.test_launcher.sh -v 32 -s 1 -m 8 -d on -t tdx -f tdx -x TD_MEM_ACPT_T_32C_8G_256W -c "accept_memory=lazy" -p off
  ```
  - Check lazy accept remained memory being fully accepted time consumed under 32VCPU 32G memory size with 32 stress-ng workers
  ```
    ./guest-test/guest.test_launcher.sh -v 32 -s 1 -m 32 -d on -t tdx -f tdx -x TD_MEM_ACPT_T_32C_32G_32W -c "accept_memory=lazy" -p off
  ```
  - Check lazy accept remained memory being fully accepted time consumed under 32VCPU 32G memory size with 256 stress-ng workers
  ```
    ./guest-test/guest.test_launcher.sh -v 32 -s 1 -m 32 -d on -t tdx -f tdx -x TD_MEM_ACPT_T_32C_32G_256W -c "accept_memory=lazy" -p off
  ```
  - Check lazy accept remained memory being fully accepted time consumed under 32VCPU 96G memory size with 32 stress-ng workers
  ```
    ./guest-test/guest.test_launcher.sh -v 32 -s 1 -m 96 -d on -t tdx -f tdx -x TD_MEM_ACPT_T_32C_96G_32W -c "accept_memory=lazy" -p off
  ```
  - Check lazy accept remained memory being fully accepted time consumed under 32VCPU 96G memory size with 256 stress-ng workers
  ```
    ./guest-test/guest.test_launcher.sh -v 32 -s 1 -m 96 -d on -t tdx -f tdx -x TD_MEM_ACPT_T_32C_96G_256W -c "accept_memory=lazy" -p off
  ```
  - Check TDX guest functional accepting memory dynamically as requested
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 16 -d on -t tdx -f tdx -x TD_MEM_ACPT_FUNC -c "accept_memory=lazy" -p off
  ```
  - Calculate based on nr_unaccepted in /proc/vmstat and Unaccepted in /proc/meminfo for correct unaccepted memory info mapping
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 16 -d on -t tdx -f tdx -x TD_MEM_ACPT_CAL -c "accept_memory=lazy" -p off
  ```
  - Check TD guest boot with lazy_accept disabled (accept_memory=eager) and nr_unaccpeted in /proc/vmstat
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 16 -d on -t tdx -f tdx -x TD_MEM_ACPT_NEG -c "accept_memory=eager" -p off
  ```
### case implemented by tdx_test_module.sh
  - Execute hlt instruction to trigger #VE handler kernel space EXIT_REASON_HLT code path
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t tdx -f tdx -x TD_VE_HALT -c "accept_memory=lazy" -p off
  ```
### case implemented by tdx_guest_bat_test.sh
  - Check cpu_info of TD guest contains tdx_guest
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t tdx -f tdx -x TD_GUEST_CPUINFO -c "accept_memory=lazy" -p off
  ```
  - Check TD guest kernel kconfig contains CONFIG_INTEL_TDX_GUEST=y
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t tdx -f tdx -x TD_GUEST_KCONFIG -c "accept_memory=lazy" -p off
  ```
  - Check TD guest kernel kconfig contains CONFIG_TDX_GUEST_DRIVER=y or m
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t tdx -f tdx -x TD_GUEST_DRIVER_KCONFIG -c "accept_memory=lazy" -p off
  ```
  - Check TD guest kernel kconfig contains CONFIG_UNACCEPTED_MEMORY=y
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t tdx -f tdx -x TD_GUEST_LAZY_ACCEPT_KCONFIG -c "accept_memory=lazy" -p off
  ```
  - Check TD guest kernel kconfig contains CONFIG_TSM_REPORTS=y or m
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t tdx -f tdx -x TD_GUEST_TSM_REPORTS_KCONFIG -c "accept_memory=lazy" -p off
  ```
  - Check TD guest kernel has ioctl based attestation device /dev/tdx_guest
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t tdx -f tdx -x TD_GUEST_ATTEST_DEV -c "accept_memory=lazy" -p off
  ```

## Latest Upstream Kernel non-applicable tests
### case implemented by tdx_guest_boot_check.sh

### case implemented by tdx_attest_check.sh
  - TD attestation - verify report mac in ioctl design
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t tdx -f tdx -x TD_ATTEST_VERITY_REPORTMAC -c "accept_memory=lazy" -p off
  ```
  - Check TD guest can extend the RTMR to include measurement registers at run-time in ioctl design
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t tdx -f tdx -x TD_ATTEST_VERIFY_RTMR_EXTEND -c "accept_memory=lazy" -p off
  ```
  - Check TDX Guest Attestation Quote Generation in ioctl design
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t tdx -f tdx -x TD_ATTEST_VERIFY_QUOTE -c "accept_memory=lazy" -p off
  ```

### case implemented by tdx_speed_test.sh

### case implemented by tdx_mem_test.sh

### case implemented by tdx_test_module.sh

### case implemented by tdx_guest_bat_test.sh

### case implemented by tdx_device_filter_test.sh
  - TD guest allow ACPI WAET table test by device filter kernel cmdline
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t tdx -f tdx -x TD_ALLOW_ACPI -c "tdx_allow_acpi=WAET" -p off
  ```
  - TD guest block ACPI WAET table test by default
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t tdx -f tdx -x TD_BLOCK_ACPI -c " " -p off
  ```
  - TD guest disable device filter test for debug purpose
  ```
    ./guest-test/guest.test_launcher.sh -v 1 -s 1 -m 1 -d on -t tdx -f tdx -x TD_NO_CCFILTER -c "noccfilter" -p off
  ```