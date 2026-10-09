// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2022 Intel Corporation.

/*
 * Basic acceptance tests for the Intel(R) Processor Trace driver.
 *
 * Ported from BAT-ipt.c of the IPT test suite in LTP-DDT.
 *
 * Author: Emmanuel Lucet <emmanuelx.lucet@intel.com>
 *         Ammy Yi <ammy.yi@intel.com>
 *
 * Usage: bat_ipt <test> <mode>
 *
 *	test 1	ToPA usage. In full trace mode the output buffer has to stop
 *		the trace once it is full, in snapshot mode it has to wrap
 *		around and keep tracing.
 *	test 3	Packet check in full trace mode, tracing the calling task.
 *	test 4	Packet check in snapshot mode, tracing the calling task.
 *	test 5	Packet check in full trace mode, repeated for every CPU.
 *
 *	mode 0	trace both privilege levels
 *	mode 1	exclude user space
 *	mode 2	exclude kernel space
 *
 * Test 2 of the original test suite covered Intel BTS, which is a separate
 * feature, so it has no counterpart here and the numbering has a hole.
 *
 * The trace is decoded with libipt. The original implementation ran the
 * ptdump binary and grepped its output, which means a search for "tip" also
 * matched the tip.pge and tip.pgd lines and a search for "tnt" matched both
 * TNT encodings. seek_tip() and seek_tnt() keep that meaning so that the
 * checks stay exactly as strong as they used to be.
 */

#define _GNU_SOURCE
#include <fcntl.h>
#include <sched.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include "utils.h"

#define MSR_IA32_RTIT_CTL	0x00000570
#define MSR_IA32_RTIT_STATUS	0x00000571

#define RTIT_CTL_TRACEEN	(1ULL << 0)
#define RTIT_STATUS_TRIGGEREN	(1ULL << 2)
#define RTIT_STATUS_STOPPED	(1ULL << 5)

#define BUF_SNAPSHOT	0
#define BUF_FULL	1

/* How to fold the per CPU status bits into one answer. */
#define AGG_ANY		0
#define AGG_ALL		1

/* Two pages only, so that the full trace buffer fills up quickly. */
#define BUF_PAGES	2

#define FILL_ROUNDS		(6 * 4 * 1024)
#define FILL_ROUNDS_USER	(16 * 4 * 1024)
#define SETTLE_ROUNDS		33

#define RESULT(fail)	((fail) ? "FAIL" : "PASS")

static void print_help(const char *name)
{
	printf("Usage: %s <test> <mode>\n", name);
	printf("  test 1  ToPA usage\n");
	printf("  test 3  packet check, full trace mode, own task\n");
	printf("  test 4  packet check, snapshot mode, own task\n");
	printf("  test 5  packet check, full trace mode, every CPU\n");
	printf("  mode 0  trace both privilege levels\n");
	printf("  mode 1  exclude user space\n");
	printf("  mode 2  exclude kernel space\n");
}

static int read_msr(int cpu, __u32 reg, __u64 *data)
{
	char path[64];
	int fd, ret = 0;

	/* An event opened on every CPU still has to be read somewhere. */
	snprintf(path, sizeof(path), "/dev/cpu/%d/msr", cpu < 0 ? 0 : cpu);
	fd = open(path, O_RDONLY);
	if (fd < 0)
		return fd;

	if (pread(fd, data, sizeof(*data), reg) != sizeof(*data))
		ret = -1;
	close(fd);

	return ret;
}

/*
 * Tell whether a status bit is set. A cpu of -1 means the event follows the
 * task around, so the bit can live on any CPU: AGG_ANY takes one CPU as
 * enough, AGG_ALL wants every CPU to agree. Returns -1 when no CPU could be
 * read at all.
 */
static int msr_bit_set(int cpu, __u32 reg, __u64 bit, int agg)
{
	int i, nproc, ret = -1;
	__u64 val;

	if (cpu >= 0) {
		if (read_msr(cpu, reg, &val))
			return -1;
		return !!(val & bit);
	}

	nproc = sysconf(_SC_NPROCESSORS_ONLN);
	for (i = 0; i < nproc; i++) {
		if (read_msr(i, reg, &val))
			continue;

		if (val & bit) {
			if (agg == AGG_ANY || ret < 0)
				ret = 1;
		} else {
			if (agg == AGG_ALL || ret < 0)
				ret = 0;
		}
	}

	return ret;
}

static int trace_en(int cpu)
{
	return msr_bit_set(cpu, MSR_IA32_RTIT_CTL, RTIT_CTL_TRACEEN, AGG_ANY);
}

static int trigger_en(int cpu)
{
	return msr_bit_set(cpu, MSR_IA32_RTIT_STATUS, RTIT_STATUS_TRIGGEREN,
			   AGG_ANY);
}

/* A trace has only stopped once it has stopped everywhere. */
static int trace_stopped(int cpu)
{
	return msr_bit_set(cpu, MSR_IA32_RTIT_STATUS, RTIT_STATUS_STOPPED,
			   AGG_ALL);
}

/*
 * Burn through a randomised number of iterations. Stepping backwards makes
 * the trip count unpredictable, so the branch predictor keeps missing and
 * the trace fills up fast. Passing a file descriptor adds a system call per
 * round, which is the only way to generate kernel side trace data.
 */
static void burn_branches(int rounds, int fd)
{
	struct stat sb;
	int i;

	for (i = 0; i < rounds; i++) {
		if (fd >= 0)
			fstat(fd, &sb);
		if (i > (int)((double)random() * rounds / RAND_MAX))
			i--;
	}
}

static void init_attr(struct perf_event_attr *attr, unsigned int mode)
{
	init_evt_attribute(attr);

	if (mode == 1)
		attr->exclude_user = 1;
	else if (mode == 2)
		attr->exclude_kernel = 1;
}

/*
 * Time the event spent running minus the time it spent enabled, or -1 when
 * the counter cannot be read. The layout follows the read_format set by
 * init_evt_attribute(): value, time enabled, time running, id.
 *
 * An event never runs for longer than it is enabled, so the difference is
 * zero or negative. As in the original test a negative difference is taken
 * for an unreadable counter, which is reported but never fatal.
 */
static long long time_gap(int fd)
{
	__u64 val[4];

	if (read(fd, val, sizeof(val)) < (ssize_t)(3 * sizeof(__u64)))
		return -1;

	return (long long)(val[2] - val[1]);
}

static int pin_to_cpu(int cpu)
{
	cpu_set_t set;

	CPU_ZERO(&set);
	CPU_SET(cpu, &set);
	if (sched_setaffinity(0, sizeof(set), &set) < 0) {
		perror("sched_setaffinity");
		printf("affinity error cpu %i\n", cpu);
		return -1;
	}

	return 0;
}

static long aux_head(__u64 **buf_m, long bufsize)
{
	struct perf_event_mmap_page *pmp;
	__u64 head;

	pmp = (struct perf_event_mmap_page *)buf_m[0];
	head = __atomic_load_n(&pmp->aux_head, __ATOMIC_ACQUIRE);

	/* The decoder must not be allowed to walk past the mapping. */
	if (head > (__u64)bufsize)
		head = bufsize;

	return (long)head;
}

/*
 * ptdump prints the two TNT encodings as tnt.8 and tnt.64 and the original
 * grep matched either of them.
 */
static int seek_tnt(__u64 *buf, long size)
{
	if (!seek_pck_w_lib(ppt_tnt_8, buf, size))
		return 0;

	return seek_pck_w_lib(ppt_tnt_64, buf, size);
}

/*
 * The original grep for "tip" also hit the tip.pge and tip.pgd lines, so any
 * packet of the TIP family counts as a match.
 */
static int seek_tip(__u64 *buf, long size)
{
	if (!seek_pck_w_lib(ppt_tip, buf, size))
		return 0;
	if (!seek_pck_w_lib(ppt_tip_pge, buf, size))
		return 0;

	return seek_pck_w_lib(ppt_tip_pgd, buf, size);
}

/*
 * A full trace starts with the packet generation enable, while a snapshot
 * keeps wrapping around so only the closing disable is left in the buffer.
 */
static int check_packets(__u64 *buf, long size, int snapshot)
{
	enum pt_packet_type edge;
	const char *edge_name;
	int fail = 0;

	edge = snapshot ? ppt_tip_pgd : ppt_tip_pge;
	edge_name = snapshot ? "tip.pgd" : "tip.pge";

	if (seek_pck_w_lib(edge, buf, size)) {
		printf("packet check %s failed\n", edge_name);
		fail = 1;
	}
	if (seek_tip(buf, size)) {
		printf("packet check tip failed\n");
		fail = 1;
	}
	if (seek_tnt(buf, size)) {
		printf("packet check tnt failed\n");
		fail = 1;
	}

	return fail;
}

/*
 * Fill the output buffer in full trace mode. Tracing has to be off by the
 * time the buffer is full. Only the trigger bit is fatal, the other two
 * status reads and the time counter are reported but tolerated, as in the
 * original test.
 */
static int topa_full(struct perf_event_attr *attr, pid_t pid, int cpu,
		     long bufsize)
{
	int fde, fdi, fail = 0;
	__u64 **buf_m;
	long long gap;

	fde = sys_perf_event_open(attr, pid, cpu, -1, 0);
	if (fde < 0) {
		perror("perf_event_open");
		printf("open event error cpu %i\n", cpu);
		return 1;
	}

	buf_m = create_map(fde, bufsize, BUF_FULL, &fdi);
	if (!buf_m || buf_m[0] == MAP_FAILED || buf_m[1] == MAP_FAILED) {
		perror("full trace create_map");
		printf("create_map error cpu %i\n", cpu);
		if (buf_m)
			del_map(buf_m, bufsize, BUF_FULL, fdi);
		close(fde);
		return 1;
	}

	ioctl(fde, PERF_EVENT_IOC_RESET);
	ioctl(fde, PERF_EVENT_IOC_ENABLE);

	burn_branches(FILL_ROUNDS, fde);
	if (attr->exclude_kernel)
		burn_branches(FILL_ROUNDS_USER, -1);
	burn_branches(SETTLE_ROUNDS, -1);

	if (trace_en(cpu))
		printf("Rk -- trace still enabled cpu %i\n", cpu);
	if (trigger_en(cpu)) {
		printf("tracing still enabled cpu %i\n", cpu);
		fail = 1;
	}
	if (!trace_stopped(cpu))
		printf("Rk -- full trace not stopped cpu %i\n", cpu);

	gap = time_gap(fde);
	if (gap < 0)
		printf("time not readable cpu %i\n", cpu);
	else if (!gap)
		printf("Rk -- full trace time counter not stopped cpu %i\n",
		       cpu);

	ioctl(fde, PERF_EVENT_IOC_DISABLE);
	del_map(buf_m, bufsize, BUF_FULL, fdi);
	close(fde);

	return fail;
}

/*
 * Same amount of work in snapshot mode. The buffer wraps around instead of
 * filling up, so tracing has to still be running afterwards and the event
 * must have run for as long as it was enabled.
 */
static int topa_snapshot(struct perf_event_attr *attr, pid_t pid, int cpu,
			 long bufsize)
{
	int fde, fdi, fail = 0;
	__u64 **buf_m;
	long long gap;

	fde = sys_perf_event_open(attr, pid, cpu, -1, 0);
	if (fde < 0) {
		perror("perf_event_open");
		printf("open event error cpu %i\n", cpu);
		return 1;
	}

	buf_m = create_map(fde, bufsize, BUF_SNAPSHOT, &fdi);
	if (!buf_m || buf_m[0] == MAP_FAILED || buf_m[1] == MAP_FAILED) {
		perror("snapshot create_map");
		printf("create_map error cpu %i\n", cpu);
		if (buf_m)
			del_map(buf_m, bufsize, BUF_SNAPSHOT, fdi);
		close(fde);
		return 1;
	}

	ioctl(fde, PERF_EVENT_IOC_RESET);
	ioctl(fde, PERF_EVENT_IOC_ENABLE);

	burn_branches(FILL_ROUNDS, -1);
	burn_branches(SETTLE_ROUNDS, -1);

	if (!trace_en(cpu)) {
		printf("trace not enabled cpu %i\n", cpu);
		fail = 1;
	}
	if (!trigger_en(cpu)) {
		printf("tracing not enabled cpu %i\n", cpu);
		fail = 1;
	}
	if (trace_stopped(cpu)) {
		printf("snapshot trace stopped cpu %i\n", cpu);
		fail = 1;
	}

	gap = time_gap(fde);
	if (gap < 0) {
		printf("time not readable cpu %i\n", cpu);
	} else if (gap) {
		printf("snapshot time counter stopped cpu %i\n", cpu);
		fail = 1;
	}

	ioctl(fde, PERF_EVENT_IOC_DISABLE);
	del_map(buf_m, bufsize, BUF_SNAPSHOT, fdi);
	close(fde);

	return fail;
}

static int topa_usage(unsigned int mode)
{
	long bufsize = BUF_PAGES * PAGESIZE;
	struct perf_event_attr attr;
	int cpu, nproc, fail = 0;

	init_attr(&attr, mode);
	nproc = sysconf(_SC_NPROCESSORS_ONLN);

	for (cpu = -1; cpu < nproc; cpu++) {
		pid_t pid = -1;

		if (cpu == -1)
			pid = getpid();
		else if (pin_to_cpu(cpu) < 0)
			continue;

		if (topa_full(&attr, pid, cpu, bufsize))
			fail = 1;
		if (topa_snapshot(&attr, pid, cpu, bufsize))
			fail = 1;
	}

	printf("ToPA usage %s\n", RESULT(fail));

	return fail;
}

/*
 * Record one trace and look for the expected packets in it. A full trace is
 * given a second of work to record, a snapshot is disabled straight away so
 * that the closing disable stays at the head of the ring buffer.
 */
static int record_and_check(struct perf_event_attr *attr, pid_t pid, int cpu,
			    int buf_mode)
{
	long bufsize = BUF_PAGES * PAGESIZE;
	int fde, fdi, fail = 0;
	__u64 **buf_m;
	long head;

	fde = sys_perf_event_open(attr, pid, cpu, -1, 0);
	if (fde < 0) {
		perror("perf_event_open");
		printf("open event error cpu %i\n", cpu);
		return 1;
	}

	buf_m = create_map(fde, bufsize, buf_mode, &fdi);
	if (!buf_m || buf_m[0] == MAP_FAILED || buf_m[1] == MAP_FAILED) {
		perror("create_map");
		printf("create_map error cpu %i\n", cpu);
		if (buf_m)
			del_map(buf_m, bufsize, buf_mode, fdi);
		close(fde);
		return 1;
	}

	ioctl(fde, PERF_EVENT_IOC_RESET);
	ioctl(fde, PERF_EVENT_IOC_ENABLE);
	if (buf_mode == BUF_FULL)
		sleep(1);
	ioctl(fde, PERF_EVENT_IOC_DISABLE);

	head = aux_head(buf_m, bufsize);
	printf("cpu = %i, buf size = %ld, head = %ld\n", cpu, bufsize, head);

	fail = check_packets(buf_m[1], head, buf_mode == BUF_SNAPSHOT);

	del_map(buf_m, bufsize, buf_mode, fdi);
	close(fde);

	return fail;
}

static int full_check(unsigned int mode)
{
	struct perf_event_attr attr;
	int fail;

	init_attr(&attr, mode);
	/* Trace the calling task wherever it runs. */
	fail = record_and_check(&attr, getpid(), -1, BUF_FULL);

	printf("Full trace packet check %s\n", RESULT(fail));

	return fail;
}

static int snapshot_check(unsigned int mode)
{
	struct perf_event_attr attr;
	int fail;

	init_attr(&attr, mode);
	fail = record_and_check(&attr, getpid(), -1, BUF_SNAPSHOT);

	printf("Snapshot packet check %s\n", RESULT(fail));

	return fail;
}

static int full_cpu_check(unsigned int mode)
{
	struct perf_event_attr attr;
	int cpu, nproc, fail = 0;

	init_attr(&attr, mode);
	nproc = sysconf(_SC_NPROCESSORS_ONLN);

	for (cpu = -1; cpu < nproc; cpu++) {
		pid_t pid = -1;

		if (cpu == -1)
			pid = getpid();
		else if (pin_to_cpu(cpu) < 0)
			continue;

		if (record_and_check(&attr, pid, cpu, BUF_FULL))
			fail = 1;
	}

	printf("Full trace per CPU packet check %s\n", RESULT(fail));

	return fail;
}

/*
 * The status bits are read through /dev/cpu/N/msr and the trace must not be
 * broken up by the scheduler, so load the msr driver and ask for the highest
 * real time priority.
 */
static int setup(void)
{
	struct sched_param param;
	struct utsname osinfo;
	int prio;

	if (system("modprobe msr") == -1)
		printf("Rk -- cannot load the msr driver\n");

	prio = sched_get_priority_max(SCHED_FIFO);
	if (sched_getparam(0, &param) < 0) {
		perror("sched_getparam");
		return -1;
	}

	param.sched_priority = prio;
	if (sched_setscheduler(0, SCHED_FIFO, &param) < 0) {
		perror("sched_setscheduler");
		return -1;
	}

	if (!uname(&osinfo))
		printf("OS: %s %s %s %s\n", osinfo.nodename, osinfo.sysname,
		       osinfo.release, osinfo.machine);

	return 0;
}

int main(int argc, char *argv[])
{
	unsigned int test, mode;
	int fail;

	if (argc != 3) {
		print_help(argv[0]);
		return 2;
	}

	test = strtoul(argv[1], NULL, 10);
	mode = strtoul(argv[2], NULL, 10);
	if (mode > 2) {
		print_help(argv[0]);
		return 2;
	}

	if (setup() < 0) {
		printf("BLOCK: cannot set the test up\n");
		return 2;
	}

	switch (test) {
	case 1:
		fail = topa_usage(mode);
		break;
	case 3:
		fail = full_check(mode);
		break;
	case 4:
		fail = snapshot_check(mode);
		break;
	case 5:
		fail = full_cpu_check(mode);
		break;
	default:
		print_help(argv[0]);
		return 2;
	}

	return fail;
}
