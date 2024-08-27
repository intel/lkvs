# RAS

Intel Xeon processor Scalable family supports various Reliability, Availability, and Serviceability (RAS) features across the product lineup.

Current BM/ras covers following features:
* basic error injection

## Usage
Before test case execution, make sure git submodules are initialized and updated:
```
git submodule update --init --recursive
```

You can run the cases one by one, e.g. command

```
./mce_test.sh -t apei-inj
```
You also can run the cases together with runtests command, e.g.

```
cd ..
./runtests -f ras/tests -o logfile
```
