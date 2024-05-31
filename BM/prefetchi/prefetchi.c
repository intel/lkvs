// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2024 Intel Corporation.

#include <stdio.h>
#include <stdint.h>
#include "../common/kselftest.h"

#define CPUID_LEAF7_EDX_PREFETCHI_MASK	(1 << 14) /* PREFETCHI instructions */

static void check_cpuid_prefetchi(void)
{
	uint32_t eax, ebx, ecx, edx;

	/*
	 * CPUID.(EAX=07H, ECX=01H).EDX.PREFETCHI[bit 14] enumerates
	 * support for PREFETCHIT0/1 instructions.
	 */
	__cpuid_count(7, 1, eax, ebx, ecx, edx);
	if (!(edx & CPUID_LEAF7_EDX_PREFETCHI_MASK))
		printf("cpuid: CPU doesn't support PREFETCHIT0/1.\n");
	else
		printf("Test passed\n");
}

int main(void)
{
	check_cpuid_prefetchi();
	return 0;
}
