# Linux PKU selftest sources

These files are based on sources from the Linux kernel repository:

- Upstream: https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
- Commit: `666539eecdf4db623f5e3c3e55cf9f2dfad24aa4`
- Imported: 2026-11-17

Source paths:

- `tools/testing/selftests/mm/protection_keys.c`
- `tools/testing/selftests/mm/pkey_util.c`
- `tools/testing/selftests/mm/pkey-helpers.h`
- `tools/testing/selftests/mm/pkey-x86.h`
- `tools/testing/selftests/kselftest.h`
- `tools/lib/mm/hugepage_settings.c`
- `tools/lib/mm/hugepage_settings.h`
- `tools/lib/mm/file_utils.c`
- `tools/lib/mm/file_utils.h`

Each source file retains its upstream SPDX identifier. The files are licensed
under GPL-2.0 or GPL-2.0-only as indicated in their individual headers.

Local adaptations:

- `pkey_compat.h` supplies `PKEY_UNRESTRICTED` when the guest's UAPI headers
	predate that definition.
- `protection_keys.c` keeps the original process alive until the forked test
	process completes and propagates its status to the test runner.
- `protection_keys.c` checks the number of allocated keys instead of the loop
	index after exhausting the available keys.

All other imported source files are unmodified copies of the commit above.

The `cpu_pku` case copies this directory into the guest and builds the test
there. It does not download Linux sources or require a prebuilt kselftest
package.
