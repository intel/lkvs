// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2022 Intel Corporation.

/*
 * xstate.c - tests XSAVE feature with fork and signal handling.
 *
 * Author: Pengfei Xu <pengfei.xu@intel.com>
 *
 * The XSAVE feature set supports the saving and restoring of state components.
 * It tests "FP, SSE(XMM), AVX2(YMM), AVX512_OPMASK/AVX512_ZMM_Hi256/
 * AVX512_Hi16_ZMM and PKRU parts" xstates with the following cases:
 * 1. The contents of these xstates in the process should not change after the
 *    signal handling.
 * 2. The contents of these xstates in the child process should be the same as
 *    the contents of the xstate in the parent process after the fork syscall.
 * 3. The contents of xstates in the parent process should not change after
 *    the context switch.
 *
 * The regions and reserved bytes of the components tested for XSAVE feature
 * are as follows:
 * x87(FP)/SSE    (0 - 159 bytes)
 * SSE(XMM part)  (160-415 bytes)
 * Reserved       (416-511 bytes)
 * Header_used    (512-527 bytes; XSTATE BV(bitmap vector) mask:512-519 bytes)
 * Header_reserved(528-575 bytes must be 00)
 * YMM            (Offset:CPUID.(EAX=0D,ECX=2).EBX Size:CPUID(EAX=0D,ECX=2).EAX)
 * AVX512_OPMASK  (Offset:CPUID.(EAX=0D,ECX=5).EBX Size:CPUID(EAX=0D,ECX=5).EAX)
 * ZMM_Hi256      (Offset:CPUID.(EAX=0D,ECX=6).EBX Size:CPUID(EAX=0D,ECX=6).EAX)
 * Hi16_ZMM       (Offset:CPUID.(EAX=0D,ECX=7).EBX Size:CPUID(EAX=0D,ECX=7).EAX)
 * PKRU           (Offset:CPUID.(EAX=0D,ECX=9).EBX Size:CPUID(EAX=0D,ECX=9).EAX)
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <stdbool.h>
#include <malloc.h>
#include <stdlib.h>

#include "xstate.h"
#include "xstate_helpers.h"
#include "../common/kselftest.h"

#define NUM_TESTS	3
#define xstate_test_array_init(idx, init_opt, fill_opt)		\
	do {							\
		xstate_tests[idx].init = init_opt;		\
		xstate_tests[idx].fill_xbuf = fill_opt;		\
	} while (0)

static struct xsave_buffer *valid_xbuf, *compared_xbuf;
static struct xstate_test xstate_tests[XFEATURE_MAX];
static uint32_t xstate_size;

static struct xsave_buffer *alloc_xbuf(uint32_t buf_size)
{
	struct xsave_buffer *xbuf;

	/* XSAVE buffer should be 64B-aligned. */
	xbuf = aligned_alloc(64, buf_size);
	if (!xbuf)
		ksft_exit_fail_msg("aligned_alloc() failed.\n");

	return xbuf;
}

static void show_test_xfeatures(void)
{
	uint32_t xfeature_num;
	const char *xfeature_name;

	ksft_print_msg("[NOTE] Test following xstates with mask:%lx.\n",
		       xstate_info.mask);
	for (xfeature_num = 0; xfeature_num < XFEATURE_MAX; xfeature_num++) {
		if (!(xstate_info.mask & (1 << xfeature_num)))
			continue;
		xfeature_name = xfeature_names[xfeature_num];
		ksft_print_msg("[NOTE] XSAVE feature num %02d: '%s'.\n",
			       xfeature_num, xfeature_name);
	}
}

static void dump_buffer(unsigned char *buf, int size)
{
	int new_ln, num;

	ksft_print_msg("xsave size = %d (%03xh)\n", size, size);
	for (new_ln = 0; new_ln < size; new_ln += 16) {
		printf("%04x: ", new_ln);
		for (num = new_ln; ((num < new_ln + 16) && (num < size)); num++)
			printf("%02x ", buf[num]);
		printf("\n");
	}
}

static void compare_buf_result(struct xsave_buffer *valid_buf,
			       struct xsave_buffer *compare_buf,
			       const char *case_name)
{
	if (memcmp(&valid_buf->bytes[0], &compare_buf->bytes[0], xstate_size))
		ksft_test_result_fail("%s", case_name);
	else
		ksft_test_result_pass("%s", case_name);
}

static void test_xstate_sig_handle(void)
{
	const char *case_name1 = "xstate around process signal handling";

	ksft_print_msg("[RUN] Check xstate around signal handling test.\n");
	dump_buffer((unsigned char *)valid_xbuf, xstate_size);
	if (xstate_sig_handle(valid_xbuf, compared_xbuf, xstate_info.mask,
	    xstate_size)) {
		ksft_print_msg("[NOTE] SIGUSR1 handling is done.\n");
	} else {
		ksft_test_result_error("%s: Didn't access SIGUSR1 handling.\n",
				       case_name1);
		return;
	}

	compare_buf_result(valid_xbuf, compared_xbuf, case_name1);
	dump_buffer((unsigned char *)compared_xbuf, xstate_size);
}

static void test_xstate_fork(void)
{
	const char *case_name2 = "xstate of child process should be same as xstate of parent";
	const char *case_name3 = "parent xstate should be same after context switch";

	ksft_print_msg("[RUN]\tParent pid:%d check xstate around fork test.\n",
		       getpid());
	/* Child process xstate should be same as the parent process xstate. */
	if (xstate_fork(valid_xbuf, compared_xbuf, xstate_info.mask,
	    xstate_size)) {
		ksft_test_result_pass("%s", case_name2);
	} else {
		ksft_test_result_fail("%s", case_name2);
	}

	/* The parent process xstate should not change after context switch. */
	compare_buf_result(valid_xbuf, compared_xbuf, case_name3);
	dump_buffer((unsigned char *)compared_xbuf, xstate_size);
}

static void prepare_xstate_test(void)
{
	xstate_test_array_init(XFEATURE_FP, init_legacy_info,
			       fill_fp_mxcsr_xstate_buf);
	xstate_test_array_init(XFEATURE_SSE, init_legacy_info,
			       fill_xmm_xstate_buf);
	xstate_test_array_init(XFEATURE_YMM, init_ymm_info,
			       fill_common_xstate_buf);
	xstate_test_array_init(XFEATURE_OPMASK, init_avx512_info,
			       fill_common_xstate_buf);
	xstate_test_array_init(XFEATURE_ZMM_Hi256, init_avx512_info,
			       fill_common_xstate_buf);
	xstate_test_array_init(XFEATURE_Hi16_ZMM, init_avx512_info,
			       fill_common_xstate_buf);
	xstate_test_array_init(XFEATURE_PKRU, init_pkru_info,
			       fill_pkru_xstate_buf);

	xstate_tests[XSTATE_CASE_SIG].xstate_case = test_xstate_sig_handle;
	xstate_tests[XSTATE_CASE_FORK].xstate_case = test_xstate_fork;
}

static void test_xstate(void)
{
	uint32_t xfeature_num, case_num, eax, ebx, ecx, edx;

	/*
	 * CPUID.0xd.0:EBX[bit 5] enumerates the size(in bytes) required by
	 * the XSAVE instruction for an XSAVE area containing all the user
	 * state components corresponding to bits currently set in XCR0.
	 */
	__cpuid_count(CPUID_LEAF_XSTATE, CPUID_SUBLEAF_XSTATE_USER, eax, ebx,
		      ecx, edx);
	xstate_size = ebx;
	valid_xbuf = alloc_xbuf(xstate_size);
	compared_xbuf = alloc_xbuf(xstate_size);

	for (xfeature_num = XFEATURE_FP; xfeature_num < XFEATURE_MAX;
	     xfeature_num++) {
		/* If there is no the xfeature init function, will continue. */
		if (xstate_tests[xfeature_num].init) {
			/* If CPU doesn't support the xfeature, will continue */
			if (!xstate_tests[xfeature_num].init(xfeature_num))
				continue;
		} else {
			continue;
		}

		/* Fill xstate buffer. */
		if (xfeature_num != XFEATURE_PKRU) {
			xstate_tests[xfeature_num].fill_xbuf(valid_xbuf,
				xfeature_num, XSTATE_TESTBYTE);
		} else {
			/*
			 * Bits 0-1 in first byte of PKRU must be 0 for
			 * RW access to linear address.
			 */
			xstate_tests[xfeature_num].fill_xbuf(valid_xbuf,
				xfeature_num, PKRU_TESTBYTE);
		}
	}

	/*
	 * Fill xstate-component bitmap(512-519 bytes) into the beginning of
	 * xstate header. xstate header range is 512-575 bytes.
	 */
	*(uint64_t *)(&valid_xbuf->header) = xstate_info.mask;

	show_test_xfeatures();

	for (case_num = XSTATE_CASE_SIG; case_num < XSTATE_CASE_MAX; case_num++)
		xstate_tests[case_num].xstate_case();

	free(valid_xbuf);
	free(compared_xbuf);
}

int main(void)
{
	ksft_print_header();
	ksft_set_plan(NUM_TESTS);

	/* Check hardware availability for xsave at first. */
	check_cpuid_xsave_availability();
	prepare_xstate_test();
	test_xstate();

	ksft_exit(ksft_cnt.ksft_pass == ksft_plan);
}
