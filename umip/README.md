# User-Mode Instruction Prevention

## Description
User-Mode Instruction Prevention(UMIP) is a security feature in Intel
Processors. The 8th generation and later Intel CPUs will support
the UMIP feature. If UMIP is enabled and in CPL(Current Privilege Level) > 0
environment, it verifies that execution of the instructions(SGDT, SIDT,
SLDT, SMSW, STR) with mapped fault page should return the signal
SIGSEGV(Segmentation Violation); above instructions with locked prefix
opcode should return signal SIGILL(Illegal); SIDT and SGDT with illegal
opcode should return signal SIGILL.

Below instructions are protected by UMIP feature:
* SGDT - Store Global Descriptor Table
* SIDT - Store Interrupt Descriptor Table
* SLDT - Store Local Descriptor Table
* SMSW - Store Machine Status Word
* STR  - Store Task Register

## Usage
make
./umip_exceptions_64 a
and
./umip_exceptions_32 a
It tests all 3 types of cases:
1. Execution of the instructions(SGDT, SIDT, SLDT, SMSW, STR) with mapped fault
   page should return the signal SIGSEGV.
2. Execution of the instructions(SGDT, SIDT, SLDT, SMSW, STR) with locked prefix
   opcode should return the signal SIGILL(Illegal).
3. Execution of the instructions SGDT and SIDT with illegal opcode should return
   the signal SIGILL.

## Expected result
All test results should show pass without fail.
