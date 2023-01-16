/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (c) 2022 Intel Corporation. */

/*
 * cet_ioctl.h:
 * This file is cet driver head
 *      - cet driver head file
 */

#ifndef QUERY_IOCTL_H
#define QUERY_IOCTL_H
#include <linux/ioctl.h>

#define CET_SHSTK1 _IO('q', 4)
#define CET_IBT1 _IO('q', 5)
#define CET_IBT2 _IO('q', 6)
#define CET_SHSTK_XSAVES _IO('q', 7)

#endif

#ifndef __cpuid_count
#define __cpuid_count(level, count, a, b, c, d) ({	\
	__asm__ __volatile__ ("cpuid\n\t"	\
			: "=a" (a), "=b" (b), "=c" (c), "=d" (d)	\
			: "0" (level), "2" (count));	\
})
#endif

#define CPUID_LEAF_XSTATE		0xd
#define CPUID_SUBLEAF_XSTATE_USER	0x0

#define MSR_IA32_PL3_SSP	0x000006a7 /* user shadow stack pointer */

/* The following definition is from arch/x86/include/asm/fpu/types.h */
#define XFEATURE_MASK_FP (1 << XFEATURE_FP)
#define XFEATURE_MASK_SSE (1 << XFEATURE_SSE)
#define XFEATURE_MASK_CET_USER		(1 << XFEATURE_CET_USER)

#define XFEATURE_CET_USER 11

static uint32_t get_xstate_size(void)
{
	uint32_t eax, ebx, ecx, edx;

	__cpuid_count(CPUID_LEAF_XSTATE, CPUID_SUBLEAF_XSTATE_USER, eax, ebx,
		      ecx, edx);
	/*
	 * EBX enumerates the size (in bytes) required by the XSAVE
	 * instruction for an XSAVE area containing all the user state
	 * components corresponding to bits currently set in XCR0.
	 */
	return ebx;
}
