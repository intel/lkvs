# Cache-Aware Scheduler Test Cases

## Description
The cache-aware scheduler (`sched/cache`, also called "LLC balancing") improves
cache locality by grouping threads of the same process onto CPUs that share the
same last-level cache (LLC). This reduces cross-LLC cache misses and improves
data access efficiency on platforms with multiple LLC domains (e.g. multiple
dies per socket or multiple clusters).

The feature tracks per-process CPU occupancy across LLC domains and migrates
threads toward the LLC where their process already has the highest activity,
establishing a "preferred LLC" for each process.

### Kernel Interface
The feature is controlled via debugfs:
```
/sys/kernel/debug/sched/llc_balancing/
├── enabled                 # 0=off, 1=on
├── aggr_tolerance          # 0-100: how aggressively tasks are aggregated
├── epoch_period            # epoch duration in ms
├── epoch_affinity_timeout  # timeout before affinity is re-evaluated
├── overaggr_pct            # over-aggregation percentage threshold
└── imb_pct                 # imbalance percentage threshold
```

## Platform Requirements
- Intel® Architecture-based server platform with **multiple LLCs**

## Dependencies
| Package | Install |
|---------|---------|
| stress-ng | `dnf install stress-ng` or `apt install stress-ng` |
| bc | `dnf install bc` or `apt install bc` |
| gcc | `dnf install gcc` or `apt install gcc` |
| hackbench (perf_hackbench only) | `dnf install rt-tests` or `apt install rt-tests` (or build from source, see Performance Tests notes) |

## Build
```bash
cd scheduler/
make
```
This compiles `test_llc_agg` — a multi-threaded workload (28 threads sharing a
4MB array that fits in LLC) used by all functional tests — and `test_llc_share`,
the cache-line-sharing workload used by the performance tests.

## Execution
### Run all tests via LKVS runtests framework
```bash
cd BM/
./runtests -f scheduler/tests
```

### Run individual test cases
```bash
cd BM/scheduler/
./cache_aware_function_tests.sh -t test_llc_agg
./cache_aware_function_tests.sh -t test_llc_reselect
./cache_aware_function_tests.sh -t test_two_proc
./cache_aware_function_tests.sh -t test_pref_switch
./cache_aware_function_tests.sh -t test_pin_steal
./cache_aware_perf_tests.sh -t perf_llc_miss
./cache_aware_perf_tests.sh -t perf_hackbench
```

### Environment Overrides
```bash
MONITOR_SECS=120 ./cache_aware_function_tests.sh -t test_llc_agg   # longer observation window
SAMPLE_INTERVAL=2 ./cache_aware_function_tests.sh -t test_two_proc  # slower polling
```

## Test Case Summary
| ID | Test | Description |
|----|------|-------------|
| F1 | test_llc_agg | Workers converge onto a single LLC; stay spread when feature is disabled |
| F2 | test_llc_reselect | Process re-converges onto a new LLC when preferred one is saturated |
| F3 | test_two_proc | Two processes settle onto different LLCs |
| F4 | test_pref_switch | Preferred LLC does not switch below 2x ratio; switches above 2x |
| F5 | test_pin_steal | Workers stay on preferred LLC (feature on); spread freely (feature off) |

### Performance Tests
These use `perf` hardware counters to quantify the benefit of aggregation on a
true cache-line-sharing workload (`test_llc_share`, where every thread
read-modify-writes every line of one shared buffer sized to fit a single LLC).

| ID | Test | Description |
|----|------|-------------|
| PERF1 | perf_llc_miss | Measures the LLC-load-miss rate (`LLC-load-misses / LLC-loads`) and IPC (`instructions / cycles`) for the feature ON vs OFF. |
| PERF2 | perf_hackbench | Runs the native `hackbench` (`--pipe`, `-f`) with a small communicating task set that fits inside one LLC, and compares the mean wall-clock time with the feature ON vs OFF. |

> **Notes:**
> - `perf_llc_miss` requires a working `perf` with usable `LLC-loads` /
>   `LLC-load-misses` counters; it skips (NA) when `perf` is missing or when the
>   counters read zero in both phases (e.g. restrictive `perf_event_paranoid` or
>   virtualization). On a single-LLC box the OFF phase cannot scatter, so the
>   control is invalid and the case reports FAIL rather than a false pass.
> - `perf_hackbench` requires the native `hackbench` binary. It skips
>   (NA) when `hackbench` is missing, and blocks (BLOCK) when `hackbench`
>   produces no parseable samples. Prefer installing the `rt-tests` package; if
>   it is unavailable, build `hackbench` directly:
>   ```bash
>   curl -fsSLo hackbench.c https://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git/plain/src/hackbench/hackbench.c \
>     && gcc -O2 -pthread -o /usr/local/bin/hackbench hackbench.c \
>     && hackbench --help | head
>   ```
