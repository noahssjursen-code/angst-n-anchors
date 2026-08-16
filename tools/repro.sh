#!/usr/bin/env bash
# Is a capture rig reproducible? Run it twice with no code change and compare.
#
#   tools/repro.sh hull_visual_capture           # a tests/*.tscn rig (lane B)
#   tools/repro.sh --script ocean_wake_visual_capture
#   REPRO_GAP=780 tools/repro.sh _starter_shot   # wait 13 min between the runs
#
# Exit 0 == every frame the rig wrote is byte-identical between the two runs.
#
# ── Why this tool exists, and why the gap knob is not optional ──────────────
#
# This project settles look questions by looking at captures, and a great many
# claims in STATE.md are of the form "this frame used to show X and now shows
# Y". That argument is only sound if the rig produces the same pixels from the
# same input, and several rigs here do not.
#
# The failure that matters is NOT visible in two back-to-back runs.
# `WorldClock` runs a 24-REAL-MINUTE day off the Unix clock and
# `ShipLighting` rescales every light on a vessel from it, so two runs one
# minute apart are one game hour apart and agree, while the same two runs
# twelve minutes apart are twelve game hours apart and disagree on most of the
# frame. `tests/_starter_28m_shot.gd` measured 0.0000% back to back on
# 2026-08-16 and is time-dependent all the same.
#
# So REPRO_GAP is the load-bearing argument, not a convenience: a rig is only
# shown reproducible by a pair of runs separated by more than half a game day
# (720 s). The default is 780 s — thirteen real minutes, thirteen game hours —
# which crosses noon-to-midnight for any starting hour. Set REPRO_GAP=0 for the
# fast, WEAKER check, and do not quote its 0.0000% as reproducibility.

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

GODOT="${GODOT:-godot}"
TIMEOUT="${REPRO_TIMEOUT:-900}"
RES="${REPRO_RES:-1280x720}"
GAP="${REPRO_GAP:-780}"
OUT_ROOT="${REPRO_OUT:-$PROJECT_DIR/.probe/repro}"

LANE_SCRIPT=0
if [ "${1:-}" = "--script" ]; then
  LANE_SCRIPT=1
  shift
fi
RIG="${1:-}"
if [ -z "$RIG" ]; then
  echo "usage: tools/repro.sh [--script] <rig-name> [-- rig args]" >&2
  exit 2
fi
shift || true

if [ "$LANE_SCRIPT" -eq 1 ]; then
  TARGET=(--script "res://tests/${RIG}.gd")
  SRC="tests/${RIG}.gd"
else
  TARGET=("res://tests/${RIG}.tscn")
  SRC="tests/${RIG}.gd"
fi
if [ ! -f "$SRC" ]; then
  echo "repro: no such rig — $SRC" >&2
  exit 2
fi

USERDATA="${HOME}/.local/share/godot/app_userdata/Angst N Anchors"
# Everywhere this project writes a PNG. Narrow it with REPRO_DIR when another
# render is running in the same tree — the search is by MTIME, so a concurrent
# capture rig's frames would otherwise be collected as if this rig had written
# them, and land in the report as "written by run 1 only".
SEARCH_DIRS="${REPRO_DIR:-$PROJECT_DIR/screenshots $USERDATA}"
RUN_DIR="$OUT_ROOT/$RIG"
rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR/run1" "$RUN_DIR/run2"

shoot() {
  local slot="$1"
  local stamp="$RUN_DIR/.stamp"
  : > "$stamp"
  sleep 1
  timeout "$TIMEOUT" xvfb-run -a --server-args="-screen 0 ${RES}x24" \
    "$GODOT" --rendering-driver opengl3 --audio-driver Dummy "${TARGET[@]}" "$@" \
    > "$RUN_DIR/$slot/_stdout.txt" 2>&1
  # Every PNG anywhere the project writes them, newer than the stamp. A rig that
  # changes WHERE it writes is a rig whose old frames stop being overwritten,
  # which is its own reproducibility bug (CONVENTIONS §3), so the search is wide
  # rather than a per-rig path list that would go stale.
  { find $SEARCH_DIRS -name '*.png' -newer "$stamp" 2>/dev/null; } | while read -r png; do
      rel="${png#"$PROJECT_DIR"/}"
      rel="${rel#"$USERDATA"/}"
      cp "$png" "$RUN_DIR/$slot/$(echo "$rel" | tr '/' '~')"
  done
  rm -f "$stamp"
  echo "repro: $RIG $slot wrote $(find "$RUN_DIR/$slot" -name '*.png' | wc -l) frames"
}

echo "repro: $RIG — two runs, ${GAP}s apart ($(awk "BEGIN{printf \"%.1f\", $GAP/60}") game hours)"
shoot run1 "$@"
if [ "$GAP" -gt 0 ]; then
  echo "repro: waiting ${GAP}s so the game clock moves"
  sleep "$GAP"
fi
shoot run2 "$@"

python3 tools/png_repro_diff.py "$RUN_DIR/run1" "$RUN_DIR/run2" "$RIG"
code=$?
if [ "$GAP" -eq 0 ] && [ "$code" -eq 0 ]; then
  echo "repro: REPRO_GAP=0 — this pair cannot see a time-of-day dependency."
fi
exit "$code"
