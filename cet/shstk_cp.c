// SPDX-License-Identifier: GPL-2.0
// Copyright (c) 2022 Intel Corporation.

/*
 * shstk_cp.c: enable shstk and then do shstk violation
 *             expected #CP should be triggered
 */

#include <sys/syscall.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <stdbool.h>
#include <x86intrin.h>
#include <sys/wait.h>
#include <sys/ptrace.h>
#include <sys/user.h>

/* It's from arch/x86/include/uapi/asm/mman.h file. */
#define SHADOW_STACK_SET_TOKEN	(1ULL << 0)
/* It's from arch/x86/include/uapi/asm/prctl.h file. */
#define ARCH_CET_ENABLE		0x5001
#define ARCH_CET_DISABLE	0x5002
#define ARCH_CET_UNLOCK		0x5004
/* ARCH_SHSTK_ features bits */
#define ARCH_SHSTK_SHSTK		(1ULL <<  0)
#define ARCH_SHSTK_WRSS			(1ULL <<  1)
/* It's from arch/x86/entry/syscalls/syscall_64.tbl file. */
#define __NR_map_shadow_stack	451

#define rdssp() ({						\
	unsigned long _ret;					\
	asm volatile("xor %0, %0; rdsspq %0" : "=r" (_ret));	\
	_ret;							\
})

/*
 * For use in inline enablement of shadow stack.
 *
 * The program can't return from the point where shadow stack get's enabled
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

static long hacked(void)
{
	printf("[INFO]\tAccess hack function\n");
	printf("[FAIL]\tpid=%d Hacked!\n", getpid());
	printf("[WARN]\tYou see this line, which means shstk #CP failed!\n");
	return 1;
}

/* rbp + 8 bytes modification shstk violation, which should trigger #CP. */
void shstk_violation(void)
{
	unsigned long *ssp, *rbp;

	ssp = (unsigned long *)rdssp();
	asm("movq %%rbp,%0" : "=r"(rbp));

	printf("[INFO]\tdo_hack() change address for return:\n");
	printf("[INFO]\tBefore,ssp:%p,*ssp:%lx,rbp:%p,*rbp:%lx,*(rbp+1):%lx\n",
	       ssp, *ssp, rbp, *rbp, *(rbp + 1));

	/* rbp+1(8bytes) saved sp(ret ip), change rbp+1 to change sp content */
	*(rbp + 1) = (unsigned long)hacked;

	printf("[INFO]\tAfter, ssp:%p,*ssp:%lx,rbp:%p,*rbp:%lx,*(rbp+1):%lx\n",
	       ssp, *ssp, rbp, *rbp, *(rbp + 1));
}

int main(void)
{
	int ret = 0;
	unsigned long ssp;

	if (ARCH_PRCTL(ARCH_CET_ENABLE, ARCH_SHSTK_SHSTK)) {
		printf("[SKIP]\tCould not enable Shadow stack.\n");
		return 1;
	}
	printf("[PASS]\tEnable SHSTK successfully\n");

	if (ARCH_PRCTL(ARCH_CET_DISABLE, ARCH_SHSTK_SHSTK)) {
		ret = 1;
		printf("[FAIL]\tDisabling shadow stack failed\n");
	} else {
		printf("[PASS]\tDisabling shadow stack successfully\n");
	}

	if (ARCH_PRCTL(ARCH_CET_ENABLE, ARCH_SHSTK_SHSTK)) {
		printf("[SKIP]\tCould not re-enable Shadow stack.\n");
		return 1;
	}
	printf("[PASS]\tRe-enable shadow stack successfully\n");

	ssp = rdssp();

	if (!ssp) {
		printf("[FAIL]\tCould not read ssp:%lx.\n", ssp);
		return 1;
	}
	printf("[PASS]\tSHSTK enabled, ssp:%lx\n", ssp);

	/* There is no *(unsigned long *)ssp of main, otherwise segfault. */

	shstk_violation();

	return ret;
}
