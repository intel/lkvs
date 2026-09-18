// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Copyright (C) 2019 Intel Corporation
 * Author: Pengfei, Xu <pengfei.xu@intel.com>
 */

/*
 * It's for CPU XSAVE tests, which could verify CPU support XSAVE
 * instruction or not, and check all support XSAVE features
 *
 */

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <linux/types.h>
#include "xsave_list.h"

#define ALIGN(x, a)	(((x) + (a) - 1) & ~((a) - 1))
#define TMUL_XSTATE			18
#define TMUL_EXPANDED_SIZE	576


static int linux_xsave_size, tmul_xsave_size, sum_size, align_size, xstate_num,
			max_size;
static u64 xfeatures_mask_all;

void usage(char *progname)
{
	printf("Usage: %s NUM1 NUM2\n", progname);
	printf("  NUM1: xstate id\n");
	printf("  NUM2: xstate id expected size\n");
}

/*
 * We spell it out in here for xsave xfeature names
 */
static const char * const xfeature_names[] = {
	"x87 floating point registers & SSE registers",
	"XSAVE header",
	"AVX registers",
	"MPX bounds registers",
	"MPX CSR",
	"AVX-512 opmask",
	"AVX-512 Hi256",
	"AVX-512 ZMM_Hi256",
	"Processor Trace (unused)",
	"Protection Keys User registers",
	"PASID state",
	"Control-flow User registers",
	"Control-flow Kernel registers",
	"Reserved Component (13)",
	"Reserved Component (14)",
	"Reserved Component (15)",
	"Reserved Component (16)",
	"AMX TILE config",
	"AMX TILE data",
	"unknown xstate feature",
};

static inline void cpuid_count(u32 id, u32 count,
		u32 *a, u32 *b, u32 *c, u32 *d)
{
	asm volatile(".ifnc %%ebx,%3; movl %%ebx,%3; .endif\n\t"
		     "cpuid\n\t"
		     ".ifnc %%ebx,%3; xchgl %%ebx,%3; .endif\n\t"
		    : "=a" (*a), "=c" (*c), "=d" (*d), "=b" (*b)
		    : "a" (id), "c" (count)
	);
}

static int xfeature_is_aligned(int xfeature_nr)
{
	u32 eax, ebx, ecx, edx;

	cpuid_count(XSTATE_CPUID, xfeature_nr, &eax, &ebx, &ecx, &edx);
	/*
	 * The value returned by ECX value 2(binary 10) indicates the alignment
	 * of state component 'i' when the compacted format
	 * of the extended region of an XSAVE area is used
	 */
	return !!(ecx & 2);
}

static int xfeature_is_supervisor(int xfeature_nr)
{
	u32 eax, ebx, ecx, edx;

	cpuid_count(XSTATE_CPUID, xfeature_nr, &eax, &ebx, &ecx, &edx);
	/*
	 * The value returned by ECX value 1(binary 1) indicates that state
	 * component 'i' is supported in the IA32_XSS MSR, which means that this
	 * xstate is supervisor xstate
	 */
	return !!(ecx & 1);
}

static void xstate_dump_leaves(void)
{
	int i;
	u32 eax, ebx, ecx, edx;

	printf("Dump this CPU XSAVE related CPUID as below:\n");
	/*
	 * Dump out a few leaves past the ones that we support
	 * just in case there are some goodies up there
	 */
	for (i = 0; i < XFEATURE_MAX + 10; i++) {
		cpuid_count(XSTATE_CPUID, i, &eax, &ebx, &ecx, &edx);
		printf("CPUID[%02x,%02x]:eax=%08x ebx=%08x ecx=%08x edx=%08x\n",
			XSTATE_CPUID, i, eax, ebx, ecx, edx);
	}
}

u64 fpu_get_supported_xfeatures_mask(void)
{
	return SUPPORTED_XFEATURES_MASK_USER |
	       SUPPORTED_XFEATURES_MASK_SUPERVISOR;
}

void xfeature_name(u64 xfeature_idx, const char **feature_name)
{
	*feature_name = xfeature_names[xfeature_idx];
}

static unsigned int get_xfeature_size(int ecx)
{
	unsigned int eax, ebx, edx;

	cpuid_count(XSTATE_CPUID, ecx, &eax, &ebx, &ecx, &edx);
	return eax;
}

static unsigned int get_xfeature_offset(int ecx)
{
	unsigned int eax, ebx, edx;

	cpuid_count(XSTATE_CPUID, ecx, &eax, &ebx, &ecx, &edx);
	return ebx;
}

static void print_xstate_feature(u32 xstate_mask)
{
	const char *feature_name;
	int xfeature_size = 0, is_aligned = 0, xfeature_offset;

	xfeature_name(xstate_mask, &feature_name);
	is_aligned = xfeature_is_aligned(xstate_mask);
	if (xstate_mask == 0) {
		xfeature_size = 512;
		xfeature_offset = 0;
		max_size = xfeature_size;
	} else if (xstate_mask == 1) {
		xfeature_size = 64;
		xfeature_offset = 512;
	} else {
		xfeature_size = get_xfeature_size(xstate_mask);
		xfeature_offset = get_xfeature_offset(xstate_mask);
	}

	sum_size = xfeature_size + sum_size;
	align_size = max_size;

	if (is_aligned)
		align_size = ALIGN(align_size, 64);

	if (!xfeature_is_supervisor(xstate_mask))
		align_size = align_size + xfeature_size;

	if (xfeature_offset)
		max_size = xfeature_offset + xfeature_size;

	printf("XSAVE 0x%02x| %4d |  %d  | %4d |   %4d   | %4d | %4d |'%s'\n",
		xstate_mask, xfeature_size, is_aligned,
		sum_size, align_size, xfeature_offset, max_size, feature_name);
	linux_xsave_size = align_size;
	/* TMUL xstate will create one more 576 bytes for TMUL expanded area*/
	if (xstate_mask == TMUL_XSTATE)
		tmul_xsave_size = linux_xsave_size + TMUL_EXPANDED_SIZE;
}

int cpu_support_xstate_list(void)
{
	unsigned int eax, ebx, ecx, edx, bit_check = 0x4000000, i = 0;

	// Verify this CPU could support XSAVE instructions
	cpuid_count(1, 0, &eax, &ebx, &ecx, &edx);
	if (!(ecx & bit_check)) {
		printf("CPU could not support XSAVE instructions, exit.\n");
		return 1;
	}
	cpuid_count(XSTATE_CPUID, 0, &eax, &ebx, &ecx, &edx);
	xfeatures_mask_all = eax + ((u64)edx << 32);
	printf("cpu id 7 0 0 0, eax | edx, xfeatures_mask_all:%lx\n",
		xfeatures_mask_all);

	cpuid_count(XSTATE_CPUID, 1, &eax, &ebx, &ecx, &edx);
	xfeatures_mask_all |= ecx + ((u64)edx << 32);
	printf("With cpu id 7 0 1 0, ecx | edx, xfeatures_mask_all:%lx\n",
		xfeatures_mask_all);

	xfeatures_mask_all &= fpu_get_supported_xfeatures_mask();
	printf("After check FPU support, xfeatures_mask_all:%lx\n",
		xfeatures_mask_all);
	printf("Align for CPUID(EAX=0DH, ECX=xfeature_id):ECX[bit 2].\n");

	printf("XSAVE 0xID| Size |Align| Sum  |Align_size|Offset| total|'feature'\n");
	for (i = 0; i < XFEATURE_MAX; i++) {
		if (!(xfeatures_mask_all & (1 << i)))
			continue;
		xstate_num++;
		print_xstate_feature(i);
	}
	return 0;
}

static int xfeature_enabled(unsigned int xfeature)
{
	return !!(xfeatures_mask_all & (1UL << xfeature));
}

int xstate_size_verify(int xfeature_id, int xstate_exp_size)
{
	unsigned int eax, ebx, ecx, edx, xfeature_size = 0;

	cpu_support_xstate_list();
	if (xfeature_enabled(xfeature_id))
		printf("CPU could support decimal xstate %d\n", xfeature_id);
	else {
		printf("CPU can not support decimal xstate %d\n", xfeature_id);
		exit(2);
	}
	cpuid_count(XSTATE_CPUID, xfeature_id, &eax, &ebx, &ecx, &edx);
	xfeature_size = eax;
	if (xfeature_size == xstate_exp_size) {
		printf("RESULTS:xstate id %d size is as expected:%d\n",
			xfeature_id, xfeature_size);
	} else {
		printf("RESULTS:xstate id %d actual size:%d, expected:%d\n",
			xfeature_id, xfeature_size, xstate_exp_size);
		exit(1);
	}
}

int main(int argc, char *argv[])
{
	unsigned int eax, ebx, ecx, edx, cpu_xsave_size, cpu_max_xsave_size;
	int xstate_id, xstate_id_size;
	char *endp;

	if (argc == 1)
		usage(argv[0]);
	else if (argc == 3) {
		xstate_id = (int)strtol(argv[1], &endp, 10);
		if (*endp != '\0') {
			printf("Invalid xstate_id:%s\n", argv[1]);
			usage(argv[0]);
			exit(2);
		}
		xstate_id_size = (int)strtol(argv[2], &endp, 10);
		if (*endp != '\0') {
			printf("Invalid xstate_id_size:%s\n", argv[2]);
			usage(argv[0]);
			exit(2);
		}
		printf("Will verify xstate id:%d, size should be:%d\n",
			xstate_id, xstate_id_size);
		xstate_size_verify(xstate_id, xstate_id_size);
		exit(0);
	} else {
		usage(argv[0]);
		exit(2);
	}

	cpuid_count(XSTATE_CPUID, 1, &eax, &ebx, &ecx, &edx);
	cpu_xsave_size = ebx;

	cpuid_count(XSTATE_CPUID, 0, &eax, &ebx, &ecx, &edx);
	cpu_max_xsave_size = ebx;

	cpu_support_xstate_list();
	printf("This CPU supports above %d parts xstates.\n", xstate_num);
	printf("XSAVE size:CPUID.(0xd,0x1) EBX;  max:CPUID.(0xd,0x0) EBX\n");
	printf("CPUID XSAVE size:0d%d(0x%x), max:0d%d, linux_xsave_size:0d%d\n",
		cpu_xsave_size, cpu_xsave_size, cpu_max_xsave_size,
		linux_xsave_size);
	if (cpu_xsave_size != linux_xsave_size)
		printf("WARN:cpu_xsave_size:%d not equal to linux:%d, max:%d\n",
			cpu_xsave_size, linux_xsave_size, cpu_max_xsave_size);
	if (tmul_xsave_size > 0)
		printf("TMUL XSAVE SIZE:0d%d\n", tmul_xsave_size);
	xstate_dump_leaves();
	return 0;
}
