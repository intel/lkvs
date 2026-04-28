/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (c) 2026 Intel Corporation */

#ifndef BUS_LOCK_COMMON_H
#define BUS_LOCK_COMMON_H

#define CPUID_80000006_ECX_CACHE_LINE_SIZE 0x000000FF

static inline void do_cpuid(int leaf, int subleaf, int *eax, int *ebx,
			    int *ecx, int *edx)
{
	asm volatile("cpuid"
		 : "=a" (*eax),
		   "=b" (*ebx),
		   "=c" (*ecx),
		   "=d" (*edx)
		 : "0" (leaf), "2" (subleaf)
		 : "memory");
}

static inline void locked_add_1(int *ptr)
{
	asm volatile("lock; addl $1,%0\n\t"
		 : "+m"(*ptr)
		 :
		 : "memory");
}

static inline int get_cache_line_size_cpuid(void)
{
	int eax, ecx;

	do_cpuid(0x80000006, 0, &eax, &eax, &ecx, &eax);
	return ecx & CPUID_80000006_ECX_CACHE_LINE_SIZE;
}

#endif
