// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2024 Intel Corporation.

/*
 * lass.c:
 *
 * Author: Pengfei, Xu <pengfei.xu@intel.com>,
 *         Weihong,Zhang <weihong.zhang@intel.com>,
 *         Xuelian, Guo <xuelian.guo@intel.com>
 *********************************************************
 * Usage: m | d | g | t | r | i | v | e | a | h
 *       m       Test get vsyscall address maps.
 *       d       Test execute vsyscall addr 0xffffffffff600000.
 *       g       Test call vsyscall
 *       t       Test call vsyscall api gettimeofday
 *       r       Test read vsyscall 0xffffffffff600000.
 *       i       Test read random kernel space.
 *       v       Test process_vm_readv read address 0xffffffffff600000.[negative]
 *       e       Test vsyscall emulation.
 *       a       Test all.
 *       h       Help
 ********************************************************
 *
 * /

/*****************************************************************************/

#define _GNU_SOURCE

#include <stdio.h>
#include <sys/time.h>
#include <time.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <dlfcn.h>
#include <string.h>
#include <inttypes.h>
#include <signal.h>
#include <sys/ucontext.h>
#include <errno.h>
#include <err.h>
#include <sched.h>
#include <stdbool.h>
#include <setjmp.h>
#include <sys/uio.h>

#include <cpuid.h>

#define ARRAY_SIZE(x) (sizeof(x) / sizeof((x)[0]))
#define BIT(nr) (1UL << (nr))
#define MAPS_LINE_LEN 128

#define KERNEL_START_ADDR 0xffff800000000000
#define VSYS_START_ADDR 0xffffffffff600000
#define VSYS_END_ADDR 0xffffffffff601000
#define READ_LEN 1024

#ifdef __x86_64__
#define VSYS(x) (x)
#else
#define VSYS(x) (0 * (x))
#endif

static sig_atomic_t num_vsyscall_traps;
static int instruction_num, pass_num, fail_num;
static jmp_buf jmpbuf;

static bool lass_enable;
static bool no_vsys_map = true;
static bool vsyscall_none;
static bool vsyscall_xonly;
static bool vsyscall_emulate;
static bool vsyscall_default;
/*
 * /proc/self/maps, r means readable, x means executable
 * vsyscall map: ffffffffff600000-ffffffffff601000
 */
bool vsyscall_map_r = false, vsyscall_map_x = false;
static unsigned long segv_err;

typedef long (*gtod_t)(struct timeval *tv, struct timezone *tz);
const gtod_t vgtod = (gtod_t)VSYS(VSYS_START_ADDR);

typedef long (*time_func_t)(time_t *t);
const time_func_t vtime = (time_func_t)VSYS(0xffffffffff600400);

struct testcases {
	char param; /* 2: SIGSEGV Error; 1: other errors */
	const char *msg;
	int (*test_func)();
};

static int usage(void);
static int run_all(void);

/* syscalls */
static inline long sys_gtod(struct timeval *tv, struct timezone *tz)
{
	return syscall(SYS_gettimeofday, tv, tz);
}

static int fail_case(const char *format)
{
	printf("[FAIL]\t%s\n", format);
	fail_num++;
	return 1;
}

static int pass_case(const char *format)
{
	printf("[PASS]\t%s\n", format);
	pass_num++;
	return 0;
}

/*
 * LASS support by the processor is enumerated by the CPUID feature flag
 * LASS CPUID.EAX=7.ECX=1.EAX[6]
 */
int cpu_has_lass(void)
{
	unsigned int cpuinfo[4];

	__cpuid_count(0x7, 1, cpuinfo[0], cpuinfo[1], cpuinfo[2], cpuinfo[3]);

	return (cpuinfo[0] & (1 << 6));
}

/* Get information from /proc/cmdline */
static bool check_lass_enable(void)
{
	char buf[256] = {0};
	char command[256] = "cat /proc/cmdline";
	bool rv = false;

	FILE *cmd = popen(command, "r");

	if (cmd) {
		while (fgets(buf, sizeof(buf) - 1, cmd))
			;
		// printf("Get buff:%s\n", buf);
		pclose(cmd);
		rv = (strstr(buf, " lass") != 0);
		// printf("%s Get lass! rv:%x\n", __func__, rv);
	}

	return rv;
}

/* Get information from /proc/cmdline */
static bool check_vsyscall_status(void)
{
	char buf[256] = {0};
	char command[256] = "cat /proc/cmdline";
	bool rv = false;

	FILE *cmd = popen(command, "r");

	if (cmd) {
		while (fgets(buf, sizeof(buf) - 1, cmd))
			;
		pclose(cmd);

		rv = (strstr(buf, " vsyscall") != 0);
		if (!rv)
			vsyscall_default = true;
		rv = (strstr(buf, " vsyscall=emulate") != 0);
		if (rv)
			vsyscall_emulate = true;
		rv = (strstr(buf, " vsyscall=xonly") != 0);
		if (rv)
			vsyscall_xonly = true;
		rv = (strstr(buf, " vsyscall=none") != 0);
		if (rv)
			vsyscall_none = true;
	}
	return rv;
}

static int get_vsys_map(void)
{
	FILE *maps;
	char line[MAPS_LINE_LEN];

	maps = fopen("/proc/self/maps", "r");
	if (!maps) {
		printf("[WARN]\tCould not open /proc/self/maps\n");
		vsyscall_map_r = false;
		return 0;
	}

	while (fgets(line, MAPS_LINE_LEN, maps)) {
		char r, x;
		void *start, *end;
		char name[MAPS_LINE_LEN];

		/* sscanf() is safe as strlen(name) >= strlen(line) */
		if (sscanf(line, "%p-%p %c-%cp %*x %*x:%*x %*u %s",
			   &start, &end, &r, &x, name) != 5)
			continue;

		if (strcmp(name, "[vsyscall]"))
			continue;

		printf("\tvsyscall map: %s", line);

		if (start != (void *)VSYS_START_ADDR ||
		    end != (void *)VSYS_END_ADDR) {
			fail_case("address range is nonsense\n");
		}

		printf("\tvsyscall permissions are %c-%c\n", r, x);
		vsyscall_map_r = (r == 'r');
		vsyscall_map_x = (x == 'x');
		printf("vsyscall_map_r:%d, vsyscall_map_x:%d\n",
		       vsyscall_map_r, vsyscall_map_x);

		no_vsys_map = false;
		break;
	}
	fclose(maps);

	if (no_vsys_map) {
		printf("[WARN]\tno vsyscall map in /proc/self/maps\n");
		vsyscall_map_r = false;
		vsyscall_map_x = false;
	}
	return 0;
}

static int test_read_vsys_map(void)
{
	get_vsys_map();
	if (no_vsys_map) {
		if (lass_enable && vsyscall_none)
			pass_case("vsyscall=none, vsyscall address map OK");
		else
			fail_case("vsyscall=emulate/xonly/default, vsyscall address map OK");
	} else {
		if (lass_enable && vsyscall_none)
			fail_case("vsyscall=none, vsyscall address map NG");
		else
			pass_case("lass vsyscall=emulate/xonly/default, vsyscall addr map OK");
	}

	return 0;
}

void dump_buffer(unsigned char *buf, int size)
{
	int i, j;

	printf("-----------------------------------------------------\n");
	printf("buf addr:%p size = %d (%03xh)\n", buf, size, size);

	for (i = 0; i < size; i += 16) {
		printf("%04x: ", i);

		for (j = i; ((j < i + 16) && (j < size)); j++)
			printf("%02x ", buf[j]);

		printf("\n");
	}
}

static int test_read_vsys_address(void)
{
	bool can_read;
	int a = 0;

	if (sigsetjmp(jmpbuf, 1) == 0) {
		printf("Access 0x%lx\n", VSYS_START_ADDR);
		a = *(int *)VSYS_START_ADDR;
		printf("0x%lx content:0x%x\n", VSYS_START_ADDR, a);
		can_read = true;
	} else {
		can_read = false;
	}
	printf("can_read:%d, vsyscall_map_r:%d\n", can_read, vsyscall_map_r);

	// when LASS enable, the vsyscall page is unreadable except vsyscall=emulate
	if (lass_enable && vsyscall_emulate)
		vsyscall_map_r = true;
	else
		vsyscall_map_r = false;

	// vsyscall_map_r = true;
	// can_read = true;
	printf("can_read:%d, vsyscall_map_r:%d\n", can_read, vsyscall_map_r);

	if (vsyscall_map_r == can_read)
		pass_case("Could read vsyscall addr is expected");
	else
		fail_case("Could not read vsyscall addr is not expected");

	return 0;
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
		err(1, "sigaction");
}

static void sigsegv(int sig, siginfo_t *info, void *ctx_void)
{
	ucontext_t *ctx = (ucontext_t *)ctx_void;

	segv_err = ctx->uc_mcontext.gregs[REG_ERR];
	unsigned long ip = ctx->uc_mcontext.gregs[REG_RIP];
	unsigned long bp = ctx->uc_mcontext.gregs[REG_RBP];

	printf("Received sig:%d,si_code:%d,ip:0x%lx,bp:0x%lx\n",
	       sig, info->si_code, ip, bp);
	siglongjmp(jmpbuf, 1);
}

static int test_process_vm_readv_vsys_address(void)
{
	unsigned char buf[READ_LEN] = "";
	struct iovec local, remote;
	int ret;

	printf("[RUN]\tprocess_vm_readv() from vsyscall page\n");

	local.iov_base = buf;
	local.iov_len = READ_LEN;
	remote.iov_base = (void *)VSYS_START_ADDR;
	remote.iov_len = READ_LEN;

	ret = process_vm_readv(getpid(), &local, 1, &remote, 1, 0);
	printf("After process_vm_readv copy to buf\n");
	//when LASS enable, the vsyscall page is unreadable
	if (lass_enable)
		vsyscall_map_r = false;

	if (ret != READ_LEN) {
		perror("Get error:");
		if (vsyscall_map_r) {
			if (lass_enable && vsyscall_emulate)
				fail_case("vsyscall=emulate, Read vsyscall addr OK, read date NG");
			else
				fail_case("vsyscall!=emulate, Readable vsyscall addr NG");
		} else {
			if (lass_enable && vsyscall_emulate)
				fail_case("vsyscall=emulate, process_vm_readv NG");
			else
				pass_case("vsyscall!=emulate, process_vm_readv OK");
		}
	} else {
		dump_buffer(buf, 0x100);
		if (vsyscall_map_r) {
			if (memcmp(buf, (const void *)VSYS_START_ADDR, READ_LEN)) {
				printf("[WARN]\t Read incorrect data\n");
				fail_case("read vsyscall data is not acceptable in lass");
			} else {
				if (lass_enable && vsyscall_emulate)
					pass_case("vsyscall=emulate, Read vsyscall data OK");
				else
					fail_case("vsyscall!=emulate, Read vsyscall data NG");
			}
		} else {
			if (lass_enable && vsyscall_emulate)
				pass_case("vsyscall=emulate,read vsyscall addr OK,read data NG");
			else
				fail_case("Read vsyscall data is unexpected.");
		}
	}

	return 0;
}

// call vsyscall api
static int test_vsys_api_gtod(void)
{
	int ret_sys = -1;
	struct timeval tv;

	ret_sys = gettimeofday(&tv, NULL);
	if (ret_sys)
		fail_case("gettimeofday func failed, check lass.");
	else
		pass_case("gettimeofday func pass.");

	return ret_sys;
}

// test vsyscall through call entry
static int test_vsys_address_executable(void)
{
	bool executed;
	struct timeval tv;
	struct timezone tz;

	if (vsyscall_map_x)
		printf("vsyscall address is executable!\n");
	else
		printf("vsyscall address is not executable!\n");

	printf("[RUN]\tMake sure that vsyscalls is executable\n");
	if (sigsetjmp(jmpbuf, 1) == 0) {
		vgtod(&tv, &tz);
		executed = true;
	} else {
		executed = false;
	}

	if (executed) {
		printf("Get time: tv_sys.sec:%ld usec:%ld\n", tv.tv_sec, tv.tv_usec);

		if (lass_enable && vsyscall_none) {
			fail_case("vsyscall=none,exe vsyscall addr unexpected!");
		} else {
			if (vsyscall_map_x)
				pass_case("Exe vsyscall address is expected");
			else
				fail_case("Should trigger wrong page fault!");
		}
	} else { /* INSTR */
		printf("Failed to get time\n");
		if (lass_enable && vsyscall_none) {
			pass_case("vsyscall=none,not support exe vsyscall addr");
		} else {
			if (vsyscall_map_x)
				fail_case("Should be execute vsyscall address");
			else
				pass_case("Fail to exe vsyscall is expected!");
		}
	}

	return 0;
}

static unsigned long get_eflags(void)
{
	unsigned long eflags;

	asm volatile("pushfq\n\tpopq %0"
		     : "=rm"(eflags));
	return eflags;
}

static void set_eflags(unsigned long eflags)
{
	asm volatile("pushq %0\n\tpopfq"
				:
				: "rm"(eflags)
				: "flags");
}

static void sigtrap(int sig, siginfo_t *info, void *ctx_void)
{
	ucontext_t *ctx = (ucontext_t *)ctx_void;
	unsigned long ip = ctx->uc_mcontext.gregs[REG_RIP];
	unsigned long bp = ctx->uc_mcontext.gregs[REG_RBP];

	instruction_num++;
	/* Check sig number and rip rbp status. */
	if (((ip ^ 0xffffffffff600000UL) & ~0xfffUL) == 0) {
		printf("Got sig:%d,si_code:%d,ip:%lx,rbp:%lx,ins_num:%d\n",
		       sig, info->si_code, ip, bp, instruction_num);
		num_vsyscall_traps++;
	} else if (instruction_num < 16) {
		printf("instruction_num:%02d, ip:%lx, rbp:%lx\n",
		       instruction_num, ip, bp);
	}
}

static int test_vsys_emulation(void)
{
	time_t tmp = 0;
	bool is_native;

	num_vsyscall_traps = 0;
	if (!vsyscall_map_x) {
		printf("Could not execute vsyscall\n");
		pass_case("Sysfile: vsyscall could not be executed\n");
		return 1;
	}

	printf("[RUN]\tchecking vsyscall is emulated\n");
	sethandler(SIGTRAP, sigtrap, 0);
	printf("&tmp:%p, tmp:%lx\n", &tmp, tmp);
	//set_eflags(get_eflags() | X86_EFLAGS_TF);
	set_eflags(get_eflags() | BIT(8));

	/*
	 * Single step signal checking, don't add any steps between
	 * set_eflags() and vtime() to avoid confuse.
	 */
	vtime(&tmp);
	printf("&tmp:%p, tmp:%lx, ins_num:%d\n",
	       &tmp, tmp, instruction_num);
	//set_eflags(get_eflags() & ~X86_EFLAGS_TF);
	set_eflags(get_eflags() & ~BIT(8));

	/*
	 * If vsyscalls are emulated, we expect a single trap in the
	 * vsyscall page -- the call instruction will trap with RIP
	 * pointing to the entry point before emulation takes over.
	 * In native mode, we expect two traps, since whatever code
	 * the vsyscall page contains will be more than just a ret
	 * instruction.
	 */
	is_native = (num_vsyscall_traps > 1);
	printf("is_native:%d, num_vsyscall_traps:%d\n",
	       is_native, num_vsyscall_traps);
	printf("[%s]\tvsyscalls are %s (%d instructions in vsyscall page)\n",
	       (is_native ? "FAIL" : "OK"),
	       (is_native ? "native" : "emulated"),
	       (int)num_vsyscall_traps);
	if (is_native)
		fail_case("It's native mode, traps num more than 1");
	else
		pass_case("Not native mode, traps num is 1");

	return is_native;
}

int test_vsys_syscall_gtod(void)
{
	long ret_vsys = -1;
	struct timeval tv_sys;
	struct timezone tz_sys;

	ret_vsys = sys_gtod(&tv_sys, &tz_sys);
	if (ret_vsys) {
		fail_case("Failed to test syscall gettimeofday!");
	} else {
		printf("Sysvall: gettimeofday\n");
		printf("Get time. tv_sys.sec:%ld usec:%ld\n",
		       tv_sys.tv_sec, tv_sys.tv_usec);
		pass_case("test syscall:gettimeofday pass");
	}

	return ret_vsys;
}

int test_read_kernel_linear(void)
{
	unsigned long a, b;
	unsigned long kernel_random_addr;
	int addr_content;
	bool read_done = 0;

	/* this is for some special time test
	 * srand((unsigned) (time(NULL)));
	 */
	a = rand();
	b = rand();
	kernel_random_addr = ((a << 32) | 0xffff800000000000ul) | b;

	if (kernel_random_addr < KERNEL_START_ADDR) {
		printf("addr:0x%lx is smaller than 0x%lx\n",
		       kernel_random_addr, KERNEL_START_ADDR);
		fail_case("Set addr error!");
		return 1;
	}
	printf("Kernel linear addr:0x%lx\n", kernel_random_addr);
	if (sigsetjmp(jmpbuf, 1) == 0) {
		addr_content = *(const int *)kernel_random_addr;
		read_done = true;
	} else {
		read_done = false;
	}

	if (read_done) {
		printf("Get content:0x%x (0x%lx)\n", addr_content, kernel_random_addr);

		fail_case("Kernel address could not read from user space!");
	} else { /* INSTR */
		printf("Failed to read kernel space.\n");

		pass_case("LASS not support access to read kernel address!");
	}

	return 0;
}

static struct testcases lass_cases[] = {
	{
		.param = 'm',
		.test_func = test_read_vsys_map,
		.msg = "Test get vsyscall address maps.",
		},
		{
		.param = 'd',
		.test_func = test_vsys_address_executable,
		.msg = "Test execute vsyscall addr 0xffffffffff600000.",
		},
		{
		.param = 'g',
		.test_func = test_vsys_syscall_gtod,
		.msg = "Test call vsyscall",
		},
	{
		.param = 't',
		.test_func = test_vsys_api_gtod,
		.msg = "Test call vsyscall api gettimeofday",
	},
	{
		.param = 'r',
		.test_func = test_read_vsys_address,
		.msg = "Test read vsyscall 0xffffffffff600000.",
	},
	{
		.param = 'i',
		.test_func = test_read_kernel_linear,
		.msg = "Test read random kernel space.",
		},
		{
		.param = 'v',
		.test_func = test_process_vm_readv_vsys_address,
		.msg = "Test process_vm_readv read address 0xffffffffff600000.[negative]",
		},
		{
		.param = 'e',
		.test_func = test_vsys_emulation,
		.msg = "Test vsyscall emulation.",
	},
	{
		.param = 'a',
		.test_func = run_all,
		.msg = "Test all.",
	},
	{
		.param = 'h',
		.test_func = usage,
		.msg = "Help",
	}};

int usage(void)
{
	int cnt = ARRAY_SIZE(lass_cases);

	printf("********************************************************\n");
	printf("Usage: [|");
	for (int i = 0; i < cnt; i++)
		printf(" %c |", lass_cases[i].param);
	printf("]\n");

	for (int i = 0; i < cnt; i++)
		printf("\t%c\t%s\n", lass_cases[i].param, lass_cases[i].msg);
	printf("********************************************************\n");

	exit(2);
}

int run_test_case(char opt)
{
	int cnt = ARRAY_SIZE(lass_cases);
	int ret = 0;

	for (int i = 0; i < cnt; i++) {
		if (lass_cases[i].param != opt)
			continue;

		printf("########### Start %c: %s ###########\n",
		       lass_cases[i].param, lass_cases[i].msg);
		ret = lass_cases[i].test_func();
		printf("########### Finished %c: %s ###########\n\n",
		       lass_cases[i].param, lass_cases[i].msg);
		break;
	}

	return ret;
}

int run_all(void)
{
	int cnt = ARRAY_SIZE(lass_cases);
	int ret = 0;

	for (int i = 0; i < cnt; i++) {
		if (lass_cases[i].param == 'h' || lass_cases[i].param == 'a')
			continue;

		printf("########### Start %c: %s ###########\n",
		       lass_cases[i].param, lass_cases[i].msg);
		ret = lass_cases[i].test_func();
		printf("########### Finished %c: %s ###########\n\n",
		       lass_cases[i].param, lass_cases[i].msg);
	}

	return ret;
}

int check_param(char opt)
{
	int cnt = ARRAY_SIZE(lass_cases);
	int ret = 0;

	for (int i = 0; i < cnt; i++) {
		if (lass_cases[i].param != opt) {
			ret = 1;
			break;
		}
	}

	return ret;
}

int main(int argc, char *argv[])
{
	char param;

	if (!cpu_has_lass()) {
		printf("Unsupported LASS feature!\n");
		return 1;
	}

	if (!check_lass_enable()) {
		lass_enable = false;
		printf(" under default mode without lass defined in cmdline.\n");
	}
	lass_enable = true;

	check_vsyscall_status();

	if (argc == 2) {
		if (sscanf(argv[1], "%c", &param) != 1) {
			printf("Invalid param:%c\n", param);
			usage();
		}
		printf("param:%c\n", param);
	} else {
		usage();
	}

	if (!check_param(param))
		usage();

	sethandler(SIGSEGV, sigsegv, 0);
	get_vsys_map();

	run_test_case(param);

	printf("[Results] pass_num:%d, fail_num:%d\n",
	       pass_num, fail_num);

	return 0;
}
