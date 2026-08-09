#!/usr/bin/env bash
# Angst 'n Anchors — the gate.
#
# Runs every headless test under tests/, in two lanes, and reports pass/fail.
# The tree is green only when this exits 0.
#
#   tools/gate.sh                  # everything, both lanes
#   tools/gate.sh ui structure     # only tests whose filename matches a filter
#   GATE_JOBS=4 tools/gate.sh      # parallelism (default: half the cores, min 2)
#   GATE_TIMEOUT=240 tools/gate.sh # per-test timeout seconds
#   GATE_LANE=A tools/gate.sh      # restrict to one lane (A|B, default both)
#   GATE_DRIVER=headless tools/gate.sh   # force the degraded driver (see below)
#
# ---------------------------------------------------------------------------
# THE TWO LANES
#
# Lane A — `extends SceneTree`, run with `--script res://tests/x.gd`.
#   Cheap and the historical default. Its limitation is compile-time: under
#   `--script` a test that names an autoload as a bare global identifier
#   (`WorldGateway`, `LocalPlayerView`) dies with "Identifier not found", and
#   that failure cascades to everything preloading it. Autoload *instances*
#   do exist and resolve fine via `root.get_node("FreightService")`.
#
# Lane B — `extends Node` / `Node3D` plus a sibling `.tscn`, run as a main
#   scene with `godot ... res://tests/x.tscn`. Booting a scene registers the
#   autoloads properly, so these tests may name them directly. This lane was
#   not run by the gate at all until 2026-08-09; `company_service_test` — which
#   holds the "no starter vessel for any new player" bug — lives in it.
#
# The two lanes are disjoint by construction: lane A is exactly the
# `extends SceneTree` scripts, lane B is exactly the `.tscn` files whose
# sibling script is *not* `extends SceneTree`. No name can appear in both, so
# per-name log files never collide.
#
# A `.tscn` whose sibling script *is* `extends SceneTree` is STALE — Godot
# refuses to assign a SceneTree script to a Node ("Script inherits from native
# type 'SceneTree', so it can't be assigned to an object of type 'Node'"), the
# scene never runs, and the process idles until the timeout kills it. Those are
# skipped, by detection rather than by a hardcoded name list, and reported.
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
# comparison, but it is not the gate — and it is especially wrong for lane B,
# whose whole point is having the autoloads.
# ---------------------------------------------------------------------------

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

GODOT="${GODOT:-godot}"
TIMEOUT="${GATE_TIMEOUT:-240}"
DRIVER="${GATE_DRIVER:-xvfb}"
LANE_FILTER="${GATE_LANE:-AB}"

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
  # $1 = lane (A|B), $2 = res:// path.
  # Lane A boots the script directly; lane B boots the .tscn as the main scene.
  local lane="$1"
  local target="$2"
  local args=()
  [ "$lane" = "A" ] && args+=(--script)
  args+=("$target")

  if [ "$DRIVER" = "xvfb" ]; then
    xvfb-run -a --server-args="-screen 0 1280x720x24" \
      "$GODOT" --rendering-driver opengl3 --audio-driver Dummy "${args[@]}"
  else
    "$GODOT" --headless "${args[@]}"
  fi
}

# ---- collect ---------------------------------------------------------------
# Each unit is "<lane>|<path>": lane A paths are .gd, lane B paths are .tscn.
ALL_UNITS=()
SKIPPED_STALE=()

while IFS= read -r gd; do
  [ -n "$gd" ] && ALL_UNITS+=("A|$gd")
done < <(grep -l '^extends SceneTree' tests/*.gd 2>/dev/null | sort)

for tscn in tests/*.tscn; do
  [ -e "$tscn" ] || continue
  gd="${tscn%.tscn}.gd"
  # No sibling script: nothing for this gate to assert on.
  [ -f "$gd" ] || continue
  # Stale pairing — see the header. Skipped, never run: it can only time out.
  if head -1 "$gd" | grep -q '^extends SceneTree'; then
    SKIPPED_STALE+=("$tscn")
    continue
  fi
  ALL_UNITS+=("B|$tscn")
done

UNITS=()
for u in "${ALL_UNITS[@]}"; do
  lane="${u%%|*}"
  path="${u#*|}"
  case "$LANE_FILTER" in
    *"$lane"*) ;;
    *) continue ;;
  esac
  if [ "$#" -gt 0 ]; then
    for filter in "$@"; do
      if [[ "$path" == *"$filter"* ]]; then UNITS+=("$u"); break; fi
    done
  else
    UNITS+=("$u")
  fi
done

if [ "${#UNITS[@]}" -eq 0 ]; then
  echo "gate: no tests matched: $*" >&2
  exit 1
fi

count_lane() {
  local want="$1" n=0
  for u in "${UNITS[@]}"; do [ "${u%%|*}" = "$want" ] && n=$(( n + 1 )); done
  echo "$n"
}
A_COUNT="$(count_lane A)"
B_COUNT="$(count_lane B)"

echo "gate: run $RUN_ID · driver=$DRIVER · ${#UNITS[@]} tests (A:$A_COUNT script · B:$B_COUNT scene) · jobs=$JOBS · timeout=${TIMEOUT}s"
for s in "${SKIPPED_STALE[@]:-}"; do
  [ -n "$s" ] && echo "gate: skipping STALE scene $s (sibling script is 'extends SceneTree'; a Node cannot take it)"
done

# ---- run -------------------------------------------------------------------
# A "verdict" is a line by which the test itself declared an outcome — the
# TestReport summary, or one of the older ad-hoc "... passed" / "... completed"
# lines. It matters for lane B: a scene that boots, exits 0 and says nothing did
# not pass, it just failed to speak. That is NOTRUN, not PASS, and it reads
# differently from FAIL(n) — which is a test that ran and reported failures.
VERDICT_RE='(: PASS \([0-9]+ checks\)$)|(: [0-9]+/[0-9]+ FAILED$)|(: NO CHECKS RAN$)|([Pp]assed)|(: completed$)|(PASS)|(FAIL)'

run_one() {
  local unit="$1"
  local lane="${unit%%|*}"
  local path="${unit#*|}"
  local name; name="$(basename "$path")"; name="${name%.*}"
  local gd="$path"; [ "$lane" = "B" ] && gd="${path%.tscn}.gd"
  local log="$OUT_DIR/logs/$name.log"
  local start; start=$(date +%s)

  timeout "$TIMEOUT" bash -c "$(declare -f godot_run); GODOT='$GODOT' DRIVER='$DRIVER' godot_run '$lane' 'res://$path'" \
    >"$log" 2>&1
  local code=$?
  local elapsed=$(( $(date +%s) - start ))

  # A unit whose own script or scene failed to load never ran, whatever the
  # exit code — and an unloadable scene exits 1, which is indistinguishable
  # from an honest failure by exit code alone.
  if grep -qF "Failed to load script \"res://$gd\"" "$log" \
     || grep -qF "Failed loading scene: res://$path" "$log" \
     || grep -qF "Script inherits from native type 'SceneTree'" "$log"; then
    code=90
  fi

  # Lane B only: exited clean but never declared an outcome. Lane A is left
  # alone here — several of its oldest members (probes, captures, smokes) pass
  # without printing anything a regex can recognise, and demoting those to
  # NOTRUN would be a fabricated red.
  if [ "$code" -eq 0 ] && [ "$lane" = "B" ] && ! grep -qE "$VERDICT_RE" "$log"; then
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

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$status" "$lane" "$name" "${elapsed}s" "$noise" "$log" >>"$OUT_DIR/results.tsv"
  local flag=""; [ "$noise" -gt 0 ] && flag=" (${noise} script errors)"
  printf '  %-11s %s  %-44s %4ss%s\n' "$status" "$lane" "$name" "$elapsed" "$flag"
}
export -f godot_run

: >"$OUT_DIR/results.tsv"

for u in "${UNITS[@]}"; do
  run_one "$u" &
  while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n 2>/dev/null || true; done
done
wait

# ---- report ----------------------------------------------------------------
sort -k2,2 -k3,3 -o "$OUT_DIR/results.tsv" "$OUT_DIR/results.tsv"
total=${#UNITS[@]}
passed=$(grep -c $'^PASS\t' "$OUT_DIR/results.tsv" || true)
noisy=$(awk -F'\t' '$5 > 0' "$OUT_DIR/results.tsv" | wc -l)
failed=$(( total - passed ))

lane_line() {
  local want="$1" label="$2"
  local tot pass
  tot=$(awk -F'\t' -v l="$want" '$2 == l' "$OUT_DIR/results.tsv" | wc -l)
  [ "$tot" -eq 0 ] && return
  pass=$(awk -F'\t' -v l="$want" '$1 == "PASS" && $2 == l' "$OUT_DIR/results.tsv" | wc -l)
  echo "gate:   lane $want ($label): $pass/$tot passed"
}

echo
echo "gate: $passed/$total passed · $noisy with script-error noise · results in $OUT_DIR"
lane_line A "--script"
lane_line B "scene"

if [ "$failed" -gt 0 ]; then
  echo "gate: FAILURES"
  grep -v $'^PASS\t' "$OUT_DIR/results.tsv" | while IFS=$'\t' read -r status lane name elapsed noise log; do
    echo "  --- [$lane] $name ($status) ---"
    if [ "$status" = "TIMEOUT" ]; then
      echo "      no verdict: killed at ${TIMEOUT}s — the test never quit()"
    elif [ "$status" = "NOTRUN" ]; then
      echo "      no verdict: the unit never reported an outcome (load failure, or exited silently)"
    fi
    grep -E 'SCRIPT ERROR|Parse Error|ERROR|FAIL|assert' "$log" 2>/dev/null | head -5 | sed 's/^/      /'
  done
  echo
  echo "gate: RED"
  exit 1
fi

echo "gate: GREEN"
exit 0
