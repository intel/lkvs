// SPDX-License-Identifier: GPL-2.0
/* Copyright(c) 2025 Intel Corporation. All rights reserved. */
/*
 * This test case check the memory coherency in SMP system.
 * userage:
 * ./mem_co seed_file1 & ./mem_coh seed_file2 & ..
 */


#include <stdio.h>
#include <pthread.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

/*#define _DEBUG */
#ifdef _DEBUG
#define DEBUG(fmt, args...)    printf("%s: "fmt, __func__, ##args)
#else
#define DEBUG(args...)
#endif

#ifdef CONFIG_SMP
#define LOCK "lock ; "
#else
#define LOCK ""
#endif

#define CHK(x)  do { if ((x) == -1) { perror("x"); exit(1); } } while (0)

#define BLKSIZE (1024 * 1024) // 1M bytes

int fd, CK = 8, PNUM = 0;
struct stat   sbuf;
void *ADDR;

#ifdef ARCH_64
static inline void atomic_sub(int i, void *v)
{
	int old, new, ia64_intri_res;

	do {
		old = *(int *)v;
		new = old - i;
		__asm__ __volatile__(
			"mov ar.ccv=%0;;"
			::"rO" (old));
		__asm__ __volatile__(
			"cmpxchg8.acq %0=[%1],%2,ar.ccv"
			: "=r" (ia64_intri_res)
			: "r" (v), "r" (new)
			: "memory");
	} while (ia64_intri_res != old);

}
#else
static inline void atomic_sub(int i, void *v)
{
	__asm__ __volatile__(
		LOCK "subl %1,%0"
		: "=m" (*(int *)v)
		: "ir" (i), "m" (*(int *)v));
}
#endif

int get_p_num(void)
{
	int nb_cpu;
	char line[1024];
	FILE *f;

	f = fopen("/proc/cpuinfo", "r");
	if (f == NULL) {
		perror("  [-] fopen /proc/cpuinfo");
		return 1;
	}

	nb_cpu = 0;

	while (fgets(line, sizeof(line) - 1, f) != NULL) {
		line[1023] = 0;
		if (memcmp(line, "processor", 9) == 0)
			nb_cpu++;
	}
	fclose(f);
	return nb_cpu;

}

int get_system_mem(void)
{
	char mem_info[1024], *cp;
	FILE *fd;
	int i;

	fd = fopen("/proc/meminfo", "r");
	if (fd == NULL) {
		perror(" Can not open file /proc/cpuinfo:");
		return -1;
	}

	if (fgets(mem_info, 1023, fd) != NULL) {
		mem_info[1023] = 0;
		if (strstr(mem_info, "MemTotal:") != NULL) {
			cp = mem_info + strlen("MemTotal:");
			i = atoi(cp);
			DEBUG("this system have %d K memory\n", i);
		} else {
			printf("can not find MemTotal charcters in /proc/mem_info file\n");
			return -1;
		}
	}
	fclose(fd);
	return i;
}

void *threadfunc1(void *arg)
{
	int i, pgsize, fsize;
	int *ip;

	i = *(int *) arg;
	DEBUG("thread num is %d, thread pid is %u  sbuf.st_size is %u\n", i, pthread_self(), sbuf.st_size);
	fsize = sbuf.st_size;

	//sleep(10);
	pgsize = getpagesize();
	for (i = 0; i < CK; i++) {
		for (ip = ADDR, fsize = sbuf.st_size; fsize > 0; fsize -= sizeof(int)) {
			atomic_sub(1, ip);
			ip++;
		}
		//msync(ADDR, BLKSIZE, MS_ASYNC);
		usleep(10000);
	}
}


void *threadfunc2(void *arg)
{
	int i, j, k, l, t_num, memtotal, pgsize;
	int *ip, **mp;

	t_num = *(int *) arg;
	mp = malloc(sizeof(int *)*1024*1024*4);
	if (mp == NULL) {
		perror("malloc fail ");
		return NULL;
	}
	memtotal = get_system_mem();
	DEBUG("thread num is %d, thread pid is %u  system memory is %d KB\n", t_num, pthread_self(), memtotal);
	if (memtotal < 0)
		memtotal = 512000;

	pgsize = getpagesize();
	for (i = 0; i < memtotal/1024/PNUM; i++) {
		mp[i] = (int *)malloc(BLKSIZE);
		if (mp[i] == 0) {
			perror("malloc");
			break;
		}
		ip = mp[i];
		for (j = 0; j < BLKSIZE/pgsize/2; j++) {
			*ip = 'A';
			ip += pgsize/sizeof(int);
		}

	}
}


int main(int argc, char *argv[])
{
	pthread_t pid1[1024];
	pthread_t pid2[1024];
	int i, fsize, thr_num[1024];
	//int i, fsize;
	int *ip, initv = 0x7fffffff;

	if (argc < 2) {
		printf("no seed file\n");
		exit(1);
	}
	PNUM = get_p_num();
	if (PNUM  <= 1) {
		printf("it is not a SMP system; exit\n");
		exit(1);
	}

	CHK(fd = open(argv[1], O_RDWR));
	CHK(fstat(fd, &sbuf));

	fsize = sbuf.st_size;
	DEBUG("pagesize is %d, file size is %ud\n", getpagesize(), sbuf.st_size);
	if (fsize < BLKSIZE) {
		printf("%s size is too small\n", argv[1]);
		return -1;
	}

	ADDR = mmap(0, fsize, PROT_WRITE, MAP_SHARED, fd, 0);
	if (ADDR  == (void *)-1) {
		perror("mmap ");
		return -1;
	}
	for (fsize = sbuf.st_size, ip = ADDR; fsize > 0; fsize -= sizeof(int)) {
		*ip = initv;
		ip++;
	}

	for (fsize = sbuf.st_size, ip = ADDR; fsize > 0; fsize -= sizeof(int)) {
	//	DEBUG("cp value is %d initv is %d\n", *cp, initv);
		if (*ip != initv)
			break;
		ip++;
	}
	if (fsize == 0)
		DEBUG("set mem is OK\n");
	else {
		printf("set mem fail\n test failed\n");
		return -1;
	}
	for (i = 0; i < PNUM; i++) {
		thr_num[i] = i;
		if (pthread_create(&pid2[i], NULL, threadfunc2, &i) != 0)
			perror("phread_create");
	}
	sleep(8);
	for (i = 0; i < PNUM; i++) {
		thr_num[i] = i;
		if (pthread_create(&pid1[i], NULL, threadfunc1, &i) != 0)
			perror("phread_create");
	}

	for (i = 0; i < PNUM; i++)
		pthread_join(pid1[i], NULL);
	for (i = 0; i < PNUM; i++)
		pthread_join(pid2[i], NULL);

	for (fsize = sbuf.st_size, ip = ADDR; fsize > 0; fsize -= sizeof(int)) {
		if (*ip != (initv - PNUM * CK)) {
			printf("cp value is %d initv is %d\n", *ip, initv-PNUM * CK);
			printf("test FAIL\n");
			return -1;
		}
		ip++;
	}
	printf("PASS\n");
	DEBUG("test PASS\n init value is 0x%x final value is 0x%x\n", initv, initv-PNUM * CK);
	return 0;
}

