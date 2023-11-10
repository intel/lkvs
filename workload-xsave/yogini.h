 // SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2022 Intel Corporation.
 * Len Brown <len.brown@intel.com>
 * Yi Sun <yi.sun@intel.com>
 * Dongcheng Yan <dongcheng.yan@intel.com>
 *
 */

#ifndef YOGINI_H
#define YOGINI_H
#include<string.h>
#include <pthread.h>

struct work_instance {
	struct work_instance *next;
	pthread_t thread_id;
	int thread_number;
	struct workload *workload;
	void *worker_data;
	unsigned int repeat;
	unsigned int wi_bytes;
	int break_reason;
};

struct workload {
	char *name;
	int (*initialize)(struct work_instance *wi);
	int (*cleanup)(struct work_instance *wi);
	unsigned long long (*run)(struct work_instance *wi);

	struct workload *next;
};

extern struct workload *all_workloads;

extern struct workload *register_GETCPU(void);
extern struct workload *register_RDTSC(void);
extern struct workload *register_AVX(void);
extern struct workload *register_AVX2(void);
extern struct workload *register_AVX512(void);
extern struct workload *register_VNNI512(void);
extern struct workload *register_VNNI(void);
extern struct workload *register_DOTPROD(void);
extern struct workload *register_PAUSE(void);
extern struct workload *register_TPAUSE(void);
extern struct workload *register_UMWAIT(void);
extern struct workload *register_FP64(void);
extern struct workload *register_SSE(void);
extern struct workload *register_MEM(void);
extern struct workload *register_memcpy(void);
extern struct workload *register_AMX(void);

extern unsigned int SIZE_1GB;

#ifdef YOGINI_MAIN
struct workload *(*all_register_routines[]) () = {
	register_AVX,
	register_AVX2,
	register_AVX512,
#if __GNUC__ >= 9
	register_VNNI512,
#endif
#if __GNUC__ >= 11
	register_VNNI,
#endif
	register_DOTPROD,
	register_PAUSE,
#if __GNUC__ >= 9
	register_TPAUSE,
	register_UMWAIT,
#endif
	register_RDTSC,
	register_SSE,
	register_MEM,
	register_memcpy,
	register_AMX,
	NULL
};
#endif
static inline struct workload *find_workload(char *name)
{
	struct workload *wp;

	for (wp = all_workloads; wp; wp = wp->next) {
		if (strcmp(name, wp->name) == 0)
			return wp;
	}
	printf("Can't find this workload, please retry.\n");
	return NULL;
}

static inline unsigned long long rdtsc(void)
{
	unsigned int low, high;

	asm volatile ("rdtsc" : "=a" (low), "=d"(high));

	return low | ((unsigned long long)high) << 32;
}

void clflush_range(void *address, size_t size);
extern int clfulsh;
struct cpuid {
	unsigned int avx512f;
	unsigned int vnni512;
	unsigned int avx2vnni;
	unsigned int tpause;
};

extern struct cpuid cpuid;
#endif
