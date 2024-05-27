# EDAC

EDAC (Error Detection and Correction) framework provides support for detecting and correcting memory errors on systems with ECC (Error-Correcting Code) memory or other error detection mechanism.

Intel i10nm EDAC driver supports the Intel 10nm series server integrated memory controller.

## Usage

You can run the cases one by one, e.g. command

```
./intel_edac.sh -t check_edac_bus
```
You also can run the cases together with runtests command, e.g.

```
cd ..
./runtests -f edac/tests -o logfile
```
