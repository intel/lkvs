# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation.
cmake_minimum_required(VERSION 3.10)

# Set project name and version
project(th_test VERSION 1.0)

# Find all source files in the current directory
file(GLOB SOURCES *.c *.h)

# Create an executable from the source files
add_executable(th_test ${SOURCES})
