// SPDX-License-Identifier: GPL-2.0
/*
 *Verify Shadow Stack performance impact on specific CPU
 *
 *  Author: Pengfei Xu <pengfei.xu@intel.com>
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>
#include <unistd.h>
#include <sched.h>

void shstk2(void)
{
	unsigned long *j;

	#ifdef __x86_64__
		asm("movq %%rbx,%0" : "=r"(j));
	#else

		asm("mov %%ebp,%0" : "=r"(j));
	#endif
}

void shstk1(void)
{
	unsigned long *i;

	#ifdef __x86_64__
		asm("movq %%rbx,%0" : "=r"(i));
	#else
		asm("mov %%ebp,%0" : "=r"(i));
	#endif
	shstk2();
}

int main(int argc, char *argv[])
{
	int x = 100000000, a, cpu;
	clock_t tstart, tend;
	cpu_set_t set;

	if (argc >= 2) {
		cpu = atoi(argv[1]);
	} else {
		cpu = 0;
		printf("There is no cpu setting, set as cpu0 by default\n");
	}
	printf("testing on cpu %d\n", cpu);
	CPU_ZERO(&set);
	CPU_SET(cpu, &set);
	if (sched_setaffinity(getpid(), sizeof(set), &set) == -1) {
		printf("set affinity failed\n");
		return -1;
	}

	tstart = clock();
	for (a = 1; a <= x; a++) {
		shstk1();
		shstk2();
	}
	tend = clock();
	printf("RESULTS %dloop,start:%ld,end:%ld, used CLOCK:%ld: CLOCK/SEC:%ld\n",
	       x, tstart, tend, (long)(tend - tstart), CLOCKS_PER_SEC);
}
