// SPDX-License-Identifier: GPL-2.0
/* Copyright(c) 2025 Intel Corporation. All rights reserved. */
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

/* Assume the system processors are less 512. and /proc/cpuinfo lines are less 64 lines.
 * This programm check the /proc/cpuinfo and compare each line of each of cpu infomation.
 * If each line of different cpu's info are same, execept bogomips, this test case PASS.
 * otherwise, it fail.
 */

#define MAX_CPU		512
#define MAX_LINE	64
#define MAX_LETTER	1024
int main(void)
{
	char *cpu_info[MAX_CPU][MAX_LINE];
	FILE *fd;
	int i, j, k, l;

	fd = fopen("/proc/cpuinfo", "r");
	if (fd == NULL) {
		perror(" Can not open file /proc/cpuinfo:");
		exit(-1);
	}
	for (i = 0; i < MAX_CPU; i++)
		for (j = 0; j < MAX_LINE; j++)
			cpu_info[i][j] = (char *)malloc(MAX_LETTER);
			if (cpu_info[i][j] == NULL) {
				perror("Malloc fail");
				return -1;
			}

	for (i = 0; !feof(fd); i++) {
		for (j = 0; fgets(cpu_info[i][j], MAX_LETTER, fd) != NULL ; j++) {
			if (strcmp(cpu_info[i][j], "\n") == 0)
				break;
		}
		if (feof(fd))
			break;
	}

	// i is the processor number, j is the lines of one processor info.
	for (l = 1; l < (j-1); l++) // don't check the last line of processor info, it is bogomips info.
		for (k = 0; k < i; k++)
			if (!strcmp(cpu_info[0][j], cpu_info[k][j])) {
				printf(" %s is different from %s\n", cpu_info[0][j], cpu_info[k][j]);
				printf("This platform have some error in SMP field\n");
				return 1;
			}

	for (k = 0; k < MAX_CPU; k++)
		for (l = 0; l < MAX_LINE; l++)
			free(cpu_info[k][l]);

	if (i <= 1) {
		printf("It is a UP system\n");
		return 1;
	}

	printf("This platform have %d processors, it is a SMP system\n", i);
	printf("PASS\n");
	fclose(fd);
	return 0;
}
