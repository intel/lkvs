// SPDX-License-Identifier: GPL-2.0
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <signal.h>
#include <setjmp.h>
#include <sys/mman.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <inttypes.h>
#include <sched.h>
#include <unistd.h>
#include <libgen.h>

#include <sys/uio.h>
#include <linux/io_uring.h>
#include <cpuid.h>
#include <linux/types.h>
#include <stddef.h>

#define ARRAY_SIZE(a)           (sizeof(a) / sizeof((a)[0])) // mainline has no this line

#ifndef __x86_64__
# error This test is 64-bit only
#endif

/* LAM modes, these definitions were copied from kernel code */
#define LAM_NONE                0
#define LAM_U57_BITS            6

#define LAM_U57_MASK            (0x3fULL << 57)

/* arch prctl for LAM */
#define ARCH_GET_UNTAG_MASK     0x4001
#define ARCH_ENABLE_TAGGED_ADDR 0x4002
#define ARCH_GET_MAX_TAG_BITS   0x4003
#define ARCH_FORCE_TAGGED_SVM	0x4004

/* Specified test function bits */
#define FUNC_MALLOC             0x1
#define FUNC_BITS               0x2
#define FUNC_MMAP               0x4
#define FUNC_SYSCALL            0x8
#define FUNC_URING              0x10
#define FUNC_INHERITE           0x20
#define FUNC_PASID              0x40
#define FUNC_CPUID              0x80
#define FUNC_CONFIG             0x100

#define TEST_MASK               0x1ff

#define LOW_ADDR                (0x1UL << 30)
#define HIGH_ADDR               (0x3UL << 48)

#define MALLOC_LEN              32

#define PAGE_SIZE               (4 << 10)

#define STACK_SIZE		(4 << 10) //mainline 65536

#define barrier() ({\
		   __asm__ __volatile__("" : : : "memory");	\
})

#define URING_QUEUE_SZ 1
#define URING_BLOCK_SZ 2048

/* Pasid test define */
#define LAM_CMD_BIT 0x1
#define PAS_CMD_BIT 0x2
#define SVM_CMD_BIT 0x4

#define PAS_CMD(cmd1, cmd2, cmd3) (((cmd3) << 8) | ((cmd2) << 4) | ((cmd1) << 0))

struct testcases {
	unsigned int later;
	int expected; /* 2: SIGSEGV Error; 1: other errors */
	unsigned long lam;
	__u64 addr;
	__u64 cmd;
	int (*test_func)(struct testcases *test);
	const char *msg;
};

/* Used by CQ of uring, source file handler and file's size */
struct file_io {
	int file_fd;
	off_t file_sz;
	struct iovec iovecs[];
};

struct io_uring_queue {
	unsigned int *head;
	unsigned int *tail;
	unsigned int *ring_mask;
	unsigned int *ring_entries;
	unsigned int *flags;
	unsigned int *array;
	union {
		struct io_uring_cqe *cqes;
		struct io_uring_sqe *sqes;
	} queue;
	size_t ring_sz;
};

struct io_ring {
	int ring_fd;
	struct io_uring_queue sq_ring;
	struct io_uring_queue cq_ring;
};

int tests_cnt;
int tests_pass;
jmp_buf segv_env;

static void segv_handler(int sig)
{
	printf("Get segmentation fault(%d).", sig);

	siglongjmp(segv_env, 1);
}

static inline int cpu_has_lam(void)
{
	unsigned int cpuinfo[4];

	__cpuid_count(0x7, 1, cpuinfo[0], cpuinfo[1], cpuinfo[2], cpuinfo[3]);

	return (cpuinfo[0] & (1 << 26));
}

/* Check 5-level page table feature in CPUID.(EAX=07H, ECX=00H):ECX.[bit 16] */
static inline int cpu_has_la57(void)
{
	unsigned int cpuinfo[4];

	__cpuid_count(0x7, 0, cpuinfo[0], cpuinfo[1], cpuinfo[2], cpuinfo[3]);

	return (cpuinfo[2] & (1 << 16));
}

/*
 * Set tagged address and read back untag mask.
 * check if the untagged mask is expected.
 *
 * @return:
 * 0: Set LAM mode successfully
 * others: failed to set LAM
 */
static int set_lam(unsigned long lam)
{
	int ret = 0;
	__u64 ptr = 0;

	if (lam != LAM_U57_BITS && lam != LAM_NONE)
		return -1;

	/* Skip check return */
	syscall(SYS_arch_prctl, ARCH_ENABLE_TAGGED_ADDR, lam);

	/* Get untagged mask */
	syscall(SYS_arch_prctl, ARCH_GET_UNTAG_MASK, &ptr);

	/* Check mask returned is expected */
	if (lam == LAM_U57_BITS)
		ret = (ptr != ~(LAM_U57_MASK));
	else if (lam == LAM_NONE)
		ret = (ptr != -1ULL);

	return ret;
}

static unsigned long get_default_tag_bits(void)
{
	pid_t pid;
	int lam = LAM_NONE;
	int ret = 0;

	pid = fork();
	if (pid < 0) {
		perror("Fork failed.");
	} else if (pid == 0) {
		/* Set LAM mode in child process */
		if (set_lam(LAM_U57_BITS) == 0)
			lam = LAM_U57_BITS;
		else
			lam = LAM_NONE;
		exit(lam);
	} else {
		wait(&ret);
		lam = WEXITSTATUS(ret);
	}

	return lam;
}

/*
 * Set tagged address and read back untag mask.
 * check if the untag mask is expected.
 */
static int get_lam(void)
{
	__u64 ptr = 0;
	int ret = -1;
	/* Get untagged mask */
	if (syscall(SYS_arch_prctl, ARCH_GET_UNTAG_MASK, &ptr) == -1)
		return -1;

	/* Check mask returned is expected */
	if (ptr == ~(LAM_U57_MASK))
		ret = LAM_U57_BITS;
	else if (ptr == -1ULL)
		ret = LAM_NONE;

	return ret;
}

/* According to LAM mode, set metadata in high bits */
static __u64 set_metadata(__u64 src, unsigned long lam)
{
	__u64 metadata;

	srand(time(NULL));
	/* Get a random value as metadata */
	metadata = rand();

	switch (lam) {
	case LAM_U57_BITS: /* Set metadata in bits 62:57 */
	/* Get a random non-zero value as metadata */
	metadata = (rand() % ((1UL << LAM_U57_BITS) - 1) + 1) << 57;
	metadata |= (src & ~(LAM_U57_MASK));
	/* ddt old way*/
	//metadata = (src & ~(LAM_U57_MASK)) | ((metadata & 0x3f) << 57);
	break;
	default:
		metadata = src;
		break;
	}

	return metadata;
}

/*
 * Set metadata in user pointer, compare new pointer with original pointer.
 * both pointers should point to the same address.
 *
 * @return:
 * 0: value on the pointer with metadate and value on original are same
 * 1: not same.
 */
static int handle_lam_test(void *src, unsigned int lam)
{
	char *ptr;

	strcpy((char *)src, "USER POINTER");

	ptr = (char *)set_metadata((__u64)src, lam);
	if (src == ptr)
		return 0;

	/* Copy a string into the pointer with metadata */
	strcpy((char *)ptr, "METADATA POINTER");

	return (!!strcmp((char *)src, (char *)ptr));
}

int handle_max_bits(struct testcases *test)
{
	void *ptr;
	unsigned int flags = MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED;
	unsigned long exp_bits = get_default_tag_bits();
	unsigned long bits = 0;

	if (exp_bits != LAM_NONE)
		exp_bits = LAM_U57_BITS;

	ptr = mmap((void *)test->addr, PAGE_SIZE, PROT_READ | PROT_WRITE,
		   flags, -1, 0);
	if (ptr == MAP_FAILED) {
		if (test->addr == HIGH_ADDR)
			if (!cpu_has_la57())
				return 3; /* unsupported LA57 */

		return 1;
	}

	/* Get LAM max tag bits */
	if (syscall(SYS_arch_prctl, ARCH_GET_MAX_TAG_BITS, &bits) == -1)
		return 1;

	return (exp_bits != bits);
}

/*
 * Test lam feature through dereference pointer get from malloc.
 * @return 0: Pass test. 1: Get failure during test 2: Get SIGSEGV
 */
static int handle_malloc(struct testcases *test)
{
	char *ptr = NULL;
	int ret = 0;

	if (test->later == 0 && test->lam != 0)
		if (set_lam(test->lam) == -1)
			return 1;

	ptr = (char *)malloc(MALLOC_LEN);
	if (!ptr) {
		perror("malloc() failure\n");
		return 1;
	}

	/* Set signal handler */
	if (sigsetjmp(segv_env, 1) == 0) {
		signal(SIGSEGV, segv_handler);
		ret = handle_lam_test(ptr, test->lam);
	} else {
		ret = 2;
	}

	if (test->later != 0 && test->lam != 0)
		if (set_lam(test->lam) == -1 && ret == 0)
			ret = 1;

	free(ptr);

	return ret;
}

static int handle_mmap(struct testcases *test)
{
	void *ptr;
	unsigned int flags = MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED;
	int ret = 0;

	if (test->later == 0 && test->lam != 0)
		if (set_lam(test->lam) != 0)
			return 1;

	ptr = mmap((void *)test->addr, PAGE_SIZE, PROT_READ | PROT_WRITE, flags, -1, 0);
	if (ptr == MAP_FAILED) {
		if (test->addr == HIGH_ADDR) {
			if (!cpu_has_la57())
				return 3; /* unsupported LA57 */
			else
				return 1; /* support LA57 */
		} else {
			return 1;
		}
	}

	if (test->later != 0 && test->lam != 0)
		if (set_lam(test->lam) != 0)
			ret = 1;

	if (ret == 0) {
		if (sigsetjmp(segv_env, 1) == 0) {
			signal(SIGSEGV, segv_handler);
			ret = handle_lam_test(ptr, test->lam);
		} else {
			ret = 2;
		}
	}

	munmap(ptr, PAGE_SIZE);
	return ret;
}

static int handle_syscall(struct testcases *test)
{
	struct utsname unme, *pu;
	int ret = 0;

	if (test->later == 0 && test->lam != 0)
		if (set_lam(test->lam) != 0)
			return 1;

	if (sigsetjmp(segv_env, 1) == 0) {
		signal(SIGSEGV, segv_handler);
		pu = (struct utsname *)set_metadata((__u64)&unme, test->lam);
		ret = uname(pu);
		if (ret < 0)
			ret = 1;
	} else {
		ret = 2;
	}

	if (test->later != 0 && test->lam != 0)
		if (set_lam(test->lam) != -1 && ret == 0)
			ret = 1;

	return ret;
}

int sys_uring_setup(unsigned int entries, struct io_uring_params *p)
{
	return (int)syscall(__NR_io_uring_setup, entries, p);
}

int sys_uring_enter(int fd, unsigned int to, unsigned int min, unsigned int flags)
{
	return (int)syscall(__NR_io_uring_enter, fd, to, min, flags, NULL, 0);
}

/* Init submission queue and completion queue */
int mmap_io_uring(struct io_uring_params p, struct io_ring *s)
{
	struct io_uring_queue *s_ring = &s->sq_ring;
	struct io_uring_queue *c_ring = &s->cq_ring;

	s_ring->ring_sz = p.sq_off.array + p.sq_entries * sizeof(unsigned int);
	c_ring->ring_sz = p.cq_off.cqes + p.cq_entries * sizeof(struct io_uring_cqe);

	if (p.features & IORING_FEAT_SINGLE_MMAP) {
		if (c_ring->ring_sz > s_ring->ring_sz)
			s_ring->ring_sz = c_ring->ring_sz;

		c_ring->ring_sz = s_ring->ring_sz;
	}

	void *sq_ptr = mmap(0, s_ring->ring_sz, PROT_READ | PROT_WRITE,
			    MAP_SHARED | MAP_POPULATE, s->ring_fd,
			    IORING_OFF_SQ_RING);

	if (sq_ptr == MAP_FAILED) {
		perror("sub-queue!");
		return 1;
	}

	void *cq_ptr = sq_ptr;

	if (!(p.features & IORING_FEAT_SINGLE_MMAP)) {
		cq_ptr = mmap(0, c_ring->ring_sz, PROT_READ | PROT_WRITE,
			      MAP_SHARED | MAP_POPULATE, s->ring_fd,
			      IORING_OFF_CQ_RING);
		if (cq_ptr == MAP_FAILED) {
			perror("cpl-queue!");
			munmap(sq_ptr, s_ring->ring_sz);
			return 1;
		}
	}

	s_ring->head = sq_ptr + p.sq_off.head;
	s_ring->tail = sq_ptr + p.sq_off.tail;
	s_ring->ring_mask = sq_ptr + p.sq_off.ring_mask;
	s_ring->ring_entries = sq_ptr + p.sq_off.ring_entries;
	s_ring->flags = sq_ptr + p.sq_off.flags;
	s_ring->array = sq_ptr + p.sq_off.array;

	/* Map a queue as mem map */
	s->sq_ring.queue.sqes = mmap(0, p.sq_entries * sizeof(struct io_uring_sqe),
				     PROT_READ | PROT_WRITE, MAP_SHARED | MAP_POPULATE,
				     s->ring_fd, IORING_OFF_SQES);
	if (s->sq_ring.queue.sqes == MAP_FAILED) {
		munmap(sq_ptr, s_ring->ring_sz);
		if (sq_ptr != cq_ptr) {
			printf("failed to mmap uring queue!");
			munmap(cq_ptr, c_ring->ring_sz);
			return 1;
		}
	}

	c_ring->head = cq_ptr + p.cq_off.head;
	c_ring->tail = cq_ptr + p.cq_off.tail;
	c_ring->ring_mask = cq_ptr + p.cq_off.ring_mask;
	c_ring->ring_entries = cq_ptr + p.cq_off.ring_entries;
	c_ring->queue.cqes = cq_ptr + p.cq_off.cqes;

	return 0;
}

/* Init io_uring queues */
int setup_io_uring(struct io_ring *s)
{
	struct io_uring_params para;

	memset(&para, 0, sizeof(para));
	s->ring_fd = sys_uring_setup(URING_QUEUE_SZ, &para);
	if (s->ring_fd < 0)
		return 1;

	return mmap_io_uring(para, s);
}

/*
 * Get data from completion queue. the data buffer saved the file data
 * return 0: success; others: error;
 */
int handle_uring_cq(struct io_ring *s)
{
	struct file_io *fi = NULL;
	struct io_uring_queue *cring = &s->cq_ring;
	struct io_uring_cqe *cqe;
	unsigned int head;
	off_t len = 0;

	head = *cring->head;

	do {
		barrier();
		if (head == *cring->tail)
			break;
		/* Get the entry */
		cqe = &cring->queue.cqes[head & *s->cq_ring.ring_mask];
		fi = (struct file_io *)cqe->user_data;
		if (cqe->res < 0)
			break;

		int blocks = (int)(fi->file_sz + URING_BLOCK_SZ - 1) / URING_BLOCK_SZ;

		for (int i = 0; i < blocks; i++)
			len += fi->iovecs[i].iov_len;

		head++;
	} while (1);

	*cring->head = head;
	barrier();

	return (len != fi->file_sz);
}

/*
 * Submit squeue. specify via IORING_OP_READV.
 * the buffer need to be set metadata according to LAM mode
 */
int handle_uring_sq(struct io_ring *ring, struct file_io *fi, unsigned long lam)
{
	int file_fd = fi->file_fd;
	struct io_uring_queue *s_ring = &ring->sq_ring;
	unsigned int index = 0, cur_block = 0, tail = 0, next_tail = 0;
	struct io_uring_sqe *sqe;

	off_t remain = fi->file_sz;
	int blocks = (int)(remain + URING_BLOCK_SZ - 1) / URING_BLOCK_SZ;

	while (remain) {
		off_t bytes = remain;
		void *buf;

		if (bytes > URING_BLOCK_SZ)
			bytes = URING_BLOCK_SZ;

		fi->iovecs[cur_block].iov_len = bytes;

		if (posix_memalign(&buf, URING_BLOCK_SZ, URING_BLOCK_SZ))
			return 1;

		fi->iovecs[cur_block].iov_base = (void *)set_metadata((__u64)buf, lam);
		remain -= bytes;
		cur_block++;
	}

	next_tail = *s_ring->tail;
	tail = next_tail;
	next_tail++;

	barrier();

	index = tail & *ring->sq_ring.ring_mask;

	sqe = &ring->sq_ring.queue.sqes[index];
	sqe->fd = file_fd;
	sqe->flags = 0;
	sqe->opcode = IORING_OP_READV;
	sqe->addr = (unsigned long)fi->iovecs;
	sqe->len = blocks;
	sqe->off = 0;
	sqe->user_data = (__u64)fi;

	s_ring->array[index] = index;
	tail = next_tail;

	if (*s_ring->tail != tail) {
		*s_ring->tail = tail;
		barrier();
	}

	if (sys_uring_enter(ring->ring_fd, 1, 1, IORING_ENTER_GETEVENTS) < 0)
		return 1;

	return 0;
}

/*
 * Test LAM in async I/O and io_uring, read current binery through io_uring
 * Set metadata in pointers to iovecs buffer.
 */
int do_uring(unsigned long lam)
{
	struct io_ring *ring;
	struct file_io *fi;
	struct stat st;
	int ret = 1;
	char path[PATH_MAX] = {0};

	/* get current process path */
	if (readlink("/proc/self/exe", path, PATH_MAX) <= 0)
		return 1;

	int file_fd = open(path, O_RDONLY);

	if (file_fd < 0)
		return 1;

	if (fstat(file_fd, &st) < 0)
		return 1;

	off_t file_sz = st.st_size;

	int blocks = (int)(file_sz + URING_BLOCK_SZ - 1) / URING_BLOCK_SZ;

	fi = malloc(sizeof(*fi) + sizeof(struct iovec) * blocks);
	if (!fi)
		return 1;

	fi->file_sz = file_sz;
	fi->file_fd = file_fd;

	ring = malloc(sizeof(*ring));
	if (!ring)
		return 1;

	memset(ring, 0, sizeof(struct io_ring));

	if (setup_io_uring(ring))
		goto out;

	if (handle_uring_sq(ring, fi, lam))
		goto out;

	ret = handle_uring_cq(ring);

out:
	free(ring);

	for (int i = 0; i < blocks; i++) {
		if (fi->iovecs[i].iov_base) {
			__u64 addr = ((__u64)fi->iovecs[i].iov_base);

			switch (lam) {
			case LAM_U57_BITS: /* Clear bits 62:57 */
				addr = (addr & ~(LAM_U57_MASK));
				break;
			}
			free((void *)addr);
			fi->iovecs[i].iov_base = NULL;
		}
	}

	free(fi);

	return ret;
}

int handle_uring(struct testcases *test)
{
	int ret = 0;

	if (test->later == 0 && test->lam != 0)
		if (set_lam(test->lam) != 0)
			return 1;

	if (sigsetjmp(segv_env, 1) == 0) {
		signal(SIGSEGV, segv_handler);
		ret = do_uring(test->lam);
	} else {
		ret = 2;
	}

	return ret;
}

static int fork_test(struct testcases *test)
{
	int ret, child_ret;
	pid_t pid;

	pid = fork();
	if (pid < 0) {
		perror("Fork failed.");
		ret = 1;
	} else if (pid == 0) {
		ret = test->test_func(test);
		exit(ret);
	} else {
		wait(&child_ret);
		ret = WEXITSTATUS(child_ret);
	}

	return ret;
}

static int handle_execve(struct testcases *test)
{
	int ret, child_ret;
	int lam = test->lam;
	pid_t pid;

	pid = fork();
	if (pid < 0) {
		perror("Fork failed.");
		ret = 1;
	} else if (pid == 0) {
		char path[PATH_MAX] = {0};

		/* Set LAM mode in parent process */
		if (set_lam(lam) != 0)
			return 1;

		/* Get current binary's path and the binary was run by execve */
		if (readlink("/proc/self/exe", path, PATH_MAX) <= 0)
			exit(-1);

		/* run binary to get LAM mode and return to parent process */
		printf("%s\n", path);
		if (execlp(path, path, "-t 0x0", NULL) < 0) {
			perror("error on exec");
			exit(-1);
		}
	} else {
		wait(&child_ret);
		ret = WEXITSTATUS(child_ret);
		if (ret != LAM_NONE)
			return 1;
	}

	return 0;
}

static int handle_inheritance(struct testcases *test)
{
	int ret, child_ret;
	int lam = test->lam;
	pid_t pid;

	/* Set LAM mode in parent process */
	if (set_lam(lam) != 0)
		return 1;

	pid = fork();
	if (pid < 0) {
		perror("Fork failed.");
		return 1;
	} else if (pid == 0) {
		/* Set LAM mode in parent process */
		int child_lam = get_lam();

		exit(child_lam);
	} else {
		wait(&child_ret);
		ret = WEXITSTATUS(child_ret);

		if (lam != ret)
			return 1;
	}

	return 0;
}

static int thread_fn_get_lam(void *arg)
{
	return get_lam();
}

static int thread_fn_set_lam(void *arg)
{
	struct testcases *test = arg;

	return set_lam(test->lam);
}

static int handle_thread(struct testcases *test)
{
	char stack[STACK_SIZE];
	int ret, child_ret;
	int lam = 0;
	pid_t pid;

	/* Set LAM mode in parent process */
	if (!test->later) {
		lam = test->lam;
		if (set_lam(lam) != 0)
			return 1;
	}

	pid = clone(thread_fn_get_lam, stack + STACK_SIZE,
		    SIGCHLD | CLONE_FILES | CLONE_FS | CLONE_VM, NULL);
	if (pid < 0) {
		perror("Clone failed.");
		return 1;
	}

	waitpid(pid, &child_ret, 0);
	ret = WEXITSTATUS(child_ret);

	if (lam != ret)
		return 1;

	if (test->later) {
		if (set_lam(test->lam) != 0)
			return 1;
	}

	return 0;
}

static int handle_thread_enable(struct testcases *test)
{
	char stack[STACK_SIZE];
	int ret, child_ret;
	int lam = test->lam;
	pid_t pid;

	pid = clone(thread_fn_set_lam, stack + STACK_SIZE,
		    SIGCHLD | CLONE_FILES | CLONE_FS | CLONE_VM, test);
	if (pid < 0) {
		perror("Clone failed.");
		return 1;
	}

	waitpid(pid, &child_ret, 0);
	ret = WEXITSTATUS(child_ret);

	if (lam != ret)
		return 1;

	return 0;
}

int handle_cpuid(struct testcases *test)
{
	int ret = 0;

	if (cpu_has_lam())
		ret = 0; /* LAM CPUID is supported */
	else
		ret = 1; /* LAM CPUID is not supported */

	return ret;
}

int handle_config(struct testcases *test)
{
	int ret = 0;
	char command[256];
	char result[16];
	FILE *fp;

	/* Use shell script to check CONFIG_ADDRESS_MASKING */
	snprintf(command, sizeof(command),
		 "source %s/../common/common.sh; get_kconfig CONFIG_ADDRESS_MASKING",
		 dirname(realpath("/proc/self/exe", NULL)));

	fp = popen(command, "r");
	if (!fp) {
		printf("Failed to execute shell command\n");
		return 1;
	}

	if (fgets(result, sizeof(result), fp)) {
		/* Remove newline */
		result[strcspn(result, "\n")] = 0;
		if (strcmp(result, "y") == 0) {
			printf("CONFIG_ADDRESS_MASKING=y is set\n");
			ret = 0;
		} else {
			printf("CONFIG_ADDRESS_MASKING is not set to 'y', value: %s\n", result);
			ret = 1;
		}
	} else {
		printf("Failed to read config value\n");
		ret = 1;
	}

	pclose(fp);
	return ret;
}

static void run_test(struct testcases *test, int count)
{
	int i, ret = 0;

	for (i = 0; i < count; i++) {
		struct testcases *t = test + i;

		/* fork a process to run test case */
		tests_cnt++;
		ret = fork_test(t);

		/* return 3 is not support LA57, the case should be skipped */
		if (ret == 3) {
			tests_pass++;
			printf("[SKIP] No:%d %s", tests_cnt, t->msg);
			continue;
		}

		if (ret != 0)
			ret = (t->expected == ret);
		else
			ret = !(t->expected);

		if (ret == 1) {
			tests_pass++;
			printf("[PASS] No:%d %s", tests_cnt, t->msg);
		} else {
			printf("[FAIL] No:%d %s", tests_cnt, t->msg);
		}
	}
}

static struct testcases uring_cases[] = {
	{
		.later = 0,
		.lam = LAM_U57_BITS,
		.test_func = handle_uring,
		.msg = "URING: LAM_U57. Dereferencing pointer with metadata\n",
	},
	{
		.later = 1,
		.expected = 1,
		.lam = LAM_U57_BITS,
		.test_func = handle_uring,
		.msg = "URING:[Negative] Disable LAM. Dereferencing pointer with metadata.\n",
	},
};

static struct testcases malloc_cases[] = {
	{
		.later = 0,
		.lam = LAM_U57_BITS,
		.test_func = handle_malloc,
		.msg = "MALLOC: LAM_U57. Dereferencing pointer with metadata\n",
	},
	{
		.later = 1,
		.expected = 2,
		.lam = LAM_U57_BITS,
		.test_func = handle_malloc,
		.msg = "MALLOC:[Negative] Disable LAM. Dereferencing pointer with metadata.\n",
	},
};

static struct testcases bits_cases[] = {
	{
		.test_func = handle_max_bits,
		.msg = "BITS: Check default tag bits\n",
	},
};

static struct testcases syscall_cases[] = {
	{
		.later = 0,
		.lam = LAM_U57_BITS,
		.test_func = handle_syscall,
		.msg = "SYSCALL: LAM_U57. syscall with metadata\n",
	},
	{
		.later = 1,
		.expected = 1,
		.lam = LAM_U57_BITS,
		.test_func = handle_syscall,
		.msg = "SYSCALL:[Negative] Disable LAM. Dereferencing pointer with metadata.\n",
	},
};

static struct testcases mmap_cases[] = {
	{
		.later = 1,
		.expected = 0,
		.lam = LAM_U57_BITS,
		.addr = HIGH_ADDR,
		.test_func = handle_mmap,
		.msg = "MMAP: First mmap high address, then set LAM_U57.\n",
	},
	{
		.later = 0,
		.expected = 0,
		.lam = LAM_U57_BITS,
		.addr = HIGH_ADDR,
		.test_func = handle_mmap,
		.msg = "MMAP: First LAM_U57, then High address.\n",
	},
	{
		.later = 0,
		.expected = 0,
		.lam = LAM_U57_BITS,
		.addr = LOW_ADDR,
		.test_func = handle_mmap,
		.msg = "MMAP: First LAM_U57, then Low address.\n",
	},
};

static struct testcases inheritance_cases[] = {
	{
		.expected = 0,
		.lam = LAM_U57_BITS,
		.test_func = handle_inheritance,
		.msg = "FORK: LAM_U57, child process should get LAM mode same as parent\n",
	},
	{
		.expected = 0,
		.lam = LAM_U57_BITS,
		.test_func = handle_thread,
		.msg = "THREAD: LAM_U57, child thread should get LAM mode same as parent\n",
	},
	{
		.expected = 1,
		.lam = LAM_U57_BITS,
		.test_func = handle_thread_enable,
		.msg = "THREAD: [NEGATIVE] Enable LAM in child.\n",
	},
	{
		.expected = 1,
		.later = 1,
		.lam = LAM_U57_BITS,
		.test_func = handle_thread,
		.msg = "THREAD: [NEGATIVE] Enable LAM in parent after thread created.\n",
	},
	{
		.expected = 0,
		.lam = LAM_U57_BITS,
		.test_func = handle_execve,
		.msg = "EXECVE: LAM_U57, child process should get disabled LAM mode\n",
	},
};

static void cmd_help(void)
{
	printf("usage: lam [-h] [-t test list]\n");
	printf("\t-t test list: run tests specified in the test list, default:0x%x\n", TEST_MASK);
	printf("\t\t0x1:malloc;\n");
	printf("\t\t0x2:max_bits;\n");
	printf("\t\t0x4:mmap;\n");
	printf("\t\t0x8:syscall;\n");
	printf("\t\t0x10:io_uring;\n");
	printf("\t\t0x20:inherit;\n");
	printf("\t\t0x40:pasid;\n");
	printf("\t\t0x80:cpuid;\n");
	printf("\t\t0x100:config;\n");

	printf("\t-h: help\n");
}

/* Check for file existence */
__u8 file_exists(const char *file_name)
{
	struct stat buffer;

	__u8 ret = (stat(file_name, &buffer) == 0);

	return ret;
}

/* Sysfs idxd files */
const char *dsa_configs[] = {
	"echo 1 > /sys/bus/dsa/devices/dsa0/wq0.1/group_id",
	"echo shared > /sys/bus/dsa/devices/dsa0/wq0.1/mode",
	"echo 10 > /sys/bus/dsa/devices/dsa0/wq0.1/priority",
	"echo 16 > /sys/bus/dsa/devices/dsa0/wq0.1/size",
	"echo 15 > /sys/bus/dsa/devices/dsa0/wq0.1/threshold",
	"echo user > /sys/bus/dsa/devices/dsa0/wq0.1/type",
	"echo MyApp1 > /sys/bus/dsa/devices/dsa0/wq0.1/name",
	"echo 1 > /sys/bus/dsa/devices/dsa0/engine0.1/group_id",
	"echo dsa0 > /sys/bus/dsa/drivers/idxd/bind",
	/* bind files and devices, generated a device file in /dev */
	"echo wq0.1 > /sys/bus/dsa/drivers/user/bind",
};

/* DSA device file */
const char *dsa_device_file = "/dev/dsa/wq0.1";
/* file for io*/
const char *dsa_pasid_enable = "/sys/bus/dsa/devices/dsa0/pasid_enabled";

/*
 * DSA depends on kernel cmdline "intel_iommu=on,sm_on"
 * return pasid_enabled (0: disable 1:enable)
 */
int check_dsa_kernel_setting(void)
{
	char command[256] = "";
	char buf[256] = "";
	char *ptr;
	int rv = -1;

	snprintf(command, sizeof(command) - 1, "cat %s", dsa_pasid_enable);

	FILE *cmd = popen(command, "r");

	if (cmd) {
		while (fgets(buf, sizeof(buf) - 1, cmd))
			;

		pclose(cmd);
		rv = strtol(buf, &ptr, 16);
	}

	return rv;
}

/*
 * Config DSA's sysfs files as shared DSA's WQ.
 * Generated a device file /dev/dsa/wq0.1
 * Return:  0 OK; 1 Failed; 3 Skip(SVM disabled).
 */
int dsa_init_sysfs(void)
{
	uint len = ARRAY_SIZE(dsa_configs);
	const char **p = dsa_configs;

	if (file_exists(dsa_device_file) == 1)
		return 0;

	/* check the idxd driver */
	if (file_exists(dsa_pasid_enable) != 1) {
		printf("Please make sure idxd driver was loaded\n");
		return 3;
	}

	/* Check SVM feature */
	if (check_dsa_kernel_setting() != 1) {
		printf("Please enable SVA.(Add intel_iommu=on,sm_on in kernel cmdline)\n");
		return 3;
	}

	/* Check the idxd device file on /dev/dsa/ */
	for (int i = 0; i < len; i++) {
		if (system(p[i]))
			return 1;
	}

	/* After config, /dev/dsa/wq0.1 should be generated */
	return (file_exists(dsa_device_file) != 1);
}

/*
 * Open DSA device file, trigger API: iommu_sva_alloc_pasid
 */
void *allocate_dsa_pasid(void)
{
	int fd;
	void *wq;

	fd = open(dsa_device_file, O_RDWR);
	if (fd < 0) {
		perror("open");
		return MAP_FAILED;
	}

	wq = mmap(NULL, 0x1000, PROT_WRITE, MAP_SHARED | MAP_POPULATE, fd, 0);
	if (wq == MAP_FAILED)
		perror("mmap");

	return wq;
}

int set_force_svm(void)
{
	int ret = 0;

	ret = syscall(SYS_arch_prctl, ARCH_FORCE_TAGGED_SVM);

	return ret;
}

int handle_pasid(struct testcases *test)
{
	uint tmp = test->cmd;
	uint runed = 0x0;
	int ret = 0;
	void *wq = NULL;

	ret = dsa_init_sysfs();
	if (ret != 0)
		return ret;

	for (int i = 0; i < 3; i++) {
		int err = 0;

	if (tmp & 0x1) {
		/* run set lam mode*/
		if ((runed & 0x1) == 0)	{
			err = set_lam(LAM_U57_BITS);
			runed = runed | 0x1;
		} else {
			err = 1;
		}
	} else if (tmp & 0x4) {
		/* run force svm */
		if ((runed & 0x4) == 0)	{
			err = set_force_svm();
			runed = runed | 0x4;
		} else {
			err = 1;
		}
	} else if (tmp & 0x2) {
		/* run allocate pasid */
		if ((runed & 0x2) == 0) {
			runed = runed | 0x2;
			wq = allocate_dsa_pasid();
			if (wq == MAP_FAILED)
				err = 1;
		} else {
			err = 1;
		}
	}

	ret = ret + err;
	if (ret > 0)
		break;

		tmp = tmp >> 4;
	}

	if (wq != MAP_FAILED && wq)
		if (munmap(wq, 0x1000))
			perror("munmap failed:");

	if (runed != 0x7)
		ret = 1;

	return (ret != 0);
}

/*
 * Pasid test depends on idxd and SVM, kernel should enable iommu and sm.
 * command line(intel_iommu=on,sm_on)
 */
static struct testcases pasid_cases[] = {
	{
		.expected = 1,
		.cmd = PAS_CMD(LAM_CMD_BIT, PAS_CMD_BIT, SVM_CMD_BIT),
		.test_func = handle_pasid,
		.msg = "PASID: [Negative] Execute LAM, PASID, SVM in sequence\n",
	},
	{
		.expected = 0,
		.cmd = PAS_CMD(LAM_CMD_BIT, SVM_CMD_BIT, PAS_CMD_BIT),
		.test_func = handle_pasid,
		.msg = "PASID: Execute LAM, SVM, PASID in sequence\n",
	},
	{
		.expected = 1,
		.cmd = PAS_CMD(PAS_CMD_BIT, LAM_CMD_BIT, SVM_CMD_BIT),
		.test_func = handle_pasid,
		.msg = "PASID: [Negative] Execute PASID, LAM, SVM in sequence\n",
	},
	{
		.expected = 0,
		.cmd = PAS_CMD(PAS_CMD_BIT, SVM_CMD_BIT, LAM_CMD_BIT),
		.test_func = handle_pasid,
		.msg = "PASID: Execute PASID, SVM, LAM in sequence\n",
	},
	{
		.expected = 0,
		.cmd = PAS_CMD(SVM_CMD_BIT, LAM_CMD_BIT, PAS_CMD_BIT),
		.test_func = handle_pasid,
		.msg = "PASID: Execute SVM, LAM, PASID in sequence\n",
	},
	{
		.expected = 0,
		.cmd = PAS_CMD(SVM_CMD_BIT, PAS_CMD_BIT, LAM_CMD_BIT),
		.test_func = handle_pasid,
		.msg = "PASID: Execute SVM, PASID, LAM in sequence\n",
	},
};

/* cpuid_cases
 * cpuid of LAM checking.
 */
static struct testcases cpuid_cases[] = {
	{
		.expected = 0,
		.test_func = handle_cpuid,
		.msg = "CPUID: cpuid are supported\n",
	},
};

/* config_cases
 * kernel config checking.
 */
static struct testcases config_cases[] = {
	{
		.expected = 0,
		.test_func = handle_config,
		.msg = "CONFIG: CONFIG_ADDRESS_MASKING\n",
	},
};

int main(int argc, char **argv)
{
	int c = 0;
	unsigned int tests = TEST_MASK;

	tests_cnt = 0;
	tests_pass = 0;

	if (!cpu_has_lam()) {
		printf("Unsupported LAM feature!\n");
		return -1;
	}

	while ((c = getopt(argc, argv, "ht:")) != -1) {
		switch (c) {
		case 't':
			tests = strtoul(optarg, NULL, 16);
			if (tests && !(tests & TEST_MASK)) {
				printf("Invalid argument!\n");
				return -1;
			}
			break;
		case 'h':
			cmd_help();
			return -1;
		default:
			printf("Invalid argument\n");
			return -1;
		}
	}

	/*
	 * When tests is 0, it is not a real test case;
	 * the option used by test case(execve) to check the lam mode in
	 * process generated by execve, the process read back lam mode and
	 * check with lam mode in parent process.
	 */
	if (!tests)
		return (get_lam());

	/* Run test cases */
	if (tests & FUNC_MALLOC)
		run_test(malloc_cases, ARRAY_SIZE(malloc_cases));

	if (tests & FUNC_BITS)
		run_test(bits_cases, ARRAY_SIZE(bits_cases));

	if (tests & FUNC_MMAP)
		run_test(mmap_cases, ARRAY_SIZE(mmap_cases));

	if (tests & FUNC_SYSCALL)
		run_test(syscall_cases, ARRAY_SIZE(syscall_cases));

	if (tests & FUNC_URING)
		run_test(uring_cases, ARRAY_SIZE(uring_cases));

	if (tests & FUNC_INHERITE)
		run_test(inheritance_cases, ARRAY_SIZE(inheritance_cases));

	if (tests & FUNC_PASID)
		run_test(pasid_cases, ARRAY_SIZE(pasid_cases));

	if (tests & FUNC_CPUID)
		run_test(cpuid_cases, ARRAY_SIZE(cpuid_cases));

	if (tests & FUNC_CONFIG)
		run_test(config_cases, ARRAY_SIZE(config_cases));

	printf("Total tests: %d; Pass:%d\n", tests_cnt, tests_pass);

	return (tests_cnt - tests_pass);
}
