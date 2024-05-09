// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2022 Intel Corporation.
/*
 * cpuid_check.c: one CPU ID check tool for script usage
 *
 * Author: Pengfei Xu <Pengfei.xu@intel.com>
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define N 32
#define M 40

int usage(char *progname)
{
	printf("%s NUM1 NUM2 NUM3 NUM4 CHAR5 NUM6\n", progname);
	printf("  NUM1: input EAX value in hex\n");
	printf("  NUM2: input EBX value in hex\n");
	printf("  NUM3: input ECX value in hex\n");
	printf("  NUM4: input EDX value in hex\n");
	printf("  CHAR5: a|b|c|d indicates the output matching EAX|EBX|ECX|EDX\n");
	printf("  NUM6: number of decimal digits in CHAR5 output register matching SPEC\n");
	printf("CET SHSTK cpuid check example:\n# %s 7 0 0 0 c 7\n", progname);
	exit(2);
}

/* cpuid checking function with assembly. */
static inline void native_cpuid(unsigned int *eax, unsigned int *ebx,
				unsigned int *ecx, unsigned int *edx)
{
	asm volatile("cpuid"
	: "=a" (*eax),
	"=b" (*ebx),
	"=c" (*ecx),
	"=d" (*edx)
	: "0" (*eax), "2" (*ecx)
	: "memory");
}

/* Convert hex to binary mode to display cpuid information. */
int h_to_b(long n)
{
	int i = 0;
	static int a[N];

	for (i = 0; i != N; ++i) {
		a[N - 1 - i] = n % 2;
		n /= 2;
	}
	for (i = 0; i != N; ++i) {
		printf("%d", a[i]);
		if ((i + 1) % 4 == 0)
			printf(" ");
	}
	printf("\n");
	return 0;
}

/* Check that the cpuid target output bits are correct. */
int check_id(long n, int ex_number)
{
	int i = 0;
	static int b[N];
	int bit_n = N - 1 - ex_number;

	for (i = 0; i != N; ++i) {
		b[N - 1 - i] = n % 2;
		n /= 2;
	}
	printf("Start with 0, pass: bit set 1, fail: bit set 0\n");
	if (b[bit_n] == 1) {
		printf("Order bit:%d, invert order:%d, bit:%d, pass!\n",
		       bit_n, ex_number, b[bit_n]);
	} else {
		printf("Order bit:%d, invert order:%d, bit:%d, fail!\n",
		       bit_n, ex_number, b[bit_n]);
		return 1;
	}
	return 0;
}

int main(int argc, char *argv[])
{
	unsigned int eax = 0, ebx = 0, ecx = 0, edx = 0;
	int ex_n, test_result = 1;
	char ex = 'e';

	if (argc == 1) {
		usage(argv[0]);
		exit(2);
	} else if (argc == 5) {
		if (sscanf(argv[1], "%x", &eax) != 1)
			usage(argv[0]);
		printf("4 parameters, eax=%d\n", eax);
		if (sscanf(argv[2], "%x", &ebx) != 1)
			usage(argv[0]);
		if (sscanf(argv[3], "%x", &ecx) != 1)
			usage(argv[0]);
		if (sscanf(argv[4], "%x", &edx) != 1)
			usage(argv[0]);
	} else if (argc == 7) {
		if (sscanf(argv[1], "%x", &eax) != 1)
			usage(argv[0]);
		printf("6 parameters, eax=%d\n", eax);
		if (sscanf(argv[2], "%x", &ebx) != 1)
			usage(argv[0]);
		if (sscanf(argv[3], "%x", &ecx) != 1)
			usage(argv[0]);
		if (sscanf(argv[4], "%x", &edx) != 1)
			usage(argv[0]);
		if (sscanf(argv[5], "%c", &ex) != 1)
			usage(argv[0]);
		if (sscanf(argv[6], "%d", &ex_n) != 1)
			usage(argv[0]);
	} else {
		if (sscanf(argv[1], "%x", &eax) != 1)
			usage(argv[0]);
		printf("Just get eax=%d\n", eax);
	}

	printf("cpuid(eax=%08x, ebx=%08x, ecx=%08x, edx=%08x)\n",
	       eax, ebx, ecx, edx);
	printf("cpuid(&eax=%p, &ebx=%p, &ecx=%p, &edx=%p)\n",
	       &eax, &ebx, &ecx, &edx);
	native_cpuid(&eax, &ebx, &ecx, &edx);
	printf("After native_cpuid:\n");
	printf("out:  eax=%08x, ebx=%08x, ecx=%08x,  edx=%08x\n",
	       eax, ebx, ecx, edx);
	printf("cpuid(&eax=%p, &ebx=%p, &ecx=%p, &edx=%p)\n",
	       &eax, &ebx, &ecx, &edx);
	printf("output:\n");
	printf("  eax=%08x    || Binary: ", eax);
	h_to_b(eax);
	printf("  ebx=%08x    || Binary: ", ebx);
	h_to_b(ebx);
	printf("  ecx=%08x    || Binary: ", ecx);
	h_to_b(ecx);
	printf("  edx=%08x    || Binary: ", edx);
	h_to_b(edx);

	printf("Now check cpuid e%cx, bit %d\n", ex, ex_n);
	if (ex == 'a') {
		test_result = check_id(eax, ex_n);
	} else if (ex == 'b') {
		test_result = check_id(ebx, ex_n);
	} else if (ex == 'c') {
		test_result = check_id(ecx, ex_n);
	} else if (ex == 'd') {
		test_result = check_id(edx, ex_n);
	} else {
		printf("No check point, not in a-d, skip.\n");
		test_result = 0;
	}

	printf("Done! Return:%d.\n\n", test_result);
	return test_result;
}
