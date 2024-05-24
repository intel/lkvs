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

	uop1 = 4;
	uop2 = 1;
	uop3 = 3;
	output = cmp_np_add(uop1, uop2, uop3);
	printf("cmp_np_add - target: *(rax) = 4, rbx = 4, rcx = 3, rflags = 0x206\n");
	if (output.rax == 4 && output.rbx == 4 && output.rcx == 3 && output.rflags == 0x206)
		printf("Test passed\n");
	else
		printf("Test failed\n");
}
