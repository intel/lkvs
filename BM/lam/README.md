# LAM

## Description
Linear Address Masking (LAM) is a new feature in the latest Intel platform Sierra Forest.
LAM modifies the checking that is applied to 64-bit linear addresses, allowing software 
to use of the untranslated address bits for metadata.
This test suite provides basic functional check to ensure LAM works properly.

## Usage
```
make
# To run a specific case
./lam -t <testcase_id>
(for example, cpuid) ./lam -t 0x80
```
Test results (PASS or FAIL) will be printed out. 

## Testcase ID
| Case ID | Case Name |
| ------ | ---------------------------- |
| 0x1    | malloc   |
| 0x2    | max_bits |
| 0x4    | mmap     |
| 0x8    | syscall  |
| 0x10   | io_uring |
| 0x20   | inherit  |
| 0x40   | pasid    |
| 0x80   | cpuid    |
