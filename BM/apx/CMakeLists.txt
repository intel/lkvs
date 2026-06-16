# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2024 Intel Corporation.

cmake_minimum_required(VERSION 3.12)
project(apx)

# Set the build output directory
set(BUILD_OUTPUT ${CMAKE_CURRENT_BINARY_DIR})

# Set the installation prefix
set(CMAKE_INSTALL_PREFIX /usr/local/bin)

# Set common compilation flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O2 -g -std=gnu99 -Wall -no-pie")

# APX requires GCC 14+ with -mapxf or compatible assembler
# Check for APX assembler support
include(CheckCCompilerFlag)
check_c_compiler_flag("-mapxf" HAS_MAPXF)

if(HAS_MAPXF)
    set(APX_FLAGS "-mapxf")
else()
    message(WARNING "Compiler does not support -mapxf, using raw .byte encoding")
    set(APX_FLAGS "")
endif()

# Build apx_cpuid
add_executable(apx_cpuid apx_cpuid.c)

# Build apx_xstate_helpers as object library (needs special flags)
add_library(apx_xstate_helpers OBJECT apx_xstate_helpers.c)
target_compile_options(apx_xstate_helpers PRIVATE
    -mno-sse -mno-mmx -mno-sse2 -mno-avx -mno-pku ${APX_FLAGS})

# Build apx_xstate
add_executable(apx_xstate apx_xstate.c)
target_link_libraries(apx_xstate PRIVATE apx_xstate_helpers)

# Build apx_egpr
add_executable(apx_egpr apx_egpr.c)
target_compile_options(apx_egpr PRIVATE ${APX_FLAGS})

# Build apx_instructions
add_executable(apx_instructions apx_instructions.c)
target_compile_options(apx_instructions PRIVATE ${APX_FLAGS})

# Build apx_ptrace
add_executable(apx_ptrace apx_ptrace.c)
target_link_libraries(apx_ptrace PRIVATE apx_xstate_helpers)

# Build apx_sigcontext
add_executable(apx_sigcontext apx_sigcontext.c)
target_link_libraries(apx_sigcontext PRIVATE apx_xstate_helpers)

# Build apx_ctxsw
add_executable(apx_ctxsw apx_ctxsw.c)
target_link_libraries(apx_ctxsw PRIVATE apx_xstate_helpers pthread)

# Install targets
install(TARGETS apx_cpuid apx_xstate apx_egpr apx_instructions
                apx_ptrace apx_sigcontext apx_ctxsw
        RUNTIME DESTINATION ${CMAKE_INSTALL_PREFIX})
