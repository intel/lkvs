# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (c) 2024 Intel Corporation.
# Haoliang Zhu <haoliang.zhu@intel.com>

cmake_minimum_required(VERSION 3.12)
project(th_test)

# Set the build output directory
set(BUILD_OUTPUT ${CMAKE_CURRENT_BINARY_DIR})

# Set the installation prefix 
set(CMAKE_INSTALL_PREFIX /usr/local/bin)

# Set the global compilation flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -ggdb -Wall -fstack-protector-all")

# Set the source files
set(SRC th_test.c)

# Add the executable
add_executable(th_test ${SRC})

# Install the program
install(TARGETS th_test DESTINATION ${CMAKE_INSTALL_PREFIX})
