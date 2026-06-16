// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2024 Intel Corporation.

/*
 * apx_sigcontext.c - Test signal frame ABI for APX EGPR state.
 *
 * Validates the kernel's signal delivery ABI for APX state:
 *   1. sigctx_magic     - FP_XSTATE_MAGIC1 and MAGIC2 present in sigframe
 *   2. sigctx_xfeatures - xfeatures in fpx_sw_bytes includes APX bit
 *   3. sigctx_xstatebv  - XSTATE_BV in XSAVE header includes APX bit
 *   4. sigctx_delivery  - EGPR data delivered correctly in signal frame
 *   5. sigctx_restore   - Modified EGPR in sighandler restored after sigreturn
 *
 * See ABI format: arch/x86/include/uapi/asm/sigcontext.h
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdbool.h>
#include <signal.h>
#include <ucontext.h>
#include <getopt.h>
#include <cpuid.h>

#include "apx_xstate_helpers.h"
#include "../common/kselftest.h"

#define CPUID_LEAF_XSTATE	0xD
#define XSTATE_TESTBYTE		0xC3

/* Signal frame magic values from arch/x86/include/uapi/asm/sigcontext.h */
#define FP_XSTATE_MAGIC1	0x46505853U	/* FPXS */
#define FP_XSTATE_MAGIC2	0x46505845U	/* FPXE */

/* fpx_sw_bytes offset within the legacy FXSAVE region (bytes 464-511) */
#define SW_BYTES_OFFSET		464
#define SW_BYTES_BV_OFFSET	(SW_BYTES_OFFSET + 8)

/* fpx_sw_bytes structure (from sigcontext.h) */
struct fpx_sw_bytes {
	u32 magic1;
	u32 extended_size;
	u64 xfeatures;
	u32 xstate_size;
	u32 padding[7];
};

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

/*
 * Signal handler results — avoid printf in signal handler (not async-signal-safe).
 * Use a result structure instead.
 */
static struct {
	bool magic1_valid;
	bool magic2_valid;
	bool xfeatures_valid;
	bool xstatebv_valid;
	bool delivery_valid;
	bool handler_ran;
	u32 magic1_val;
	u32 magic2_val;
	u64 sw_xfeatures;
	u64 hdr_xstatebv;
} sig_result;

/* Stashed buffer for comparison in signal handler */
static void *stashed_xbuf;

static void sigcontext_handler(int sig, siginfo_t *si, void *ctx_void)
{
	ucontext_t *ctx = (ucontext_t *)ctx_void;
	void *fpregs = (void *)ctx->uc_mcontext.fpregs;
	struct fpx_sw_bytes *sw_bytes;
	struct apx_state *apx_sig, *apx_stash;
	u32 magic2;
	bool match;
	int i;

	sig_result.handler_ran = true;

	if (!fpregs)
		return;

	/* Check magic1 in fpx_sw_bytes */
	sw_bytes = (struct fpx_sw_bytes *)((char *)fpregs + SW_BYTES_OFFSET);
	sig_result.magic1_val = sw_bytes->magic1;
	sig_result.magic1_valid = (sw_bytes->magic1 == FP_XSTATE_MAGIC1);

	/* Check xfeatures in fpx_sw_bytes */
	sig_result.sw_xfeatures = sw_bytes->xfeatures;
	sig_result.xfeatures_valid = (sw_bytes->xfeatures & XFEATURE_MASK_APX) != 0;

	/* Check XSTATE_BV in XSAVE header */
	u64 *xstatebv = (u64 *)((char *)fpregs + XSAVE_HDR_OFFSET);

	sig_result.hdr_xstatebv = *xstatebv;
	sig_result.xstatebv_valid = (*xstatebv & XFEATURE_MASK_APX) != 0;

	/* Check magic2 at the end of xstate area */
	magic2 = *(u32 *)((char *)fpregs + sw_bytes->xstate_size);
	sig_result.magic2_val = magic2;
	sig_result.magic2_valid = (magic2 == FP_XSTATE_MAGIC2);

	/* Compare APX state in signal frame vs stashed */
	apx_sig = (struct apx_state *)((char *)fpregs + apx_xstate_offset);
	apx_stash = (struct apx_state *)((char *)stashed_xbuf + apx_xstate_offset);
	match = true;
	for (i = 0; i < APX_NUM_REGS; i++) {
		if (apx_sig->egpr[i] != apx_stash->egpr[i]) {
			match = false;
			break;
		}
	}
	sig_result.delivery_valid = match;
}

/*
 * Modified signal handler: changes EGPRs in the signal frame, verifies
 * they take effect after sigreturn.
 */
static void *restore_stashed_xbuf;

static void sigcontext_modify_handler(int sig, siginfo_t *si, void *ctx_void)
{
	ucontext_t *ctx = (ucontext_t *)ctx_void;
	void *fpregs = (void *)ctx->uc_mcontext.fpregs;
	struct apx_state *apx_sig;
	int i;

	sig_result.handler_ran = true;

	if (!fpregs)
		return;

	/* Modify EGPR values in the signal frame */
	apx_sig = (struct apx_state *)((char *)fpregs + apx_xstate_offset);
	for (i = 0; i < APX_NUM_REGS; i++)
		apx_sig->egpr[i] = 0xBEEF000000000000ULL + i;

	/* Record expected values for post-sigreturn comparison */
	struct apx_state *apx_restore =
		(struct apx_state *)((char *)restore_stashed_xbuf + apx_xstate_offset);
	for (i = 0; i < APX_NUM_REGS; i++)
		apx_restore->egpr[i] = 0xBEEF000000000000ULL + i;
}

static void sethandler(int sig, void (*handler)(int, siginfo_t *, void *))
{
	struct sigaction sa;

	memset(&sa, 0, sizeof(sa));
	sa.sa_sigaction = handler;
	sa.sa_flags = SA_SIGINFO;
	sigemptyset(&sa.sa_mask);
	if (sigaction(sig, &sa, 0))
		ksft_exit_fail_msg("sigaction failed: %m\n");
}

static void clearhandler(int sig)
{
	struct sigaction sa;

	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = SIG_DFL;
	sigemptyset(&sa.sa_mask);
	sigaction(sig, &sa, 0);
}

/*
 * Test: Validate FP_XSTATE_MAGIC1 and MAGIC2 in signal frame.
 */
static void test_sigctx_magic(void)
{
	memset(&sig_result, 0, sizeof(sig_result));

	stashed_xbuf = alloc_xbuf(total_xstate_size);
	fill_apx_xbuf(stashed_xbuf, XSTATE_TESTBYTE);

	sethandler(SIGUSR1, sigcontext_handler);

	xrstor_apx(stashed_xbuf, XFEATURE_MASK_APX);
	raise(SIGUSR1);

	clearhandler(SIGUSR1);

	if (!sig_result.handler_ran) {
		ksft_test_result_fail("Signal handler did not run\n");
	} else if (sig_result.magic1_valid && sig_result.magic2_valid) {
		ksft_test_result_pass("sigcontext: MAGIC1=0x%x MAGIC2=0x%x valid\n",
				      sig_result.magic1_val, sig_result.magic2_val);
	} else {
		ksft_test_result_fail("sigcontext: MAGIC1=0x%x(%s) MAGIC2=0x%x(%s)\n",
				      sig_result.magic1_val,
				      sig_result.magic1_valid ? "ok" : "BAD",
				      sig_result.magic2_val,
				      sig_result.magic2_valid ? "ok" : "BAD");
	}

	free(stashed_xbuf);
}

/*
 * Test: xfeatures in fpx_sw_bytes includes APX bit.
 */
static void test_sigctx_xfeatures(void)
{
	memset(&sig_result, 0, sizeof(sig_result));

	stashed_xbuf = alloc_xbuf(total_xstate_size);
	fill_apx_xbuf(stashed_xbuf, XSTATE_TESTBYTE);

	sethandler(SIGUSR1, sigcontext_handler);

	xrstor_apx(stashed_xbuf, XFEATURE_MASK_APX);
	raise(SIGUSR1);

	clearhandler(SIGUSR1);

	if (!sig_result.handler_ran) {
		ksft_test_result_fail("Signal handler did not run\n");
	} else if (sig_result.xfeatures_valid) {
		ksft_test_result_pass("sigcontext: fpx_sw_bytes.xfeatures=0x%llx includes APX\n",
				      (unsigned long long)sig_result.sw_xfeatures);
	} else {
		ksft_test_result_fail("sigcontext: fpx_sw_bytes.xfeatures=0x%llx missing APX bit\n",
				      (unsigned long long)sig_result.sw_xfeatures);
	}

	free(stashed_xbuf);
}

/*
 * Test: XSTATE_BV in XSAVE header includes APX bit.
 */
static void test_sigctx_xstatebv(void)
{
	memset(&sig_result, 0, sizeof(sig_result));

	stashed_xbuf = alloc_xbuf(total_xstate_size);
	fill_apx_xbuf(stashed_xbuf, XSTATE_TESTBYTE);

	sethandler(SIGUSR1, sigcontext_handler);

	xrstor_apx(stashed_xbuf, XFEATURE_MASK_APX);
	raise(SIGUSR1);

	clearhandler(SIGUSR1);

	if (!sig_result.handler_ran) {
		ksft_test_result_fail("Signal handler did not run\n");
	} else if (sig_result.xstatebv_valid) {
		ksft_test_result_pass("sigcontext: XSTATE_BV=0x%llx includes APX\n",
				      (unsigned long long)sig_result.hdr_xstatebv);
	} else {
		ksft_test_result_fail("sigcontext: XSTATE_BV=0x%llx missing APX bit\n",
				      (unsigned long long)sig_result.hdr_xstatebv);
	}

	free(stashed_xbuf);
}

/*
 * Test: EGPR data correctly delivered in signal frame.
 */
static void test_sigctx_delivery(void)
{
	memset(&sig_result, 0, sizeof(sig_result));

	stashed_xbuf = alloc_xbuf(total_xstate_size);
	fill_apx_xbuf(stashed_xbuf, XSTATE_TESTBYTE);

	sethandler(SIGUSR1, sigcontext_handler);

	xrstor_apx(stashed_xbuf, XFEATURE_MASK_APX);
	raise(SIGUSR1);

	clearhandler(SIGUSR1);

	if (!sig_result.handler_ran)
		ksft_test_result_fail("Signal handler did not run\n");
	else if (sig_result.delivery_valid)
		ksft_test_result_pass("sigcontext: EGPR data correctly delivered\n");
	else
		ksft_test_result_fail("sigcontext: EGPR data mismatch in signal frame\n");

	free(stashed_xbuf);
}

/*
 * Test: Modify EGPRs in signal handler, verify change persists after sigreturn.
 */
static void test_sigctx_restore(void)
{
	void *post_xbuf;
	struct apx_state *apx_post, *apx_expect;
	bool match = true;
	int i;

	memset(&sig_result, 0, sizeof(sig_result));

	stashed_xbuf = alloc_xbuf(total_xstate_size);
	restore_stashed_xbuf = alloc_xbuf(total_xstate_size);
	post_xbuf = alloc_xbuf(total_xstate_size);

	fill_apx_xbuf(stashed_xbuf, XSTATE_TESTBYTE);

	sethandler(SIGUSR1, sigcontext_modify_handler);

	xrstor_apx(stashed_xbuf, XFEATURE_MASK_APX);
	raise(SIGUSR1);

	/* After sigreturn, save current EGPR state */
	xsave_apx(post_xbuf, XFEATURE_MASK_APX);

	clearhandler(SIGUSR1);

	if (!sig_result.handler_ran) {
		ksft_test_result_fail("Signal handler did not run\n");
		goto out;
	}

	/* Compare post-sigreturn state with what the handler wrote */
	apx_post = (struct apx_state *)((char *)post_xbuf + apx_xstate_offset);
	apx_expect = (struct apx_state *)((char *)restore_stashed_xbuf + apx_xstate_offset);

	for (i = 0; i < APX_NUM_REGS; i++) {
		if (apx_post->egpr[i] != apx_expect->egpr[i]) {
			ksft_print_msg("[FAIL] R%d: expected 0x%llx, got 0x%llx\n",
				       i + 16,
				       (unsigned long long)apx_expect->egpr[i],
				       (unsigned long long)apx_post->egpr[i]);
			match = false;
		}
	}

	if (match)
		ksft_test_result_pass("sigcontext: modified EGPRs restored after sigreturn\n");
	else
		ksft_test_result_fail("sigcontext: modified EGPRs NOT restored after sigreturn\n");

out:
	free(stashed_xbuf);
	free(restore_stashed_xbuf);
	free(post_xbuf);
}

static void usage(const char *prog)
{
	fprintf(stderr, "Usage: %s -t <test>\n", prog);
	fprintf(stderr, "Tests:\n");
	fprintf(stderr, "  sigctx_magic     - FP_XSTATE_MAGIC1/MAGIC2 in signal frame\n");
	fprintf(stderr, "  sigctx_xfeatures - xfeatures in fpx_sw_bytes includes APX\n");
	fprintf(stderr, "  sigctx_xstatebv  - XSTATE_BV in XSAVE header includes APX\n");
	fprintf(stderr, "  sigctx_delivery  - EGPR data delivered in signal frame\n");
	fprintf(stderr, "  sigctx_restore   - Modified EGPRs persist after sigreturn\n");
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

	if (strcmp(test_name, "sigctx_magic") == 0)
		test_sigctx_magic();
	else if (strcmp(test_name, "sigctx_xfeatures") == 0)
		test_sigctx_xfeatures();
	else if (strcmp(test_name, "sigctx_xstatebv") == 0)
		test_sigctx_xstatebv();
	else if (strcmp(test_name, "sigctx_delivery") == 0)
		test_sigctx_delivery();
	else if (strcmp(test_name, "sigctx_restore") == 0)
		test_sigctx_restore();
	else
		ksft_exit_fail_msg("Unknown test: %s\n", test_name);

	ksft_finished();
	return 0;
}
