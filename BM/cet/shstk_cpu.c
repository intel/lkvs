// SPDX-License-Identifier: GPL-2.0
/*
 * Verify Shadow Stack performance impact on specific CPU
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
#include <sys/syscall.h>

/* It's from arch/x86/include/uapi/asm/prctl.h file. */
#define ARCH_SHSTK_ENABLE	0x5001
#define ARCH_SHSTK_DISABLE	0x5002
/* ARCH_SHSTK_ features bits */
#define ARCH_SHSTK_SHSTK		(1ULL <<  0)
#define ARCH_SHSTK_WRSS			(1ULL <<  1)

/*
 * For use in inline enablement of shadow stack.
 *
 * The program can't return from the point where shadow stack gets enabled
 * because there will be no address on the shadow stack. So it can't use
 * syscall() for enablement, since it is a function.
 *
 * Based on code from nolibc.h. Keep a copy here because this can't pull in all
 * of nolibc.h.
 */
#define ARCH_PRCTL(arg1, arg2)					\
({								\
	long _ret;						\
	register long _num  asm("eax") = __NR_arch_prctl;	\
	register long _arg1 asm("rdi") = (long)(arg1);		\
	register long _arg2 asm("rsi") = (long)(arg2);		\
								\
	asm volatile (						\
		"syscall\n"					\
		: "=a"(_ret)					\
		: "r"(_arg1), "r"(_arg2),			\
		  "0"(_num)					\
		: "rcx", "r11", "memory", "cc"			\
	);							\
	_ret;							\
})

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

	if (ARCH_PRCTL(ARCH_SHSTK_ENABLE, ARCH_SHSTK_SHSTK))
		printf("[FAIL]\tParent process could not enable SHSTK!\n");
	else
		printf("[PASS]\tParent process enable SHSTK.\n");

	tstart = clock();
	for (a = 1; a <= x; a++) {
		shstk1();
		shstk2();
	}
	tend = clock();
	printf("RESULTS %dloop,start:%ld,end:%ld, used CLOCK:%ld: CLOCK/SEC:%ld\n",
	       x, tstart, tend, (long)(tend - tstart), CLOCKS_PER_SEC);

	/* Disable SHSTK in parent process to avoid segfault issue. */
	if (ARCH_PRCTL(ARCH_SHSTK_DISABLE, ARCH_SHSTK_SHSTK))
		printf("[FAIL]\tParent process disable shadow stack failed.\n");
	else
		printf("[PASS]\tParent process disable shadow stack successfully.\n");

	return 0;
}
