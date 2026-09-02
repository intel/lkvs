#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation
# @Desc  Performance tests for cache-aware scheduler (SCHED_CACHE /
#         llc_balancing), each comparing feature ON vs feature OFF:
#           perf_llc_miss  - perf hardware counters: LLC-load-miss rate and IPC
#                            on a true cache-line-sharing workload.
#           perf_hackbench - native hackbench wall-clock time (PASS when ON is
#                            faster than OFF).

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env
source ./cache_aware_common.sh

WORKER_PID=""

# LLC size in KiB from cache/index3/size (handles K / M suffix). Echoes 0 if unknown.
_llc_size_kib() {
    local raw
    raw=$(cat /sys/devices/system/cpu/cpu0/cache/index3/size 2>/dev/null)
    case "$raw" in
        *K|*k) echo "${raw%[Kk]}" ;;
        *M|*m) echo $(( ${raw%[Mm]} * 1024 )) ;;
        ''|*[!0-9]*) echo 0 ;;
        *) echo "$raw" ;;
    esac
}

# Are perf and the LLC load counters usable?
_perf_ok() {
    command -v perf >/dev/null 2>&1 || return 1
    local out
    out=$(perf stat -e LLC-loads,LLC-load-misses -- sleep 0.2 2>&1)
    echo "$out" | grep -q "LLC-load" || return 1
    echo "$out" | grep -qi "not supported" && return 1
    return 0
}

# Scatter then wait for <pid> to converge onto one LLC. Returns 0 if converged
# for <consec> consecutive samples within <timeout>s, else 1.
_converge_wait() {
    local pid=$1 timeout=$2 consec_needed=${3:-3}
    local consec=0 elapsed=0
    scatter_workers "$pid"
    while [ "$elapsed" -lt "$timeout" ]; do
        sleep 1; elapsed=$(( elapsed + 1 ))
        kill -0 "$pid" 2>/dev/null || return 1
        if check_convergence "$pid" >/dev/null 2>&1; then
            consec=$(( consec + 1 ))
            [ "$consec" -ge "$consec_needed" ] && return 0
        else
            consec=0
        fi
    done
    return 1
}

# Sample a running <pid> for <window>s. Echoes "<missrate_pct> <ipc>" on stdout
# and a human-readable line on stderr.
_perf_measure() {
    local pid=$1 window=$2 out
    out=$(perf stat -e LLC-loads,LLC-load-misses,cycles,instructions \
            -p "$pid" -- sleep "$window" 2>&1)
    local loads misses cycles insns
    loads=$(echo "$out"  | awk '/LLC-loads/       { gsub(",","",$1); print $1; exit }')
    misses=$(echo "$out" | awk '/LLC-load-misses/ { gsub(",","",$1); print $1; exit }')
    cycles=$(echo "$out" | awk '/ cycles/         { gsub(",","",$1); print $1; exit }')
    insns=$(echo "$out"  | awk '/ instructions/   { gsub(",","",$1); print $1; exit }')
    local missrate ipc
    missrate=$(awk -v m="${misses:-0}" -v l="${loads:-0}" \
        'BEGIN{ if (l>0) printf "%.3f", 100*m/l; else print "0" }')
    ipc=$(awk -v i="${insns:-0}" -v c="${cycles:-0}" \
        'BEGIN{ if (c>0) printf "%.3f", i/c; else print "0" }')
    echo "    [perf pid=$pid] LLC-loads=${loads:-0} LLC-load-misses=${misses:-0} miss=${missrate}% IPC=$ipc" >&2
    echo "$missrate $ipc"
}

# ---------------------------------------------------------------------------
# PERF1: Measure LLC miss rate and IPC — feature ON vs feature OFF.
# ---------------------------------------------------------------------------
run_perf_llc_miss() {
    local WINDOW=${PERF_WINDOW:-15}
    local CONV_TIMEOUT=${CONV_TIMEOUT:-30}
    local WS_PCT=${WS_PCT:-60}
    local SCATTER_SETTLE=${SCATTER_SETTLE:-2}

    echo "=== LLC miss rate — feature ON vs feature OFF ==="

    if ! _perf_ok; then
        skip_test "perf_llc_miss needs perf with working LLC-loads/LLC-load-misses counters; perf is missing or the counters are not supported/accessible on this CPU (check perf_event_paranoid)"
    fi

    local llc_kib ws_kib
    llc_kib=$(_llc_size_kib)
    if [ "${llc_kib:-0}" -le 0 ]; then
        ws_kib=${WS_KIB:-8192}
        echo "[WARN] could not read LLC size; using working set = ${ws_kib} KiB"
    else
        ws_kib=$(( llc_kib * WS_PCT / 100 ))
        echo "[INFO] LLC size ${llc_kib} KiB; shared working set = ${ws_kib} KiB (${WS_PCT}% of one LLC)"
    fi

    echo "--- Phase ON (enabled=1) ---"
    echo 1 > "$LLC_DBG/enabled" 2>/dev/null
    "$SCRIPT_DIR/test_llc_share" "$ws_kib" 0 & WORKER_PID=$!
    sleep 0.5
    if ! kill -0 "$WORKER_PID" 2>/dev/null; then
        echo "perf_llc_miss: worker failed to start"; return 1
    fi
    _converge_wait "$WORKER_PID" "$CONV_TIMEOUT" 3 || echo "  [WARN] did not fully converge; measuring anyway"
    echo "  placement: $(get_proc_llc_dist_workers $WORKER_PID)"
    local on_missrate on_ipc
    read -r on_missrate on_ipc < <(_perf_measure "$WORKER_PID" "$WINDOW")
    kill "$WORKER_PID" 2>/dev/null; wait "$WORKER_PID" 2>/dev/null; WORKER_PID=""

    echo "--- Phase OFF (enabled=0) ---"
    echo 0 > "$LLC_DBG/enabled" 2>/dev/null
    "$SCRIPT_DIR/test_llc_share" "$ws_kib" 0 & WORKER_PID=$!
    sleep 0.5
    if ! kill -0 "$WORKER_PID" 2>/dev/null; then
        echo "perf_llc_miss: worker failed to start"; return 1
    fi
    scatter_workers "$WORKER_PID"
    sleep "$SCATTER_SETTLE"
    local nllc
    nllc=$(get_proc_llc_dist_workers "$WORKER_PID" | tr ' ' '\n' | grep -c '^LLC')
    echo "  placement: $(get_proc_llc_dist_workers $WORKER_PID)"
    local off_missrate off_ipc
    read -r off_missrate off_ipc < <(_perf_measure "$WORKER_PID" "$WINDOW")
    kill "$WORKER_PID" 2>/dev/null; wait "$WORKER_PID" 2>/dev/null; WORKER_PID=""

    echo 1 > "$LLC_DBG/enabled" 2>/dev/null

    if awk -v a="$on_missrate" -v b="$off_missrate" 'BEGIN{ exit !(a==0 && b==0) }'; then
        skip_test "perf_llc_miss: LLC counters read zero in both phases; the counters are not actually counting on this host (check perf_event_paranoid / virtualization)"
    fi

    local miss_ok control_ok improvement ipc_gain
    miss_ok=$(awk -v on="$on_missrate" -v off="$off_missrate" 'BEGIN{ print (on < off) ? 1 : 0 }')
    control_ok=$([ "${nllc:-1}" -gt 1 ] && echo 1 || echo 0)
    improvement=$(awk -v on="$on_missrate" -v off="$off_missrate" \
        'BEGIN{ if (off>0) printf "%.1f", 100*(off-on)/off; else print "0" }')
    ipc_gain=$(awk -v on="$on_ipc" -v off="$off_ipc" \
        'BEGIN{ if (off>0) printf "%.1f", 100*(on-off)/off; else print "0" }')

    # The OFF phase is only a valid control if its workers actually landed on
    # more than one LLC; otherwise the ON-vs-OFF comparison is meaningless.
    if [ "$control_ok" -ne 1 ]; then
        echo "  [ERROR] OFF phase did not scatter: workers stayed on ${nllc} LLC;" \
             "the ON-vs-OFF comparison is invalid"
    fi

    local result="FAIL"
    [ "$miss_ok" -eq 1 ] && [ "$control_ok" -eq 1 ] && result="PASS"

    echo ""
    echo "----------------------------------------"
    echo "perf_llc_miss result: $result"
    echo "  LLC-load-miss rate   ON=${on_missrate}%   OFF=${off_missrate}%"
    echo "  miss-rate reduction (ON vs OFF)                      : ${improvement}%   (ON<OFF => $([ $miss_ok -eq 1 ] && echo yes || echo no))"
    echo "  Instructions Per Cycle (IPC)  ON=${on_ipc}   OFF=${off_ipc}   (IPC gain ${ipc_gain}%)"
    echo "----------------------------------------"
    [ "$result" = "PASS" ]
}

# Echo mean hackbench Time (secs) over <runs>; returns 1 if nothing parseable.
# args: <runs> <groups> <fds> <loops> <thread(1/0)>
_bench_mean() {
    local runs=$1 groups=$2 fds=$3 loops=$4 thread=$5
    local mode="--process"; [ "$thread" = "1" ] && mode="--threads"
    local sum=0 n=0 t i
    for i in $(seq 1 "$runs"); do
        t=$(hackbench -g "$groups" -f "$fds" -l "$loops" -s 100 --pipe $mode 2>&1 \
                | awk '/Time:/ { print $2; exit }')
        if [ -z "$t" ]; then
            echo "    run $i/$runs: (no time parsed)" >&2
            continue
        fi
        sum=$(awk -v s="$sum" -v t="$t" 'BEGIN{ print s + t }')
        n=$(( n + 1 ))
        echo "    run $i/$runs: ${t}s" >&2
    done
    [ "$n" -eq 0 ] && { echo ""; return 1; }
    awk -v s="$sum" -v n="$n" 'BEGIN{ printf "%.3f", s / n }'
}

# ---------------------------------------------------------------------------
# PERF2: hackbench Time — feature ON vs feature OFF (PASS when ON is faster).
# ---------------------------------------------------------------------------
run_perf_hackbench() {
    local RUNS=${HB_RUNS:-5}
    local NGROUPS=${HB_GROUPS:-1}
    local FDS=${HB_FDS:-2}
    local LOOPS=${HB_LOOPS:-3000000}
    local THREAD=${HB_THREAD:-1}

    echo "=== hackbench throughput — feature ON vs feature OFF ==="

    # Native hackbench is required: it needs --pipe and -f, which keep the task
    # count small enough to fit one LLC ('perf bench sched messaging' can't).
    if ! command -v hackbench >/dev/null 2>&1; then
        skip_test "perf_hackbench needs the native 'hackbench' binary (it uses --pipe and -f, which 'perf bench sched messaging' does not provide); install rt-tests hackbench and retry"
    fi

    local modestr="process"; [ "$THREAD" = "1" ] && modestr="threads"
    echo "  backend: hackbench (-g $NGROUPS -f $FDS -l $LOOPS -s 100 --pipe, $modestr)  x${RUNS} runs/phase"
    echo "  task count = 2 x fds x groups = $(( 2 * FDS * NGROUPS )) (aim: <= one LLC = $LLC_SIZE CPUs)"

    echo "--- Phase ON (enabled=1) ---"
    echo 1 > "$LLC_DBG/enabled" 2>/dev/null
    local on_mean
    on_mean=$(_bench_mean "$RUNS" "$NGROUPS" "$FDS" "$LOOPS" "$THREAD") || \
        block_test "perf_hackbench: no parseable ON samples from hackbench (tooling malfunction, not a feature verdict)"
    echo "  ON  mean time: ${on_mean}s"

    echo "--- Phase OFF (enabled=0) ---"
    echo 0 > "$LLC_DBG/enabled" 2>/dev/null
    local off_mean
    off_mean=$(_bench_mean "$RUNS" "$NGROUPS" "$FDS" "$LOOPS" "$THREAD") || \
        block_test "perf_hackbench: no parseable OFF samples from hackbench (tooling malfunction, not a feature verdict)"
    echo "  OFF mean time: ${off_mean}s"

    echo 1 > "$LLC_DBG/enabled" 2>/dev/null

    # Advantage = feature ON faster than OFF => (off-on)/off > 0.
    local improvement faster
    improvement=$(awk -v on="$on_mean" -v off="$off_mean" \
        'BEGIN{ if (off>0) printf "%.1f", 100*(off-on)/off; else print "0" }')
    faster=$(awk -v on="$on_mean" -v off="$off_mean" 'BEGIN{ print (on < off) ? 1 : 0 }')

    local result="FAIL"
    [ "$faster" -eq 1 ] && result="PASS"

    echo ""
    echo "----------------------------------------"
    echo "perf_hackbench result: $result"
    echo "  mean wall-clock time  ON=${on_mean}s   OFF=${off_mean}s"
    echo "  speedup (ON vs OFF)                                  : ${improvement}%   (ON<OFF => $([ $faster -eq 1 ] && echo yes || echo no))"
    echo "  (a slower ON usually means the task count exceeded one LLC; keep it <= $LLC_SIZE)"
    echo "----------------------------------------"
    [ "$result" = "PASS" ]
}

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------
usage() {
    echo "Usage: $0 -t <test>"
    echo ""
    echo "Available tests:"
    echo "  perf_llc_miss  LLC-load-miss rate, feature ON vs feature OFF"
    echo "  perf_hackbench native hackbench Time, feature ON vs feature OFF (needs hackbench)"
    echo ""
    echo "Environment overrides:"
    echo "  PERF_WINDOW=15    perf sampling window per phase (secs)"
    echo "  CONV_TIMEOUT=30   ON phase: max time to wait for convergence (secs)"
    echo "  WS_PCT=60         shared working set as a percent of one LLC's size"
    echo "  WS_KIB=8192       explicit working set (KiB) if LLC size can't be read"
    echo "  SCATTER_SETTLE=2  OFF phase: settle time after forcing the scatter (secs)"
    echo "  HB_RUNS=5         perf_hackbench: hackbench invocations per phase"
    echo "  HB_GROUPS=1       perf_hackbench: hackbench task groups (-g)"
    echo "  HB_FDS=2          perf_hackbench: hackbench file descriptors per group (-f)"
    echo "  HB_LOOPS=3000000  perf_hackbench: hackbench message loops per run"
    exit 1
}

TEST=""

while getopts "t:" opt; do
    case $opt in
        t) TEST="$OPTARG" ;;
        *) usage ;;
    esac
done

[ -z "$TEST" ] && usage

if pgrep -x test_llc_share > /dev/null 2>&1; then
    test_print_trc "Killing stale test_llc_share processes..."
    pkill -x test_llc_share 2>/dev/null
    sleep 0.5
fi

if pgrep -x hackbench > /dev/null 2>&1; then
    test_print_trc "Killing stale hackbench processes..."
    pkill -x hackbench 2>/dev/null
    sleep 0.5
fi

save_llc_params

trap "restore_llc_params
      [ -n \"\$WORKER_PID\" ] && kill \$WORKER_PID 2>/dev/null
      pkill -x test_llc_share 2>/dev/null
      pkill -x hackbench 2>/dev/null
      pkill -x yes 2>/dev/null" EXIT INT TERM

echo 1 > /sys/kernel/debug/sched/llc_balancing/enabled
echo ""

case "$TEST" in
    perf_llc_miss)  run_perf_llc_miss ;;
    perf_hackbench) run_perf_hackbench ;;
    *) echo "Unknown test: $TEST"; usage ;;
esac
