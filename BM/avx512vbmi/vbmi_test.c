// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2022 Intel Corporation.

/*
 * vbmi_test.c:  Vector Byte Manipulation Instructions
 *
 * Author: Pengfei, Xu <pengfei.xu@intel.com>
 *        - Add parameter and usage to add new instruction next
 *        - Check output binary result
 *        - Check zmm1 output relation with zmm2 and zmm3
 *        - Solved stack smashing and core dump issue after execute program
 */

/*****************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#define N 64

typedef unsigned long long al __attribute__((aligned (64)));
static unsigned long pp1[16] = {0};
static al c;

void h_to_b(unsigned long n, int bit)
{
	int i, j = 0;
	int a[bit];

	for (i = 0; i != bit; ++i) {
		a[bit - 1 - i] = n % 2;
		n /= 2;
	}
	for (i = 0; i != bit; ++i) {
		printf("%d", a[i]);
		if ((i + 1) % 4 == 0)
			printf(" ");
	}
}

static inline void vbmi(unsigned int r1, unsigned int r2)
{
	al a, b;

	a = r1;
	b = r2;
	asm volatile("vmovdqa32 %0, %%zmm2\n\t"
				 "vmovdqa32 %1, %%zmm3\n\t"
				 :
				 : "m"(a), "m"(b));

	asm volatile("vpmultishiftqb %zmm3, %zmm2, %zmm1");

	asm volatile("vmovdqa32 %%zmm1,%0" : : "m"(c));
}

void usage(void)
{
	printf("Usage: [Num1] [Num2] [b]\n");
	printf("  Num1 Hex number for zmm2\n");
	printf("  Num2 Hex number for zmm3\n");
	printf("  b    Test vbmi\n");
}

int main(int argc, char *argv[])
{
	unsigned int r1, r2, p1, i;
	char feature;

	if (argc == 4) {
		if (sscanf(argv[1], "%x", &r1) != 1) {
			printf("Invalid argv[1]: %s\n", argv[1]);
			return 2;
		}
		if (sscanf(argv[2], "%x", &r2) != 1) {
			printf("Invalid argv[2]: %s\n", argv[2]);
			return 2;
		}
		if (sscanf(argv[3], "%c", &feature) != 1) {
			printf("Invalid argv[3]: %s\n", argv[3]);
			return 2;
		}
		printf("r1(zmm2):%d, r2(zmm3):%d, feature: %c\n",
		       r1, r2, feature);
		switch (feature) {
		case 'b':
			printf("vbmi:\n");
			vbmi(r1, r2);
			pp1[0] = c;
			printf("Test vpmultishiftqb results:\n");
			printf("Result c size : %zu bytes\n", sizeof(c));

			for (i = 0; i < 4; i++) {
				printf("pp1[%d]:%-24lx|", i, pp1[i]);
				h_to_b(pp1[i], N);
				printf("\n");
			}
			break;
		default:
			usage();
			exit(1);
		}
	} else {
		usage();
		exit(1);
	}
	return 0;
}
