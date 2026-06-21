# RAS

Intel Xeon processor Scalable family supports various Reliability, Availability, and Serviceability (RAS) features across the product lineup.

This test suite targets Intel 10nm+ server platforms (ICX, SPR, EMR, GNR, SRF, CWF, DMR).
The EDAC driver loaded is `i10nm_edac` for Family 6 or `imh_edac` for Family 19 (DMR+).

Current BM/ras covers following features:
* basic error injection
* EINJv2 memory error injection
* LMCE (Local Machine Check Exception)
* MCE corrected error threshold (yellow status via mce-inject)

## Submodules

| Submodule | Source | Purpose |
|-----------|--------|---------|
| mce-test | kernel.org | MCE test suite (APEI, EINJ, EMCA, ERST, PFA, etc.) |
| mce-inject | kernel.org | MCE event injection tool |
| ras-tools | kernel.org | LMCE injection binary |
| mcelog | github.com/andikleen | Machine check event logger (legacy) |
| rasdaemon | github.com/mchehab | RAS daemon using kernel tracepoints (modern) |

## MCE Logging Backend

The test suite supports two MCE logging backends:
- **mcelog** — legacy daemon reading from `/dev/mcelog`
- **rasdaemon** — modern daemon using kernel tracepoints, stores events in SQLite

The Makefile automatically detects which is installed on your system:
- If a backend is already installed from your distro packages, it will be used as-is.
- If neither is found, both are built from their respective submodules.

Most tests (`tests`) work with either backend. Tests in `tests_mcelog` require mcelog specifically.

## Usage
Before test case execution:
1. make sure git submodules are initialized and updated:
```
git submodule update --init --recursive
```
2. install the MCE logging backend from your distribution (preferred):
```
# Option A: mcelog (legacy, CentOS/RHEL 7)
yum install mcelog

# Option B: rasdaemon (modern, RHEL 8+, Fedora, Ubuntu 22.04+)
yum install rasdaemon    # or: apt install rasdaemon
```
If neither is available from your distro, the Makefile will build from the submodule.

3. build the test suite (only builds submodules not already installed):
```
make
sudo make install
```
4. make sure other required packages are installed:
```
yum install msr-tools cpuid screen    # for CentOS/RHEL
apt install msr-tools cpuid screen    # for Debian/Ubuntu
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
