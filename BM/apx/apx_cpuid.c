// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2024 Intel Corporation.

/*
 * apx_cpuid.c - Validate APX CPUID enumeration.
 *
 * Checks:
 *   1. CPUID.(EAX=7, ECX=1):EDX[21] - APX feature flag
 *   2. CPUID.(EAX=0Dh, ECX=19) - APX XSAVE state info (size=128, offset, alignment)
 *   3. XCR0[19] - OS has enabled APX state saving
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <cpuid.h>

typedef uint32_t u32;
typedef uint64_t u64;

#include "../common/kselftest.h"

#define NUM_TESTS	4

static inline u64 xgetbv(u32 index)
{
	u32 eax, edx;

	asm volatile("xgetbv" : "=a"(eax), "=d"(edx) : "c"(index));
	return ((u64)edx << 32) | eax;
}

int main(void)
{
	u32 eax, ebx, ecx, edx;
	u64 xcr0;

	ksft_print_header();
	ksft_set_plan(NUM_TESTS);

	/* Test 1: APX feature bit in CPUID */
	__cpuid_count(7, 1, eax, ebx, ecx, edx);
	if (edx & (1U << 21))
		ksft_test_result_pass("CPUID.7.1:EDX[21] APX feature present\n");
	else
		ksft_test_result_fail("CPUID.7.1:EDX[21] APX feature NOT present\n");

	/* Test 2: XSAVE support prerequisite */
	__cpuid_count(1, 0, eax, ebx, ecx, edx);
	if ((ecx & (1U << 26)) && (ecx & (1U << 27)))
		ksft_test_result_pass("XSAVE/OSXSAVE supported and enabled\n");
	else
		ksft_test_result_skip("XSAVE/OSXSAVE not available\n");

	/* Test 3: XCR0 bit 19 - OS enabled APX state */
	xcr0 = xgetbv(0);
	if (xcr0 & (1ULL << 19))
		ksft_test_result_pass("XCR0[19] APX state enabled by OS\n");
	else
		ksft_test_result_fail("XCR0[19] APX state NOT enabled (xcr0=0x%llx)\n",
				      (unsigned long long)xcr0);

	/* Test 4: APX XSAVE area properties via CPUID.(0Dh, 19) */
	__cpuid_count(0xD, 19, eax, ebx, ecx, edx);
	if (eax == 128 && ebx > 0)
		ksft_test_result_pass("CPUID.0D.19: size=%u offset=%u (expected 128B)\n",
				      eax, ebx);
	else
		ksft_test_result_fail("CPUID.0D.19: size=%u offset=%u (expected size=128)\n",
				      eax, ebx);

	ksft_finished();
	return 0;
}
