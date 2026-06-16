// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2024 Intel Corporation.

/*
 * apx_instructions.c - Test APX new instruction encodings.
 *
 * Tests APX instruction sub-features exercisable from user space:
 *   - NDD (New Data Destination): non-destructive 3-operand form
 *   - NF (No Flags): instructions that suppress EFLAGS updates
 *   - CFCMOV: conditional moves with memory destination
 *   - PUSH2/POP2: push/pop register pairs
 *
 * These instructions use EVEX or REX2 encoding and require APX support.
 * The tests verify that the CPU correctly executes these new encodings
 * and produces expected results.
 *
 * Requires: assembler with APX support (GNU as 2.43+ or LLVM 19+).
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdbool.h>
#include <stdlib.h>
#include <getopt.h>
#include <signal.h>
#include <setjmp.h>
#include <cpuid.h>

typedef uint8_t  u8;
typedef uint32_t u32;
typedef uint64_t u64;

#include "../common/kselftest.h"

static sigjmp_buf jmpbuf;
static sig_atomic_t sigill_received;

static void sigill_handler(int sig)
{
	sigill_received = true;
	siglongjmp(jmpbuf, 1);
}

static void check_apx_support(void)
{
	u32 eax, ebx, ecx, edx;

	__cpuid_count(7, 1, eax, ebx, ecx, edx);
	if (!(edx & (1U << 21)))
		ksft_exit_skip("CPU doesn't support APX (CPUID.7.1:EDX[21]).\n");
}

/*
 * Helper: install SIGILL handler to catch #UD from unsupported instructions.
 */
static void setup_sigill_handler(void)
{
	struct sigaction sa;

	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = sigill_handler;
	sigemptyset(&sa.sa_mask);
	sigaction(SIGILL, &sa, NULL);
}

/*
 * NDD ADD: dst = src1 + src2 (non-destructive, src1 unchanged)
 * EVEX.NDD encoding: ADD r64, r/m64, r64
 *
 * Example: {evex} add %rax, %rbx, %rcx  =>  rcx = rax + rbx (rax, rbx unchanged)
 */
static void test_ndd_add(void)
{
	u64 src1 = 100, src2 = 200, dst = 0;

	sigill_received = false;
	setup_sigill_handler();

	if (sigsetjmp(jmpbuf, 1) == 0) {
		/* NDD ADD: %0 = %1 + %2 */
		asm volatile("add %1, %2, %0\n\t"
			: "=r"(dst)
			: "r"(src1), "r"(src2)
			:
		);
	}

	if (sigill_received) {
		ksft_test_result_fail("NDD ADD raised #UD (not supported)\n");
	} else if (dst == 300) {
		ksft_test_result_pass("NDD ADD: dst=%llu (100+200)\n",
				      (unsigned long long)dst);
	} else {
		ksft_test_result_fail("NDD ADD: expected dst=300; got dst=%llu\n",
				      (unsigned long long)dst);
	}
}

/*
 * NDD SUB: dst = src1 - src2 (non-destructive)
 */
static void test_ndd_sub(void)
{
	u64 src1 = 500, src2 = 200, dst = 0;

	sigill_received = false;
	setup_sigill_handler();

	if (sigsetjmp(jmpbuf, 1) == 0) {
		/* NDD SUB: %0 = %2 - %1 (AT&T: sub src,rm,ndd => ndd = rm - src) */
		asm volatile("sub %1, %2, %0\n\t"
			: "=r"(dst)
			: "r"(src2), "r"(src1)
			:
		);
	}

	if (sigill_received)
		ksft_test_result_fail("NDD SUB raised #UD\n");
	else if (dst == 300)
		ksft_test_result_pass("NDD SUB: dst=%llu (500-200)\n",
				      (unsigned long long)dst);
	else
		ksft_test_result_fail("NDD SUB: expected 300, got %llu\n",
				      (unsigned long long)dst);
}

/*
 * NDD AND: dst = src1 & src2 (non-destructive)
 */
static void test_ndd_and(void)
{
	u64 src1 = 0xFF00FF00, src2 = 0xFFFF0000, dst = 0;

	sigill_received = false;
	setup_sigill_handler();

	if (sigsetjmp(jmpbuf, 1) == 0) {
		asm volatile("and %1, %2, %0\n\t"
			: "=r"(dst)
			: "a"(src1), "b"(src2)
			:
		);
	}

	if (sigill_received)
		ksft_test_result_fail("NDD AND raised #UD\n");
	else if (dst == (src1 & src2))
		ksft_test_result_pass("NDD AND: dst=0x%llx\n", (unsigned long long)dst);
	else
		ksft_test_result_fail("NDD AND: expected 0x%llx, got 0x%llx\n",
				      (unsigned long long)(src1 & src2),
				      (unsigned long long)dst);
}

/*
 * NDD OR: dst = src1 | src2 (non-destructive)
 */
static void test_ndd_or(void)
{
	u64 src1 = 0x00FF0000, src2 = 0x000000FF, dst = 0;

	sigill_received = false;
	setup_sigill_handler();

	if (sigsetjmp(jmpbuf, 1) == 0) {
		asm volatile("or %1, %2, %0\n\t"
			: "=r"(dst)
			: "a"(src1), "b"(src2)
			:
		);
	}

	if (sigill_received)
		ksft_test_result_fail("NDD OR raised #UD\n");
	else if (dst == (src1 | src2))
		ksft_test_result_pass("NDD OR: dst=0x%llx\n", (unsigned long long)dst);
	else
		ksft_test_result_fail("NDD OR: expected 0x%llx, got 0x%llx\n",
				      (unsigned long long)(src1 | src2),
				      (unsigned long long)dst);
}

/*
 * NDD XOR: dst = src1 ^ src2 (non-destructive)
 */
static void test_ndd_xor(void)
{
	u64 src1 = 0xAAAAAAAA, src2 = 0x55555555, dst = 0;

	sigill_received = false;
	setup_sigill_handler();

	if (sigsetjmp(jmpbuf, 1) == 0) {
		asm volatile("xor %1, %2, %0\n\t"
			: "=r"(dst)
			: "a"(src1), "b"(src2)
			:
		);
	}

	if (sigill_received)
		ksft_test_result_fail("NDD XOR raised #UD\n");
	else if (dst == (src1 ^ src2))
		ksft_test_result_pass("NDD XOR: dst=0x%llx\n", (unsigned long long)dst);
	else
		ksft_test_result_fail("NDD XOR: expected 0x%llx, got 0x%llx\n",
				      (unsigned long long)(src1 ^ src2),
				      (unsigned long long)dst);
}

/*
 * NDD SHL: dst = src1 << count (non-destructive)
 */
static void test_ndd_shl(void)
{
	u64 src = 1, dst = 0;
	u8 count = 16;

	sigill_received = false;
	setup_sigill_handler();

	if (sigsetjmp(jmpbuf, 1) == 0) {
		asm volatile("shl %%cl, %1, %0\n\t"
			: "=r"(dst)
			: "r"(src), "c"(count)
			:
		);
	}

	if (sigill_received)
		ksft_test_result_fail("NDD SHL raised #UD\n");
	else if (dst == (src << count))
		ksft_test_result_pass("NDD SHL: 1<<%u = %llu\n",
				      count, (unsigned long long)dst);
	else
		ksft_test_result_fail("NDD SHL: expected %llu, got %llu\n",
				      (unsigned long long)(src << count),
				      (unsigned long long)dst);
}

/*
 * NDD SHR: dst = src1 >> count (non-destructive)
 */
static void test_ndd_shr(void)
{
	u64 src = 0x10000, dst = 0;
	u8 count = 8;

	sigill_received = false;
	setup_sigill_handler();

	if (sigsetjmp(jmpbuf, 1) == 0) {
		asm volatile("shr %%cl, %1, %0\n\t"
			: "=r"(dst)
			: "r"(src), "c"(count)
			:
		);
	}

	if (sigill_received)
		ksft_test_result_fail("NDD SHR raised #UD\n");
	else if (dst == (src >> count))
		ksft_test_result_pass("NDD SHR: 0x10000>>%u = 0x%llx\n",
				      count, (unsigned long long)dst);
	else
		ksft_test_result_fail("NDD SHR: expected 0x%llx, got 0x%llx\n",
				      (unsigned long long)(src >> count),
				      (unsigned long long)dst);
}

/*
 * NF ADD: add without updating EFLAGS.
 * After NF ADD, the flags should be unchanged from their prior state.
 */
static void test_nf_add(void)
{
	u64 result;
	u64 flags_before, flags_after;

	sigill_received = false;
	setup_sigill_handler();

	if (sigsetjmp(jmpbuf, 1) == 0) {
		/* Set flags to a known state (clear CF,ZF,SF,OF) */
		asm volatile("xor %%eax, %%eax\n\t"       /* ZF=1, others cleared */
			"pushfq\n\t"
			"pop %1\n\t"                  /* Save flags before */
			/* NF ADD: rax = rax + rbx, no flags update */
			"mov $100, %%rax\n\t"
			"mov $200, %%rbx\n\t"
			".byte 0x62, 0xf4, 0xfc, 0x0c, 0x01, 0xd8\n\t"  /* NF ADD */
			"pushfq\n\t"
			"pop %2\n\t"                  /* Save flags after */
			"mov %%rax, %0\n\t"
			: "=r"(result), "=r"(flags_before), "=r"(flags_after)
			:
			: "rax", "rbx", "memory"
		);
	}

	if (sigill_received) {
		ksft_test_result_fail("NF ADD raised #UD\n");
	} else if (result == 300 && flags_before == flags_after) {
		ksft_test_result_pass("NF ADD: result=%llu, flags unchanged\n",
				      (unsigned long long)result);
	} else {
		ksft_test_result_fail("NF ADD: got %llu, bef=0x%llx, aft=0x%llx\n",
				      (unsigned long long)result,
				      (unsigned long long)flags_before,
				      (unsigned long long)flags_after);
	}
}

/*
 * NF SUB: subtract without updating EFLAGS.
 */
static void test_nf_sub(void)
{
	u64 result;
	u64 flags_before, flags_after;

	sigill_received = false;
	setup_sigill_handler();

	if (sigsetjmp(jmpbuf, 1) == 0) {
		asm volatile("xor %%eax, %%eax\n\t"
			"pushfq\n\t"
			"pop %1\n\t"
			"mov $500, %%rax\n\t"
			"mov $200, %%rbx\n\t"
			".byte 0x62, 0xf4, 0xfc, 0x0c, 0x29, 0xd8\n\t"  /* NF SUB */
			"pushfq\n\t"
			"pop %2\n\t"
			"mov %%rax, %0\n\t"
			: "=r"(result), "=r"(flags_before), "=r"(flags_after)
			:
			: "rax", "rbx", "memory"
		);
	}

	if (sigill_received)
		ksft_test_result_fail("NF SUB raised #UD\n");
	else if (result == 300 && flags_before == flags_after)
		ksft_test_result_pass("NF SUB: result=%llu, flags unchanged\n",
				      (unsigned long long)result);
	else
		ksft_test_result_fail("NF SUB: result=%llu, flags mismatch\n",
				      (unsigned long long)result);
}

/*
 * NF INC: increment without flag updates.
 */
static void test_nf_inc(void)
{
	u64 result;
	u64 flags_before, flags_after;

	sigill_received = false;
	setup_sigill_handler();

	if (sigsetjmp(jmpbuf, 1) == 0) {
		asm volatile("xor %%eax, %%eax\n\t"
			"pushfq\n\t"
			"pop %1\n\t"
			"mov $99, %%rax\n\t"
			".byte 0x62, 0xf4, 0xfc, 0x0c, 0xff, 0xc0\n\t"  /* NF INC rax */
			"pushfq\n\t"
			"pop %2\n\t"
			"mov %%rax, %0\n\t"
			: "=r"(result), "=r"(flags_before), "=r"(flags_after)
			:
			: "rax", "memory"
		);
	}

	if (sigill_received)
		ksft_test_result_fail("NF INC raised #UD\n");
	else if (result == 100 && flags_before == flags_after)
		ksft_test_result_pass("NF INC: result=%llu, flags unchanged\n",
				      (unsigned long long)result);
	else
		ksft_test_result_fail("NF INC: result=%llu (exp 100), flags changed\n",
				      (unsigned long long)result);
}

/*
 * NF DEC: decrement without flag updates.
 */
static void test_nf_dec(void)
{
	u64 result;
	u64 flags_before, flags_after;

	sigill_received = false;
	setup_sigill_handler();

	if (sigsetjmp(jmpbuf, 1) == 0) {
		asm volatile("xor %%eax, %%eax\n\t"
			"pushfq\n\t"
			"pop %1\n\t"
			"mov $100, %%rax\n\t"
			".byte 0x62, 0xf4, 0xfc, 0x0c, 0xff, 0xc8\n\t"  /* NF DEC rax */
			"pushfq\n\t"
			"pop %2\n\t"
			"mov %%rax, %0\n\t"
			: "=r"(result), "=r"(flags_before), "=r"(flags_after)
			:
			: "rax", "memory"
		);
	}

	if (sigill_received)
		ksft_test_result_fail("NF DEC raised #UD\n");
	else if (result == 99 && flags_before == flags_after)
		ksft_test_result_pass("NF DEC: result=%llu, flags unchanged\n",
				      (unsigned long long)result);
	else
		ksft_test_result_fail("NF DEC: result=%llu (exp 99), flags changed\n",
				      (unsigned long long)result);
}

/*
 * CFCMOV: Conditional move (flag-based) with support for memory destinations.
 * Test CFCMOVNE (conditional move if not equal/not zero).
 */
static void test_cfcmov(void)
{
	u64 dst = 0;
	u64 src = 0xCAFEBABE;

	sigill_received = false;
	setup_sigill_handler();

	if (sigsetjmp(jmpbuf, 1) == 0) {
		/* Set ZF=0 (condition NE is true) */
		asm volatile("mov $1, %%ecx\n\t"
			"test %%ecx, %%ecx\n\t"      /* ZF=0 since ecx!=0 */
			/* CFCMOVNE: if ZF=0, dst = src */
			".byte 0x62, 0xf4, 0xfc, 0x08, 0x45, 0xc3\n\t"
			"mov %%rax, %0\n\t"
			: "=r"(dst)
			: "a"(0), "b"(src)
			: "rcx", "cc"
		);
	}

	if (sigill_received)
		ksft_test_result_fail("CFCMOV raised #UD\n");
	else if (dst == src)
		ksft_test_result_pass("CFCMOV NE: moved 0x%llx when ZF=0\n",
				      (unsigned long long)dst);
	else
		ksft_test_result_fail("CFCMOV NE: expected 0x%llx, got 0x%llx\n",
				      (unsigned long long)src, (unsigned long long)dst);
}

/*
 * PUSH2/POP2: Push/pop a pair of registers in one instruction.
 * PUSH2 r1, r2 pushes both registers; POP2 r1, r2 restores them.
 */
static void test_push2_pop2(void)
{
	u64 val1 = 0x1111111111111111ULL;
	u64 val2 = 0x2222222222222222ULL;
	u64 out1 = 0, out2 = 0;

	sigill_received = false;
	setup_sigill_handler();

	if (sigsetjmp(jmpbuf, 1) == 0) {
		asm volatile("mov %2, %%r16\n\t"
			"mov %3, %%r17\n\t"
			"push2 %%r16, %%r17\n\t"
			/* Clobber registers */
			"xor %%r16d, %%r16d\n\t"
			"xor %%r17d, %%r17d\n\t"
			/* pop2 with reversed operand order restores correctly */
			"pop2 %%r17, %%r16\n\t"
			"mov %%r16, %0\n\t"
			"mov %%r17, %1\n\t"
			: "=r"(out1), "=r"(out2)
			: "r"(val1), "r"(val2)
			: "r16", "r17", "memory"
		);
	}

	if (sigill_received) {
		ksft_test_result_fail("PUSH2/POP2 raised #UD\n");
	} else if (out1 == val1 && out2 == val2) {
		ksft_test_result_pass("PUSH2/POP2: r16=0x%llx, r17=0x%llx correctly restored\n",
				      (unsigned long long)out1, (unsigned long long)out2);
	} else {
		ksft_test_result_fail("PUSH2/POP2: expected (0x%llx,0x%llx), got (0x%llx,0x%llx)\n",
				      (unsigned long long)val1, (unsigned long long)val2,
				      (unsigned long long)out1, (unsigned long long)out2);
	}
}

static void usage(const char *prog)
{
	fprintf(stderr, "Usage: %s -t <test>\n", prog);
	fprintf(stderr, "Tests:\n");
	fprintf(stderr, "  ndd_add    - NDD ADD (non-destructive destination)\n");
	fprintf(stderr, "  ndd_sub    - NDD SUB\n");
	fprintf(stderr, "  ndd_and    - NDD AND\n");
	fprintf(stderr, "  ndd_or     - NDD OR\n");
	fprintf(stderr, "  ndd_xor    - NDD XOR\n");
	fprintf(stderr, "  ndd_shl    - NDD SHL\n");
	fprintf(stderr, "  ndd_shr    - NDD SHR\n");
	fprintf(stderr, "  nf_add     - NF ADD (no flags update)\n");
	fprintf(stderr, "  nf_sub     - NF SUB\n");
	fprintf(stderr, "  nf_inc     - NF INC\n");
	fprintf(stderr, "  nf_dec     - NF DEC\n");
	fprintf(stderr, "  cfcmov     - CFCMOV (conditional move)\n");
	fprintf(stderr, "  push2_pop2 - PUSH2/POP2 register pairs\n");
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

	if (strcmp(test_name, "ndd_add") == 0)
		test_ndd_add();
	else if (strcmp(test_name, "ndd_sub") == 0)
		test_ndd_sub();
	else if (strcmp(test_name, "ndd_and") == 0)
		test_ndd_and();
	else if (strcmp(test_name, "ndd_or") == 0)
		test_ndd_or();
	else if (strcmp(test_name, "ndd_xor") == 0)
		test_ndd_xor();
	else if (strcmp(test_name, "ndd_shl") == 0)
		test_ndd_shl();
	else if (strcmp(test_name, "ndd_shr") == 0)
		test_ndd_shr();
	else if (strcmp(test_name, "nf_add") == 0)
		test_nf_add();
	else if (strcmp(test_name, "nf_sub") == 0)
		test_nf_sub();
	else if (strcmp(test_name, "nf_inc") == 0)
		test_nf_inc();
	else if (strcmp(test_name, "nf_dec") == 0)
		test_nf_dec();
	else if (strcmp(test_name, "cfcmov") == 0)
		test_cfcmov();
	else if (strcmp(test_name, "push2_pop2") == 0)
		test_push2_pop2();
	else
		ksft_exit_fail_msg("Unknown test: %s\n", test_name);

	ksft_finished();
	return 0;
}
