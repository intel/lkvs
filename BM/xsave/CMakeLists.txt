# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (c) 2024 Intel Corporation.
# Haoliang Zhu <haoliang.zhu@intel.com>

cmake_minimum_required(VERSION 3.12)
project(xsave)

# Set the build output directory
set(BUILD_OUTPUT ${CMAKE_CURRENT_BINARY_DIR})

# Set the installation prefix 
set(CMAKE_INSTALL_PREFIX /usr/local/bin)

# Set the global compilation flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O2 -g -std=gnu99 -pthread -Wall -no-pie")

# Flags to disable FPU/vector code generation for the no-FPU test programs
set(NO_FPU_FLAG -mno-sse -mno-mmx -mno-sse2 -mno-avx -mno-pku)

# Build xstate_helpers.o from xstate_helpers.c
add_library(xstate_helpers OBJECT xstate_helpers.c)
target_compile_options(xstate_helpers PRIVATE ${NO_FPU_FLAG})

add_executable(xstate_64 xstate.c)
target_compile_definitions(xstate_64 PRIVATE CAN_BUILD_32 CAN_BUILD_64)
target_link_libraries(xstate_64 PRIVATE xstate_helpers)
target_link_libraries(xstate_64 PRIVATE rt dl)

add_executable(xsave_list xsave_list.c)

add_executable(xsave_test xsave_test.c)

# Install the programs
install(TARGETS
  xstate_64 xsave_list xsave_test
  DESTINATION ${CMAKE_INSTALL_PREFIX})
