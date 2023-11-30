#include "tdx-compliance.h"

/* pre-conditions */
static int get_perfmon(void) {
	/* PERFMON: CPUID(0xa).* */
	struct test_cpuid cpt = DEF_CPUID_TEST(0xa, 0);

	run_cpuid(&cpt);

	if (cpt.regs.eax.val == 0 && cpt.regs.ebx.val == 0 &&
	    cpt.regs.ecx.val == 0 && cpt.regs.edx.val == 0)
		return 0;

	return 1;
}

static void pre_perfmon(struct test_msr *c)
{
	if (!get_perfmon())
		c->excp.expect = X86_TRAP_GP;
}

static void pre_pks(struct test_msr *c)
{
	/* PKS: CPUID(0x7,0x0).ecx[31] */
	struct test_cpuid cpt = DEF_CPUID_TEST(0x7, 0);

	run_cpuid(&cpt);

	if ((cpt.regs.ecx.val & _BITUL(31)) == 0)
		c->excp.expect = X86_TRAP_GP;
}

static void pre_0x1_ecx24(struct test_msr *c)
{
	/* CPUID(0x1,0x0).ecx[24] */
	struct test_cpuid cpt = DEF_CPUID_TEST(0x1, 0);

	run_cpuid(&cpt);

	if ((cpt.regs.ecx.val & _BITUL(24)) == 0)
		c->excp.expect = X86_TRAP_GP;
}

static void pre_0x7_ecx5(struct test_msr *c)
{
	/* CPUID(0x7,0x0).ecx[5] */
	struct test_cpuid cpt = DEF_CPUID_TEST(0x7, 0);

	run_cpuid(&cpt);

	if ((cpt.regs.ecx.val & _BITUL(5)) == 0)
		c->excp.expect = X86_TRAP_GP;
}

static void pre_0x7_ecx13(struct test_msr *c)
{
	/* CPUID(0x7,0x0).ecx[13] */
	struct test_cpuid cpt = DEF_CPUID_TEST(0x7, 0);

	run_cpuid(&cpt);

	if ((cpt.regs.ecx.val & _BITUL(13)) == 0)
		c->excp.expect = X86_TRAP_GP;
}

static void pre_0x7_edx18(struct test_msr *c)
{
	/* CPUID(0x7,0x0).edx[18] */
	struct test_cpuid cpt = DEF_CPUID_TEST(0x7, 0);

	run_cpuid(&cpt);

	if ((cpt.regs.edx.val & _BITUL(18)) == 0)
		c->excp.expect = X86_TRAP_GP;
}

static void pre_0xd_0x1_eax4(struct test_msr *c)
{
	/* CPUID(0xd,0x1).eax[4] */
	struct test_cpuid cpt = DEF_CPUID_TEST(0xd, 1);

	run_cpuid(&cpt);

	if ((cpt.regs.eax.val & _BITUL(4)) == 0)
		c->excp.expect = X86_TRAP_GP;
}

static void pre_0x1_ecx18(struct test_msr *c)
{
	/* CPUID(0x1).ecx[18] */
	struct test_cpuid cpt = DEF_CPUID_TEST(0x1, 0);

	run_cpuid(&cpt);

	if ((cpt.regs.ecx.val & _BITUL(18)) == 0)
		c->excp.expect = X86_TRAP_GP;
}

static void pre_xfam_8(struct test_msr *c)
{
	/* XFAM[8] RTIT CPUID(0x7,0x0).ebx[25] */
	struct test_cpuid cpt = DEF_CPUID_TEST(0x7, 0);

	run_cpuid(&cpt);

	if ((cpt.regs.ebx.val & _BITUL(25)) == 0)
		c->excp.expect = X86_TRAP_GP;
}

static void pre_xfam_12_11(struct test_msr *c)
{
	/* XFAM[12:11] CET CPUID(0xd,0x1).ecx[12:11] */
	struct test_cpuid cpt = DEF_CPUID_TEST(0xd, 1);

	run_cpuid(&cpt);

	if ((cpt.regs.ecx.val & _BITUL(11)) == 0 &&
	    (cpt.regs.ecx.val & _BITUL(12)) == 0)
		c->excp.expect = X86_TRAP_GP;
}

static void pre_xfam_14(struct test_msr *c)
{
	/* XFAM[14] ULI CPUID(0x7,0x0).edx[5] */
	struct test_cpuid cpt = DEF_CPUID_TEST(0x7, 0);

	run_cpuid(&cpt);

	if ((cpt.regs.edx.val & _BITUL(5)) == 0)
		c->excp.expect = X86_TRAP_GP;
}

static void pre_xfam_15(struct test_msr *c)
{
	/* XFAM[15] LBR CPUID(0x7,0x0).edx[19] */
	struct test_cpuid cpt = DEF_CPUID_TEST(0x7, 0);

	run_cpuid(&cpt);

	if ((cpt.regs.edx.val & _BITUL(19)) == 0)
		c->excp.expect = X86_TRAP_GP;
}

static void pre_tsx(struct test_msr *c)
{
	/* TSX enabled: IA32_ARCH_CAPABILITIES[7] */
	struct test_msr t = DEF_READ_MSR("MSR_IA32_ARCH_CAPABILITIES", 0x10a, NO_EXCP, NO_PRE_COND, VER1_0);

	if (!read_msr_native(&t)) {
		if ((t.msr.val.q & _BITUL(7)) == 0)
			c->excp.expect = X86_TRAP_GP;
	}
}

static void pre_fixedctr(struct test_msr *c)
{
	struct test_cpuid cpt = DEF_CPUID_TEST(0xa, 0x0);

	run_cpuid(&cpt);

	if (!get_perfmon() || (cpt.regs.edx.val & 0x1f) == 0)
		c->excp.expect = X86_TRAP_GP;
}
