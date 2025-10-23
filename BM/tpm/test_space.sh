#!/bin/bash
# SPDX-License-Identifier: (GPL-2.0 OR BSD-3-Clause)

# Kselftest framework requirement - SKIP code is 4.
ksft_skip=4

[ -e /dev/tpmrm0 ] || exit $ksft_skip

# shellcheck disable=SC3028,SC3054
TPM_ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
export PYTHONPATH="$TPM_ROOT"
python3 -m unittest -v tpm2_tests.SpaceTest
