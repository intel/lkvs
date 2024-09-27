# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (c) 2024 Intel Corporation.
# Haoliang Zhu <haoliang.zhu@intel.com>

cmake_minimum_required(VERSION 3.12)
project(telemetry_tests)

# Set the build output directory
set(BUILD_OUTPUT ${CMAKE_CURRENT_BINARY_DIR})

# Set the installation prefix 
set(CMAKE_INSTALL_PREFIX /usr/local/bin)

# Set the source files
set(SRC telemetry_tests.c)

# Add the executable
add_executable(telemetry_tests ${SRC})

# Install the program
install(TARGETS telemetry_tests DESTINATION ${CMAKE_INSTALL_PREFIX})
