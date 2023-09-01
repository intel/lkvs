/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef TDX_COMPLIANCE_H
#define TDX_COMPLIANCE_H

/*
 * The following macro definitions are backported from the kernel upstream.
 * This is because TDX compliance requires compatibility with older kernels,
 * such as v5.19. All of these definitions can be removed in the future when
 * TDX no longer considers kernel v5.19 or earlier versions.
 */
#define X86_CR4_CET_BIT			23 /* enable Control-flow Enforcement Technology */
#define X86_CR4_CET			_BITUL(X86_CR4_CET_BIT)
#define MSR_IA32_VMX_PROCBASED_CTLS3	0x00000492
#define MSR_IA32_U_CET			0x000006a0 /* user mode cet */
#define MSR_IA32_S_CET			0x000006a2 /* kernel mode cet */
#define MSR_IA32_PL0_SSP		0x000006a4 /* ring-0 shadow stack pointer */
#define MSR_IA32_PL1_SSP		0x000006a5 /* ring-1 shadow stack pointer */
#define MSR_IA32_PL2_SSP		0x000006a6 /* ring-2 shadow stack pointer */
#define MSR_IA32_PL3_SSP		0x000006a7 /* ring-3 shadow stack pointer */
#define MSR_IA32_INT_SSP_TAB		0x000006a8 /* exception shadow stack table */
#define MSR_IA32_INT_SSP_TAB		0x000006a8
/****** END of Backport ******/

#define VER1_0 1
#define VER1_5 2

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
	int version;
	struct cpuid_regs_ext regs;
	struct list_head list;
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
	int version;
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
	int version;

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
extern struct list_head cpuid_list;
#endif
