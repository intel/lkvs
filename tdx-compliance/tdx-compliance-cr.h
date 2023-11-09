/* SPDX-License-Identifier: GPL-2.0-only */
#include "tdx-compliance.h"

/* Define Control Register compliance tests verified in TD guest. */
static int set_cr0_bit(u64 cr0)
{
	cr0 |= cur_cr0;
	return _native_write_cr0(cr0);
}

static int set_cr0_clear_bit(u64 cr0)
{
	cr0 = ~cr0;
	cr0 &= cur_cr0;

	return _native_write_cr0(cr0);
}

static int set_cr4_bit(u64 cr4)
{
	cr4 |= cur_cr4;
	return _native_write_cr4(cr4);
}

static int set_cr4_exchange_bit(u64 cr4)
{
	cr4 = cur_cr4 ^ cr4;
	return _native_write_cr4(cr4);
}

static int pre_cond_cr0_combine(struct test_cr *c)
{
	if ((cur_cr0 & X86_CR0_PE) != 0 || (cur_cr0 & X86_CR0_PG) != 0)
		c->excp.expect = X86_TRAP_VE;

	return 0;
}

static int pre_cond_cr4_perfmon(struct test_cr *c)
{
	struct test_cpuid cpuid_perf = DEF_CPUID_TEST(0xa, 0);

	run_cpuid(&cpuid_perf);

	/* CPUID(0xa,0x0).* */
	if (cpuid_perf.regs.eax.val == 0 && cpuid_perf.regs.ebx.val == 0 &&
	    cpuid_perf.regs.ecx.val == 0 && cpuid_perf.regs.edx.val == 0) {
		c->excp.expect = X86_TRAP_GP;
		return 0;
	}

	return -1;
}

static int pre_cond_cr4_kl(struct test_cr *c)
{
	struct test_cpuid cpuid_kl = DEF_CPUID_TEST(0x7, 0);

	run_cpuid(&cpuid_kl);

	/* CPUID(0x7,0x0).ecx[23] */
	if ((cpuid_kl.regs.ecx.val & _BITUL(23)) == 0) {
		c->excp.expect = X86_TRAP_GP;
		return 0;
	}

	return -1;
}

static int pre_cond_cr4_pks(struct test_cr *c)
{
	struct test_cpuid cpuid_pks = DEF_CPUID_TEST(0x7, 0);

	run_cpuid(&cpuid_pks);

	/* CPUID(0x7,0x0).ecx[31] */
	if ((cpuid_pks.regs.ecx.val & _BITUL(31)) == 0) {
		c->excp.expect = X86_TRAP_GP;
		return 0;
	}
	return -1;
}

static int pre_cond_cr4_pke(struct test_cr *c)
{
	struct test_cpuid cpuid_pke = DEF_CPUID_TEST(0xd, 0);

	run_cpuid(&cpuid_pke);

	/* CPUID(0xd,0x0).eax[9] */
	if ((cpuid_pke.regs.eax.val & _BITUL(9)) == 0)
		c->excp.expect = X86_TRAP_GP;
	return 0;
}

static int pre_cond_cr4_cet(struct test_cr *c)
{
	struct test_cpuid  cpuid_cet = DEF_CPUID_TEST(0x7, 0);

	run_cpuid(&cpuid_cet);

	/* CPUID(0x7,0x0).edx[20] */
	if ((cpuid_cet.regs.edx.val & _BITUL(20)) == 0)
		c->excp.expect = X86_TRAP_GP;
	return 0;
}

static int pre_cond_cr4_uint(struct test_cr *c)
{
	struct test_cpuid  cpuid_uint = DEF_CPUID_TEST(0xd, 1);

	run_cpuid(&cpuid_uint);

	/* CPUID(0xd,0x1).ecx[14] */
	if ((cpuid_uint.regs.ecx.val & _BITUL(14)) == 0)
		c->excp.expect = X86_TRAP_GP;
	return 0;
}

#define NO_EXCP 0
#define NO_PRE_COND NULL

#define DEF_GET_CR0(_mask, _expect, _excp, _precond, _vsn)	\
{							\
	.name = "CR0_GET_" #_mask,			\
	.version = _vsn,				\
	.reg.expect = _expect,				\
	.reg.mask = _mask,				\
	.run_cr_get = get_cr0,				\
	.pre_condition = _precond,			\
}

#define DEF_SET_CR0(_mask, _excp, _precond, _vsn)		\
{							\
	.name = "CR0_SET_" #_mask,			\
	.version = _vsn,				\
	.reg.mask = _mask,				\
	.excp.expect = _excp,				\
	.run_cr_set = set_cr0_bit,			\
	.pre_condition = _precond,			\
}

#define DEF_CLEAR_CR0(_mask, _excp, _precond, _vsn)		\
{							\
	.name = "CR0_SET_" #_mask,			\
	.version = _vsn,				\
	.reg.mask = _mask,				\
	.excp.expect = _excp,				\
	.run_cr_set = set_cr0_clear_bit,		\
	.pre_condition = _precond,			\
}

#define DEF_GET_CR4(_mask, _expect, _excp, _precond, _vsn)	\
{							\
	.name = "CR4_GET_" #_mask,			\
	.version = _vsn,				\
	.reg.expect = _expect,				\
	.reg.mask = _mask,				\
	.run_cr_get = get_cr4,				\
	.pre_condition = _precond,			\
}

#define DEF_SET_CR4(_mask, _excp, _precond, _vsn)		\
{							\
	.name = "CR4_SET_" #_mask,			\
	.version = _vsn,				\
	.reg.mask = _mask,				\
	.excp.expect = _excp,				\
	.run_cr_set = set_cr4_bit,			\
	.pre_condition = _precond,			\
}

#define DEF_XCH_CR4(_mask, _excp, _precond, _vsn)		\
{							\
	.name = "CR4_XCH_" #_mask,			\
	.version = _vsn,				\
	.reg.mask = _mask,				\
	.excp.expect = _excp,				\
	.run_cr_set = set_cr4_exchange_bit,		\
	.pre_condition = _precond,			\
}

#define BIT_SET	1
#define BIT_CLEAR 0

#define X86_CR4_KL_BIT 19
#define X86_CR4_KL _BITUL(X86_CR4_KL_BIT)
#define X86_CR4_PKS_BIT 24
#define X86_CR4_PKS _BITUL(X86_CR4_PKS_BIT)
#define X86_CR4_UINT_BIT 25
#define X86_CR4_UINT _BITUL(X86_CR4_UINT_BIT)

struct test_cr cr_list[] = {
	/*
	 * Validate CR0 read:
	 *   bits PE(0) and NE(5) are always set to 1
	 *   bits NW(29) and CD(30) are always cleared to 0
	 */
	DEF_GET_CR0(X86_CR0_CD, BIT_CLEAR, NO_EXCP, NO_PRE_COND, VER1_0 | VER1_5),
	DEF_GET_CR0(X86_CR0_NW, BIT_CLEAR, NO_EXCP, NO_PRE_COND, VER1_0 | VER1_5),
	DEF_GET_CR0(X86_CR0_PE, BIT_SET, NO_EXCP, NO_PRE_COND, VER1_0 | VER1_5),
	DEF_GET_CR0(X86_CR0_NE, BIT_SET, NO_EXCP, NO_PRE_COND, VER1_0 | VER1_5),

	DEF_GET_CR4(X86_CR4_SMXE, BIT_CLEAR, NO_EXCP, NO_PRE_COND, VER1_0 | VER1_5),
	DEF_GET_CR4(X86_CR4_VMXE, BIT_CLEAR, NO_EXCP, NO_PRE_COND, VER1_0 | VER1_5),
	DEF_GET_CR4(X86_CR4_MCE, BIT_SET, NO_EXCP, NO_PRE_COND, VER1_0 | VER1_5),

	DEF_CLEAR_CR0(X86_CR0_PE, X86_TRAP_GP, NO_PRE_COND, VER1_0 | VER1_5),
	DEF_CLEAR_CR0(X86_CR0_NE, X86_TRAP_GP, NO_PRE_COND, VER1_0 | VER1_5),
	DEF_CLEAR_CR0(X86_CR0_PE | X86_CR0_PG, NO_EXCP, pre_cond_cr0_combine, VER1_0 | VER1_5),

	DEF_SET_CR0(X86_CR0_NW, X86_TRAP_VE, NO_PRE_COND, VER1_0 | VER1_5),
	DEF_SET_CR0(X86_CR0_CD, X86_TRAP_VE, NO_PRE_COND, VER1_0 | VER1_5),

	/*
	 * TD attempts to modify them results in a #VE,
	 * bits VMXE(13) and SMXE(14) are fixed to 0.
	 */
	DEF_XCH_CR4(X86_CR4_VMXE, X86_TRAP_VE, NO_PRE_COND, VER1_0 | VER1_5),
	DEF_XCH_CR4(X86_CR4_SMXE, X86_TRAP_VE, NO_PRE_COND, VER1_0 | VER1_5),

	/*
	 * TD attempts to modify bit MCE(6) results in a #VE,
	 * bits MCE(6) are fixed to 1.
	 */
	DEF_XCH_CR4(X86_CR4_MCE, X86_TRAP_VE, NO_PRE_COND, VER1_0 | VER1_5),

	/*
	 * TD attempts to set bit PCE(8) results in a #GP(0),
	 * if the TD's ATTRIBUTES.PERFMON is 0.
	 */
	DEF_SET_CR4(X86_CR4_PCE, NO_EXCP, pre_cond_cr4_perfmon, VER1_0),

	/*
	 * TD attempts to set bit KL(19) results in a #GP(0),
	 * if the TD's ATTRIBUTES.KL is 0.
	 */
	DEF_SET_CR4(X86_CR4_KL, NO_EXCP, pre_cond_cr4_kl, VER1_0 | VER1_5),

	/*
	 * TD attempts to set bit PKS(24) results in a #GP(0),
	 * if the TD's ATTRIBUTES.PKS is 0.
	 */
	DEF_SET_CR4(X86_CR4_PKS, NO_EXCP, pre_cond_cr4_pks, VER1_0 | VER1_5),

	/*
	 * TD modification of CR4 bit PKE(22) is prevented,
	 * depending on TD's XFAM.
	 */
	DEF_XCH_CR4(X86_CR4_PKE, NO_EXCP, pre_cond_cr4_pke, VER1_0 | VER1_5),

	/*
	 * TD modification of CR4 bit CET(23) is prevented,
	 * depending on TD's XFAM.
	 */
	DEF_XCH_CR4(X86_CR4_CET, NO_EXCP, pre_cond_cr4_cet, VER1_0 | VER1_5),

	/*
	 * TD modification of CR4 bit UINT(25) is prevented,
	 * depending on TD's XFAM
	 */
	DEF_XCH_CR4(X86_CR4_UINT, NO_EXCP, pre_cond_cr4_uint, VER1_0 | VER1_5),
};
