// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2022 Intel Corporation.

/*
 * Author: Ricardo Neri Calderon <ricardo.neri-calderon@linux.intel.com>
 *      - Use: assistant for Intel User-Mode Execution Prevention
 *      - 0 no exit on signal
 *      - 1 receiving a signal means the test failed
 *      - 2 receiving a signal means the test passed
 * Contributor: Pengfei Xu <pengfei.xu@intel.com>
 *      - Some formatting improvements
 *      - A kernel bug was found and now fixed, it caused umip test to go into
 *        an infinite loop, so add 1000 loop checks to avoid the infinite loop
 *        problem.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <ucontext.h>
#include <ctype.h>
#include <sys/utsname.h>
#include "umip_test_defs.h"

extern int test_passed, test_failed, test_errors;
static int step_add;
void (*cleanup)(void) = NULL;
sig_atomic_t got_signal, got_sigcode;

/*
 * Use:
 * 0 no exit on signal
 * 1 receiving a signal means the test failed
 * 2 receiving a signal means the test passed
 */
int exit_on_signal;

void print_results(void)
{
	printf("RESULTS: passed[%d], failed[%d], errors[%d].\n",
	       test_passed, test_failed, test_errors);
}

/*
 * use:
 * 0: kernel version is or newer than target
 * 1: kernel version is older than target
 * 2: could not get kernel version by uname
 */
int kver_cmp(int major, int minor)
{
	struct utsname buffer;
	char *p;
	long ver[16] = {0};
	int i = 0;

	if (uname(&buffer) != 0) {
		pr_fail(test_failed, "get uname failed\n");
		return 2;
	}
	p = buffer.release;

	while (*p) {
		if (isdigit(*p)) {
			ver[i] = strtol(p, &p, 10);
			i++;
		} else {
			p++;
		}
	}
	pr_info("Kernel major:%ld, minor:%ld\n", ver[0], ver[1]);
	if (ver[0] < major) {
		pr_info("major version %ld older than target %d\n", ver[0], major);
		return 1;
	} else if (ver[0] == major) {
		if (ver[1] < minor) {
			pr_info("minor version %ld older than target %d\n", ver[1], minor);
			return 1;
		}
	}
	pr_info("Kernel version is or newer than target v%d.%d\n", major, minor);
	return 0;
}

/*
 * Use:
 * 0 no signal should be received as expected, pass
 * 1 received unexpected signal, and show it's sig num and sig code
 */
int unexpected_signal(void)
{
	if (got_signal) {
		pr_fail(test_failed, "Received unexpected signal:[%d], sigcode:[%d]\n",
			got_signal, got_sigcode);
		return 0;
	}

	pr_pass(test_passed, "No signal received as expected.\n");
	return 1;

}

int check_signal(int exp_signum)
{
	if (exp_signum) {
		if (got_signal == exp_signum) {
			pr_pass(test_passed, "Received expected signal:%d. Sig_code:%d.\n",
				got_signal, got_sigcode);
			return 0;
		}
		pr_fail(test_failed, "Received wrong signal:%d, expected sig:%d.\n",
		got_signal, exp_signum);
		return 1;
	}
	pr_fail(test_failed, "There was no signal received.\n");
	return 1;
}

/*
 * Inspect the contents of exp_signum and exp_sigcode to determine if they match
 * the received got_signal signal and signal code, if any. A return value of
 * 1 means that the test case is complete and no further action is needed (e.g.,
 * examine values returned by instructions. A return value of 0 means that
 * signal processing is not relevant for the caller can proceed with further
 * test case validation.
 */
int inspect_signal(int exp_signum, int exp_sigcode)
{
	/* If we expect signal, make sure it is the one we expect. */
	if (exp_signum) {
		/* A signal was received, examine it */
		if (got_signal == exp_signum) {
			if (got_sigcode == exp_sigcode) {
				/* All is good. Test case is complete. */
				pr_pass(test_passed, "Received expected signal and code.\n");
				return 1;
			}
			pr_fail(test_failed, "Wrong signal:%d, code:%d Expected si_code[%d].\n",
				got_signal, got_sigcode, exp_sigcode);
			return 1;
		}
		if (got_signal) {
			/* Wrong signal */
			pr_fail(test_failed, "Received wrong signal. Expected [%d]\n",
			        exp_signum);
			return 1;
		}
		/* signal did not come */
		pr_fail(test_failed, "Signal [%d] was expected. Nothing received.\n",
		        exp_signum);
		return 1;
	}
	/* If no signal is expected, make sure we did not receive one */
	if (got_signal) {
		pr_fail(test_failed, "Received unexpected signal.\n");
		return 1;
	}
	/* Signal is not relevant.*/
	return 0;
}

void signal_handler(int signum, siginfo_t *info, void *ctx_void)
{
	ucontext_t *ctx = (ucontext_t *)ctx_void;

	pr_info("si_signo[%d]\n", info->si_signo);
	pr_info("si_errno[%d]\n", info->si_errno);
	pr_info("si_code[%d]\n", info->si_code);
	pr_info("si_addr[0x%p]\n", info->si_addr);

	got_signal = signum;

	if (signum == SIGSEGV) {
		if (info->si_code == SEGV_MAPERR)
			pr_info("Signal because of unmapped object.\n");
		else if (info->si_code == SI_KERNEL)
			pr_info("Signal because of #GP\n");
		else
			pr_info("Unknown si_code!\n");
	} else if (signum == SIGILL) {
		if (info->si_code == SEGV_MAPERR)
			pr_info("Signal because of unmapped object.\n");
		else if (info->si_code == ILL_ILLOPN)
			pr_info("Signal because of #UD\n");
		else
			pr_info("Unknown si_code!\n");
	} else {
		pr_error(test_errors, "Received signal that I cannot handle!\n");
		exit(1);
	}

	/* Save the signal code */
	got_sigcode = info->si_code;

	if (exit_on_signal) {
		if (exit_on_signal == 1)
			pr_fail(test_failed, "Whoa! I got a signal! Something went wrong!\n");
		else if (exit_on_signal == 2)
			pr_pass(test_passed, "I got the expected signal.\n");
		else
			pr_fail(test_failed, "I don't know what to do on exit.\n");

		if (cleanup)
			(*cleanup)();

		exit(1);
	}

	/*
	 * Move to the next instruction; to move, increment the instruction
	 * pointer by 10 bytes. 10 bytes is the size of the instruction
	 * considering two prefix bytes, two opcode bytes, one
	 * ModRM byte, one SIB byte and 4 displacement bytes. We have
	 * a NOP sled after the instruction to ensure we continue execution
	 * safely in case we overestimate the size of the instruction.
	 */
#ifdef __x86_64__
	ctx->uc_mcontext.gregs[REG_RIP] += 10;
	pr_info("REG_RIP:%d, ctx->uc_mcontext.gregs[REG_RIP]:%lld, content:0x%lx\n",
		REG_RIP, ctx->uc_mcontext.gregs[REG_RIP],
		*(unsigned long *)ctx->uc_mcontext.gregs[REG_RIP]);
#else
	ctx->uc_mcontext.gregs[REG_EIP] += 10;
	pr_info("REG_EIP:%d, ctx->uc_mcontext.gregs[REG_EIP]:%d, content:0x%lx\n",
		REG_EIP, ctx->uc_mcontext.gregs[REG_EIP],
		*(unsigned long *)ctx->uc_mcontext.gregs[REG_EIP]);
#endif
	step_add++;
	if (step_add > 1000) {
		pr_fail(test_failed, "uc_mcontext.gregs[REG_R/EIP] add 1000 times!\n");
		exit(1);
	}
}
