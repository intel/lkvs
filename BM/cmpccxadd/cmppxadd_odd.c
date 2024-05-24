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
	struct output_unsigned output;

	uop1 = 2;
	uop2 = 1;
	uop3 = 3;
	output = cmp_p_add(uop1, uop2, uop3);
	printf("cmp_p_add - target: *(rax) = 2, rbx = 2, rcx = 3, rflags = 0x202\n");
	if (output.rax == 2 && output.rbx == 2 && output.rcx == 3 && output.rflags == 0x202)
		printf("Test passed\n");
	else
		printf("Test failed\n");
}
