// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * For https://lore.kernel.org/lkml/0000000000004c453905c30f8334@google.com/
 * issue verification
 */


#define _GNU_SOURCE

#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sched.h>
#include <sys/types.h>

/* Copied from Linux kernel */
static inline void native_cpuid(unsigned int *eax, unsigned int *ebx,
				unsigned int *ecx, unsigned int *edx)
{
	/* ecx is often an input as well as an output. */
	asm volatile("cpuid"
		: "=a" (*eax),
		  "=b" (*ebx),
		  "=c" (*ecx),
		  "=d" (*edx)
		: "0" (*eax), "2" (*ecx)
		: "memory");
}

static inline int xsave_enabled(void)
{
	unsigned int eax, ebx, ecx, edx;

	eax = 0x1;
	ecx = 0x0;
	native_cpuid(&eax, &ebx, &ecx, &edx);

	/* Is CR4.OSXSAVE enabled ? */
	return ecx & (1U << 27);
}

static void sig_handler(int sig, siginfo_t *info, void *__ctxp)
{
	ucontext_t *uctx = __ctxp;
	mcontext_t *mctx = &uctx->uc_mcontext;
	unsigned long *p = (unsigned long *) mctx->fpregs;

	printf("Before change, p[66](XSAVE offset 528, header offset 16):%ld\n",
		p[66]);
	printf("&p:%p, p:%p, *p:%lx, p[0]:%lx, *p+1:%lx, *p+2:%lx\n",
		&p, p, *p, p[0], *(p+1), *(p+2));

	printf("&(mctx->fpregs): %p, mctx->fpregs:%lx\n",
		&(mctx->fpregs), (unsigned long)mctx->fpregs);
	/* SDM Vol1 13.8.1: if bytes 23:8 of the XSAVE header are not all 0, XRSTOR
	 * instruction will trigger general-protection exception (#GP), this test
	 * will fill XSAVE header 16-19 bytes with ffffffff, XSAVE header 16-19
	 * bytes are XSAVE 528(66*8)-531 offset bytes, 528 bytes represents the
	 * sum of 512 FPU status bytes plus 16 XSAVE header offset bytes. The SDM
	 * mentioned on the same page: software should ensure that bytes 63:16
	 * of the XSAVE header are all 0 in any XSAVE area. So this test will check
	 * whether the kernel can correctly modify all bytes 63:16 of the XSAVE
	 * header to 0, when any application fills non-zero values into the XSAVE
	 * header 19:16, this can avoid unnecessary #CP problems in XRSTOR action
	 */
	p[66] = 0xffffffff;
	printf("After change, p[66](XSAVE offset 528, header offset 16):%lx\n",
		p[66]);
}

static void sigsegv(int sig)
{
	printf("Got SEGV as expected.\n");
}

int main(void)
{
	struct sigaction sa;
	pid_t child;
	cpu_set_t set;

	if (!xsave_enabled()) {
		printf("[SKIP] CR4.OSXSAVE CPUID.(0x1, 0x0) ECX[27] disabled.\n");
		return 0;
	}

	memset(&sa, 0, sizeof(sa));
	sa.sa_sigaction = sig_handler;
	sa.sa_flags = SA_SIGINFO;
	sigemptyset(&sa.sa_mask);
	if (sigaction(SIGUSR1, &sa, 0))
		exit(1);

	signal(SIGSEGV, sigsegv);

	CPU_ZERO(&set);
	CPU_SET(0, &set);
	sched_setaffinity(getpid(), sizeof(set), &set);

	raise(SIGUSR1);
	printf("Back from signal, now schedule, create child pid\n");
	child = fork();
	if (child < 0)
		printf("fork failed\n");
	if (child == 0) {
		printf("Child pid:%d\n", getpid());
		return 0;
	}
	if (child)
		waitpid(child, NULL, 0);
	printf("[OK]\tBack in the parent thread.\n");
	printf("Parent process:%d\n", getpid());

	printf("Please make sure \"noxsaves\" in cmdline.\n");
	printf("'dmesg | grep \"Bad FPU\"', if it exists, issue is reproduced.\n");

	return 0;
}
