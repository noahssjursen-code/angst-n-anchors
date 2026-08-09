#!/usr/bin/env bash
# Photograph vessels built from structure_plan_v1 data objects.
#
#   tools/capture.sh                  # every fixture, every canonical angle
#   tools/capture.sh demo_workboat    # one fixture, by filename stem
#
# PNGs land in screenshots/studio/ under stable names, so re-running overwrites
# and two runs are diffable. The run also asserts — geometry exists, the bake
# stayed merged, no capture came out blank — and exits non-zero if any claim
# fails. A picture on its own is not a test result.
#
# Scene lane, not --script: VesselSpawn reaches BoatBody, which names the
# WorldGateway autoload, and --script registers no autoloads. See CONVENTIONS.md §2.

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

GODOT="${GODOT:-godot}"
TIMEOUT="${CAPTURE_TIMEOUT:-600}"
RES="${CAPTURE_RES:-1600x900}"

if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "capture: godot not found on PATH" >&2
  exit 127
fi
if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "capture: xvfb-run not found — headless Godot cannot render (see CONVENTIONS.md §2)" >&2
  exit 127
fi

echo "capture: ${RES} · fixtures: ${*:-all}"

timeout "$TIMEOUT" xvfb-run -a --server-args="-screen 0 ${RES}x24" \
  "$GODOT" --rendering-driver opengl3 --audio-driver Dummy \
  res://tests/vessel_render_capture.tscn -- "$@" 2>&1 \
  | grep -vE 'ALSA lib|snd_func|snd_config|Could not set V-Sync|at: set_use_vsync'
code=${PIPESTATUS[0]}

if [ "$code" -eq 124 ]; then
  echo "capture: TIMEOUT after ${TIMEOUT}s" >&2
  exit 124
fi
if [ "$code" -ne 0 ]; then
  echo "capture: FAILED (exit $code)" >&2
  exit "$code"
fi

echo "capture: OK — $(ls -1 screenshots/studio/*.png 2>/dev/null | wc -l) images in screenshots/studio/"
