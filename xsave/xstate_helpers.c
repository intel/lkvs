// SPDX-License-Identifier: GPL-2.0
/*
 * xstate_helpers.c - xstate helpers to prevent GCC from generating any FP code.
 *
 * Because xstate like XMM will not be preserved across function calls, it uses
 * assembly instruction to call a system call of fork or raise signal, and uses
 * the "inline" keyword in test functions in this file.
 * To prevent GCC from generating any FP/SSE(XMM)/AVX/PKRU code, add
 * "-mno-sse -mno-mmx -mno-sse2 -mno-avx -mno-pku" compiler arguments. stdlib.h
 * can not be used in this test file due to GCC bug.
 * The test functions that prepare the xstate buffers are placed in a separate
 * xstate.c because they do not require the above requirements.
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

#include "xstate_helpers.h"

/* err() exits and will not return. */
#define fatal_error(msg, ...)	err(1, "[FAIL]\t" msg, ##__VA_ARGS__)
/* FP and SSE are legacy xstates with fixed masks in regions 0-511 bytes. */
#define MASK_FP_SSE	3

static bool sigusr1_done;

static inline void __xsave(void *xbuf, uint64_t rfbm)
{
	uint32_t rfbm_lo = rfbm;
	uint32_t rfbm_hi = rfbm >> 32;

	asm volatile("xsave (%%rdi)"
		     : : "D" (xbuf), "a" (rfbm_lo), "d" (rfbm_hi)
		     : "memory");
}

static inline void __xrstor(void *xbuf, uint64_t rfbm)
{
	uint32_t rfbm_lo = rfbm;
	uint32_t rfbm_hi = rfbm >> 32;

	asm volatile("xrstor (%%rdi)"
		     : : "D" (xbuf), "a" (rfbm_lo), "d" (rfbm_hi));
}

inline void fill_fp_mxcsr_xstate_buf(void *buf, uint32_t xfeature_num,
				     uint8_t ui8_fp)
{
	/*
	 * Sets the FPU control, status, tag, instruction pointer, and
	 * data pointer registers to their default states.
	 */
	asm volatile("finit");
	/* Populate tested bytes onto FP registers stack ST0-7. */
	asm volatile("fldl %0" : : "m" (ui8_fp));
	asm volatile("fldl %0" : : "m" (ui8_fp));
	asm volatile("fldl %0" : : "m" (ui8_fp));
	asm volatile("fldl %0" : : "m" (ui8_fp));
	asm volatile("fldl %0" : : "m" (ui8_fp));
	asm volatile("fldl %0" : : "m" (ui8_fp));
	asm volatile("fldl %0" : : "m" (ui8_fp));
	asm volatile("fldl %0" : : "m" (ui8_fp));
	/* Xsave the x87 FPU and SSE MXCSR(bytes 24-27) xstate into the buf. */
	__xsave(buf, MASK_FP_SSE);
}

/*
 * Because xstate like XMM, YMM registers are not preserved across function
 * calls, so use inline function with assembly code only for fork syscall.
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
 * Because xstate like XMM, YMM registers are not preserved across function
 * calls, so use inline function with assembly code only to raise signal.
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

bool xstate_sig_handle(void *valid_xbuf, void *compared_xbuf, uint64_t mask,
		       uint32_t xstate_size)
{
	pid_t process_pid;

	sigusr1_done = false;
	memset(compared_xbuf, 0, xstate_size);
	sethandler(SIGUSR1, sigusr1_handler, 0);
	process_pid = getpid();
	/*
	 * Xrstor the valid buf and call syscall assembly instruction, then
	 * save the xstate to compared buf after signal handling for comparison.
	 */
	__xrstor(valid_xbuf, mask);
	__raise(process_pid, SIGUSR1);
	__xsave(compared_xbuf, mask);
	clearhandler(SIGUSR1);

	return sigusr1_done;
}

bool xstate_fork(void *valid_xbuf, void *compared_xbuf, uint64_t mask,
		 uint32_t xstate_size)
{
	pid_t child;
	int status, fd[2];
	bool child_result;

	memset(compared_xbuf, 0, xstate_size);
	/* Use pipe to transfer test result to parent process. */
	if (pipe(fd) < 0)
		fatal_error("create pipe failed");
	/*
	 * Xrstor the valid_xbuf and call syscall assembly instruction, then
	 * save the xstate to compared_xbuf in child process for comparison.
	 */
	__xrstor(valid_xbuf, mask);
	child = __fork();
	if (child < 0) {
		/* Fork syscall failed. */
		fatal_error("fork failed");
	} else if (child == 0) {
		/* Fork syscall succeeded, now in the child. */
		__xsave(compared_xbuf, mask);

		if (memcmp(valid_xbuf, compared_xbuf, xstate_size))
			child_result = false;
		else
			child_result = true;

		/*
		 * Transfer the child process test result to
		 * the parent process for aggregation.
		 */
		close(fd[0]);
		if (!write(fd[1], &child_result, sizeof(child_result)))
			fatal_error("write fd failed");
		_exit(0);
	} else {
		/* Fork syscall succeeded, now in the parent. */
		__xsave(compared_xbuf, mask);
		if (waitpid(child, &status, 0) != child || !WIFEXITED(status)) {
			fatal_error("Child exit with error status");
		} else {
			close(fd[1]);
			if (!read(fd[0], &child_result, sizeof(child_result)))
				fatal_error("read fd failed");
			return child_result;
		}
	}
}
