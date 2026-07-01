# CPU Family / Model CPUID Test

## Description
Verifies that the running kernel and SUT CPUID matches the expected
Intel platform CPUID definitions added in the kernel header
`arch/x86/include/asm/intel-family.h`.

For the platform specified with `-p`, the test checks all sources of
truth in a single invocation:

1. `/proc/cpuinfo` vendor / family / model
2. `cpuid` utility synthesized family / model from leaf `0x01`
3. (Optional) `#define <INTEL_*_MACRO>` in
   `arch/x86/include/asm/intel-family.h`, when `-s <linux-src>` is given

Any mismatch fails the whole test. Missing prerequisites (e.g. the
`cpuid` utility, an unsupported `-p` value) BLOCK the test.

Current platform database:

| Code | Platform            | Vendor       | Family (dec/hex) | Model (dec/hex) | Kernel macro             | Kernel IFM      |
| ---- | ------------------- | ------------ | ---------------- | --------------- | ------------------------ | --------------- |
| DMR  | Diamond Rapids      | GenuineIntel | 19 / 0x13        | 1 / 0x01        | `INTEL_DIAMONDRAPIDS_X`  | `IFM(19, 0x01)` |
| CWF  | Clearwater Forest   | GenuineIntel | 6 / 0x06         | 221 / 0xDD      | `INTEL_ATOM_DARKMONT_X`  | `IFM(6, 0xDD)`  |

Add new rows to `PLATFORM_DB` inside `cpu_family_model_test.sh` for new platforms.

## Usage
Prepare the BM folder as usual (no-op for this pure-shell suite):
```
cd ../
make
```

Run the check for a specific platform:
```
./cpu_family_model_test.sh -p DMR
./cpu_family_model_test.sh -p CWF
```

Additionally verify the intel-family.h macro against a Linux source tree:
```
./cpu_family_model_test.sh -p DMR -s /root/linux
./cpu_family_model_test.sh -p CWF -s /root/linux
```

List supported platforms:
```
./cpu_family_model_test.sh -l
```

Run through `runtests`:
```
cd ..
./runtests -f cpu_family_model/tests-dmr -o cpu_family_model_dmr.log
./runtests -f cpu_family_model/tests-cwf -o cpu_family_model_cwf.log
```

## Options
| Option | Description                                                             |
| ------ | ----------------------------------------------------------------------- |
| `-p`   | Expected platform code (e.g. `DMR`, `CWF`). Required.                   |
| `-s`   | Path to a Linux kernel source tree for the optional header check.       |
| `-l`   | List supported platforms and their expected CPUID values.               |
| `-h`   | Show usage.                                                             |

## Dependencies
- `cpuid` utility (`apt install cpuid` on Debian/Ubuntu, `dnf install cpuid`
  on RHEL/CentOS) is required.
- A Linux kernel source tree is required only for the optional
  `intel-family.h` macro check.

## Expected result
`PASS` for all checks on a matching SUT.
`FAIL` if any /proc/cpuinfo or cpuid value diverges from the platform DB.
`BLOCK` when the `cpuid` utility is missing, `-p` is omitted, or the platform code is unknown.
