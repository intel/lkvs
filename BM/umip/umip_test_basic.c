// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2022 Intel Corporation.

/*
 * umip_test_basic.c
 *
 * This tests for Intel User-Mode Execution Prevention
 *
 * Author:
 *        Neri, Ricardo <ricardo.neri@intel.com>
 *        - GPL v2
 *        - Tested sgdt,sidt,sldt,smsw and str instruction expected exception
 *        Pengfei, Xu <pengfei.xu@intel.com>
 *        - Add different behavior judgement for kernel code change from v5.4
 *        - Add different behavior judgement for kernel code change from v5.10
 *        - Add parameter for each instruction test and unify the code style
 *        - Format improvement
 */

/*****************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <err.h>
#include <signal.h>
#include <string.h>
#include "umip_test_defs.h"

#ifdef __x86_64__
#define GDTR_LEN 10
#define IDTR_LEN 10
#else
#define GDTR_LEN 6
#define IDTR_LEN 6
#endif

int test_passed, test_failed, test_errors;
extern sig_atomic_t got_signal, got_sigcode;

static void call_sgdt(void)
{
	unsigned char val[GDTR_LEN];
	unsigned long base = INIT_VAL(89898989);
	unsigned short limit = 0x3d3d;
	int i, exp_signum, exp_sigcode;

	got_signal = 0;
	got_sigcode = 0;
	INIT_EXPECTED_SIGNAL(exp_signum, 0, exp_sigcode, 0);

	for (i = 0; i < GDTR_LEN; i++)
		val[i] = 0;
	pr_info("Will issue SGDT and save at [%p]\n", val);
	asm volatile("sgdt %0\n" NOP_SLED : "=m" (val));

	// if Linux kernel is or newer than v5.4, should not receive signal
	if (kver_cmp(5, 4) == 0) {
		pr_info("Kernel version is or newer than v5.4\n");
		if (unexpected_signal())
			return;
	} else if (kver_cmp(5, 4) == 1) {
		pr_info("Kernel version is older than v5.4\n");
		if (inspect_signal(exp_signum, exp_sigcode))
			return;
	} else {
		pr_info("Get uname kernel version failed\n");
		return;
	}

	limit = val[1] << 8 | val[0];
	pr_info("GDT Limit [0x%04x]\n", limit);

	if (limit == expected_gdt.limit)
		pr_pass(test_passed, "Expected limit value\n");
	else
		pr_fail(test_failed, "Unexpected limit value\n");

	base = *(unsigned long *)(val + 2);

	pr_info("GDT Base [0x%016lx]\n", base);

	if (base == expected_gdt.base)
		pr_pass(test_passed, "Expected base value\n");
	else
		pr_fail(test_failed, "Unexpected base value\n");
}

static void call_sidt(void)
{
	unsigned char val[IDTR_LEN];
	unsigned long base = INIT_VAL(73737373);
	unsigned short limit = 0x9696;
	int i, exp_signum, exp_sigcode;

	got_signal = 0;
	got_sigcode = 0;
	INIT_EXPECTED_SIGNAL(exp_signum, 0, exp_sigcode, 0);

	for (i = 0; i < IDTR_LEN; i++)
		val[i] = 0;
	pr_info("Will issue SIDT and save at [%p]\n", val);
	asm volatile("sidt %0\n"  NOP_SLED : "=m" (val));

	if (kver_cmp(5, 4) == 0) {
		pr_info("Kernel version is or newer than v5.4\n");
		if (unexpected_signal())
			return;
	} else if (kver_cmp(5, 4) == 1) {
		pr_info("Kernel version is older than v5.4\n");
		if (inspect_signal(exp_signum, exp_sigcode))
			return;
	} else {
		pr_info("Get uname kernel version failed\n");
		return;
	}

	limit = val[1] << 8 | val[0];
	pr_info("IDT Limit [0x%04x]\n", limit);

	if (limit == expected_idt.limit)
		pr_pass(test_passed, "Expected limit value\n");
	else
		pr_fail(test_failed, "Unexpected limit value\n");

	base = *(unsigned long *)(val + 2);

	pr_info("IDT Base [0x%016lx]\n", base);

	if (base == expected_idt.base)
		pr_pass(test_passed, "Expected base value\n");
	else
		pr_fail(test_failed, "Unexpected base value\n");
}

static void call_sldt(void)
{
	unsigned long val = INIT_VAL(a1a1a1a1);
	unsigned long init_val = INIT_VAL(a1a1a1a1);
	/* if operand is memory, result is 16-bit */
	unsigned short mask = 0xffff;
	int exp_signum, exp_sigcode;

	got_signal = 0;
	got_sigcode = 0;
	INIT_EXPECTED_SIGNAL_STR_SLDT(exp_signum, 0, exp_sigcode, 0);

	pr_info("Will issue SLDT and save at [%p]\n", &val);
	asm volatile("sldt %0\n" NOP_SLED : "=m" (val));

	if (kver_cmp(5, 10) == 0) {
		pr_info("Kernel version is or newer than v5.10\n");
		if (unexpected_signal())
			return;
	} else if (kver_cmp(5, 10) == 1) {
		pr_info("Kernel version is older than v5.10\n");
		if (inspect_signal(exp_signum, exp_sigcode))
			return;
	} else {
		pr_info("Get uname kernel version failed\n");
		return;
	}

	pr_info("SS for LDT[0x%08lx]\n", val);

	/*
	 * Check that the bits that are supposed to change does so
	 * as well as that the bits that are not supposed to change
	 * does not change.
	 */
	if ((val & mask) == (expected_ldt & mask) &&
	    (val & ~mask) == (init_val & ~mask))
		pr_pass(test_passed, "Obtained expected value\n");
	else
		pr_fail(test_failed, "Obtained unexpected value\n");
}

static void call_smsw(void)
{
	unsigned long val = INIT_VAL(a2a2a2a2);
	unsigned long init_val = INIT_VAL(a2a2a2a2);
	unsigned short mask = 0xffff;
	int exp_signum, exp_sigcode;

	got_signal = 0;
	got_sigcode = 0;
	INIT_EXPECTED_SIGNAL(exp_signum, 0, exp_sigcode, 0);

	pr_info("Will issue SMSW and save at [%p]\n", &val);
	asm volatile("smsw %0\n" NOP_SLED : "=m" (val));

	if (kver_cmp(5, 4) == 0) {
		pr_info("Kernel version is or newer than v5.4\n");
		if (unexpected_signal())
			return;
	} else if (kver_cmp(5, 4) == 1) {
		pr_info("Kernel version is older than v5.4\n");
		if (inspect_signal(exp_signum, exp_sigcode))
			return;
	} else {
		pr_info("Get uname kernel version failed\n");
		return;
	}

	pr_info("CR0[0x%08lx]\n", val);

	/*
	 * Check that the bits that are supposed to change does so
	 * as well as that the bits that are not supposed to change
	 * does not change.
	 */
	if ((val & mask) == (expected_msw & mask) &&
	    (val & ~mask) == (init_val & ~mask))
		pr_pass(test_passed, "Obtained expected value\n");
	else
		pr_fail(test_failed, "Obtained unexpected value\n");
}

static void call_str(void)
{
	unsigned int val32 = 0xa4a4a4a4;
	unsigned int init_val32 = 0xa4a4a4a4;
	unsigned short val16 = 0xa5a5;
	unsigned short init_val16 = 0xa5a5;
	int exp_signum, exp_sigcode;

	got_signal = 0;
	got_sigcode = 0;
	INIT_EXPECTED_SIGNAL_STR_SLDT(exp_signum, 0, exp_sigcode, 0);

#if __x86_64__
	unsigned long val64 = 0xa3a3a3a3a3a3a3a3;
	unsigned long init_val64 = 0xa3a3a3a3a3a3a3a3;

	pr_info("Will issue STR and save at m64[0x%p]\n", &val64);
	asm volatile("str %0\n" NOP_SLED : "=m" (val64));

	if (kver_cmp(5, 10) == 0) {
		pr_info("Kernel version is or newer than v5.10\n");
		if (unexpected_signal())
			return;
	} else if (kver_cmp(5, 10) == 1) {
		pr_info("Kernel version is older than v5.10\n");
		if (inspect_signal(exp_signum, exp_sigcode))
			goto test_m32;
	} else {
		pr_info("Get uname kernel version failed\n");
		return;
	}

	pr_info("SS for TSS[0x%016lx]\n", val64);

	/*
	 * Check that the bits that are supposed to change does so
	 * as well as that the bits that are not supposed to change
	 * does not change. Since operand is memory, value will be
	 * 16-bit.
	 */
	if ((val64 & 0xffff) == (expected_tr & 0xffff) &&
	    (val64 & ~0xffff) == (init_val64 & ~0xffff))
		pr_pass(test_passed, "Obtained 64-bit expected value\n");
	else
		pr_fail(test_failed, "Obtained 64-bit unexpected value\n");

test_m32:
#endif

	got_signal = 0;
	got_sigcode = 0;

	pr_info("Will issue STR and save at m32[0x%p]\n", &val32);
	asm volatile("str %0\n" NOP_SLED : "=m" (val32));

	if (kver_cmp(5, 10) == 0) {
		pr_info("Kernel version is or newer than v5.10\n");
		if (unexpected_signal())
			return;
	} else if (kver_cmp(5, 10) == 1) {
		pr_info("Kernel version is older than v5.10\n");
		if (inspect_signal(exp_signum, exp_sigcode))
			return;
	} else {
		pr_info("Get uname kernel version failed\n");
		return;
	}

	pr_info("SS for TSS[0x%08x]\n", val32);

	/*
	 * Check that the bits that are supposed to change does so
	 * as well as that the bits that are not supposed to change
	 * does not change. Since operand is memory, value will be
	 * 16-bit.
	 */
	if ((val32 & 0xffff) == (expected_tr & 0xffff) &&
	    (val32 & ~0xffff) == (init_val32 & ~0xffff))
		pr_pass(test_passed, "Obtained 32-bit expected value\n");
	else
		pr_fail(test_failed, "Obtained 32-bit unexpected value\n");

test_m16:
	got_signal = 0;
	got_sigcode = 0;

	pr_info("Will issue STR and save at m16[0x%p]\n", &val16);
	asm volatile("str %0\n" NOP_SLED : "=m" (val16));

	if (inspect_signal(exp_signum, exp_sigcode))
		return;

	pr_info("SS for TSS[0x%04x]\n", val16);

	/*
	 * Check that the bits that are supposed to change does so
	 * as well as that the bits that are not supposed to change
	 * does not change. Since operand is memory, value will be
	 * 16-bit.
	 */
	if ((val16 & 0xffff) == (expected_tr & 0xffff) &&
	    (val16 & ~0xffff) == (init_val16 & ~0xffff))
		pr_pass(test_passed, "Obtained 16-bit expected value\n");
	else
		pr_fail(test_failed, "Obtained 16-bit unexpected value\n");
}

void usage(void)
{
	printf("Usage: [g][i][l][m][t][a]\n");
	printf("g      Test sgdt\n");
	printf("i      Test sidt\n");
	printf("l      Test sldt\n");
	printf("m      Test smsw\n");
	printf("t      Test str\n");
	printf("a      Test all\n");
}

int main(int argc, char *argv[])
{
	struct sigaction action;

	PRINT_BITNESS;

	memset(&action, 0, sizeof(action));
	action.sa_sigaction = &signal_handler;
	action.sa_flags = SA_SIGINFO;
	sigemptyset(&action.sa_mask);
	char param;

	if (argc == 1) {
		usage();
		exit(1);
	} else if (argc == 2) {
		if (sscanf(argv[1], "%c", &param) == 1) {
			pr_info("1 parameters: param=%c\n", param);
		} else {
			pr_info(" Get param failed, return 2\n");
			return 2;
		}
	} else {
		if (sscanf(argv[1], "%c", &param) == 1) {
			pr_info("1 parameters: param=%c\n", param);
		} else {
			pr_info(" Get param failed, return 2\n");
			return 2;
		}
		pr_info("Just get param=%c\n", param);
	}

	if (sigaction(SIGSEGV, &action, NULL) < 0) {
		pr_error(test_errors, "Could not set the signal handler!");
		print_results();
		exit(1);
	}

	switch (param) {
	case 'a':
		pr_info("Test all.\n");
		call_sgdt();
		call_sidt();
		call_sldt();
		call_smsw();
		call_str();
		break;
	case 'g':
		call_sgdt();
		break;
	case 'i':
		call_sidt();
		break;
	case 'l':
		call_sldt();
		break;
	case 'm':
		call_smsw();
		break;
	case 't':
		call_str();
		break;
	default:
		usage();
		exit(1);
	}

	memset(&action, 0, sizeof(action));
	action.sa_handler = SIG_DFL;
	sigemptyset(&action.sa_mask);

	if (sigaction(SIGSEGV, &action, NULL) < 0) {
		pr_error(test_errors, "Could not remove signal handler!");
		print_results();
		exit(1);
	}

	print_results();
	return 0;
}
