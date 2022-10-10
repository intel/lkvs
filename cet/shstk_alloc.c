// SPDX-License-Identifier: GPL-2.0
/*
 * shstk_alloc.c - allocate a new shadow stack buffer aligenment by instructions
 *
 * 1. Test shstk buffer allocation for one new shstk buffer
 * 2. Test rstorssp, saveprevssp, rdsspq to load new shstk buffer
 * 3. Test rstorssp, saveprevssp to restore the previous shstk buffer
 */

#define _GNU_SOURCE

#include <sys/mman.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <stdbool.h>
#include <x86intrin.h>

#define SHADOW_STACK_SET_TOKEN	0x1
#define __NR_map_shadow_stack 451

size_t shstk_size = 0x200000;

void *create_shstk(void)
{
	return (void *)syscall(__NR_map_shadow_stack, 0, shstk_size,
			       SHADOW_STACK_SET_TOKEN);
}

#if (__GNUC__ < 8) || (__GNUC__ == 8 && __GNUC_MINOR__ < 5)
int main(int argc, char *argv[])
{
	printf("BLOCK: compiler does not support CET.");
	return 2;
}
#else
void try_shstk(unsigned long new_ssp)
{
	unsigned long ssp0, ssp1, ssp2;

	printf("pid=%d\n", getpid());
	printf("new_ssp = %lx, *new_ssp = %lx\n",
		new_ssp, *((unsigned long *)new_ssp));

	ssp0 = _get_ssp();
	printf("changing ssp from %lx(*ssp:%lx) to %lx(%lx)\n",
	       ssp0, *((unsigned long *)ssp0), new_ssp,
	       *((unsigned long *)new_ssp));

	/* Make sure ssp address is aligned to 8 bytes */
	if ((ssp0 & 0xf) != 0) {
		ssp0 = (unsigned long)(ssp0 & -8);
		printf("ssp0 & (-8): %lx\n", ssp0);
	}
	asm volatile("rstorssp (%0)\n":: "r" (new_ssp));
	asm volatile("saveprevssp");
	ssp1 = _get_ssp();
	printf("ssp is now %lx, *ssp:%lx\n", ssp1, *((unsigned long *)ssp1));

	ssp0 -= 8;
	asm volatile("rstorssp (%0)\n":: "r" (ssp0));
	asm volatile("saveprevssp");

	ssp2 = _get_ssp();
	printf("ssp changed back: %lx, *ssp:%lx\n", ssp2,
	       *((unsigned long *)ssp2));
}

int main(int argc, char *argv[])
{
	void *shstk;
	unsigned long ssp, *asm_ssp, *bp;

	if (!_get_ssp()) {
		printf("[SKIP]\tshadow stack was disabled.\n");
		return 2;
	}

	ssp = _get_ssp();
	#ifdef __x86_64__
		asm volatile ("rdsspq %rbx");
		asm("movq %%rbx,%0" : "=r"(asm_ssp));
		asm("movq %%rbp,%0" : "=r"(bp));
	#else
		asm volatile ("rdsspd %ebx");
		asm("mov %%ebx,%0" : "=r"(asm_ssp));
		asm("mov %%ebp,%0" : "=r"(bp));
	#endif
	printf("Libc get_ssp -> ssp:%lx, content:%lx\n", ssp, *(long *)ssp);
	printf("Show: bp+1:%p, *(bp+1):0x%lx, asm_ssp:%p, *asm_ssp:0x%lx\n",
	       bp + 1, *(bp + 1), asm_ssp, *asm_ssp);
	shstk = create_shstk();
	if (shstk == MAP_FAILED) {
		printf("[FAIL]\tError creating shadow stack: %d\n", errno);
		return 1;
	}
	printf("Allocate new shstk addr:%p, content:%lx\n", shstk,
	       *(long *)shstk);
	try_shstk((unsigned long)shstk + shstk_size - 8);

	printf("[PASS]\tCreated and allocated new shstk addr test.\n");
	return 0;
}
#endif
