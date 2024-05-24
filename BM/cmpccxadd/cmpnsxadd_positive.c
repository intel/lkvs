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

	uop1 = 1;
	uop2 = 1;
	uop3 = 1;
	output = cmp_ns_add(uop1, uop2, uop3);
	printf("cmp_ns_add - target: *(rax) = 2, rbx = 1, rcx = 1, rflags = 0x246\n");
	if (output.rax == 2 && output.rbx == 1 && output.rcx == 1 && output.rflags == 0x246)
		printf("Test passed\n");
	else
		printf("Test failed\n");
}
