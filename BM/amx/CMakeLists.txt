# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (c) 2024 Intel Corporation.
# Haoliang Zhu <haoliang.zhu@intel.com>

cmake_minimum_required(VERSION 3.12)
project(tmul)

# Set the build output directory
set(BUILD_OUTPUT ${CMAKE_CURRENT_BINARY_DIR})

# Set the installation prefix 
set(CMAKE_INSTALL_PREFIX /usr/local/bin)

# Set the source files
set(SRC tmul.c)

# Get target CPU information
execute_process(
    COMMAND ${CMAKE_C_COMPILER} -march=native -Q --help=target
    OUTPUT_VARIABLE TARGET_CPU
    ERROR_QUIET
)

# Check if the target CPU supports AMX
string(REGEX MATCH "-mamx-tile[ \t]+\\[enabled\\]" AMX_SUPPORTED "${TARGET_CPU}")

if(AMX_SUPPORTED)
    message(STATUS "AMX supported by the CPU.")
else()
    message(WARNING "AMX not supported by the CPU - skipping tmul build.")
    return()
endif()

# Add the executable
add_executable(tmul ${SRC})

# Auto-enable the FP16 (TDPFP16PS, -i 5) cases when the toolchain can assemble
# tdpfp16ps. Older toolchains (binutils < 2.38 / gcc < 13.3, some distros
# backport to 12.3) build tmul without FP16 so the remaining AMX cases still
# compile.
include(CheckCSourceCompiles)
check_c_source_compiles(
    "int main(void){asm volatile(\"tdpfp16ps %tmm7, %tmm6, %tmm5\");return 0;}"
    HAVE_TDPFP16PS)
if(HAVE_TDPFP16PS)
    target_compile_definitions(tmul PRIVATE FP16)
else()
    message(WARNING "Toolchain cannot assemble tdpfp16ps; building tmul without FP16.")
endif()

# Link libraries
target_link_libraries(tmul m pthread)

# Install the program
install(TARGETS tmul DESTINATION ${CMAKE_INSTALL_PREFIX})
