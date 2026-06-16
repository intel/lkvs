# Intel APX (Advanced Performance Extensions) Tests

## Overview

Intel APX extends the x86-64 ISA with:
- **Extended General Purpose Registers (EGPRs)**: 16 additional 64-bit registers (R16-R31)
- **REX2 prefix**: New 2-byte prefix encoding (0xD5) enabling access to EGPRs
- **Extended EVEX**: Promotes legacy instructions to use EGPRs via EVEX encoding
- **NDD (New Data Destination)**: Non-destructive destination forms of instructions
- **NF (No Flags)**: Suppress flag updates for certain instructions
- **CFCMOV**: Conditional flag-based CMOVcc with memory destination support

## Kernel Support Tested

1. **CPUID enumeration**: CPUID.(EAX=7, ECX=1):EDX[21] for APX feature
2. **XSAVE/XRSTOR**: XFEATURE_APX (state component 19) - saves/restores EGPR state
3. **XSTATE size**: 128 bytes (16 x 8-byte registers)
4. **Signal handling**: EGPR state preserved across signal delivery and return
5. **Context switch**: EGPR state preserved across fork and context switches
6. **Instruction decoder**: REX2 prefix (0xD5) parsing in kernel oops decoder
7. **APX/MPX mutual exclusion**: Kernel rejects CPUs advertising both APX and MPX

## Platform Support

- **DMR** (Diamond Rapids) and later

## Test Structure

```
apx/
├── CMakeLists.txt          # Build system
├── Makefile                # Legacy make support
├── README.md               # This file
├── tests                   # Test case list for runtests framework
├── apx_xstate.c            # XSAVE/XRSTOR EGPR tests (signal, fork, context switch)
├── apx_xstate_helpers.c    # Assembly helpers for EGPR manipulation
├── apx_xstate_helpers.h    # Helper declarations
├── apx_egpr.c              # EGPR basic functionality tests
└── apx_instructions.c      # APX instruction encoding tests (NDD, NF, CFCMOV)
```

## Dependencies

- CPU with APX support (CPUID.7.1:EDX[21])
- Kernel with CONFIG_X86_64=y and XSAVE support
- GCC 14+ or Clang 19+ with `-mapxf` flag for APX instruction encoding
- Binutils 2.43+ for APX assembler support
