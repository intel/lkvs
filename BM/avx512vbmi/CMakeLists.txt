# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (c) 2024 Intel Corporation.
# Haoliang Zhu <haoliang.zhu@intel.com>

cmake_minimum_required(VERSION 3.12)
project(vbmi_test)

# Set the build output directory
set(BUILD_OUTPUT ${CMAKE_CURRENT_BINARY_DIR})

# Set the installation prefix 
set(CMAKE_INSTALL_PREFIX /usr/local/bin)

# Set the source files
set(SRC vbmi_test.c)

# Get target CPU information
execute_process(
    COMMAND ${CMAKE_C_COMPILER} -march=native -Q --help=target
    OUTPUT_VARIABLE TARGET_CPU
    ERROR_QUIET
)

# Check if the target CPU supports AVX-512VBMI
string(REGEX MATCH "-mavx512vbmi[ \t]+\\[enabled\\]" AVX512VBMI_SUPPORTED "${TARGET_CPU}")

if(AVX512VBMI_SUPPORTED)
    message(STATUS "AVX-512VBMI supported by the CPU.")
else()
    message(WARNING "AVX-512VBMI not supported by the CPU - skipping vbmi_test build.")
    return()
endif()

# Add the executable
add_executable(vbmi_test ${SRC})

# Install the program
install(TARGETS vbmi_test DESTINATION ${CMAKE_INSTALL_PREFIX})
