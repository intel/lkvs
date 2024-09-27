# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (c) 2024 Intel Corporation.
# Yi Sun <yi.sun@intel.com>
# Haoliang Zhu <haoliang.zhu@intel.com>

cmake_minimum_required(VERSION 3.12)
project(Yogini)

# Set the build output directory
set(BUILD_OUTPUT ${CMAKE_CURRENT_BINARY_DIR})

# Set the installation prefix
set(CMAKE_INSTALL_PREFIX /usr/local/bin)

# Set the source files
set(SRC
    yogini.c
    work_UMWAIT.c
    work_TPAUSE.c
    work_RDTSC.c
    work_PAUSE.c
    work_memcpy.c
    work_MEM.c
    # The source files here are not needed for now
    # run_common.c
    # work_GETCPU.c
)

add_compile_definitions(CMAKE_FLAG=0)

# Get target CPU information
execute_process(
    COMMAND ${CMAKE_C_COMPILER} -march=native -Q --help=target
    OUTPUT_VARIABLE TARGET_CPU
    ERROR_QUIET
)

# Print information about the target CPU
# message(STATUS "Target CPU: ${TARGET_CPU}")

# Function to check for CPU feature and add source files and compile definition if the feature is enabled
function(check_cpu_feature)
    # Separate the feature, compile definition, and source files
    set(options "")
    set(oneValueArgs FEATURE COMPILE_DEFINITION)
    set(multiValueArgs SOURCES)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    string(REGEX MATCH "${ARG_FEATURE}[ \t]+\\[enabled\\]" feature_enabled_match "${TARGET_CPU}")
    if(feature_enabled_match)
        message(STATUS "${ARG_FEATURE} is enabled")
        add_compile_definitions(${ARG_COMPILE_DEFINITION}=1)
        # Append all source files to the list in the parent scope
        set(SRC_LIST ${SRC})
        foreach(source_file IN LISTS ARG_SOURCES)
            list(APPEND SRC_LIST ${source_file})
        endforeach()
        set(SRC ${SRC_LIST} PARENT_SCOPE)
    else()
        message(STATUS "${ARG_FEATURE} is disabled or not found")
    endif()
endfunction()

# Check CPU feature and add source files and compile definition
check_cpu_feature(FEATURE "-mamx-tile" COMPILE_DEFINITION "MAMX_ENABLED" SOURCES "work_AMX.c")
check_cpu_feature(FEATURE "-mavx" COMPILE_DEFINITION "MAVX_ENABLED" SOURCES "work_AVX.c")
check_cpu_feature(FEATURE "-mavx2" COMPILE_DEFINITION "MAVX2_ENABLED" SOURCES "work_AVX2.c" "work_DOTPROD.c")
check_cpu_feature(FEATURE "-mavx512f" COMPILE_DEFINITION "MAVX512F_ENABLED" SOURCES "work_AVX512.c")
check_cpu_feature(FEATURE "-msse" COMPILE_DEFINITION "MSSE_ENABLED" SOURCES "work_SSE.c")
check_cpu_feature(FEATURE "-mvnni" COMPILE_DEFINITION "MVNNI_ENABLED" SOURCES "work_VNNI.c")
check_cpu_feature(FEATURE "-mvnni512" COMPILE_DEFINITION "MVNNSI512_ENABLED" SOURCES "work_VNNI512.c")

# Print the contents of the SRC
message(STATUS "SRC contains the following files: ${SRC}")

# Set the compiler flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -D_FORTIFY_SOURCE=2 -Wall -O3")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -march=native")
# Add the -g flags, if use gdb for debugging
# set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -g")

# Add the executable
add_executable(yogini ${SRC})

# Link libraries
target_link_libraries(yogini m pthread)

# Install the program
install(TARGETS yogini DESTINATION ${CMAKE_INSTALL_PREFIX})