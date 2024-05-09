// SPDX-License-Identifier: GPL-2.0
// Copyright (c) 2022 Intel Corporation.
/*
 *    glibc_shstk_test.c:
 *
 *    Author: Pengfei Xu <pengfei.xu@intel.com>
 *
 *      - Test CET shadow stack function, should trigger #CP protection.
 *      - Some stack changes that don't affect sp should not trigger #CP.
 *      - Add more print to show stack address and content before and after
 *        the stack modification.
 */

#define _GNU_SOURCE
#include <sys/types.h>
#include <sys/wait.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <signal.h>
#include <sched.h>
#include <immintrin.h>

static long hacked(void)
{
	printf("[INFO]\tAccess hack function\n");
	printf("[FAIL]\tpid=%d Hacked!\n", getpid());
	printf("[WARN]\tYou see this line, which means CET shstk #CP failed!\n");
	return 1;
}

/*
 * stack variable + 1(1 means 8bytes for 64bit, 4bytes for 32bit) is bp,
 * and here use bp directly, it's bp hacked not sp hacked, so it should not
 * trigger #CP.
 */
static void stack_add1_test(unsigned long changed_bp)
{
	unsigned long *func_bp;

#ifdef __x86_64__
	asm("movq %%rbp,%0" : "=r"(func_bp));
#else
	asm("mov %%ebp,%0" : "=r"(func_bp));
#endif
	printf("[INFO]\tReal add1 function rbp content:%lx for main rbp.\n",
	       *func_bp);
	*func_bp = changed_bp;
	printf("[INFO]\tChange add1 rbp content:%lx, but right main rbp content in it!\n",
	       *func_bp);
}

/* stack base rbp + 1 addr test, which should be hacked and #CP should work */
static unsigned long stack_add2_test(void)
{
	unsigned long y;
	unsigned long *i, *j;

	i = (unsigned long *)_get_ssp();
	j = __builtin_frame_address(0);

	printf("[INFO]\tdo_hack() change address for return:\n");
	printf("[INFO]\tBefore change,y:%lx,&y:%p,j:%p,*j:%lx,*(&j+1):0x%lx, ssp:%p *ssp:0x%lx\n",
	       y, &y, j, *j, *(j + 1), i, *i);

	/* j(rbp)+1 is sp address, change rbp+1 to change sp content */
	*(j + 1) = (unsigned long)hacked;

	printf("[INFO]\tAfter change, rbp+1 to hacked:0x%lx\n", *(j + 1));
	printf("[INFO]\tAfter hacked  &y:%p, *j:0x%lx,*(&j+1):0x%lx\n",
	       &y, *j, *(j + 1));

	/* Debug purpose: it's not related with ret instruction in objdump. */
	return y;
}

/* stack base y + 3 addr test, which should not be hacked and #CP */
static unsigned long stack_add3_test(void)
{
	unsigned long y;

	printf("[INFO]\tdo_hack() change address for return:\n");
	printf("[INFO]\tBefore change, y:0x%lx, *(&y+2):0x%lx\n", y,
	       *((unsigned long *)&y + 2));
	*((unsigned long *)&y + 3) = (unsigned long)hacked;
	printf("[INFO]\tAfter change, *(&y+3) to change:0x%lx\n", (unsigned long)hacked);
	printf("[INFO]\tAfter change &y+3:%p,*(&x+2):0x%lx\n",
	       (unsigned long *)&y + 3, *((unsigned long *)&y + 3));
	printf("[INFO]\tAfter changed &y:%p, &y+2:%p,*(&y+2):0x%lx\n",
	       &y, (unsigned long *)&y + 2, *((unsigned long *)&y + 2));

	return y;
}

static long stack_long2_test(unsigned long i)
{
	unsigned long *p;

	printf("[INFO]\tuse rbp + long(+8bytes) size to hack:\n");
	/*
	 * Another way to read rbp
	 * asm("movq %%rbp,%0" : "=r"(p));
	 */
	p = __builtin_frame_address(0);

	printf("[INFO]\t*(p+1):%lx will be hacked\n", *(p + 1));
	*(p + 1) = (unsigned long)hacked;

	return 0;
}

/* stack base y + 2 change to random value to do shstk violation */
static unsigned long stack_random(unsigned long j)
{
	unsigned long y;
	unsigned long *p;

	y = j;
	printf("[INFO]\tSHSTK hack with random value:\n");
#ifdef __x86_64__
	asm("movq %%rbp,%0" : "=r"(p));
#else
	asm("mov %%ebp,%0" : "=r"(p));
#endif

	*(p + 1) = j;

	return y;
}

/* stack base y + 2 changed but no return */
static void stack_no_return(void)
{
	unsigned long *p;

	printf("[INFO]\tSHSTK with void no return function:\n");
#ifdef __x86_64__
	asm("movq %%rbp,%0" : "=r"(p));
#else
	asm("mov %%ebp,%0" : "=r"(p));
#endif

	*(p + 1) = (unsigned long)hacked;
}

/* buffer overflow change stack base, which should trigger #CP */
static void stack_buf_impact(void)
{
	char buffer[20];
	int overflow_num = 44;

	printf("[INFO]\tbuffer[20]:%x\n", buffer[20]);
	memset(buffer, 0, overflow_num);
	printf("[INFO]\tbuffer[44]:%x,&buffer[44]:%p\n", buffer[44], &buffer[44]);
	printf("[INFO]\tbuffer[20] after overflow:%x\n", buffer[20]);
}

/* buffer overflow not change stack base, which should not trigger #CP */
static void stack_buf_no_impact(void)
{
	char buf[20];
	int overflow_24 = 24, overflow_28 = 28;

	printf("[INFO]\tbuf[20]:%x\n", buf[20]);
#ifdef __x86_64__
	memset(buf, 0, overflow_28);
#else
	memset(buf, 0, overflow_24);
#endif
	printf("[INFO]\tbuf[20] after overflow:%x\n", buf[20]);
}

/* test hack function */
static int do_hack(void *p)
{
	/*
	 * Ret and then rip will get this value(rbp + 8 bytes in 64 bit OS)
	 * rbp(8 bytes in 64bit OS)
	 * *i, *j and so on variable content
	 */
	unsigned long *i, *j;

	i = (unsigned long *)_get_ssp();
	j = __builtin_frame_address(0);

	printf("[INFO]\tBefore: rbp + 8:0x%p content=0x%lx; ssp=0x%p, ssp content=0x%lx\n",
	       j + 1, *(j + 1), i, *i);
	*(j + 1) = (unsigned long)hacked;
	printf("[INFO]\tAfter: rbp + 8:0x%p content=0x%lx; ssp=0x%p, ssp content=0x%lx\n",
	       j + 1, *(j + 1), i, *i);

	return 0;
}

/* check shadow stack wo core dump in child pid */
static void stack_wo_core(void)
{
	void *s = malloc(0x100000);

	if (fork() == 0)
		do_hack(s);
}

/* test shstk by clone way */
static int stack_clone(void)
{
	pid_t cid;

	void *child_stack = malloc(0x100000);

	if (!child_stack) {
		printf("[FAIL]\tmalloc child_stack failed!\n");
		return 1;
	}

	cid = clone(do_hack, /* function */
	child_stack + 0x100000,
	SIGCHLD,
	0 /*arg*/
	);

	if (cid == -1) {
		printf("[FAIL]\tclone failed!\n");
		free(child_stack);
		return 1;
	}

	printf("[INFO]\tparent=%d, child=%d\n", getpid(), cid);

	if (waitpid(cid, NULL, 0) == -1) {
		printf("[FAIL]\twaitpid() failed!\n");
		return 1;
	}
	printf("[INFO]\tchild exits!\n");

	free(child_stack);
	return 0;
}

/*
 * Check shadow stack address and content and
 * rbp address and protect address content
 */
static int shadow_stack_check(void)
{
	unsigned long y;
	unsigned long *bp_a, *ssp_a;
	unsigned long long size_bp, size_ssp;

	ssp_a = (unsigned long *)_get_ssp();
	bp_a = __builtin_frame_address(0);
	size_bp = sizeof(*(bp_a + 1));
	size_ssp = sizeof(*ssp_a);

	printf("[INFO]\t&y=0x%p\n", &y);
	printf("[INFO]\tbp=%p,bp+1=%p,*(bp+1):0x%lx(size:%lld) ssp=%p *ssp=0x%lx(size:%lld)\n",
	       bp_a, bp_a + 1, *(bp_a + 1), size_bp, ssp_a, *ssp_a, size_ssp);
	return 0;
}

static void usage(void)
{
	printf("Usage: [null | s1 | s2 | s3 | sl1 | sr | sn...]\n");
	printf("  null: no parm, stack add 2 test, should trigger #CP\n");
	printf("  s1: stack add 1 test\n");
	printf("  s2: stack add 2 test, should trigger #CP\n");
	printf("  s3: stack add 3 test\n");
	printf("  sl1: stack with long add 2 test\n");
	printf("  sr: stack change to random value\n");
	printf("  sn: stack change but no return\n");
	printf("  buf1: buffer overflow change stack base\n");
	printf("  buf2: buffer overflow not change stack base\n");
	printf("  snc: test shadow stack wo core dump\n");
	printf("  sc: test shadow stack by clone way\n");
	printf("  ssp: check shadow stack addr and content\n");
}

int main(int argc, char *argv[])
{
	unsigned long random = 0, *main_rbp, fake_bp[2];

	random = rand();

#ifdef __x86_64__
	asm("movq %%rbp,%0" : "=r"(main_rbp));
#else
	asm("mov %%ebp,%0" : "=r"(main_rbp));
#endif

	/*
	 * Mark real main rbp address and content to change the called function
	 * bp and sp.
	 */
	fake_bp[0] = *main_rbp;
	fake_bp[1] = *(main_rbp + 1);

	if (argc == 1) {
		usage();
		stack_add2_test();
	} else {
		if (strcmp(argv[1], "s1") == 0) {
			printf("[INFO]\ts1: stack + 1\n");
			stack_add1_test((unsigned long)&fake_bp[0]);
		} else if (strcmp(argv[1], "s2") == 0) {
			printf("[INFO]\ts2: stack rbp + 1\n");
			stack_add2_test();
		} else if (strcmp(argv[1], "s3") == 0) {
			printf("[INFO]\ts3: stack + 3\n");
			stack_add3_test();
		} else if (strcmp(argv[1], "sl1") == 0) {
			printf("[INFO]\tsl1: stack with long + 2, random:0x%lx\n",
			       random);
			stack_long2_test(random);
		} else if (strcmp(argv[1], "sr") == 0) {
			printf("[INFO]\tsr: stack changed to random value:0x%lx\n",
			       random);
			stack_random(random);
		} else if (strcmp(argv[1], "sn") == 0) {
			printf("[INFO]\tsn: stack changed but no return\n");
			stack_no_return();
		} else if (strcmp(argv[1], "buf1") == 0) {
			printf("buf1: buffer overflow change stack base\n");
			stack_buf_impact();
		} else if (strcmp(argv[1], "buf2") == 0) {
			printf("[INFO]\tbuf2: buffer overflow not change stack base\n");
			stack_buf_no_impact();
		} else if (strcmp(argv[1], "snc") == 0) {
			printf("[INFO]\tsnc: test shadow stack wo core dump\n");
			stack_wo_core();
		} else if (strcmp(argv[1], "sc") == 0) {
			printf("[INFO]\tsc: test shstk by stack clone way\n");
			stack_clone();
		} else if (strcmp(argv[1], "ssp") == 0) {
			printf("[INFO]\tssp: check shadow stack addr and content\n");
			shadow_stack_check();
		} else {
			usage();
			exit(1);
		}
	}

	printf("[RESULTS]\tParent pid=%d is done.\n", getpid());

	return 0;
}
