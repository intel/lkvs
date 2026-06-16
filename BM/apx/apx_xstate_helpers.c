// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2024 Intel Corporation.

/*
 * apx_xstate_helpers.c - Assembly helpers for APX EGPR manipulation.
 *
 * These functions use inline assembly to directly manipulate APX extended
 * general purpose registers (R16-R31) and perform XSAVE/XRSTOR operations.
 *
 * Compiled with special flags to prevent GCC from using EGPR registers
 * for other purposes that would interfere with the test.
 */

#define _GNU_SOURCE
#include <err.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <sched.h>
#include <stdbool.h>
#include <sys/wait.h>
#include <sys/syscall.h>

#include "apx_xstate_helpers.h"

#define fatal_error(msg, ...)	err(1, "[FAIL]\t" msg, ##__VA_ARGS__)

static bool sigusr1_done;

/*
 * Fill all 16 extended GPRs (R16-R31) with a pattern.
 * Uses REX2-encoded MOV instructions to access R16-R31.
 */
void fill_egpr_registers(u64 pattern)
{
	/*
	 * Load all 16 extended GPRs (R16-R31) with distinct patterns.
	 * Requires compilation with -mapxf to enable EGPR register names.
	 */
	register u64 r16 asm("r16") = pattern;
	register u64 r17 asm("r17") = pattern + 1;
	register u64 r18 asm("r18") = pattern + 2;
	register u64 r19 asm("r19") = pattern + 3;
	register u64 r20 asm("r20") = pattern + 4;
	register u64 r21 asm("r21") = pattern + 5;
	register u64 r22 asm("r22") = pattern + 6;
	register u64 r23 asm("r23") = pattern + 7;
	register u64 r24 asm("r24") = pattern + 8;
	register u64 r25 asm("r25") = pattern + 9;
	register u64 r26 asm("r26") = pattern + 10;
	register u64 r27 asm("r27") = pattern + 11;
	register u64 r28 asm("r28") = pattern + 12;
	register u64 r29 asm("r29") = pattern + 13;
	register u64 r30 asm("r30") = pattern + 14;
	register u64 r31 asm("r31") = pattern + 15;

	asm volatile("" : : "r"(r16), "r"(r17), "r"(r18), "r"(r19));
	asm volatile("" : : "r"(r20), "r"(r21), "r"(r22), "r"(r23));
	asm volatile("" : : "r"(r24), "r"(r25), "r"(r26), "r"(r27));
	asm volatile("" : : "r"(r28), "r"(r29), "r"(r30), "r"(r31));
}

/*
 * XSAVE the APX EGPR state into buffer.
 */
inline void xsave_apx(void *buf, u64 mask)
{
	u32 lo = (u32)mask;
	u32 hi = (u32)(mask >> 32);

	asm volatile("xsave (%%rdi)"
		     : : "D" (buf), "a" (lo), "d" (hi)
		     : "memory");
}

/*
 * XRSTOR the APX EGPR state from buffer.
 */
inline void xrstor_apx(void *buf, u64 mask)
{
	u32 lo = (u32)mask;
	u32 hi = (u32)(mask >> 32);

	asm volatile("xrstor (%%rdi)"
		     : : "D" (buf), "a" (lo), "d" (hi));
}

/*
 * Inline syscall for fork to avoid function call clobbering EGPRs.
 */
static inline long __fork(void)
{
	long ret, nr = SYS_fork;

	asm volatile("syscall"
		     : "=a" (ret)
		     : "a" (nr)
		     : "rcx", "r11", "memory", "cc");

	return ret;
}

/*
 * Inline syscall for kill (to raise signal) without clobbering EGPRs.
 */
static inline long __raise(long pid_num, long sig_num)
{
	long ret, nr = SYS_kill;

	asm volatile("movq %0, %%rdi" : : "r"(pid_num) : "%rdi");
	asm volatile("movq %0, %%rsi" : : "r"(sig_num) : "%rsi");
	asm volatile("syscall"
		     : "=a" (ret)
		     : "a" (nr)
		     : "rcx", "r11", "memory", "cc");

	return ret;
}

static void sigusr1_handler(int signum, siginfo_t *info, void *__ctxp)
{
	sigusr1_done = true;
}

static void sethandler(int sig, void (*handler)(int, siginfo_t *, void *),
		       int flags)
{
	struct sigaction sa;

	memset(&sa, 0, sizeof(sa));
	sa.sa_sigaction = handler;
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

/*
 * Test that EGPR state is preserved across signal handling.
 *
 * 1. Load known values into EGPRs
 * 2. XSAVE the state
 * 3. Raise a signal
 * 4. After signal return, XSAVE again
 * 5. Compare: values must be identical
 */
bool apx_signal_test(void *valid_xbuf, void *compared_xbuf,
		     u64 mask, u32 xstate_size)
{
	pid_t process_pid;

	sigusr1_done = false;
	memset(compared_xbuf, 0, xstate_size);
	sethandler(SIGUSR1, sigusr1_handler, 0);
	process_pid = getpid();

	/* Load EGPRs, xsave, signal, xsave again for comparison */
	xrstor_apx(valid_xbuf, mask);
	__raise(process_pid, SIGUSR1);
	xsave_apx(compared_xbuf, mask);
	clearhandler(SIGUSR1);

	return sigusr1_done;
}

/*
 * Test that EGPR state is preserved across fork.
 *
 * 1. Load known values into EGPRs
 * 2. XSAVE the state
 * 3. Fork
 * 4. In child: XSAVE and compare with parent's state
 * 5. In parent: XSAVE and verify state unchanged
 */
bool apx_fork_test(void *valid_xbuf, void *compared_xbuf,
		   u64 mask, u32 xstate_size)
{
	pid_t child;
	int status, fd[2];
	bool child_result;

	memset(compared_xbuf, 0, xstate_size);
	if (pipe(fd) < 0)
		fatal_error("create pipe failed");

	xrstor_apx(valid_xbuf, mask);
	child = __fork();
	if (child < 0) {
		fatal_error("fork failed");
	} else if (child == 0) {
		/* Child: save EGPR state and compare */
		xsave_apx(compared_xbuf, mask);

		if (memcmp(valid_xbuf, compared_xbuf, xstate_size))
			child_result = false;
		else
			child_result = true;

		close(fd[0]);
		if (!write(fd[1], &child_result, sizeof(child_result)))
			fatal_error("write fd failed");
		_exit(0);
	} else {
		/* Parent: save state and verify */
		xsave_apx(compared_xbuf, mask);
		if (waitpid(child, &status, 0) != child || !WIFEXITED(status)) {
			fatal_error("Child exit with error status");
		} else {
			close(fd[1]);
			if (!read(fd[0], &child_result, sizeof(child_result)))
				fatal_error("read fd failed");
			return child_result;
		}
	}

	return false;
}

/*
 * Test that EGPR state is preserved across context switch.
 *
 * 1. Load known values into EGPRs
 * 2. XSAVE the state
 * 3. Yield CPU (sched_yield) to force context switch
 * 4. XSAVE again
 * 5. Compare: values must be identical
 */
bool apx_context_switch_test(void *valid_xbuf, void *compared_xbuf,
			     u64 mask, u32 xstate_size)
{
	memset(compared_xbuf, 0, xstate_size);

	xrstor_apx(valid_xbuf, mask);
	/* Force context switch */
	sched_yield();
	xsave_apx(compared_xbuf, mask);

	return (memcmp(valid_xbuf, compared_xbuf, xstate_size) == 0);
}
