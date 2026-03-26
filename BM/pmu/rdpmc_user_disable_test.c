// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Intel Corporation.

#define LINUX
#define _GNU_SOURCE
#include <unistd.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/fcntl.h>
#include <sys/ioctl.h>
#include <linux/perf_event.h>
#include <stdint.h>
#include <stdlib.h>
#include <asm/unistd.h>
#include <signal.h>
#include <string.h>
#include <sched.h>

typedef unsigned long long u64;
int pagesize;

// Read memory barrier
#define rmb()   asm volatile("" ::: "memory")

struct cpu {
	int fd;
	struct perf_event_mmap_page *buf;
};

int perf_open(struct cpu *ctx, int cpu, unsigned int counter, int pid)
{
	int ret;

	struct perf_event_attr attr = {
		.type = PERF_TYPE_RAW,
		.size = sizeof(struct perf_event_attr),
		.config = counter,
		.sample_type = PERF_SAMPLE_READ,
		.precise_ip = 0,
	};

	ctx->buf = NULL;
	ctx->fd = syscall(__NR_perf_event_open, &attr, pid, cpu, -1, 0);
	if (ctx->fd < 0) {
		printf("Failed to open event 0x%x err %d\n", counter, ctx->fd);
		return -1;
	}

	ctx->buf = mmap(NULL, pagesize, PROT_READ, MAP_SHARED, ctx->fd, 0);
	if (ctx->buf == MAP_FAILED) {
		close(ctx->fd);
		printf("Failed to mmap event 0x%x\n", counter);
		return -1;
	}

	ret = ioctl(ctx->fd, PERF_EVENT_IOC_ENABLE, 0);
	if (ret < 0) {
		printf("Failed to enable event 0x%x\n", counter);
		return -1;
	}

	return 0;
}

void perf_close(struct cpu *ctx)
{
	close(ctx->fd);
	if (ctx->buf)
		munmap(ctx->buf, pagesize);
}

unsigned long long perf_read(struct cpu *ctx)
{
	u64 val;
	unsigned int seq;
	u64 offset;
	typeof(ctx->buf) buf = ctx->buf;

	do {
		seq = buf->lock;
		/* Pairs with the rmb below in perf_read */
		rmb();
		/* XXX fallback */
		val = __builtin_ia32_rdpmc(buf->index - 1);
		offset = buf->offset;
		/* Pairs with the rmb above in perf_read */
		rmb();
	} while (buf->lock != seq);
	return val;
}

void gp_fault_handler(int sig, siginfo_t *si, void *unused)
{
	printf("Receive and handle #GP fault\n");
	exit(-2);
}

int main(int argc, const char **argv)
{
	struct sigaction sa;
	cpu_set_t cpuset;
	struct cpu cpu;
	unsigned int counter;
	u64 count;
	int cpuid;
	int pid;
	int ret;

	if (argc != 4) {
		printf("Usage: %s <cpuid> <system | process> <gp | fixed>\n", argv[0]);
		return -1;
	}

	if (!strncmp(argv[2], "system", 6))
		pid = -1;
	else if (!strncmp(argv[2], "process", 7))
		pid = 0;
	else {
		printf("Usage: %s <cpuid> <system | process> <gp | fixed>\n", argv[0]);
		return -1;
	}

	if (!strncmp(argv[3], "gp", 6))
		counter = 0xc4;	/* branches */
	else if (!strncmp(argv[3], "fixed", 5))
		counter = 0xc0;	/* instructions */
	else {
		printf("Usage: %s <cpuid> <system | process> <gp | fixed>\n", argv[0]);
		return -1;
	}

	cpuid = atoi(argv[1]);

	sa.sa_flags = SA_SIGINFO;
	sigemptyset(&sa.sa_mask);
	sa.sa_sigaction = gp_fault_handler;

	if (sigaction(SIGSEGV, &sa, NULL) == -1) {
		printf("Fail to set the #GP handler\n");
		return -1;
	}

	CPU_ZERO(&cpuset);
	CPU_SET(cpuid, &cpuset);
	if (sched_setaffinity(0, sizeof(cpu_set_t), &cpuset) == -1) {
		printf("Fail to bind the program to cpu %d\n", cpuid);
		return -1;
	}

	pagesize = sysconf(_SC_PAGESIZE);

	/* open & enable event */
	ret = perf_open(&cpu, cpuid, counter, pid);
	if (ret < 0)
		goto err;

	/* do something here */
	sleep(1);

	/* read event */
	count = perf_read(&cpu);

	/* disable event */
	ret = ioctl(cpu.fd, PERF_EVENT_IOC_DISABLE, 0);
	if (ret < 0) {
		printf("Failed to disable event 0x%x\n", counter);
		goto err;
	}

	/* close event */
	perf_close(&cpu);

	printf("CPU %d - %s %s event (0x%x) count %lld\n",
	       cpuid, argv[2], argv[3], counter, count);

	return count;

err:
	printf("rdpmc-user-disable test case: CPU %d - %s %s event (0x%x) FAIL!\n",
	       cpuid, argv[2], argv[3], counter);
	return -1;
}
