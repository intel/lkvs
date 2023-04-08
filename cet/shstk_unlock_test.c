// SPDX-License-Identifier: GPL-2.0
// Copyright (c) 2022 Intel Corporation.

/*
 * shstk_unlock_test.c: unlock child process shstk by ptrace and then tests
 *                      get/set shstk regsets and shstk status syscalls
 */

#define _GNU_SOURCE

#include <sys/syscall.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <stdbool.h>
#include <x86intrin.h>
#include <sys/wait.h>
#include <sys/ptrace.h>
#include <sys/user.h>
#include <stdint.h>
#include <cpuid.h>
#include <sys/uio.h>
#include <errno.h>
#include <stdlib.h>
#include <fcntl.h>
#include <err.h>

/* It's from arch/x86/include/uapi/asm/mman.h file. */
#define SHADOW_STACK_SET_TOKEN	(1ULL << 0)
/* It's from arch/x86/include/uapi/asm/prctl.h file. */
#define ARCH_SHSTK_ENABLE	0x5001
#define ARCH_SHSTK_DISABLE	0x5002
#define ARCH_SHSTK_LOCK		0x5003
#define ARCH_SHSTK_UNLOCK	0x5004
#define ARCH_SHSTK_STATUS	0x5005
/* ARCH_SHSTK_ features bits */
#define ARCH_SHSTK_SHSTK		(1ULL <<  0)
#define ARCH_SHSTK_WRSS			(1ULL <<  1)
/* It's from arch/x86/entry/syscalls/syscall_64.tbl file. */
#ifndef __NR_map_shadow_stack
#define __NR_map_shadow_stack 451
#endif
/* It's from include/uapi/linux/elf.h. */
#define NT_X86_SHSTK		0x204
#define NT_X86_XSTATE		0x202
#define CPUID_LEAF_XSTATE	0xd

static long err_num;

/* err() exits. */
#define fatal_error(msg, ...)	err(1, "[FAIL]\t" msg, ##__VA_ARGS__)

#define rdssp() ({						\
	long _ret;						\
	asm volatile("xor %0, %0; rdsspq %0" : "=r" (_ret));	\
	_ret;							\
})

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

static void write_shstk(unsigned long *addr, unsigned long val)
{
	asm volatile("wrssq %[val], (%[addr])\n"
		     : "+m" (addr)
		     : [addr] "r" (addr), [val] "r" (val));
}

long unlock_shstk(pid_t pid)
{
	int status;
	long ret = 0;
	uint32_t eax = 0, ebx = 0, ecx = 0, edx = 0, xstate_size, cet_offset;
	uint64_t *xstate, user_ssp = 0, feature = 0;

	/*
	 * CPUID.(EAX=0DH, ECX=0H):EBX: maximum size (bytes, from the beginning
	 * of the XSAVE/XRSTOR save area) required by enabled features in XCR0.
	 */
	__cpuid_count(CPUID_LEAF_XSTATE, ecx, eax, ebx, ecx, edx);
	xstate_size = ebx;
	xstate = aligned_alloc(64, ebx);
	struct iovec iov = { .iov_base = xstate, .iov_len = ebx };
	struct iovec iov_cet = { .iov_base = &user_ssp, .iov_len = sizeof(user_ssp) };

	if (ptrace(PTRACE_SEIZE, pid, 0, 0)) {
		free(xstate);
		printf("[FAIL]\tCan't attach to %d", pid);
		return -1;
	}

	if (ptrace(PTRACE_INTERRUPT, pid, 0, 0)) {
		printf("[FAIL]\tCan't interrupt the %d task", pid);
		err_num++;
		goto detach;
	}

	if (wait4(pid, &status, __WALL, NULL) != pid) {
		printf("[FAIL]\twaitpid(%d) failed", pid);
		err_num++;
		goto detach;
	}

	if (ptrace(PTRACE_ARCH_PRCTL, pid, ARCH_SHSTK_SHSTK, ARCH_SHSTK_UNLOCK)) {
		printf("[FAIL]\tCan't unlock CET for %d task", pid);
		err_num++;
		goto detach;
	} else {
		printf("[PASS]\tUnlock CET successfully for pid:%d\n", pid);
	}

	ret = ptrace(PTRACE_GETREGSET, pid, NT_X86_SHSTK, &iov_cet);
	if (ret) {
		printf("[FAIL]\tGETREGSET NT_X86_SHSTK fail ret:%ld, errno:%d\n",
		       ret, errno);
		err_num++;
	} else if (user_ssp == 0) {
		printf("[FAIL]\tcet_ssp:%ld is 0\n", user_ssp);
		err_num++;
	} else {
		printf("[PASS]\tGET CET REG ret:%ld, err:%d, ssp:%lx\n",
		       ret, errno, user_ssp);
	}

	ret = ptrace(PTRACE_SETREGSET, pid, NT_X86_SHSTK, &iov_cet);
	if (ret) {
		printf("[FAIL]\tSETREGSET NT_X86_SHSTK fail ret:%ld, errno:%d\n",
		       ret, errno);
		err_num++;
	} else if (user_ssp == 0) {
		printf("[FAIL]\tcet_ssp:%ld is 0\n", user_ssp);
		err_num++;
	} else {
		printf("[PASS]\tSET CET REG ret:%ld, err:%d, ssp:%lx\n",
		       ret, errno, user_ssp);
	}

	user_ssp = -1;
	ret = ptrace(PTRACE_SETREGSET, pid, NT_X86_SHSTK, &iov_cet);
	if (ret) {
		printf("[PASS]\tSET ssp -1 failed(expected) ret:%ld, errno:%d\n",
		       ret, errno);
	} else {
		printf("[FAIL]\tSET ssp -1 ret:%ld, err:%d, ssp:%lx\n",
		       ret, errno, user_ssp);
		err_num++;
	}

	ret = ptrace(PTRACE_GETREGSET, pid, NT_X86_XSTATE, &iov);
	if (ret) {
		printf("[FAIL]\tGET xstate failed ret:%ld\n", ret);
		err_num++;
	} else {
		printf("[PASS]\tGET xstate successfully ret:%ld\n", ret);
	}

detach:
	free(xstate);
	if (ptrace(PTRACE_DETACH, pid, NULL, 0)) {
		printf("Unable to detach %d", pid);
		err_num++;
	}

	return err_num;
}

void check_ssp(void)
{
	unsigned long *ssp;

	ssp = (unsigned long *)rdssp();
	printf("[INFO]\tpid:%d, ssp:%p, *ssp:%lx\n", getpid(), ssp, *ssp);
}

int main(void)
{
	pid_t child;
	int status, fd[2] = {0};
	unsigned long *ssp, *bp, i, loop_num = 1000000;
	long ret = 0, result = 0;

	if (ARCH_PRCTL(ARCH_SHSTK_ENABLE, ARCH_SHSTK_SHSTK)) {
		printf("[FAIL]\tParent process could not enable SHSTK!\n");
		err_num++;
		return 1;
	}
	printf("[PASS]\tParent process enable SHSTK.\n");

	/* Check ssp buf after enabled SHSTK. */
	ssp = (unsigned long *)rdssp();
	if (!ssp) {
		printf("[FAIL]\tShadow stack disabled.\n");
		err_num++;
		return 1;
	}
	printf("[PASS]\tParent pid:%d, ssp:%p\n", getpid(), ssp);

	/* There is no *ssp for main so call function to check *ssp. */
	check_ssp();

	/* Use pipe to transfer test result to parent process. */
	if (pipe(fd) < 0)
		fatal_error("create pipe failed");

	child = fork();
	if (child < 0) {
		/* Fork syscall failed. */
		printf("[FAIL]\tfork failed\n");
		err_num++;
		return err_num;
	} else if (child == 0) {
		unsigned long feature = 0, *ssp_verify;

		/* Verify child process shstk is enabled. */
		ssp = 0;
		ssp = (unsigned long *)rdssp();
		if (!ssp) {
			printf("[FAIL]\tSHSTK is disabled in child process\n");
			err_num++;
			return err_num;
		}
		printf("[PASS]\tSHSTK is enabled in child process\n");

		asm("movq %%rbp,%0" : "=r"(bp));
		printf("[INFO]\tChild:%d origin ssp:%p\n", getpid(), ssp);
		ssp = (unsigned long *)rdssp();
		printf("[INFO]\tChild:%d, ssp:%p, bp,%p, *bp:%lx, *(bp+1):%lx\n",
		       getpid(), ssp, bp, *bp, *(bp + 1));

		if (ARCH_PRCTL(ARCH_SHSTK_DISABLE, ARCH_SHSTK_SHSTK)) {
			printf("[FAIL]\tDisabling shadow stack failed\n");
			err_num++;
		} else {
			printf("[PASS]\tDisabling shadow stack successfully\n");
		}

		ret = ARCH_PRCTL(ARCH_SHSTK_STATUS, &feature);
		if (ret) {
			printf("[FAIL]\tSHSTK_STATUS nok, feature:%lx, ret:%ld\n",
			       feature, ret);
			err_num++;
		} else if (feature == 0) {
			printf("[PASS]\tSHSTK_STATUS ok, feature:%lx is 0, ret:%ld\n",
			       feature, ret);
		} else {
			printf("[FAIL]\tSHSTK_STATUS ok, feature:%lx isn't 0, ret:%ld\n",
			       feature, ret);
			err_num++;
		}

		if (ARCH_PRCTL(ARCH_SHSTK_ENABLE, ARCH_SHSTK_SHSTK)) {
			printf("[FAIL]\tCould not re-enable Shadow stack.\n");
			err_num++;
		} else {
			printf("[PASS]\tChild process re-enable ssp\n");
		}

		ret = ARCH_PRCTL(ARCH_SHSTK_STATUS, &feature);
		if (ret) {
			printf("[FAIL]\tSHSTK_STATUS nok, feature:%lx, ret:%ld\n",
			       feature, ret);
			err_num++;
		} else if ((feature & 1) == 1) {
			printf("[PASS]\tSHSTK_STATUS ok, feature:%lx 1st bit is 1, ret:%ld\n",
			       feature, ret);
		} else {
			printf("[FAIL]\tSHSTK_STATUS ok, feature:%lx isn't 1, ret:%ld\n",
			       feature, ret);
			err_num++;
		}

		if (ARCH_PRCTL(ARCH_SHSTK_ENABLE, ARCH_SHSTK_WRSS)) {
			printf("[FAIL]\tCould not enable WRSS in child pid.\n");
			err_num++;
		} else {
			printf("[PASS]\tChild process enabled wrss\n");
		}

		ret = ARCH_PRCTL(ARCH_SHSTK_STATUS, &feature);
		if (ret) {
			printf("[FAIL]\tSHSTK_STATUS nok, feature:%lx, ret:%ld\n",
			       feature, ret);
			err_num++;
		} else if (((feature >> 1) & 1) == 1) {
			printf("[PASS]\tSHSTK_STATUS ok, feature:%lx 2nd bit is 1, ret:%ld\n",
			       feature, ret);
		} else {
			printf("[FAIL]\tSHSTK_STATUS ok, feature:%lx 2nd bit isn't 1, ret:%ld\n",
			       feature, ret);
			err_num++;
		}

		ssp_verify = (unsigned long *)rdssp();
		asm("movq %%rbp,%0" : "=r"(bp));
		printf("[INFO]\tChild:%d, ssp:%p, bp,%p, *bp:%lx, *(bp+1):%lx\n",
		       getpid(), ssp, bp, *bp, *(bp + 1));

		if (ssp == ssp_verify) {
			printf("[INFO]\tssp addr:%p is same as ssp_verify:%p\n",
			       ssp, ssp_verify);
		} else {
			printf("[INFO]\tssp addr:%p isn't same as ssp_verify:%p\n",
			       ssp, ssp_verify);
			err_num++;
		}

		if (ARCH_PRCTL(ARCH_SHSTK_DISABLE, ARCH_SHSTK_SHSTK)) {
			printf("[FAIL]\tChild process could not disable shstk.\n");
			err_num++;
		} else {
			printf("[PASS]\tChild process disable shstk successfully.\n");
		}

		/*
		 * Transfer the child process test result to
		 * the parent process for aggregation.
		 */
		close(fd[0]);
		if (!write(fd[1], &result, sizeof(result)))
			fatal_error("write fd failed");

		return result;
	}

	if (child > 0) {
		err_num = unlock_shstk(child);
		if (waitpid(child, &status, 0) != child || !WIFEXITED(status)) {
			printf("Child exit with error status:%d\n", status);
			err_num++;
		} else {
			/* Parent process fetch the child process's result. */
			close(fd[1]);
			if (!read(fd[0], &result, sizeof(result))) {
				err_num++;
				fatal_error("read fd failed");
			}
		}
		/* Disable SHSTK in parent process to avoid segfault issue. */
		if (ARCH_PRCTL(ARCH_SHSTK_DISABLE, ARCH_SHSTK_SHSTK)) {
			printf("[FAIL]\tParent process disable shadow stack failed.\n");
			err_num++;
		} else {
			printf("[PASS]\tParent process disable shadow stack successfully.\n");
		}
	}

	return err_num;
}
