// SPDX-License-Identifier: GPL-2.0
/* Copyright(c) 2025 Intel Corporation. All rights reserved. */
/*
 * Test inherit affinity from parent process in SMP system.
 */

#define _GNU_SOURCE
#include <sys/syscall.h>
#include <sys/types.h>
#include <linux/unistd.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <sched.h>

#ifdef _DEBUG
# define DEBUG(fmt, args...)    printf("%s: " fmt "\n", __func__, ## args)
#else
# define DEBUG(args...)
#endif

#define PROCFS_PATH "/proc/"
#define CPUINFO_PATH "/proc/cpuinfo"
#define CPU_NAME "processor"
#define STAT_NAME "stat"

// return 0 means Pass, return 1 means Fail
int smp_inheritaffinity(void)
{
	cpu_set_t mask, mask2;
	unsigned long bitmask = 0, bitmask2 = 0;
	pid_t pid;
	int status;
	int i, nrcpus;

	CPU_ZERO(&mask);
	CPU_SET(0, &mask);
	CPU_SET(1, &mask);
	pid = getpid();
	nrcpus = sysconf(_SC_NPROCESSORS_CONF);

	DEBUG("Inherit affinity from parent process.\n");

	sched_setaffinity(pid, sizeof(cpu_set_t), &mask);
	for (i = 0; i < nrcpus; i++) {
		if (CPU_ISSET(i, &mask)) {
			bitmask |= 0x01UL << i;
			DEBUG("processor #%d is set\n", i);
		}
	}
	DEBUG("bitmask = %#lx\n", bitmask);
	sleep(1);

	pid = fork();
	if (pid == 0) {
		sleep(1);

		CPU_ZERO(&mask2);
		sched_getaffinity(pid, sizeof(cpu_set_t), &mask2);
		for (i = 0; i < nrcpus; i++) {
			if (CPU_ISSET(i, &mask2)) {
				bitmask2 |= 0x01UL << i;
				DEBUG("processor #%d is set\n", i);
			}
		}
		DEBUG("bitmask2 = %#lx\n", bitmask2);
		if (bitmask == bitmask2)
			exit(0);
		exit(1);
	}

	wait(&status);
	if (WEXITSTATUS(status)) {
		printf("fail\n");
		return 1;
	}
	return 0;
}

// return 0 means Pass, return 1 means Fail
int main(int argc, char *argv[])
{
	DEBUG("start: SMP processor affinity testing\n");

	if (!smp_inheritaffinity())
		printf("Inheritance of affinity test PASS.\n");
	else
		printf("Inheritance of affinity test FAIL\n");

	DEBUG("End: SMP processor affinity\n");

	return 0;
}
