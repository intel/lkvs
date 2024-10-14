// SPDX-License-Identifier: GPL-2.0-only
/*
 *
 * Copyright (c) 2024 Intel Corporation.
 * Jiaxi Chen <jiaxi.chen@linux.intel.com>
 * Jiaan Lu <jiaan.lu@intel.com>
 *
 */

#include <stdio.h>
#include <limits.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

/* Assembling [cmpbexadd qword [rax],rbx,rcx] */
#define CMPBEXADD ".byte 0xc4,0xe2,0xf1,0xe6,0x18"
/* Assembling [cmpbxadd qword [rax],rbx,rcx] */
#define CMPBXADD ".byte 0xc4,0xe2,0xf1,0xe2,0x18"
/* Assembling [cmplexadd qword [rax],rbx,rcx] */
#define CMPLEXADD ".byte 0xc4,0xe2,0xf1,0xee,0x18"
/* Assembling [cmplxadd qword [rax],rbx,rcx] */
#define CMPLXADD ".byte 0xc4,0xe2,0xf1,0xec,0x18"
/* Assembling [cmpnbexadd qword [rax],rbx,rcx] */
#define CMPNBEXADD ".byte 0xc4,0xe2,0xf1,0xe7,0x18"
/* Assembling [cmpnbxadd qword [rax],rbx,rcx] */
#define CMPNBXADD ".byte 0xc4,0xe2,0xf1,0xe3,0x18"
/* Assembling [cmpnlexadd qword [rax],rbx,rcx] */
#define CMPNLEXADD ".byte 0xc4,0xe2,0xf1,0xef,0x18"
/* Assembling [cmpnlxadd qword [rax],rbx,rcx] */
#define CMPNLXADD ".byte 0xc4,0xe2,0xf1,0xed,0x18"
/* Assembling [cmpnoxadd qword [rax],rbx,rcx] */
#define CMPNOXADD ".byte 0xc4,0xe2,0xf1,0xe1,0x18"
/* Assembling [cmpnpxadd qword [rax],rbx,rcx] */
#define CMPNPXADD ".byte 0xc4,0xe2,0xf1,0xeb,0x18"
/* Assembling [cmpnsxadd qword [rax],rbx,rcx] */
#define CMPNSXADD ".byte 0xc4,0xe2,0xf1,0xe9,0x18"
/* Assembling [cmpnzxadd qword [rax],rbx,rcx] */
#define CMPNZXADD ".byte 0xc4,0xe2,0xf1,0xe5,0x18"
/* Assembling [cmpoxadd qword [rax],rbx,rcx] */
#define CMPOXADD ".byte 0xc4,0xe2,0xf1,0xe0,0x18"
/* Assembling [cmppxadd qword [rax],rbx,rcx] */
#define CMPPXADD ".byte 0xc4,0xe2,0xf1,0xea,0x18"
/* Assembling [cmpsxadd qword [rax],rbx,rcx] */
#define CMPSXADD ".byte 0xc4,0xe2,0xf1,0xe8,0x18"
/* Assembling [cmpzxadd qword [rax],rbx,rcx] */
#define CMPZXADD ".byte 0xc4,0xe2,0xf1,0xe4,0x18"

struct output_unsigned {
	unsigned long rax;
	unsigned long rbx;
	unsigned long rcx;
	unsigned long rflags;
};

struct output_signed {
	long rax;
	long rbx;
	long rcx;
	unsigned long rflags;
};

#define DEF_FUNC_UNSIGNED(name, insr, op1, op2, op3)			\
struct output_unsigned name(unsigned long op1, unsigned long op2, unsigned long op3)	\
{									\
	unsigned long rflags;						\
	unsigned long rax, rbx, rcx;					\
	struct output_unsigned output;					\
									\
	printf("%s -  input: op1 = %d, op2 = %d, op3 = %d\n",		\
		__func__, op1, op2, op3);				\
	asm volatile ("mov %4, %%rax;\n\t"				\
			"mov %5, %%rbx;\n\t"				\
			"mov %6, %%rcx;\n\t"				\
			insr "\n\t"					\
			"pushfq;\n\t"					\
			"popq %0;\n\t"					\
			"mov (%%rax), %1;\n\t"				\
			"mov %%rbx, %2;\n\t"				\
			"mov %%rcx, %3;\n\t"				\
	: "=m"(rflags), "=r"(rax), "=r"(rbx), "=r"(rcx)		\
			: "r"(&op1), "r"(op2), "r"(op3)		\
	: "rax", "rbx", "rcx");					\
									\
	printf("%s - output: *(rax) = %d, rbx = %d, rcx = %d, rflags = 0x%lx\n", \
		__func__, rax, rbx, rcx, rflags);			\
	output.rax = rax;				\
	output.rbx = rbx;				\
	output.rcx = rcx;				\
	output.rflags = rflags;				\
	return output;				\
}

#define DEF_FUNC_SIGNED(name, insr, op1, op2, op3)			\
struct output_signed name(long op1, long op2, long op3)				\
{									\
	unsigned long rflags;						\
	long rax, rbx, rcx;						\
	struct output_signed output;						\
									\
	printf("%s -  input: op1 = %d, op2 = %d, op3 = %d\n",		\
		__func__, op1, op2, op3);				\
	asm volatile ("mov %4, %%rax;\n\t"				\
			"mov %5, %%rbx;\n\t"				\
			"mov %6, %%rcx;\n\t"				\
			insr "\n\t"					\
			"pushfq;\n\t"					\
			"popq %0;\n\t"					\
			"mov (%%rax), %1;\n\t"				\
			"mov %%rbx, %2;\n\t"				\
			"mov %%rcx, %3;\n\t"				\
	: "=m"(rflags), "=r"(rax), "=r"(rbx), "=r"(rcx)		\
			: "r"(&op1), "r"(op2), "r"(op3)		\
	: "rax", "rbx", "rcx");					\
									\
	printf("%s - output: *(rax) = %d, rbx = %d, rcx = %d, rflags = 0x%lx\n", \
		__func__, rax, rbx, rcx, rflags);			\
	output.rax = rax;				\
	output.rbx = rbx;				\
	output.rcx = rcx;				\
	output.rflags = rflags;				\
	return output;				\
}

DEF_FUNC_UNSIGNED(cmp_be_add, CMPBEXADD, op1, op2, op3);
DEF_FUNC_UNSIGNED(cmp_b_add, CMPBXADD, op1, op2, op3);
DEF_FUNC_SIGNED(cmp_le_add, CMPLEXADD, op1, op2, op3);
DEF_FUNC_SIGNED(cmp_l_add, CMPLXADD, op1, op2, op3);
DEF_FUNC_UNSIGNED(cmp_nbe_add, CMPNBEXADD, op1, op2, op3);
DEF_FUNC_UNSIGNED(cmp_nb_add, CMPNBXADD, op1, op2, op3);
DEF_FUNC_SIGNED(cmp_nle_add, CMPNLEXADD, op1, op2, op3);
DEF_FUNC_SIGNED(cmp_nl_add, CMPNLXADD, op1, op2, op3);
DEF_FUNC_SIGNED(cmp_no_add, CMPNOXADD, op1, op2, op3);
DEF_FUNC_SIGNED(cmp_o_add, CMPOXADD, op1, op2, op3);
DEF_FUNC_UNSIGNED(cmp_p_add, CMPPXADD, op1, op2, op3);
DEF_FUNC_UNSIGNED(cmp_np_add, CMPNPXADD, op1, op2, op3);
DEF_FUNC_SIGNED(cmp_s_add, CMPSXADD, op1, op2, op3);
DEF_FUNC_SIGNED(cmp_ns_add, CMPNSXADD, op1, op2, op3);
DEF_FUNC_UNSIGNED(cmp_z_add, CMPZXADD, op1, op2, op3);
DEF_FUNC_UNSIGNED(cmp_nz_add, CMPNZXADD, op1, op2, op3);

int cmp_target_unsigned(unsigned long rax, unsigned long rbx,
			unsigned long rcx, unsigned long rflags,
			unsigned long rax_t, unsigned long rbx_t,
			unsigned long rcx_t, unsigned long rflags_t)
{
	printf("target: *(rax) = %d, rbx = %d, rcx = %d, rflags = 0x%lx\n",
	       rax_t, rbx_t, rcx_t, rflags_t);

	if (rax == rax_t && rbx == rbx_t && rcx == rcx_t && rflags == rflags_t) {
		printf("Test passed\n\n");
	} else {
		fprintf(stderr, "Test failed\n\n");
		return 1;
	}
	return 0;
}

int cmp_target_signed(long rax, long rbx, long rcx, unsigned long rflags,
		      long rax_t, long rbx_t, long rcx_t, unsigned long rflags_t)
{
	printf("target: *(rax) = %d, rbx = %d, rcx = %d, rflags = 0x%lx\n",
	       rax_t, rbx_t, rcx_t, rflags_t);

	if (rax == rax_t && rbx == rbx_t && rcx == rcx_t && rflags == rflags_t) {
		printf("Test passed\n\n");
	} else {
		fprintf(stderr, "Test failed\n\n");
		return 1;
	}
	return 0;
}

unsigned long uop1, uop2, uop3;
long op1, op2, op3;
struct output_unsigned uoutput;
struct output_signed output;

int cmpbexadd_above(void)
{
	int ret = 0;

	uop1 = 2;
	uop2 = 1;
	uop3 = 3;
	uoutput = cmp_be_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 2, 2, 3, 0x202);
	return ret;
}

int cmpbexadd_below(void)
{
	int ret = 0;

	uop1 = 1;
	uop2 = 2;
	uop3 = 3;
	uoutput = cmp_be_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 4, 1, 3, 0x297);
	return ret;
}

int cmpbexadd_equal(void)
{
	int ret = 0;

	uop1 = 2;
	uop2 = 2;
	uop3 = 3;
	uoutput = cmp_be_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 5, 2, 3, 0x246);
	return ret;
}

int cmpbxadd_above(void)
{
	int ret = 0;

	uop1 = 2;
	uop2 = 1;
	uop3 = 3;
	uoutput = cmp_b_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 2, 2, 3, 0x202);
	return ret;
}

int cmpbxadd_below(void)
{
	int ret = 0;

	uop1 = 1;
	uop2 = 2;
	uop3 = 3;
	uoutput = cmp_b_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 4, 1, 3, 0x297);
	return ret;
}

int cmpbxadd_equal(void)
{
	int ret = 0;

	uop1 = 2;
	uop2 = 2;
	uop3 = 3;
	uoutput = cmp_b_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 2, 2, 3, 0x246);
	return ret;
}

int cmplexadd_equal(void)
{
	int ret = 0;

	op1 = -1;
	op2 = -1;
	op3 = 2;
	output = cmp_le_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx, output.rflags, 1, -1, 2, 0x246);
	return ret;
}

int cmplexadd_less(void)
{
	int ret = 0;

	op1 = -1;
	op2 = 1;
	op3 = 2;
	output = cmp_le_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx, output.rflags, 1, -1, 2, 0x282);
	return ret;
}

int cmplexadd_more(void)
{
	int ret = 0;

	op1 = -1;
	op2 = -2;
	op3 = 2;
	output = cmp_le_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx,
				output.rflags, -1, -1, 2, 0x202);
	return ret;
}

int cmplxadd_equal(void)
{
	int ret = 0;

	op1 = -1;
	op2 = -1;
	op3 = 2;
	output = cmp_l_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx,
				output.rflags, -1, -1, 2, 0x246);
	return ret;
}

int cmplxadd_less(void)
{
	int ret = 0;

	op1 = -1;
	op2 = 1;
	op3 = 2;
	output = cmp_l_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx, output.rflags, 1, -1, 2, 0x282);
	return ret;
}

int cmplxadd_more(void)
{
	int ret = 0;

	op1 = -1;
	op2 = -2;
	op3 = 2;
	output = cmp_l_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx,
				output.rflags, -1, -1, 2, 0x202);
	return ret;
}

int cmpnbexadd_above(void)
{
	int ret = 0;

	op1 = -1;
	uop1 = 2;
	uop2 = 1;
	uop3 = 3;
	uoutput = cmp_nbe_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 5, 2, 3, 0x202);
	return ret;
}

int cmpnbexadd_below(void)
{
	int ret = 0;

	uop1 = 1;
	uop2 = 2;
	uop3 = 3;
	uoutput = cmp_nbe_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 1, 1, 3, 0x297);
	return ret;
}

int cmpnbexadd_equal(void)
{
	int ret = 0;

	uop1 = 2;
	uop2 = 2;
	uop3 = 3;
	uoutput = cmp_nbe_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 2, 2, 3, 0x246);
	return ret;
}

int cmpnbxadd_above(void)
{
	int ret = 0;

	uop1 = 2;
	uop2 = 1;
	uop3 = 3;
	uoutput = cmp_nb_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 5, 2, 3, 0x202);
	return ret;
}

int cmpnbxadd_below(void)
{
	int ret = 0;

	uop1 = 1;
	uop2 = 2;
	uop3 = 3;
	uoutput = cmp_nb_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 1, 1, 3, 0x297);
	return ret;
}

int cmpnbxadd_equal(void)
{
	int ret = 0;

	uop1 = 2;
	uop2 = 2;
	uop3 = 3;
	uoutput = cmp_nb_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 5, 2, 3, 0x246);
	return ret;
}

int cmpnlexadd_equal(void)
{
	int ret = 0;

	op1 = -1;
	op2 = -1;
	op3 = 2;
	output = cmp_nle_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx,
				output.rflags, -1, -1, 2, 0x246);
	return ret;
}

int cmpnlexadd_less(void)
{
	int ret = 0;

	op1 = -1;
	op2 = 1;
	op3 = 2;
	output = cmp_nle_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx,
				output.rflags, -1, -1, 2, 0x282);
	return ret;
}

int cmpnlexadd_more(void)
{
	int ret = 0;

	op1 = -1;
	op2 = -2;
	op3 = 2;
	output = cmp_nle_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx, output.rflags, 1, -1, 2, 0x202);
	return ret;
}

int cmpnlxadd_equal(void)
{
	int ret = 0;

	op1 = -1;
	op2 = -1;
	op3 = 2;
	output = cmp_nl_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx, output.rflags, 1, -1, 2, 0x246);
	return ret;
}

int cmpnlxadd_less(void)
{
	int ret = 0;

	op1 = -1;
	op2 = 1;
	op3 = 2;
	output = cmp_nl_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx,
				output.rflags, -1, -1, 2, 0x282);
	return ret;
}

int cmpnlxadd_more(void)
{
	int ret = 0;

	op1 = -1;
	op2 = -2;
	op3 = 2;
	output = cmp_nl_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx, output.rflags, 1, -1, 2, 0x202);
	return ret;
}

int cmpnoxadd_not_overflow(void)
{
	int ret = 0;

	op1 = -1;
	op1 = -2;
	op2 = 1;
	op3 = 1;
	output = cmp_no_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx,
				output.rflags, -1, -2, 1, 0x282);
	return ret;
}

int cmpnoxadd_overflow(void)
{
	int ret = 0;

	op1 = -2;
	op2 = LONG_MAX;
	op3 = 1;
	output = cmp_no_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx,
				output.rflags, -2, -2, 1, 0xa16);
	return ret;
}

int cmpnpxadd_even(void)
{
	int ret = 0;

	uop1 = 4;
	uop2 = 1;
	uop3 = 3;
	uoutput = cmp_np_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 4, 4, 3, 0x206);
	return ret;
}

int cmpnpxadd_odd(void)
{
	int ret = 0;

	uop1 = 2;
	uop2 = 1;
	uop3 = 3;
	uoutput = cmp_np_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 5, 2, 3, 0x202);
	return ret;
}

int cmpnsxadd_negative(void)
{
	int ret = 0;

	op1 = 1;
	op2 = 2;
	op3 = 2;
	output = cmp_ns_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx, output.rflags, 1, 1, 2, 0x297);
	return ret;
}

int cmpnsxadd_positive(void)
{
	int ret = 0;

	op1 = 1;
	op2 = 1;
	op3 = 1;
	output = cmp_ns_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx, output.rflags, 2, 1, 1, 0x246);
	return ret;
}

int cmpnzxadd_not_zero(void)
{
	int ret = 0;

	uop1 = 3;
	uop2 = 2;
	uop3 = 2;
	uoutput = cmp_nz_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 5, 3, 2, 0x202);
	return ret;
}

int cmpnzxadd_zero(void)
{
	int ret = 0;

	uop1 = 2;
	uop2 = 2;
	uop3 = 2;
	uoutput = cmp_nz_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 2, 2, 2, 0x246);
	return ret;
}

int cmpoxadd_not_overflow(void)
{
	int ret = 0;

	op1 = -2;
	op2 = 1;
	op3 = 1;
	output = cmp_o_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx,
				output.rflags, -2, -2, 1, 0x282);
	return ret;
}

int cmpoxadd_overflow(void)
{
	int ret = 0;

	op1 = -2;
	op2 = LONG_MAX;
	op3 = 1;
	output = cmp_o_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx,
				output.rflags, -1, -2, 1, 0xa16);
	return ret;
}

int cmppxadd_even(void)
{
	int ret = 0;

	uop1 = 4;
	uop2 = 1;
	uop3 = 3;
	uoutput = cmp_p_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 7, 4, 3, 0x206);
	return ret;
}

int cmppxadd_odd(void)
{
	int ret = 0;

	uop1 = 2;
	uop2 = 1;
	uop3 = 3;
	uoutput = cmp_p_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 2, 2, 3, 0x202);
	return ret;
}

int cmpsxadd_negative(void)
{
	int ret = 0;

	op1 = 1;
	op2 = 2;
	op3 = 2;
	output = cmp_s_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx, output.rflags, 3, 1, 2, 0x297);
	return ret;
}

int cmpsxadd_positive(void)
{
	int ret = 0;

	op1 = 1;
	op2 = 1;
	op3 = 1;
	output = cmp_s_add(op1, op2, op3);
	ret = cmp_target_signed(output.rax, output.rbx, output.rcx, output.rflags, 1, 1, 1, 0x246);
	return ret;
}

int cmpzxadd_not_zero(void)
{
	int ret = 0;

	uop1 = 3;
	uop2 = 2;
	uop3 = 2;
	uoutput = cmp_z_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 3, 3, 2, 0x202);
	return ret;
}

int cmpzxadd_zero(void)
{
	int ret = 0;

	uop1 = 2;
	uop2 = 2;
	uop3 = 2;
	uoutput = cmp_z_add(uop1, uop2, uop3);
	ret = cmp_target_unsigned(uoutput.rax, uoutput.rbx, uoutput.rcx,
				  uoutput.rflags, 4, 2, 2, 0x246);
	return ret;
}

int main(int argc, char **argv)
{
	if (argc != 3 || strcmp(argv[1], "-t") != 0) {
		fprintf(stderr, "Usage: ./cmpccxadd -t <testcase_id>\n");
		return -1;
	}

	int ret;
	int case_id;

	case_id = atoi(argv[2]);

	switch (case_id) {
	case 1:
		ret = cmpbexadd_above();
		break;
	case 2:
		ret = cmpbexadd_below();
		break;
	case 3:
		ret = cmpbexadd_equal();
		break;
	case 4:
		ret = cmpbxadd_above();
		break;
	case 5:
		ret = cmpbxadd_below();
		break;
	case 6:
		ret = cmpbxadd_equal();
		break;
	case 7:
		ret = cmplexadd_equal();
		break;
	case 8:
		ret = cmplexadd_less();
		break;
	case 9:
		ret = cmplexadd_more();
		break;
	case 10:
		ret = cmplxadd_equal();
		break;
	case 11:
		ret = cmplxadd_less();
		break;
	case 12:
		ret = cmplxadd_more();
		break;
	case 13:
		ret = cmpnbexadd_above();
		break;
	case 14:
		ret = cmpnbexadd_below();
		break;
	case 15:
		ret = cmpnbexadd_equal();
		break;
	case 16:
		ret = cmpnbxadd_above();
		break;
	case 17:
		ret = cmpnbxadd_below();
		break;
	case 18:
		ret = cmpnbxadd_equal();
		break;
	case 19:
		ret = cmpnlexadd_equal();
		break;
	case 20:
		ret = cmpnlexadd_less();
		break;
	case 21:
		ret = cmpnlexadd_more();
		break;
	case 22:
		ret = cmpnlxadd_equal();
		break;
	case 23:
		ret = cmpnlxadd_less();
		break;
	case 24:
		ret = cmpnlxadd_more();
		break;
	case 25:
		ret = cmpnoxadd_not_overflow();
		break;
	case 26:
		ret = cmpnoxadd_overflow();
		break;
	case 27:
		ret = cmpnpxadd_even();
		break;
	case 28:
		ret = cmpnpxadd_odd();
		break;
	case 29:
		ret = cmpnsxadd_negative();
		break;
	case 30:
		ret = cmpnsxadd_positive();
		break;
	case 31:
		ret = cmpnzxadd_not_zero();
		break;
	case 32:
		ret = cmpnzxadd_zero();
		break;
	case 33:
		ret = cmpoxadd_not_overflow();
		break;
	case 34:
		ret = cmpoxadd_overflow();
		break;
	case 35:
		ret = cmppxadd_even();
		break;
	case 36:
		ret = cmppxadd_odd();
		break;
	case 37:
		ret = cmpsxadd_negative();
		break;
	case 38:
		ret = cmpsxadd_positive();
		break;
	case 39:
		ret = cmpzxadd_not_zero();
		break;
	case 40:
		ret = cmpzxadd_zero();
		break;
	default:
		fprintf(stderr, "Invalid testcase!\n");
		ret = -1;
		break;
	}
	return ret;
}
