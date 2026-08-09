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
#
# ---------------------------------------------------------------------------
# "CANNOT RUN HERE" — `## gate-requires:`
#
# Some tests need a machine capability this box may not have. Without a way to
# say so they show up as FAIL or TIMEOUT forever, and the noise trains everyone
# to ignore the gate. The mechanism below gives them a first-class outcome —
# SKIP — built so it cannot be used to bury an inconvenient failure.
#
#   1. The requirement is declared IN THE TEST, in its header:
#        ## gate-requires: rendering_device
#      There is no list of test names in this script. Editing gate.sh cannot
#      exclude a test; only the test can, and `git blame` shows who did it.
#
#   2. The gate PROBES the capability. Each token maps (in `capability_expr`
#      below) to a GDScript expression that is compiled and evaluated by a real
#      Godot process under the same driver flags the tests use. Nothing is
#      assumed about the box. Probes run once per gate run and are cached.
#
#   3. A probe that says YES means the unit RUNS. Declaring a requirement this
#      box satisfies buys nothing — it is not an opt-out, it is a question.
#
#   4. An UNDECLARABLE token is a hard FAIL, never a SKIP. A test naming a
#      capability `capability_expr` does not know fails the gate. So you cannot
#      invent `## gate-requires: my-machine-is-tired` to escape; you would have
#      to add a probe here, in the diff, next to the real ones.
#
#   5. A probe that cannot be run (godot crashed, timed out) is INDETERMINATE
#      and the unit RUNS. Every uncertain path leads to running the test.
#
#   6. Skips are counted and printed loudly — in the headline, in a dedicated
#      block naming the unit, the capability and the probe expression that
#      returned NO, and in results.tsv. A green run with skips says so on the
#      GREEN line. Nothing is silently dropped.
#
#   7. `GATE_NO_SKIP=1 tools/gate.sh` runs every skipped unit anyway. The claim
#      "cannot run here" is falsifiable on demand by anyone who doubts it, and
#      the summary advertises the switch.
# ---------------------------------------------------------------------------

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

GODOT="${GODOT:-godot}"
TIMEOUT="${GATE_TIMEOUT:-240}"
DRIVER="${GATE_DRIVER:-xvfb}"
LANE_FILTER="${GATE_LANE:-AB}"
NO_SKIP="${GATE_NO_SKIP:-0}"

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

mkdir -p "$OUT_DIR/logs" "$OUT_DIR/probes" "$OUT_DIR/caps"
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

# ---- capabilities ----------------------------------------------------------
# The whole registry. A token is a question about the machine, expressed as a
# GDScript boolean expression evaluated in a real Godot process. Adding a token
# here means adding a probe; there is nowhere to name a test.
capability_expr() {
  case "$1" in
    rendering_device)
      echo 'RenderingServer.get_rendering_device() != null' ;;
    frame_capture)
      echo 'root.get_viewport().get_texture() != null and root.get_viewport().get_texture().get_image() != null' ;;
    *) return 1 ;;
  esac
}

# Tokens declared by a unit's script, from its header only — a marker buried at
# the bottom of a 400-line file would not be seen by a reviewer either.
unit_requirements() {
  sed -n '1,40p' "$1" 2>/dev/null \
    | sed -n 's/^## gate-requires:[[:space:]]*\([A-Za-z0-9_, -]*[A-Za-z0-9_]\)[[:space:]]*$/\1/p' \
    | tr ',' ' ' | tr ' ' '\n' | sed '/^$/d'
}

# YES | NO | UNKNOWN. Cached per run: one Godot process per distinct token.
probe_capability() {
  local token="$1"
  local cache="$OUT_DIR/caps/$token"
  if [ -f "$cache" ]; then cat "$cache"; return 0; fi

  local expr
  if ! expr="$(capability_expr "$token")"; then
    echo UNKNOWN >"$cache"; echo UNKNOWN; return 0
  fi

  local gd="$OUT_DIR/probes/$token.gd"
  cat >"$gd" <<EOF
extends SceneTree

func _initialize() -> void:
	call_deferred("_probe")

func _probe() -> void:
	await process_frame
	print("GATE_CAP %s" % ("YES" if ($expr) else "NO"))
	quit(0)
EOF

  local log="$OUT_DIR/probes/$token.log"
  timeout 120 bash -c \
    "$(declare -f godot_run); GODOT='$GODOT' DRIVER='$DRIVER' godot_run 'A' 'res://${gd#"$PROJECT_DIR"/}'" \
    >"$log" 2>&1

  local verdict=UNKNOWN
  if grep -q '^GATE_CAP YES' "$log"; then
    verdict=YES
  elif grep -q '^GATE_CAP NO' "$log"; then
    verdict=NO
  fi
  echo "$verdict" >"$cache"
  echo "$verdict"
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

# ---- requirements ----------------------------------------------------------
# Partition the matched units by whether this box can answer what they ask for.
# Probes run before any test does, so the header line is already truthful.
RUN_UNITS=()
SKIPPED_CAP=()   # "<lane>|<path>|<token>"
BAD_REQUIRE=()   # "<lane>|<path>|<token>"

for u in "${UNITS[@]}"; do
  lane="${u%%|*}"
  path="${u#*|}"
  gd="$path"; [ "$lane" = "B" ] && gd="${path%.tscn}.gd"
  decision="run"
  while IFS= read -r token; do
    [ -n "$token" ] || continue
    if ! capability_expr "$token" >/dev/null 2>&1; then
      # No probe exists for this token, so nothing has been established about
      # the box. That is a defect in the test, not permission to skip it.
      BAD_REQUIRE+=("$u|$token"); decision="bad"; break
    fi
    verdict="$(probe_capability "$token")"
    # YES runs. UNKNOWN (probe crashed or timed out) runs — an unanswered
    # question is not a licence to skip. Only a measured NO skips.
    if [ "$verdict" = "NO" ] && [ "$NO_SKIP" != "1" ]; then
      SKIPPED_CAP+=("$u|$token"); decision="skip"; break
    fi
  done < <(unit_requirements "$gd")
  [ "$decision" = "run" ] && RUN_UNITS+=("$u")
done

count_lane() {
  local want="$1" n=0
  for u in "${RUN_UNITS[@]:-}"; do [ "${u%%|*}" = "$want" ] && n=$(( n + 1 )); done
  echo "$n"
}
A_COUNT="$(count_lane A)"
B_COUNT="$(count_lane B)"

echo "gate: run $RUN_ID · driver=$DRIVER · ${#RUN_UNITS[@]} tests (A:$A_COUNT script · B:$B_COUNT scene) · jobs=$JOBS · timeout=${TIMEOUT}s"
[ "$NO_SKIP" = "1" ] && echo "gate: GATE_NO_SKIP=1 — capability skips disabled, every matched unit runs"
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

  # Did the unit declare an outcome in its own words? This is authoritative and
  # must be decided BEFORE anything else reclassifies the run.
  local spoke=1
  grep -qE "$VERDICT_RE" "$log" || spoke=0

  # A unit whose own script or scene failed to load never ran, whatever the exit
  # code — an unloadable scene exits 1, indistinguishable from an honest failure.
  #
  # But ONLY when it never spoke. Godot emits `Failed to load script "res://..."`
  # during the transient compile cascade that the --script lane provokes (an
  # autoload named as a bare identifier, three files deep), then loads and runs
  # the script anyway. Treating that banner as authoritative reported
  # `building_blueprint_test: 17/20 FAILED` as NOTRUN, and reported five tests
  # that passed every check as never having run. A verdict outranks a banner.
  if [ "$spoke" -eq 0 ]; then
    if grep -qF "Failed to load script \"res://$gd\"" "$log" \
       || grep -qF "Failed loading scene: res://$path" "$log" \
       || grep -qF "Script inherits from native type 'SceneTree'" "$log"; then
      code=90
    fi
  fi

  # Lane B only: exited clean but never declared an outcome. Lane A is left
  # alone here — several of its oldest members (probes, captures, smokes) pass
  # without printing anything a regex can recognise, and demoting those to
  # NOTRUN would be a fabricated red.
  if [ "$code" -eq 0 ] && [ "$lane" = "B" ] && [ "$spoke" -eq 0 ]; then
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

# A unit whose declared requirement has no probe never runs and never passes.
for entry in "${BAD_REQUIRE[@]:-}"; do
  [ -n "$entry" ] || continue
  lane="${entry%%|*}"; rest="${entry#*|}"
  path="${rest%|*}"; token="${rest##*|}"
  name="$(basename "$path")"; name="${name%.*}"
  printf 'FAIL(cap)\t%s\t%s\t0s\t0\t%s\n' "$lane" "$name" "unknown gate-requires: $token" >>"$OUT_DIR/results.tsv"
  printf '  %-11s %s  %-44s %4ss  (unknown gate-requires: %s)\n' "FAIL(cap)" "$lane" "$name" 0 "$token"
done

for entry in "${SKIPPED_CAP[@]:-}"; do
  [ -n "$entry" ] || continue
  lane="${entry%%|*}"; rest="${entry#*|}"
  path="${rest%|*}"; token="${rest##*|}"
  name="$(basename "$path")"; name="${name%.*}"
  printf 'SKIP\t%s\t%s\t0s\t0\t%s\n' "$lane" "$name" "$OUT_DIR/probes/$token.log" >>"$OUT_DIR/results.tsv"
done

for u in "${RUN_UNITS[@]:-}"; do
  [ -n "$u" ] || continue
  run_one "$u" &
  while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n 2>/dev/null || true; done
done
wait

# ---- report ----------------------------------------------------------------
sort -k2,2 -k3,3 -o "$OUT_DIR/results.tsv" "$OUT_DIR/results.tsv"
skipped=${#SKIPPED_CAP[@]}
total=$(( ${#RUN_UNITS[@]} + ${#BAD_REQUIRE[@]} ))
passed=$(grep -c $'^PASS\t' "$OUT_DIR/results.tsv" || true)
noisy=$(awk -F'\t' '$5 > 0' "$OUT_DIR/results.tsv" | wc -l)
failed=$(( total - passed ))

lane_line() {
  local want="$1" label="$2"
  local tot pass
  tot=$(awk -F'\t' -v l="$want" '$2 == l && $1 != "SKIP"' "$OUT_DIR/results.tsv" | wc -l)
  [ "$tot" -eq 0 ] && return
  pass=$(awk -F'\t' -v l="$want" '$1 == "PASS" && $2 == l' "$OUT_DIR/results.tsv" | wc -l)
  echo "gate:   lane $want ($label): $pass/$tot passed"
}

echo
skip_note=""
[ "$skipped" -gt 0 ] && skip_note=" · $skipped SKIPPED (cannot run here)"
echo "gate: $passed/$total passed$skip_note · $noisy with script-error noise · results in $OUT_DIR"
lane_line A "--script"
lane_line B "scene"

# Skips are never silent: every one names the unit, the capability it declared,
# and the probe expression that answered NO on this box.
if [ "$skipped" -gt 0 ]; then
  echo "gate: SKIPPED — declared a capability this box does not have"
  for entry in "${SKIPPED_CAP[@]}"; do
    lane="${entry%%|*}"; rest="${entry#*|}"
    path="${rest%|*}"; token="${rest##*|}"
    name="$(basename "$path")"; name="${name%.*}"
    echo "  [$lane] $name — gate-requires: $token"
    echo "        probe: $(capability_expr "$token") → NO   ($OUT_DIR/probes/$token.log)"
  done
  echo "  These units did not run and did not pass. Re-run with GATE_NO_SKIP=1 to make them run anyway."
fi

if [ "$failed" -gt 0 ]; then
  echo "gate: FAILURES"
  grep -vE $'^(PASS|SKIP)\t' "$OUT_DIR/results.tsv" | while IFS=$'\t' read -r status lane name elapsed noise log; do
    echo "  --- [$lane] $name ($status) ---"
    if [ "$status" = "TIMEOUT" ]; then
      echo "      no verdict: killed at ${TIMEOUT}s — the test never quit()"
    elif [ "$status" = "NOTRUN" ]; then
      echo "      no verdict: the unit never reported an outcome (load failure, or exited silently)"
    elif [ "$status" = "FAIL(cap)" ]; then
      echo "      $log — add a probe to capability_expr() in tools/gate.sh, or drop the marker"
      continue
    fi
    grep -E 'SCRIPT ERROR|Parse Error|ERROR|FAIL|assert' "$log" 2>/dev/null | head -5 | sed 's/^/      /'
  done
  echo
  echo "gate: RED"
  exit 1
fi

if [ "$skipped" -gt 0 ]; then
  echo "gate: GREEN · $skipped unit(s) could not run here — see SKIPPED above"
else
  echo "gate: GREEN"
fi
exit 0
