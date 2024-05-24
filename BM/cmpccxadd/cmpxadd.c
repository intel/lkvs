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
	printf("%s - output: *(rax) = %d, rbx = %d, rcx = %d, rflags = 0x%lx\n\n", \
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
	printf("%s - output: *(rax) = %d, rbx = %d, rcx = %d, rflags = 0x%lx\n\n", \
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
