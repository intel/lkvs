// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2022 Intel Corporation.

#include "utils.h"

/**
 * psb check:
 *  will check if PSB is first package
 *	PASS will return 0 and FAIL will return 1
 */
int psbcheck(void)
{
	unsigned int cond = 0, stp = 0, END = 0xFFFF, FAIL = 0, result = 0;
	struct perf_event_attr attr;
	struct perf_event_mmap_page *pmp;
	int fde, fdi;
	long buf_size;
	__u64 **buf_m, head;
	pid_t pid;
	char *en_trace = "en.trace";
	char *de_trace = "de.trace";
	enum pt_packet_type c_type = ppt_psb;
//	Set buffersize as 2 pagesize
	buf_size = 2 * PAGESIZE;
//initial attribute for PT
	init_evt_attribute(&attr);

	attr.exclude_user = 1;

	pid = getpid();

	//only get trace for own pid
	fde = sys_perf_event_open(&attr, pid, -1, -1, 0);
	if (fde < 0) {
		perror("perf_event_open");
		FAIL = 1;
		goto onerror;
	}
	/* map event : full */

	buf_m =  create_map(fde, buf_size, 0, &fdi);

	if (!buf_m || (buf_m)[0] == MAP_FAILED || (buf_m)[1] == MAP_FAILED) {
		perror("Full Trace create_map");

		close(fde);
		FAIL = 1;
		goto onerror;
	}

	ioctl(fde, PERF_EVENT_IOC_RESET);
	ioctl(fde, PERF_EVENT_IOC_ENABLE);
	/* stop tracing */
	ioctl(fde, PERF_EVENT_IOC_DISABLE);

	printf("buf_size = %ld\n", buf_size);
	pmp = buf_m[0];
	head = (*(volatile __u64 *)&pmp->aux_head);
	printf("head = %ld\n", head);

	if (seek_pck_w_lib(c_type, buf_m[1], head) != 0) {
		printf("PSB check failed!\n");
		FAIL = 1;
	}
	/* unmap and close */
	del_map(buf_m, buf_size, 1, fdi);
	close(fde);
onerror:
	printf("psb check %s\n", FAIL ? "[FAIL] psb check: FAIL.\n"
		: "[PASS] psb check: PASS.\n");
	return FAIL;
}

/**
 * PSB package check
 * ./psb
 */
int main(void)
{
	int result = 0;

	result = psbcheck();
	printf("CASE result = %d\n", result);
	return result;
}
