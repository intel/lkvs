// SPDX-License-Identifier: GPL-2.0-only
/* A guest data load from a page whose EPT PTE cache line is poisoned. */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define PAGE_BYTES 4096
#define REGION_BYTES (1024 * 1024)

static int guest_physical_address(void *ptr, unsigned long long *gpa)
{
	unsigned long long entry;
	uintptr_t va = (uintptr_t)ptr;
	off_t offset = (off_t)((va / PAGE_BYTES) * sizeof(entry));
	int fd = open("/proc/self/pagemap", O_RDONLY);

	if (fd < 0) {
		perror("open pagemap (run as guest root)");
		return -1;
	}
	if (pread(fd, &entry, sizeof(entry), offset) != sizeof(entry)) {
		perror("pread pagemap");
		close(fd);
		return -1;
	}
	close(fd);
	if (!(entry & (1ULL << 63)) || !(entry & ((1ULL << 55) - 1))) {
		fprintf(stderr, "Guest page absent or PFN hidden by pagemap\n");
		return -1;
	}
	*gpa = ((entry & ((1ULL << 55) - 1)) << 12) | (va & 0xfff);
	return 0;
}

int main(int argc, char **argv)
{
	int *target;
	unsigned char *region;
	unsigned long long gpa;
	char trigger;
	int fd;
	int value;
	size_t i;

	if (argc != 2 || sysconf(_SC_PAGESIZE) != PAGE_BYTES) {
		fprintf(stderr, "Usage: %s /path/to/trigger.fifo (4K guest pages)\n",
			argv[0]);
		return 2;
	}
	region = mmap(NULL, REGION_BYTES, PROT_READ | PROT_WRITE | PROT_EXEC,
		      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (region == MAP_FAILED) {
		perror("mmap executable region");
		return 2;
	}
	for (i = 0; i < REGION_BYTES; i += PAGE_BYTES)
		__atomic_store_n(&region[i], 0, __ATOMIC_RELAXED);

	/* Execute this page once so KVM can split a huge EPT NX mapping. */
	memset(region, 0x90, PAGE_BYTES);
	region[PAGE_BYTES - 1] = 0xc3; /* ret */
	__builtin___clear_cache((char *)region, (char *)region + PAGE_BYTES);
	((void (*)(void))region)();

	if (guest_physical_address(region, &gpa)) {
		munmap(region, REGION_BYTES);
		return 2;
	}
	target = (int *)region;
	__atomic_store_n(target, 10086, __ATOMIC_RELAXED);
	printf("READY gva=%p gpa=0x%llx\n", (void *)region, gpa);
	fflush(stdout);

	/* Blocks until the host releases us after VM resume and EINJ. */
	fd = open(argv[1], O_RDONLY);
	if (fd < 0 || read(fd, &trigger, 1) != 1) {
		fprintf(stderr, "Trigger FIFO failed: %s\n", strerror(errno));
		if (fd >= 0)
			close(fd);
		munmap(region, REGION_BYTES);
		return 2;
	}
	close(fd);
	printf("TRIGGERED gpa=0x%llx\n", gpa);
	fflush(stdout);

	value = __atomic_load_n(target, __ATOMIC_RELAXED);
	printf("LOAD_OK value=%d\n", value);
	fflush(stdout);
	munmap(region, REGION_BYTES);
	return value == 10086 ? 0 : 1;
}
