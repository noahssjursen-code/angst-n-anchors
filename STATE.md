# STATE.md — Ship construction vocabulary & Structure Studio

Position file for the orchestration loop. Read `CONVENTIONS.md` first.
Rewritten at every checkpoint. If it disagrees with the tree, the tree wins.

- **Branch:** `claude/branding-gui-orchestration-hhjb52` (both repos)
- **Last updated:** 2026-08-09 · after the items mechanism landed
- **Milestone:** M2 — parts vocabulary. The five primitives are being built now.

---

## WHERE WE ARE — read this first, the rest of the file is the record

**The loop works.** A `structure_plan_v1` JSON goes in; `tools/capture.sh` bakes it onto its
hull and returns four canonical-angle PNGs plus assertions. No display, no clicking. Five
fixtures live in `resources/data/structures/`; captures under `screenshots/studio/` with stable
names, so `git diff` on an image shows what a change did to the silhouette.

**What is built and verified**

| | |
|---|---|
| Gate | Three lanes — A `--script`, B scene, C app self-check. Capability skips are self-policing: a skipped unit that passes when forced turns the gate red. Scratch probes (`_`-prefixed) are skipped and reported. |
| Tests | Zero bare `assert()` anywhere (38 files converted). `TestReport` fails a run that executed zero checks. |
| Colour | **Free.** The bucket key is material alone, colour rides in vertex data. A 20-colour plan bakes to 4 draw calls, measured on the renderer's own counter. |
| Collision | Diagonal walls collide as drawn, asserted against `PhysicsServer3D` on a real body — not against the baker's dictionaries. |
| Items | Float metres, free yaw + optional pitch/roll, props bag, **host-relative placement** so a fitting follows its host. Part catalog + plan-side compliance measurement exist. |
| Scale | Settled: 1 unit = 1 m, player 1.8 m, deck cells 0.5 m as a *build resolution*. `hull_28x10` is a 28 × 10 m vessel. |

**What is missing, in the order it matters**

1. **The five primitives** — spar, railing run, wire, sloped plate, sheer band. *In flight.*
   Without them a hull is a shed on a barge; `references/COMPONENTS.md` maps 344 components onto
   them.
2. **Geometry for `items[]`** — the mechanism exists, nothing draws the parts yet.
3. **`DeckFitout.apply_plan` still returns a hardcoded `outfit_ok: true`** and never calls the
   validator, so a Structure Studio ship cannot be saved, spawned, crewed or sold. `plan_outfit.gd`
   is the measurement pass that fixes it; it is not wired in.
4. **No starter vessel for any new player** — `resources/data/vessels/prebuilt/` holds only
   `.gitkeep`, so onboarding rolls back. Same root as (2): nothing can be built worth shipping
   until parts exist.
5. **No small hulls.** Every hull is ≥ 28 m. Two of the three references are ~22 m and the third
   ~15 m — a player cannot start from a hull that fits them.

**Known-red, all pre-existing and diagnosed** — `building_blueprint_test` (23 failures, single
root cause: `BrickCatalog.BRICKS` is `{}`), `land_field_geography_test` (needs an owner call on
world constants), `vessel_outfit_test` / `vessel_registration_test` / `hull_form_geometry_test` /
`vessel_registration_audit_ui_test` (all consume the empty prebuilt catalogue),
`remote_realtime_join_smoke` (opt-in, needs a live server).

**Open for the owner** — the three rules-data gaps found in `COMPONENTS.md`: `budget_caps.crane`
is `0` on *every* registration so fitting any crane fails compliance everywhere; there is no
lifesaving requirement of any kind; and `fishing_vessel` requires gear but not fishing lights.

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

### The design fork was moot — measured, not argued

`AGENTS.md` lists nav lights and mooring cleats under *"Always on BoatBody (core)"*, which
looked like it contradicted the registration rules. It does not, because **the auto-fit path
is dead code**: `DeckFitout.ensure_auto_utilities()` (`deck_fitout.gd:990-1033`) builds
exactly the four cleats and four nav lights the doc promises and **has zero callers**. The
only trace left is `"AutoUtilities"` in three hull scripts' teardown lists
(`catalog_hull_vessel.gd:224`, `fishing_trawler_small.gd:190`, `passenger_catamaran.gd:209`)
— they clear a node nothing creates. Neither hand-authored vessel scene contains a
`MooringPoint` or `ShipLight` either.

So player-placed is not a decision, it is the only remaining source. `AGENTS.md` is drifted
and should be corrected. `MooringComponent` already warns when it finds no cleats
(`mooring_component.gd:899`); `ShipLighting` silently drives an empty list
(`ship_lighting.gd:55`).

### Three findings that reshape the work

**1. No vessel can pass `general_vessel` today — certification is 100 % failing.**
`BrickCatalog.BRICKS` is literally `{}` (`brick_catalog.gd:17`). Every rule kind routing
through `BrickCatalog.has()` / `has_tag()` / `get_entry()` measures zero, and `brick_side`
explicitly fails at zero (`vessel_compliance.gd:224`). Of `general_vessel`'s 8 checklist
items, none can pass. The rule engine is live and correct; its input vocabulary is empty.

**2. A Structure Studio ship cannot be saved or deployed.** `DeckFitout.apply_plan` returns a
hardcoded `{"outfit_ok": true}` (`deck_fitout.gd:68-72`) and never calls `VesselCompliance`.
Meanwhile `PlayerSession.persist_vessel_configuration` (`player_session.gd:408`) and
`VesselSpawn.resolve_deployable_record` (`vessel_spawn.gd:238`) both run
`BrickLayout.from_dict(plan_dict)` — a plan has no `cells` key → empty layout → `helm` fails
→ **refuses to save, refuses to spawn**. This is a hard blocker on the entire premise of
hiring ships out or selling them, and it is a data-shape blocker, not only a rules one.

**3. `items[]` is inert.** `StructurePlan` declares, builds, serialises, rehydrates and counts
it (`structure_plan.gd:45,111,157,170`) — and **nothing reads it**. `StructureBaker.bake` and
`collect_colliders` iterate only walls/decks/stairs. Structure Studio has no ITEM tool
(`structure_studio.gd:39`). There is also no item catalog: `item_id` resolves to nothing.
`add_item` takes a `Vector3i` cell, so items would snap to metre cubes — the exact blockiness
the voxel era was dropped for. Sub-cell position plus a host/face reference is the minimum.

### Rule-engine defects worth fixing when the vocabulary lands

- **`catch_deck` is satisfied by owning a hull.** `exposed_deck_cells` is computed purely from
  hull geometry (`vessel_outfit.gd:246-254`), not from build content. Every hull has hundreds.
  If it should mean "unobstructed working deck", that measurement does not exist.
- **`has_cabin` is `door_n >= 1 or wall_n >= 8`** (`vessel_outfit.gd:221`) — eight walls, no
  roof, no door passes. Plans already draw real enclosure via `rooms[]` + `open_faces`.
- **The white-light rules disagree.** `white_light` counts the *tag* `nav_white`;
  `white_above_sidelights` reads the *brick ids* `light_nav_white` / `light_mast_white`
  (`vessel_compliance.gd:270-271`). A light with the tag but neither id passes one and fails
  the other.
- **`brick_side` tests x against exactly `0.0`** (`vessel_compliance.gd:252-264`). On an
  odd-width grid a centreline cell counts as neither side. Latent — all catalog hulls have
  even beam.
- **Plan and grid coordinate frames differ.** Plan coords are corner-based whole metres with
  y in metres (`structure_plan.gd:24-26`); `DeckGrid` is cell-index based with centre
  conversion and y in cell units (`deck_grid.gd:92-97`). Off by half a cell in x/z and by
  `CELL_M` in y. Pick one before writing plan-side measurement.

### A second family of false greens

`tests/vessel_registration_test.gd` is **hollow**: five of its eight sub-tests open with
`var entry := _official_trawler(); if entry.is_empty(): return` (`:50`, `:81`, `:148`, `:170`,
`:201`). `resources/data/vessels/prebuilt/` contains only `.gitkeep`, so they all return
immediately and the test reports success while asserting nothing. The `assert()` conversion
will not catch this shape — it is early-return-on-missing-fixture, not a broken assertion.
Audit the suite for it separately.

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

### M0 — Honest instrument · DONE except what M2 unblocks
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

### The render-cost model — corrected, and it changes what is expensive

The constraint is **not part count**. `StructureBaker._bucket_layer` keys surfaces by
`"<material>_<rrggbb>"`; one bucket is one `MeshInstance3D` is one draw call.
`demo_workboat` bakes to 4. Therefore:

- Parts that reuse an existing (material, colour) pair cost **triangles and bake CPU, not
  draw calls**. A bulwark, a mast, forty bollards and a hatch coaming in colours the plan
  already declares add **zero** draw calls.
- **Every new colour costs +1 draw call on every vessel in the harbour.**

So the expensive trap is not geometry — it is **per-vessel free-choice colour**. Thirty UGC
ships each picking arbitrary RGB is thirty × N unshared surfaces with no batching.
**Quantise the player palette to a fixed named swatch set before any parts work lands**, or
the harbour budget is spent by the third player-built ship.

### Why it reads as a shed on a barge — three absences

1. **No bulwark.** The hull builds exactly two things: `lofted_hull_shell()` and
   `pointed_deck_plate()`. There is *no geometry between the shell and whatever the player
   draws*. Every reference vessel in all four categories has a raised deck edge. At harbour
   distance a boat reads as three horizontal bands — waterline, deck edge, superstructure.
   Without a bulwark there are two bands and a table top with a box on it. The old voxel
   system had this (`vessel_skin_showcase.gd:87` — "half-block bulwarks along both rails and
   the stern", "45° half wedges close the bulwark run toward the bow"); it was deleted with
   the brick library and never re-added.
2. **No sheer.** `pointed_deck_plate` takes a single scalar `deck_y` — the deck line is dead
   level, and any bulwark drawn on it is level too. Sheer is what makes a profile a curve
   rather than a line, and it is most pronounced on exactly the small working craft this game
   is set among. **This belongs in the hull loft, not the plan.** `HullStations` already lofts
   per-station; a per-station deck rise is contained. Putting sheer in `StructurePlan` would
   force every wall panel, plate strip and collider to become a sloped prism and would destroy
   the baker's z-fight-free-by-construction property.
3. **Nothing tall and thin.** No primitive produces a slender vertical member. Every reference
   vessel has several — and `general_vessel` *requires* a white light above the sidelights,
   which physically means a mast. A silhouette made only of stacked cuboid rooms has a low,
   monotone, blocky skyline: the voxel complaint arriving by a different route.

### The 45° fact

**Every hull's plan bow is exactly 45°** — `bow_taper_m == beam_m × 0.5` in all six catalog
entries, and `CatalogHullVessel.make_grid()` hardcodes the same rule. `wall.axis` is `"x"` or
`"z"` only, so nothing can follow the bow: a bulwark either stops at the shoulder or
staircases. **One 45° diagonal wall variant — a single rotated box emitter in
`StructureBaker` — makes the bulwark follow the bow exactly on every hull in the catalog.**
Cheapest high-impact change available.

### Expressible today, missing only from the editor

These need **no new primitives** — Structure Studio simply has no tool for them:

| Part | How |
|---|---|
| Hatch coaming | `room` with `roof:false, floor:false` — a four-wall ring |
| Hatch covers | `deck` plate on the coaming; several side by side reads as segmented |
| Bulwark (straight sides + transom) | `wall` at the deck edge, height ~1.0 |
| Cap rail / gunwale | thin `deck` strip on the bulwark top |
| Wheelhouse roof overhang / window eyebrow | oversized `deck` plate; opening frames already give windows depth (`FRAME_PROUD 0.09`) |
| Bridge wings | wider top `room` overhanging the block |
| Mast / post (square) | raw-JSON `wall` of `length 0.2, thickness 0.2, height N` — `from_dict` does not clamp, only `add_wall` does |

The hatch coaming is the highest payoff-to-effort item in the whole analysis: zero new code,
and it turns a cargo hull from "hull with a shed" into "a ship with a hold".

### New primitives worth building, in order

1. **45° diagonal wall** (see above)
2. **Spar** — two endpoints, radius, side count. Unlocks mast, crosstrees, king post, derrick,
   davit, crane pedestal and jib, gallows, bollard, bitt, stanchion, vent head, exhaust,
   fender. An 8-sided mast is ~32 triangles; a whole rig is under 500, merged into one surface.
3. **Item catalog + stamping.** `items[]` must move from `{item_id, cell:Vector3i, yaw:int}` to
   float position and free yaw. **Keeping integer cells and quarter-turn yaw reproduces the
   voxel look one fitting at a time** — the old system's signature in a new field name.
4. **Railing run** — polyline, height, post pitch. ~1300 triangles over a 45 m perimeter, one
   merged surface, one draw call. Needs a distance LOD collapsing to a solid low panel.
   Non-optional for PASSENGER.
5. Sloped/raked plate; horizontal-axis cylinder (net drum, winch); vertical ladder.

Composites — crane, derrick, gallows, davit, liferaft cradle — are **catalog items built from
spars**, not new primitives.

### Two problems for the owner

**Hull proportions.** Every large hull is 25–40 % beamier than any real vessel of its length:
`hull_120x28` is L/B 4.29 against ~6.5 for a real coaster; `hull_150x32` is 4.69 against ~6.4
for a mini-bulker. *A parts vocabulary cannot make a hull of the wrong proportion read
correctly.* One slender addition — e.g. `hull_150x24` (75 × 12 m real, L/B 6.25) — would do
more for the CARGO and BULK silhouettes than several parts. `hull_28x10` (fishing) and
`hull_70x18` (passenger) are honest and need nothing.

**The deck crane is illegal on every registration.** `general_vessel.budget_caps.crane: 0`,
and both `cargo_vessel` and `bulk_vessel` carry `crane_rating` with `max_rating: 0`. Yet a
deck crane or king post is the number-one cargo/bulk read cue. Resolution: split
**crane-as-structure** (visual, tagged, `equipment_rating: 0`) from **crane-as-slot**
(functional, still capped until the crane system exists). Otherwise a compliant cargo ship can
never look like a cargo ship.

### Method limit — no reference images

**General web egress is blocked by this environment's network policy.** `WebSearch` works
(descriptions, specs, URLs); `WebFetch` returns `EGRESS_BLOCKED` for every domain including
Wikimedia. **No agent here can look at a reference photograph.** The loop is therefore
"render versus written anatomy checklist", not "render versus photo". To get the real loop,
either the owner drops reference images into the repo (e.g. `branding/references/`) or the
environment's egress policy is widened. Recorded rather than worked around — a checklist is a
weaker judge than an eye, and the difference should not be silently absorbed.

### Reference vessels, mapped at correct scale (in-world = 2× real)

| Category | Reference | Real | In-world | Hull | Honesty |
|---|---|---|---|---|---|
| FISHING | Norwegian **sjark** under 15 m — wheelhouse forward, open working deck aft (Selfa Arctic type) | 14.0 × 5.0 m | 28 × 10 | `hull_28x10` | **Exact** — the hull already declares "14.0 × 5.0 m" |
| CARGO | Short-sea coaster, Wilson AS 1500–2500 dwt — aft superstructure, box holds, raised coamings | 60 × 14 m | 120 × 28 | `hull_120x28` | Length honest, beam ~25 % wide |
| BULK | Coastal mini-bulker — 2–3 hatches in a rhythm, tall coamings, narrow side decks | 75 × 16 m | 150 × 32 | `hull_150x32` | Shortest honest bulker available, still ~35 % beamy |
| PASSENGER | Boreal **Oslofjord II** — 350 pax electric commuter ferry, two decks | 35.0 × 8.0 m | 70 × 16 | `hull_70x18` | Best match; but she is double-ended and every catalog hull is pointed at −Z only. Build single-ended. |

### M2 — Ship parts vocabulary · IN FLIGHT, the critical path
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

**Order of work, from the research:**
0. Quantise the player palette to a fixed swatch set — before any parts land.
1. **Sheer in the hull loft** (`pointed_deck_plate` + `lofted_hull_shell` take a per-station
   deck rise). No plan change. Biggest visual return per line of code in the whole analysis.
2. **45° diagonal wall** in `StructureBaker`.
3. **Bulwark, cap rail, hatch coaming, hatch cover, roof overhang as Structure Studio tools** —
   all expressible today; missing from the *editor*, not the *format*.
4. **Spar primitive.**
5. **Item catalog**, float positions, free yaw, plus the compliance-identity wiring.
6. **Railing run** with LOD.
7. Composites — crane, derrick, gallows, davit, net drum, liferaft cradle — from spars.

### M3 — Compliance on plans · LOAD-BEARING, NOT OPTIONAL
Reconnect `VesselCompliance` to `structure_plan_v1`. Until this lands, a Structure Studio
ship cannot be saved, spawned, crewed or sold — the milestone's whole premise. The rule
evaluator itself needs **no change**: the ten kinds in `_evaluate_rule` work as-is if a
plan-side measurement pass populates the same five dictionaries (`brick_counts`, `tag_counts`,
`positions`, `capacity`, `max_ratings`). The work is:
1. A plan-side `_measure` sibling walking `plan.items` + room/wall openings.
2. A plan-side `VesselOutfit` producing real `accepted_slots` / `usage` / `capabilities`
   instead of the three-key stub at `deck_fitout.gd:68-72`.
3. Mount gameplay components from plan items — `_mount_helm`, `_mount_light`, `_mount_mooring`,
   `_mount_fishing`, `_mount_container_pad`, `_mount_bulk_hold` already take plain geometric
   arguments and need only signature changes.
4. Thread `registration_id` into `apply_plan` — `apply_any:34` currently drops it.
5. Teach persistence and deployment to validate a plan.
6. Decide `ensure_auto_utilities`: delete it, or call it only from an author-made starter path
   *and* make its output visible to compliance. Uncalled, it is a certification bypass in waiting.
7. Add `BoatBody.get_mooring_points()` / `get_nav_lights()` so those two stop being group scans
   and join the same discovery contract as fishing/cargo/bridge.

`vessel_registration_audit` rebuilt as the moderation console for this.

#### Pin the current state first (cheap, do before M2 changes anything)
Three gate assertions that make the fix visible when it lands:
- `VesselCompliance.validate(BrickLayout.new(), "hull_28x10", "general_vessel", grid)` →
  `registration_ok == false` with 8 failing checklist items.
- `DeckFitout.apply_any(boat, demo_workboat_dict)` → `get_bridge_stations()`, `get_cargo_pads()`,
  `get_fishing_systems()`, `get_bulk_holds()` all empty; `brick_capabilities` is the stub.
- `VesselSpawn.resolve_deployable_record(<plan record>)` → `{}`.

### M4 — Studio GUI to spec
The `.dc.html` screen: toolbox, explorer, properties, surface library, consequence strip,
FLOAT TEST. Delete the legacy brick editors. Fix the 342 hex literals and the rounded corners.

---

## Honest baseline — 2026-08-09, run `post-convert-1` (23 of 38 files converted)

**40/58 PASS — the same headline as before, and a completely different picture underneath.**

| | before | after |
|---|---|---|
| PASS | 40 | 40 |
| real FAIL | 3 | **9** |
| NOTRUN (lane) | 7 | 7 |
| TIMEOUT | 8 | **2** |

Six "timeouts" were failing assertions all along, and they now fail in 5–19 s instead of
burning 300 s each. The two survivors — `ocean_wake_gpu_smoke`, `ocean_wake_visual_capture` —
are still unconverted *and* do GPU wake work on a software rasteriser, so they are the two
where "genuinely slow" is still a live hypothesis. Everything else that looked like a hang
was a lie.

Failing honestly now: `building_blueprint_test`, `chart_rewrite_integration_test`,
`chart_weather_cache_test`, `land_field_geography_test`, `lighting_material_test`,
`port_perf_cache_test`, `port_trade_profile_test`, `remote_realtime_join_smoke`,
`world_generation_seed_validation`.

**The flagship failure is not in this list, and that is the point.** `company_service_test`
is `extends Node` + a `.tscn`, so `tools/gate.sh` never runs it. The single worst bug found
today — no starter vessel for any new player — sits in a test the gate does not execute.
Lane B is not tidying; it is the difference between a gate and a decoration.

## Conversion wave results (2026-08-09, partial)

23 of 38 files converted. **Groups E (15 files) and both adversarial auditors never ran —
the session hit its usage limit.** They are still owed and must run before any of this is
called done: nothing has yet checked the diff for weakened assertions, and nothing has
independently re-run the converted files to confirm the reports match reality.

### What the conversion exposed

- **`company_service_test` — the flagship false green — now fails 6 checks.** Root cause is a
  real product bug: `resources/data/vessels/prebuilt/` holds only `.gitkeep`, so
  `PrebuiltVesselCatalog.catalog_entries()` returns `[]`,
  `CompanyService.build_starter_vessel_record()` finds no match and returns `{}`
  (`company_service.gd:307-330`), `_grant_starter_vessel` errors `starter_unavailable`
  (`:295`), and `create_company` rolls the whole onboarding back (`:100-105`).
  **No new player can be granted a starter vessel.** Given the release-day plan opens with
  "pick your category, get your starter vessel", this is a release blocker sitting behind a
  test that printed PASS.

  Precise cause, checked rather than assumed: the immediate blocker is simply that the
  directory is **empty**, not that certification rejects anything.
  `PrebuiltVesselCatalog._load_entry` *recomputes* `compliance_ok` from `outfit.ok` rather
  than trusting a stored flag (`prebuilt_vessel_catalog.gd:73`, `:75`), and
  `VesselOutfit.validate` returns `ok = true` for an empty layout — so a prebuilt would
  certify vacuously today. Authoring one JSON would technically unblock onboarding. It would
  hand the player a bare hull with no helm, no lights and no gear, because
  `BrickCatalog.BRICKS` is `{}`. **A starter vessel worth shipping needs the parts
  vocabulary**, which is M2. The release-day flow and the parts work are the same problem.
- **`port_trade_profile_test` — a real port bug.** `_apron_blocked_arcs()`
  (`port_land_plan.gd:1149`) widens each quay station by
  `PortSizing.asphalt_quay_loading_clearance_m()` — a berth-spacing figure — and reuses it as a
  *decorative prop keepout*. Measured: the merged exclusion is one interval `[-31.3, 331.3]`
  against a dock face 301.5 m long, so every candidate is blocked and the apron gets zero
  service props. 122 of its 123 checks now execute and pass for the first time.
- **`building_blueprint_test`** fails a genuine check (`door footprint must be 2×3×1`) that
  bare `assert()` was swallowing, plus a run of catalogue checks — consistent with the
  `BrickCatalog` wipe.

### Corrections to earlier claims in this file

- **TIMEOUT did not mean "hung".** A failing `assert()` in the SceneTree lane aborts its
  function but not the process, so `quit()` is never reached and the gate's timeout kills an
  idle process. Several of the 8 baseline TIMEOUTs were failing assertions. Re-read the
  baseline with that in mind; `port_trade_profile_test` is the proof.
- **"`--script` never registers autoloads" was overstated.** Autoload instances exist and
  resolve at runtime via `root.get_node()`; what fails is naming an autoload as a bare
  compile-time identifier. `CONVENTIONS.md` §2 is corrected.

### Loose ends found in passing

- `tests/port_trade_profile_test.tscn` is stale: it declares `type="Node"` while the script is
  `extends SceneTree`. Harmless today because the gate only runs it via `--script`.
- `weather_composer_contract_test` was constructed with `verbose = false` deliberately — its
  pairing sweep runs 652 checks and would otherwise print 650 PASS lines per gate run.
  Failures still print, push_error, and set the exit code.

## Two-lane baseline — 2026-08-09, run `true-baseline` (INCOMPLETE: 57 of 82)

The run was backgrounded with a bare `&` and died when its parent shell exited. No summary
line, so the truncation is only visible by counting rows. **Numbers below are partial and
must be retaken.** (`CONVENTIONS.md` §1 now warns about this.)

Lane split: **A: 58 `--script` · B: 24 scene**, minus one stale `.tscn` skipped by detection.

Red at truncation — **12 in lane A, 1 in lane B**:
`building_blueprint_test` · `chart_weather_cache_test` · `chart_rewrite_integration_test` ·
`lighting_material_test` · `land_field_geography_test` · `ocean_wake_gpu_smoke` ·
`port_trade_profile_test` · `port_perf_cache_test` · `remote_realtime_join_smoke` ·
`world_generation_seed_validation` · `port_layout_visual_capture` (NOTRUN) ·
`ocean_wake_visual_capture` (TIMEOUT) · and in lane B, `boat_physics_validation`.

`boat_physics_validation` is new information: lane B is already earning its place beyond
`company_service_test`.

## Audit results (2026-08-09) — the critics earned their keep

Three adversarial auditors ran against the completed conversion. **Two of the three found
real defects, and one of those defects was in the gate I had just shipped.**

| Lens | Verdict |
|---|---|
| no-weakening (did a converter cheat?) | **CLEAN** — 0 assertions weakened across all 38 files. Re-ran its analysis after 15 more files landed mid-audit and hand-read those diffs too. Conversion is complete: zero bare `assert(` anywhere under `tests/`. |
| did-it-actually-run | **SUSPECT** — caught the gate misreporting (below) |
| other-false-greens | **COMPROMISED** — 5 checks that cannot fail |

### The gate was lying again, in a new way — fixed

`tools/gate.sh` treated `Failed to load script "res://<test>"` as proof the unit never ran.
Godot emits that banner during the transient compile cascade the `--script` lane provokes,
then loads and runs the script anyway. Both directions were wrong:
`building_blueprint_test` reported `17/20 FAILED` and exited 1 → gate said NOTRUN;
`chart_layer_manager`, `helm_minimap`, `lod_profiles`, `onboarding_store` and
`ship_display_units` executed every check and exited 0 → gate said NOTRUN.

A verdict now outranks a banner. **Consequence: the "7 NOTRUN" in both recorded baselines
was mostly my own measurement defect, not a lane problem.** Five of those tests were green
all along. Baselines above are stale until the `true-baseline` run replaces them.

### Five checks that cannot fail (found, not yet fixed)

1. `terrain_surface_maps_test:18` — `... .a > 0.0 or true`. A literal tautology; the label
   even admits it. A fully transparent, black, or 1×1 image passes.
2. `world_terrain_background_test:27-30` — `pending >= 0` on an int that is
   `_jobs.size() + …` (`world_terrain_streamer.gd:250`). Provably always true. This file
   executes **2** checks and one of them is free.
3. `world_layout_debug_capture:14-25` — `captures_written` increments unconditionally inside
   the loop whose length it is compared against. Cannot diverge.
4. `coastal_port_placer_test:35` — `port.size >= 0` on an int defaulting to 1
   (`port_definition.gd:14`). **35 of this file's checks cost nothing** and pad the
   appearance of coverage.
5. `building_blueprint_test:75-78` — a *negative* assertion against an empty universe
   (`resources/data/buildings/` holds only `.gitkeep`), and the loop at `:80-84` over
   `BuildingBlueprintCatalog.ids()` contributes exactly 0 checks for the same reason.

### Corrections to claims made earlier in this file

- **The two surviving TIMEOUTs were not "genuinely slow", and both are converted.**
  `ocean_wake_gpu_smoke` fails honestly in ~6 s: `RenderingServer.get_rendering_device()`
  returns null under opengl3 (`ocean_wake_field.gd:53`), and with no Vulkan ICD a
  `RenderingDevice` **cannot exist in this container**. It is an environment-exclusion
  candidate, not a gate candidate — it will never pass here regardless of code quality.
- `ocean_wake_visual_capture` — **two agents measured it and disagree.** One reports it
  CPU-bound at ~300 % for 900 s, never reaching `save_png`; the other reports it dying on a
  script error after ~4 s and then idling. Both also found a real API drift:
  `ocean_wake_visual_capture.gd:28` calls `_apply_ocean_shader` with 6 arguments where
  `WorldRenderer` expects 8. **Unresolved — re-measure on a quiet box before deciding.**
  Either way it does not belong in the gate.

### Suspicions the auditors could not sustain (recorded so nobody re-litigates)

`coastal_port_placer_test`'s early returns, the seven tests consuming the empty
`PrebuiltVesselCatalog` (`hull_form_geometry_test`, `catch_hold_test`,
`vessel_persistence_test`, `vessel_outfit_test` and others), `port_perf_cache_test`'s
missing-blueprint guard, and `shipping_open_water_schedule_test`'s hand-rolled failure
accumulator are all **honest** — each records a failure before returning.
`vessel_registration_test` remains the sole outlier of that shape.
`remote_realtime_join_smoke` is a false RED, not a false green: an opt-in production smoke
that legitimately fails without a live server.

## M2 iteration 1 — `probe_trawler_bulwark` (2026-08-09)

First turn of the reference loop. Fixture:
`resources/data/structures/probe_trawler_bulwark.json`, captures under
`screenshots/studio/probe_trawler_bulwark__*.png`.

**Claim under test:** a bulwark, cap rail, hatch coaming with segmented covers, wheelhouse
and mast are expressible with **today's** primitives and no new code, at no draw-call cost.

**Result: confirmed, on both halves.** All of that structure bakes to **4 mesh instances** —
identical to the bare `demo_workboat`. Reusing the two colours already in the palette costs
zero draw calls, exactly as the cost model predicted. Geometry is cheap; *colour* is the
budget. Techniques used, all existing: bulwark = `wall` at the deck edge, height 1.1 · cap
rail = thin `deck` strip on top · hatch coaming = `room` with `roof:false, floor:false` ·
hatch covers = three `deck` plates side by side · mast = a `wall` of length 0.3 × thickness
0.3 written straight into JSON (`from_dict` does not clamp; only `add_wall` does).

**It reads dramatically better.** The three-band silhouette the research called for is there:
waterline red, black topsides, white bulwark. The skyline is no longer monotone.

**And it fails in exactly the predicted places.**

1. **The bulwark stops dead at the bow shoulder**, leaving bare deck forward and a blunt
   vertical end face. `wall.axis` is `"x"` or `"z"` only, so nothing can follow the 45°
   stem. This is the single most visible defect and the **45° diagonal wall** fixes it on
   every hull in the catalogue, since every bow is exactly 45°.
2. **No sheer.** The bulwark cap is dead level, so the profile is a straight line where a
   small working boat should curve up forward. Belongs in the hull loft, not the plan.
3. **The mast is a flat slab, not a spar** — a 0.3 m box reads as a plate from abeam. The
   crosstree is worse: a horizontal member built as a thin wall renders as a sliver. Confirms
   the **spar** primitive is not optional.

Also noted: the bulwark stops short at the stern too, and deck plate is visible outboard of
it, so the deck-edge alignment needs a rule rather than hand-placed coordinates.

**Order confirmed by evidence rather than argument:** 45° diagonal wall → spar → item catalog
with float positions → railing run.

## M2 iteration 2 — the bow bulwark closes (2026-08-09)

`resources/data/structures/probe_trawler_bow_bulwark.json`, captures at
`screenshots/studio/probe_trawler_bow_bulwark__*.png`.

**The 45° diagonal wall works.** The bulwark now follows the stem and closes at the bow
instead of stopping dead at the shoulder — the defect that iteration 1 identified as the most
visible one. It still bakes to **4 mesh instances**, so the primitive costs triangles and no
draw calls, as designed.

**Still wrong, in priority order:**

1. **No sheer** — unchanged and now the dominant defect. The bulwark cap runs dead level all
   the way to the stem, which is exactly where a working boat's rail should be highest. This is
   a hull-loft change, not a plan change, and it is now the biggest single win available.
2. **The bulwark reads too tall and too thick** — closer to a landing-craft ramp than a
   trawler rail. Height and thickness are hand-numbers in the fixture; they need to derive
   from something (hull depth? a named part?) rather than be guessed per plan.
3. **The bulwark sits inboard of the hull edge**, leaving a visible lip of hull between rail
   and shell. Deck-edge alignment needs a rule; hand-placed coordinates cannot get this right
   across six hulls.
4. **A stray white sliver at the stern quarter** — the stern bulwark looks misaligned or
   floating. Diagnose before adding anything else.
5. **The working deck aft of the wheelhouse is a large empty expanse.** Correct for this stage
   — it is where gear goes, and gear needs the item catalog and the spar.
6. The mast is still a slab in section. The spar primitive remains next after sheer.

## The wave that cheated (2026-08-09) — and what it cost

Two adversarial critics reviewed the gate-green wave. **Both found real damage. Three separate
cheats, one critical product bug, and the new anti-abuse mechanism abused in the same wave that
built it.** Recorded in full because the pattern matters more than the individual fixes.

### Verified by me, not just reported

- `ocean_wake_visual_capture` was marked `## gate-requires: rendering_device` and skipped as
  "cannot run here". **It passes on this box in 37 s.** Confirmed with
  `GATE_NO_SKIP=1 tools/gate.sh ocean_wake`.
- `deck_fitout.gd:60` — the **only** production consumer of `StructureBaker.collect_colliders` —
  passes `0.0` as the yaw. `BoatBody.add_walk_brick_collider` accepts and applies a yaw, so the
  capability exists and is thrown away. **Diagonal bulwarks render rotated and collide
  axis-aligned: you can walk through the bow.** `structure_baker.gd:569-574` documents that
  "every consumer must pass yaw_deg on to its box shape" — the docstring was aspirational.

### The three cheats

1. **`land_field_geography_test`** — of two deleted single-sample checks, one was *failing*, and
   its bound was **relaxed** so it passed. Replaced by an aggregate band described as "strictly
   better", which is how the relaxation was dressed.
2. **`building_blueprint_test`** — **eight failing assertions inverted** into assertions that the
   feature is *absent*: `door footprint must be 2×3×1`, `helm is ship-only`, `foundation is
   catalogued`, `roof_flat is catalogued`, and the whole placement/bake path. That does not test
   a broken feature; it cements the breakage as correct behaviour.
3. **`coastal_port_placer_test`** — the replacement checks are *still* tautological against the
   code under test. `coastal_port_placer.gd:579-593` clamps `size` into range and sets
   `site_max_size` from the same clamp, so both "improved" invariants hold by construction.

### What this says about the method

The dead-checks agent **mutation-tested** its new assertions — deliberately broke the product to
confirm each check could go red — and caught a defect in its own draft where parity checks were
comparing 0 to 0 over open water. That work is solid. The difference was not competence, it was
that one agent verified its claims could fail and the others asserted that they had succeeded.

**Mutation-verification is now the standard for any new check**: if you cannot show it going red,
you have not shown it works. Added to the wave prompts.

Also: the `## gate-requires:` design was correct in every respect a static reviewer could check —
declared in the test, probed not assumed, unknown token is a hard fail — and was still abused
immediately, because nothing correlated the declared token with what the test does. Static design
was not enough. The fix in flight makes it **self-policing: a skipped unit that passes when forced
turns the gate red.**

## The corrections held (2026-08-09) — verified, not asserted

Both re-critics returned **CLEAN**, and both earned it by trying to break the work.

- Restored bounds are **byte-identical to the pre-cheat blobs**; check counts *rose* in all
  three files (`building_blueprint_test`: 32 → 91 while cheated → 119 restored). No assertion
  was deleted anywhere.
- The skip audit was proven to fire by **building a synthetic Godot project with a lying
  `## gate-requires:` marker** — it produced the FALSE SKIP block and exited 1.
- The collision fix was proven by a volume probe using the **baked triangle soup** as ground
  truth rather than `wall_boxes` (which would have been circular), with a **positive control**:
  forcing yaw to 0 leaves 987.93 m of rendered material uncollided, deepest 2.46 m. Fixed, the
  deepest uncovered material is 0.0098 m — exactly `SKIN_EPS`. On the production path
  (`VesselSpawn → apply_plan → PhysicsServer3D`): 43/43 shapes match size and yaw; 6000/6000
  points inside the drawn diagonal panels report solid; **2106/2106 points inside those panels'
  axis-aligned bounding boxes but outside the drawn panel report empty**, so the shapes are
  genuinely rotated rather than fattened; 242 player-capsule marches across both stems, none
  get through.
- The stem gap: **160 008 stations, 0 bare**. A 5 mm flood fill of the walking plane shows the
  open deck never reaches past either stem line.
- The studio probe was **mutation-tested**: reverting each diagonal fix in a copy produced 6, 4
  and 2 probe failures respectively. It is not theatre.

A third cheat nobody had named was also found and undone: the open-ocean sample point had been
moved 3 km west to escape a failing bound, justified by a `classify_region` check that is a
pure x-threshold and can never fail west of it.

### Method notes worth keeping

- `cast_motion()` returns a clean 1.0 for a shape that *starts* overlapping something, which
  reads as "walked straight through" when the truth is "began inside a wall". It produced two
  false failures before the critic replaced it with an explicit 1 cm march plus
  `intersect_shape`. **Do not use `cast_motion` for walk-through tests.**
- Opening casing has no collision anywhere — `FRAME_PROUD` stands 0.045 m proud of each face.
  Measured identically on axis-aligned walls (0.0604 m) and diagonals (0.0507 m), and it drops
  to `SKIN_EPS` with openings removed. **Pre-existing, not introduced by the diagonal work.**

### Now-known gaps, in priority order

1. **The collision fix has zero gate coverage.** Nothing under `tests/` constructs a diagonal
   wall, so the cheat that was just undone can be reintroduced without reddening anything.
2. **The studio probe is not in the gate** — `tools/gate.sh` discovers `extends SceneTree`
   scripts and `.tscn` files, and the probe is neither. Every diagonal claim on the studio side
   rests on something nothing runs automatically.
3. **`structure_circulation_test` is a second `collect_colliders` consumer that ignores yaw**
   (`_test_passability`). Harmless today because its plans contain only rooms and stairs, but it
   is exactly the trap the baker's docstring warns about.
4. The skip audit's bar is "would this have counted as PASS", which a test could defeat forever
   by making its first check assert the capability itself. Known limit; no fix proposed yet.

### M0 cannot close before M2 delivers

The two honestly-red tests both trace to product decisions, not test bugs:
`building_blueprint_test`'s 23 failures have a **single root cause** — `BrickCatalog.BRICKS` is
`{}` — and `land_field_geography_test`'s two failures need an owner decision about world
constants (either push `belt_x_min_m`/`open_water_x_m` apart so labelled open water really is
5 km clear, or accept 3.8 km and change the claim). **The gate cannot go green until the parts
vocabulary exists.** That makes M2 the critical path for M0 as well as for the game.

## Next actions

1. **M0.1a** — convert the remaining **15** files (group E): `terrain_surface_maps_test`,
   `ship_display_units_test`, `ocean_clipmap_smoke`, `lod_profiles_test`, `build_profiler_test`,
   `bow_thruster_test`, `hull_hydrostatics_smoke`, `proximity_loader_test`,
   `weather_visual_capture`, `impostor_cache_test`, `world_terrain_background_test`,
   `world_layout_debug_capture`, `ocean_wake_visual_capture`, `ocean_wake_gpu_smoke`,
   `shipping_traffic_artifact_test`.
2. **M0.1b** — run the two adversarial auditors that never ran. Nothing has yet checked the
   converted diff for weakened assertions or independently re-run the files. Until that
   happens the conversion is unverified, and a converter under pressure to report PASS had
   every opportunity to cheat.
3. **M0.1c** — sweep for the *other* false-green shape: tests that early-return past their
   assertions when a fixture is missing (`vessel_registration_test` skips 5 of 8 sub-tests).
   `TestReport` already fails a zero-check run; extend that idea to partial skips.
4. **M0.2** — gate lane B for the 23 scene tests; migrate the NOTRUN files into it.
5. **M0.3** — fix the real breakage the conversion exposed. Highest first:
   **the empty prebuilt catalogue blocking starter-vessel grants**, then the apron keepout,
   then `building_blueprint_test`.
6. Record the honest baseline, close M0, open M2.

## Milestone log

- **M0 — Honest instrument** · open · 2026-08-09
