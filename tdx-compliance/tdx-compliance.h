/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef TDX_COMPLIANCE_H
#define TDX_COMPLIANCE_H
struct cpuid_reg {
	u32 val;
	u32 expect;
	u32 mask;
};

struct cpuid_regs_ext {
	struct cpuid_reg eax;
	struct cpuid_reg ebx;
	struct cpuid_reg ecx;
	struct cpuid_reg edx;
};

struct test_cpuid {
	const char *name;
	u32 leaf;
	u32 subleaf;
	int ret;
	struct cpuid_regs_ext regs;
};

struct cr_reg {
	u64 val;
	u64 mask;
	u64 expect;
};

struct excp {
	int expect;
	int val;
};

struct test_cr {
	char *name;		/* The name of the case */
	int ret;		/* The result of the test, 1 for pass */
	struct cr_reg reg;
	struct excp excp;	/* The test's predicted and actual trap number */

	int (*pre_condition)(struct test_cr *t);
	u64 (*run_cr_get)(void);
	int (*run_cr_set)(u64 cr);
};

struct msr_info_ext {
	u32 msr_num;
	struct msr val;
};

struct test_msr {
	char *name;
	struct msr_info_ext msr;
	int size;
	int ret;
	struct excp excp;

	int (*run_msr_rw)(struct test_msr *p_test_msr);
	void (*pre_condition)(struct test_msr *p_test_msr);
	struct cpuid_regs_ext regs;
};

static int run_cpuid(struct test_cpuid *t);
static u64 get_cr0(void);
static u64 get_cr4(void);
int __no_profile _native_write_cr0(u64 val);
int __no_profile _native_write_cr4(u64 val);
static int write_msr_native(struct test_msr *c);
static int read_msr_native(struct test_msr *c);

u64 cur_cr4, cur_cr0;
#endif
