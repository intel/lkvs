// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2024 Intel Corporation.
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>

#define ARRAY_LEN 3000

void swap(int *a, int *b)
{
	int temp = *a;
	*a = *b;
	*b = temp;
}

size_t partition(int *a, size_t low, size_t high)
{
	int pivot = a[high];
	size_t i = low - 1;

	for (size_t j = low; j <= high - 1; j++) {
		if (a[j] < pivot) {
			i++;
			swap(&a[i], &a[j]);
		}
	}
	swap(&a[i + 1], &a[high]);
	return (i + 1);
}

static inline void start(struct timeval *tm)
{
	gettimeofday(tm, NULL);
}

static inline void stop(struct timeval *tm1, struct timeval *tm2)
{
	unsigned long long t = 1000 * (tm2->tv_sec - tm1->tv_sec) +
			       (tm2->tv_usec - tm1->tv_usec) / 1000;
	printf("%llu ms\n", t);
}

void quick_sort(int *a, size_t low, size_t high)
{
	if (low < high) {
		size_t pivot = partition(a, low, high);

		quick_sort(a, low, pivot - 1);
		quick_sort(a, pivot + 1, high);
	}
}

void sort_array(void)
{
	printf("Quick sorting array of %zu elements\n", ARRAY_LEN);
	int data[ARRAY_LEN];

	for (size_t i = 0; i < ARRAY_LEN; ++i)
		data[i] = rand();

	quick_sort(data, 0, ARRAY_LEN - 1);
}

int main(void)
{
	struct timeval tm1, tm2;

	start(&tm1);
	sort_array();
	gettimeofday(&tm2, NULL);
	stop(&tm1, &tm2);
	return 0;
}
