// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2022 Intel Corporation.
 * Len Brown <len.brown@intel.com>
 * Yi Sun <yi.sun@intel.com>
 *
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <err.h>
#include <unistd.h>
#include <signal.h>
#include <stdlib.h>
#include <getopt.h>
#include <string.h>
#include <time.h>
#include <cpuid.h>
#include <math.h>
#include <pthread.h>
#include <sys/syscall.h>
#include <linux/futex.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <x86intrin.h>
#define YOGINI_MAIN
#include "yogini.h"

enum {
	BREAK_BY_NOTHING = 0,
	BREAK_BY_YIELD = 1,
	BREAK_BY_SLEEP,
	BREAK_BY_TRAP,
	BREAK_BY_SIGNAL,
	BREAK_BY_FUTEX,
	BREAK_REASON_MAX = BREAK_BY_FUTEX
} BREAK_REASON;
#define FUTEX_VAL 0x5E5E5E5E

int repeat_cnt;
int clfulsh;
char *progname;
struct workload *all_workloads;
struct work_instance *first_worker;
struct work_instance *last_worker;

static int num_worker_threads;
static int num_checked_in_threads;
static pthread_mutex_t checkin_mutex;
static pthread_cond_t checkin_cv = PTHREAD_COND_INITIALIZER;
int32_t break_reason = BREAK_BY_NOTHING;
static int32_t *futex_ptr;
static bool *thread_done;
pthread_t *tid_ptr;

unsigned int SIZE_1GB = 1024 * 1024 * 1024;

struct cpuid cpuid;

static void dump_command(int argc, char **argv)
{
	int i;

	for (i = 0; i < argc; i++)
		printf("%s ", argv[i]);

	putchar('\n');
}

void dump_workloads(void)
{
	struct workload *wp;

	for (wp = all_workloads; wp; wp = wp->next)
		fprintf(stderr, " %s", wp->name);

	fprintf(stderr, "\n");
}

static void help(void)
{
	fprintf(stderr,
		"usage: %s [OPTIONS]\n"
		"\n"
		"%s runs some simple micro workloads\n"
		"  -w, --workload [workload_name,threads#,break#, ...]\n", progname, progname);
	fprintf(stderr, "Available workloads: ");
	dump_workloads();
	fprintf(stderr,
		"  -r, --repeat, each instance needs to be run\n"
		"  -b, --break_reason, [yield/sleep/trap/signal/futex]\n"
		"For more help, see README\n");
	exit(0);
}

int parse_break_cmd(char *input_string)
{
	if (strcmp(input_string, "sleep") == 0)
		break_reason = BREAK_BY_SLEEP;
	else if (strcmp(input_string, "yield") == 0)
		break_reason = BREAK_BY_YIELD;
	else if (strcmp(input_string, "trap") == 0)
		break_reason = BREAK_BY_TRAP;
	else if (strcmp(input_string, "signal") == 0)
		break_reason = BREAK_BY_SIGNAL;
	else if (strcmp(input_string, "futex") == 0)
		break_reason = BREAK_BY_FUTEX;
	else
		return -1;
	return 0;
}

static void set_tsc_per_sec(void)
{
	unsigned int ebx = 0, ecx = 0, edx = 0;
	unsigned int max_level;

	__cpuid(0, max_level, ebx, ecx, edx);

	/* Structured Extended Feature Flags Enumeration Leaf */
	if (max_level >= 0x7) {
		unsigned int eax_subleaves;

		eax_subleaves = 0;
		ecx = 0;
		edx = 0;

		__cpuid_count(0x7, 0, eax_subleaves, ebx, ecx, edx);

		if (ebx & (1 << 16))
			cpuid.avx512f = 1;
		if (ecx & (1 << 5))
			cpuid.tpause = 1;
		if (ecx & (1 << 11))
			cpuid.vnni512 = 1;

		if (eax_subleaves > 0) {
			unsigned int eax = 0;

			eax = ebx = ecx = edx = 0;
			__cpuid_count(0x7, 1, eax, ebx, ecx, edx);
			if (eax & (1 << 4))
				cpuid.avx2vnni = 1;
		}
	}

	if (max_level < 0x15)
		errx(1, "sorry CPU too old: cpuid level 0x%x < 0x15", max_level);
}

void register_all_workloads(void)
{
	int i;
	struct workload *wp;

	for (i = 0; all_register_routines[i]; ++i) {
		wp = all_register_routines[i] ();

		if (!wp)
			continue;

		wp->next = all_workloads;
		all_workloads = wp;
	}
}

struct work_instance *alloc_new_work_instance(void)
{
	struct work_instance *wi;

	wi = calloc(1, sizeof(struct work_instance));
	if (!wi)
		err(1, "work_instance");

	wi->workload = all_workloads;	/* default workload is last probed */
	return wi;
}

void register_new_worker(struct work_instance *wi)
{
	if (!first_worker)
		first_worker = wi;
	else
		last_worker->next = wi;
	last_worker = wi;

	wi->next = NULL;
}

int parse_work_cmd(char *work_cmd)
{
	struct work_instance *wi;
	struct workload *wp;

	wp = find_workload(work_cmd);
	if (wp) {
		wi = alloc_new_work_instance();
		wi->workload = wp;
	} else {
		fprintf(stderr, "Unrecognized work parameter '%s' try -h for help\n", work_cmd);
		exit(1);
	}

	/* register this work_instance */
	register_new_worker(wi);
	return 0;
}

static void initial_ptr(void)
{
	futex_ptr = (int32_t *)malloc(sizeof(int32_t) * num_worker_threads);
	thread_done = (bool *)malloc(sizeof(bool) * num_worker_threads);
	tid_ptr = (pthread_t *)malloc(sizeof(pthread_t) * num_worker_threads);
	if (!futex_ptr || !thread_done || !tid_ptr) {
		printf("Fail to malloc memory for futex_ptr & tid_ptr\n");
		exit(1);
	}
}

static void initial_wi(void)
{
	struct work_instance *wi;

	wi = first_worker;
	while (wi) {
		wi->break_reason = break_reason;
		wi->wi_bytes = SIZE_1GB;
		wi->repeat = repeat_cnt;
		wi = wi->next;
		num_worker_threads++;
	}
}

static void deinitialize(void)
{
	struct work_instance *wi;
	struct work_instance *cur;

	wi = first_worker;
	while (wi) {
		cur = wi->next;
		free(wi);
		wi = cur;
	}

	free(futex_ptr);
	free(thread_done);
	free(tid_ptr);
}

static void cmdline(int argc, char **argv)
{
	int opt;
	int option_index = 0;
	static struct option long_options[] = {
		{ "help", no_argument, 0, 'h' },
		{ "work", required_argument, 0, 'w' },
		{ "repeat", required_argument, 0, 'r' },
		{ "break_reason", required_argument, 0, 'b' },
		{"clflush", no_argument, 0, 'f'},
		{ 0, 0, 0, 0 }
	};

	progname = argv[0];

	while ((opt = getopt_long_only(argc, argv, "h:w:r:b:f",
	       long_options, &option_index)) != -1) {
		switch (opt) {
		case 'h':
			help();
			break;
		case 'w':
			if (parse_work_cmd(optarg))
				help();
			break;
		case 'r':
			repeat_cnt = atoi(optarg);
			break;
		case 'b':
			if (parse_break_cmd(optarg))
				help();
			break;
		case 'f':
			clfulsh = 1;
			break;
		default:
			help();
		}
	}

	dump_command(argc, argv);
}

static void initialize(int argc, char **argv)
{
	set_tsc_per_sec();
	register_all_workloads();
	cmdline(argc, argv);
	initial_wi();
	initial_ptr();
}

void clflush_range(void *address, size_t size)
{
	uintptr_t start = (uintptr_t)address;
	uintptr_t end = start + size;

	// Align according to the size of the cache line.
	uintptr_t aligned_start = (start & ~(63UL));
	uintptr_t aligned_end = (end + 63UL) & ~(63UL);

	for (uintptr_t addr = aligned_start; addr < aligned_end; addr += 64)
		_mm_clflush((void *)addr);

	// Ensure clearing of unaligned portions.
	for (uintptr_t addr = aligned_end; addr < end; addr++)
		_mm_clflush((void *)addr);
}

static uint64_t do_syscall(uint64_t nr, uint64_t rdi, uint64_t rsi, uint64_t rdx,
			   uint64_t r10, uint64_t r8, uint64_t r9)
{
	uint64_t rtn;

	asm volatile("movq %0, %%rdi" : : "r"(rdi) : "%rdi");
	asm volatile("movq %0, %%rsi" : : "r"(rsi) : "%rsi");
	asm volatile("movq %0, %%rdx" : : "r"(rdx) : "%rdx");
	asm volatile("movq %0, %%r10" : : "r"(r10) : "%r10");
	asm volatile("movq %0, %%r8" : : "r"(r8) : "%r8");
	asm volatile("movq %0, %%r9" : : "r"(r9) : "%r9");
	asm volatile("syscall"
		     : "=a" (rtn)
		     : "a" (nr)
		     : "rcx", "r11", "memory", "cc");

	return rtn;
}

static void signal_handler(int32_t signum)
{
	//int32_t current_cpu = sched_getcpu();

	//if (signum == SIGTRAP)
		//printf("Break by trap, current_cpu=%d\n", current_cpu);

	//if (signum == SIGUSR1)
		//printf("Break by signal, current_cpu=%d\n", current_cpu);
}

void thread_break(int32_t reason, uint32_t thread_idx)
{
	struct timespec req;

	switch (reason) {
	case BREAK_BY_YIELD:
		/*
		 * Schedule out current thread by executing syscall
		 * instruction with syscall number SYS_sched_yield
		 */
		do_syscall(SYS_sched_yield, 0, 0, 0, 0, 0, 0);
		break;
	case BREAK_BY_SLEEP:
		/*
		 * Schedule out current thread by executing syscall
		 * instruction with syscall number SYS_nanosleep
		 */
		req.tv_sec = 1;
		req.tv_nsec = 0;
		do_syscall(SYS_nanosleep, (uint64_t)&req, 0, 0, 0, 0, 0);
		break;
	case BREAK_BY_TRAP:
		/*
		 * Trap is handled by the thread generated the trap,
		 * Schedule out current thread by trap handling
		 */
		asm volatile("int3;");
		break;
	case BREAK_BY_SIGNAL:
		/*
		 * Do nothing, main thread send SIGUSR1 to sub thread periodically
		 * Schedule out current thread by signal handling
		 */
		break;
	case BREAK_BY_FUTEX:
		/* Schedule out current thread by waiting futex */
		do_syscall(SYS_futex, (uint64_t)&futex_ptr[thread_idx],
			   FUTEX_WAIT, FUTEX_VAL, 0, 0, 0);
		break;
	}
}

static void worker_barrier(void)
{
	int i_am_last = 0;

	pthread_mutex_lock(&checkin_mutex);

	num_checked_in_threads += 1;
	if (num_checked_in_threads == num_worker_threads)
		i_am_last = 1;

	pthread_mutex_unlock(&checkin_mutex);

	if (i_am_last) {
		pthread_cond_broadcast(&checkin_cv);
	} else {
		/* wait for all workers to checkin */
		pthread_mutex_lock(&checkin_mutex);
		while (num_checked_in_threads < num_worker_threads)
			if (pthread_cond_wait(&checkin_cv, &checkin_mutex))
				err(1, "cond_wait: checkin_cv");
		pthread_mutex_unlock(&checkin_mutex);
	}
}

static void *worker_main(void *arg)
{
	// cpu_set_t mask;
	// CPU_ZERO(&mask);
	// CPU_SET(1, &mask);
	// pthread_setaffinity_np(pthread_self(), sizeof(mask), &mask);
	struct work_instance *wi = (struct work_instance *)arg;

	/* initialize data for this worker */
	if (wi->workload->initialize)
		wi->workload->initialize(wi);

	worker_barrier();

	printf("%s will repeat %u in reason %d\n",
	       wi->workload->name, wi->repeat, wi->break_reason);

	unsigned long long bgntsc, endtsc;

	bgntsc = rdtsc();
	endtsc = wi->workload->run(wi);
	printf("Thread %d:%s took %llu clock-cycles, end in %llu.\n",
	       wi->thread_number, wi->workload->name, endtsc - bgntsc, endtsc);

	/* cleanup data for this worker */
	if (wi->workload->cleanup)
		wi->workload->cleanup(wi);

	thread_done[wi->thread_number] = true;
	pthread_exit((void *)0);
	/* thread exit */
}

static void start_and_wait_for_workers(void)
{
	int i;
	cpu_set_t mask;
	struct work_instance *wi;
	struct sigaction sigact;
	bool all_thread_done = false;

	CPU_ZERO(&mask);
	CPU_SET(0, &mask);
	pthread_setaffinity_np(pthread_self(), sizeof(mask), &mask);

	if (break_reason == BREAK_BY_TRAP) {
		sigact.sa_handler = signal_handler;
		sigemptyset(&sigact.sa_mask);
		sigact.sa_flags = 0;
		sigaction(SIGTRAP, &sigact, NULL);
	}

	if (break_reason == BREAK_BY_SIGNAL) {
		sigact.sa_handler = signal_handler;
		sigemptyset(&sigact.sa_mask);
		sigact.sa_flags = 0;
		sigaction(SIGUSR1, &sigact, NULL);
	}

	/* create workers */
	for (wi = first_worker, i = 0; !wi; wi = wi->next, i++) {
		futex_ptr[i] = FUTEX_VAL;
		thread_done[i] = false;
		wi->thread_number = i;
		pthread_attr_t attr;

		pthread_attr_init(&attr);
		pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_JOINABLE);

		if (pthread_create(&tid_ptr[i], &attr, &worker_main, wi) != 0)
			err(1, "pthread_create");

		wi->thread_id = tid_ptr[i];
	}

	sleep(1);

	if (break_reason == BREAK_BY_SIGNAL) {
		while (!all_thread_done) {
			all_thread_done = true;
			for (i = 0; i < num_worker_threads; i++) {
				if (!thread_done[i]) {
					pthread_kill(tid_ptr[i], SIGUSR1);
					all_thread_done = false;
					/*
					 * wait 0.5 second to prevent from
					 * sending signal too frequently
					 */
					usleep(1);
				}
			}
		}
	}

	/* Wake up the sub-thread waiting on a futex */
	if (break_reason == BREAK_BY_FUTEX) {
		while (!all_thread_done) {
			all_thread_done = true;
			for (i = 0; i < num_worker_threads; i++) {
				if (!thread_done[i]) {
					syscall(SYS_futex, &futex_ptr[i], FUTEX_WAKE, 1, 0, 0, 0);
					all_thread_done = false;
					/* wait 0.5 second to prevent from printing too much */
					usleep(1);
				}
			}
		}
	}

	/* wait for all workers to join */
	for (wi = first_worker, i = 0; !wi; wi = wi->next, ++i)
		if (pthread_join(tid_ptr[i], NULL) != 0)
			err(0, "thread %ld failed to join\n", wi->thread_id);
}

int main(int argc, char **argv)
{
	initialize(argc, argv);
	start_and_wait_for_workers();
	deinitialize();
}
