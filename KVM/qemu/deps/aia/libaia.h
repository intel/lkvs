/* SPDX-License-Identifier: GPL-2.0 */
/* Copyright(c) 2026 Intel Corporation. All rights reserved. */
/*
 * This test case checks movdir64b, movdiri and waitpkg features.
 */

#ifndef LIBAIA_H
#define LIBAIA_H

#include <stdbool.h>

/* CPUID.07H.0H:ECX.DIRSTR[bit 27] */
#define MOVDIRI_BIT		27
/* CPUID.07H.0H:ECX.DIRSTR64B[bit 28] */
#define MOVDIR64B_BIT		28

/* CPUID.07H:ECX[5] */
#define UMONITOR_UMWAIT_BIT	5

/*
 * Move 32-bit data into memory using direct store.
 */
void movdir32(int *dst, int data)
{
	/*
	 * According to calling convention for i386 and AMD64 Linux
	 * user-level applications, p is stored in edi and a is stored in esi.
	 * So the direct memory move instruction is:
	 *  movdiri esi, [edi]
	 */
	asm volatile(".byte 0x48, 0x0f, 0x38, 0xf9, 0x02"
		     :
		     : "a" (data), "d" (dst));
}

/*
 * Move 64 bytes from memory to memory as direct store.
 */
void movdir64b(char *dst, char *src)
{
	/*
	 * According to calling convention for AMD64 Linux
	 * user-level applications, p is stored in rdi and a is stored in rsi.
	 * So the direct 64 bytes direct store instruction is:
	 * movdir64b [rsi], rdi
	 */
	asm volatile(".byte 0x66, 0x0f, 0x38, 0xf8, 0x02"
		     :
		     : "a" (src), "d" (dst));
}

inline void cpuid(void)
{
	int eax, ebx, ecx, edx;

	asm volatile("mov $5, %%eax\t\n"
		     "cpuid\t\n"
		      : "=a" (eax), "=b" (ebx), "=c" (ecx), "=d" (edx)
		     :);
}

bool movdiri_supported(void)
{
	int eax, ebx, ecx, edx;

	asm volatile("mov $7, %%eax\t\n"
		     "mov $0, %%ecx\t\n"
		     "cpuid\t\n"
		     : "=a" (eax), "=b" (ebx), "=c" (ecx), "=d" (edx));

	return ecx & (1 << MOVDIRI_BIT);
}

unsigned long tsc_freq;

bool get_tsc_freq(void)
{
	int eax, ebx, ecx, edx;

	asm volatile("mov $15, %%eax\t\n"
		     "cpuid\t\n"
		     : "=a" (eax), "=b" (ebx), "=c" (ecx), "=d" (edx));
	if (ebx == 0 || ecx == 0)
		return -1;

	tsc_freq = ecx * ebx / eax;

	return 0;
}

int nsec_to_tsc(unsigned long nsec, unsigned long *tsc)
{
	if (tsc_freq <= 0)
		return -1;

	*tsc = tsc_freq * nsec / 1000000000;

	return 0;
}

bool movdir64b_supported(void)
{
	int eax, ebx, ecx, edx;

	asm volatile("mov $7, %%eax\t\n"
		     "mov $0, %%ecx\t\n"
		     "cpuid\t\n"
		     : "=a" (eax), "=b" (ebx), "=c" (ecx), "=d" (edx));

	return ecx & (1 << MOVDIR64B_BIT);
}

bool umonitor_umwait_supported(void)
{
	int eax, ebx, ecx, edx;

	asm volatile("mov $7, %%eax\t\n"
		     "mov $0, %%ecx\t\n"
		     "cpuid\t\n"
		      : "=a"(eax), "=b" (ebx), "=c" (ecx), "=d" (edx));

	return ecx & (1 << UMONITOR_UMWAIT_BIT);
}

void umonitor(char *addr)
{
	asm volatile(".byte 0xf3, 0x0f, 0xae, 0xf7\t\n"
			  :
		      : "rdi" (addr));
}

void _umwait(int state, unsigned long eax, unsigned long edx)
{
	asm volatile("mov %%esi, %%eax\t\n"
		     ".byte 0xf2, 0x0f, 0xae, 0xf7\t\n"
		     :
		     :);
}

void umwait(int state, unsigned long nsec)
{
	unsigned long tsc;
	int err;

	err = nsec_to_tsc(nsec, &tsc);
	if (err)
		tsc = 0;

	_umwait(state, tsc >> 32, tsc & 0xffffffff);
}

void _tpause(int state, unsigned long eax, unsigned long edx)
{
	asm volatile("mov %%esi, %%eax\n\t"
			 ".byte 0x66, 0x0f, 0xae, 0xf7\n\t"
			 :
			 :);
}

void tpause(int state, unsigned long nsec)
{
	unsigned long tsc;
	int err;

	err = nsec_to_tsc(nsec, &tsc);
	if (err)
		tsc = 0;

	_tpause(state, tsc >> 32, tsc & 0xffffffff);
}

#endif
