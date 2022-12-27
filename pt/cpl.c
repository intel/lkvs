// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2022 Intel Corporation.

#include "utils.h"

/**
 * user mode trace check :
 *  will set exclude_kernel=1, so only can get userspace trace logs
 *	PASS will return 0 and FAIL will return 1
 */
int usermodecheck(void)
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
	enum pt_packet_type c_type;
//	Set buffersize as 2 pagesize
	buf_size = 2 * PAGESIZE;
//initial attribute for PT
	init_evt_attribute(&attr);

	attr.exclude_kernel = 1;

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
	pmp = (struct perf_event_mmap_page *)buf_m[0];
	head = (*(volatile __u64 *)&pmp->aux_head);
	printf("head = %lld\n", head);

	c_type = ppt_tip;
	if (seek_pck_w_lib(c_type, buf_m[1], head) != 0) {
		printf("check address tip failed\n");
		FAIL = 1;
	}

	c_type = ppt_tip_pgd;
	if (seek_pck_w_lib(c_type, buf_m[1], head) != 0) {
		printf("check address tip.pgd failed\n");
		FAIL = 1;
	}
	c_type = ppt_tip_pge;
	if (seek_pck_w_lib(c_type, buf_m[1], head) != 0) {
		printf("check address tip.pge failed\n");
		FAIL = 1;
	}

	/* unmap and close */
	del_map(buf_m, buf_size, 1, fdi);
	close(fde);
onerror:
	printf("USER trace address check %s\n", FAIL ? "[FAIL] USER trace address check: FAIL.\n"
		: "[PASS] USER trace address check: PASS.\n");
	return FAIL;
}

/**
 * kernel mode trace check :
 *  will set exclude_user=1, so only can get kernel trace logs
 *	PASS will return 0 and FAIL will return 1
 */
int kernel_mode_check(void)
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
	enum pt_packet_type c_type;
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
	pmp = (struct perf_event_mmap_page *)buf_m[0];
	head = (*(volatile __u64 *)&pmp->aux_head);
	printf("head = %lld\n", head);

	c_type = ppt_tip;
	if (seek_pck_w_lib(c_type, buf_m[1], head) != 0) {
		printf("check address tip failed\n");
		FAIL = 1;
	}
	c_type = ppt_tip_pgd;
	if (seek_pck_w_lib(c_type, buf_m[1], head) != 0) {
		printf("check address tip.pgd failed\n");
		FAIL = 1;
	}
	c_type = ppt_tip_pge;
	if (seek_pck_w_lib(c_type, buf_m[1], head) != 0) {
		printf("check address tip.pge failed\n");
		FAIL = 1;
	}
	c_type = ppt_fup;
	if (seek_pck_w_lib(c_type, buf_m[1], head) != 0) {
		printf("check address fup failed\n");
		FAIL = 1;
	}
	/* unmap and close */
	del_map(buf_m, buf_size, 1, fdi);
	close(fde);
onerror:
	printf("KERNEL trace address check %s\n", FAIL ? "[FAIL] KERNEL trace address check: FAIL."
		: "[PASS] KERNEL trace address check: PASS.");
	return FAIL;
}

/**
 * User mode and kernel mode check
 * ./cpl 1 for user mode check
 * ./cpl 2 for kernel mode check
 */
int main(int argc, char *argv[])
{
	unsigned int CASEID;
	int result = 0;

	if (argc == 2)
		CASEID = atoi(argv[1]);
	printf("CASE ID = %d\n", CASEID);
	switch (CASEID) {
	case 1:
		result = usermodecheck();
		break;
	case 2:
		result = kernel_mode_check();
		break;
	default:
		printf("CASE ID is invalid, please input valid ID!\n");
		result = 2;
		break;
	}
	printf("CASE result = %d\n", result);
	return result;
}
