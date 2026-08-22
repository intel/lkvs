#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Intel Corporation
# @Desc  Functional tests for cache-aware scheduler (SCHED_CACHE / llc_balancing).
#         Covers: LLC convergence, re-selection, two-process separation,
#         preferred-LLC switch threshold, and pin-steal locality protection.

cd "$(dirname "$0")" 2>/dev/null || exit 1
source ../.env
source ./cache_aware_common.sh

# ---------------------------------------------------------------------------
# F1: Verify workers converge onto a single LLC; confirm spread when disabled.
# ---------------------------------------------------------------------------
run_test_llc_agg() {
    local MONITOR_SECS=${MONITOR_SECS:-60}
    local PID=""

    echo "=== Phase 1: LLC aggregation ==="
    local converged_llc=""
    local result="FAIL"

    if launch_and_converge PID converged_llc "$MONITOR_SECS" "$SAMPLE_INTERVAL" "$PASS_THRESHOLD"; then
        result="PASS"
    fi

    echo ""
    echo "----------------------------------------"
    echo "test_llc_agg phase 1 result: $result"
    echo "----------------------------------------"

    kill $PID 2>/dev/null
    wait $PID 2>/dev/null

    echo ""
    echo "Phase 2: disabling llc_balancing (enabled=0)..."
    echo 0 > /sys/kernel/debug/sched/llc_balancing/enabled

    "$SCRIPT_DIR/test_llc_agg" &
    PID=$!
    echo "Started test_llc_agg PID=$PID"
    sleep 0.2

    echo "Scattering workers and releasing affinity..."
    scatter_workers $PID
    echo "t=0s  workers: $(get_proc_llc_dist_workers $PID)"
    echo ""

    echo "Monitoring for ${MONITOR_SECS}s (sample every ${SAMPLE_INTERVAL}s)..."
    echo ""

    elapsed=0
    local phase2_result="PASS"

    while [ "$(echo "$elapsed < $MONITOR_SECS" | bc)" -eq 1 ]; do
        sleep $SAMPLE_INTERVAL
        elapsed=$(echo "$elapsed + $SAMPLE_INTERVAL" | bc)

        if ! kill -0 $PID 2>/dev/null; then
            echo "  [ERROR] process $PID exited unexpectedly"
            phase2_result="ERROR"
            break
        fi

        echo "t=${elapsed}s  LLC distribution:"
        echo "    all:     $(get_proc_llc_dist $PID | tr '\n' ' ')"
        echo "    workers: $(get_proc_llc_dist_workers $PID | tr '\n' ' ')"

        if check_convergence $PID; then
            echo "  => FAIL (aggregation occurred despite llc_balancing=0)"
            phase2_result="FAIL"
            break
        else
            echo "  => spread (still no aggregation at t=${elapsed}s)"
        fi
        echo ""
    done

    echo ""
    echo "----------------------------------------"
    echo "test_llc_agg phase 2 result: $phase2_result"
    echo "(PASS = threads stayed spread, aggregation correctly suppressed)"
    echo "----------------------------------------"

    echo 1 > /sys/kernel/debug/sched/llc_balancing/enabled

    kill $PID 2>/dev/null
    wait $PID 2>/dev/null

    [ "$result" = "PASS" ] && [ "$phase2_result" = "PASS" ]
}

# ---------------------------------------------------------------------------
# F2: Verify process re-converges onto a new LLC when preferred one is saturated.
# ---------------------------------------------------------------------------
run_test_llc_reselect() {
    local MONITOR_SECS=${MONITOR_SECS:-60}
    local SATURATION_SECS=20
    local PID="" STRESS_PID=""

    echo "=== Phase 1: waiting for LLC convergence ==="
    local converged_llc=""

    if ! launch_and_converge PID converged_llc "$MONITOR_SECS" "$SAMPLE_INTERVAL" "$PASS_THRESHOLD"; then
        kill $PID 2>/dev/null; wait $PID 2>/dev/null
        return 1
    fi

    echo ""
    echo "=== Phase 2: saturating LLC${converged_llc} — expecting re-convergence onto a new LLC ==="
    local SAT_CPUS
    eval "SAT_CPUS=\$LLC_CPUS_${converged_llc}"

    stress-ng --cpu $LLC_SIZE --taskset "$SAT_CPUS" &
    local STRESS_PID=$!
    echo "stress-ng saturating LLC${converged_llc} ($SAT_CPUS) with $LLC_SIZE workers..."

    elapsed=0
    local phase2_result="FAIL"
    local consecutive_pass=0
    while [ "$(echo "$elapsed < $SATURATION_SECS" | bc)" -eq 1 ]; do
        sleep $SAMPLE_INTERVAL
        elapsed=$(echo "$elapsed + $SAMPLE_INTERVAL" | bc)

        if ! kill -0 $PID 2>/dev/null; then
            echo "  [ERROR] process $PID exited unexpectedly"
            break
        fi

        echo "t=${elapsed}s  workers: $(get_proc_llc_dist_workers $PID)"

        if check_convergence $PID; then
            local new_llc
            new_llc=$(get_top_llc $PID)
            if [ "$new_llc" != "$converged_llc" ]; then
                consecutive_pass=$(( consecutive_pass + 1 ))
                echo "  => re-converged on new LLC${new_llc} ($consecutive_pass/$PASS_THRESHOLD consecutive)"
                if [ $consecutive_pass -ge $PASS_THRESHOLD ]; then
                    phase2_result="PASS"
                    break
                fi
            else
                consecutive_pass=0
                echo "  => still converged on saturated LLC${new_llc}"
            fi
        else
            consecutive_pass=0
            echo "  => spread (re-selection in progress)"
        fi
    done

    kill $STRESS_PID 2>/dev/null; wait $STRESS_PID 2>/dev/null
    echo "stress-ng released"

    echo ""
    echo "----------------------------------------"
    echo "test_llc_reselect phase 2 result: $phase2_result"
    echo "----------------------------------------"

    kill $PID 2>/dev/null; wait $PID 2>/dev/null

    [ "$phase2_result" = "PASS" ]
}

# ---------------------------------------------------------------------------
# F3: Verify two processes settle onto different LLCs via even scatter.
# ---------------------------------------------------------------------------
run_test_two_proc() {
    local MONITOR_SECS=${MONITOR_SECS:-60}
    local PID1="" PID2=""

    echo "=== Phase 1: waiting for proc1 to converge ==="
    # shellcheck disable=SC2034
    local proc1_llc=""

    if ! launch_and_converge PID1 proc1_llc "$MONITOR_SECS" "$SAMPLE_INTERVAL" "$PASS_THRESHOLD"; then
        kill $PID1 2>/dev/null; wait $PID1 2>/dev/null
        return 1
    fi

    echo ""
    echo "=== Phase 2: launching proc2, scattering evenly across all LLCs ==="
    "$SCRIPT_DIR/test_llc_agg" &
    local PID2=$!
    echo "Started proc2 PID=$PID2"
    sleep 0.2

    echo "Scattering proc2 workers and releasing affinity..."
    scatter_workers $PID2
    echo "t=0s  proc1: $(get_proc_llc_dist_workers $PID1)  proc2: $(get_proc_llc_dist_workers $PID2)"
    echo ""

    elapsed=0
    local consecutive_pass=0
    local result="FAIL"

    while [ "$(echo "$elapsed < $MONITOR_SECS" | bc)" -eq 1 ]; do
        sleep $SAMPLE_INTERVAL
        elapsed=$(echo "$elapsed + $SAMPLE_INTERVAL" | bc)

        if ! kill -0 $PID1 2>/dev/null || ! kill -0 $PID2 2>/dev/null; then
            echo "  [ERROR] a process exited unexpectedly"
            result="ERROR"
            break
        fi

        local dist1 dist2
        dist1=$(get_proc_llc_dist_workers $PID1)
        dist2=$(get_proc_llc_dist_workers $PID2)
        echo "t=${elapsed}s"
        echo "  proc1 workers: $dist1"
        echo "  proc2 workers: $dist2"

        local llcs1 llcs2 top1 top2
        llcs1=$(echo "$dist1" | tr ' ' '\n' | grep -c "^LLC")
        llcs2=$(echo "$dist2" | tr ' ' '\n' | grep -c "^LLC")
        top1=$(get_top_llc $PID1)
        top2=$(get_top_llc $PID2)

        if [ "$llcs1" -eq 1 ] && [ "$llcs2" -eq 1 ] && [ "$top1" != "$top2" ]; then
            consecutive_pass=$(( consecutive_pass + 1 ))
            echo "  => PASS: proc1 on LLC${top1}, proc2 on LLC${top2} ($consecutive_pass/$PASS_THRESHOLD consecutive)"
            if [ $consecutive_pass -ge $PASS_THRESHOLD ]; then
                result="PASS"
                break
            fi
        else
            consecutive_pass=0
            if [ "$llcs2" -gt 1 ]; then
                echo "  => proc2 still converging..."
            elif [ "$top1" = "$top2" ]; then
                echo "  => proc2 converged on proc1's LLC${top2} (not yet separated)"
            else
                echo "  => proc1 not on a single LLC"
            fi
        fi
        echo ""
    done

    echo ""
    echo "----------------------------------------"
    echo "test_two_proc result: $result"
    echo "----------------------------------------"

    kill $PID1 $PID2 2>/dev/null
    wait $PID1 $PID2 2>/dev/null

    [ "$result" = "PASS" ]
}

# ---------------------------------------------------------------------------
# F4: Verify preferred LLC does not switch below 2x occupancy ratio;
#     does switch above 2x.
# ---------------------------------------------------------------------------
run_test_pref_switch() {
    local MONITOR_SECS=${MONITOR_SECS:-20}
    local PID=""
    local NWORKERS=$DEFAULT_NTHREADS

    local majority=$(( NWORKERS * 3 / 4 ))
    local minority=$(( NWORKERS - majority ))

    echo "NTHREADS=$NWORKERS  majority=$majority  minority=$minority"
    echo "Phase 1 ratio: minority/majority = $minority/$majority (below 2x → should NOT switch)"
    echo "Phase 2 ratio: majority/minority = $majority/$minority (above 2x → should switch)"
    echo ""

    echo "=== Phase 1: ratio below 2x — preferred LLC should stay ==="
    local converged_llc=""

    if ! launch_and_converge PID converged_llc "$MONITOR_SECS" "$SAMPLE_INTERVAL" 2; then
        echo "[FAIL] initial convergence failed"
        kill $PID 2>/dev/null; return 1
    fi

    local other_llc=""
    for _id in $LLC_IDS; do
        [ "$_id" != "$converged_llc" ] && other_llc=$_id && break
    done
    echo "Converged on LLC${converged_llc}. Pinning $minority workers to LLC${other_llc}..."
    pin_n_workers $PID $minority $other_llc

    echo "Observing for ${MONITOR_SECS}s — preferred LLC should stay LLC${converged_llc}..."
    local elapsed=0
    local switched=0
    while [ $elapsed -lt $MONITOR_SECS ]; do
        sleep $SAMPLE_INTERVAL
        elapsed=$(( elapsed + 1 ))
        local dist top
        dist=$(get_proc_llc_dist_workers $PID)
        top=$(get_top_llc $PID)
        echo "t=${elapsed}s  workers: $dist"
        if [ "$top" != "$converged_llc" ]; then
            switched=1
            echo "  => preferred LLC switched to LLC${top} (unexpected)"
        fi
    done

    local phase1_result="PASS"
    [ "$switched" -eq 1 ] && phase1_result="FAIL"
    echo ""
    echo "Phase 1 result: $phase1_result (PASS = preferred LLC did NOT switch)"

    kill $PID 2>/dev/null; wait $PID 2>/dev/null
    echo ""

    echo "=== Phase 2: ratio above 2x — preferred LLC should switch ==="

    local converged2_llc=""
    if ! launch_and_converge PID converged2_llc "$MONITOR_SECS" "$SAMPLE_INTERVAL" 2; then
        echo "[FAIL] phase 2 convergence failed"
        kill $PID 2>/dev/null; wait $PID 2>/dev/null
        return 1
    fi

    local other2_llc=""
    for _id in $LLC_IDS; do
        [ "$_id" != "$converged2_llc" ] && other2_llc=$_id && break
    done
    echo "Converged on LLC${converged2_llc}. Pinning $majority workers to LLC${other2_llc}; $minority free as probes..."
    pin_n_workers $PID $majority $other2_llc
    local free_tids=("${FREE_TIDS[@]}")
    local nfree=${#free_tids[@]}

    echo "t=0s (after pin, pre-switch):"
    echo "    all:     $(get_proc_llc_dist $PID)"
    echo "    workers: $(get_proc_llc_dist_workers $PID)"

    echo "Observing for ${MONITOR_SECS}s — the $nfree free probe workers should follow to LLC${other2_llc}..."
    elapsed=0
    local phase2_result="FAIL"
    local consecutive_pass=0

    while [ $elapsed -lt $MONITOR_SECS ]; do
        sleep $SAMPLE_INTERVAL
        elapsed=$(( elapsed + 1 ))
        local on_other=0
        for tid in "${free_tids[@]}"; do
            local cpu
            cpu=$(awk '{print $39}' /proc/$PID/task/$tid/stat 2>/dev/null)
            [ -z "$cpu" ] && continue
            [ "$(get_llc_id $cpu)" = "$other2_llc" ] && on_other=$(( on_other + 1 ))
        done
        echo "t=${elapsed}s"
        echo "    all:     $(get_proc_llc_dist $PID)"
        echo "    workers: $(get_proc_llc_dist_workers $PID)"
        echo "    free probe workers on LLC${other2_llc}: $on_other/$nfree"
        if [ "$on_other" -eq "$nfree" ]; then
            consecutive_pass=$(( consecutive_pass + 1 ))
            echo "  => all probe workers followed elected LLC${other2_llc} ($consecutive_pass/2 consecutive)"
            if [ $consecutive_pass -ge 2 ]; then
                phase2_result="PASS"
                break
            fi
        else
            consecutive_pass=0
        fi
    done

    echo ""
    echo "----------------------------------------"
    echo "test_pref_switch phase 1: $phase1_result"
    echo "test_pref_switch phase 2: $phase2_result"
    echo "----------------------------------------"

    kill $PID 2>/dev/null; wait $PID 2>/dev/null

    [ "$phase1_result" = "PASS" ] && [ "$phase2_result" = "PASS" ]
}

# ---------------------------------------------------------------------------
# F5: Verify workers stay on preferred LLC with feature on; spread freely
#     with feature off.
# ---------------------------------------------------------------------------
run_test_pin_steal() {
    local MONITOR_SECS=${MONITOR_SECS:-20}
    local PID=""

    eval "local LLC0_CPUS=\$LLC_CPUS_0"

    echo "=== Phase 1: llc_balancing=1 (workers should stay on LLC0) ==="
    echo 1 > /sys/kernel/debug/sched/llc_balancing/enabled

    taskset -c "$LLC0_CPUS" "$SCRIPT_DIR/test_llc_agg" &
    PID=$!
    echo "Started test_llc_agg PID=$PID (pinned to LLC0)"
    sleep 0.2
    # shellcheck disable=SC2045
    for tid in $(ls /proc/$PID/task/); do
        taskset -p -c 0-$(($(nproc) - 1)) $tid > /dev/null 2>&1
    done
    echo "Affinity released — monitoring..."
    echo ""

    local elapsed=0
    local phase1_off_llc0=0
    while [ $elapsed -lt $MONITOR_SECS ]; do
        sleep $SAMPLE_INTERVAL
        elapsed=$(( elapsed + 1 ))
        local dist
        dist=$(get_proc_llc_dist_workers $PID)
        echo "t=${elapsed}s  workers: $dist"
        # FAIL if any worker is seen on a non-LLC0 LLC
        if echo "$dist" | tr ' ' '\n' | grep "^LLC" | grep -qv "^LLC0:"; then
            phase1_off_llc0=1
        fi
    done

    local phase1_result="PASS"
    [ "$phase1_off_llc0" -eq 1 ] && phase1_result="FAIL"
    echo ""
    echo "Phase 1 result: $phase1_result (PASS = workers stayed on LLC0)"
    kill $PID 2>/dev/null; wait $PID 2>/dev/null
    echo ""

    echo "=== Phase 2: llc_balancing=0 (workers should spread to other LLCs) ==="
    echo 0 > /sys/kernel/debug/sched/llc_balancing/enabled

    taskset -c "$LLC0_CPUS" "$SCRIPT_DIR/test_llc_agg" &
    PID=$!
    echo "Started test_llc_agg PID=$PID (pinned to LLC0)"
    sleep 0.2
    # shellcheck disable=SC2045
    for tid in $(ls /proc/$PID/task/); do
        taskset -p -c 0-$(($(nproc) - 1)) $tid > /dev/null 2>&1
    done
    echo "Affinity released — monitoring..."
    echo ""

    elapsed=0
    local phase2_result="FAIL"
    while [ $elapsed -lt $MONITOR_SECS ]; do
        sleep $SAMPLE_INTERVAL
        elapsed=$(( elapsed + 1 ))
        local dist
        dist=$(get_proc_llc_dist_workers $PID)
        local unique
        unique=$(echo "$dist" | tr ' ' '\n' | grep -c "^LLC")
        echo "t=${elapsed}s  workers: $dist"
        [ "$unique" -gt 1 ] && phase2_result="PASS"
    done

    echo 1 > /sys/kernel/debug/sched/llc_balancing/enabled

    echo ""
    echo "----------------------------------------"
    echo "test_pin_steal phase 1: $phase1_result (llc_balancing=1 → workers stay on LLC0)"
    echo "test_pin_steal phase 2: $phase2_result (llc_balancing=0 → workers spread)"
    echo "----------------------------------------"

    kill $PID 2>/dev/null; wait $PID 2>/dev/null

    [ "$phase1_result" = "PASS" ] && [ "$phase2_result" = "PASS" ]
}

# ---------------------------------------------------------------------------
# F6: Observe steady-state migration destinations after convergence.
# ---------------------------------------------------------------------------
run_test_migrate_type() {
    local MONITOR_SECS=${MONITOR_SECS:-60}
    local STEADY_SECS=10
    local PID=""
    local TRACE=/sys/kernel/debug/tracing

    trap 'echo 0 > /sys/kernel/debug/tracing/tracing_on 2>/dev/null
          echo 0 > /sys/kernel/debug/tracing/events/sched/sched_migrate_task/enable 2>/dev/null
          restore_llc_params
          pkill -x test_llc_agg 2>/dev/null' EXIT INT TERM

    echo "=== Phase 1: converging (no tracing) ==="
    local converged_llc=""
    if ! launch_and_converge PID converged_llc "$MONITOR_SECS" "$SAMPLE_INTERVAL" "$PASS_THRESHOLD"; then
        echo "[FAIL] process did not converge — cannot evaluate migration direction"
        kill $PID 2>/dev/null; wait $PID 2>/dev/null
        return 1
    fi
    echo "Converged on LLC${converged_llc}"

    echo ""
    echo "=== Phase 2: recording steady-state migrations for ${STEADY_SECS}s ==="
    echo 0 > $TRACE/tracing_on
    echo > $TRACE/trace
    echo 1 > $TRACE/events/sched/sched_migrate_task/enable
    echo 1 > $TRACE/tracing_on

    local elapsed=0
    while [ $elapsed -lt $STEADY_SECS ]; do
        sleep $SAMPLE_INTERVAL
        elapsed=$(( elapsed + 1 ))
        if ! kill -0 $PID 2>/dev/null; then
            echo "  [ERROR] process $PID exited unexpectedly"
            echo 0 > $TRACE/tracing_on
            echo 0 > $TRACE/events/sched/sched_migrate_task/enable
            return 1
        fi
        echo "t=${elapsed}s  workers: $(get_proc_llc_dist_workers $PID)"
    done

    echo 0 > $TRACE/tracing_on
    echo 0 > $TRACE/events/sched/sched_migrate_task/enable

    local tid_pattern
    tid_pattern=$(ls /proc/$PID/task/ 2>/dev/null | tr '\n' '|' | sed 's/|$//')

    local worker_migrations
    worker_migrations=$(grep "comm=test_llc_agg" $TRACE/trace 2>/dev/null | \
                        grep -E "pid=($tid_pattern) ")

    if [ -z "$worker_migrations" ]; then
        echo "[FAIL] No migration events found for test_llc_agg workers (PID=$PID)"
        kill $PID 2>/dev/null; wait $PID 2>/dev/null
        return 1
    fi

    echo ""
    echo "=== Worker migration events (top 20 records) ==="
    echo "$worker_migrations" | head -20
    echo ""

    declare -A llc_dest_count
    while IFS= read -r line; do
        local dest_cpu
        dest_cpu=$(echo "$line" | grep -oP 'dest_cpu=\K[0-9]+')
        [ -z "$dest_cpu" ] && continue
        local dest_llc
        dest_llc=$(get_llc_id $dest_cpu)
        llc_dest_count[$dest_llc]=$(( ${llc_dest_count[$dest_llc]:-0} + 1 ))
    done <<< "$worker_migrations"

    echo "=== Migration destination distribution ==="
    local total=0
    for llc_id in $(echo "${!llc_dest_count[@]}" | tr ' ' '\n' | sort -n); do
        local count=${llc_dest_count[$llc_id]}
        echo "  LLC${llc_id}: $count migrations"
        total=$(( total + count ))
    done
    echo "  Total: $total migrations"
    echo ""

    local to_conv=${llc_dest_count[$converged_llc]:-0}
    local result="FAIL"
    if [ "$total" -gt 0 ] && [ $(( to_conv * 100 )) -ge $(( total * 90 )) ]; then
        result="PASS"
    fi

    echo "----------------------------------------"
    echo "test_migrate_type result: $result"
    echo "($to_conv/$total migrations targeted converged LLC${converged_llc}, bar >= 90%)"
    echo "----------------------------------------"

    kill $PID 2>/dev/null; wait $PID 2>/dev/null

    [ "$result" = "PASS" ]
}

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------
usage() {
    echo "Usage: $0 -t <test>"
    echo ""
    echo "Available tests:"
    echo "  test_llc_agg       Basic LLC aggregation"
    echo "  test_llc_reselect  Preferred LLC re-selection under saturation"
    echo "  test_two_proc      Two processes separate onto different LLCs"
    echo "  test_pref_switch   Preferred LLC switch threshold (2x occupancy)"
    echo "  test_pin_steal     LLC locality protection — pin vs idle steal"
    echo "  test_migrate_type  Migration type — tasks pulled toward preferred LLC"
    echo ""
    echo "Environment overrides:"
    echo "  MONITOR_SECS=<n>       Observation window in seconds (default varies per test)"
    echo "  SAMPLE_INTERVAL=1      Seconds between samples"
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

if pgrep -x test_llc_agg > /dev/null 2>&1; then
    test_print_trc "Killing stale test_llc_agg processes..."
    pkill -x test_llc_agg 2>/dev/null
    sleep 0.5
fi

save_llc_params

trap "restore_llc_params
      pkill -x test_llc_agg 2>/dev/null
      pkill -x stress-ng 2>/dev/null" EXIT INT TERM

echo 1 > /sys/kernel/debug/sched/llc_balancing/enabled
echo ""

case "$TEST" in
    test_llc_agg)       run_test_llc_agg ;;
    test_llc_reselect)  run_test_llc_reselect ;;
    test_two_proc)      run_test_two_proc ;;
    test_pref_switch)   run_test_pref_switch ;;
    test_pin_steal)     run_test_pin_steal ;;
    test_migrate_type)  run_test_migrate_type ;;
    *) echo "Unknown test: $TEST"; usage ;;
esac
