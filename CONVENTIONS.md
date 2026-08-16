# CONVENTIONS.md — how work gets done here

`AGENTS.md` is the law for **what the code may look like**.
`REALITY.md` is the record of **how this project lies to itself** — read it before you
claim anything, and treat its standing orders as binding.
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

> ### ⚠ "SAME INPUT JSON IN, SAME PNG OUT" WAS FALSE FOR TEN OF THIRTY RIGS — SURVEYED 2026-08-16
>
> Every capture rig under `tests/` was run twice with no code change and the frames
> byte-compared. **Ten moved.** `STATE.md` carries the table, the three causes and the
> claims that were argued from a diff of one of them. Two things belong here, because
> they are rules about how work moves and not facts about one rig:
>
> **1. A pair of back-to-back runs cannot show a rig reproducible.** `WorldClock` runs a
> **24-REAL-MINUTE** game day off `Time.get_unix_time_from_system()` and `ShipLighting`
> rescales every light on a spawned vessel from it, so two runs twelve real minutes
> apart are twelve GAME HOURS apart. `_starter_28m_shot` measured **0.0000% over 15
> frames** back to back and its frames still differ from the committed ones by up to
> 10% once the clock is pinned. **Use `tools/repro.sh`, which waits 780 s between the
> two runs by default, and do not quote a `REPRO_GAP=0` result as reproducibility.**
>
> **2. A capture rig must pin the clock and settle on the draw.** `tests/support/capture_clock.gd`:
> `pin()` stops the clock and fixes `time_of_day`; `settle()` awaits N frames **then**
> `RenderingServer.frame_post_draw`. Every byte-stable rig in this repo already awaited
> `frame_post_draw`; every unstable one awaited `process_frame` and grabbed a draw out,
> which shows up as a one-pixel outline around every silhouette edge. A new rig copied
> from an existing one must copy both, and copying `vessel_render_capture` without them
> is exactly how the nine scratch rigs lost it.
>
> **3. A rig that cannot be made reproducible says so in its own header AND in what it
> prints.** `ocean_wake_visual_capture` photographs a sea whose phase comes from
> `Time.get_ticks_msec()`; it now prints `THIS FRAME IS NOT REPRODUCIBLE AND MUST NOT BE
> DIFFED` on every run. A capture that cannot be compared is still worth looking at; it
> is worth nothing in a diff, and the two must not be confused.
- A capture is evidence, not an assertion. Pair every capture with at least one
  machine-checkable claim in a gate test (node counts, AABB extents, token usage,
  no-overlap, hit-target sizes). "It looks right" is not a test result.
- Never commit `.gate/` or `.probe/` (both gitignored).

---

## 3a. Scale — read this before authoring any plan

### Settled, 2026-08-09, FOR THE PHYSICS AND GEOMETRY LAYER. One world unit is one metre.

**The player is 1.8 m** (`scenes/shared/player.tscn`, capsule 1.8, eye 1.6, step 0.45, jump 0.9
— all 1× human). **Hull `loa_m` / `beam_m` / `depth_m` are real metres.** `hull_28x10` is a
**28 × 10 m vessel** — its record lives in `HullRegistry.FISHING_TRAWLER_SMALL`, not in
`resources/data/vessels/hulls/catalog.json`, whose smallest hull is 70 m. Size everything
against the figure.

> ### ⚠ "NOTHING IS DOUBLE-SCALE" IS FALSE OF THE PLAYER-FACING LABEL LAYER — MEASURED 2026-08-15
>
> That heading used to end *"Nothing is double-scale"*, and the paragraph below used to end
> *"Labels and comments were corrected to match the data; no physics was touched."* The physics
> half is true. The labels half is not: the correction landed in the JSON catalog's `notes` and
> in `HullRegistry`'s `display` string, and in **no other label**.
>
> Still live, measured by calling the functions (`tests/_doc_claim_audit.gd`):
>
> | Site | Measured |
> |---|---|
> | `ShipClass.METRIC_SCALE` | **2.0**, with the header *"World hulls and berth clearances use 2× those values"* |
> | `ShipClass.DISPLAY_METRE_SCALE` | **0.5** |
> | `ShipClass.format_display_dimensions(28, 10)` | **`"14.0 × 5.0 m"`** |
> | `HullCatalog._normalize` | **overwrites** the authored `display` with the halved string on every load |
> | Player-facing catalog labels | hull_150x32 → `"75.0 × 16.0 m"`, hull_120x28 → `"60.0 × 14.0 m"`, hull_70x18 → `"35.0 × 9.0 m"` |
> | `VesselSpawn.LEGACY_STOCK_DISPLAY_NAMES` | renames a captain's `"28x10 Cargo"` to `"14x5 Cargo"` |
> | `scripts/ship/hull_catalog.gd:5` | still carried the exact *"dimensions are in-world metres (2× real)"* note this section says was deleted (corrected 2026-08-15) |
>
> And `tests/ship_display_units_test` asserts all of it **green**, in lane B, today — its own
> header states *"`hull_28x10` is 28 x 10 CELLS — a 14.0 x 5.0 m boat"*. So the repo contains two
> passing tests that disagree about how long the starter boat is, which is REALITY.md §4a: the
> disagreement is the finding, do not average it.
>
> **Which side is wrong is an owner decision, not a slip to patch.** The five-field argument
> below says the hull is really 28 × 10 m, so the display layer is the leftover — but changing it
> renames every vessel a player owns. Nobody has decided. Until someone does, **do not write
> "nothing is double-scale" without naming the layer**: geometry, physics, grids and berth
> geometry are 1×; the shipyard label, the vessel name and `ShipClass`'s length table are 0.5×.

**Deck-grid cells are 0.5 m — two cells per metre.** That is a *build resolution*, not a size:
a 28 m hull is 56 cells long. A 1 m grid was too coarse to build detail on, which is the only
reason this constant exists. Measured through `DeckGrid.from_hull` 2026-08-15: 28 m → 56 cells,
70 → 140, 120 → 240, 150 → 300, and a 30 × 24 m deck is **60 × 48**.

`half_beam` and `half_loa` derive from metres (`width × CELL_M × 0.5`), so the factors cancel
and changing `DECK_CELL_M` moves no geometry in the five collections that are authored in
metres — `walls`, `decks`, `stairs`, `edges`, `items`. Fixtures re-rendered byte-identical
(same MD5) after halving it.

**That is now narrower than the sixth collection.** `pieces[]` did not exist when that run was
made. A placement resolves through `PieceKit.node_plan` / `StructurePlan.piece_node_plan`, which
are literally `cell × DECK_CELL_M`, so a piece-built plan moves with this constant exactly as a
brick does. Measured on `probe_piece_house.json` by doubling the node term: the resolved item
AABB went from position (2.0, 0.0, 12.0) size (6.0, 5.5, 13.5) to position (4.0, 0.0, 24.0) size
(12.0, 11.0, 27.0) — exactly 2×, in all six numbers. Three shipped fixtures carry pieces
(`probe_piece_house` 58 placements, `probe_piece_trawler` 49, `probe_piece_tug` 34).

Separately, `resources/data/parts/structure_pieces.json` declares `cell_m: 0.5` and
`PieceKit.parse_document` compares it against `WorldUnits.DECK_CELL_M`. Doctoring that field to
1.0 produces the error *"the kit and the grid must agree"* — **but the kit still parses and
still returns all six pieces**. The guard reports; it does not stop.

> ### ⚠ THAT CLAIM USED TO BE WRITTEN WITHOUT THE WORD "STRUCTURE-PLAN", AND IT WAS FALSE
>
> It said *"changing `DECK_CELL_M` moves no geometry… zero new gate failures against a 1.0
> control"*. It is true for structure plans, whose every dimension is in metres. It is **false
> for BRICKS**: `BrickCatalog.size_m` is `footprint × CELL_M`, so halving the constant in
> `a70bdbc` **halved every brick in the game**.
>
> Measured, not inferred: `shipyard_editor_ui_test` failed on a railing post whose z moved from
> **−0.472 to −0.222** — and a `railing` brick is now **0.5 m tall with a 0.44 m post**, which is
> knee-high beside the 1.8 m figure this very section says to size everything against.
>
> The "zero new gate failures" half was also wrong, and it took months to surface because the
> failure it caused was read as an ordinary red in a stale known-red list.
>
> **Whether 0.5 m is the right BRICK cell is an open product decision** — it is a real question
> about the old LEGO-brick system, not a slip to patch. Nobody has looked at a rendered brick
> vessel beside the figure. Until someone does, do not repeat the byte-identical claim without
> the qualifier.
>
> **The measured consequence, 2026-08-15.** `BuildingGrid.CELL_M` is **1.0** and steps
> `cell_center_local` by 1.0 m. `BrickCatalog.size_m("block")` — footprint 1×1×1 — draws
> **(0.5, 0.5, 0.5)**. A factor of exactly **2.000**: every land blueprint lays half-size bricks
> on a full-size lattice, so no blueprint data produces a solid wall. `BrickCatalog` also has
> **64 live definitions**, not the "currently WIPED" state `AGENTS.md` claimed until today.
>
> The general lesson is the one this file exists for: a doc line that says a change is safe is a
> claim, and a claim that was verified **on one subsystem** is not a claim about the codebase.

**Anything under 0.5 m cannot sit on the grid at any resolution** — cleats, fairleads, chocks,
blocks, sheaves, light fixtures, stanchions. Those are free-positioned items with float
coordinates, which is why the item placement model does not snap.

### How this was misread, twice, and how it was settled

The catalog carried a note reading "Dimensions are in-world metres (2× real)" and displayed
`hull_28x10` as "14.0 × 5.0 m". Both were wrong — leftovers from a scaling decision that never
landed — and between them they convinced two readers in a row that the world was double-scale.
I then copied the mistake into this file, where every agent reads it.

Five independent fields say 28 m and only a label and a comment said 14 m (these live in
`HullRegistry.FISHING_TRAWLER_SMALL`, verified 2026-08-15 — `hull_28x10` is **not** in the JSON
hull catalog, so do not go looking for them there):

| Field | `hull_28x10` | a 14 × 5 m boat | a 28 × 10 m boat |
|---|---|---|---|
| `depth_m` | 5.6 | ~2.5–3 | ~5.5 |
| `displacement_t` | 256 | 41–50 | 325–398 |
| `default_shaft_power_kw` | 1871 | ~300–500 | ~1500–1900 |

`tests/vessel_registration_test.gd` had been calling it the *"28×10 m starter"* the whole time.
**Two labels and one comment were corrected; the machinery that produces the rest was not** —
see the boxed warning above. `HullRegistry.display` and the JSON `notes` field now read 28 × 10;
`ShipClass.format_display_dimensions`, `HullCatalog._normalize`,
`VesselSpawn.LEGACY_STOCK_DISPLAY_NAMES` and `hull_catalog.gd`'s own header still halved
everything until this audit, and the first three still do. No physics was touched, then or now.

**The lesson, since it will recur: a display string and a comment are the two softest artefacts
in a codebase.** When they disagree with five numeric fields and a test's own wording, they are
what is wrong. Check the load-bearing data before believing the label — and before writing the
label into a conventions file that every agent treats as ground truth.

### The rule that survives regardless

**Every vessel capture carries a 1.8 m figure on deck** (`tests/vessel_render_capture.gd`).
A capture without one has no absolute scale, and a wrongly-proportioned build looks entirely
plausible. Check the figure is actually *visible* — the first placement put it inside the
wheelhouse, where it rendered perfectly and appeared in no frame.

**When a proportion looks wrong to a person, believe them and go measure.** Every number the
gate records agreed with every other, and they were all wrong together. It took a human looking
at a picture.

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
