# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (c) 2024 Intel Corporation.
# Haoliang Zhu <haoliang.zhu@intel.com>

cmake_minimum_required(VERSION 3.12)
project(lkvs)

set(SUBFOLDER amx/tmul avx512vbmi cet cmpccxadd pt 
              splitlock telemetry th tools/cpuid_check 
	      tools/pcie umip workload-xsave xsave)

foreach(subfolder ${SUBFOLDER})
    message(STATUS "Start build ${subfolder}.")
    add_subdirectory(${subfolder})
    message(STATUS "Finish build ${subfolder}.")
endforeach()
