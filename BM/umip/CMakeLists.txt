# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (c) 2024 Intel Corporation.
# Haoliang Zhu <haoliang.zhu@intel.com>

cmake_minimum_required(VERSION 3.12)
project(umip)

# Set the build output directory
set(BUILD_OUTPUT ${CMAKE_CURRENT_BINARY_DIR})

# Set the installation prefix 
set(CMAKE_INSTALL_PREFIX /usr/local/bin)

# Set the source files
set(SRC umip_utils.c)

# Build umip_utils_64.o from umip_utils.c
add_library(umip_utils_64 OBJECT ${SRC})

# Build umip_exceptions_64 executable
add_executable(umip_exceptions_64 umip_exceptions.c)
target_link_libraries(umip_exceptions_64 umip_utils_64)

# Build umip_test_basic_64 executable
add_executable(umip_test_basic_64 umip_test_basic.c)
target_link_libraries(umip_test_basic_64 umip_utils_64)

execute_process(
    COMMAND gcc -no-pie -c umip_utils.c -m32 -o umip_utils_32.o
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    RESULT_VARIABLE RESULT
    OUTPUT_QUIET
    ERROR_QUIET
)

if(RESULT EQUAL 0)
    set(COMPILER_SUPPORTS_M32 TRUE)
    message(STATUS "32-bit compilation is supported.")
    # Build umip_utils_32.o from umip_utils.c with -m32 flag
    add_library(umip_utils_32 OBJECT ${SRC})
    target_compile_options(umip_utils_32 PRIVATE "-m32")

    # Build umip_exceptions_32 executable with -m32 flag
    add_executable(umip_exceptions_32 umip_exceptions.c)
    target_link_libraries(umip_exceptions_32 umip_utils_32 "-m32")
    target_compile_options(umip_exceptions_32 PRIVATE "-m32")
else()
    message(WARNING "Skip 32-bit compilation or clean due to lack of GCC support for 32-bit architecture.")
endif()

# Install the program
if(COMPILER_SUPPORTS_M32)
    install(TARGETS umip_exceptions_64 umip_test_basic_64 umip_exceptions_32 DESTINATION ${CMAKE_INSTALL_PREFIX}/bin)
else()
    install(TARGETS umip_exceptions_64 umip_test_basic_64 DESTINATION ${CMAKE_INSTALL_PREFIX})
endif()
