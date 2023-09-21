#!/bin/bash
case=("msr" "cr" "cpuid" "all")
ver=("1.0" "1.5" "")

# store test results to a specified folder
script_dir=$(dirname "$0")
result_dir="$script_dir/result"

if [ ! -d "$result_dir" ]; then
  mkdir "$result_dir"
fi

for c in "${case[@]}"; do
	for v in "${ver[@]}"; do
		echo $c $v > /sys/kernel/debug/tdx/tdx-tests
		OUTPUT="${c}_${v}"
		echo "CMD:${c} ${v}"

		cat "/sys/kernel/debug/tdx/tdx-tests" > "${result_dir}/$OUTPUT"
	done
done
