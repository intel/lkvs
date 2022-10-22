// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2022 Intel Corporation.

/*
 * umip_exceptions.c
 * Author: Ricardo Neri Calderon <ricardo.neri-calderon@linux.intel.com>
 *      Neri, Ricardo <ricardo.neri@intel.com>
 *      - Tested sgdt, sidt, sldt, smsw and str instructions
 *      - test UMIP emulation code when a page fault should be
 *      - generated (i.e., the requested memory access is not mapped. No code
 *      - is included to test cases in which Memory Protection Keys are used.
 *      - maperr_pf
 *      - lock_prefix
 *      - register_operand
 * Contributor: Pengfei Xu <pengfei.xu@intel.com>
 *      - Add parameter for each instruction test and unify the code style
 *      - Some formatting improvements
 */

/*****************************************************************************/

#define _GNU_SOURCE
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <ucontext.h>
#include <err.h>
#include <asm/ldt.h>
#include <sys/syscall.h>
#include "umip_test_defs.h"

extern sig_atomic_t got_signal, got_sigcode;

int test_passed, test_failed, test_errors;

#define gen_test_maperr_pf_inst(inst, bad_addr)					\
static void __test_maperr_pf_##inst(int exp_signum, int exp_sigcode)		\
{										\
	unsigned long *val_bad = (unsigned long *)bad_addr;			\
										\
	got_signal = 0;								\
	got_sigcode = 0;							\
										\
	pr_info("Test page fault because unmapped memory for %s with addr %p\n",\
		#inst, val_bad);						\
	asm volatile (#inst" %0\n" NOP_SLED : "=m"(*val_bad));			\
										\
	check_signal(exp_signum);						\
}

gen_test_maperr_pf_inst(smsw, 0x100000)
gen_test_maperr_pf_inst(sidt, 0x100000)
gen_test_maperr_pf_inst(sgdt, 0x100000)
gen_test_maperr_pf_inst(str, 0x100000)
gen_test_maperr_pf_inst(sldt, 0x100000)

static void test_maperr_pf(void)
{
	int exp_signum, exp_sigcode;
	int exp_signum_str_sldt, exp_sigcode_str_sldt;

	INIT_EXPECTED_SIGNAL(exp_signum, SIGSEGV, exp_sigcode, SEGV_MAPERR);
	INIT_EXPECTED_SIGNAL_STR_SLDT(exp_signum_str_sldt, SIGSEGV,
				      exp_sigcode_str_sldt, SEGV_MAPERR);

	__test_maperr_pf_smsw(exp_signum, exp_sigcode);
	__test_maperr_pf_sidt(exp_signum, exp_sigcode);
	__test_maperr_pf_sgdt(exp_signum, exp_sigcode);
	__test_maperr_pf_str(exp_signum_str_sldt, exp_sigcode_str_sldt);
	__test_maperr_pf_sldt(exp_signum_str_sldt, exp_sigcode_str_sldt);
}

#define gen_test_lock_prefix_inst(name, inst)				\
static void __test_lock_prefix_##name(void)				\
{									\
	got_signal = 0;							\
	got_sigcode = 0;						\
									\
	pr_info("Test %s with lock prefix\n", #name);			\
	/* name (%eax) with the LOCK prefix */				\
	asm volatile(inst NOP_SLED);					\
									\
	inspect_signal(SIGILL, ILL_ILLOPN);				\
}

gen_test_lock_prefix_inst(SMSW, ".byte 0xf0, 0xf, 0x1, 0x20\n")
gen_test_lock_prefix_inst(SIDT, ".byte 0xf0, 0xf, 0x1, 0x8\n")
gen_test_lock_prefix_inst(SGDT, ".byte 0xf0, 0xf, 0x1, 0x0\n")
gen_test_lock_prefix_inst(STR,  ".byte 0xf0, 0xf, 0x0, 0x8\n")
gen_test_lock_prefix_inst(SLDT, ".byte 0xf0, 0xf, 0x0, 0x0\n")

static void test_lock_prefix(void)
{
	__test_lock_prefix_SMSW();
	__test_lock_prefix_SIDT();
	__test_lock_prefix_SGDT();
	__test_lock_prefix_STR();
	__test_lock_prefix_SLDT();
}

#define gen_test_register_operand_inst(name, inst)			\
static void __test_register_operand_##name(void)			\
{									\
	got_signal = 0;							\
	got_sigcode = 0;						\
									\
	pr_info("Test %s with register operand\n", #name);		\
	/* name (%eax) with the LOCK prefix */				\
	asm volatile(inst NOP_SLED);					\
									\
	inspect_signal(SIGILL, ILL_ILLOPN);				\
	return;								\
}

gen_test_register_operand_inst(SIDT, ".byte 0xf, 0x1, 0xc8\n")
gen_test_register_operand_inst(SGDT, ".byte 0xf, 0x1, 0xc0\n")

static void test_register_operand(void)
{
	__test_register_operand_SGDT();
	__test_register_operand_SIDT();
}

#ifdef __x86_64__
static void test_null_segment_selectors(void) {}
#else
#define gen_test_null_segment_selector(inst, reg)				\
static void __test_null_segment_selector_##inst##_##reg(void)			\
{										\
	got_signal = 0;								\
	got_sigcode = 0;							\
										\
	pr_info("Test using null seg sel for " #inst " with " #reg "\n");	\
	asm volatile("push %" #reg "\n"						\
		     "push %eax\n"						\
		     "push %ebx\n"						\
		     "mov $0x1000, %eax\n"					\
		     "mov $0, %ebx\n"						\
		     "mov %bx, %" #reg "\n"					\
		     "smsw %" #reg ":(%eax)\n"					\
		     NOP_SLED							\
		     "pop %ebx\n"						\
		     "pop %eax\n"						\
		     "pop %" #reg "\n");					\
										\
	inspect_signal(SIGSEGV, SI_KERNEL);					\
	return;									\
}

gen_test_null_segment_selector(smsw, ds)
gen_test_null_segment_selector(smsw, es)
gen_test_null_segment_selector(smsw, fs)
gen_test_null_segment_selector(smsw, gs)
gen_test_null_segment_selector(sidt, ds)
gen_test_null_segment_selector(sidt, es)
gen_test_null_segment_selector(sidt, fs)
gen_test_null_segment_selector(sidt, gs)
gen_test_null_segment_selector(sgdt, ds)
gen_test_null_segment_selector(sgdt, es)
gen_test_null_segment_selector(sgdt, fs)
gen_test_null_segment_selector(sgdt, gs)
gen_test_null_segment_selector(str, ds)
gen_test_null_segment_selector(str, es)
gen_test_null_segment_selector(str, fs)
gen_test_null_segment_selector(str, gs)
gen_test_null_segment_selector(sldt, ds)
gen_test_null_segment_selector(sldt, es)
gen_test_null_segment_selector(sldt, fs)
gen_test_null_segment_selector(sldt, gs)

static void test_null_segment_selectors(void)
{
	__test_null_segment_selector_smsw_ds();
	__test_null_segment_selector_smsw_es();
	__test_null_segment_selector_smsw_fs();
#ifdef TEST_GS /* TODO: Meddling with gs breaks libc */
	__test_null_segment_selector_smsw_gs();
#endif
	__test_null_segment_selector_sidt_ds();
	__test_null_segment_selector_sidt_es();
	__test_null_segment_selector_sidt_fs();
#ifdef TEST_GS /* TODO: Meddling with gs breaks libc */
	__test_null_segment_selector_sidt_gs();
#endif

	__test_null_segment_selector_sgdt_ds();
	__test_null_segment_selector_sgdt_es();
	__test_null_segment_selector_sgdt_fs();
#ifdef TEST_GS /* TODO: Meddling with gs breaks libc */
	__test_null_segment_selector_sgdt_gs();
#endif

	__test_null_segment_selector_sldt_ds();
	__test_null_segment_selector_sldt_es();
	__test_null_segment_selector_sldt_fs();
	#ifdef TEST_GS /* TODO: Meddling with gs breaks libc */
	__test_null_segment_selector_sldt_gs();
#endif

	__test_null_segment_selector_str_ds();
	__test_null_segment_selector_str_es();
	__test_null_segment_selector_str_fs();

#ifdef TEST_GS /* TODO: Meddling with gs breaks libc */
	__test_null_segment_selector_str_gs();
#endif
}
#endif

#ifdef __x86_64__
static void test_addresses_outside_segment(void) {}
#else

#define SEGMENT_SIZE 0x1000
#define CODE_DESC_INDEX 1
#define DATA_DESC_INDEX 2

#define RPL3 3
#define TI_LDT 1

#define SEGMENT_SELECTOR(index) (RPL3 | (TI_LDT << 2) | (index << 3))

unsigned char custom_segment[SEGMENT_SIZE];

static int setup_data_segments(void)
{
	int ret;
	struct user_desc desc = {
		.entry_number    = 0,
		.base_addr       = 0,
		.limit           = SEGMENT_SIZE,
		.seg_32bit       = 1,
		.contents        = 0, /* data */
		.read_exec_only  = 0,
		.limit_in_pages  = 0,
		.seg_not_present = 0,
		.useable         = 1
	};

	desc.entry_number = DATA_DESC_INDEX;
	desc.base_addr = (unsigned long)&custom_segment;

	ret = syscall(SYS_modify_ldt, 1, &desc, sizeof(desc));
	if (ret) {
		pr_error(test_errors, "Failed to install stack segment [%d].\n", ret);
		return ret;
	}

	return 0;
}

#define gen_test_addresses_outside_segment(inst, sel)			\
static void __test_addresses_outside_segment_##inst##_##sel(void)	\
{									\
	int ret;							\
	unsigned short seg_sel;						\
									\
	got_signal = 0;							\
	got_sigcode = 0;						\
									\
									\
	seg_sel = SEGMENT_SELECTOR(DATA_DESC_INDEX);			\
									\
	pr_info("Test address outside of segment limit for " #inst " with " #sel"\n");\
	asm volatile("push %%" #sel"\n"					\
		     "push %%eax\n"					\
		     "push %%ebx\n"					\
		     "mov $0x2000, %%eax\n"				\
		     "mov %0, %%" #sel "\n"				\
		     #inst " %%" #sel ":(%%eax)\n"			\
		     NOP_SLED						\
		     "pop %%ebx\n"					\
		     "pop %%eax\n"					\
		     "pop %%" #sel "\n"					\
		     :							\
		     : "m" (seg_sel));					\
									\
	inspect_signal(SIGSEGV, SI_KERNEL);				\
	return;								\
}

gen_test_addresses_outside_segment(smsw, ds)
gen_test_addresses_outside_segment(str, ds)
gen_test_addresses_outside_segment(sldt, ds)
gen_test_addresses_outside_segment(sgdt, ds)
gen_test_addresses_outside_segment(sidt, ds)
gen_test_addresses_outside_segment(smsw, es)
gen_test_addresses_outside_segment(str, es)
gen_test_addresses_outside_segment(sldt, es)
gen_test_addresses_outside_segment(sgdt, es)
gen_test_addresses_outside_segment(sidt, es)
gen_test_addresses_outside_segment(smsw, fs)
gen_test_addresses_outside_segment(str, fs)
gen_test_addresses_outside_segment(sldt, fs)
gen_test_addresses_outside_segment(sgdt, fs)
gen_test_addresses_outside_segment(sidt, fs)
gen_test_addresses_outside_segment(smsw, gs)
gen_test_addresses_outside_segment(str, gs)
gen_test_addresses_outside_segment(sldt, gs)
gen_test_addresses_outside_segment(sgdt, gs)
gen_test_addresses_outside_segment(sidt, gs)

static void test_addresses_outside_segment(void)
{
	int ret;

	ret = setup_data_segments();
	if (ret)
		return;

	__test_addresses_outside_segment_smsw_ds();
	__test_addresses_outside_segment_str_ds();
	__test_addresses_outside_segment_sgdt_ds();
	__test_addresses_outside_segment_sidt_ds();
	__test_addresses_outside_segment_sldt_ds();
	__test_addresses_outside_segment_smsw_es();
	__test_addresses_outside_segment_str_es();
	__test_addresses_outside_segment_sgdt_es();
	__test_addresses_outside_segment_sidt_es();
	__test_addresses_outside_segment_sldt_es();
	__test_addresses_outside_segment_smsw_fs();
	__test_addresses_outside_segment_str_fs();
	__test_addresses_outside_segment_sgdt_fs();
	__test_addresses_outside_segment_sidt_fs();
	__test_addresses_outside_segment_sldt_fs();
#ifdef TEST_GS
	__test_addresses_outside_segment_smsw_gs();
	__test_addresses_outside_segment_str_gs();
	__test_addresses_outside_segment_sgdt_gs();
	__test_addresses_outside_segment_sidt_gs();
	__test_addresses_outside_segment_sldt_gs();
#endif
}
#endif

void usage(void)
{
	printf("Usage: [m][l][r][n][d][a]\n");
	printf("m      Test test_maperr_pf\n");
	printf("l      Test test_lock_prefix\n");
	printf("r      Test test_register_operand\n");
	printf("n      Test test_null_segment_selectors(TODO)\n");
	printf("d      Test test_addresses_outside_segment(TODO)\n");
	printf("a      Test all\n");
}

int main(int argc, char *argv[])
{
	struct sigaction action;
	int ret;

	PRINT_BITNESS;

	memset(&action, 0, sizeof(action));
	action.sa_sigaction = &signal_handler;
	action.sa_flags = SA_SIGINFO;
	sigemptyset(&action.sa_mask);
	char parm;

	if (argc == 1) {
		usage();
		exit(1);
	} else {
		ret = sscanf(argv[1], "%c", &parm);
		if (ret != 1) {
			printf("argv[2]:%c is not a char value.\n", argv[2]);
			return 2;
		}
		sscanf(argv[1], "%c", &parm);
		pr_info("Only get 1st parameter: parm=%c\n", parm);
	}

	if (sigaction(SIGSEGV, &action, NULL) < 0) {
		pr_error(test_errors, "Could not set the signal handler for SIGSEGV!\n");
		exit(1);
	}

	if (sigaction(SIGILL, &action, NULL) < 0) {
		pr_error(test_errors, "Could not set signal handler SIGILL!\n");
		exit(1);
	}

	switch (parm) {
	case 'a':
		pr_info("Test all.\n");
		pr_info("***Test test_maperr_pf next***\n");
		test_maperr_pf();
		pr_info("***Test test_lock_prefix next***\n");
		test_lock_prefix();
		pr_info("***Test test_register_operand next***\n");
		test_register_operand();
		pr_info("***Test test_null_segment_selectors***\n");
		test_null_segment_selectors();
		pr_info("***Test test_addresses_outside_segment***\n");
		test_addresses_outside_segment();
		break;
	case 'm':
		pr_info("***Test test_maperr_pf next***\n");
		test_maperr_pf();
		break;
	case 'l':
		pr_info("***Test test_lock_prefix***\n");
		test_lock_prefix();
		break;
	case 'r':
		pr_info("***Test test_register_operand***\n");
		test_register_operand();
		break;
	default:
		usage();
		exit(1);
	}

	memset(&action, 0, sizeof(action));
	action.sa_handler = SIG_DFL;
	sigemptyset(&action.sa_mask);

	if (sigaction(SIGSEGV, &action, NULL) < 0) {
		pr_error(test_errors, "Could not remove signal SIGSEGV handler!\n");
		print_results();
		return 1;
	}

	if (sigaction(SIGILL, &action, NULL) < 0) {
		pr_error(test_errors, "Could not remove signal SIGILL handler!\n");
		print_results();
		return 1;
	}

	print_results();
	return 0;
}
