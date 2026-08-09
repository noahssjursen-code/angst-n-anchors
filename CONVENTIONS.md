# CONVENTIONS.md — how work gets done here

`AGENTS.md` is the law for **what the code may look like**.
This file is the law for **how work moves**: the gate, the orchestration loop, the
commit discipline, and the container facts that cost real time to discover.

Read this before `STATE.md`. Read both before touching anything.

---

## 0. The one-paragraph version

Work is run as waves of subagents driven by an orchestrator. Subagents plan, edit,
and adversarially critique; the orchestrator verifies against the gate and commits.
A wave is not finished because an agent says it is finished — it is finished when
`tools/gate.sh` exits 0 and the claim has survived a critic whose job was to break it.
Nothing is real until it is pushed; the container is ephemeral.

---

## 1. The gate

```bash
tools/gate.sh            # every headless test; exit 0 == green
tools/gate.sh structure  # filter by filename substring
```

The tree is green **only** when `tools/gate.sh` exits 0. Not when a test you ran by
hand passed. Not when the thing looked right in a screenshot.

Useful knobs: `GATE_JOBS` (default = half the cores), `GATE_TIMEOUT` (default 240s),
`GATE_DRIVER=headless` (the degraded driver — for comparison only, never the gate),
`GATE_OUT` / `GATE_RUN_ID`.

Results land in a **run-unique** `.gate/<timestamp>-<pid>/`, with `.gate/latest`
symlinked to the newest. This is deliberate: several agents and the orchestrator can
be running the gate at once, and an earlier version of this script wiped a live run
with `rm -rf`. Do not reintroduce a shared output path.

Two consequences, both learned the hard way:

- **`.gate/latest` is not yours.** Any concurrent run repoints it. To follow your own
  run, capture the id from the runner's first line (or set `GATE_RUN_ID`) and read
  `.gate/<that-id>/results.tsv`. Watching `latest` will silently show you someone
  else's numbers.
- **Do not tell a recon/analysis agent that the gate exists** unless you want it run.
  Agents helpfully run it, and on 4 cores that turns one 15-minute baseline into
  three 40-minute ones. Name the gate in a wave prompt only when running it is the job.
- **Never background a gate run with a bare `&`.** The shell that launched it exits
  when the tool call returns and takes the run with it — a 25-minute run died at 57 of
  82 units that way, with no summary line to show it had been truncated. Use the Bash
  tool's own `run_in_background`, which survives the call and reports completion.

### Reading the results

`results.tsv` columns are `status · lane · name · elapsed · script-error-count · log`.

- `PASS` / `FAIL(n)` — the unit ran and declared an outcome.
- `TIMEOUT` — killed at `GATE_TIMEOUT`. **Do not read this as "slow" without checking.**
  A failing `assert()` used to idle the process here; that shape is gone now that the
  suite is off bare `assert()`, but any future code that stalls before `quit()` recreates it.
- `NOTRUN` — the unit never declared an outcome. A *verdict outranks a load-failure
  banner*: Godot prints `Failed to load script "res://…"` during the transient compile
  cascade the `--script` lane provokes and then runs the script anyway, so that banner
  alone never means NOTRUN. Getting this wrong reported a `17/20 FAILED` as "never ran"
  and five passing tests as un-run.
- The script-error column is **noise, not failure** — it is how autoload and driver
  regressions announce themselves. A test can be green with 27 script errors in its log.

### What the gate covers, and what it does not

- **Covers:** the `extends SceneTree` tests under `tests/` — the ones runnable from a
  command line.
- **Does not cover:** the `extends Node` / `Node3D` tests that need a `.tscn`, the
  showcase scenes, or anything visual. Those are captured, not asserted (§3).

Both numbers live in `STATE.md`. If you add a test, say which side of that line it
lands on.

---

## 2. Container facts (verified, do not relitigate)

These were established empirically in this container. They are written down so no
future wave burns an hour rediscovering them.

| Fact | Detail |
|---|---|
| Godot | 4.6-stable at `/usr/local/bin/godot`, installed by `.claude/hooks/session-start.sh`. On a fresh container: `CLAUDE_CODE_REMOTE=true .claude/hooks/session-start.sh` |
| Import | `godot --headless --import` completes clean, 0 errors. Do it once per fresh container before anything else. |
| **`--headless` is broken for this project** | Two independent failures, both measured. (1) Autoload singletons are **not registered**, so any test that transitively preloads a script naming `WorldGateway` / `LocalPlayerView` dies with `Compile Error: Identifier not found`. (2) `await RenderingServer.frame_post_draw` **never returns** — the dummy driver never draws a frame — so every render-dependent test hangs to timeout. |
| **The working invocation** | `xvfb-run -a --server-args="-screen 0 1280x720x24" godot --rendering-driver opengl3 --audio-driver Dummy --script res://<path>.gd` |
| Renderer under xvfb | Mesa **llvmpipe** (LLVM 20.1.2), GL 4.5 core. Software rasterisation — correct pixels, slow. |
| Vulkan | `libvulkan.so.1` is present but there is **no ICD** in `/usr/share/vulkan/icd.d/`. Forward+ / Vulkan does **not** run here. `opengl3` (Compatibility) is the only renderer available, and it is not the renderer the game ships on. Treat captures as layout/colour evidence, not as shader-accurate previews. |
| Audio | No ALSA device. Always pass `--audio-driver Dummy` or eat a wall of ALSA errors. |
| Capture works | A probe rendering a `ColorRect` + lit `BoxMesh` under xvfb+opengl3 produced a 1280×720 PNG with real, correctly-coloured pixels. Capture is a solved problem; see §3. |
| **`--script` breaks autoloads at COMPILE time, not runtime** | Corrected 2026-08-09, was overstated before. Autoload *instances* exist under `--script` and resolve fine at runtime via `root.get_node("FreightService")` — measured. What fails is the **compile-time global identifier**: a script that names `WorldGateway` or `LocalPlayerView` bare dies with `Identifier not found`, and that failure cascades to everything preloading it. So the split is not "autoloads are absent"; it is "you may look them up, you may not name them". Tests that need bare identifiers run as a **scene** — `godot <driver flags> res://tests/<x>.tscn`. This is the two-lane split in §1. |
| **A failing `assert()` idles the SceneTree lane** | In an `extends SceneTree` script a failed `assert()` aborts the enclosing function but lets the caller continue — so `quit()` is never reached and the process sits there until the gate's timeout kills it. **Several gate "TIMEOUT"s were failing assertions, not hangs.** `port_trade_profile_test` timed out at 300 s pre-conversion; converted, it fails honestly in 6 s. Do not read TIMEOUT as "slow" until the file is off bare `assert()`. |
| **4 cores** | `nproc` = 4. Workflow agent concurrency caps at `min(16, cores-2)` = **2**. A 10-agent wave runs five at a time, serially. Size waves for that, and do not run a full gate while a wide wave is in flight — load average hit 14 doing exactly that, and everything crawled. |

---

## 3. Screenshots and visual evidence

Visual work is not reviewable from a diff. Any change to a UI surface, a studio
region, or a baked structure ships with a capture.

- Captures are written under `screenshots/<area>/` and named
  `<surface>__<case>.png` — stable names, so re-running overwrites rather than
  accumulating. A capture whose name changes every run cannot be diffed.
- The capture harness is a `SceneTree` script driven by a **data object**, not by
  clicking. Same input JSON in, same PNG out.
- A capture is evidence, not an assertion. Pair every capture with at least one
  machine-checkable claim in a gate test (node counts, AABB extents, token usage,
  no-overlap, hit-target sizes). "It looks right" is not a test result.
- Never commit `.gate/` or `.probe/` (both gitignored).

---

## 3a. Scale — read this before authoring any plan

**The player is 1.8 world units tall.** `scenes/shared/player.tscn` is a `CapsuleShape3D` of
height 1.8 with the camera at 1.6. Structure Studio's own `_build_scale_mannequin` matches it
and labels it "1.8 m". So for a human, **one world unit is one metre.**

**Hull geometry is not on that scale.** `resources/data/vessels/hulls/catalog.json` says
"Dimensions are in-world metres (2× real)" and displays `hull_28x10` as "14.0 × 5.0 m" — but it
draws it **28 units long**. Stand a 1.8 m player on it and it reads as a **28 m vessel**, not a
14 m one.

**Therefore: size everything against the figure, never against the catalog's display name.**
A superstructure proportioned for the "14 m" label sits on a hull that reads as 28 m and comes
out half the size it should be. That happened — `probe_trawler_bow_bulwark`'s wheelhouse is
~10% of LOA where a real trawler's is nearly double that — and it was invisible in every number
the gate records. It took a human looking at a picture and saying "the wheelhouse looks shorter
than the player".

Consequences:

- **Every vessel capture carries a 1.8 m figure on deck.** `tests/vessel_render_capture.gd`
  adds one; a capture without it has no absolute scale and a wrongly-proportioned build looks
  entirely plausible.
- Check the figure is actually *visible*. The first placement put it inside the wheelhouse — it
  rendered perfectly and appeared in no frame, which is the one failure mode a scale reference
  must not have.
- When a proportion looks wrong to a person, believe them and go measure. The numbers agreed
  with each other and were all wrong together.

## 4. Data objects are the interface

The user-facing requirement for Structure Studio is that **an agent authors a
structure as data and gets back a render plus assertions** — no UI driving.

Therefore:

- `structure_plan_v1` JSON (see `resources/data/structures/demo_workboat.json`) is
  the input contract. Fixtures live beside it.
- Anything the studio can build, the plan format must be able to express, and the
  headless path must be able to bake without a studio instance. If a feature is only
  reachable through a UI callback, that is a bug in the seam, not a limitation.
- New studio features land as: plan schema → baker support → gate test → studio UI.
  In that order. The UI is the last layer, not the first.

---

## 5. Orchestration loop

1. Read `CONVENTIONS.md`, then `STATE.md`.
2. Verify green: run `tools/gate.sh`. If it is red, the milestone is *fixing that*,
   whatever `STATE.md` says next.
3. Spawn the next wave from `STATE.md` → "Next actions". Waves run in parallel.
4. Every substantive claim gets an adversarial critic. Critics are told to **break**
   the claim, not to approve it. A critic that returns "looks good" has failed to do
   its job and its finding is worth nothing.
5. Orchestrator verifies, commits, pushes, updates `STATE.md`.
6. Close the milestone in `STATE.md`; open the next. The work is never "finished".

### Rules for parallel waves

- **One agent owns one file.** Two agents editing the same `.gd` will clobber each
  other — GDScript has no merge driver worth trusting. Partition by file before
  spawning, and write the partition into the wave's prompt.
- Agents that need isolation get `isolation: "worktree"`.
- Agents do **not** commit. The orchestrator commits. One agent's green is not the
  tree's green.
- Agents may run `tools/gate.sh` (it is concurrency-safe now), but the orchestrator's
  run is the one that counts.

---

## 6. Commit discipline

- Branch: `claude/branding-gui-orchestration-hhjb52` in **both** repos.
- Commit and push at **every green checkpoint**. The container is ephemeral;
  uncommitted work does not exist.
- `git push -u origin claude/branding-gui-orchestration-hhjb52`. On network failure
  retry 4× with 2/4/8/16s backoff.
- Commit messages: imperative subject, then what changed and why it is safe.
- Never push to another branch. Never open a PR unless asked.

---

## 7. Documentation drift is a defect

`AGENTS.md` and `ARCHITECTURE.md` are load-bearing — agents act on them. When code
supersedes a doc, the doc changes in the *same commit*. Known drift is tracked in
`STATE.md`, not left in the file to mislead the next wave.

`branding/CLAUDE.md` states the house rule: superseded work gets **deleted**, not
archived. That applies to code and docs alike — but supersession must be *proved*
(no inbound references, no scene, no test), never assumed.
