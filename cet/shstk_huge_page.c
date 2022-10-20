// SPDX-License-Identifier: GPL-2.0-only
/* shstk_huge_page.c - allocate a 4M shadow stack buffer and works well. */

#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/mman.h>
#include <x86intrin.h>
#include <sys/syscall.h>
#include <sys/prctl.h>
#include <asm/prctl.h>
#include <signal.h>
#include <string.h>
#include <errno.h>

/* It's from arch/x86/include/uapi/asm/mman.h file. */
#define SHADOW_STACK_SET_TOKEN	0x1
/* It's from arch/x86/entry/syscalls/syscall_64.tbl file. */
#define __NR_map_shadow_stack	451

#define PASS		0
#define FAIL		1
#define F_HEX		0xf
#define BYTE_BITS	8

#ifdef __i386__
#define get_ssp()						\
({								\
	long _ret;						\
	asm volatile("xor %0, %0; rdsspd %0" : "=r" (_ret));	\
	_ret;							\
})
#else
#define get_ssp()						\
({								\
	long _ret;						\
	asm volatile("xor %0, %0; rdsspq %0" : "=r" (_ret));	\
	_ret;							\
})
#endif

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

size_t shstk_size = 0x800000;
static int loop_func_b(int sum);
const int count = 100000;
static unsigned long ssp_check;

static int loop_func_a(int sum)
{
	if (sum < count) {
		sum++;
		loop_func_b(sum);
	} else {
		ssp_check = get_ssp();
		printf("[PASS]\tloop a reached loop sum:%d, ssp:%lx(%lx)\n",
		       sum, ssp_check, *(unsigned long *)ssp_check);
		return PASS;
	}

	if (sum < count)
		return PASS;
	else
		return FAIL;
}

static int loop_func_b(int sum)
{
	if (sum < count) {
		sum++;
		loop_func_a(sum);
	} else {
		ssp_check = get_ssp();
		printf("[PASS]\tloop b reached loop sum:%d, ssp:%lx(%lx)\n",
		       sum, ssp_check, *(unsigned long *)ssp_check);
		return PASS;
	}

	if (sum < count)
		return PASS;
	else
		return FAIL;
}

static int create_huge_page_ssp(void)
{
	unsigned long ssp_origin, *asm_ssp, *bp, *new_ssp_end, new_ssp,
		      ssp_val;
	int start_num = 1;

	new_ssp_end = (unsigned long *)syscall(__NR_map_shadow_stack, 0,
					       shstk_size,
					       SHADOW_STACK_SET_TOKEN);
	if (new_ssp_end == MAP_FAILED) {
		printf("[FAIL]\tError creating shadow stack: %d\n", errno);
		return FAIL;
	}
	new_ssp = (unsigned long)new_ssp_end + shstk_size - 8;
	printf("[OK]\tCreate new ssp end:%p(0x%lx) start:%lx(0x%lx) size:%lx\n",
	       new_ssp_end, *new_ssp_end, new_ssp, *(unsigned long *)new_ssp,
	       shstk_size);

	ssp_origin = get_ssp();
	printf("[INFO]\tChange origin ssp:%lx(*ssp:%lx) to %lx(content:%lx)\n",
		ssp_origin, *(unsigned long *)ssp_origin, new_ssp,
		*(unsigned long *)new_ssp);

	asm volatile("rstorssp (%0)\n":: "r" (new_ssp));
	asm volatile("saveprevssp");

	asm volatile("rdsspq %rbx");
	asm("movq %%rbx,%0" : "=r"(asm_ssp));
	asm("movq %%rbp,%0" : "=r"(bp));

	printf("[INFO]\trstorssp, print origin_ssp:%lx(%lx) new_ssp:%lx(%lx)\n",
	       ssp_origin, *(unsigned long *)ssp_origin, new_ssp,
	       *(unsigned long *)new_ssp);
	printf("[INFO]\tAfter rstorssp and print twice, new ssp:%lx(%lx)\n",
	       new_ssp, *(unsigned long *)new_ssp);

	printf("[INFO]\tbp+1:%p, *(bp+1):0x%lx, asm_ssp:%p(new ssp top + 8)\n",
	       bp + 1, *(bp + 1), asm_ssp);

	if (loop_func_a(start_num))
		printf("[FAIL]\t loop func a test failed.\n");
	if (loop_func_b(start_num))
		printf("[FAIL]\t loop func b test failed.\n");

	/* Switch back to origin ssp */
	printf("[INFO]\tAfter huge ssp, saveprevssp to use back origin ssp.\n");

	asm volatile("rstorssp (%0)\n":: "r" (ssp_origin - BYTE_BITS));
	asm volatile("saveprevssp");
	ssp_val = get_ssp();
	if (ssp_origin == ssp_val) {
		printf("[PASS]\tAfter saveprevssp, ssp ori:%lx(%lx) is same\n",
		       ssp_origin, *(unsigned long *)ssp_origin);
	} else {
		printf("[FAIL]\tAfter saveprevssp, ssp ori:%lx not same ssp:%lx\n",
		       ssp_origin, ssp_val);
		return FAIL;
	}

	return PASS;
}

int main(int argc, char *argv[])
{
	unsigned long main_ssp;
	pid_t child;

	main_ssp = get_ssp();
	if (!main_ssp) {
		printf("[BLOCK]\tget ssp failed, shadow stack disabled.\n");
		return 2;
	}
	printf("[INFO]\tpid:%d, main_ssp:%lx, *main_ssp:%lx\n",
	       getpid(), main_ssp, *(long *)main_ssp);

	return create_huge_page_ssp();
}
