# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (c) 2022 Intel Corporation.
# Yi Sun <yi.sun@intel.com>
# Dongcheng Yan <dongcheng.yan@intel.com>

#!/bin/bash
option=""
result=""
repeat=""
num=$#

# store test results to a specified folder
script_dir=$(dirname "$0")
result_dir="$script_dir/result"

if [ ! -d "$result_dir" ]; then
  mkdir "$result_dir"
fi

# mode1: test workloads in specific break_reason
test_single () {
  echo "trace-cmd record -e x86_fpu -F ./yogini -b $break_reason -r $repeat $option"
  trace-cmd record -e x86_fpu -F ./yogini -b $break_reason -r $repeat $option
  if [ $? -ne 0 ]; then
    echo "Failed to execute trace-cmd record."
    exit 1
  fi
  trace-cmd report > "${result_dir}/${result}${break_reason}"
}

# mode2: test workloads in all break_reason
test_all () {
for ((i=1; i<=5; i++))
do
  break_reason=$i
  test_single
done
}

usage() {
  GREEN='\033[0;32m'
  NC='\033[0m'
  echo -e "${GREEN}Usage:${NC}"
  echo "first param:   break_reason"
  echo "second param:  repeat_cnt"
  echo "remain params: workload"
  echo -e "${GREEN}Example:${NC}"
  echo "$0 2 100 AVX MEM VNNI"
  echo "$0 -1 100 AVX MEM VNNI"
  echo -e "${GREEN}You can test all break_reason if first param is -1.${NC} "
}

# main func
if [ $num -lt 3 ]; then
  usage
else
  break_reason=$1
  repeat=$2
  for ((i=3; i<=$#; i++))
  do
  # add workload cmd
    arg="${!i}"
    option+="-w $arg "
    result+="${arg}_"
  done

  if [ "$1" == "-1" ]; then
    test_all "$@"
  else
    test_single "$@"
  fi
fi
