// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2022 Intel Corporation.

/* quick_test.c - shadow stack violation should trigger expected SIGSEGV. */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <ucontext.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sched.h>

ucontext_t ucp;
static int result[2] = {-1, -1};
static int test_id;

static void stack_hacked(void)
{
	result[test_id] = -1;
	test_id++;
	printf("[WARN]\tProtection failed and func is hacked!\n");
	setcontext(&ucp);
}

static void ibt_violation(void)
{
#ifdef __i386__
	asm volatile("lea 1f, %eax");
	asm volatile("jmp *%eax");
#else
	asm volatile("lea 1f, %rax");
	asm volatile("jmp *%rax");
#endif
	asm volatile("1:");
	result[test_id] = -1;
	test_id++;
	setcontext(&ucp);
}

static void shstk_violation(void)
{
	unsigned long x[1];

	/*
	 * Use overflow method to achieve shstk violation:
	 * x[1] is for rbp, x[2] is the attack point where SHSTK stack
	 * return contents.
	 */
	x[2] = (unsigned long)stack_hacked;
}

static void segv_handler(int signum, siginfo_t *si, void *uc)
{
	printf("[INFO]\tGet SEGV(11) as expected, make result[%d]:%d to 0\n",
	       test_id, result[test_id]);
	result[test_id] = 0;
	test_id++;
	setcontext(&ucp);
}

static void user1_handler(int signum, siginfo_t *si, void *uc)
{
	shstk_violation();
}

static void user2_handler(int signum, siginfo_t *si, void *uc)
{
	ibt_violation();
}

int main(int argc, char *argv[])
{
	struct sigaction sa;
	int ret;

	int cpu;
	cpu_set_t set;

	if (argc >= 2) {
		cpu = atoi(argv[1]);
		printf("[INFO]\ttesting on cpu %d\n", cpu);
		CPU_ZERO(&set);
		CPU_SET(cpu, &set);
		if (sched_setaffinity(getpid(), sizeof(set), &set) == -1) {
			printf("[FAIL]\tset affinity failed\n");
			return -1;
		}
	}

	printf("[INFO]\tresult[0-1]:{%d, %d}\n", result[0], result[1]);
	ret = sigemptyset(&sa.sa_mask);
	if (ret)
		return -1;

	sa.sa_flags = SA_SIGINFO;

	/* Control protection fault handler */
	sa.sa_sigaction = segv_handler;
	ret = sigaction(SIGSEGV, &sa, NULL);
	if (ret)
		return -1;

	/* Handler to test SHSTK */
	sa.sa_sigaction = user1_handler;
	ret = sigaction(SIGUSR1, &sa, NULL);
	if (ret)
		return -1;

	/* Handler to test IBT */
	sa.sa_sigaction = user2_handler;
	ret = sigaction(SIGUSR2, &sa, NULL);
	if (ret)
		return -1;

	test_id = 0;
	ret = getcontext(&ucp);
	if (ret)
		return -1;

	if (test_id == 0) {
		printf("[INFO]\tCaes1: shstk violation\n");
		shstk_violation();
	} else if (test_id == 1) {
		printf("[INFO]\tCase2: SIGUSR1(10) trigger shstk violation\n");
		raise(SIGUSR1);
	}

	ret = 0;
	printf("[RESULTS]\tSHSTK: %d, %s\n", result[0],
	       result[0] ? "FAIL":"PASS");
	ret += result[0];
	printf("[RESULTS]\tSHSTK in signal: %d, %s\n", result[1],
	       result[1] ? "FAIL":"PASS");
	ret += result[1];

	if (ret) {
		printf("[WARN]\tret:%d is not 0, some cases failed\n", ret);
		ret = 1;
	}
	return ret;
}
