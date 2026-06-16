// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2024 Intel Corporation.

/*
 * apx_ptrace.c - Test ptrace EGPR state injection and retrieval.
 *
 * Validates the kernel's ptrace ABI for APX EGPR (XFEATURE 19):
 *   1. ptrace_get     - PTRACE_GETREGSET reads EGPR state from a stopped child
 *   2. ptrace_inject  - PTRACE_SETREGSET injects EGPR state, then reads back
 *   3. ptrace_modify  - Modify individual EGPRs via ptrace and verify
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdbool.h>
#include <signal.h>
#include <getopt.h>
#include <cpuid.h>
#include <elf.h>
#include <sys/ptrace.h>
#include <sys/uio.h>
#include <sys/wait.h>

#include "apx_xstate_helpers.h"
#include "../common/kselftest.h"

#define CPUID_LEAF_XSTATE	0xD
#define XSTATE_TESTBYTE		0xB7

static u32 apx_xstate_offset;
static u32 apx_xstate_size;
static u32 total_xstate_size;

static void check_apx_cpuid(void)
{
	u32 eax, ebx, ecx, edx;

	__cpuid_count(7, 1, eax, ebx, ecx, edx);
	if (!(edx & (1U << 21)))
		ksft_exit_skip("CPU doesn't support APX (CPUID.7.1:EDX[21]).\n");

	__cpuid_count(1, 0, eax, ebx, ecx, edx);
	if (!(ecx & (1U << 26)))
		ksft_exit_skip("CPU doesn't support XSAVE.\n");
	if (!(ecx & (1U << 27)))
		ksft_exit_skip("OS hasn't enabled XSAVE (OSXSAVE=0).\n");

	__cpuid_count(CPUID_LEAF_XSTATE, XFEATURE_APX, eax, ebx, ecx, edx);
	apx_xstate_size = eax;
	apx_xstate_offset = ebx;

	if (apx_xstate_size == 0)
		ksft_exit_skip("APX XSAVE area size is 0 (not enabled by OS).\n");

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

static void fill_apx_xbuf(void *xbuf, u8 test_byte)
{
	struct apx_state *apx;
	u64 *header_xfeatures;
	u64 pattern;
	int i;

	header_xfeatures = (u64 *)((char *)xbuf + XSAVE_HDR_OFFSET);
	*header_xfeatures |= XFEATURE_MASK_APX;

	apx = (struct apx_state *)((char *)xbuf + apx_xstate_offset);
	pattern = (u64)test_byte | ((u64)test_byte << 8) |
		  ((u64)test_byte << 16) | ((u64)test_byte << 24) |
		  ((u64)test_byte << 32) | ((u64)test_byte << 40) |
		  ((u64)test_byte << 48) | ((u64)test_byte << 56);

	for (i = 0; i < APX_NUM_REGS; i++)
		apx->egpr[i] = pattern + i;
}

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

/*
 * Child process for ptrace tests: mark as tracee, touch xstate to ensure
 * the kernel allocates the extended buffer, then stop.
 */
static void ptracee_child(void)
{
	void *xbuf;

	if (ptrace(PTRACE_TRACEME, 0, NULL, NULL)) {
		perror("PTRACE_TRACEME");
		_exit(1);
	}

	/* Touch APX state to ensure kernel allocates extended FPU buffer */
	xbuf = alloc_xbuf(total_xstate_size);
	fill_apx_xbuf(xbuf, 0x11);
	xrstor_apx(xbuf, XFEATURE_MASK_APX);
	/* Clear state back to init */
	memset(xbuf, 0, total_xstate_size);
	xrstor_apx(xbuf, XFEATURE_MASK_APX);
	free(xbuf);

	raise(SIGTRAP);
	_exit(0);
}

static pid_t start_ptracee(void)
{
	pid_t child;
	int status;

	child = fork();
	if (child < 0)
		ksft_exit_fail_msg("fork() failed\n");

	if (child == 0)
		ptracee_child();

	/* Wait for SIGTRAP */
	do {
		waitpid(child, &status, 0);
	} while (!WIFSTOPPED(status) || WSTOPSIG(status) != SIGTRAP);

	return child;
}

static void stop_ptracee(pid_t child)
{
	int status;

	ptrace(PTRACE_DETACH, child, NULL, NULL);
	waitpid(child, &status, 0);
	if (!WIFEXITED(status) || WEXITSTATUS(status))
		ksft_print_msg("[WARN] ptracee exited with error\n");
}

/*
 * Test 1: PTRACE_GETREGSET reads APX EGPR state from stopped child.
 */
static void test_ptrace_get(void)
{
	void *xbuf;
	struct iovec iov;
	struct apx_state *apx;
	pid_t child;

	xbuf = alloc_xbuf(total_xstate_size);

	child = start_ptracee();

	iov.iov_base = xbuf;
	iov.iov_len = total_xstate_size;

	if (ptrace(PTRACE_GETREGSET, child, (unsigned int)NT_X86_XSTATE, &iov)) {
		ksft_test_result_fail("PTRACE_GETREGSET failed: %m\n");
		stop_ptracee(child);
		free(xbuf);
		return;
	}

	/* Verify we got a valid buffer (iov_len updated to actual size) */
	apx = (struct apx_state *)((char *)xbuf + apx_xstate_offset);
	ksft_print_msg("[INFO] GETREGSET returned %zu bytes, APX R16=0x%llx\n",
		       iov.iov_len, (unsigned long long)apx->egpr[0]);

	if (iov.iov_len >= apx_xstate_offset + apx_xstate_size)
		ksft_test_result_pass("PTRACE_GETREGSET: read EGPR state (%zu bytes)\n",
				      iov.iov_len);
	else
		ksft_test_result_fail("PTRACE_GETREGSET: buffer too small (%zu < %u)\n",
				      iov.iov_len, apx_xstate_offset + apx_xstate_size);

	stop_ptracee(child);
	free(xbuf);
}

/*
 * Test 2: PTRACE_SETREGSET injects EGPR state, then GETREGSET reads it back.
 * Verifies the kernel correctly writes and re-reads the APX xstate.
 */
static void test_ptrace_inject(void)
{
	void *xbuf_set, *xbuf_get;
	struct iovec iov;
	pid_t child;

	xbuf_set = alloc_xbuf(total_xstate_size);
	xbuf_get = alloc_xbuf(total_xstate_size);

	child = start_ptracee();

	/* First read existing state to get a valid base buffer */
	iov.iov_base = xbuf_set;
	iov.iov_len = total_xstate_size;

	if (ptrace(PTRACE_GETREGSET, child, (unsigned int)NT_X86_XSTATE, &iov)) {
		ksft_test_result_fail("PTRACE_GETREGSET (pre-inject) failed: %m\n");
		stop_ptracee(child);
		goto out;
	}

	/* Fill APX area with known test pattern */
	fill_apx_xbuf(xbuf_set, XSTATE_TESTBYTE);

	/* Inject the modified state */
	iov.iov_base = xbuf_set;
	iov.iov_len = total_xstate_size;

	if (ptrace(PTRACE_SETREGSET, child, (unsigned int)NT_X86_XSTATE, &iov)) {
		ksft_test_result_fail("PTRACE_SETREGSET failed: %m\n");
		stop_ptracee(child);
		goto out;
	}

	/* Read back and compare */
	iov.iov_base = xbuf_get;
	iov.iov_len = total_xstate_size;

	if (ptrace(PTRACE_GETREGSET, child, (unsigned int)NT_X86_XSTATE, &iov)) {
		ksft_test_result_fail("PTRACE_GETREGSET (post-inject) failed: %m\n");
		stop_ptracee(child);
		goto out;
	}

	if (compare_apx_state(xbuf_set, xbuf_get))
		ksft_test_result_pass("PTRACE inject+readback: EGPR state matches\n");
	else
		ksft_test_result_fail("PTRACE inject+readback: EGPR state mismatch\n");

	stop_ptracee(child);
out:
	free(xbuf_set);
	free(xbuf_get);
}

/*
 * Test 3: Modify individual EGPR values via ptrace and verify.
 * Sets each R16-R31 to a unique value, injects, reads back.
 */
static void test_ptrace_modify(void)
{
	void *xbuf_set, *xbuf_get;
	struct iovec iov;
	struct apx_state *apx;
	pid_t child;
	bool pass = true;
	int i;

	xbuf_set = alloc_xbuf(total_xstate_size);
	xbuf_get = alloc_xbuf(total_xstate_size);

	child = start_ptracee();

	/* Read current state */
	iov.iov_base = xbuf_set;
	iov.iov_len = total_xstate_size;

	if (ptrace(PTRACE_GETREGSET, child, (unsigned int)NT_X86_XSTATE, &iov)) {
		ksft_test_result_fail("PTRACE_GETREGSET failed: %m\n");
		stop_ptracee(child);
		goto out;
	}

	/* Set each EGPR to a distinct value */
	apx = (struct apx_state *)((char *)xbuf_set + apx_xstate_offset);
	for (i = 0; i < APX_NUM_REGS; i++)
		apx->egpr[i] = 0xDEAD000000000000ULL | ((u64)(i + 16) << 32) | i;

	/* Set XSTATE_BV to include APX */
	u64 *header = (u64 *)((char *)xbuf_set + XSAVE_HDR_OFFSET);
	*header |= XFEATURE_MASK_APX;

	iov.iov_base = xbuf_set;
	iov.iov_len = total_xstate_size;

	if (ptrace(PTRACE_SETREGSET, child, (unsigned int)NT_X86_XSTATE, &iov)) {
		ksft_test_result_fail("PTRACE_SETREGSET failed: %m\n");
		stop_ptracee(child);
		goto out;
	}

	/* Read back */
	iov.iov_base = xbuf_get;
	iov.iov_len = total_xstate_size;

	if (ptrace(PTRACE_GETREGSET, child, (unsigned int)NT_X86_XSTATE, &iov)) {
		ksft_test_result_fail("PTRACE_GETREGSET failed: %m\n");
		stop_ptracee(child);
		goto out;
	}

	/* Verify each register */
	struct apx_state *apx_got = (struct apx_state *)((char *)xbuf_get + apx_xstate_offset);

	for (i = 0; i < APX_NUM_REGS; i++) {
		u64 expected = 0xDEAD000000000000ULL | ((u64)(i + 16) << 32) | i;

		if (apx_got->egpr[i] != expected) {
			ksft_print_msg("[FAIL] R%d: expected 0x%llx, got 0x%llx\n",
				       i + 16, (unsigned long long)expected,
				       (unsigned long long)apx_got->egpr[i]);
			pass = false;
		}
	}

	if (pass)
		ksft_test_result_pass("PTRACE modify: all 16 EGPRs individually verified\n");
	else
		ksft_test_result_fail("PTRACE modify: EGPR value mismatch\n");

	stop_ptracee(child);
out:
	free(xbuf_set);
	free(xbuf_get);
}

static void usage(const char *prog)
{
	fprintf(stderr, "Usage: %s -t <test>\n", prog);
	fprintf(stderr, "Tests:\n");
	fprintf(stderr, "  ptrace_get     - Read EGPR via PTRACE_GETREGSET\n");
	fprintf(stderr, "  ptrace_inject  - Inject and readback EGPR via ptrace\n");
	fprintf(stderr, "  ptrace_modify  - Modify individual EGPRs via ptrace\n");
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

	if (strcmp(test_name, "ptrace_get") == 0)
		test_ptrace_get();
	else if (strcmp(test_name, "ptrace_inject") == 0)
		test_ptrace_inject();
	else if (strcmp(test_name, "ptrace_modify") == 0)
		test_ptrace_modify();
	else
		ksft_exit_fail_msg("Unknown test: %s\n", test_name);

	ksft_finished();
	return 0;
}
