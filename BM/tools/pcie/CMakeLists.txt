# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (c) 2024 Intel Corporation.
# Haoliang Zhu <haoliang.zhu@intel.com>

cmake_minimum_required(VERSION 3.12)
project(pcie_check)

# Set the build output directory
set(BUILD_OUTPUT ${CMAKE_CURRENT_BINARY_DIR})

# Set the installation prefix 
set(CMAKE_INSTALL_PREFIX /usr/loacl/bin)

# Set the source files
set(SRC pcie_check.c)

# Add the executable
add_executable(pcie_check ${SRC})

# Install the program
install(TARGETS pcie_check DESTINATION ${CMAKE_INSTALL_PREFIX})
