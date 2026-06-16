// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2024 Intel Corporation.

/*
 * apx_xstate.c - Test APX EGPR XSAVE state (component 19) handling.
 *
 * Tests that the kernel correctly saves and restores APX Extended General
 * Purpose Registers (R16-R31) across:
 *   1. Signal delivery and return
 *   2. Fork (child inherits parent's EGPR state)
 *   3. Context switches (sched_yield)
 *
 * Also validates XSAVE area layout:
 *   - State component 19 offset matches CPUID.(EAX=0Dh, ECX=13h).EBX
 *   - State component 19 size = 128 bytes (16 x 8B) per CPUID.(EAX=0Dh, ECX=13h).EAX
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

#include "apx_xstate_helpers.h"
#include "../common/kselftest.h"

#define XSTATE_TESTBYTE		0xA5
#define CPUID_LEAF_XSTATE	0xD

static u32 apx_xstate_offset;
static u32 apx_xstate_size;
static u32 total_xstate_size;

static void check_apx_cpuid(void)
{
	u32 eax, ebx, ecx, edx;

	/* Check APX feature: CPUID.(EAX=7, ECX=1):EDX[21] */
	__cpuid_count(7, 1, eax, ebx, ecx, edx);
	if (!(edx & (1U << 21)))
		ksft_exit_skip("CPU doesn't support APX (CPUID.7.1:EDX[21]).\n");

	/* Check XSAVE support */
	__cpuid_count(1, 0, eax, ebx, ecx, edx);
	if (!(ecx & (1U << 26)))
		ksft_exit_skip("CPU doesn't support XSAVE.\n");
	if (!(ecx & (1U << 27)))
		ksft_exit_skip("OS hasn't enabled XSAVE (OSXSAVE=0).\n");

	/* Query APX XSAVE area: CPUID.(EAX=0Dh, ECX=19) */
	__cpuid_count(CPUID_LEAF_XSTATE, XFEATURE_APX, eax, ebx, ecx, edx);
	apx_xstate_size = eax;
	apx_xstate_offset = ebx;

	if (apx_xstate_size == 0)
		ksft_exit_skip("APX XSAVE area size is 0 (not enabled by OS).\n");

	/* Get total XSAVE area size: CPUID.(EAX=0Dh, ECX=0).EBX */
	__cpuid_count(CPUID_LEAF_XSTATE, 0, eax, ebx, ecx, edx);
	total_xstate_size = ebx;

	ksft_print_msg("[INFO] APX XSAVE: offset=%u, size=%u, total=%u\n",
		       apx_xstate_offset, apx_xstate_size, total_xstate_size);
}

static void *alloc_xbuf(u32 size)
{
	void *buf = aligned_alloc(XSAVE_ALIGNMENT, size);

	if (!buf)
		ksft_exit_fail_msg("aligned_alloc(%u) failed.\n", size);
	memset(buf, 0, size);
	return buf;
}

/*
 * Fill the APX EGPR area in the XSAVE buffer with a known pattern.
 */
static void fill_apx_xbuf(void *xbuf, u8 test_byte)
{
	struct apx_state *apx;
	u64 *header_xfeatures;
	u64 pattern;
	int i;

	/* Set XSTATE_BV bit for APX */
	header_xfeatures = (u64 *)((char *)xbuf + XSAVE_HDR_OFFSET);
	*header_xfeatures |= XFEATURE_MASK_APX;

	/* Fill EGPR values at the APX offset */
	apx = (struct apx_state *)((char *)xbuf + apx_xstate_offset);
	pattern = (u64)test_byte | ((u64)test_byte << 8) |
		  ((u64)test_byte << 16) | ((u64)test_byte << 24) |
		  ((u64)test_byte << 32) | ((u64)test_byte << 40) |
		  ((u64)test_byte << 48) | ((u64)test_byte << 56);

	for (i = 0; i < APX_NUM_REGS; i++)
		apx->egpr[i] = pattern + i;
}

/*
 * Compare APX state in two XSAVE buffers.
 */
static bool compare_apx_state(void *buf1, void *buf2)
{
	struct apx_state *apx1 = (struct apx_state *)((char *)buf1 + apx_xstate_offset);
	struct apx_state *apx2 = (struct apx_state *)((char *)buf2 + apx_xstate_offset);
	int i;

	for (i = 0; i < APX_NUM_REGS; i++) {
		if (apx1->egpr[i] != apx2->egpr[i]) {
			ksft_print_msg("[FAIL] R%d mismatch: expected 0x%llx, got 0x%llx\n",
				       i + 16, (unsigned long long)apx1->egpr[i],
				       (unsigned long long)apx2->egpr[i]);
			return false;
		}
	}
	return true;
}

static void test_xstate_size(void)
{
	/*
	 * APX state component 19 must be exactly 128 bytes (16 x 8B registers).
	 */
	if (apx_xstate_size == APX_STATE_SIZE)
		ksft_test_result_pass("APX XSAVE size = %u bytes (16 x 8B EGPRs)\n",
				      apx_xstate_size);
	else
		ksft_test_result_fail("APX XSAVE size = %u, expected %u\n",
				      apx_xstate_size, APX_STATE_SIZE);
}

static void test_xstate_offset(void)
{
	/*
	 * APX state offset must be non-zero and properly aligned.
	 * The offset is reported by CPUID and must be 64-byte aligned.
	 */
	if (apx_xstate_offset > 0 && (apx_xstate_offset % 64 == 0))
		ksft_test_result_pass("APX XSAVE offset = %u (64B-aligned)\n",
				      apx_xstate_offset);
	else
		ksft_test_result_fail("APX XSAVE offset = %u (expected non-zero, 64B-aligned)\n",
				      apx_xstate_offset);
}

static void test_signal(void)
{
	void *valid_xbuf, *compared_xbuf;
	bool sig_done;

	valid_xbuf = alloc_xbuf(total_xstate_size);
	compared_xbuf = alloc_xbuf(total_xstate_size);

	fill_apx_xbuf(valid_xbuf, XSTATE_TESTBYTE);

	sig_done = apx_signal_test(valid_xbuf, compared_xbuf,
				   XFEATURE_MASK_APX, total_xstate_size);

	if (!sig_done)
		ksft_test_result_fail("Signal was not delivered\n");
	else if (compare_apx_state(valid_xbuf, compared_xbuf))
		ksft_test_result_pass("EGPR state preserved across signal\n");
	else
		ksft_test_result_fail("EGPR state corrupted after signal handling\n");

	free(valid_xbuf);
	free(compared_xbuf);
}

static void test_fork(void)
{
	void *valid_xbuf, *compared_xbuf;
	bool result;

	valid_xbuf = alloc_xbuf(total_xstate_size);
	compared_xbuf = alloc_xbuf(total_xstate_size);

	fill_apx_xbuf(valid_xbuf, XSTATE_TESTBYTE);

	result = apx_fork_test(valid_xbuf, compared_xbuf,
			       XFEATURE_MASK_APX, total_xstate_size);

	if (result)
		ksft_test_result_pass("EGPR state preserved across fork\n");
	else
		ksft_test_result_fail("EGPR state corrupted after fork\n");

	free(valid_xbuf);
	free(compared_xbuf);
}

static void test_context_switch(void)
{
	void *valid_xbuf, *compared_xbuf;
	bool result;

	valid_xbuf = alloc_xbuf(total_xstate_size);
	compared_xbuf = alloc_xbuf(total_xstate_size);

	fill_apx_xbuf(valid_xbuf, XSTATE_TESTBYTE);

	result = apx_context_switch_test(valid_xbuf, compared_xbuf,
					 XFEATURE_MASK_APX, total_xstate_size);

	if (result)
		ksft_test_result_pass("EGPR state preserved across context switch\n");
	else
		ksft_test_result_fail("EGPR state corrupted after context switch\n");

	free(valid_xbuf);
	free(compared_xbuf);
}

static void usage(const char *prog)
{
	fprintf(stderr, "Usage: %s -t <test>\n", prog);
	fprintf(stderr, "Tests:\n");
	fprintf(stderr, "  xstate_size      - Validate APX XSAVE area size\n");
	fprintf(stderr, "  xstate_offset    - Validate APX XSAVE area offset\n");
	fprintf(stderr, "  signal           - EGPR preservation across signal\n");
	fprintf(stderr, "  fork             - EGPR preservation across fork\n");
	fprintf(stderr, "  context_switch   - EGPR preservation across context switch\n");
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

	check_apx_cpuid();

	if (strcmp(test_name, "xstate_size") == 0)
		test_xstate_size();
	else if (strcmp(test_name, "xstate_offset") == 0)
		test_xstate_offset();
	else if (strcmp(test_name, "signal") == 0)
		test_signal();
	else if (strcmp(test_name, "fork") == 0)
		test_fork();
	else if (strcmp(test_name, "context_switch") == 0)
		test_context_switch();
	else
		ksft_exit_fail_msg("Unknown test: %s\n", test_name);

	ksft_finished();
	return 0;
}
