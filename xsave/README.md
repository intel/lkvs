# XSAVE

## Description
The XSAVE feature set supports the saving and restoring of xstate components.
XSAVE feature has been used for process context switching. Xstate components
include x87 state for FP execution environment, SSE state, AVX state and so on.

In order to ensure that XSAVE works correctly, add XSAVE most basic test for
XSAVE architecture functionality.

From page 21 of ABI(Application Binary Interface) specification:
https://refspecs.linuxbase.org/elf/x86_64-abi-0.99.pdf
Xstate like XMM is not preserved across function calls, so fork() function
which provided from libc could not be used in the xsave test, and the libc
function is replaced with an inline function of the assembly code only.

To prevent GCC from generating any FP/SSE(XMM)/AVX/PKRU code by mistake, add
"-mno-sse -mno-mmx -mno-sse2 -mno-avx -mno-pku" compiler arguments. stdlib.h
can not be used because of the "-mno-sse" option.

## Usage
make
./xstate_64
It tests "FP, SSE(XMM), AVX2(YMM), AVX512_OPMASK/AVX512_ZMM_Hi256/
AVX512_Hi16_ZMM and PKRU parts" xstates with the following cases:
1. The contents of these xstates in the process should not change after the
   signal handling.
2. The contents of these xstates in the child process should be the same as
   the contents of the xstate in the parent process after the fork syscall.
3. The contents of xstates in the parent process should not change after
   the context switch.

## Expected result
All test results should show pass, no fail.
