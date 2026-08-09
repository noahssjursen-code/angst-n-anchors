#!/usr/bin/env bash
# Angst 'n Anchors — the gate.
#
# Runs every `extends SceneTree` test under tests/ and reports pass/fail.
# The tree is green only when this exits 0.
#
#   tools/gate.sh                  # everything
#   tools/gate.sh ui structure     # only tests whose filename matches a filter
#   GATE_JOBS=4 tools/gate.sh      # parallelism (default: half the cores, min 2)
#   GATE_TIMEOUT=240 tools/gate.sh # per-test timeout seconds
#   GATE_DRIVER=headless tools/gate.sh   # force the degraded driver (see below)
#
# ---------------------------------------------------------------------------
# WHY NOT `--headless`
#
# `godot --headless --script res://tests/x.gd` uses the dummy rendering driver.
# Two things break under it, measured on this container:
#   1. Autoload singletons are not registered, so any test that transitively
#      preloads a script naming WorldGateway / LocalPlayerView dies with
#      "Compile Error: Identifier not found".
#   2. `await RenderingServer.frame_post_draw` never returns, because no frame
#      is ever drawn. Every render-dependent test hangs until the timeout.
#
# Under xvfb + the opengl3 driver (Mesa llvmpipe software rasteriser, present in
# this container) both problems disappear and captures produce real pixels.
# That is the default here. `GATE_DRIVER=headless` keeps the old behaviour for
# comparison, but it is not the gate.
# ---------------------------------------------------------------------------

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

GODOT="${GODOT:-godot}"
TIMEOUT="${GATE_TIMEOUT:-240}"
DRIVER="${GATE_DRIVER:-xvfb}"

CORES="$(nproc 2>/dev/null || echo 4)"
DEFAULT_JOBS=$(( CORES / 2 )); [ "$DEFAULT_JOBS" -lt 2 ] && DEFAULT_JOBS=2
JOBS="${GATE_JOBS:-$DEFAULT_JOBS}"

# Run-unique output dir: concurrent gate runs (an agent and the orchestrator,
# two agents) must never delete each other's results. `.gate/latest` is a
# symlink to the most recent run.
RUN_ID="${GATE_RUN_ID:-$(date -u +%Y%m%d-%H%M%S)-$$}"
OUT_DIR="${GATE_OUT:-$PROJECT_DIR/.gate/$RUN_ID}"

if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "gate: godot not found on PATH (set GODOT=/path/to/godot)" >&2
  echo "gate: on a fresh container run: CLAUDE_CODE_REMOTE=true .claude/hooks/session-start.sh" >&2
  exit 127
fi

mkdir -p "$OUT_DIR/logs"
ln -sfn "$OUT_DIR" "$PROJECT_DIR/.gate/latest"

# ---- driver ----------------------------------------------------------------
case "$DRIVER" in
  xvfb)
    if ! command -v xvfb-run >/dev/null 2>&1; then
      echo "gate: xvfb-run not found; falling back to GATE_DRIVER=headless (degraded)" >&2
      DRIVER=headless
    fi
    ;;
  headless) ;;
  *) echo "gate: unknown GATE_DRIVER=$DRIVER (want xvfb|headless)" >&2; exit 2 ;;
esac

godot_run() {
  # $1 = res:// script path, rest = extra args
  if [ "$DRIVER" = "xvfb" ]; then
    xvfb-run -a --server-args="-screen 0 1280x720x24" \
      "$GODOT" --rendering-driver opengl3 --audio-driver Dummy --script "$1"
  else
    "$GODOT" --headless --script "$1"
  fi
}

# ---- collect ---------------------------------------------------------------
mapfile -t ALL_TESTS < <(grep -l '^extends SceneTree' tests/*.gd | sort)

TESTS=()
if [ "$#" -gt 0 ]; then
  for t in "${ALL_TESTS[@]}"; do
    for filter in "$@"; do
      if [[ "$t" == *"$filter"* ]]; then TESTS+=("$t"); break; fi
    done
  done
else
  TESTS=("${ALL_TESTS[@]}")
fi

if [ "${#TESTS[@]}" -eq 0 ]; then
  echo "gate: no tests matched: $*" >&2
  exit 1
fi

echo "gate: run $RUN_ID · driver=$DRIVER · ${#TESTS[@]} tests · jobs=$JOBS · timeout=${TIMEOUT}s"

# ---- run -------------------------------------------------------------------
run_one() {
  local path="$1"
  local name; name="$(basename "$path" .gd)"
  local log="$OUT_DIR/logs/$name.log"
  local start; start=$(date +%s)

  timeout "$TIMEOUT" bash -c "$(declare -f godot_run); GODOT='$GODOT' DRIVER='$DRIVER' godot_run 'res://$path'" \
    >"$log" 2>&1
  local code=$?
  local elapsed=$(( $(date +%s) - start ))

  # A test whose own script failed to compile never ran, whatever the exit code.
  if [ "$code" -eq 0 ] && grep -qF "Failed to load script \"res://$path\"" "$log"; then
    code=90
  fi

  local status
  case "$code" in
    0)   status="PASS" ;;
    124) status="TIMEOUT" ;;
    90)  status="NOTRUN" ;;
    *)   status="FAIL($code)" ;;
  esac

  # Compile noise in *other* scripts does not fail the gate, but it is tracked:
  # it is how autoload/driver regressions announce themselves.
  # grep -c prints 0 and exits 1 when there is no match; swallow the status only.
  local noise; noise=$(grep -c 'SCRIPT ERROR' "$log" 2>/dev/null || true); noise=${noise:-0}

  printf '%s\t%s\t%s\t%s\t%s\n' "$status" "$name" "${elapsed}s" "$noise" "$log" >>"$OUT_DIR/results.tsv"
  local flag=""; [ "$noise" -gt 0 ] && flag=" (${noise} script errors)"
  printf '  %-11s %-46s %4ss%s\n' "$status" "$name" "$elapsed" "$flag"
}
export -f godot_run

: >"$OUT_DIR/results.tsv"

for t in "${TESTS[@]}"; do
  run_one "$t" &
  while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n 2>/dev/null || true; done
done
wait

# ---- report ----------------------------------------------------------------
sort -k2,2 -o "$OUT_DIR/results.tsv" "$OUT_DIR/results.tsv"
total=${#TESTS[@]}
passed=$(grep -c $'^PASS\t' "$OUT_DIR/results.tsv" || true)
noisy=$(awk -F'\t' '$4 > 0' "$OUT_DIR/results.tsv" | wc -l)
failed=$(( total - passed ))

echo
echo "gate: $passed/$total passed · $noisy with script-error noise · results in $OUT_DIR"

if [ "$failed" -gt 0 ]; then
  echo "gate: FAILURES"
  grep -v $'^PASS\t' "$OUT_DIR/results.tsv" | while IFS=$'\t' read -r status name elapsed noise log; do
    echo "  --- $name ($status) ---"
    grep -E 'SCRIPT ERROR|Parse Error|ERROR|FAIL|assert' "$log" 2>/dev/null | head -5 | sed 's/^/      /'
  done
  echo
  echo "gate: RED"
  exit 1
fi

echo "gate: GREEN"
exit 0
