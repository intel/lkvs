// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2022 Intel Corporation.

#include <stdint.h>

extern void fill_fp_mxcsr_xstate_buf(void *buf, uint32_t xfeature_num,
				     uint8_t ui8_fp);
extern bool xstate_sig_handle(void *valid_xbuf, void *compared_xbuf,
			      uint64_t mask, uint32_t xstate_size);
extern bool xstate_fork(void *valid_xbuf, void *compared_xbuf,
			uint64_t mask, uint32_t xstate_size);
