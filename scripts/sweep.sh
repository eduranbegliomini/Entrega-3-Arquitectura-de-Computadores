#!/usr/bin/env bash
# Design-space sweeps (sections 3.2, 3.4, 3.5). Runs JOBS flows in parallel.
#   scripts/sweep.sh period <rom|ff> <T1> <T2> ...   CLOCK_PERIOD sweep at U = 40 %
#   scripts/sweep.sh util   <rom|ff> <U1> <U2> ...   FP_CORE_UTIL sweep at T = 100 ns
# Run tags: T<period>_U40 and T100_U<util>. Summary: python3 scripts/collect.py
# Note: each CLOCK_PERIOD may re-optimise the circuit (sizing, buffering,
# placement). With SYNTH_STRATEGY = AREA 0 and timing repair only in the
# default (typical) corner, our netlists turned out identical (report, 4.1).
set -euo pipefail
cd "$(dirname "$0")/.."
kind=$1; design=$2; shift 2
JOBS=${JOBS:-3}
for v in "$@"; do
  case $kind in
    period) echo "$design T${v}_U40 -c CLOCK_PERIOD=$v" ;;
    util)   echo "$design T100_U${v} -c FP_CORE_UTIL=$v" ;;
    *) echo "unknown sweep '$kind'" >&2; exit 1 ;;
  esac
done | xargs -P "$JOBS" -L 1 sh -c 'scripts/run.sh "$0" "$1" "$2" "$3" > "/tmp/$0_$1.log" 2>&1 && echo "done $0 $1" || echo "FAILED $0 $1 (see /tmp/$0_$1.log)"'
python3 scripts/collect.py "$design"
