// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2022 Intel Corporation.

#include "utils.h"

/**
 * non privilege full/snapshot trace check :
 *  will set exclude_kernel=1 and run as non privilege to check if we can get trace
 *	PASS will return 0 and FAIL will return 1
 */
int non_pri_test(int mode)
{
	unsigned int FAIL = 0;
	struct perf_event_attr attr = {};
	struct perf_event_mmap_page *pmp;
	int fde, fdi;
	long buf_size;
	__u64 **buf_m = NULL, head;

//	Set buffersize as 2 pagesize
	buf_size = 2 * PAGESIZE;
//initial attribute for PT
	init_evt_attribute(&attr);

	attr.exclude_kernel = 1;

	//only get trace for own pid
	fde = sys_perf_event_open(&attr, 0, -1, -1, 0);
	if (fde < 0) {
		perror("perf_event_open");
		FAIL = 1;
		goto onerror;
	}
	/* map event : full */
	if (mode == 1) {
		printf("full trace\n");
		buf_m =  create_map(fde, buf_size, 1, &fdi);
	}
	if (mode == 2) {
		printf("snapshot trace\n");
		buf_m =  create_map(fde, buf_size, 0, &fdi);
	}

	if (!buf_m || (buf_m)[0] == MAP_FAILED || (buf_m)[1] == MAP_FAILED) {
		perror("Full Trace create_map");

		close(fde);
		FAIL = 1;
		goto onerror;
	}

	/* enable tracing */
	if (ioctl(fde, PERF_EVENT_IOC_RESET) != 0) {
		printf("ioctl with PERF_EVENT_IOC_RESET is failed!\n");
		FAIL = 1;
	}
	if (ioctl(fde, PERF_EVENT_IOC_ENABLE) != 0) {
		printf("ioctl with PERF_EVENT_IOC_ENABLE is failed!\n");
		FAIL = 1;
	}

	/* stop tracing */
	if (ioctl(fde, PERF_EVENT_IOC_DISABLE) != 0) {
		printf("ioctl with PERF_EVENT_IOC_DISABLE is failed!\n");
		FAIL = 1;
	}

	printf("buf_size = %ld\n", buf_size);
	pmp = (struct perf_event_mmap_page *)buf_m[0];
	head = (*(volatile __u64 *)&pmp->aux_head);
	printf("head = %lld\n", head);
	if (head == 0) {
		FAIL = 1;
		printf("No trace generated!\n");
	}

	/* unmap and close */
	del_map(buf_m, buf_size, 1, fdi);
	close(fde);
onerror:
	printf("non privilege trace check %s\n", FAIL ? "[FAIL] non privilege trace check: FAIL.\n"
		: "[PASS] non privilege trace check: PASS.\n");
	return FAIL;
}

/**
 * non privilege test :
 *  ./nonroot_test 1
 *  Non root user do full trace check.
 *  ./nonroot_test 2
 *  Non root user do snapshot trace check.
 *	Will check if non privilege can get trace with full mode and snapshot mode
 *	PASS will return 0 and FAIL will return 1
 *	If skip case will return 2
 *  CASE ID=1 for full; CASE ID=2 for snapshot
 */
int main(int argc, char *argv[])
{
	int CASEID;
	int result = 0;
	//full trace mode = 1, snapshot mode = 2
	int mode = 0;

	if (argc == 2)
		CASEID = atoi(argv[1]);
	printf("CASE ID = %d\n", CASEID);

	switch (CASEID) {
	case 1:
		mode = 1;
		result = non_pri_test(mode);
		break;
	case 2:
		mode = 2;
		result = non_pri_test(mode);
		break;
	default:
		printf("CASE ID is invalid, please input valid ID!\n");
		result = 2;
		break;
	}
	printf("CASE result = %d\n", result);
	return result;
}
