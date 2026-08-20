// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2025 Intel Corporation
//
// PKU (Protection Keys for Userspace) validation test.
// Tests rdpkru/wrpkru, pkey_alloc, pkey_mprotect, and enforcement.
// Compile: gcc -o pku_test pku_test.c

#define _GNU_SOURCE
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <setjmp.h>

static sigjmp_buf jmpbuf;
static sig_atomic_t got_sigsegv;

static inline unsigned int rdpkru(void)
{
	unsigned int eax, edx, ecx = 0;

	asm volatile(".byte 0x0f,0x01,0xee"
		     : "=a"(eax), "=d"(edx)
		     : "c"(ecx));
	return eax;
}

static inline void wrpkru(unsigned int pkru)
{
	unsigned int ecx = 0, edx = 0;

	asm volatile(".byte 0x0f,0x01,0xef"
		     : : "a"(pkru), "c"(ecx), "d"(edx));
}

static void sigsegv_handler(int sig)
{
	(void)sig;
	got_sigsegv = 1;
	siglongjmp(jmpbuf, 1);
}

int main(void)
{
	unsigned int pkru;
	void *ptr;
	int pkey;
	struct sigaction sa;

	/* Test 1: rdpkru/wrpkru basic operation */
	wrpkru(0x55555554);
	pkru = rdpkru();
	if (pkru != 0x55555554) {
		printf("FAIL: wrpkru/rdpkru mismatch: got 0x%08x\n", pkru);
		return 1;
	}
	printf("PASS: wrpkru/rdpkru works\n");
	wrpkru(0x0);

	/* Test 2: pkey_alloc */
	pkey = pkey_alloc(0, 0);
	if (pkey < 0) {
		printf("FAIL: pkey_alloc\n");
		return 1;
	}
	printf("PASS: pkey_alloc ok (pkey=%d)\n", pkey);

	/* Test 3: pkey_mprotect */
	ptr = mmap(NULL, 4096, PROT_READ | PROT_WRITE,
		   MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);
	if (ptr == MAP_FAILED) {
		printf("FAIL: mmap\n");
		return 1;
	}
	if (pkey_mprotect(ptr, 4096, PROT_READ | PROT_WRITE, pkey) != 0) {
		printf("FAIL: pkey_mprotect\n");
		return 1;
	}
	printf("PASS: pkey_mprotect ok\n");

	/* Write data while access is permitted */
	*((int *)ptr) = 0xdeadbeef;

	/* Test 4: PKU enforcement - disable write access via PKRU */
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = sigsegv_handler;
	sigemptyset(&sa.sa_mask);
	sigaction(SIGSEGV, &sa, NULL);

	/* Set AD (access disable) bit for this pkey: bit (2*pkey) */
	got_sigsegv = 0;
	wrpkru(1U << (2 * pkey + 1));  /* WD bit = write disable */

	if (sigsetjmp(jmpbuf, 1) == 0) {
		/* Attempt write to pkey-protected page - should fault */
		*((int *)ptr) = 0x12345678;
		/* If we reach here, enforcement failed */
		wrpkru(0x0);
		printf("FAIL: write to WD-protected page did not fault\n");
		return 1;
	}

	/* Restore PKRU and verify we caught the fault */
	wrpkru(0x0);
	if (!got_sigsegv) {
		printf("FAIL: did not receive SIGSEGV\n");
		return 1;
	}
	printf("PASS: PKU write-disable enforcement works (SIGSEGV caught)\n");

	/* Test 5: access disable */
	got_sigsegv = 0;
	wrpkru(1U << (2 * pkey));  /* AD bit = access disable */

	if (sigsetjmp(jmpbuf, 1) == 0) {
		/* Attempt read from pkey-protected page - should fault */
		int tmp = *((int *)ptr);
		(void)tmp;
		wrpkru(0x0);
		printf("FAIL: read from AD-protected page did not fault\n");
		return 1;
	}

	wrpkru(0x0);
	if (!got_sigsegv) {
		printf("FAIL: did not receive SIGSEGV on read\n");
		return 1;
	}
	printf("PASS: PKU access-disable enforcement works (SIGSEGV caught)\n");

	pkey_free(pkey);
	munmap(ptr, 4096);

	printf("all tests OK\n");
	return 0;
}
