# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (c) 2024 Intel Corporation.
# Haoliang Zhu <haoliang.zhu@intel.com>

cmake_minimum_required(VERSION 3.12)
project(xstate_64)

# Set the build output directory
set(BUILD_OUTPUT ${CMAKE_CURRENT_BINARY_DIR})

# Set the installation prefix 
set(CMAKE_INSTALL_PREFIX /usr/local/bin)

# Set the global compilation flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O2 -g -std=gnu99 -pthread -Wall -no-pie")

# Set the source files
set(SRC xstate.c)

# Build xstate_helpers.o from xstate_helpers.c
add_library(xstate_helpers OBJECT xstate_helpers.c)
target_compile_options(xstate_helpers PRIVATE -mno-sse -mno-mmx -mno-sse2 -mno-avx -mno-pku)

add_executable(xstate_64 ${SRC})

# Link libraries
target_link_libraries(xstate_64 PRIVATE xstate_helpers)
target_link_libraries(xstate_64 PRIVATE rt dl)

# Install the program
install(TARGETS xstate_64 DESTINATION ${CMAKE_INSTALL_PREFIX})
