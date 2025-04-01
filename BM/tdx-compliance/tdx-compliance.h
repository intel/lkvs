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
#define VER2_0 4

#define TDX_HYPERCALL_STANDARD      0

/* TDX TDCALL.VMCALL leaf id  */
#define TDG_VP_VMCALL           0

/*
 * Bitmasks of exposed registers (with VMM).
 */
#define TDX_RDX     BIT(2)
#define TDX_RBX     BIT(3)
#define TDX_RSI     BIT(6)
#define TDX_RDI     BIT(7)
#define TDX_R8      BIT(8)
#define TDX_R9      BIT(9)
#define TDX_R10     BIT(10)
#define TDX_R11     BIT(11)
#define TDX_R12     BIT(12)
#define TDX_R13     BIT(13)
#define TDX_R14     BIT(14)
#define TDX_R15     BIT(15)

/*
 * These registers are clobbered to hold arguments for each
 * TDVMCALL. They are safe to expose to the VMM.
 * Each bit in this mask represents a register ID. Bit field
 * details can be found in TDX GHCI specification, section
 * titled "TDCALL [TDG.VP.VMCALL] leaf".
 */
#define TDVMCALL_EXPOSE_REGS_MASK   \
	(TDX_RDX | TDX_RBX | TDX_RSI | TDX_RDI | TDX_R8  | TDX_R9  | \
	 TDX_R10 | TDX_R11 | TDX_R12 | TDX_R13 | TDX_R14 | TDX_R15)

/*
 * Used in __tdcall*() to gather the input/output registers' values of the
 * TDCALL instruction when requesting services from the TDX module. This is a
 * software only structure and not part of the TDX module/VMM ABI
 */
struct tdx_module_args {
	/* callee-clobbered */
	u64 rcx;
	u64 rdx;
	u64 r8;
	u64 r9;
	/* extra callee-clobbered */
	u64 r10;
	u64 r11;
	/* callee-saved + rdi/rsi */
	u64 r12;
	u64 r13;
	u64 r14;
	u64 r15;
	u64 rbx;
	u64 rdi;
	u64 rsi;
};

/* Used to communicate with the TDX module */
extern u64 __tdcall(u64 fn, struct tdx_module_args *args);
extern u64 __tdcall_ret(u64 fn, struct tdx_module_args *args);
extern u64 __tdcall_saved_ret(u64 fn, struct tdx_module_args *args);
u64 tdcall(u64 fn, struct tdx_module_args *args);

/* Used to request services from the VMM */
u64 __tdx_hypercall(struct tdx_module_args *args);

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
	u64 tdcs_td_ctl;
	u64 tdcs_feature_pv_ctl;
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
void initial_cpuid(void);
void parse_version(void);
void parse_input(char *s);
int check_results_cr(struct test_cr *t);

u64 cur_cr4, cur_cr0;
extern struct list_head cpuid_list;
#endif
