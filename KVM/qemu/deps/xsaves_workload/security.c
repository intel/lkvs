// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Intel Corporation
/*
 * XSAVES security test payload.
 *
 * Installs a SIGHUP handler that overwrites the fpstate pointer in the
 * signal frame with an invalid address, then raises SIGHUP against itself.
 * On return from the handler the kernel must detect the bogus fpstate and
 * terminate the process; a well-behaved kernel additionally emits a
 * diagnostic in dmesg. Silent completion is treated as a regression by the
 * calling test harness.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <signal.h>
#include <unistd.h>
#include <ucontext.h>

void sighup(int sig, siginfo_t *info, void *ctxt)
{
	ucontext_t *uctxt = ctxt;
	struct sigcontext *sctxt = (void *)&uctxt->uc_mcontext;

	printf("SIGHUP! %p\n", sctxt->fpstate);
	sctxt->fpstate = (void *)1;
}

int main(void)
{
	struct sigaction sa = {
		.sa_sigaction	= sighup,
		.sa_flags	= SA_SIGINFO,
	};

	sigaction(SIGHUP, &sa, NULL);
	kill(getpid(), SIGHUP);

	return 0;
}
