// SPDX-License-Identifier: GPL-2.0
/* Copyright(c) 2025 Intel Corporation. All rights reserved. */
/*
 * This test case set affinity through system call in SMP system.
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
# define DEBUG(fmt, args...)    printf("%s: " fmt "\n", __func__, ## args)
#else
# define DEBUG(args...)
#endif

#define PROCFS_PATH "/proc/"
#define CPUINFO_PATH "/proc/cpuinfo"
#define CPU_NAME "processor"
#define STAT_NAME "stat"

int get_current_cpu(pid_t pid)
{
	int cpu = -1;
	int da;
	char str[100];
	char ch;
	char buf[256];
	FILE *pfile;

	sprintf(buf, "%s%d/%s%c", PROCFS_PATH, pid, STAT_NAME, 0);

	pfile = fopen(buf, "r");
	if (!pfile)
		return -1;

	if (fscanf(pfile, "%d %s %c %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d",
		&da, str, &ch, &da, &da, &da, &da, &da, &da, &da,
		&da, &da, &da, &da, &da, &da, &da, &da, &da, &da,
		&da, &da, &da, &da, &da, &da, &da, &da, &da, &da,
		&da, &da, &da, &da, &da, &da, &da, &da, &cpu) <= 0) {
		fclose(pfile);
		return -1;
	}

	fclose(pfile);
	return cpu;
}

int get_cpu_count(void)
{
	FILE *pfile;
	int count;

	char buf[256];

	pfile = fopen(CPUINFO_PATH, "r");
	if (!pfile)
		return 0;

	count = 0;

	while (fgets(buf, 255, pfile)) {
		if (strncmp(buf, CPU_NAME, strlen(CPU_NAME)) == 0)
			count++;
	}

	fclose(pfile);
	return count;
}

int smp_setaffinity(void)
{
	cpu_set_t mask;
	pid_t pid;
	int result = 1;
	int cpu_count, i, j, k, cpuid;

	pid = getpid();

	DEBUG("Set affinity through system call.\n");

	cpu_count = get_cpu_count();
	if (cpu_count == 0)
		return 0;
	else if (cpu_count > 32)
		cpu_count = 32;

	for (i = 0; i < cpu_count; i++) {
		DEBUG("Set test process affinity.");
		CPU_ZERO(&mask);
		//for (j=0; j < i; j++)
			//CPU_SET(j, &mask);
		CPU_SET(i, &mask);
		sched_setaffinity(pid, sizeof(cpu_set_t), &mask);

		for (k = 0; k < 2; k++) {
			if (fork() == 0) {
				system("ps > /dev/null");
				exit(0);
			}
			sleep(1);
			if (get_current_cpu(pid) != i)
				break;
		}

		if (k < 2) {
			DEBUG("...Error\n");
			result = 0;
		} else {
			DEBUG("...OK\n");
		}
	}

	for (i = 0; i < cpu_count - 1; i++) {
		DEBUG("Set test process affinity.");
		CPU_ZERO(&mask);
		//for (j=0; j < i; j++)
			//CPU_SET(j+1, &mask);
		CPU_SET(i + 1, &mask);
		sched_setaffinity(pid, sizeof(cpu_set_t), &mask);

		for (k = 0; k < 2; k++) {
			if (fork() == 0) {
				system("ps > /dev/null");
				exit(0);
			}

			sleep(1);
			cpuid = get_current_cpu(pid);
			if (cpuid != i && cpuid != i + 1)
				break;
		}

		if (k < 2) {
			DEBUG("...Error\n");
			result = 0;
		} else {
			DEBUG("...OK\n");
		}
	}

	if (result)
		return 1;
	else
		return 0;
}

// return 0 means Pass, return 1 means Fail
int main(int argc, char *argv[])
{
	DEBUG("start: SMP processor affinity testing\n");

	if (smp_setaffinity())
		printf("System call setaffinity() test PASS.\n");
	else
		printf("System call setaffinity() test FAIL");

	DEBUG("End: SMP processor affinity\n");

	return 0;
}
