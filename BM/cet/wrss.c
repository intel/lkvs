// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2022 Intel Corporation.

/*
 * wrss.c: enable writable shadow stack and write value into shadow stack.
 *
 * Author: Pengfei Xu <pengfei.xu@intel.com>
 *
 * 1. Enable writable shadow stack via syscall "ARCH_CET_ENABLE and ARCH_SHSTK_WRSS"
 * 2. Write one incorrect value into shadow stack
 * 3. The expected SISEGV should be received after ret instruction
 */

#include <sys/mman.h>
#include <err.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <stdbool.h>
#include <x86intrin.h>
#include <signal.h>
#include <sys/syscall.h>
#include <asm/prctl.h>
#include <sys/prctl.h>

/* It's from arch/x86/include/uapi/asm/mman.h file. */
#define SHADOW_STACK_SET_TOKEN	(1ULL << 0)
/* It's from arch/x86/include/uapi/asm/prctl.h file. */
#define ARCH_CET_ENABLE		0x5001
#define ARCH_CET_DISABLE	0x5002
/* ARCH_SHSTK_ features bits */
#define ARCH_SHSTK_SHSTK		(1ULL <<  0)
#define ARCH_SHSTK_WRSS			(1ULL <<  1)
/* It's from arch/x86/entry/syscalls/syscall_64.tbl file. */
#ifndef __NR_map_shadow_stack
#define __NR_map_shadow_stack 453
#endif

/* err() exits and will not return */
#define fatal_error(msg, ...)	err(1, "[FAIL]\t" msg, ##__VA_ARGS__)

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

size_t shstk_size = 0x200000;

void *create_shstk(void)
{
	unsigned long ssp;

	ssp = _get_ssp();
	printf("[INFO]\tBefore create ssp:%lx\n", ssp);
	return (void *)syscall(__NR_map_shadow_stack, 0, shstk_size,
		SHADOW_STACK_SET_TOKEN);
}

void write_shstk(void *addr, unsigned long val)
{
	#ifndef __i386__
	asm volatile("1: wrssq %[val], (%[addr])\n" : : [addr] "r"
		(addr), [val] "r" (val));
	#else
	asm volatile("1: wrssd %[val], (%[addr])\n" : : [addr] "r"
		(addr), [val] "r" (val));
	#endif
}

static void sethandler(int sig, void *handler(int, siginfo_t *, void *),
		       int flags)
{
	struct sigaction sa;

	memset(&sa, 0, sizeof(sa));
	sa.sa_sigaction = (void *)handler;
	sa.sa_flags = SA_SIGINFO | flags;
	sigemptyset(&sa.sa_mask);
	if (sigaction(sig, &sa, 0))
		fatal_error("sigaction");
}

static void clearhandler(int sig)
{
	struct sigaction sa;

	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = SIG_DFL;
	sigemptyset(&sa.sa_mask);
	if (sigaction(sig, &sa, 0))
		fatal_error("sigaction");
}

static void *sigill_receive_expected(int signum, siginfo_t *info,
	void *__ctxp)
{
	unsigned long *shstk;
	int ret;

	if (signum == SIGILL)
		printf("[PASS]\tReceived SIGILL as expected\n");

	shstk = (unsigned long *)create_shstk();
	if (shstk == MAP_FAILED) {
		printf("[FAIL]\tError creating shadow stack: %d\n", errno);
		exit(1);
	}
	printf("[INFO]\tWill write shstk from addr:%p, content:0x%lx\n", shstk,
	       *shstk);

	/*
	 * arch_prctl libc has same result as ARCH_PRCTL(),
	 * ret = syscall(SYS_arch_prctl, ARCH_CET_ENABLE, ARCH_SHSTK_WRSS);
	 */
	if (ARCH_PRCTL(ARCH_CET_ENABLE, ARCH_SHSTK_WRSS)) {
		printf("[SKIP]\tCould not enable WRSS.\n");
		ret = 1;
		exit(ret);
	}
	printf("[PASS]\tEnabled write permit for SHSTK successfully\n");
	printf("[INFO]\tBefore write, *shstk:%lx\n", *shstk);
	write_shstk(shstk, 1);
	if (*shstk != 1) {
		printf("[FAIL]\twrss failed to write\n");
		exit(1);
	}
	printf("[PASS]\twrss succeded write shstk addr:%p, *shstk:%lx\n", shstk,
	       *shstk);

	clearhandler(SIGILL);

	/* If return 0, process will change shstk to 1 and trigger #CP */
	exit(0);
}

int main(int argc, char *argv[])
{
	unsigned long *current_shstk;

	if (ARCH_PRCTL(ARCH_CET_ENABLE, ARCH_SHSTK_SHSTK)) {
		printf("[SKIP]\tCould not enable Shadow stack.\n");
		return 1;
	}
	printf("[PASS]\tEnable SHSTK successfully\n");

	if (!_get_ssp()) {
		printf("[SKIP]\tSHSTK disabled, could not get shstk addr.\n");
		return 1;
	}

	sethandler(SIGILL, sigill_receive_expected, 0);
	current_shstk = (unsigned long *)_get_ssp();
	printf("[INFO]\tSHSTK addr:%p, illegal to change to 1.\n",
	       current_shstk);
	write_shstk(current_shstk, 1);
	clearhandler(SIGILL);

	return 0;
}
