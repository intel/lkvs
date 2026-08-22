#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation
# @Desc  Shared topology detection and helper functions for cache-aware
#         scheduler (SCHED_CACHE / llc_balancing) validation tests.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Topology detection — run once at startup, used by all test functions
# ---------------------------------------------------------------------------
# LLC_IDS    : space-separated list of unique LLC ids (e.g. "0 1 2 3")
# LLC_COUNT  : number of LLCs
# LLC_SIZE   : number of CPUs per LLC (assumes uniform)
# LLC_CPUS_<id> : comma-separated CPU list for each LLC
# ---------------------------------------------------------------------------
LLC_IDS=$(for cpu in $(seq 0 $(($(nproc) - 1))); do
    cat /sys/devices/system/cpu/cpu${cpu}/cache/index3/id
done | sort -un)
LLC_COUNT=$(echo "$LLC_IDS" | wc -w)
for _llc_id in $LLC_IDS; do
    eval "LLC_CPUS_${_llc_id}=$(for cpu in $(seq 0 $(($(nproc) - 1))); do
        [ "$(cat /sys/devices/system/cpu/cpu${cpu}/cache/index3/id)" = "$_llc_id" ] && echo $cpu
    done | tr '\n' ',' | sed 's/,$//')"
done
LLC_SIZE=$(echo "$LLC_CPUS_0" | tr ',' '\n' | wc -l)
# DEFAULT_NTHREADS: 70% of LLC_SIZE — below the invalid_llc_nr() guard threshold
# (which fires at ~80% of LLC_SIZE) on any machine, with margin to spare.
DEFAULT_NTHREADS=$(( LLC_SIZE * 7 / 10 ))
[ "$DEFAULT_NTHREADS" -lt 4 ] && DEFAULT_NTHREADS=4
test_print_trc "Detected $LLC_COUNT LLCs, $LLC_SIZE CPUs each (DEFAULT_NTHREADS=$DEFAULT_NTHREADS)"

# Rebuild test_llc_agg with -DNTHREADS=N; called at source-time with DEFAULT_NTHREADS
# and by individual tests that need a different count. Falls back to prebuilt binary if
# gcc is unavailable.
build_llc_agg() {
    local _n=${1:-$DEFAULT_NTHREADS}
    if gcc -O2 -pthread -DNTHREADS="$_n" \
        -o "$SCRIPT_DIR/test_llc_agg" "$SCRIPT_DIR/test_llc_agg.c"; then
        return 0
    fi
    if [ -x "$SCRIPT_DIR/test_llc_agg" ]; then
        test_print_wrg "gcc build of test_llc_agg (NTHREADS=$_n) failed; using existing binary"
        return 0
    fi
    test_print_err "cannot build test_llc_agg (NTHREADS=$_n) and no prebuilt binary present"
    return 1
}

build_llc_agg "$DEFAULT_NTHREADS" && \
    test_print_trc "Built test_llc_agg (NTHREADS=$DEFAULT_NTHREADS)"

# Build test_llc_share with -DNTHREADS=N; same threshold reasoning as build_llc_agg.
build_llc_share() {
    local _n=${1:-$DEFAULT_NTHREADS}
    if gcc -O2 -pthread -DNTHREADS="$_n" \
        -o "$SCRIPT_DIR/test_llc_share" "$SCRIPT_DIR/test_llc_share.c"; then
        return 0
    fi
    if [ -x "$SCRIPT_DIR/test_llc_share" ]; then
        test_print_wrg "gcc build of test_llc_share (NTHREADS=$_n) failed; using existing binary"
        return 0
    fi
    test_print_err "cannot build test_llc_share (NTHREADS=$_n) and no prebuilt binary present"
    return 1
}

build_llc_share "$DEFAULT_NTHREADS" && \
    test_print_trc "Built test_llc_share (NTHREADS=$DEFAULT_NTHREADS)"

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------
SAMPLE_INTERVAL=${SAMPLE_INTERVAL:-1}
PASS_THRESHOLD=${PASS_THRESHOLD:-2}

# ---------------------------------------------------------------------------
# llc_balancing parameter save/restore
# ---------------------------------------------------------------------------
LLC_PARAMS="enabled aggr_tolerance epoch_period epoch_affinity_timeout overaggr_pct imb_pct"
LLC_DBG=/sys/kernel/debug/sched/llc_balancing

save_llc_params() {
    for _p in $LLC_PARAMS; do
        if [ -r "$LLC_DBG/$_p" ]; then
            eval "LLC_ORIG_${_p}=\$(cat $LLC_DBG/$_p)"
        fi
    done
    test_print_trc "baseline llc_balancing: $(for _p in $LLC_PARAMS; do
        eval "printf '%s=%s ' \"$_p\" \"\$LLC_ORIG_${_p}\""
    done)"
}

restore_llc_params() {
    for _p in $LLC_PARAMS; do
        eval "_v=\$LLC_ORIG_${_p}"
        [ -n "$_v" ] && [ -w "$LLC_DBG/$_p" ] && echo "$_v" > "$LLC_DBG/$_p"
    done
    test_print_trc "llc_balancing baseline restored"
}

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

# Get LLC ID for a given CPU.
get_llc_id() {
    local cpu=$1
    cat /sys/devices/system/cpu/cpu${cpu}/cache/index3/id
}

# Return the NUMA node id owning a given LLC (node of its first CPU).
get_llc_node() {
    local llc=$1
    eval "local _cpus=\$LLC_CPUS_${llc}"
    # shellcheck disable=SC2154
    local _first=${_cpus%%,*}
    local _nd
    _nd=$(ls -d /sys/devices/system/cpu/cpu${_first}/node* 2>/dev/null | head -1)
    [ -n "$_nd" ] && basename "$_nd" | sed 's/node//'
}

# Get LLC distribution for all threads of a process.
get_proc_llc_dist() {
    local pid=$1
    for cpu in $(cat /proc/$pid/task/*/stat 2>/dev/null | awk '{print $39}'); do
        get_llc_id $cpu
    done | sort | uniq -c | sort -rn | awk '{printf "LLC%s:%s ", $2, $1}'
    echo
}

# Get LLC distribution for worker threads only (state=R, excludes main thread).
get_proc_llc_dist_workers() {
    local pid=$1
    local main_tid=$pid
    # shellcheck disable=SC2231
    for stat in /proc/$pid/task/*/stat; do
        read -r fields < "$stat" 2>/dev/null || continue
        tid=$(echo "$fields"   | awk '{print $1}')
        state=$(echo "$fields" | awk '{print $3}')
        cpu=$(echo "$fields"   | awk '{print $39}')
        [ "$tid" = "$main_tid" ] && continue
        [ "$state" = "R" ] && get_llc_id $cpu
    done | sort | uniq -c | sort -rn | awk '{printf "LLC%s:%s ", $2, $1}'
    echo
}

# Get the dominant LLC id for a process (LLC with most running workers).
get_top_llc() {
    get_proc_llc_dist_workers $1 | tr ' ' '\n' | grep "^LLC" | head -1 | cut -d: -f1 | sed 's/LLC//'
}

# Check convergence: pass if all active worker threads are on a single LLC.
check_convergence() {
    local pid=$1
    local total unique_llcs

    # shellcheck disable=SC2231
    total=$(for stat in /proc/$pid/task/*/stat; do
        read -r fields < "$stat" 2>/dev/null || continue
        tid=$(echo "$fields"   | awk '{print $1}')
        state=$(echo "$fields" | awk '{print $3}')
        [ "$tid" = "$pid" ] && continue
        [ "$state" = "R" ] && echo "$tid"
    done | wc -l)

    if [ "$total" -eq 0 ]; then
        echo "  [WARN] no running worker threads found for PID $pid"
        return 1
    fi

    unique_llcs=$(get_proc_llc_dist_workers $pid | tr ' ' '\n' | grep -c "^LLC")
    unique_llcs=${unique_llcs:-0}
    echo "  worker_threads=$total  llcs_used=$unique_llcs"
    [ "$unique_llcs" -eq 1 ]
}

# Scatter all worker threads of PID round-robin across all LLCs, then release affinity.
scatter_workers() {
    local pid=$1
    local tids
    tids=$(ls /proc/$pid/task/ | grep -v "^${pid}$")
    local count=0
    local llc_arr=($LLC_IDS)
    for tid in $tids; do
        local llc_id=${llc_arr[$((count % LLC_COUNT))]}
        eval "local cpus=\$LLC_CPUS_${llc_id}"
        # shellcheck disable=SC2154
        taskset -p -c "$cpus" $tid > /dev/null 2>&1
        count=$(( count + 1 ))
    done
    sleep 0.05
    # shellcheck disable=SC2045
    for tid in $(ls /proc/$pid/task/); do
        taskset -p -c 0-$(($(nproc) - 1)) $tid > /dev/null 2>&1
    done
}

# Pin the first N worker threads of PID to LLC; store remaining tids in FREE_TIDS array.
pin_n_workers() {
    local pid=$1 n=$2 llc=$3
    eval "local _cpus=\$LLC_CPUS_${llc}"
    local tids
    tids=$(ls /proc/$pid/task/ | grep -v "^${pid}$")
    local count=0
    FREE_TIDS=()
    for tid in $tids; do
        if [ $count -lt $n ]; then
            taskset -p -c "$_cpus" $tid > /dev/null 2>&1
        else
            FREE_TIDS+=($tid)
        fi
        count=$(( count + 1 ))
    done
}

# Scatter workers across all LLCs, release affinity, poll until convergence.
# Returns 0 on converge, 1 on timeout.
launch_and_converge() {
    local _pid_var=$1
    local _llc_var=$2
    local _monitor_secs=$3
    local _interval=$4
    local _threshold=$5

    "$SCRIPT_DIR/test_llc_agg" &
    local _pid=$!
    eval "$_pid_var=$_pid"
    echo "Started test_llc_agg PID=$_pid"
    sleep 0.2

    local _tids
    _tids=$(ls /proc/$_pid/task/ | grep -v "^${_pid}$")
    local _total
    _total=$(echo "$_tids" | wc -w)
    local _count=0
    local _llc_arr=($LLC_IDS)
    echo "Scattering $_total workers round-robin across $LLC_COUNT LLCs..."
    for _tid in $_tids; do
        local _llc_id=${_llc_arr[$((_count % LLC_COUNT))]}
        eval "local _cpus=\$LLC_CPUS_${_llc_id}"
        taskset -p -c "$_cpus" $_tid > /dev/null 2>&1
        _count=$(( _count + 1 ))
    done

    sleep 0.05
    echo "t=0s (after scatter, pre-convergence):"
    echo "    all:     $(get_proc_llc_dist $_pid)"
    echo "    workers: $(get_proc_llc_dist_workers $_pid)"
    echo ""
    echo "Removing CPU affinity restrictions so scheduler can converge..."
    # shellcheck disable=SC2045
    for _tid in $(ls /proc/$_pid/task/); do
        taskset -p -c 0-$(($(nproc) - 1)) $_tid > /dev/null 2>&1
    done
    echo ""

    local _consecutive=0
    local _elapsed=0

    while [ "$(echo "$_elapsed < $_monitor_secs" | bc)" -eq 1 ]; do
        sleep $_interval
        _elapsed=$(echo "$_elapsed + $_interval" | bc)

        if ! kill -0 $_pid 2>/dev/null; then
            echo "  [ERROR] process $_pid exited unexpectedly"
            return 1
        fi

        echo "t=${_elapsed}s  workers: $(get_proc_llc_dist_workers $_pid)"
        if check_convergence $_pid; then
            _consecutive=$(( _consecutive + 1 ))
            echo "  => converged ($_consecutive/$_threshold consecutive)"
            if [ $_consecutive -ge $_threshold ]; then
                local _converged_llc
                _converged_llc=$(get_top_llc $_pid)
                eval "$_llc_var=$_converged_llc"
                echo "  => converged on LLC${_converged_llc}"
                return 0
            fi
        else
            _consecutive=0
        fi
    done

    echo "[FAIL] process did not converge in ${_monitor_secs}s"
    return 1
}
