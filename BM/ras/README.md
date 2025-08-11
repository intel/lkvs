# RAS

Intel Xeon processor Scalable family supports various Reliability, Availability, and Serviceability (RAS) features across the product lineup.

Current BM/ras covers following features:
* basic error injection

## Usage
Before test case execution:
1. make sure git submodules are initialized and updated:
```
git submodule update --init --recursive
```
2. make sure required packages are installed:
```
yum install msr-tools cpuid mcelog screen # for CentOS
apt install msr-tools cpuid mcelog screen # for Debian/Ubuntu
```

You can run the cases one by one, e.g. command

```
./mce_test.sh -t apei-inj
./lmce_test.sh -t sameaddr_samecore_instr/instr
```
You also can run the cases together with runtests command, e.g.

```
cd ..
./runtests -f ras/tests -o logfile
```
