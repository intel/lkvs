// SPDX-License-Identifier: GPL-2.0
// Copyright (c) 2018 Intel Corporation.
/*
 *    sig_stack.c:
 *
 *    Author: Pengfei Xu <pengfei.xu@intel.com>
 *
 *      - CET(Control-flow Enforcement Technology) signal stack test.
 *      - Verify the signal trigger function could be protected by CET.
 *      - Parameter "a": signal stack access cet stack check test.
 *      - Parameter "s": signal stack access and shstk violation test, which
 *        should be #CP blocked.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <immintrin.h>

void sigaction_handler(int signum, siginfo_t *info, void *ptr)
{
	unsigned long *p_rbp, *addr_ssp;

	asm volatile ("rdsspq %rbx");
	asm("movq %%rbx,%0" : "=r"(addr_ssp));
	asm("movq %%rbp,%0" : "=r"(p_rbp));

	printf("%s():rbp=%p, p_rbp=%p, *(p_rbp+1):%lx\n",
	       __func__, __builtin_frame_address(0), p_rbp, *(p_rbp + 1));
	printf("%s():__builtin_return_address=%p\n",
	       __func__, __builtin_return_address(0));
	printf("%s(): ssp:%p, *ssp:%lx\n",
	       __func__, addr_ssp, *addr_ssp);
	printf("ssp+1:%p, *(ssp+1):%lx\nssp+2:%p, *(ssp+2):%lx\n",
	       addr_ssp + 1, *(addr_ssp + 1), addr_ssp + 2, *(addr_ssp + 2));
	if (*(p_rbp + 1) != *addr_ssp) {
		printf("SIGUSR1 trigger handler, *(rbp+1):%lx not equal to *ssp:%lx\n",
		       *(p_rbp + 1), *addr_ssp);
		exit(1);
	}
}

int signal_access_func(void)
{
	stack_t ss;
	struct sigaction sigact;
	unsigned long *addr_rbp, *addr_ssp;

	ss.ss_sp = malloc(SIGSTKSZ);
	ss.ss_flags = 0;
	ss.ss_size = SIGSTKSZ;

	addr_rbp = __builtin_frame_address(0);
	addr_ssp = (unsigned long *)_get_ssp();

	printf("sigaltstack ss.ss_sp:%p\n", (void *)ss.ss_sp);
	printf("%s: rbp:%p, *(rbp):%lx, *(rbp+1):%lx\n",
	       __func__, addr_rbp, *addr_rbp, *(addr_rbp + 1));
	printf("%s: ssp:%p, *ssp:%lx\n",
	       __func__, addr_ssp, *addr_ssp);

	sigact.sa_sigaction = sigaction_handler;
	sigemptyset(&sigact.sa_mask);
	sigact.sa_flags = SA_ONSTACK;
	sigaction(SIGUSR1, &sigact, NULL);
	raise(SIGUSR1);

	printf("After signal SIGUSR1:rbp=%p\n", __builtin_frame_address(0));
	return 0;
}

int hack(void)
{
	printf("Access %s function, Which should be #cp blocked\n", __func__);
	exit(1);
}

void shstk_violation_handler(int signum, siginfo_t *si, void *uc)
{
	int exp_sig = 12;
	unsigned long *p_rbp, *addr_ssp;

	addr_ssp = (unsigned long *)_get_ssp();
	printf("signal SIGUSR2(#12) received:\nsi_signo:%d\n", si->si_signo);
	printf("si_errno:%d\n", si->si_errno);
	printf("si_code:%d\n", si->si_code);
	printf("%s: ssp:%p, *ssp:%lx\n",
	       __func__, addr_ssp, *addr_ssp);
	printf("ssp+1:%p, *(ssp+1):%lx\nssp+2:%p, *(ssp+2):%lx\n",
	       addr_ssp + 1, *(addr_ssp + 1), addr_ssp + 2, *(addr_ssp + 2));

	if (si->si_signo != exp_sig) {
		printf("si_signo error, actual:%d, expect:%d.\n",
		       si->si_signo, exp_sig);
		exit(1);
	}

	p_rbp = __builtin_frame_address(0);
	*(p_rbp + 1) = (unsigned long)hack;
}

int signal_shstk_violation(void)
{
	int result;
	struct sigaction sa;
	unsigned long *addr_ssp;

	asm volatile ("rdsspq %rbx");
	asm("movq %%rbx,%0" : "=r"(addr_ssp));
	printf("%s: ssp:%p, *ssp:%lx\n",
	       __func__, addr_ssp, *addr_ssp);
	result = sigemptyset(&sa.sa_mask);
	if (result) {
		printf("Init empty sa signal failed\n");
		return 2;
	}
	sa.sa_flags = SA_SIGINFO;
	sa.sa_sigaction = shstk_violation_handler;
	result = sigaction(SIGUSR2, &sa, NULL);
	if (result) {
		printf("Could not handle SIGUSR2(12)\n");
		return 2;
	}
	raise(SIGUSR2);

	return 0;
}

void usage(void)
{
	printf("Usage: [a][s]\n");
	printf("  a: signal stack access cet stack check test\n");
	printf("  s: signal stack access and shstk violation test\n");
}

int main(int argc, char **argv)
{
	struct sigaction sa;
	int result;
	char parm;

	result = sigemptyset(&sa.sa_mask);
	if (result) {
		printf("Init empty sa signal failed\n");
		return 2;
	}

	if (argc == 1) {
		usage();
		exit(2);
	} else {
		if (sscanf(argv[1], "%c", &parm) != 1) {
			printf("Invalid parameter:%s\n", argv[1]);
			exit(2);
		}
		printf("parm:%c\n", parm);
	}

	switch (parm) {
	case 'a':
		signal_access_func();
		break;
	case 's':
		signal_shstk_violation();
		break;
	default:
		usage();
		exit(2);
	}

	return 0;
}
