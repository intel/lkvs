# EDAC

EDAC (Error Detection and Correction) framework provides support for detecting and correcting memory errors on systems with ECC (Error-Correcting Code) memory or other error detection mechanisms.

Intel EDAC drivers supported:
- **i10nm_edac**: ICX, SPR, EMR, GNR, SRF, CWF and other 10nm+ server platforms (CPU family 6)
- **imh_edac**: Diamond Rapids (DMR) and future IMH platforms (CPU family 19)

The test script auto-detects the platform and selects the appropriate driver.

## Test Cases

| Test | Description |
|------|-------------|
| check_edac_bus | Verify EDAC bus exists and has registered devices |
| check_edac_driver | Verify EDAC driver is loaded (attempts modprobe if not) |
| edac_addr_decode | Test address decoding via EDAC debugfs interface |
| edac_mc_index_change | Inject errors and verify multiple MC indices in decode log |
| edac_mc_check_populated | Cross-check decoded MCs against sysfs populated MCs |

## Usage

Run cases individually:

```
./intel_edac.sh -t check_edac_bus
./intel_edac.sh -t edac_addr_decode
```

Run all cases with runtests:

```
cd ..
./runtests -f edac/tests -o logfile
```
