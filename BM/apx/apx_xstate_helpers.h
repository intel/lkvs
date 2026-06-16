/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (c) 2024 Intel Corporation. */

#ifndef APX_XSTATE_HELPERS_H
#define APX_XSTATE_HELPERS_H

#include <stdint.h>
#include <stdbool.h>

typedef uint8_t  u8;
typedef uint32_t u32;
typedef uint64_t u64;

#ifndef BIT_ULL
#define BIT_ULL(nr)		(1ULL << (nr))
#endif

/* APX XSAVE state component number */
#define XFEATURE_APX		19
#define XFEATURE_MASK_APX	BIT_ULL(XFEATURE_APX)

/* APX EGPR state: 16 x 64-bit registers (R16-R31) = 128 bytes */
#define APX_STATE_SIZE		128
#define APX_NUM_REGS		16

/* XSAVE buffer alignment requirement */
#define XSAVE_ALIGNMENT		64

/* XSAVE header offset and size */
#define XSAVE_HDR_OFFSET	512
#define XSAVE_HDR_SIZE		64

struct apx_state {
	u64 egpr[APX_NUM_REGS];  /* R16-R31 */
};

void fill_egpr_registers(u64 pattern);
void xsave_apx(void *buf, u64 mask);
void xrstor_apx(void *buf, u64 mask);
bool apx_signal_test(void *valid_xbuf, void *compared_xbuf,
		     u64 mask, u32 xstate_size);
bool apx_fork_test(void *valid_xbuf, void *compared_xbuf,
		   u64 mask, u32 xstate_size);
bool apx_context_switch_test(void *valid_xbuf, void *compared_xbuf,
			     u64 mask, u32 xstate_size);

#endif /* APX_XSTATE_HELPERS_H */
