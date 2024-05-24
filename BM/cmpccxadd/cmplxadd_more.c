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
#include "cmpxadd.c"
void main(void)
{
	unsigned long uop1, uop2, uop3;
	long op1, op2, op3;
	struct output_signed output;

	op1 = -1;
	op2 = -2;
	op3 = 2;
	output = cmp_l_add(op1, op2, op3);
	printf("cmp_l_add - target: *(rax) = -1, rbx = -1, rcx = 2, rflags = 0x202\n");
	if (output.rax == -1 && output.rbx == -1 && output.rcx == 2 && output.rflags == 0x202)
		printf("Test passed\n");
	else
		printf("Test failed\n");
}
