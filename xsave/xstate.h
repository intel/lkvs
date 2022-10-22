// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2022 Intel Corporation.

#include "../common/kselftest.h"

#define XSTATE_TESTBYTE		0x8f
/* Bits 0-1 in first byte of PKRU must be 0 for RW access to linear address. */
#define PKRU_TESTBYTE		0xfc
/* FP xstate(0-159 bytes) offset(0) and size(160 bytes) are fixed. */
#define FP_SIZE			160
/* XMM xstate(160-415 bytes) offset(160 byte) and size(256 bytes) are fixed. */
#define XMM_OFFSET		160
#define XMM_SIZE		256
/*
 * xstate 416-511 bytes are reserved, XSAVE header offset 512 bytes
 * and header size 64 bytes are fixed.
 */
#define XSAVE_HDR_OFFSET	512
#define XSAVE_HDR_SIZE		64

#define CPUID_LEAF1_ECX_XSAVE_MASK	(1 << 26) /* XSAVE instructions */
#define CPUID_LEAF1_ECX_OSXSAVE_MASK	(1 << 27) /* OSXSAVE flag */

#define CPUID_LEAF7_EBX_AVX2_MASK	(1U << 5) /* AVX2 instructions */
#define CPUID_LEAF7_EBX_AVX512F_MASK	(1U << 16) /* AVX-512 Foundation */

#define CPUID_LEAF7_ECX_OSPKE_MASK	(1U << 4) /* OS Protection Keys Enable */

#define CPUID_LEAF_XSTATE		0xd
#define CPUID_SUBLEAF_XSTATE_USER	0x0

/* It's from arch/x86/kernel/fpu/xstate.c. */
static const char * const xfeature_names[] = {
	"x87 floating point registers",
	"SSE registers",
	"AVX registers",
	"MPX bounds registers",
	"MPX CSR",
	"AVX-512 opmask",
	"AVX-512 Hi256",
	"AVX-512 ZMM_Hi256",
	"Processor Trace (unused)",
	"Protection Keys User registers",
	"PASID state",
	"unknown xstate feature",
	"unknown xstate feature",
	"unknown xstate feature",
	"unknown xstate feature",
	"unknown xstate feature",
	"unknown xstate feature",
	"AMX Tile config",
	"AMX Tile data",
	"unknown xstate feature",
};

/* List of XSAVE features Linux knows about. */
enum xfeature {
	XFEATURE_FP,
	XFEATURE_SSE,
	/*
	 * Values above here are "legacy states".
	 * Those below are "extended states".
	 */
	XFEATURE_YMM,
	XFEATURE_BNDREGS,
	XFEATURE_BNDCSR,
	XFEATURE_OPMASK,
	XFEATURE_ZMM_Hi256,
	XFEATURE_Hi16_ZMM,
	XFEATURE_PT_UNIMPLEMENTED_SO_FAR,
	XFEATURE_PKRU,
	XFEATURE_PASID,
	XFEATURE_RSRVD_COMP_11,
	XFEATURE_RSRVD_COMP_12,
	XFEATURE_RSRVD_COMP_13,
	XFEATURE_RSRVD_COMP_14,
	XFEATURE_LBR,
	XFEATURE_RSRVD_COMP_16,
	XFEATURE_XTILE_CFG,
	XFEATURE_XTILE_DATA,
	XFEATURE_MAX,
};

enum xstate_case {
	XSTATE_CASE_SIG,
	XSTATE_CASE_FORK,
	XSTATE_CASE_MAX,
};

struct xsave_buffer {
	union {
		struct {
			char legacy[XSAVE_HDR_OFFSET];
			char header[XSAVE_HDR_SIZE];
			char extended[0];
		};
		char bytes[0];
	};
};

struct {
	uint64_t mask;
	uint32_t size[XFEATURE_MAX];
	uint32_t offset[XFEATURE_MAX];
} xstate_info;

struct xstate_test {
	bool (*init)(uint32_t xfeature_num);
	void (*fill_xbuf)(void *buf, uint32_t xfeature_num, uint8_t test_byte);
	void (*xstate_case)(void);
};

static void check_cpuid_xsave_availability(void)
{
	uint32_t eax, ebx, ecx, edx;

	/*
	 * CPUID.1:ECX.XSAVE[bit 26] enumerates general
	 * support for the XSAVE feature set, including
	 * XGETBV.
	 */
	__cpuid_count(1, 0, eax, ebx, ecx, edx);
	if (!(ecx & CPUID_LEAF1_ECX_XSAVE_MASK))
		ksft_exit_skip("cpuid: CPU doesn't support xsave.\n");

	if (!(ecx & CPUID_LEAF1_ECX_OSXSAVE_MASK))
		ksft_exit_skip("cpuid: CPU doesn't support OS xsave.\n");
}

/* Retrieve the mask, offset and size of a specific xstate. */
static void retrieve_xstate_mask_size_offset(uint32_t xfeature_num)
{
	uint32_t eax, ebx, ecx, edx;

	xstate_info.mask = (uint64_t)(xstate_info.mask | (1 << xfeature_num));
	/*
	 * The offset and size of xstate FP and SSE are not recorded by CPUID,
	 * the contents of FP (x87 state) and MXCSR register are mixed in
	 * bytes 0-511.
	 */
	if (xfeature_num == XFEATURE_FP || xfeature_num == XFEATURE_SSE)
		return;

	__cpuid_count(CPUID_LEAF_XSTATE, xfeature_num, eax, ebx, ecx, edx);
	/*
	 * CPUID.(EAX=0xd, ECX=xfeature_num), and output is as follow:
	 * eax: xfeature num state component size
	 * ebx: xfeature num state component offset in user buffer
	 */
	if (!eax || !ebx)
		ksft_exit_fail_msg("xfeature num:%d size/offset:%d/%d is 0.\n",
				   xfeature_num, eax, ebx);

	xstate_info.size[xfeature_num] = eax;
	xstate_info.offset[xfeature_num] = ebx;
}

/* Retrieve legacy FP and SSE xstate info. */
static bool init_legacy_info(uint32_t xfeature_num)
{
	retrieve_xstate_mask_size_offset(xfeature_num);
	return true;
}

static bool init_ymm_info(uint32_t xfeature_num)
{
	uint32_t eax, ebx, ecx, edx;

	/* CPUID.7.0:EBX.AVX2[bit 5]: the support for AVX2 instructions. */
	__cpuid_count(7, 0, eax, ebx, ecx, edx);
	if (ebx & CPUID_LEAF7_EBX_AVX2_MASK) {
		retrieve_xstate_mask_size_offset(xfeature_num);
		return true;
	}
	return false;
}

static bool init_avx512_info(uint32_t xfeature_num)
{
	uint32_t eax, ebx, ecx, edx;

	/* CPUID.7.0:EBX.AVX512F[bit 16]: support for AVX512F instructions. */
	__cpuid_count(7, 0, eax, ebx, ecx, edx);
	if (ebx & CPUID_LEAF7_EBX_AVX512F_MASK) {
		retrieve_xstate_mask_size_offset(xfeature_num);
		return true;
	}
	return false;
}

static bool init_pkru_info(uint32_t xfeature_num)
{
	uint32_t eax, ebx, ecx, edx;

	/* CPUID.7.0:ECX.OSPKE[bit 4]: the support for OS set CR4.PKE. */
	__cpuid_count(7, 0, eax, ebx, ecx, edx);
	if (ecx & CPUID_LEAF7_ECX_OSPKE_MASK) {
		retrieve_xstate_mask_size_offset(xfeature_num);
		return true;
	}
	return false;
}

static void fill_xmm_xstate_buf(void *buf, uint32_t xfeature_num,
				uint8_t test_byte)
{
	/*
	 * Fill test byte value into SSE XMM part xstate buffer(160-415 bytes).
	 * xstate 416-511 bytes are reserved as all 0.
	 */
	memset((unsigned char *)buf + XMM_OFFSET, test_byte, XMM_SIZE);
}

static void fill_common_xstate_buf(void *buf, uint32_t xfeature_num,
				   uint8_t test_byte)
{
	memset((unsigned char *)buf + xstate_info.offset[xfeature_num],
	       test_byte, xstate_info.size[xfeature_num]);
}

static void fill_pkru_xstate_buf(void *buf, uint32_t xfeature_num,
				 uint8_t test_byte)
{
	/*
	 * Only 0-3 bytes of PKRU xstate are allowed to be written. 4-7
	 * bytes are reserved as all 0.
	 */
	memset((unsigned char *)buf + xstate_info.offset[XFEATURE_PKRU],
	       test_byte, sizeof(uint32_t));
}
