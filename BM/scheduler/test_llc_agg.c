// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Intel Corporation.
#define _GNU_SOURCE
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

#ifndef NTHREADS
#define NTHREADS 28
#endif
#define ARRAY_SIZE (1024 * 1024)  /* 4MB shared - fits in LLC */
static int shared_array[ARRAY_SIZE];

void *worker(void *arg)
{
	int id = *(int *)arg;

	while (1) {
		for (int i = id * (ARRAY_SIZE / NTHREADS);
		     i < (id + 1) * (ARRAY_SIZE / NTHREADS); i++)
			shared_array[i]++;
	}
	return NULL;
}

int main(void)
{
	pthread_t threads[NTHREADS];
	int ids[NTHREADS];

	printf("PID: %d\n", getpid());
	for (int i = 0; i < NTHREADS; i++) {
		ids[i] = i;
		pthread_create(&threads[i], NULL, worker, &ids[i]);
	}
	sleep(300);
	return 0;
}
