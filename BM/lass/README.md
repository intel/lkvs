#LASS

## Description
Linear Address Space Separation (LASS) aims to prevent side-channel attacks based that rely on timing memory accesses (cache hits will have shorter access times).

LASS achieves this by preventing memory loads/stores to user space memory in supervisor mode and vice versa (access to kernel memory in user mode).

## Usage
```
make
# To run a specific case
./lam -t <testcase_id>
(for example, cpuid) ./lass m
```
Test results (PASS or FAIL) will be printed out. 

## Testcase ID
| Case ID | Case Name |
| ------ | ------------------------------------------------------------------- |
| m      |  Test get vsyscall address maps.[negative]                          |
| d      |  Test execute vsyscall addr 0xffffffffff600000.[negative]           |
| g      |  Test call vsyscall                                                 |
| t      |  Test call vsyscall api gettimeofday                                |
| r      |  Test read vsyscall 0xffffffffff600000.[negative]                   |
| i      |  Test read random kernel space.[negative]                           |
| v      |  Test process_vm_readv read address 0xffffffffff600000.[negative]   |
| e      |  Test vsyscall emulation.                                           |
