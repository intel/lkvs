# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation

"""
Shared helpers for downloading, building, and running nbench-byte
inside a guest VM.
"""

import re


_NBENCH_RESULT_RE = re.compile(
    r"^\s*(NUMERIC SORT|STRING SORT|BITFIELD|FP EMULATION|FOURIER|"
    r"ASSIGNMENT|IDEA|HUFFMAN|NEURAL NET|LU DECOMPOSITION)\b"
)


def prepare_nbench(session, guest_workdir, params):
    """Download nbench tarball in guest, extract and build.

    Required params: ``nbench_url``, ``nbench_tarball``,
    ``nbench_extracted_dir``.
    """
    nbench_url = params["nbench_url"]
    tarball = params["nbench_tarball"]
    extracted = params["nbench_extracted_dir"]

    session.cmd("mkdir -p %s" % guest_workdir)
    session.cmd("rm -rf %s/*" % guest_workdir, ignore_all_errors=True)

    session.cmd(
        "cd %s && wget -q %s -O %s" % (guest_workdir, nbench_url, tarball),
        timeout=120,
    )
    session.cmd(
        "cd %s && tar xzf %s" % (guest_workdir, tarball), timeout=60,
    )
    session.cmd(
        "cd %s/%s && sed -i 's/-static//' Makefile && make"
        % (guest_workdir, extracted),
        timeout=180,
    )


def run_nbench(session, guest_workdir, params, test, label="nbench"):
    """Run nbench under a bounded timeout and validate result output.

    Required params: ``nbench_extracted_dir``,
    ``nbench_max_runtime_seconds``, ``nbench_min_result_lines``.

    :param label: prefix for log/failure messages (e.g. ``"pre-lm"``).
    """
    extracted = params["nbench_extracted_dir"]
    max_seconds = int(params["nbench_max_runtime_seconds"])
    min_lines = int(params["nbench_min_result_lines"])

    out = session.cmd_output(
        "cd %s/%s && stdbuf -oL timeout %d ./nbench 2>&1"
        % (guest_workdir, extracted, max_seconds),
        timeout=max_seconds + 60,
    )

    result_lines = [
        line for line in out.splitlines() if _NBENCH_RESULT_RE.match(line)
    ]
    test.log.info(
        "%s: nbench emitted %d result lines (need >= %d)",
        label, len(result_lines), min_lines,
    )
    for line in result_lines[:min_lines]:
        test.log.info("  %s", line)
    if len(result_lines) < min_lines:
        test.fail(
            "%s: nbench produced %d result lines; expected >= %d. "
            "Tail of output:\n%s"
            % (
                label,
                len(result_lines),
                min_lines,
                "\n".join(out.splitlines()[-10:]),
            )
        )
