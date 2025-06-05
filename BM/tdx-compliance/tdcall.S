/*
 * Low level helpers for tdcall
 *
 * Copyright (c) 2023, Intel Inc
 *
 * Authors:
 *   Zhenzhong Duan <zhenzhong.duan@intel.com>
 *   Qian Wen <qian.wen@intel.com>
 *
 * SPDX-License-Identifier: GPL-2.0
 */
#include <linux/linkage.h>
#include "tdxcall.S"

/*
 * __tdcall()  - Used by TDX guests to request services from the TDX
 * module (does not include VMM services) using TDCALL instruction.
 *
 * __tdcall() function ABI:
 *
 * @fn   (RDI)	- TDCALL Leaf ID, moved to RAX
 * @args (RSI)	- struct tdx_module_args for input
 *
 * Only RCX/RDX/R8-R11 are used as input registers.
 *
 * Return status of TDCALL via RAX.
 */
.global __tdcall
__tdcall:
	TDX_MODULE_CALL host=0

/*
 * __tdcall_ret() - Used by TDX guests to request services from the TDX
 * module (does not include VMM services) using TDCALL instruction, with
 * saving output registers to the 'struct tdx_module_args' used as input.
 *
 * __tdcall_ret() function ABI:
 *
 * @fn   (RDI)	- TDCALL Leaf ID, moved to RAX
 * @args (RSI)	- struct tdx_module_args for input and output
 *
 * Only RCX/RDX/R8-R11 are used as input/output registers.
 *
 * Return status of TDCALL via RAX.
 */
.global __tdcall_ret
__tdcall_ret:
	TDX_MODULE_CALL host=0 ret=1

/*
 * __tdcall_saved_ret() - Used by TDX guests to request services from the
 * TDX module (including VMM services) using TDCALL instruction, with
 * saving output registers to the 'struct tdx_module_args' used as input.
 *
 * __tdcall_saved_ret() function ABI:
 *
 * @fn   (RDI)	- TDCALL leaf ID, moved to RAX
 * @args (RSI)	- struct tdx_module_args for input/output
 *
 * All registers in @args are used as input/output registers.
 *
 * On successful completion, return the hypercall error code.
 */
.global __tdcall_saved_ret
__tdcall_saved_ret:
	TDX_MODULE_CALL host=0 ret=1 saved=1
