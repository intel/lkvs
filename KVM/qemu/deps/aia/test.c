// SPDX-License-Identifier: GPL-2.0
/* Copyright(c) 2026 Intel Corporation. All rights reserved. */
/*
 * This test case checks movdir64b, movdiri and waitpkg features.
 */

#include <stdio.h>
#include <unistd.h>
#include <linux/string.h>

#include "libaia.h"

void test_movdiri(void)
{
	int dst[10] __attribute((aligned(64)));

	__attribute((aligned(64))) int data;

	if (!movdiri_supported()) {
		printf("movdiri is not supported\n");

		return;
	}
	dst[0] = 0;
	data = 1;

	movdir32(dst, data);

	printf("movdiri test passed\n");
}

void test_movdir64b(void)
{
	char src[1024], dst[1024] __attribute((aligned(64)));

	if (!movdir64b_supported()) {
		printf("movdir64b is not supported\n");

		return;
	}
	memset(src, 0, 1024);
	memset(dst, 0, 1024);
	strcpy(src, "testdata");

//	printf("before movdir64: src=%s dst=%s\n", src, dst);
	movdir64b(src, dst);
//	printf("after movdir64:\n");
//	printf("%s, %s\n", src, dst);
	if (strcmp(src, dst))
		printf("movedir64b test failed\n");
	else
		printf("movedir64b test passed\n");
}

void test_tpause(void)
{
	if (umonitor_umwait_supported()) {
		tpause(1, 1000);
		printf("tpause is supported and test passed\n");
	} else {
		printf("tpause is not supported\n");
	}
}

void test_umonitor(void)
{
	char p[1024] __attribute((aligned(64)));

	if (umonitor_umwait_supported()) {
		umonitor(p);
		printf("umonitor pass\n");
	} else {
		printf("umonitor not supported\n");
	}
}

void test_umwait(void)
{
	if (umonitor_umwait_supported()) {
		umwait(1, 1000);
		printf("umwait is supported and test passed\n");
	} else {
		printf("umwait is not supported\n");
	}
}

int main(int argc, char *argv[])
{
//	tsc();
//return;
	int i = 1;

	while (argc > i) {
		if (strcmp(argv[i], "movdiri") == 0)
			test_movdiri();
		else if (strcmp(argv[i], "movdir64b") == 0)
			test_movdir64b();
		else if (strcmp(argv[i], "tpause") == 0)
			test_tpause();
		else if (strcmp(argv[i], "umwait") == 0)
			test_umwait();
		else if (strcmp(argv[i], "umonitor") == 0)
			test_umonitor();
		i++;
	}
	return 0;
}
