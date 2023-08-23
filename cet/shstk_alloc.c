// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2022 Intel Corporation.

// SPDX-License-Identifier: GPL-2.0
/*
 * shstk_alloc.c - allocate a new shadow stack buffer aligenment by instructions
 *
 * 1. Test shstk buffer allocation for one new shstk buffer
 * 2. Test rstorssp, saveprevssp, rdsspq to load new shstk buffer
 * 3. Test rstorssp, saveprevssp to restore the previous shstk buffer
 */

#define _GNU_SOURCE

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

/* It's from arch/x86/include/uapi/asm/prctl.h file. */
#define ARCH_SHSTK_ENABLE	0x5001
#define ARCH_SHSTK_DISABLE	0x5002
#define ARCH_SHSTK_LOCK		0x5003
#define ARCH_SHSTK_UNLOCK	0x5004
#define ARCH_SHSTK_STATUS	0x5005
/* ARCH_SHSTK_ features bits */
#define ARCH_SHSTK_SHSTK		(1ULL <<  0)
#define ARCH_SHSTK_WRSS			(1ULL <<  1)

#define SHADOW_STACK_SET_TOKEN	0x1
#ifndef __NR_map_shadow_stack
#define __NR_map_shadow_stack 451
#endif

size_t shstk_size = 0x200000;

/*
 * For use in inline enablement of shadow stack.
 *
 * The program cannot return from the point where the shadow stack is enabled
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

#define get_ssp()						\
({								\
	unsigned long _ret;					\
	asm volatile("xor %0, %0; rdsspq %0" : "=r" (_ret));	\
	_ret;							\
})

void *create_shstk(void)
{
	return (void *)syscall(__NR_map_shadow_stack, 0, shstk_size,
			       SHADOW_STACK_SET_TOKEN);
}

#if (__GNUC__ < 8) || (__GNUC__ == 8 && __GNUC_MINOR__ < 5)
int main(int argc, char *argv[])
{
	printf("BLOCK: compiler does not support CET.");
	return 2;
}
#else
void try_shstk(unsigned long new_ssp)
{
	unsigned long ssp0, ssp1, ssp2;

	printf("pid=%d\n", getpid());
	printf("new_ssp = %lx, *new_ssp = %lx\n",
		new_ssp, *((unsigned long *)new_ssp));

	ssp0 = get_ssp();
	printf("changing ssp from %lx(*ssp:%lx) to %lx(%lx)\n",
	       ssp0, *((unsigned long *)ssp0), new_ssp,
	       *((unsigned long *)new_ssp));

	/* Make sure ssp address is aligned to 8 bytes */
	if ((ssp0 & 0xf) != 0) {
		ssp0 = (unsigned long)(ssp0 & -8);
		printf("ssp0 & (-8): %lx\n", ssp0);
	}
	asm volatile("rstorssp (%0)\n":: "r" (new_ssp));
	asm volatile("saveprevssp");
	ssp1 = get_ssp();
	printf("ssp is now %lx\n", ssp1);

	ssp0 -= 8;
	asm volatile("rstorssp (%0)\n":: "r" (ssp0));
	asm volatile("saveprevssp");

	ssp2 = get_ssp();
	printf("ssp changed back: %lx, *ssp:%lx\n", ssp2,
	       *((unsigned long *)ssp2));
}

int main(int argc, char *argv[])
{
	void *shstk;
	unsigned long ssp, *asm_ssp, *bp;

	if (ARCH_PRCTL(ARCH_SHSTK_ENABLE, ARCH_SHSTK_SHSTK)) {
		printf("[FAIL]\tParent process could not enable SHSTK!\n");
		return 1;
	}
	printf("[PASS]\tParent process enable SHSTK.\n");

	shstk = create_shstk();
	if (shstk == MAP_FAILED) {
		printf("[FAIL]\tError creating shadow stack: %d\n", errno);
		return 1;
	}
	printf("Allocate new shstk addr:%p, content:%lx\n", shstk,
	       *(long *)shstk);
	try_shstk((unsigned long)shstk + shstk_size - 8);

	printf("[PASS]\tCreated and allocated new shstk addr test.\n");

	/* Disable SHSTK in parent process to avoid segfault issue. */
	if (ARCH_PRCTL(ARCH_SHSTK_DISABLE, ARCH_SHSTK_SHSTK)) {
		printf("[FAIL]\tParent process disable shadow stack failed.\n");
		return 1;
	} else {
		printf("[PASS]\tParent process disable shadow stack successfully.\n");
	}
	return 0;
}
#endif
