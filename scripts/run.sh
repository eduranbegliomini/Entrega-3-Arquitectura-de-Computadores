#!/usr/bin/env bash
# Run the full LibreLane flow for one memory strategy.
#   scripts/run.sh <rom|ff|p2_original> <run_tag> [-c KEY=VALUE ...] [other librelane flags]
# Example: scripts/run.sh rom final
#          scripts/run.sh rom T60 -c CLOCK_PERIOD=60
# Results: librelane/<design>/runs/<run_tag>/
set -euo pipefail
source "$(dirname "$0")/env.sh"
design=$1; tag=$2; shift 2
librelane_cmd --pdk "$PDK" --scl "$SCL" --run-tag "$tag" --overwrite "$@" \
  "$ROOT/librelane/$design/config.json"
