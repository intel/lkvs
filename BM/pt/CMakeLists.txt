# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (c) 2024 Intel Corporation.
# Haoliang Zhu <haoliang.zhu@intel.com>

cmake_minimum_required(VERSION 3.12)
project(pt)

# Set the build output directory
set(BUILD_OUTPUT ${CMAKE_CURRENT_BINARY_DIR})

# Set the installation prefix
set(CMAKE_INSTALL_PREFIX /usr/local/bin)

# Check if the header file "intel-pt.h" exists
include(CheckIncludeFile)
check_include_file("intel-pt.h" HAVE_INTEL_PT_H)
if(NOT HAVE_INTEL_PT_H)
    message(WARNING "Skipping the build of pt, please install libipt first. 
    You can read BM/pt/README.md for more information.")
    return()
endif()
# Set the global compilation flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -g -Wall -DMAINLINE -I./")

# Set the source files
set(SRC utils.c)

# Set the binary files
set(BIN cpl branch psb nonroot_test negative_test sort_test)

# Set the libraries
set(LFLAGS -L./ -lipt)

foreach(target ${BIN})
    add_executable(${target} ${target}.c ${SRC})
    # Link libraries
    target_link_libraries(${target} ${LFLAGS})
endforeach()

# Install the program
install(TARGETS ${BIN} DESTINATION ${CMAKE_INSTALL_PREFIX})
