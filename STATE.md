# STATE.md — Ship construction vocabulary & Structure Studio

Position file for the orchestration loop. Read `CONVENTIONS.md` first.
Rewritten at every checkpoint. If it disagrees with the tree, the tree wins.

- **Branch:** `claude/branding-gui-orchestration-hhjb52` (both repos)
- **Last updated:** 2026-08-09 · reframed after owner direction
- **Milestone:** M0 — Honest instrument · open

---

## The actual goal

Not a rebrand. **A ship building system whose output reads as a real boat and can be
certified, hired out, and sold between players.**

Owner's release-day shape (2026-08-09):

- Players pick a starting **category** — bulk, cargo, passengers, fishing.
- They pick a **starting vessel** (author-made). One or two larger ships come from the
  in-game shipwright.
- Everything after that is a **hull purchase**. The player builds the vessel on it.
- Finished UGC ships get **hired out to NPC workers** or **listed for sale** to other
  players.
- Therefore **every category needs a requirements list** — helm, port/starboard/white
  navigation lights, mooring points, and so on — and a build that fails it is not a ship.

A later server-side visual moderator will review final ship images. Out of scope; the
parts vocabulary should not make it harder.

### Why the old system was dropped

A voxel/lego-brick library stacked layer by layer. It came out **too blocky and rough**.
`StructurePlan` (drawn, not stacked) replaced it. Do not walk back toward stacking.

### The governing constraint

**Detail versus render cost.** Harbours are full of these ships. Every part must bake
into merged surfaces the way `StructureBaker` and `VesselSkinBaker` already do. "Add more
geometry" is not an available answer — that is how the voxel version got rough.

---

## The discovery that shapes M2

The certification system the owner described **already exists**, wired to the dead vocabulary.

`resources/data/vessels/registrations/catalog.json` defines `general_vessel` (inherited
base) plus `fishing_vessel`, `cargo_vessel`, `bulk_vessel`, `passenger_vessel` — the
owner's categories exactly. `scripts/ship/vessel_compliance.gd` (11 KB) implements the
rule engine: `slot_count`, `brick_count`, `brick_side`, `tag_count`, `metric_range`,
`cargo_cells`, `capability`, `capacity`, `equipment_rating_max`, and the bespoke
`white_above_sidelights`.

Already-written rules include: one helm · port light **on the port side** · starboard
light **on the starboard side** · white masthead light(s) **above the sidelights** · ≥4
mooring points · ≥1 bulk hold · exposed catch deck ≥4 cells · ≥4 passenger seats ·
enclosed cabin · ≥1 marked door · per-category `cargo_cells` and `budget_caps`.

**Every rule addresses brick ids and brick tags** (`light_nav_port`, `tag: mooring`) — the
vocabulary that was wiped. `AGENTS.md`: *"Legacy compliance/budgets do not yet apply to
plans — that rework lands with the new vocabulary."*

So: **the parts vocabulary is the reconnection.** Each part must satisfy three masters —
it reads as real, it is a gameplay attach point (`get_bridge_stations()`,
`get_cargo_pads()`, `get_fishing_systems()`), and `VesselCompliance` can count, locate and
rule on it. A part that cannot be validated cannot be in a ship one player sells another.

### Open design fork — resolved, cheap to reverse

`AGENTS.md` lists nav lights and mooring cleats under *"Always on BoatBody (core)"* —
auto-provided. The registration rules require the player to fit them, correctly placed.
Both cannot be true: if automatic, certification is theatre.

**Taken:** nav lights and mooring points become **placeable, positioned, validated parts**.
Auto-fit survives only as a convenience default on author-made starter vessels. Flagged to
the owner; reverse on request.

---

## Verified facts (measured, this container)

| | |
|---|---|
| Godot | 4.6-stable; `--headless --import` clean, **0 errors** |
| Cores | 4 → workflow agent concurrency caps at **2**. Keep waves small. |
| Renderer | xvfb + `opengl3` → Mesa llvmpipe, GL 4.5. **No Vulkan ICD → Forward+ cannot run here** |
| `--headless` | **Unusable as the gate.** No autoloads; `frame_post_draw` never fires → render tests hang |
| `--script` | **Never registers autoloads**, any driver. Autoload-touching tests need the scene lane |
| Tests | 81 files — **58** `extends SceneTree`, **23** `extends Node`/`Node3D`; 24 `.tscn` |

### Proven end to end

`godot --rendering-driver opengl3 res://scenes/apps/structure_studio.tscn -- --studio-probe`
under xvfb exits **0** (`probe ok — context=vessel entities=7`).

A probe that instantiated the studio, loaded `demo_workboat.json`, and saved the viewport
produced a **real 1280×720 PNG of the studio with the plan built in it**. Data object in,
image out, no display, no clicking. **The instrument works** — that is the whole agentic
loop, and it is what M2's reference-matching cycle runs on.

### Gate baseline — 2026-08-09, run `20260809-133513-23960`

**40/58 PASS.** 18 not passing, in three distinct kinds. Measured under load (research
agents were running); the TIMEOUTs in particular need re-measuring on a quiet box.

- **8 TIMEOUT** at 300 s — `building_blueprint_test`, `chart_rewrite_integration_test`,
  `chart_weather_cache_test`, `lighting_material_test`, `ocean_wake_gpu_smoke`,
  `ocean_wake_visual_capture`, `port_perf_cache_test`, `port_trade_profile_test`.
  Mostly render-dependent. Some are probably contention, not hangs — re-measure before
  calling any of them broken.
- **7 NOTRUN** — the test's own script failed to compile, from autoload identifiers missing
  in the `--script` lane: `chart_layer_manager_test`, `harbour_traffic_test`,
  `helm_minimap_test`, `lod_profiles_test`, `onboarding_store_test`,
  `port_layout_visual_capture`, `ship_display_units_test`. These need lane B.
- **3 FAIL** — real assertion failures: `land_field_geography_test`,
  `remote_realtime_join_smoke`, `world_generation_seed_validation`.

This number is *before* the false greens are exposed. 38 files could not fail at all when it
was taken, so the honest baseline will be worse. That is the point of taking it now.

### The false greens

`tests/company_service_test.gd` prints `PASS` and exits **0** with three assertions failing.
Godot's `assert()` does not abort, does not set an exit code, and is compiled out of release
builds. **38 of 81 test files use it.** `tests/support/test_report.gd` is the replacement;
nothing is converted yet.

### Suspected shipping defect (unverified)

`branding/.gdignore` excludes the branding tree, but `BrandTokens` loads
`res://branding/brand/tokens/palette.json` (`brand_tokens.gd:10`) and is its only loader.
If the exporter honours `.gdignore`, a shipped build resolves every token to
`Color.MAGENTA` (`brand_tokens.gd:120`). Verifying needs export templates (~1 GB, not
installed) and a Linux preset (only "Windows Desktop" exists).

---

## Brand-rule audit (measured)

| Rule | Verdict |
|---|---|
| 1 · no hex literals in UI code | **Violated.** 342 raw `Color()` literals across `scripts/ui`, `apps`, `npc`, `port`, `weather`. Worst: `port_layout_graph_visualizer` 65, `shipyard_brick_editor` 38, `building_brick_editor` 31, `structure_studio` 13 |
| 2 · AMBER is marketing-only | **Clean.** 0 occurrences in runtime code |
| 5 · no rounded corners | **Violated in the legacy apps only.** `port_showcase` 6 px, `building_brick_editor` 2–3 px, `shipyard_brick_editor` 2–3 px, `character_customization_showcase` 4 px. Design system and Structure Studio correctly use 0 |
| — | 53 files use the design system |

---

## Owner decisions

| Question | Decision |
|---|---|
| Internal apps in scope | **Structure Studio** (rebuild) and **`vessel_registration_audit`** (rebrand — it is the moderation console for the UGC economy). Legacy brick editors **deleted**. |
| Out of scope | Character/wardrobe authors; mp-server admin web UI. Defects recorded, unworked. |
| Capture fidelity | **Accept GL/llvmpipe captures** as layout/colour/type evidence. No lavapipe. Every capture pairs with a machine-checkable assertion. |
| False greens | **Fix the helper and fix the breakage.** No quarantine list. |

---

## Structure Studio — as found

`scripts/apps/structure_studio.gd` (86 KB) builds scene and UI in code from a one-node
`.tscn`. Tools: SELECT / WALL / ROOM / CORRIDOR / DECK / STAIR / OPENING, undo/redo, build
levels, ghosting, gizmo move, face resize, JSON save/load. `_run_studio_probe()`
(`structure_studio.gd:115`) is the existing headless seam — hardcoded coordinates, private
method calls, no capture.

`structure_plan_v1` (`resources/data/structures/demo_workboat.json`) is the data contract:
`walls[] · decks[] · rooms[] · stairs[] · items[]` plus `format`, `context`, `hull_id`,
`palette`. **`items[]` is empty in every plan in the repo** — there is no parts vocabulary yet.

Against `branding/Angst n Anchors Structure Studio.dc.html` (which specifies the *screen*,
not the parts), the shipped studio is missing: the whole right column (EXPLORER /
PROPERTIES / SURFACE LIBRARY), the bottom consequence strip (PARTS / DRY WEIGHT / EST.
DRAFT / STABILITY / FLOAT TEST), and the left prop TOOLBOX — the left panel is build-level
controls instead. There is also a stray brass bar clipping under the header. The spec's
toolbox lists furniture (barrel, bunk, chair, cleat, crate, helm, lantern, life ring,
locker, shelf, stove, table) — **it does not answer the ship-parts question.**

Hulls are dimension-keyed in `resources/data/vessels/hulls/catalog.json`. **In-world metres
are 2× real**, so `hull_28x10` is a ~14 × 5 m real working boat. Reference matching must
respect that or every comparison is wrong.

---

## Known documentation drift

- `ARCHITECTURE.md` §`scripts/apps/` lists only the two brick editors. Structure Studio absent.
- `AGENTS.md` calls the brick editors "retired" while their scenes and tests still ship.
- `AGENTS.md` "always on BoatBody" vs the registration rules — see the design fork above.
- mp-server `CONTEXT_HANDOFF.md` describes an in-memory position map several rewrites stale.
- mp-server: the SvelteKit admin source is **not in the repo** — 1 816 `node_modules` files and
  `.svelte-kit` build output are committed, but no `package.json`, no routes, one real source
  file. Unbuildable from a clean clone. Out of scope; recorded.

---

## Milestones

### M0 — Honest instrument · OPEN
The loop must be able to fail before it can hone anything.
1. Convert all 38 bare-`assert()` files to `tests/support/test_report.gd`; fix the breakage
   it exposes (`company_service_test` first).
2. Add **gate lane B** — the 23 scene-based tests run as scenes, so autoload-dependent code
   is covered; migrate the 5–6 NOTRUN `--script` tests into it.
3. Re-measure the 6 TIMEOUTs on a quiet box; fix or split whatever is genuinely hung.
4. Fix `land_field_geography_test`.
5. Clean full-gate baseline recorded here.

**Exit:** `tools/gate.sh` green, both lanes, no bare `assert()`, numbers recorded.

### M1 — Vessel render harness · LARGELY DONE
`tests/vessel_render_capture.{gd,tscn}` + `tools/capture.sh`. A `structure_plan_v1` goes in;
four canonical-angle PNGs and 15 machine-checkable claims come out. Runs in the scene lane
(the first worked example of lane B — `VesselSpawn` reaches autoload-naming code).

Views: `profile_port`, `bow_quarter`, `stern_quarter`, `plan`. Camera fits the projected
bounding box against a 35° lens on both axes. Autoload HUD is hidden before shooting.
Asserts the bake stays merged — the demo workboat bakes to **4 mesh instances**, which is the
draw-cost headroom the parts work gets to spend.

Remaining: fold it into `tools/gate.sh` as lane B, and add per-view visual-regression
comparison against a committed baseline.

#### First reading of `demo_workboat` (the M2 starting point)
The hull is genuinely good — sheer, bow rake and flare, boot-top, transom all read correctly.
Everything above the deck is flat grey slabs. Absent: bulwarks, guardrails/stanchions, mast,
funnel or exhaust, a wheelhouse window band, any set-back of the deckhouse from the ship's
side (real boats leave a side deck to walk), rubbing strake, fenders, deck gear. It reads as
a shed on a barge, exactly as predicted, and the captures in `screenshots/studio/` are the
evidence.

### M2 — Ship parts vocabulary · THE MILESTONE
The reference-matching loop:
1. Pick reference working boats per category and the honest matching hull (remember 2×).
2. Author the reference as `structure_plan_v1`, render from canonical angles.
3. State plainly what reads wrong — not "could be improved".
4. Diagnose each fault as a **missing part or missing primitive**. Build it so it bakes
   into merged surfaces.
5. Rebuild the same reference. Compare. Loop until it matches.
6. Every part lands with its compliance identity: tag, slot, or metric that
   `VesselCompliance` can count and locate.

**Exit:** each of the four categories has a reference build that reads correctly and passes
its registration, with captures and gate tests to prove both.

### M3 — Compliance on plans
Reconnect `VesselCompliance` to `structure_plan_v1`. Retire the brick-id rule kinds in
favour of the new vocabulary. `vessel_registration_audit` rebuilt as the moderation console.

### M4 — Studio GUI to spec
The `.dc.html` screen: toolbox, explorer, properties, surface library, consequence strip,
FLOAT TEST. Delete the legacy brick editors. Fix the 342 hex literals and the rounded corners.

---

## Next actions

1. **M0.1** — convert the 38 bare-`assert()` files. Partition by file, one agent per group.
2. **M0.2** — gate lane B for scene tests.
3. Re-run the full gate on a quiet box and record the honest baseline here.
4. Then M1.

## Milestone log

- **M0 — Honest instrument** · open · 2026-08-09
