#!/usr/bin/env bash
# Angst 'n Anchors — the gate.
#
# Runs every headless test under tests/ plus every app that declares a
# self-check, in three lanes, and reports pass/fail.
# The tree is green only when this exits 0.
#
#   tools/gate.sh                  # everything, all three lanes
#   tools/gate.sh ui structure     # only tests whose filename matches a filter
#   GATE_JOBS=4 tools/gate.sh      # parallelism (default: half the cores, min 2)
#   GATE_TIMEOUT=240 tools/gate.sh # per-test timeout seconds
#   GATE_LANE=A tools/gate.sh      # restrict to lanes (A|B|C, default all three)
#   GATE_DRIVER=headless tools/gate.sh   # force the degraded driver (see below)
#   GATE_NO_SKIP=1 tools/gate.sh   # ignore every `## gate-requires:` and just run
#   GATE_AUDIT_SKIPS=0 tools/gate.sh     # do not re-run skipped units (see below)
#
# ---------------------------------------------------------------------------
# THE THREE LANES
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
# Lane C — APP SCENES WITH A SELF-CHECK FLAG. See the block below.
#
# The three lanes are disjoint by construction: lane A is exactly the
# `extends SceneTree` scripts under tests/, lane B is exactly the tests/ `.tscn`
# files whose sibling script is *not* `extends SceneTree`, lane C is exactly the
# scenes named by a `## gate-selfcheck:` declaration and those live under
# scenes/, not tests/. Construction is not trusted on its own: the collected
# units are checked for a duplicate NAME before anything runs, and a duplicate
# aborts the run, because two units sharing a name share a log file and would
# silently overwrite each other's evidence.
#
# ---------------------------------------------------------------------------
# LANE C — "APP SCENES WITH A SELF-CHECK FLAG"  (`## gate-selfcheck:`)
#
# Some workouts are neither an `extends SceneTree` script nor a test scene: they
# are a real app, booted normally, told by a command-line flag to drive itself
# and quit with a verdict. Structure Studio's `--studio-probe` is the first —
# every diagonal claim on the studio side (bounds, picking, along-run offset,
# the opening ghost's yaw, save/load of the diagonal axis and its cut) is
# asserted there and nowhere else.
#
# There is no list of app names in this script, for the same reason there is no
# list of test names in the `## gate-requires:` mechanism: a category that a
# maintainer has to be told about is a category that gets forgotten. The app
# DECLARES ITSELF, in its own script's header:
#
#   ## gate-selfcheck: res://scenes/apps/structure_studio.tscn -- --studio-probe
#
#   <scene> is the scene to boot. `--` is required and literal: it is Godot's
#   separator, and writing it here means the declaration is exactly the command
#   you would type. Everything after it is handed to the app verbatim.
#
# The second such app joins by adding one line to its own script. An app scene
# with no declaration and no self-check is simply not a lane C unit — it is
# never booted, so an editor with no self-check cannot be mis-run as if it had
# one.
#
# A declaration that does not hold up is a hard FAIL, never a silent drop —
# same rule as an undeclarable `## gate-requires:` token. Missing scene file,
# missing `--`, no flag after it: `FAIL(selfcheck)`, named in the report. You
# cannot make a unit disappear by mangling its marker.
#
# ...NOR BY DELETING IT. That was the hole, and it was the wrong way round: a
# mangled marker failed the gate while a *deleted* one removed the unit
# entirely, with no report and exit 0. Deleting a line is easier than mangling
# one, and it is what someone under pressure to go green would reach for.
#
# The marker still lives in the app's own script — a category a maintainer has
# to be told about is a category that gets forgotten, exactly as with
# `## gate-requires:`. But a declaration that can vanish needs something that
# notices its absence, and that something cannot be a list of app names here.
# So the gate does not take the marker's word for whether an app has a
# self-check. It looks for the SELF-CHECK ITSELF, and requires the two to agree:
#
#   implementation + declaration → a lane C unit, booted and scored.
#   implementation, no declaration → FAIL(selfcheck). THIS is the deleted line.
#   declaration, no implementation → FAIL(selfcheck). This is the marker moved
#                                    somewhere it can rot, or pointing at an app
#                                    that no longer checks anything.
#   neither                        → not lane C. Nothing to report. An app that
#                                    genuinely has no self-check stays green.
#
# What counts as "implements a self-check" is exactly what lane C scores one by:
# the script speaks the suite's verdict language — `<name>: PASS (N checks)`,
# `<name>: N/M FAILED`, `<name>: NO CHECKS RAN` — either printing those lines
# itself or through `tests/support/test_report.gd`, which is where those words
# are defined. A script that reports an outcome in the gate's own vocabulary is
# reporting it TO the gate, and must say so. Comment lines do not count: this
# very block talks about verdicts, and prose is not an implementation.
#
# The remaining way out is to delete the marker *and* gut the verdict the app
# prints. That is a real code deletion in the diff, not a comment tweak — and
# an app that no longer reports an outcome no longer has a self-check to lose.
#
# Lane C is scored like lane B: booting clean and saying nothing is NOTRUN, not
# PASS. A self-check that does not declare an outcome has not passed. So the
# app must print a verdict line — `<name>: PASS (N checks)`, `<name>: N/M
# FAILED`, `<name>: NO CHECKS RAN` — the same words the rest of the suite uses.
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
#
#   8. THE SKIP AUDIT — the claim polices itself, every run.
#
#      Points 1-7 make the marker visible and probe-backed, but a critic found
#      the hole and it is a real one: nothing correlates the token a test
#      *declares* with anything the test *does*. `## gate-requires:` is a
#      comment. A test can name a capability it does not need, the probe
#      truthfully answers NO for the box, and one comment line has lifted a
#      working test out of the gate forever. That is exactly what happened to
#      `ocean_wake_visual_capture`, which passes here in ~31 s.
#
#      A declaration cannot be verified statically. It can be verified by
#      experiment, so the gate runs the experiment: every unit it skipped is
#      RE-RUN anyway, with the skip lifted, and the result is scored against
#      the claim.
#
#        re-run FAILs / TIMEOUTs / NOTRUNs  → the claim holds. The skip stands
#                                             and the gate does not go red for it.
#        re-run PASSES                      → the claim is FALSE. Hard gate
#                                             FAILURE, naming the unit and the
#                                             bogus capability.
#
#      The bar for "false" is exactly the bar the gate uses for green: if the
#      unit would have counted as PASS in a normal run, it can run here, and
#      the marker was excluding a working test.
#
#      This is on by default, because the cost has to land on the person making
#      the claim rather than on the person doubting it. A false skip now costs a
#      red gate; a true skip costs one re-run of a test that was already failing.
#      `GATE_AUDIT_SKIPS=0` turns the audit off for a run — and both the headline
#      and the verdict line then say, loudly, that the skips went unverified.
#      Audit re-runs get their own `<name>.audit.log` and their own `audit.tsv`;
#      they never touch the real run's logs or results.
# ---------------------------------------------------------------------------

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

GODOT="${GODOT:-godot}"
TIMEOUT="${GATE_TIMEOUT:-240}"
DRIVER="${GATE_DRIVER:-xvfb}"
LANE_FILTER="${GATE_LANE:-ABC}"
NO_SKIP="${GATE_NO_SKIP:-0}"
AUDIT="${GATE_AUDIT_SKIPS:-1}"
# A skipped unit is one the box supposedly cannot run, so its audit re-run is
# expected to fail or hang. Give it the normal budget unless told otherwise.
AUDIT_TIMEOUT="${GATE_AUDIT_TIMEOUT:-$TIMEOUT}"

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
  # $1 = lane (A|B|C), $2 = res:// path, $3.. = extra args (lane C only).
  # Lane A boots the script directly; lanes B and C boot a .tscn as the main
  # scene. Lane C additionally passes the app's declared self-check arguments
  # through verbatim — including the `--` that hands them to the project.
  local lane="$1"; shift
  local target="$1"; shift
  local args=()
  [ "$lane" = "A" ] && args+=(--script)
  args+=("$target")
  [ "$#" -gt 0 ] && args+=("$@")

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

# Self-check declaration from a script's header, same 40-line window and the
# same "a marker buried at the bottom would not be seen by a reviewer either"
# rule as unit_requirements(). Prints the raw argument list, or nothing.
unit_selfcheck() {
  sed -n '1,40p' "$1" 2>/dev/null \
    | sed -n 's|^##[[:space:]]*gate-selfcheck:[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*$|\1|p' \
    | head -1
}

# The other half of the pairing — see the lane C block in the header. Does this
# script IMPLEMENT a self-check, whatever it declares? It does if it speaks the
# verdict language lane C scores by, which is the whole contract: an app that
# says `x: PASS (7 checks)` is reporting an outcome to this gate.
#
# Full-line comments are stripped first. The marker's own documentation quotes
# the verdict forms, and prose is not an implementation.
SELFCHECK_IMPL_RE='NO CHECKS RAN|PASS \(%d checks\)|%d/%d FAILED|tests/support/test_report\.gd'
script_implements_selfcheck() {
  # Not a pipeline into `grep -q`: under `set -o pipefail` the quiet grep exits
  # on the first match, the upstream grep dies of SIGPIPE, and the pipeline
  # reports 141 — i.e. every implementation would read as "no implementation".
  local body
  body="$(grep -v '^[[:space:]]*#' "$1" 2>/dev/null)"
  grep -qE "$SELFCHECK_IMPL_RE" <<<"$body"
}

# ---- collect ---------------------------------------------------------------
# Each unit is "<lane>|<path>": lane A paths are .gd, lanes B and C are .tscn.
ALL_UNITS=()
SKIPPED_STALE=()
declare -A SELFCHECK_ARGS=()   # scene path -> args after the scene, verbatim
declare -A SELFCHECK_GD=()     # scene path -> the script that declared it
ALL_BAD_SELFCHECK=()           # "<gd>\t<reason>\t<declaration>" — does not hold up

SKIPPED_SCRATCH=()

while IFS= read -r gd; do
  [ -n "$gd" ] || continue
  # A leading underscore marks a scratch probe, not a test. Agents write these
  # while investigating and leave them behind; twice now the gate has discovered
  # one and run it as a unit, which either reds the tree for nothing or — worse —
  # adds a passing "test" nobody wrote on purpose. They are reported, not
  # silently dropped, so a real test accidentally named `_foo.gd` is visible.
  case "$(basename "$gd")" in
    _*) SKIPPED_SCRATCH+=("$gd"); continue ;;
  esac
  ALL_UNITS+=("A|$gd")
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

# Lane C: every script anywhere in the project that declares a self-check OR
# implements one. Both searches are over the tree, not over a directory this
# script names, so a new app in a new folder is found without editing anything
# here — and so an app whose declaration was deleted is still found, by the
# self-check it still has.
#
# The implementation search skips tests/: that tree is lanes A and B, where
# speaking the verdict language is what a unit is supposed to do and every one
# of them is already collected above. Lane C is for apps, which live elsewhere.
# Declarations are still honoured wherever they are written.
while IFS= read -r gd; do
  [ -n "$gd" ] || continue
  gd="${gd#./}"
  decl="$(unit_selfcheck "$gd")"
  bad() { ALL_BAD_SELFCHECK+=("$gd"$'\t'"$1"$'\t'"$decl"); }

  # No usable declaration in the header. Whether that is a self-check that just
  # went quiet or a script with nothing to do with lane C is not the marker's
  # word to give — it is decided by the other half of the pairing.
  if [ -z "$decl" ]; then
    if grep -q 'gate-selfcheck:' "$gd"; then
      bad "a \`gate-selfcheck:\` marker is present but not as \`## gate-selfcheck: <scene> -- <flags>\` in the first 40 lines"
    elif script_implements_selfcheck "$gd"; then
      bad "implements a self-check verdict but no \`## gate-selfcheck:\` line declares it — a self-check does not leave the gate by having its marker deleted"
    fi
    continue
  fi

  read -ra parts <<<"$decl"   # split on whitespace, no globbing
  scene="${parts[0]:-}"
  case "$scene" in
    res://*.tscn) ;;
    *) bad "scene must be a res:// .tscn path, got \"$scene\""; continue ;;
  esac
  rel="${scene#res://}"
  if [ ! -f "$rel" ]; then
    bad "declared scene does not exist: $scene"; continue
  fi
  if [ "${parts[1]:-}" != "--" ]; then
    bad "missing the literal \`--\` separator after the scene"; continue
  fi
  if [ "${#parts[@]}" -lt 3 ]; then
    bad "no self-check flag after \`--\` — nothing would run"; continue
  fi
  if ! script_implements_selfcheck "$gd"; then
    bad "declares a self-check but prints no verdict — the marker belongs in the script that reports the outcome, so that deleting one is not a way to lose the other"
    continue
  fi
  if [ -n "${SELFCHECK_ARGS[$rel]+set}" ]; then
    bad "$scene is already declared by ${SELFCHECK_GD[$rel]}"; continue
  fi
  SELFCHECK_ARGS["$rel"]="${parts[*]:1}"
  SELFCHECK_GD["$rel"]="$gd"
  ALL_UNITS+=("C|$rel")
done < <({
           # declares one (loosely matched, so a marker moved out of the header
           # or otherwise mangled is still seen and still reported)
           grep -rIl --include='*.gd' \
             --exclude-dir=.godot --exclude-dir=.gate --exclude-dir=.probe --exclude-dir=.git \
             'gate-selfcheck:' . 2>/dev/null
           # ...or implements one, declaration or no declaration
           grep -rIlE --include='*.gd' \
             --exclude-dir=.godot --exclude-dir=.gate --exclude-dir=.probe --exclude-dir=.git \
             --exclude-dir=tests \
             "$SELFCHECK_IMPL_RE" . 2>/dev/null
         } | sed 's|^\./||' | sort -u)

# The script that declares a unit, whatever lane it is in.
unit_script() {
  # $1 = lane, $2 = path
  case "$1" in
    B) echo "${2%.tscn}.gd" ;;
    C) echo "${SELFCHECK_GD[$2]}" ;;
    *) echo "$2" ;;
  esac
}

# Disjointness, checked rather than assumed. Two units with the same basename
# share $OUT_DIR/logs/<name>.log and would overwrite each other's evidence —
# and a results row would name a unit ambiguously. That is a gate defect, so it
# stops the run instead of producing numbers nobody can trace.
DUP="$(for u in "${ALL_UNITS[@]:-}"; do
         [ -n "$u" ] || continue
         n="$(basename "${u#*|}")"; echo "${n%.*}"
       done | sort | uniq -d)"
if [ -n "$DUP" ]; then
  echo "gate: NAME COLLISION — these unit names appear in more than one lane:" >&2
  echo "$DUP" | sed 's/^/  /' >&2
  echo "gate: they would share a log file. Rename one before running." >&2
  exit 2
fi

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

# Broken lane C declarations obey the same filters as everything else — a run
# narrowed to one test must not report a failure that run was never asked about.
# A malformed marker has no valid scene path, so it is matched on the declaring
# script and on the text of the declaration itself.
BAD_SELFCHECK=()
case "$LANE_FILTER" in
  *C*)
    for entry in "${ALL_BAD_SELFCHECK[@]:-}"; do
      [ -n "$entry" ] || continue
      hay="${entry%%$'\t'*} ${entry##*$'\t'}"
      if [ "$#" -eq 0 ]; then
        BAD_SELFCHECK+=("$entry")
      else
        for filter in "$@"; do
          if [[ "$hay" == *"$filter"* ]]; then BAD_SELFCHECK+=("$entry"); break; fi
        done
      fi
    done
    ;;
esac

if [ "${#UNITS[@]}" -eq 0 ] && [ "${#BAD_SELFCHECK[@]}" -eq 0 ]; then
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
  gd="$(unit_script "$lane" "$path")"
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
C_COUNT="$(count_lane C)"

echo "gate: run $RUN_ID · driver=$DRIVER · ${#RUN_UNITS[@]} tests (A:$A_COUNT script · B:$B_COUNT scene · C:$C_COUNT app) · jobs=$JOBS · timeout=${TIMEOUT}s"
for entry in "${BAD_SELFCHECK[@]:-}"; do
  [ -n "$entry" ] || continue
  rest="${entry#*$'\t'}"
  echo "gate: BAD gate-selfcheck in ${entry%%$'\t'*} — ${rest%%$'\t'*}"
done
[ "$NO_SKIP" = "1" ] && echo "gate: GATE_NO_SKIP=1 — capability skips disabled, every matched unit runs"
if [ "${#SKIPPED_CAP[@]}" -gt 0 ] && [ "$AUDIT" = "0" ]; then
  echo "gate: GATE_AUDIT_SKIPS=0 — ${#SKIPPED_CAP[@]} 'cannot run here' claim(s) will NOT be checked this run"
fi
for s in "${SKIPPED_STALE[@]:-}"; do
  [ -n "$s" ] && echo "gate: skipping STALE scene $s (sibling script is 'extends SceneTree'; a Node cannot take it)"
done
for s in "${SKIPPED_SCRATCH[@]:-}"; do
  [ -n "$s" ] && echo "gate: skipping SCRATCH probe $s (leading underscore; rename it to make it a test)"
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
  # $2 = tag. Empty for the real run. "audit" for a skip-audit re-run, which
  # gets its own log and its own results file so it can neither clobber nor be
  # mistaken for the real thing. Everything else about the run is identical —
  # the audit has to be scored by the same rules or it proves nothing.
  local tag="${2:-}"
  local lane="${unit%%|*}"
  local path="${unit#*|}"
  local name; name="$(basename "$path")"; name="${name%.*}"
  local gd; gd="$(unit_script "$lane" "$path")"
  # Lane C carries the app's declared arguments. They are whitespace-separated
  # tokens by definition of the marker format; %q keeps the inner `bash -c`
  # from re-splitting or globbing them.
  local extra=""
  if [ "$lane" = "C" ]; then
    local a declared=()
    read -ra declared <<<"${SELFCHECK_ARGS[$path]}"
    for a in "${declared[@]}"; do extra+=" $(printf '%q' "$a")"; done
  fi
  local log="$OUT_DIR/logs/$name.log"
  local results="$OUT_DIR/results.tsv"
  local budget="$TIMEOUT"
  if [ -n "$tag" ]; then
    log="$OUT_DIR/logs/$name.$tag.log"
    results="$OUT_DIR/$tag.tsv"
    budget="$AUDIT_TIMEOUT"
  fi
  local start; start=$(date +%s)

  timeout "$budget" bash -c "$(declare -f godot_run); GODOT='$GODOT' DRIVER='$DRIVER' godot_run '$lane' 'res://$path'$extra" \
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

  # Lanes B and C only: exited clean but never declared an outcome. Lane A is
  # left alone here — several of its oldest members (probes, captures, smokes)
  # pass without printing anything a regex can recognise, and demoting those to
  # NOTRUN would be a fabricated red. Lane C has no such history: a self-check
  # whose entire purpose is to report has not passed by staying silent, and a
  # flag that never reached the app looks exactly like that.
  if [ "$code" -eq 0 ] && [ "$lane" != "A" ] && [ "$spoke" -eq 0 ]; then
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

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$status" "$lane" "$name" "${elapsed}s" "$noise" "$log" >>"$results"
  local flag=""; [ "$noise" -gt 0 ] && flag=" (${noise} script errors)"
  local mark="  "; [ -n "$tag" ] && mark="  $tag "
  printf '%s%-11s %s  %-44s %4ss%s\n' "$mark" "$status" "$lane" "$name" "$elapsed" "$flag"
}
export -f godot_run

: >"$OUT_DIR/results.tsv"

# A unit whose declared requirement has no probe never runs and never passes.
# A self-check declaration that does not hold up never runs and never passes.
# Mangling the marker must not be a way to make a unit vanish.
for entry in "${BAD_SELFCHECK[@]:-}"; do
  [ -n "$entry" ] || continue
  gd="${entry%%$'\t'*}"; rest="${entry#*$'\t'}"; reason="${rest%%$'\t'*}"
  name="$(basename "$gd")"; name="${name%.*}"
  printf 'FAIL(selfcheck)\t%s\t%s\t0s\t0\t%s\n' "C" "$name" "$gd: $reason" >>"$OUT_DIR/results.tsv"
  printf '  %-11s %s  %-44s %4ss  (bad gate-selfcheck: %s)\n' "FAIL(selfck)" "C" "$name" 0 "$reason"
done

for entry in "${BAD_REQUIRE[@]:-}"; do
  [ -n "$entry" ] || continue
  lane="${entry%%|*}"; rest="${entry#*|}"
  path="${rest%|*}"; token="${rest##*|}"
  name="$(basename "$path")"; name="${name%.*}"
  printf 'FAIL(cap)\t%s\t%s\t0s\t0\t%s\n' "$lane" "$name" "unknown gate-requires: $token" >>"$OUT_DIR/results.tsv"
  printf '  %-11s %s  %-44s %4ss  (unknown gate-requires: %s)\n' "FAIL(cap)" "$lane" "$name" 0 "$token"
done

for u in "${RUN_UNITS[@]:-}"; do
  [ -n "$u" ] || continue
  run_one "$u" &
  while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n 2>/dev/null || true; done
done
wait

# ---- skip audit ------------------------------------------------------------
# See point 8 in the header. A "cannot run here" is a claim about the box, and
# an unfalsifiable claim is worth nothing — the token a test declares is a
# comment, correlated with nothing the test does. So the gate falsifies it by
# experiment: re-run every unit it skipped, and if one PASSES, the marker was
# excluding a working test and the whole run is RED.
#
# Runs after the real units, not alongside them, so the audit never competes
# with the run whose numbers actually matter.
FALSE_SKIP=()   # "<lane>|<path>|<token>" — skipped, then passed anyway
: >"$OUT_DIR/audit.tsv"

audit_row() {
  # $1 = unit name, $2 = column (1 status, 4 elapsed). Empty if not audited.
  awk -F'\t' -v n="$1" -v c="$2" '$3 == n { print $c; exit }' "$OUT_DIR/audit.tsv"
}

if [ "${#SKIPPED_CAP[@]}" -gt 0 ] && [ "$AUDIT" != "0" ]; then
  echo
  echo "gate: SKIP AUDIT — re-running ${#SKIPPED_CAP[@]} skipped unit(s) with the skip lifted."
  echo "gate:   a skipped unit that PASSES here is a false claim and fails the gate."
  for entry in "${SKIPPED_CAP[@]}"; do
    [ -n "$entry" ] || continue
    lane="${entry%%|*}"; rest="${entry#*|}"
    path="${rest%|*}"
    run_one "$lane|$path" audit &
    while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n 2>/dev/null || true; done
  done
  wait
  for entry in "${SKIPPED_CAP[@]}"; do
    [ -n "$entry" ] || continue
    rest="${entry#*|}"; path="${rest%|*}"
    name="$(basename "$path")"; name="${name%.*}"
    [ "$(audit_row "$name" 1)" = "PASS" ] && FALSE_SKIP+=("$entry")
  done
fi

is_false_skip() {
  for e in "${FALSE_SKIP[@]:-}"; do [ "$e" = "$1" ] && return 0; done
  return 1
}

# Skip rows are written only now: whether a skip is an honest SKIP or a
# FAIL(false-skip) is not known until the audit has answered.
for entry in "${SKIPPED_CAP[@]:-}"; do
  [ -n "$entry" ] || continue
  lane="${entry%%|*}"; rest="${entry#*|}"
  path="${rest%|*}"; token="${rest##*|}"
  name="$(basename "$path")"; name="${name%.*}"
  if is_false_skip "$entry"; then
    # Elapsed and script-error noise are the audit run's — that run is the only
    # evidence there is about this unit, so the row must point at it.
    printf 'FAIL(false-skip)\t%s\t%s\t%s\t%s\t%s\n' \
      "$lane" "$name" "$(audit_row "$name" 4)" "$(audit_row "$name" 5)" \
      "$OUT_DIR/logs/$name.audit.log" >>"$OUT_DIR/results.tsv"
  else
    printf 'SKIP\t%s\t%s\t0s\t0\t%s\n' "$lane" "$name" "$OUT_DIR/probes/$token.log" >>"$OUT_DIR/results.tsv"
  fi
done

# ---- report ----------------------------------------------------------------
sort -k2,2 -k3,3 -o "$OUT_DIR/results.tsv" "$OUT_DIR/results.tsv"
# A false skip is not a skip. It is a unit the gate proved it can run, so it
# counts as a unit that ran — and failed.
false_skips=${#FALSE_SKIP[@]}
skipped=$(( ${#SKIPPED_CAP[@]} - false_skips ))
total=$(( ${#RUN_UNITS[@]} + ${#BAD_REQUIRE[@]} + ${#BAD_SELFCHECK[@]} + false_skips ))
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
[ "$false_skips" -gt 0 ] && skip_note="$skip_note · $false_skips FALSE SKIP"
echo "gate: $passed/$total passed$skip_note · $noisy with script-error noise · results in $OUT_DIR"
lane_line A "--script"
lane_line B "scene"
lane_line C "app self-check"

# Skips are never silent: every one names the unit, the capability it declared,
# the probe expression that answered NO on this box, and what happened when the
# gate re-ran it anyway.
if [ "$skipped" -gt 0 ]; then
  echo "gate: SKIPPED — declared a capability this box does not have"
  for entry in "${SKIPPED_CAP[@]}"; do
    is_false_skip "$entry" && continue
    lane="${entry%%|*}"; rest="${entry#*|}"
    path="${rest%|*}"; token="${rest##*|}"
    name="$(basename "$path")"; name="${name%.*}"
    echo "  [$lane] $name — gate-requires: $token"
    echo "        probe: $(capability_expr "$token") → NO   ($OUT_DIR/probes/$token.log)"
    if [ "$AUDIT" = "0" ]; then
      echo "        audit: NOT RUN (GATE_AUDIT_SKIPS=0) — nothing checked this claim this run"
    else
      echo "        audit: re-ran it anyway → $(audit_row "$name" 1) in $(audit_row "$name" 4) — claim holds   ($OUT_DIR/logs/$name.audit.log)"
    fi
  done
  echo "  These units did not run and did not pass. Re-run with GATE_NO_SKIP=1 to make them run anyway."
fi

# A skip that passes when forced is the failure mode this whole mechanism was
# built to prevent, so it gets the loudest block in the report and its own
# instructions. There is no honest reading of it: the box can run the test.
if [ "$false_skips" -gt 0 ]; then
  echo "gate: FALSE SKIP — declared 'cannot run here', then PASSED when the gate re-ran it"
  for entry in "${FALSE_SKIP[@]}"; do
    lane="${entry%%|*}"; rest="${entry#*|}"
    path="${rest%|*}"; token="${rest##*|}"
    gd="$(unit_script "$lane" "$path")"
    name="$(basename "$path")"; name="${name%.*}"
    echo "  [$lane] $name — gate-requires: $token"
    echo "        audit: PASS in $(audit_row "$name" 4)   ($OUT_DIR/logs/$name.audit.log)"
    echo "        The marker is excluding a working test. Delete the"
    echo "        '## gate-requires: $token' line from $gd — or, if the test really"
    echo "        does need something this box lacks, name the capability it actually"
    echo "        needs and add its probe to capability_expr() in tools/gate.sh."
  done
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
    elif [ "$status" = "FAIL(selfcheck)" ]; then
      echo "      $log"
      echo "      the app's self-check and its declaration must agree. Put this line in"
      echo "      the header of the script that prints the verdict:"
      echo "        ## gate-selfcheck: res://scenes/apps/<app>.tscn -- --<flag>"
      echo "      If the app is meant to have no self-check any more, remove the verdict"
      echo "      it prints too — a line of comment is not how a unit leaves the gate."
      continue
    elif [ "$status" = "FAIL(false-skip)" ]; then
      echo "      it skipped, then passed when re-run — see the FALSE SKIP block above"
      continue
    fi
    grep -E 'SCRIPT ERROR|Parse Error|ERROR|FAIL|assert' "$log" 2>/dev/null | head -5 | sed 's/^/      /'
  done
  echo
  echo "gate: RED"
  exit 1
fi

if [ "$skipped" -gt 0 ] && [ "$AUDIT" = "0" ]; then
  echo "gate: GREEN · $skipped unit(s) claimed they cannot run here and NOTHING CHECKED THAT CLAIM"
  echo "gate:         (GATE_AUDIT_SKIPS=0). This run does not prove the skips are honest."
elif [ "$skipped" -gt 0 ]; then
  echo "gate: GREEN · $skipped unit(s) could not run here — audited, claim holds, see SKIPPED above"
else
  echo "gate: GREEN"
fi
exit 0
