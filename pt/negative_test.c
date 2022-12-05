// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2022 Intel Corporation.

#include "utils.h"

/**
 * reserved bit check :
 * ./negative_test
 *  will check to set reserved bit. if set successful, case should be fail.
 *  PASS will return 0 and FAIL will return 1
 */
int reserved_check(void)
{
	unsigned int cond = 0, stp = 0, END = 0xFFFF, FAIL = 0, result = 0;
	struct perf_event_attr attr;
	struct perf_event_mmap_page *pmp;
	int fde = -1;
	long buf_size;
	__u64 **buf_m, head;
	pid_t pid;
	char *en_trace = "en.trace";
	char *de_trace = "de.trace";
	// Set buffersize as 2 pagesize
	buf_size = 2 * PAGESIZE;
	// initial attribute for PT
	init_evt_attribute(&attr);

	attr.__reserved_1 = 1;
	attr.__reserved_2 = 1;
	pid = getpid();

	// only get trace for own pid
	fde = sys_perf_event_open(&attr, pid, -1, -1, 0);
	if (fde < 0) {
		perror("perf_event_open");
		printf("reserved set not successfully!\n");
	} else {
		printf("reserved set successfully, so case is failed! fde=%d\n", fde);
		FAIL = 1;
	}
	close(fde);
	return FAIL;
}

int main(void)
{
	int result = 0;

	result = reserved_check();
	printf("reserved set check %s\n", result ? "[FAIL] reserved set check: FAIL.\n"
		: "[PASS] reserved set check: PASS.\n");
	return result;
}
