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

# Link libraries
target_link_libraries(tmul m pthread)

# Install the program
install(TARGETS tmul DESTINATION ${CMAKE_INSTALL_PREFIX})
