# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (c) 2024 Intel Corporation.
# Haoliang Zhu <haoliang.zhu@intel.com>

cmake_minimum_required(VERSION 3.12)
project(cet)

# Set the build output directory
set(BUILD_OUTPUT ${CMAKE_CURRENT_BINARY_DIR})

# Set the installation prefix 
set(CMAKE_INSTALL_PREFIX /usr/local/bin)

# Set the flags
set(CETFLAGS -O0 -fcf-protection=full -mshstk -fno-stack-check -fno-stack-protector -no-pie)
set(SHSTKFLAGS -O0 -mshstk -fcf-protection=return -fno-stack-check -fno-stack-protector -no-pie)
set(NOCETFLAGS -O0 -fcf-protection=none -mshstk -fno-stack-check -fno-stack-protector -no-pie)

# Get the gcc version. If the version is greater than or equal to 8, build the CET programs.
execute_process(COMMAND gcc --version OUTPUT_VARIABLE GCC_VERSION)
string(REGEX MATCH "([0-9]+)\\." GCC_VER_MAJOR ${GCC_VERSION})
if(GCC_VER_MAJOR GREATER_EQUAL 8)
    set(BIN shstk_alloc test_shadow_stack quick_test wrss shstk_huge_page 
        shstk_unlock_test shstk_cp cet_app glibc_shstk_test shstk_cpu shstk_cpu_legacy)
else()
    message(WARNING "GCC version is less than 8, skipping build cet.")
    return()
endif()

# Set the kernel source path and driver path
set(KER_SRC "/lib/modules/${CMAKE_SYSTEM_VERSION}/build")
set(DRIVER_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cet_driver")

if(EXISTS ${KER_SRC})
    list(APPEND BIN cet_ioctl)
else()
    message(WARNING "Kernel source path not found, skipping build cet_ioctl.")
endif()

# Add the executable
foreach(target ${BIN})
    if(${target} STREQUAL "cet_ioctl")
        # cet_ioctl need to be built in the kernel source directory
        add_custom_target(${target}
            COMMAND ${CMAKE_MAKE_PROGRAM} -C ${KER_SRC} M=${DRIVER_PATH} modules
            WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        )
    elseif(${target} STREQUAL "cet_app")
        # cet_app need to be built with the cet_driver
        add_executable(${target} cet_driver/cet_app.c)
        target_include_directories(${target} PRIVATE cet_driver)
    else()
        add_executable(${target} ${target}.c)
        if(${target} MATCHES "quick_test|shstk_huge_page|glibc_shstk_test")
            target_compile_options(${target} PRIVATE ${SHSTKFLAGS})
        else()
            target_compile_options(${target} PRIVATE ${NOCETFLAGS})
        endif()
        if(${target} STREQUAL "test_shadow_stack")
            target_link_libraries(${target} PRIVATE pthread)
        endif()
    endif()
endforeach()

# Install the program
install(TARGETS ${BIN} DESTINATION ${CMAKE_INSTALL_PREFIX})
