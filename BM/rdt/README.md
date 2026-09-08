# Linux ACPI MRRM/ERDT test

This feature validates the running Linux kernel's ACPI support for the Intel
Resource Director Technology MRRM and ERDT tables. It does not use the
userspace ACPICA tools or build an external kernel module.

The testcase reads MRRM and ERDT through `/sys/firmware/acpi/tables`. That
sysfs path retrieves each table through the kernel ACPICA table manager. It
validates each ACPI header, declared length, checksum, and subtable boundaries.
It also requires `/sys/firmware/acpi/memory_ranges/range*`, which proves that
the Linux MRRM driver parsed the table and exported its entries, and rejects
MRRM/ERDT initialization errors reported in the kernel log.

Run it from the `BM` directory:

```bash
./runtests -f rdt/tests-acpica-mrrm-erdt
```

Run this testcase on a kernel and platform that provide MRRM and ERDT. Missing
firmware tables are reported as `BLOCK`; malformed tables or missing kernel
parse results are reported as `FAIL`.