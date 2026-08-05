// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Intel Corporation.

#define _GNU_SOURCE
#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define CACHELINE 64
#define RAM_SIZE (256UL * 1024 * 1024)
#define RAM_STRIDE 4096UL
#define LOCAL_RAM_ITERS 200000UL
#define SNOOP_ITERS 200000UL
#define SNOOP_BATCH_LINES 256UL
#define MISS_EVICT_SIZE (2UL * 1024 * 1024)

enum mode_id {
	MODE_LOCAL_RAM,
	MODE_SNOOP_NA,
	MODE_SNOOP_HIT,
	MODE_SNOOP_MISS,
};

struct cacheline_u64 {
	volatile uint64_t v[CACHELINE / sizeof(uint64_t)];
} __attribute__((aligned(CACHELINE)));

struct snoop_phase {
	volatile unsigned int v;
	uint8_t pad[CACHELINE - sizeof(unsigned int)];
} __attribute__((aligned(CACHELINE)));

struct snoop_ctx {
	struct snoop_phase phase;
	struct cacheline_u64 lines[SNOOP_BATCH_LINES];
	uint8_t *evict_buf;
	int worker_cpu;
	enum mode_id mode;
	unsigned long batches;
	volatile uint64_t sink;
};

static inline void cpu_relax(void)
{
	asm volatile("pause" ::: "memory");
}

static inline void clflushopt_line(const void *ptr)
{
	asm volatile("clflushopt (%0)" : : "r"(ptr) : "memory");
}

static inline void cldemote_line(const void *ptr)
{
	asm volatile("cldemote (%0)" : : "r"(ptr) : "memory");
}

static inline void mfence_all(void)
{
	asm volatile("mfence" ::: "memory");
}

static inline unsigned int phase_load(struct snoop_phase *phase)
{
	return __atomic_load_n(&phase->v, __ATOMIC_SEQ_CST);
}

static inline void phase_store(struct snoop_phase *phase, unsigned int value)
{
	__atomic_store_n(&phase->v, value, __ATOMIC_SEQ_CST);
}

static void die_errno(const char *msg)
{
	fprintf(stderr, "%s: %s\n", msg, strerror(errno));
	exit(EXIT_FAILURE);
}

static void bind_cpu(int cpu)
{
	cpu_set_t set;

	CPU_ZERO(&set);
	CPU_SET(cpu, &set);
	if (sched_setaffinity(0, sizeof(set), &set) != 0)
		die_errno("sched_setaffinity");
}

static void *worker_thread(void *arg)
{
	struct snoop_ctx *ctx = arg;
	unsigned long i;
	volatile uint64_t tmp = 0;

	bind_cpu(ctx->worker_cpu);
	for (i = 0; i < ctx->batches; i++) {
		unsigned long j;

		while (phase_load(&ctx->phase) != 0)
			cpu_relax();
		for (j = 0; j < SNOOP_BATCH_LINES; j++)
			clflushopt_line((const void *)&ctx->lines[j].v[0]);
		mfence_all();
		for (j = 0; j < SNOOP_BATCH_LINES; j++)
			tmp += ctx->lines[j].v[0];
		if (ctx->mode == MODE_SNOOP_MISS) {
			mfence_all();
			for (j = 0; j < MISS_EVICT_SIZE; j += CACHELINE)
				tmp += ctx->evict_buf[j];
		}
		mfence_all();
		phase_store(&ctx->phase, 1);
		while (phase_load(&ctx->phase) != 2)
			cpu_relax();
		phase_store(&ctx->phase, 0);
	}
	ctx->sink = tmp;
	return NULL;
}

static void run_local_ram(int reader_cpu, unsigned long iters)
{
	uint8_t *buf;
	unsigned long i;
	volatile uint64_t sink = 0;

	bind_cpu(reader_cpu);
	if (posix_memalign((void **)&buf, CACHELINE, RAM_SIZE) != 0) {
		fprintf(stderr, "posix_memalign failed\n");
		exit(EXIT_FAILURE);
	}
	memset(buf, 0x5a, RAM_SIZE);
	mfence_all();

	for (i = 0; i < iters; i++) {
		size_t off = (i * RAM_STRIDE) & (RAM_SIZE - CACHELINE);
		volatile uint64_t *ptr = (volatile uint64_t *)(buf + off);

		clflushopt_line((const void *)ptr);
		mfence_all();
		sink += *ptr;
	}

	fprintf(stderr, "local_ram_sink=%llu\n", (unsigned long long)sink);
	free(buf);
}

static void run_snoop_mode(int reader_cpu, int worker_cpu, enum mode_id mode, unsigned long iters)
{
	struct snoop_ctx ctx;
	pthread_t worker;
	unsigned long i;
	volatile uint64_t sink = 0;

	bind_cpu(reader_cpu);
	memset(&ctx, 0, sizeof(ctx));
	ctx.worker_cpu = worker_cpu;
	ctx.mode = mode;
	ctx.batches = (iters + SNOOP_BATCH_LINES - 1) / SNOOP_BATCH_LINES;
	for (i = 0; i < SNOOP_BATCH_LINES; i++)
		ctx.lines[i].v[0] = 0x123456789abcdef0ULL + i;
	if (mode == MODE_SNOOP_HIT || mode == MODE_SNOOP_MISS) {
		if (posix_memalign((void **)&ctx.evict_buf, CACHELINE, MISS_EVICT_SIZE) != 0) {
			fprintf(stderr, "posix_memalign failed\n");
			exit(EXIT_FAILURE);
		}
		memset(ctx.evict_buf, 0xa5, MISS_EVICT_SIZE);
	}
	if (mode != MODE_SNOOP_NA) {
		if (pthread_create(&worker, NULL, worker_thread, &ctx) != 0)
			die_errno("pthread_create");
	}

	for (i = 0; i < ctx.batches; i++) {
		unsigned long j;

		if (mode == MODE_SNOOP_NA) {
			for (j = 0; j < SNOOP_BATCH_LINES; j++)
				clflushopt_line((const void *)&ctx.lines[j].v[0]);
			mfence_all();
			for (j = 0; j < SNOOP_BATCH_LINES; j++)
				sink += ctx.lines[j].v[0];
			continue;
		}

		while (phase_load(&ctx.phase) != 1)
			cpu_relax();
		for (j = 0; j < SNOOP_BATCH_LINES; j++)
			sink += ctx.lines[j].v[0];
		if (mode == MODE_SNOOP_HIT) {
			for (j = 0; j < SNOOP_BATCH_LINES; j++)
				cldemote_line((const void *)&ctx.lines[j].v[0]);
			mfence_all();
			for (j = 0; j < MISS_EVICT_SIZE; j += CACHELINE)
				sink += ctx.evict_buf[j];
		}
		for (j = 0; j < SNOOP_BATCH_LINES; j++)
			sink += ctx.lines[j].v[0];
		phase_store(&ctx.phase, 2);
		while (phase_load(&ctx.phase) != 0)
			cpu_relax();
	}

	if (mode != MODE_SNOOP_NA)
		pthread_join(worker, NULL);
	free(ctx.evict_buf);
	fprintf(stderr, "snoop_sink=%llu worker_sink=%llu\n",
		(unsigned long long)sink,
		(unsigned long long)ctx.sink);
}

static enum mode_id parse_mode(const char *arg)
{
	if (!strcmp(arg, "local-ram"))
		return MODE_LOCAL_RAM;
	if (!strcmp(arg, "snoop-na"))
		return MODE_SNOOP_NA;
	if (!strcmp(arg, "snoop-hit"))
		return MODE_SNOOP_HIT;
	if (!strcmp(arg, "snoop-miss"))
		return MODE_SNOOP_MISS;
	fprintf(stderr, "unknown mode: %s\n", arg);
	exit(EXIT_FAILURE);
}

int main(int argc, char **argv)
{
	enum mode_id mode = MODE_LOCAL_RAM;
	unsigned long iters = 0;
	int reader_cpu = 0;
	int worker_cpu = 1;
	int opt;

	while ((opt = getopt(argc, argv, "i:m:r:w:")) != -1) {
		switch (opt) {
		case 'i':
			iters = strtoul(optarg, NULL, 0);
			break;
		case 'm':
			mode = parse_mode(optarg);
			break;
		case 'r':
			reader_cpu = atoi(optarg);
			break;
		case 'w':
			worker_cpu = atoi(optarg);
			break;
		default:
			fprintf(stderr,
				"usage: %s -m <local-ram|snoop-na|snoop-hit|snoop-miss> [-r cpu] [-w cpu]\n",
				argv[0]);
			return EXIT_FAILURE;
		}
	}

	if (!iters)
		iters = mode == MODE_LOCAL_RAM ? LOCAL_RAM_ITERS : SNOOP_ITERS;

	if (reader_cpu == worker_cpu && mode != MODE_SNOOP_NA && mode != MODE_LOCAL_RAM) {
		fprintf(stderr, "reader and worker CPUs must differ\n");
		return EXIT_FAILURE;
	}

	switch (mode) {
	case MODE_LOCAL_RAM:
		run_local_ram(reader_cpu, iters);
		break;
	case MODE_SNOOP_NA:
	case MODE_SNOOP_HIT:
	case MODE_SNOOP_MISS:
		run_snoop_mode(reader_cpu, worker_cpu, mode, iters);
		break;
	}

	return EXIT_SUCCESS;
}
