# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation.
cmake_minimum_required(VERSION 3.10)

# Set project name and version
project(LKVS VERSION 1.0)

# Find all subdirectories in the current directory
file(GLOB children RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/*)

# Run cmake on all subdirectories containing a CMakeLists.txt file
foreach(child ${children})
    if(IS_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/${child})
        if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/${child}/CMakeLists.txt)
            execute_process(
                COMMAND cmake .
                WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/${child}
            )
            add_subdirectory(${child})
        endif()
    endif()
endforeach()
