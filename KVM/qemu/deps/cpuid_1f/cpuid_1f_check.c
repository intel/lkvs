// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Intel Corporation

/*
 * cpuid_1f_check.c - Validate CPUID leaf 0x1F (V2 Extended Topology Enumeration)
 *
 * Uses the highest valid CPUID 0x1F sub-leaf to get logical CPUs per package,
 * then checks it is consistent with sysconf(_SC_NPROCESSORS_CONF).
 */

#include <stdio.h>
#include <unistd.h>

static inline void cpuid(unsigned int leaf, unsigned int sub_leaf,
						 unsigned int *eax, unsigned int *ebx,
						 unsigned int *ecx, unsigned int *edx)
{
	__asm__ __volatile__("cpuid"
						 : "=a"(*eax), "=b"(*ebx), "=c"(*ecx), "=d"(*edx)
						 : "a"(leaf), "c"(sub_leaf));
}

int main(void)
{
	unsigned int eax, ebx, ecx, edx;
	unsigned int sub_leaf = 0;
	unsigned int cpus_per_pkg = 0;
	int found_valid = 0;

	while (1) {
		cpuid(0x1f, sub_leaf, &eax, &ebx, &ecx, &edx);

		/* ECX[15:08]: Level type. 0 means invalid - end of enumeration */
		unsigned int level_type = (ecx >> 8) & 0xff;

		if (level_type == 0)
			break;

		found_valid = 1;
		/*
		 * EBX[15:0]: Number of logical processors within the next
		 * higher-scoped domain. The highest valid level gives
		 * logical CPUs per package.
		 */
		cpus_per_pkg = ebx & 0xffff;
		sub_leaf++;
	}

	if (!found_valid) {
		printf("FAIL: CPUID leaf 0x1F not supported (no valid sub-leaves)\n");
		return 1;
	}

	long total_cpus = sysconf(_SC_NPROCESSORS_CONF);

	if (total_cpus < 0) {
		printf("FAIL: sysconf(_SC_NPROCESSORS_CONF) failed\n");
		return 1;
	}

	if (cpus_per_pkg == 0) {
		printf("FAIL: CPUID 0x1F reported 0 CPUs per package\n");
		return 1;
	}

	/*
	 * Verify topology consistency: total CPUs should be evenly
	 * divisible by CPUs-per-package
	 */
	if ((unsigned int)total_cpus % cpus_per_pkg != 0) {
		printf("FAIL: Topology inconsistent: total %ld CPUs not divisible by %u CPUs/pkg\n",
		       total_cpus, cpus_per_pkg);
		return 1;
	}

	unsigned int num_pkgs = (unsigned int)total_cpus / cpus_per_pkg;

	printf("PASS: CPUID 0x1F topology consistent: %u CPUs/pkg * %u pkg(s) = %ld total\n",
	       cpus_per_pkg, num_pkgs, total_cpus);
	return 0;
}
