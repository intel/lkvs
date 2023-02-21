# Control-flow Enforcement Technology

## Description
Control-flow Enforcement Technology(CET) is a security feature in Intel
Processors. The 11th generation and later Intel CPUs will support the CET
feature.

CET is the best method to prevent ROP/JOP attack from the root cause
(instruction level) from compatibility and performance perspective.

CET contains 2 parts of functions: shadow stack(SHSTK) and indirect branch
tracking(IBT).

1. Shadow Stack – return address protection to defend against Return Oriented
   Programming(ROP),
2. Indirect Branch Tracking – free branch protection to defend against
   Jump/Call Oriented Programming(JOP).

Only userspace SHSTK cases will be provided in current stage.

Userspace IBT cases will be provided in the future.

## Usage
make
./quick_test
This tool will test the shadow stack violation in shstk enabled(in ELF) binary:
enabled binary or process with below check points:
1. Do the SHSTK violation, and receive the expected signal
2. Do the SHSTK violation triggered by signal, and should receive expected sinal
   It can quickly verify that SHSTK is working in the test environment

./test_shadow_stack
This tool test the shadow stack violation, enabling/disabling by syscall way
in non-shstk(in ELF) binary.
Test SHSTK violation by arch_prctl syscall way in non-SHSTK binary with below
points:
1. Enable shadow stack by ARCH_CET_ENABLE syscall
2. Disable shadow stack by ARCH_CET_DISABLE syscall
3. Enable SHSTK writeable by ARCH_SHSTK_WRSS syscall
4. Allocate the shstk buffer by map_shadow_stack syscall
5. Do the SHSTK violation by wrss the wrong shstk value, and recevie the
   expected signal SIGSEGV
6. Disable the SHSTK after the test, and there is no exception as expected

./shstk_huge_page
This tool will test the huge page of shstk buffer allocation and usage:
assigned 4M buffer for shadow stack, and do the loop calls to fill the shstk
buf without issue:
1. Assigned the 4M shadow stack buf without issue
2. Made test process to use the 4M shadow stack by call/ret without issue
3. Test loop ping-pong call to fill the shstk buffer without issue
4. After all above loop calls finished, check the rbp + 8 bytes value should
   same as SHSTK value

./shstk_alloc
This tool's purpose is testing SHSTK related instructions:
1. Test shstk buffer allocation for one new shstk buffer
2. Test rstorssp, saveprevssp, rdsspq to load new shstk buffer
3. Test rstorssp, saveprevssp to restore the previous shstk buffer

./wrss
This tool will test wrss into shadow stack by wrss(q for 64bit) instruction in
SHSTK enabled binary:
1. Enable writable shadow stack via system call "ARCH_CET_ENABLE and ARCH_SHSTK_WRSS"
2. Write one incorrect value into shadow stack
3. The expected SISEGV should be received after ret instruction

## Expected result
All test results should show pass, no fail.
