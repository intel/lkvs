// SPDX-License-Identifier: GPL-2.0
// Copyright (c) 2022 Intel Corporation.

/*
 * cet_app.c
 *
 * Author: Pengfei Xu <pengfei.xu@intel.com>
 *
 * This file will test cet driver with parameters
 *      - Test CET driver app
 */

#define _GNU_SOURCE

#include <stdio.h>
#include <sys/types.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sched.h>
#include <immintrin.h>
#include <stdint.h>

#include "cet_ioctl.h"

void shstk1(int fd)
{
	printf("cet app try kernel space shstk, fd:%d\n", fd);
	if (ioctl(fd, CET_SHSTK1) == -1)
		perror("shstk return -1\n");
}

void shstk_xsaves(int fd)
{
	cpu_set_t set;

	/* Set to cpu 0 to check ssp msr easily */
	CPU_ZERO(&set);
	CPU_SET(0, &set);
	sched_setaffinity(getpid(), sizeof(set), &set);

	printf("shstk xsaves test: fd:%d\n", fd);

	if (ioctl(fd, CET_SHSTK_XSAVES) == -1)
		perror("ioctl shstk xsaves return -1\n");
}

void ibt1(int fd)
{
	printf("cet_app try kernel ibt, fd:%d\n", fd);
	if (ioctl(fd, CET_IBT1) == -1)
		perror("kernel ibt return -1\n");
}

void ibt_legal(int fd)
{
	printf("cet_app try ibt legay function in kernel, fd:%d\n", fd);
	if (ioctl(fd, CET_IBT2) == -1)
		perror("kernel ibt with legal indirect jump return -1\n");
}

int main(int argc, char *argv[])
{
	char *file_name = "/dev/cet";
	int fd = 0;
	enum {
		e_shstk1,
		e_xsaves,
		e_ibt1,
		e_ibt2
	} option;

	printf("Before open, fd:%d\n", fd);

	if (argc == 1) {
		option = e_shstk1;
	} else if (argc == 2) {
		if (strcmp(argv[1], "s1") == 0) {
			option = e_shstk1;
		} else if (strcmp(argv[1], "s2") == 0) {
			option = e_xsaves;
		} else if (strcmp(argv[1], "b1") == 0) {
			option = e_ibt1;
		} else if (strcmp(argv[1], "b2") == 0) {
			option = e_ibt2;
		} else {
			fprintf(stderr, "Usage:\n%s [s1 | b1]\n", argv[0]);
			fprintf(stderr, "  s1 shstk1: trigger shstk violation in driver\n");
			fprintf(stderr, "  s2 shstk1: xsaves and rdmsr check in ring 0\n");
			fprintf(stderr, "  b1 ibt1: trigger ibt violation in driver\n");
			fprintf(stderr, "  b2 ibt2: trigger ibt legacy way in driver\n");
			return 1;
		}
	} else {
		fprintf(stderr, "Usage: %s [s1 | b1]\n", argv[0]);
		return 1;
	}
	fd = open(file_name, O_RDWR);
	if (fd == -1) {
		perror(file_name);
		return 2;
	}

	printf("fd:%d\n", fd);
	switch (option) {
	case e_shstk1:
		shstk1(fd);
		break;
	case e_xsaves:
		shstk_xsaves(fd);
		break;
	case e_ibt1:
		ibt1(fd);
		break;
	case e_ibt2:
		ibt_legal(fd);
		break;
	default:
		break;
	}

	close(fd);

	return 0;
}
