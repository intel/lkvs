// SPDX-License-Identifier: GPL-2.0
/* Copyright(c) 2025 Intel Corporation. All rights reserved. */
/*
 * This test case get affinity through system call in SMP system.
 */

#define _GNU_SOURCE
#include <sys/syscall.h>
#include <sys/types.h>
#include <linux/unistd.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sched.h>

#ifdef _DEBUG
#define DEBUG(fmt, args...)    printf("%s: " fmt "\n", __func__, ## args)
#else
#define DEBUG(args...)
#endif

#define PROCFS_PATH "/proc/"
#define CPUINFO_PATH "/proc/cpuinfo"
#define CPU_NAME "processor"
#define STAT_NAME "stat"

int smp_getaffinity(void)
{
	cpu_set_t mask, mask2;
	pid_t pid;
	unsigned long bitmask = 0, bitmask2 = 0;
	int i, nrcpus;

	pid = 0;

	DEBUG("Get affinity through system call.\n");

	nrcpus = sysconf(_SC_NPROCESSORS_CONF);
	CPU_ZERO(&mask);
	CPU_SET(0, &mask);
	CPU_SET(1, &mask);
	sched_setaffinity(pid, sizeof(cpu_set_t), &mask);
	for (i = 0; i < nrcpus; i++) {
		if (CPU_ISSET(i, &mask)) {
			bitmask |= 0x01UL << i;
			DEBUG("processor #%d is set\n", i);
		}
	}
	DEBUG("bitmask = %#lx\n", bitmask);

	sleep(1);

	CPU_ZERO(&mask2);
	sched_getaffinity(pid, sizeof(cpu_set_t), &mask2);
	DEBUG("get affinity pid %d mask %ul\n", pid, mask2);

	for (i = 0; i < nrcpus; i++) {
		if (CPU_ISSET(i, &mask2)) {
			bitmask2 |= 0x01UL << i;
			DEBUG("processor #%d is set\n", i);
		}
	}
	DEBUG("bitmask2 = %#lx\n", bitmask2);

	if (bitmask == bitmask2) {
		CPU_ZERO(&mask);
		CPU_SET(0, &mask);
		CPU_SET(1, &mask);
		CPU_SET(2, &mask);
		sched_setaffinity(pid, sizeof(cpu_set_t), &mask);
		for (i = 0; i < nrcpus; i++) {
			if (CPU_ISSET(i, &mask)) {
				bitmask |= 0x01UL << i;
				DEBUG("processor #%d is set\n", i);
			}
		}
		DEBUG("bitmask = %#lx\n", bitmask);

		sleep(1);

		CPU_ZERO(&mask2);
		sched_getaffinity(pid, sizeof(cpu_set_t), &mask2);
		DEBUG("get affinity pid %d mask %ul\n", pid, mask2);
		for (i = 0; i < nrcpus; i++) {
			if (CPU_ISSET(i, &mask2)) {
				bitmask2 |= 0x01UL << i;
				DEBUG("processor #%d is set\n", i);
			}
		}
		DEBUG("bitmask2 = %#lx\n", bitmask2);

		if (bitmask == bitmask2)
			return 1;
		else
			return 0;
	} else {
		return 0;
	}
}

// return 0 means Pass, return 1 means Fail
int main(int argc, char *argv[])
{
	DEBUG("start: SMP processor affinity testing\n");
	if (smp_getaffinity())
		printf("System call getaffinity() test PASS.\n");
	else
		printf("System call getaffinity() test FAIL.\n");

	DEBUG("End: SMP processor affinity\n");

	return 0;
}
