// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2024 Intel Corporation.

/*
 * apx_egpr.c - Test APX Extended General Purpose Registers (R16-R31).
 *
 * Tests basic EGPR functionality:
 *   1. basic_rw  - Write/read each EGPR and verify values
 *   2. all_regs  - Load all 16 EGPRs simultaneously and verify
 *   3. syscall_clobber - Verify EGPRs are caller-saved across syscalls
 *
 * Requires: GCC 14+ with -mapxf or assembler with APX support.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <stdbool.h>
#include <stdlib.h>
#include <getopt.h>
#include <cpuid.h>

typedef uint32_t u32;
typedef uint64_t u64;

#include "../common/kselftest.h"

static void check_apx_support(void)
{
	u32 eax, ebx, ecx, edx;

	__cpuid_count(7, 1, eax, ebx, ecx, edx);
	if (!(edx & (1U << 21)))
		ksft_exit_skip("CPU doesn't support APX (CPUID.7.1:EDX[21]).\n");
}

/*
 * Test basic read/write of individual EGPRs.
 * Load a known value into each register, then read it back.
 */
static void test_basic_rw(void)
{
	u64 val_out;
	u64 test_pattern = 0xDEADBEEFCAFEBABEULL;
	bool pass = true;
	int i;

	/*
	 * For each EGPR, we load a distinct value and verify it reads back.
	 * Using GCC register variables with -mapxf support.
	 */
	for (i = 0; i < 16; i++) {
		u64 expected = test_pattern + i;

		/*
		 * Use inline asm with .byte encoding for REX2 MOV.
		 * MOV imm64 to R(16+i): REX2 prefix + MOV opcode + register encoding.
		 *
		 * Simplified: with -mapxf, the compiler handles this natively.
		 * Here we use a compile-time unrolled approach for register 16 as example.
		 */
		if (i == 0) {
			asm volatile("mov %1, %%r16\n\t"
				"mov %%r16, %0\n\t"
				: "=r"(val_out)
				: "r"(expected)
				: "r16"
			);
		} else if (i == 1) {
			asm volatile("mov %1, %%r17\n\t"
				"mov %%r17, %0\n\t"
				: "=r"(val_out)
				: "r"(expected)
				: "r17"
			);
		} else if (i == 2) {
			asm volatile("mov %1, %%r18\n\t"
				"mov %%r18, %0\n\t"
				: "=r"(val_out)
				: "r"(expected)
				: "r18"
			);
		} else if (i == 3) {
			asm volatile("mov %1, %%r19\n\t"
				"mov %%r19, %0\n\t"
				: "=r"(val_out)
				: "r"(expected)
				: "r19"
			);
		} else if (i == 4) {
			asm volatile("mov %1, %%r20\n\t"
				"mov %%r20, %0\n\t"
				: "=r"(val_out)
				: "r"(expected)
				: "r20"
			);
		} else if (i == 5) {
			asm volatile("mov %1, %%r21\n\t"
				"mov %%r21, %0\n\t"
				: "=r"(val_out)
				: "r"(expected)
				: "r21"
			);
		} else if (i == 6) {
			asm volatile("mov %1, %%r22\n\t"
				"mov %%r22, %0\n\t"
				: "=r"(val_out)
				: "r"(expected)
				: "r22"
			);
		} else if (i == 7) {
			asm volatile("mov %1, %%r23\n\t"
				"mov %%r23, %0\n\t"
				: "=r"(val_out)
				: "r"(expected)
				: "r23"
			);
		} else if (i == 8) {
			asm volatile("mov %1, %%r24\n\t"
				"mov %%r24, %0\n\t"
				: "=r"(val_out)
				: "r"(expected)
				: "r24"
			);
		} else if (i == 9) {
			asm volatile("mov %1, %%r25\n\t"
				"mov %%r25, %0\n\t"
				: "=r"(val_out)
				: "r"(expected)
				: "r25"
			);
		} else if (i == 10) {
			asm volatile("mov %1, %%r26\n\t"
				"mov %%r26, %0\n\t"
				: "=r"(val_out)
				: "r"(expected)
				: "r26"
			);
		} else if (i == 11) {
			asm volatile("mov %1, %%r27\n\t"
				"mov %%r27, %0\n\t"
				: "=r"(val_out)
				: "r"(expected)
				: "r27"
			);
		} else if (i == 12) {
			asm volatile("mov %1, %%r28\n\t"
				"mov %%r28, %0\n\t"
				: "=r"(val_out)
				: "r"(expected)
				: "r28"
			);
		} else if (i == 13) {
			asm volatile("mov %1, %%r29\n\t"
				"mov %%r29, %0\n\t"
				: "=r"(val_out)
				: "r"(expected)
				: "r29"
			);
		} else if (i == 14) {
			asm volatile("mov %1, %%r30\n\t"
				"mov %%r30, %0\n\t"
				: "=r"(val_out)
				: "r"(expected)
				: "r30"
			);
		} else if (i == 15) {
			asm volatile("mov %1, %%r31\n\t"
				"mov %%r31, %0\n\t"
				: "=r"(val_out)
				: "r"(expected)
				: "r31"
			);
		}

		if (val_out != expected) {
			ksft_print_msg("[FAIL] R%d: wrote 0x%llx, read 0x%llx\n",
				       i + 16, (unsigned long long)expected,
				       (unsigned long long)val_out);
			pass = false;
		}
	}

	if (pass)
		ksft_test_result_pass("Basic EGPR read/write for all R16-R31\n");
	else
		ksft_test_result_fail("EGPR read/write mismatch detected\n");
}

/*
 * Test all 16 EGPRs loaded simultaneously.
 * Verifies no interference between registers.
 */
static void test_all_regs(void)
{
	u64 out[16];
	u64 pattern = 0x1122334455667788ULL;
	bool pass = true;
	int i;

	register u64 r16 asm("r16") = pattern + 0;
	register u64 r17 asm("r17") = pattern + 1;
	register u64 r18 asm("r18") = pattern + 2;
	register u64 r19 asm("r19") = pattern + 3;
	register u64 r20 asm("r20") = pattern + 4;
	register u64 r21 asm("r21") = pattern + 5;
	register u64 r22 asm("r22") = pattern + 6;
	register u64 r23 asm("r23") = pattern + 7;
	register u64 r24 asm("r24") = pattern + 8;
	register u64 r25 asm("r25") = pattern + 9;
	register u64 r26 asm("r26") = pattern + 10;
	register u64 r27 asm("r27") = pattern + 11;
	register u64 r28 asm("r28") = pattern + 12;
	register u64 r29 asm("r29") = pattern + 13;
	register u64 r30 asm("r30") = pattern + 14;
	register u64 r31 asm("r31") = pattern + 15;

	/* Force compiler to keep all registers live */
	asm volatile("" : "+r"(r16), "+r"(r17), "+r"(r18), "+r"(r19),
		     "+r"(r20), "+r"(r21), "+r"(r22), "+r"(r23));
	asm volatile("" : "+r"(r24), "+r"(r25), "+r"(r26), "+r"(r27),
		     "+r"(r28), "+r"(r29), "+r"(r30), "+r"(r31));

	out[0] = r16; out[1] = r17; out[2] = r18; out[3] = r19;
	out[4] = r20; out[5] = r21; out[6] = r22; out[7] = r23;
	out[8] = r24; out[9] = r25; out[10] = r26; out[11] = r27;
	out[12] = r28; out[13] = r29; out[14] = r30; out[15] = r31;

	for (i = 0; i < 16; i++) {
		if (out[i] != pattern + i) {
			ksft_print_msg("[FAIL] R%d: expected 0x%llx, got 0x%llx\n",
				       i + 16, (unsigned long long)(pattern + i),
				       (unsigned long long)out[i]);
			pass = false;
		}
	}

	if (pass)
		ksft_test_result_pass("All 16 EGPRs loaded simultaneously and verified\n");
	else
		ksft_test_result_fail("Simultaneous EGPR load interference detected\n");
}

/*
 * Test that EGPRs are caller-saved across syscalls.
 * The kernel does NOT preserve R16-R31 across syscall boundaries
 * (they are not part of the syscall ABI), but the XSAVE/XRSTOR
 * mechanism should save/restore them on context switch.
 *
 * This test verifies the kernel's behavior: after getpid() syscall,
 * the EGPR values should still be intact because we're not context-switched.
 */
static void test_syscall_clobber(void)
{
	u64 before, after;
	u64 pattern = 0xAABBCCDD11223344ULL;

	/*
	 * Load R16 with a known value, do a simple syscall (getpid),
	 * then check if R16 is preserved. The syscall ABI doesn't
	 * guarantee preservation of EGPRs, but if no context switch
	 * happens, they should remain (the kernel doesn't touch them).
	 */
	before = pattern;
	asm volatile("mov %1, %%r16\n\t"
		"mov $39, %%eax\n\t"	/* SYS_getpid */
		"syscall\n\t"
		"mov %%r16, %0\n\t"
		: "=r"(after)
		: "r"(before)
		: "rax", "rcx", "r11", "r16", "memory"
	);

	if (after == before)
		ksft_test_result_pass("EGPR R16 preserved across getpid() syscall\n");
	else
		ksft_test_result_fail("EGPR R16 clobbered by syscall: before=0x%llx after=0x%llx\n",
				      (unsigned long long)before,
				      (unsigned long long)after);
}

static void usage(const char *prog)
{
	fprintf(stderr, "Usage: %s -t <test>\n", prog);
	fprintf(stderr, "Tests:\n");
	fprintf(stderr, "  basic_rw       - Individual EGPR read/write\n");
	fprintf(stderr, "  all_regs       - All EGPRs loaded simultaneously\n");
	fprintf(stderr, "  syscall_clobber - EGPR behavior across syscalls\n");
}

int main(int argc, char *argv[])
{
	const char *test_name = NULL;
	int opt;

	while ((opt = getopt(argc, argv, "t:")) != -1) {
		switch (opt) {
		case 't':
			test_name = optarg;
			break;
		default:
			usage(argv[0]);
			return 1;
		}
	}

	if (!test_name) {
		usage(argv[0]);
		return 1;
	}

	ksft_print_header();
	ksft_set_plan(1);

	check_apx_support();

	if (strcmp(test_name, "basic_rw") == 0)
		test_basic_rw();
	else if (strcmp(test_name, "all_regs") == 0)
		test_all_regs();
	else if (strcmp(test_name, "syscall_clobber") == 0)
		test_syscall_clobber();
	else
		ksft_exit_fail_msg("Unknown test: %s\n", test_name);

	ksft_finished();
	return 0;
}
