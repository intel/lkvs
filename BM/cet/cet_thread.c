// SPDX-License-Identifier: GPL-2.0
// Copyright (c) 2018 Intel Corporation.
/*
 *    cet_thread.c:
 *
 *    Author: Pengfei Xu <pengfei.xu@intel.com>
 *
 *      - CET(Control-flow Enforcement Technology) verification in threads.
 *      - Parameter "s": test shadow stack violation in a new thread, which
 *        should be #CP blocked and get SIGSEGV.
 *      - Parameter "i": test indirect branch tracking violation in a new
 *        thread, which should be #CP blocked and get SIGSEGV.
 */

#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <pthread.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>

/* Upstream kernel reports control protection fault as SEGV_CPERR. */
#ifndef SEGV_CPERR
#define SEGV_CPERR 3
#endif

void printids(const char *s)
{
	pid_t pid;
	pthread_t tid;

	pid = getpid();
	tid = pthread_self();
	printf("%s pid %u tid %u (0x%x)\n", s, (unsigned int)pid,
	       (unsigned int)tid, (unsigned int)tid);
}

int hack(void)
{
	printf("%s function, which should be #cp blocked\n", __func__);
	sleep(1);
	return 1;
}

void *thr_shstk(void *arg)
{
	unsigned long *p;

	printids("new shstk thread: ");
	#ifdef __x86_64__
		asm("movq %%rbp,%0" : "=r"(p));
	#else
		asm("mov %%ebp,%0" : "=r"(p));
	#endif

	*(p + 1) = (unsigned long)hack;
	return NULL;
}

void *thr_ibt(void *arg)
{
	printids("new ibt thread: ");
	#ifdef __x86_64__
		asm volatile("leaq 1f, %rax");
		asm volatile("jmpq *%rax");
	#else
		asm volatile("lea 1f, %eax");
		asm volatile("jmp *%eax");
	#endif
	asm volatile("1:");
	printf("ibt test, which should be #cp blocked\n");
	return NULL;
}

void segv_handler(int signum, siginfo_t *si, void *uc)
{
	int exp_code = 8, new_code = 10;

	printf("si_signo:%d\n", si->si_signo);
	printf("si_errno:%d\n", si->si_errno);
	printf("si_code:%d\n", si->si_code);
	if (si->si_code == exp_code || si->si_code == new_code ||
	    si->si_code == SEGV_CPERR)
		printf("Got SIGSEGV(11) and si_code(%d|%d|%d) as expected\n",
		       exp_code, new_code, SEGV_CPERR);
	else {
		printf("si_code error, actual:%d, expect:%d|%d|%d.\n",
		       si->si_code, exp_code, new_code, SEGV_CPERR);
		exit(1);
	}
	exit(0);
}

void usage(void)
{
	printf("Usage: [s][i]\n");
	printf("s: Test shadow stack in thread\n");
	printf("i: Test ibt in thread\n");
}

int main(int argc, char *argv[])
{
	int err, r;
	pthread_t ntid;
	struct sigaction sa;
	char parm;

	if (argc == 1) {
		usage();
		exit(2);
	} else {
		if (sscanf(argv[1], "%c", &parm) != 1)
			return -EINVAL;
		printf("parm:%c\n", parm);
	}

	r = sigemptyset(&sa.sa_mask);
	if (r) {
		printf("Init empty signal failed\n");
		return -1;
	}
	sa.sa_flags = SA_SIGINFO;
	sa.sa_sigaction = segv_handler;
	r = sigaction(SIGSEGV, &sa, NULL);
	if (r) {
		printf("Could not handle SIGSEGV(11)\n");
		return -1;
	}

	switch (parm) {
	case 's':
		err = pthread_create(&ntid, NULL, thr_shstk, NULL);
		if (err != 0) {
			printf("can't create thr_shstk: %s\n", strerror(err));
			exit(1);
		}
		break;
	case 'i':
		err = pthread_create(&ntid, NULL, thr_ibt, NULL);
		if (err != 0) {
			printf("can't create thr_ibt: %s\n", strerror(err));
			exit(1);
		}
		break;
	default:
		usage();
		exit(2);
	}
	printids("process created thread:");
	sleep(2);
	pthread_join(ntid, NULL);
	return EXIT_FAILURE;
}
