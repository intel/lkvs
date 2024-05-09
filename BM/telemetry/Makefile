# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation.

all:
	gcc telemetry_tests.c -m64 -o telemetry_tests
	gcc telemetry_tests.c -m32 -o telemetry_tests_32

clean:
	rm -rf telemetry_tests
	rm -rf telemetry_tests_32
