// SPDX-License-Identifier: GPL-2.0

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

/* It's from arch/x86/include/uapi/asm/mman.h file. */
#define SHADOW_STACK_SET_TOKEN	(1ULL << 0)
/* It's from arch/x86/include/uapi/asm/prctl.h file. */
#define ARCH_CET_ENABLE		0x5001
#define ARCH_CET_DISABLE	0x5002
#define ARCH_CET_UNLOCK		0x5004
#define CET_SHSTK		(1ULL <<  0)
#define CET_WRSS		(1ULL <<  1)
/* It's from arch/x86/entry/syscalls/syscall_64.tbl file. */
#define __NR_map_shadow_stack	451
/* It's from include/uapi/linux/elf.h. */
#define NT_X86_CET		0x203
#define NT_X86_XSTATE		0x202
#define CPUID_LEAF_XSTATE	0xd

/*
 * State component 11 is Control-flow Enforcement user states
 */
struct cet_user_state {
	uint64_t user_cet;			/* user control-flow settings */
	uint64_t user_ssp;			/* user shadow stack pointer */
};

#define rdssp() ({						\
	long _ret;						\
	asm volatile("xor %0, %0; rdsspq %0" : "=r" (_ret));	\
	_ret;							\
})

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

static void write_shstk(unsigned long *addr, unsigned long val)
{
	asm volatile("wrssq %[val], (%[addr])\n"
		     : "+m" (addr)
		     : [addr] "r" (addr), [val] "r" (val));
}

int unlock_shstk(pid_t pid)
{
	int status;
	int ret = 0;
	struct cet_user_state cet_state;
	uint32_t eax = 0, ebx = 0, ecx = 0, edx = 0, xstate_size, cet_offset;
	uint64_t *xstate;
	/*
	 * CPUID.(EAX=0DH, ECX=0H):EBX: maximum size (bytes, from the beginning
	 * of the XSAVE/XRSTOR save area) required by enabled features in XCR0.
	 */
	__cpuid_count(CPUID_LEAF_XSTATE, ecx, eax, ebx, ecx, edx);
	xstate_size = ebx;
	xstate = aligned_alloc(64, ebx);
	struct iovec iov = { .iov_base = xstate, .iov_len = ebx };
	struct iovec iov_cet = { .iov_base = &cet_state, .iov_len = 16 };

	if (ptrace(PTRACE_SEIZE, pid, 0, 0)) {
		printf("[FAIL]\tCan't attach to %d", pid);
		return -1;
	}

	if (ptrace(PTRACE_INTERRUPT, pid, 0, 0)) {
		printf("[FAIL]\tCan't interrupt the %d task", pid);
		goto detach;
	}

	if (wait4(pid, &status, __WALL, NULL) != pid) {
		printf("[FAIL]\twaitpid(%d) failed", pid);
		goto detach;
	}

	if (ptrace(PTRACE_ARCH_PRCTL, pid, CET_SHSTK, ARCH_CET_UNLOCK)) {
		printf("[FAIL]\tCan't unlock CET for %d task", pid);
		goto detach;
	} else {
		printf("[PASS]\tUnlock CET successfully for pid:%d\n", pid);
	}

	cet_state.user_cet = 0;
	cet_state.user_ssp = 0;

	ret = ptrace(PTRACE_GETREGSET, pid, NT_X86_CET, &iov_cet);
	if (ret) {
		printf("[FAIL]\tGETREGSET NT_X86_CET fail ret:%d, errno:%d",
			ret, errno);
	} else if (cet_state.user_ssp == 0) {
		printf("[FAIL]\tcet_ssp:%d is 0\n", cet_state.user_ssp);
	} else {
		printf("[PASS]\tGET CET REG ret:%d, err:%d, cet:%lx, ssp:%lx\n",
			ret, errno, cet_state.user_cet, cet_state.user_ssp);
	}

	ret = ptrace(PTRACE_SETREGSET, pid, NT_X86_CET, &iov_cet);
	if (ret) {
		printf("[FAIL]\tSETREGSET NT_X86_CET fail ret:%d, errno:%d",
			ret, errno);
	} else if (cet_state.user_ssp == 0) {
		printf("[FAIL]\tcet_ssp:%d is 0\n", cet_state.user_ssp);
	} else {
		printf("[PASS]\tSET CET REG ret:%d, err:%d, cet:%lx, ssp:%lx\n",
			ret, errno, cet_state.user_cet, cet_state.user_ssp);
	}

	cet_state.user_ssp = -1;
	ret = ptrace(PTRACE_SETREGSET, pid, NT_X86_CET, &iov_cet);
	if (ret) {
		printf("[PASS]\tSET ssp -1 failed(expected) ret:%d, errno:%d\n",
			ret, errno);
	} else {
		printf("[FAIL]\tSET ssp -1 ret:%d, err:%d, cet:%lx, ssp:%lx\n",
			ret, errno, cet_state.user_cet, cet_state.user_ssp);
	}

	ret = ptrace(PTRACE_GETREGSET, pid, NT_X86_XSTATE, &iov);
	if (ret)
		printf("[FAIL]\tGET xstate failed ret:%d\n", ret);
	else
		printf("[PASS]\tGET xstate successfully ret:%d\n", ret);

detach:
	if (ptrace(PTRACE_DETACH, pid, NULL, 0))
		printf("Unable to detach %d", pid);

	return ret;
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
	int status;
	unsigned long *ssp, i, loop_num = 1000000, ssp_origin;
	unsigned long *bp;
	long ret = 0;

	if (ARCH_PRCTL(ARCH_CET_ENABLE, CET_SHSTK))
		printf("[FAIL]\tParent process could not enable shadow stack.\n");
	else
		printf("[PASS]\tParent process enable shadow stack.\n");

	ssp = (unsigned long *)rdssp();

	if (!ssp) {
		printf("[FAIL]\tShadow stack disabled.\n");
		return 1;
	}
	printf("[PASS]\tParent pid:%d, ssp:%p\n", getpid(), ssp);
	check_ssp();

	child = fork();
	if (child < 0) {
		/* Fork syscall failed. */
		printf("[FAIL]\tfork failed\n");
		return 2;
	} else if (child == 0) {
		/* Verify child process shstk is enabled. */
		ssp = 0;
		ssp = (unsigned long *)rdssp();
		if (!ssp) {
			printf("[FAIL]\tSHSTK is disabled in child process\n");
			return 1;
		}
		printf("[PASS]\tSHSTK is enabled in child process\n");

		asm("movq %%rbp,%0" : "=r"(bp));
		printf("[INFO]\tChild:%d origin ssp:%p\n", getpid(), ssp);
		ssp = (unsigned long *)rdssp();
		printf("[INFO]\tChild:%d, ssp:%p, bp,%p, *bp:%lx, *(bp+1):%lx\n",
		       getpid(), ssp, bp, *bp, *(bp + 1));

		/* Execute loop and wait for parent to unlock cet for child.*/
		for (i = 1; i <= loop_num; i++) {
			if (i == loop_num)
				printf("[INFO]\tChild loop reached:%d\n",
				       loop_num);
		}

		if (ARCH_PRCTL(ARCH_CET_DISABLE, CET_SHSTK)) {
			printf("[FAIL]\tDisabling shadow stack failed\n");
			ret = 1;
		} else {
			printf("[PASS]\tDisabling shadow stack succesfully\n");
		}

		if (ARCH_PRCTL(ARCH_CET_ENABLE, CET_SHSTK)) {
			printf("[FAIL]\tCould not re-enable Shadow stack.\n");
			ret = 1;
		} else {
			printf("[PASS]\tChild process re-enable ssp\n");
		}

		if (ARCH_PRCTL(ARCH_CET_ENABLE, CET_WRSS)) {
			printf("[FAIL]\tCould not enable WRSS in child pid.\n");
			ret = 1;
		} else {
			printf("[PASS]\tChild process enabled wrss\n");
		}

		ssp = (unsigned long *)rdssp();
		asm("movq %%rbp,%0" : "=r"(bp));
		printf("[INFO]\tChild:%d, ssp:%p, bp,%p, *bp:%lx, *(bp+1):%lx\n",
		       getpid(), ssp, bp, *bp, *(bp + 1));

		if (ARCH_PRCTL(ARCH_CET_DISABLE, CET_SHSTK))
			printf("[FAIL]\tChild process could not disable shstk.\n");
		else
			printf("[PASS]\tChild process disable shstk successfully.\n");

		return 0;
	}

	if (child > 0) {
		unlock_shstk(child);
		if (waitpid(child, &status, 0) != child || !WIFEXITED(status))
			printf("Child exit with error status:%d\n", status);

		/* Disable SHSTK in parent process to avoid segfault issue. */
		if (ARCH_PRCTL(ARCH_CET_DISABLE, CET_SHSTK))
			printf("[FAIL]\tParent process disable shadow stack failed.\n");
		else
			printf("[PASS]\tParent process disable shadow stack successfully.\n");
	}

	return ret;
}
