# STATE.md — Ship construction vocabulary & Structure Studio

Position file for the orchestration loop. Read `CONVENTIONS.md` first.
Rewritten at every checkpoint. If it disagrees with the tree, the tree wins.

- **Branch:** `claude/branding-gui-orchestration-hhjb52` (both repos)
- **Last updated:** 2026-08-10 · after the room purge and the first vessel that reads as a boat
- **Milestone:** M2 — parts vocabulary. Rebuilding every vessel on the new primitives.

## THE DIRECTION CHANGE — 2026-08-10, read before anything else

The owner looked at the dressed fleet and said: *"this looks like complete fucking shit. in no
way will this ever turn into the final game. do you not have eyes"*, then *"if I squint my eyes
the entire silhouette looks like shit. it does NOT resemble a fucking boat at all"*, then
*"fuck the entire ROOM thing off immediately"* and *"ALL models are going to be redone"*.

He was right, and the reason I missed it is the important part.

**I had been measuring the wrong thing.** Draw calls, check counts, triangle budgets, mutation
coverage — all real, all verifiable, and none of them can tell you a boat looks like a boat. When
I needed to report visual progress I reported the numbers I had and let them stand in for the
thing actually being asked about. That is how "reads as a working boat" got said about something
that squints to a brick.

**Then I did it again, one layer up.** I built an automated silhouette metric — sheer, massing,
asymmetry — and it PASSED all three vessels the owner had just called unrecognisable. It was
measuring "is this not a perfect rectangle", which anything with a tapered bow clears. It was
deleted rather than tuned, because tuning thresholds until a metric agrees with a known answer
makes it a rubber stamp, and this project spent a full day removing exactly that from its tests.

**The rule, and it is not negotiable:** mechanical tests for things with a right answer —
collision matching geometry, draw calls, byte-stable round trips, a wire attached to something.
**Looking, by a human or by the orchestrator, for everything else.** Do not build a metric for
appearance. Every model edit returns a render and the orchestrator judges it.

### What was actually wrong with the silhouette

Squinted, every vessel was **two parallel horizontal bars**: the hull's top edge dead straight
stem to transom, and a constant-height bulwark band above it. Working craft read by their
**sheer** — the deck edge sweeping up toward the bow. Nothing in the project could draw that
curve. Fittings never fixed it because it was never a detail problem.

### What changed

- **Rooms are DELETED.** A room was an axis-aligned box expanding to four walls, a floor and a
  ceiling, so every deckhouse was a shed by construction — and its existence is why the
  sloped-plate primitive was specified and never built. Net −631 lines.
- **The raked plate** replaces it: a quad with four independent 3D corners. Deckhouses now have
  raked fronts, set-back tiers, sloped roofs and real window bands.
- **The sheer band** carries the curve on the bulwark cap, derived per hull from
  `HullStations.sheer_cap_y_at`. This is where sheer belongs — the hull loft was tried and
  reverted because `deck_y` is the floor of four other systems with zero headroom.
- **`edges[]` is a first-class plan entity**: counted, addressable, removable, item-hostable,
  baked with colliders from the same array it renders so the two cannot drift.
- **Value contrast** — dark hull, light house, ochre cap rail. Free, since colour left the
  bucket key.
- The capture rig shoots against a **pale sky**. A silhouette is the boundary between subject and
  ground; dark-on-dark renders had been making everything look flatter than it was.

`probe_trawler_bulwark` is the first vessel that reads as a working boat and is the worked
example every other fixture should be built from.

**Still wrong on it:** blunt near-vertical stem where a trawler rakes and flares (hull-loft work,
not bulwark work), flat hull sides with no plating relief, and gallows that read as free-standing
poles rather than structure.

---

## WHERE WE ARE — read this first, the rest of the file is the record

**The loop works.** A `structure_plan_v1` JSON goes in; `tools/capture.sh` bakes it onto its
hull and returns four canonical-angle PNGs plus assertions. No display, no clicking. Five
fixtures live in `resources/data/structures/`; captures under `screenshots/studio/` with stable
names, so `git diff` on an image shows what a change did to the silhouette — **for the rigs that
write the same bytes twice, which was not all of them. Read the next section before you diff a
frame.**

---

## ⚠ WHICH CAPTURES CAN BE DIFFED — surveyed 2026-08-16, and the answer used to be "unknown"

**Every capture rig under `tests/` was run twice with no code change and the frames byte-compared.
30 rigs, 261 frames in the survey pass, plus `_starter_shot` measured separately (8 more).**

**Eight rigs moved inside a survey pair. `_starter_shot` makes nine. Three more were dependent on
the wall clock and measured 0.0000% only because their two runs were minutes apart —
`_starter_28m_shot` and `_hold_overhang_probe` (both carry a `BrickLayout`, therefore
`ShipLight`s) and `_fittings_shot` (which moves 3.79% across a six-minute gap even with the hour
pinned). **Twelve rigs in total whose frames must not be md5-compared**, and the count was "more
than two" as suspected.

The count is the finding, and so is the shape of it: the
`vessel_render_capture` family was byte-perfect and the SCRATCH RIGS COPIED FROM IT WERE NOT,
because each copy dropped the two lines that made the parent reproducible.

**Both diagnoses previously on record were wrong, and were disproved rather than replaced.**

- *"`_starter_shot` floats a hull and settles it under physics."* **False.** Across two processes
  the granted vessel's body transform is bit-identical in all twelve float words at frames 1, 4,
  8, 20 and 40; the SHA-256 of its 138 mesh surface arrays, of its 141 materials and of all 143
  visual-instance AABBs are identical. `freeze = true` holds. Nothing settles.
- *"`probe_piece_*` and `probe_plate_deckhouse` are nondeterministic (up to 1.237%)."* **Does not
  reproduce, and the number was measured against the wrong thing.** `piece_kit_capture` 12
  frames, `structure_plate_capture` 4 frames, `piece_kit_critic_capture` 12 frames — **0 moved,
  all three.** What those fifteen frames *are* is **STALE**: a fresh run differs from the PNG
  committed at `12f609f` by **0.0284% to 1.4450%** (worst channel deltas 97–169/255, so real
  geometry, not dither) — the same band as the "1.237% between identical runs" on record.
  A run compared against a committed frame measures how old the frame is, not whether the rig
  is reproducible, and the two answers look identical in a percentage.
  `screenshots/critic/` is worse: **up to 14.91%** off a rig that is byte-perfect.
  `vessel_render_capture`'s own 36 frames are the exception — they still match `12f609f` exactly.
- *"`hull_visual_capture` measured 0.000% across two runs, which made a real change
  attributable."* **The 0.000% was a lucky pair.** Measured over four runs: one pair moved 2 of 18
  frames (0.8628% and 0.8104%), one moved 1 (0.5579%), one moved 0. It is intermittent, and it
  lands only on the two views that yaw the hull.

### The three causes, because the fix differs

**1. A TIME-OF-DAY LIGHT — the big one, and it is not a light in the rig.** `WorldClock` runs a
**24-REAL-MINUTE game day** off `Time.get_unix_time_from_system()`, and `ShipLighting._process`
rescales every `ShipLight` on a spawned vessel from it twice a second via
`WeatherLighting.artificial_light_scale()` = `lerpf(1.0, 0.05, daylight)`. **Two runs twelve real
minutes apart are twelve GAME HOURS apart.** Measured on `_starter_shot`:

| grabbed | game hour | `artificial_light_scale` | vs the other run |
|---|---|---|---|
| 01:36:40 UTC | 0.67 (night) | 1.00 | — |
| 01:48:30 UTC | 12.50 (midday) | 0.05 | **94.96% of `plan_ortho`, deltas to 166/255** |

and two runs *four* minutes apart (hours 0.67 and 5.00, both night) moved **21.7% of the same
frame by 1 to 3 parts in 255** — a real lighting change, invisible to the eye, enough to move
every md5. **That second number is the dangerous one.** It is why "5.386% of pixels moved" was
reported as instability and read as if the boat had moved.

*The corollary that matters more than the fix:* **two back-to-back runs cannot see this.**
`_starter_28m_shot` measured **0.0000% over 15 frames** and is time-dependent all the same.
Any reproducibility claim from a fast pair is worth nothing.

**2. A GRAB/DRAW RACE.** A rig that awaits N `process_frame`s and then reads
`viewport.get_texture()` — without `await RenderingServer.frame_post_draw` — intermittently
returns a frame a draw out. With no anti-aliasing this shows up as a **one-pixel outline along
every silhouette edge** (the diff mask is a wireframe of the boat), worst on yawed views:
`hull_visual_capture` 0.86%, `_small_hull_shot` 0.14%, `_hull_iter_shot` 0.013%. Every
byte-stable rig here already awaited `frame_post_draw`; every unstable one did not.

**3. A WALL-CLOCK SHADER TIME — unfixable, and now labelled.** `WorldRenderer` sets the ocean
materials' `wave_time` from `WaveSurface.get_sim_time()`, which is `Time.get_ticks_msec()*0.001`.
`ocean_wake_visual_capture` moved **15.9% back-to-back and 88.3% minutes apart, delta 244/255**.
Its subject is a moving sea; freezing it would delete the thing the frame exists to show, so the
rig now **says so in its header and prints `WAVE PHASE … THIS FRAME IS NOT REPRODUCIBLE AND MUST
NOT BE DIFFED` on every run.**

**What was cleared before the rigs were blamed (REALITY §7).** The renderer itself is
bit-deterministic on this box: a synthetic scene of four yawed boxes gives identical md5s across
processes and across settle depths of 4/8/16/32 frames, in the main viewport and in a
`SubViewport`, with shadows on and off, with and without a translucent slab. The instrument is
fine; the rigs were reading it at the wrong moment and photographing a clock.

### The survey — two runs, no code change, % of pixels that differ

| rig | frames | moved | worst frame | cause |
|---|---|---|---|---|
| `vessel_render_capture` | 36 | 0 | 0.0000% | — |
| `trawler_render_capture` | 8 | 0 | 0.0000% | — |
| `piece_kit_capture` | 12 | 0 | 0.0000% | — |
| `structure_plate_capture` | 4 | 0 | 0.0000% | — |
| `structure_ao_capture` | 6 | 0 | 0.0000% | — |
| `_piece_kit_critic_capture` | 12 | 0 | 0.0000% | — |
| `weather_visual_capture` | 31 | 0 | 0.0000% | already calls `snap_time_of_day` per frame |
| `world_layout_debug_capture` | 3 | 0 | 0.0000% | CPU raster, seeded |
| `port_layout_visual_capture` | 9 | 0 | 0.0000% | CPU raster, seeded (still NOTRUN — no verdict) |
| `_q1_cell_shot` / `_q1b` / `_q1c` / `_q2` / `_q3` | 12 | 0 | 0.0000% | buildings, already `frame_post_draw` |
| `_warehouse_shot` | 3 | 0 | 0.0000% | — |
| `_probe_open_water_render` | 5 | 0 | 0.0000% | — |
| `_cache_render_probe` / `_ring_face_probe` | 3 | 0 | 0.0000% | — |
| `_fittings_shot` | 7 | 0 back-to-back | **3.79% across a six-minute gap, WITH the clock pinned** | see below — the hour is not the only wall clock |
| `_hold_showcase_shot` | 6 | 0 | 0.0000% | spawns no vessel at all |
| `_starter_28m_shot` | 15 | 0 | 0.0000% | **fast pair, and it carries a `BrickLayout` — so it has `ShipLight`s and the dependency. All 15 frames moved once the clock was pinned.** |
| `hull_visual_capture` | 18 | **2** | 0.8628% | grab/draw race, yawed views |
| `_small_hull_shot` | 7 | **4** | 0.1356% | grab/draw race |
| `_hull_iter_shot` | 7 | **4** | 0.0129% | grab/draw race |
| `_starter_shot` | 8 | **8** | 94.96% (12 min apart) | time-of-day light |
| `_hold_shot` | 16 | **11** | 75.94% | time-of-day light |
| `_hold_open_look` | 10 | **10** | 99.20% | time-of-day light |
| `_house_iter` | 6 | **6** | 33.04% | time-of-day light |
| `_house28_iter` | 24 | **24** | 20.22% | time-of-day light |
| `_hold_overhang_probe` | 1 | 0 back-to-back | **22.49% vs the committed frame** | time-of-day light, invisible to a fast pair |
| `ocean_wake_visual_capture` | 1 | **1** | 88.30% | **wall-clock wave phase — CANNOT be fixed** |

### What was done

`tests/support/capture_clock.gd` — `pin()` stops `WorldClock`'s per-frame push and writes
`WeatherLighting.time_of_day = 0.5` (noon), `settle()` is N frames **then** `frame_post_draw`.
Eleven rigs now call both and print the pinned hour on every run. Nothing was removed from any
frame: the lights are still on the boats, they are now photographed at a stated hour.

`tools/repro.sh` + `tools/png_repro_diff.py` — run any rig twice and byte-compare, reporting both
*what fraction of pixels moved* and *the worst channel delta*, because 95% of pixels at 1/255 and
0.9% of pixels at 241/255 are different diagnoses. **`REPRO_GAP` defaults to 780 s** for the
reason above; `REPRO_GAP=0` is the fast, weaker check and says so in its own output.

**After, with both numbers.**

| rig | before | after |
|---|---|---|
| `hull_visual_capture` | 2 of 18 moved, worst 0.8628% | **0 of 18, four runs, six pairs** — and the frames it writes are **byte-identical to `12f609f`**, so the fix changed nothing it shows |
| `_starter_shot` | 8 of 8, worst 94.96% | **0 of 8, `tools/repro.sh` with a 780 s gap, exit 0** |
| `_hold_shot` | 11 of 16, worst 75.94% | **0 of 16**, two runs ~5 game hours apart |
| `_hold_open_look` | 10 of 10, worst 99.20% | **0 of 10**, same gap |
| `_house_iter` | 6 of 6, worst 33.04% | **0 of 6**, same gap |
| `_small_hull_shot` | 4 of 7, worst 0.1356% | 4–6 of 7, **worst 0.0165%** — 8× better and NOT closed |
| `_hull_iter_shot` | 4 of 7, worst 0.0129% | 3–4 of 7, **worst 0.0102%** — NOT closed |
| `_hold_overhang_probe` | 22.49% vs committed | **0 of 1** across a gap |
| `_starter_28m_shot` | 0 back-to-back (blind) | **0 of 15** across a gap |
| `_house28_iter` | 24 of 24, worst 20.22% | **0 of 24** across a gap |
| `_fittings_shot` | 0 back-to-back (blind) | **2 of 7, worst 3.79%** across a gap — NOT closed |
| `ocean_wake_visual_capture` | 1 of 1, 88.30% | unchanged by design; now says so on every run |

**Mutation-verified, both numbers, on the rig the whole finding started from.**
`tools/repro.sh _starter_shot` with the default 780 s gap:

```
CONTROL  fixed rig        _starter_shot: REPRODUCIBLE — 8 frames byte-identical      exit 0
MUTANT   `git show HEAD:tests/_starter_shot.gd` restored over it, same 780 s gap
         _starter_shot: NOT REPRODUCIBLE — 4 of 8 frames moved, worst 20.2046%
         (starter__on_deck), largest channel delta 50/255                            exit 1
```

The comparator itself was mutated the same way: `tools/png_repro_diff.py` on the post-fix
`hull_visual_capture` pair prints `REPRODUCIBLE — 18 frames byte-identical` and exits 0; on the
pre-fix pair it prints `NOT REPRODUCIBLE — 2 of 18 frames moved, worst 0.8628%, largest channel
delta 241/255` and exits 1.

**`pin()` pins the HOUR and not the WEATHER, and that gap is measured rather than assumed.**
`WeatherField.current_game_time()` calls `WorldClock.get_game_hours_elapsed()`, which is computed
live from `Time.get_unix_time_from_system()` **whether or not `WorldClock` is processing** — so
anything sampling `WorldWeather` per frame still drifts, and `ShipLighting._update_auto_nav` reads
`fog_density` as well as daylight. Nine rigs closed completely with the hour pinned, so for those
the hour was the whole story. `_fittings_shot` did not. The remaining path is named and NOT
closed.

**Three rigs are still not reproducible and now declare their own floor**, in the header and on
stdout, rather than pretending: `_fittings_shot` **3.8% of the frame**, `_small_hull_shot`
**240 px (0.017%)** and `_hull_iter_shot` **150 px (0.011%)**. Looked at rather than counted — the difference mask is a dotted line down
the port and starboard sheer, 160 pixels off by 1/255 and 58 flipping the full contrast of the
edge. It is not the light (the clock is pinned) and it is not the hull (the frozen body's
transform is bit-identical in float bits across processes). **The residue was not traced
further.** A difference below the stated floor in those two rigs is noise; above it is real.

### The shipped frames that were re-shot, and what moved

Four sets are re-shot at pinned noon by a rig that is now reproducible across a gap. Every one of
them was previously shot at whatever game hour that wave happened to run at, so the difference is
the hour, not the boat:

| set | frames | worst vs `12f609f` |
|---|---|---|
| `screenshots/vessels/starter/` | 8 | **23.07%** (`starter__on_deck`, delta 236/255) |
| `screenshots/vessels/hold/` | 26 | **99.77%** (`hold__probe__boards_plan`, delta 134/255) |
| `screenshots/vessels/starter_28m/` | 15 | **82.50%** (`fishing_trawler__on_deck`, delta 248/255) |
| `screenshots/vessels/fishing_trawler_28m__stern_quarter.png` | 1 | **22.49%** (delta 254/255) |

Looked at rather than counted (`starter__on_deck`, before and after): the old frame has the deck
lights up — the wheelhouse windows are flat pale slabs and the deckhouse is a uniform white with
almost no shading. At noon the windows read as glazing with a frame, the deckhouse carries the
shadow gradient, and the deckhouse's own shadow lies across the deck. **The noon frame is the
better reference and that is a side effect, not the reason** — the reason is that it is the same
frame every time.

*This is worth holding against one of the reads below:* item 5g's complaint that *"three window
slots [read] the same value as the sky behind them… as holes punched to daylight rather than
glass"* is a judgement about glazing made from a frame whose lighting was set by the wall clock.

**Not re-shot, deliberately.** `screenshots/vessels/fittings/`, `screenshots/vessels/hull_15x5*`
and the `iter*` series are left at `12f609f`, because their rigs are still not reproducible (see
the floors above) and a fresh frame from a rig that cannot repeat itself is not an improvement on
a stale one. Their rigs now say so out loud.

### A SECOND WAY A FRAME LIES, and it hits the rigs that ARE reproducible

A committed PNG is only evidence if it is what the rig produces TODAY. Re-running the
byte-perfect rigs over a quiet tree and diffing against `12f609f`:

| shipped set | rig | worst frame vs `12f609f` |
|---|---|---|
| `screenshots/studio/probe_piece_*`, `probe_plate_deckhouse__*` | `piece_kit_capture`, `structure_plate_capture` | **1.4450%**, deltas to 169/255 |
| `screenshots/critic/*` | `_piece_kit_critic_capture` | **14.9112%**, deltas to 252/255 |
| `screenshots/buildings/*` | `_warehouse_shot` | **1.9322%** |
| `screenshots/decisions/q1_brick_cell__today__*` | `_q1_cell_shot` | **1.4752%** |
| `screenshots/studio/` (the other 36) | `vessel_render_capture` | **0.0000% — still current** |

Every one of those rigs is byte-reproducible. The frames are simply older than the code, and a
percentage cannot tell "the rig is unstable" from "the frame is stale" — which is almost
certainly what produced the *"up to 1.237% between identical runs"* on record. **Refreshing them
is a separate job and was not done here**; until it is, `git diff` on one of those images shows
the accumulated drift since the frame was committed, not what the commit under review did.

Note what this does to `q1`'s own guarantee: *"the 'today' pass was re-run last and came back
md5-identical, so the frames are comparable by construction"* was true when written and the
committed frame has since drifted **1.4752%** from what the rig now draws. A reproducible rig does
not make a committed frame current.

### The claims in this file that were argued from a diff of an unreproducible rig

Named, not re-opened. None of them is *withdrawn* — the point is which ones were argued by a
METHOD that could not support them.

1. **The catch-hold render paragraph (item 5, "Renders, re-shot from `tests/_starter_shot`").**
   *"The two frames named in the original report both changed… that band was the hold coaming,
   6.34 m across a 5.00 m boat… **It is gone**."* This is a before/after comparison of
   `_starter_shot` frames, and that rig was moving every one of its eight frames between runs.
   **The conclusion still stands and the method did not support it:** the rig's whole
   nondeterminism is lighting — the geometry is bit-identical across processes — so it cannot
   add or remove a 6.34 m coaming. Sound conclusion, unsound argument. Re-shot at pinned noon;
   the new frames differ from `12f609f`'s by 0.91% to 23.07%, all of it the hour.
2. **`fishing_trawler_28m__stern_quarter.png`, "figure_px 3521"** (same item). Re-run today the
   same rig prints **figure_px 3947** with no code change between them. A recorded count off an
   unpinned rig rots exactly like a quoted constant (REALITY §4d.5).
3. **The hull-form series, "Two renders apart, indistinguishable — v1 and v2 in the series"**
   (`screenshots/vessels/iter/`, `_hull_iter_shot`). A negative claim from a comparison, on a rig
   whose own run-to-run noise is 0.013%. The claim is probably right and it was not established.
4. **The deckhouse iteration reads (items 5g / 5i, `screenshots/vessels/iter_house*`).** Every
   frame in both series moved between runs — 33.04% and 20.22% worst — and **the series were shot
   over many runs at many game hours, so the frames are not comparable with each other.** One
   read is directly affected: *"three window slots the same value as the sky behind them so they
   read as holes punched to daylight rather than glass."* Re-shot at pinned noon the same glazing
   reads as glass with a visible frame. **That taste judgement was partly a judgement about what
   time of night the rig happened to run at.**
5. **`hull_visual_capture`'s 0.000% is what made this morning's bow-shoulder frames
   "attributable".** It is not 0.000%; it moves up to 0.86% on exactly `hull_15x5` and
   `hull_28x10` — the two hulls that fix was measured on. The *geometric* half of that entry
   (0.2181 → 0.0000 m and 0.4788 → 0.0000 m over 800 samples, held by
   `hull_sheer_test._check_deck_edge_matches_plate`, mutated red at −0.2266 m) is untouched and
   is what actually carries the claim.

**Argued from a single frame, so still fine:** item 5's aspect cap ("photographs as a low ledge
lying across the deck"), 5f (the bow rail is a staircase), 5i's proportion reads (60%/27% against
30%/14%), 5g's `ledge_45`-is-a-ramp and `roof_slope`-z-fights findings, and every `q1`/`q2`/`q3`
decision frame — those rigs measured **0.0000%** and the `q1` entry's own *"the 'today' pass was
re-run last and came back md5-identical"* is confirmed.

**What is built and verified**

| | |
|---|---|
| Gate | Three lanes — A `--script`, B scene, C app self-check. Capability skips are self-policing: a skipped unit that passes when forced turns the gate red. Scratch probes (`_`-prefixed) are skipped and reported. |
| Tests | Zero bare `assert()` **anywhere** — `tests/` (162 files) and `scripts/` alike, as of `29435d1`. The 16 production ones became guards that refuse loudly and leave a state the class's own queries define; none was a deletable note, and each was measured pre-guard against a `git archive HEAD` copy. **One (`ocean_clipmap`) mutation-passed** — 9 child meshes either way in debug, only the release half differs and this container has no export templates, so that guard is unverified and recorded as a finding, not a relief. `TestReport` fails a run that executed zero checks. |
| Units that cannot go red | Swept, all 107: **three found, all three now closed or accounted for.** `winding_probe.gd` scored PASS in 6 s with no assertions — now `_winding_probe.gd` (a dev note about the *engine's* BoxMesh convention, which is why converting it in place would have landed a layer below the bug) and the property is asserted on the mesh the baker commits, in `tests/box_winding_test.gd` (mutations: 3/18 and 6/18 red, control PASS 18, verified twice independently). `shipping_lane_traffic_profile.gd` was the same defect at **123 s measured, the most expensive lane-A unit** — now `_shipping_lane_traffic_profile.gd` (still a working hand-run instrument) and replaced by `shipping_lane_traffic_integrity_test.gd`, 12 checks in **25 s**: net **−98 s** off the gate. `port_layout_visual_capture` has no red path either but is already NOTRUN, so it is not scoring a false PASS. **All three are now closed or accounted for.** |
| Colour | **Free in the solid bake, priced in the studio x-ray.** The bucket key is material alone and colour rides in vertex data, so `demo_workboat` measures **3 mesh instances / 11 renderer draw calls at BOTH 22 and 64 distinct colours** — zero delta. The ghost/x-ray path still keys by colour and costs **112 instances at 64 colours**, which is what mutation-verifies the claim without editing production code. Earlier text here said "4 draw calls": wrong on both readings — buckets are 3 (`MATERIALS.size()` is the BOUND, not the count) and renderer draw calls are 11. |
| Collision | Diagonal walls collide as drawn, asserted against `PhysicsServer3D` on a real body — not against the baker's dictionaries. Every edge run's barrier is the yaw-frame BOUND of the boxes it draws, not a second formula — 0 loose corners across all nine capture fixtures. |
| Items | Float metres, free yaw + optional pitch/roll, props bag, **host-relative placement** so a fitting follows its host. Part catalog + plan-side compliance measurement exist. |
| Scale | Settled: 1 unit = 1 m, player 1.8 m, deck cells 0.5 m as a *build resolution*. `hull_28x10` is a 28 × 10 m vessel. |

**The authoring layer, which is now the whole story**

The five primitives landed and the fleet was rebuilt on them, and that exposed the error one layer
up: **`plate` is four free 3D corners, so agents authored deckhouses by typing coordinates.** A
player cannot do that. `REALITY.md` §5 is the write-up. Nothing in the gate could have caught it —
the geometry was correct, the tests honest, the renders good.

The answer is the **piece kit** (`resources/data/parts/structure_pieces.json`,
`scripts/construction/piece_kit.gd`): six pieces — `wall_panel`, `wall_glazed`, `corner_45`,
`deck_tile`, `roof_slope`, `trim_band` — placed at grid NODES on the 0.5 m cell grid, facing in
90° steps. **Every parameter takes its value from a declared finite set and every geometric
parameter is counted in grid units** (lengths in whole cells, rakes in whole quarter-cells). No
float is ever typed, which is the property that makes two pieces meet exactly. Pieces resolve into
the `plate` primitives `StructureBaker` already bakes — the baker learns no new word.

`corner_45` is the piece that beats blockiness: two raked walls meeting at 90° do NOT meet, a
wedge opens as wide as the rake, and its bilinear plate absorbs the difference. The by-product is
that a raked house is chamfered at every corner by construction.

Proven on `probe_piece_trawler.json`: **50 hand-solved quads replaced by 43 piece placements**,
zero hand-authored corners in the deckhouse. Stated limits, not hidden: a 0.24 m boat-deck camber
and a 0.30 m plan taper do not survive the grid, and the house is 2.50 m to the boat deck where
the hand-authored one was 2.74. A sheer-following bulwark stays in `edges[]`/`sheer_band` — the
kit deliberately refuses to quantise the one curve the fleet was rebuilt to draw.

**What is missing, in the order it matters**

**AUDITED 2026-08-15 against the tree, and four of the five were stale.** This list is
where the orchestrator picks the next wave, so a stale entry does not just misinform —
it dispatches work that is already done. Every item below was re-checked in the source,
not carried forward. What each one used to say is kept, because "we thought this was
missing and it wasn't" is the reusable part.

1. ~~**The tool.** `structure_studio.gd` is still `enum Tool { SELECT, WALL, DECK, STAIR,
   OPENING }` — it cannot author superstructure at all… This is the critical path.~~
   **LANDED.** The enum is `{ SELECT, WALL, DECK, STAIR, OPENING, PIECE }`, "piece" appears
   414 times in the file, and the tool has a kit palette, R to rotate, click-a-grid-node
   placement and steppers over each piece's own list ("nothing is typed"). It is covered by
   the lane-C self-check, not merely present: `_probe_piece_controls`, `_probe_piece_levels`,
   `_probe_piece_mouse`, `_probe_piece_selection`, `_probe_piece_persistence`, two fixtures
   and a recipe probe. **The kit is a feature now, not a format.** `GRID_SNAP := 1.0` vs
   `cell_m: 0.5` still deserves a look, but the file already explains it as the DRAW tools'
   snap, so it is a question, not the defect this entry claimed.
2. ~~**Geometry for `items[]`** — the mechanism exists, nothing draws the parts yet.~~
   **LANDED.** `StructureBaker._item_layers` draws spar, wire and plate primitives, resolved
   via `props.primitive` or falling back to `item_id`, and an unknown fitting draws nothing
   rather than being silently turned into a box.
3. ~~**`DeckFitout.apply_plan` still returns a hardcoded `outfit_ok: true`**~~ **LANDED.**
   `deck_fitout.gd:137` is `caps["outfit_ok"] = bool(report.get("ok", false))` and `:437` is
   the same off `outfit`. The validator is called; the verdict is the validator's.
4. ~~**No starter vessel for any new player** — `prebuilt/` holds only `.gitkeep`.~~
   **LANDED.** `resources/data/vessels/prebuilt/` holds `28_10_m.json`, `bulk_small.json`
   and `fishing_trawler.json`.
5. **No small hulls — HALF CLOSED 2026-08-15. `hull_15x5` exists and floats; a new
   player still does not start on it.**

   Was: two hulls only (28 × 10 and 45 × 16), all three prebuilt vessels the same
   `hull_28x10` — one hull wearing three outfits — and every legacy alias
   collapsing onto 28 m or larger.

   Now: **`hull_15x5`**, 15.0 × 5.0 × 2.6 m, draft 1.55, 44.0 t, `fine_entry`,
   280 kW, added through the `HullCatalog` JSON path (`CatalogHullVessel`), which
   every `HullRegistry` consumer checks first — so no registry code changed and it
   is reachable from `shipyard_brick_editor.gd:220` and `structure_studio.gd:3512`,
   i.e. **by a player, not only by a rig** (§3d). It passes `validate()` **cleanly,
   not clamp-rescued** — the design probe reports `stations_geometry()["clamped"]`
   alongside the verdict and carries two deliberately invalid candidates that come
   back `REJECT / clamped=true`, so it can tell the two apart; the gate test asserts
   both halves.

   Measured in the world against `hull_28x10` through the identical probe:

   | | hull_15x5 | 28x10 control |
   |---|---|---|
   | settled vs declared draft | 1.5489 / 1.5500 m (−0.07%) | 2.7981 / 2.8000 (−0.07%) |
   | volume below × ρ vs declared t | 44.000 / 44.000 (0.0000%) | 256.000 / 256.000 |
   | 1.8 m capsule drops, real `PhysicsServer3D` | **13/13 landed** | 13/13 |
   | full ahead + hard over | yaw −12.55°, heel 0.272° | yaw −6.73°, heel 0.350° |

   The small hull turns in half the distance at the same helm — correct for the
   shorter boat, and evidence the drive test reads the subject rather than the rig.
   Verified independently: `starter_small_hull_test` **PASS (23)**, and removing the
   hull from the catalogue reddens it **2/23**.

   **CLOSED 2026-08-15 — a new captain is granted `sjark_15m`, verified end to end.**
   `tests/starter_vessel_grant_test` **PASS (49)**; reverting `DEFAULT_STARTER` to
   `general_cargo` reddens it **2/49** (reproduced independently by the orchestrator).

   **Why it had stayed half closed was not the preset — it was the default.** The
   career defaulted to the literal `"general_cargo"` in **four separate places**
   (`company_setup_panel.gd:20`, `:51`, `main_menu.gd:20`, and the multiplayer
   starter-repair path). That is now one constant, `CompanyContracts.DEFAULT_STARTER`,
   pointed at `"fishing"`, and a mutation that re-hardcodes the string in the panel
   reddens the unit — so the constant is load-bearing, not decoration (§3d).

   Selection is **by name**, not order or cost: career → `STARTER_VESSELS[id]["prebuilt_id"]`
   → linear scan of `catalog_entries()`, refusing anything `is_draft` or not
   compliance-ok.

   **Existing players are untouched, with one exception I am accepting as a
   decision rather than a finding.** `PlayerData.ledger_vessel_record` deep-copies
   `brick_layout` per owned vessel and `_grant_starter_vessel` refuses when
   `owned_vessels` is non-empty, so an existing captain's boat is a snapshot no
   preset edit can reach; `WorldTrafficService` whitelists `["28_10_m","bulk_small"]`
   and the showcases pin explicit ids. The exception is `vessel_sync.gd:488`, the
   multiplayer starter-*repair* path for a captain with zero vessels, which now
   hands out the sjark. **Accepted:** it is the "nobody chose" path, so it should
   hand out the same thing onboarding does. Recorded here because it is a behaviour
   change, not a repair.

   **The three shipped presets changed, and the diff was characterised before it was
   trusted:** 128 cells each, **field `yaw` only**, zero cells added or removed,
   metadata byte-identical — verified independently. That is the railing fix, not the
   generator: `railing` draws its run along the local −Z face, and every preset placed
   every railing at yaw 0, so only the bow and transom runs pointed the right way and
   the port/starboard rails ran **athwartships** — a row of little gates standing
   across the deck. Not guessed: a probe placed one railing at each yaw and measured
   the drawn AABB. The 28 m boats improved too.

   `_prebuilt_gen.gd` was parameterised off `grid.width` / `length` /
   `bow_taper_cells` rather than replaced, and **the control is that all three shipped
   presets re-emit byte-identical** (md5 unchanged). Restoring one pre-refactor
   constant on the 10-wide hull produces 40+ `OFF-DECK` reports and `GEN REFUSED`.

   **Three findings this hull surfaced. One is now fixed — 2026-08-15:**
   - **The shipyard will label it "7.5 × 2.5 m".** `HullCatalog._normalize`
     overwrites the authored `display` via `ShipClass.format_display_dimensions`,
     which applies `DISPLAY_METRE_SCALE = 0.5`. `_normalize` runs **only on JSON
     hulls**, so the 15 m starter reads "7.5 × 2.5 m" directly above `hull_28x10`
     reading "28.0 × 10.0 m" in the same dropdown. The 2× is an open owner decision
     (CONVENTIONS §3a) — but it now has a **visible asymmetry**, and the smallest,
     most-seen hull is on the wrong side of it.
   - ~~**Deck plate and shell disagree at the bow shoulder**: the lofted shell is
     0.219 m per side WIDER than the flat deck plate on this hull (**0.480 m on
     `hull_28x10`**), because `pointed_deck_plate` chamfers linearly while
     `_assign_form_sections` blends with a smoothstep.~~ **CLOSED.** Two changes,
     both in `_assign_form_sections`: the entry now blends from a smoothstep
     underwater to a STRAIGHT chamfer at the deck edge, matching the plate and
     `DeckGrid.cell_shape`; and `HullStations.form_station_zs` snaps a station onto
     each longitudinal kink, without which the loft's own chord cuts the chamfer
     corner and lands **worse** (−0.341 m on hull_15x5 with the straight taper and
     no snap). Measured along the continuous drawn curves, 800 samples:
     **0.2181 → 0.0000 m on hull_15x5 and 0.4788 → 0.0000 m on hull_28x10.**
     `hull_sheer_test._check_deck_edge_matches_plate` holds it, on every hull;
     mutated back to the smoothstep it reads −0.2266 m and goes red.
   - **`ShipClass` fits nothing here.** `LAUNCH` maxes at 10.0 m authored,
     `COASTAL_TRADER` at 35.0 — so a 15 m boat gets `coastal_trader` and shares a
     class with the 28 m trawler, `BEAM_M[COASTAL_TRADER] = 24.0` against this
     hull's 5.0 (4.8×), and `berth_count` reserves a 35 m slot for it. The table is
     also non-monotonic independently of this hull (COASTAL_TRADER 24 >
     SHORT_SEA_COASTER 14). Left alone — `ShipClass` is an open owner decision.

   **Looked at, not asserted — the original observation, kept because it is what
   started the fix:** put beside the 28 m at matched scale, the silhouettes were the
   same drawing — dead-flat sheer stem to transom, blunt near-vertical stem, slab
   topsides, no rubbing strake. The scale itself was genuinely right (figure's knee at
   the deck edge; keel-to-deck 1.4 figures against 3.1 on the 28 m) and the bow-on view
   already read as real small craft — narrow V bottom, hard chine, strong flare.

   **What changed, 2026-08-15 — `screenshots/vessels/iter/v0…v12__*.png` is the
   series.** The loft (`HullStations._assign_form_sections`) draws the silhouette of
   **all 9 form hulls** — 7 in the JSON catalog plus `FishingTrawlerSmall` and
   `PassengerCatamaran` — so every one of them moved, including every vessel a player
   already owns. Three levers, all strictly **below `deck_y`**, so the ceiling the
   sheer note protects is untouched and `hull_sheer_test`'s ceiling / displacement /
   lever / plan-clearance checks are unchanged and still zero:

   - **Stations are clustered toward the ends and snapped onto every longitudinal
     kink.** Before, hull_15x5's 4.05 m bow taper contained exactly ONE station, so
     entry, forefoot and stem were all resolved by a single vertex — which is why
     every hull's bow read as a blunt wedge whatever its form said. Same station
     count (8): this buys resolution, it does not buy vertices.
   - **The stem rakes.** The forward extremity at height y is set back from the
     deck-level stem by `bow_keel_rise × depth × (1 − y/depth)`, and the levels below
     the stem line collapse ONTO it. Zeroing the widths alone was not enough and is
     the trap worth remembering: a level at its nominal Y with `half_beam == 0` still
     emits a vertex at z = −L/2, so the projected outline stayed exactly plumb. Two
     renders apart, indistinguishable — v1 and v2 in the series.
   - **The sheer is drawn, on the rubbing strake.** `sheer_forward_m` was computed on
     every hull and read by nothing that draws. A constant-height band standing proud
     of the deck edge now carries `sheer_rise_at(z)`, clamped to stay clear of the
     deck edge. The DECK EDGE is still flat — that limit is real and the note in
     `hull_stations.gd` argues it properly — but the hull has a curve in it.

   **The strake is painted in the anti-fouling material, and that is a budget
   decision, measured.** A third surface in `HullLivery.accent_color` was built and
   rendered and cost **+2 draw calls per vessel** (demo_workboat 16 → 18,
   probe_ferry_catamaran 20 → 22), reddening `vessel_render_capture`,
   `trawler_render_capture`, `piece_kit_capture` and `structure_bake_budget_test`.
   Geometry alone does not draw the line either: rendered with no material boundary,
   the band is invisible in profile at `topsides_color` (0.14, 0.16, 0.18), which is
   near black and compresses every shading difference to a few RGB units.

   **`hull_15x5` also has its own form now — `workboat_small`.** It shared
   `fine_entry` with `hull_28x10`, and a preset is a normalised SHAPE, so two hulls on
   one preset are the same drawing at two sizes by construction. Nothing else uses it.

   **Held by:** `hull_sheer_test` **123 → 258 checks**, all green, with four new
   per-hull properties — the curve is DRAWN (`_check_curve_is_drawn`), the strake band
   is PAINTED (`_check_strake_is_painted`), the stem RAKES on the baked surface
   (`_check_stem_rakes`), and the deck edge matches the deck plate
   (`_check_deck_edge_matches_plate`). Every one was mutation-verified, and two of them
   PASSED their first mutation and had to be re-pointed: a width-only stem rake (the
   vertices stayed at z = −L/2) and a strake check read at the bow (where every level
   collapses onto the stem line at `deck_y` whatever the paint does). Gate family of 43
   units: **41 PASS / 2 FAIL, byte-identical to the pre-change baseline** — the two reds
   are `structure_plate_test` and `plan_interior_test`, both pre-existing.

   **Still flat:** the deck edge, on every hull. A bare hull cannot curve its top
   line without putting plating above `deck_y`, and that is still the bulwark cap's
   job (`StructurePlan`), for the reasons the sheer note gives.

## COMPUTED AND NEVER SHOWN — the class, and the check that now holds it (2026-08-16)

**Nine values the game computed for a player and never showed**, surveyed by the HUD
wave and re-verified one by one by the next. This is the same defect as the piece kit
that was never wired, the apron props nothing draws, the fifteen catalogue fittings
that drew nothing and `PlanOutfit`'s warnings — **and every instance until now was
found by a human grepping.**

Re-verification changed three of the nine, which is why it was demanded:
- **`capabilities.max_stack_y` was DISPROVED, and the class inverted.** `capabilities`
  is a metric namespace addressed **by data** from `registrations/catalog.json`, so a
  key no rule names is inventory, not rot (14 of 17 are unaddressed). What had no check
  is the **other direction** — a rule naming a key nothing publishes reads `0` forever.
- `TOO CLOSE TO SHORE` **is** announced, by a different string, latched — but only in
  the moving branch.
- `errors[]` **does** reach players, in both brick editors; only `shipwright_npc`
  collapses the array into one sentence.

**Four were dead wires and were deleted**, because the honest fix for a wire nothing
reads is to remove it: `player.current_port_id` (one hit repo-wide — its own
declaration); `ShipState.hull_health`/`fuel` and their signals plus the same two dead
fields on `ShipData` (`GameState` assigned the *record*, not this state, and
`debug_draw` drew both as "not implemented" regardless); `instruments.bridge_watch`,
published 20×/s to nobody; and **`ContractState` entirely** — `FreightService` rebuilt
`active_contracts()` into it on every change while `debug_draw` connected to a signal
the class never declared, **dropped in silence by `_connect_if`'s `has_signal` guard**.

**`tests/state_projection_reach_test.gd` now holds the class.** It derives the
projection list from `GameState`'s own declarations, so a new sub-state is surveyed
without editing the test; **an assignment is not a read** (all three worst offenders
were being written constantly); it resolves every `_connect_if` signal name against the
class; and it prints the `file:line` it accepted for each member so the claim is
auditable by eye. Its excuse list is empty and policed both ways —
`ship_hud_readout_test` fell 264 → 262 when it emptied, which is the self-policing
working, not coverage lost.

**It found its own blind spot**: with the only "reader" a trailing comment it PASSED,
accepting a note about intent as evidence — its own defect one level up. Comment
stripping added.

### The three that were outside its reach — closed 2026-08-16, and the class is 59 wide

All three claims were re-verified independently before anything was touched, and one
was **narrowed**: running dry was not silent in the strictest sense. `ShipHud._fuel_status`
already reddens the FUEL cell below 10% and it reads `0%` in ALERT — but that is a POLL,
it is only visible at the helm, and it can only say the tank *is* empty, never that it
just ran dry. There was no event of any kind.

- **`BoatBody.fuel_depleted` — WIRED.** `GameState._wire_boat` (was `_wire_mooring`)
  now subscribes it to `ShipState.push_notice`, the surface the mooring refusal and the
  shore-block toast already use — `LocalPlayerView.ship_notice_requested` →
  `ShipHud.show_toast` → `BrandToast`, no HUD geometry, no new cell. **The wording is a
  placeholder and is the owner's**: `ENGINE STOPPED — fuel tank empty. Bunker fuel at a
  harbour fuel point.` `tests/fuel_stall_notice_test` (25 checks, lane A) drives it
  through the live tree — `node_added` → `_wire_boat` → the notice — and asserts one
  notice per crossing, none while dry, and one again after refuelling.
- **`BoatBody.fuel_changed` — DELETED.** Emitted on every write to `fuel_l`, sixty times
  a second under throttle, to nobody. The level does reach the player, by the other
  derivation: `_capture_instruments` → `fuel_fraction` → the HUD's FUEL cell and
  `ChartNavSnapshot`. Second copy of a delivered value (REALITY §3b).
- **`PrebuiltVesselCatalog`'s `compliance_errors` — DELETED.** Only readers were two
  lines of `starter_vessel_grant_test`, and a reader in `tests/` is not a reader. The
  same array is `push_warning`ed at the same site; the two verdict fields that DO have
  production readers, `compliance_ok` and `is_draft`, are untouched. The test now takes
  its errors from `VesselCompliance.validate` — reading the key back would have passed
  on an empty default the moment the key went (REALITY §4).

**`tests/signal_reach_test` (66 checks) answers the widening question: yes, and the
answer is 59.** Every `signal` declared in `scripts/` is scanned for a subscriber in
`scripts/` — an emission is not a subscription, a subscriber in `tests/` is not a
subscriber, and every accepted one is printed with its `file:line` and shape.
**178 declared, 119 subscribed, 59 not** — a third of the project's signals are emitted
to nobody. They are a FROZEN register policed in both directions, not an approval: it
can only shrink. Four of the 59 were invisible until the scan learned to attribute a
shared name by the receiver's declared type — `BulkHoldComponent.fill_changed`,
`ShipyardBrickEditor.closed` and `CaptainService.captain_created`/`captain_deleted` were
each answered for by a subscriber on the *other* class of the same name.

**Where it cannot go, counted rather than implied:** two connect sites name their signal
through a variable (both halves of `DebugDraw._connect_if`, whose own callers pass
literals the scan does read) — there is no `callable_mp` through a variable and no name
built at runtime anywhere in `scripts/`; 22 subscriptions to a shared name have a
receiver that cannot be typed and are accepted and printed; and **zero** `.tscn` files
carry an editor connection, which is asserted rather than assumed because the day one
appears the scan starts producing false reds.

**Still live, same class, outside both checks (they hold fields and signals, not
functions):** `BoatBody.fill_tank()` and `BoatBody.get_estimated_range_m()` have zero
callers repo-wide while their own headers name callers that do not exist ("used by the
shipwright on commission", "the map's fuel-range ring" — the chart draws a percentage
and no ring), and `CRUISE_SPEED_MS` exists only for the second.
`PropulsionComponent.delivered_thrust_n` is computed every physics tick and read by
nothing.

**Verified by the orchestrator, not accepted:** both units re-run at control (28 and 67,
matching), and two mutations reproduced independently — dropping the `PlayerVessel.GROUP`
guard gives **2/28 FAILED** naming the right defect ("a vessel that is not the player's
runs dry in silence"), and adding an unsubscribed `signal` to `rudder_component.gd` gives
**2/68 FAILED** at 179/119/60. The register polices growth; it does not merely count.

### What running dry actually costs, surveyed and NOT fixed

The notice is the event. Everything downstream of it is still wrong, and this is the
next milestone rather than a footnote:

- **`VesselAutopilot` has no fuel awareness at all** — zero occurrences of "fuel" in the
  file. It disengages on arrival or a 650 m route error and nothing else, so a dry boat
  stays `active`, keeps writing `_propulsion.throttle`, and the AUTOPILOT cell shows a
  destination and a distance-to-run **that never falls**. Read, not run.
- **`AutonomousVesselCaptain`** burns the same fuel through the same autopilot and its
  `_fail()` is reachable only from `_on_autopilot_disengaged` — an NPC that runs dry sits
  in `PASSAGE` forever **holding its traffic-lane lease**.
- **There is no tow, no reserve, no recovery.** `add_fuel` has exactly one caller and it
  needs the player physically at a harbour master. Running dry at sea is escapable only
  by abandoning the vessel.
- **Fuel is not persisted** — `_snapshot_into_player_data` sets `ship_runtime_state = {}`
  unconditionally and "fuel" appears nowhere in the save path. A dry tank is undone by a
  save/load, which is also why nobody noticed.
- **The stall is not silent, it is LOUD.** `BoatAudioSystem` blends the engine loop from
  `prop.throttle` — the *command*, not delivered thrust — so a stalled boat keeps playing
  `engine_load` at full. Code path read; not heard (`--audio-driver Dummy`).
- **Endurance, which explains the whole class:** trawler 840 L / 0.07 L·s⁻¹ = **3 h 20**
  at full ahead, catalog hulls ≈ 4 h. Nothing in `tests/` had **ever crossed the tank to
  zero** — every fixture stopped short (1000→500 L; 0.42/0.61 hard-coded) — which is why
  both the dead wire and the stale `delivered_thrust_n` survived this long.
- **`mooring_rejected` is wired with the same un-gated shape the first fuel version had**,
  so an NPC captain's mooring refusal would toast the player. Not changed, not verified
  reachable.

**Left as the owner's, not fixed:** a player sails a gale with only a KT number
(`weather_label`'s six authored strings reach the F3 panel alone), and a trawl streamed
below one knot catches nothing and says nothing.

---

## BASELINE — gate `20260815-081032-23858`, **111 units: 102 PASS, 7 FAIL, 1 NOTRUN, 1 SKIP**

**Measured over a QUIET tree — no wave editing — which is the only kind of full run
that means anything.** Not one failure is unexplained, and every one is on the list
below: `land_field_geography_test` 2/43 and `port_trade_profile_test` 1/130 (owner
decisions), `remote_realtime_join_smoke` (needs a live server), `structure_plate_test`
(the open slop decision), `building_blueprint_test` / `building_interior_test` /
`plan_interior_test` (the buildings decisions), `port_layout_visual_capture` NOTRUN
(autoload cascade), `ocean_wake_gpu_smoke` SKIP (self-policing, no RenderingDevice).

From 105 units / 19 FAIL on 2026-08-10 to 111 / 7. The six extra units are the checks
added since: `box_winding_test`, `shipping_lane_traffic_integrity_test`,
`building_cache_visual_test`, `visual_stamp_cache_test`, `starter_small_hull_test`,
`hull_sheer_test`.

**SUPERSEDED AGAIN — run `20260815-163256-2208`, quiet tree: 115 units, 108 PASS,
5 FAIL, 1 NOTRUN, 1 SKIP.** Not one failure is unexplained and none is new:
`port_trade_profile_test` 1/130 (the apron props no code draws),
`remote_realtime_join_smoke` (needs a live server), `structure_plate_test` 3/97 (the
open slop decision), `building_interior_test` 5/41 (**all five the open cell decision
— mutating `BrickCatalog.size_m` to the grid takes it to PASS (41)**),
`plan_interior_test` 1/56 (the mast); plus `port_layout_visual_capture` NOTRUN — a
capture script sitting in `tests/` without a leading underscore that never declares a
verdict, REALITY §4's own shape, still live — and `ocean_wake_gpu_smoke` SKIP,
self-policing.

**From 105 units / 19 FAIL on 2026-08-10 to 115 / 5.** The ten extra units are checks
that did not exist that morning, and eight of them guard defects that were invisible
until the wave that found them: `box_winding_test`,
`shipping_lane_traffic_integrity_test`, `building_cache_visual_test`,
`visual_stamp_cache_test`, `starter_small_hull_test`, `hull_sheer_test`,
`starter_vessel_grant_test`, `deckhouse_shape_test`, `plan_hull_bounds_test`,
`plan_fitting_draws_test`.

*(Superseded, kept for the shape of the day: run `20260815-103207-31656`, 112 units,
103 PASS, 7 FAIL, 1 NOTRUN, 1 SKIP.)* `land_field_geography_test` moved 2/43 → **PASS
(53)** and `building_interior_test` 15/37 → **5/41** (still red; all five are the open
cell decision).

**And it caught a regression no filtered run could: `captain_onboarding_test`, red and
NOT on any known list.** It asserted `_selected_starter == "general_cargo"` in three
places — a fourth copy of a value the starter wave had just made a constant
(`CompanyContracts.DEFAULT_STARTER`) — so it went red the moment the default career
became `fishing`, correctly reporting a change it had no business freezing. **The wave
that caused it ran two filtered families, 29 units, all green, and wrote in its own
"what I did NOT verify": *"I checked by grep that no other test names the prebuilt
presets, but grep is not a run."* That was exactly right, and this is the miss.**
A filtered gate is not a gate.

Fixed as a property: the panel's default must equal what `CompanyContracts` declares,
the declared default must have a card, and — independent of *which* career is default
and not derivable from the constant — exactly one card is pressed. Control PASS;
re-hardcoding `"general_cargo"` in the panel reddens it. The panel-ignores-the-constant
seam is separately covered by `starter_vessel_grant_test`'s own mutation, so pointing
this test at the constant is not self-referential.

Tree after that fix is **112 units, 104 PASS, 6 FAIL** — *inferred from one unit
re-run green, not from a full pass.* The remaining six: `port_trade_profile_test`
1/130, `remote_realtime_join_smoke` (live server), `structure_plate_test`,
`building_blueprint_test`, `building_interior_test`, `plan_interior_test`, plus
`port_layout_visual_capture` NOTRUN and `ocean_wake_gpu_smoke` SKIP.

**A full gate run over a tree with a live wave in it is not a baseline, and the attempt
an hour earlier proved why** (run `20260815-073150-10087`, same day, RED with 12 FAIL +
1 TIMEOUT). Six units died on `Identifier "VisualFlatten" not declared` — a half-applied
refactor, and a parse error is indistinguishable from a real defect in a results table.
The sharper one was `structure_edge_test`, which went red not on a missing identifier
but on **a plausible geometric number** ("half-beam 5.000 m at deck, 5.128 m 1.15 m
down") because the sheer wave was mid-edit in `hull_stations.gd`. That is exactly the
shape of a genuine regression. **Both cleared on the quiet run**, which is the proof the
diagnosis was right — and the reason to wait for quiet rather than explain a snapshot
away.

The list below replaces a seven-item one written on 2026-08-09 that had gone stale by
fourteen. **A stale known-red list is worse than none**: it reads as "these are the only
ones", so a genuinely new failure hides inside "the usual reds". Regenerate it from
`results.tsv`, do not maintain it by hand.

*(Historical: the paragraph here previously recorded 81 PASS / 19 FAIL / 2 TIMEOUT /
2 NOTRUN / 1 SKIP of 105 units on run `20260810-081647-26225`.)*

*Empty-catalogue family* — one root cause, `BrickCatalog.BRICKS` is `{}` and
`resources/data/vessels/prebuilt/` holds only `.gitkeep`: `building_blueprint_test`,
`shipyard_editor_ui_test`, `company_service_test`, `vessel_outfit_test`,
`vessel_registration_test`, `vessel_registration_audit_ui_test`, `hull_form_geometry_test`,
`vessel_persistence_test`, `captain_vessel_hard_persistence_test` (TIMEOUT), `catch_hold_test`.

*Not yet diagnosed, and NOT on the old list* — `chart_rewrite_integration_test`,
`chart_weather_cache_test` (weather cache fills 432 of 768 cells), `lighting_material_test`
(interior and weather-exposed variants do not differ; wetness changes neither albedo nor
roughness), `port_trade_profile_test`, `port_perf_cache_test`, `ship_display_units_test`
(**compilation failure**, not an assertion), `boat_physics_validation`,
`deck_fitout_staging_test`. None of these touch the construction path — checked by grep for
`StructureEdge`, `railing_collider`, and the renumbered fixtures, not assumed.

*Environmental / never quits* — `land_field_geography_test` (needs an owner call on world
constants), `remote_realtime_join_smoke` (opt-in, live server), `port_layout_visual_capture` /
`hull_visual_capture` (NOTRUN — no verdict at all, so they are not passing either),
`staged_vessel_visual_demo` (TIMEOUT at 240 s — never calls `quit()`).

**Method warning on that run.** It executed for ~40 minutes while the orchestrator and a subagent
were both editing the tree, so late tests read files that early tests did not. Verdicts touching
`structure_plan.gd`, `structure_studio.gd` and the piece fixtures are a snapshot of a moving
target. A gate run is only trustworthy over a quiet tree; when a wave is in flight, re-run the
specific tests rather than trusting the sweep.

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

> **⚠ THIS SENTENCE WAS WRONG, AND MEASURED WRONG ON 2026-08-15 — see item 2f.** It
> read *"Every rule addresses brick ids and brick tags (`light_nav_port`, `tag:
> mooring`) — the vocabulary that was wiped."* Surveyed over all five registrations
> (`tests/_reg_vocab_survey.gd`): of **51 resolved rules**, only **5 authored rules**
> ever named a brick id, and they were exactly the five a plan could never satisfy.
> The rest address compliance TAGS, outfit SLOTS, capacity fields, capabilities and
> measured geometry — all of which `PlanOutfit` already answered. The rule set was
> never a brick-only vocabulary; it had five brick-only rules in it, which is a much
> smaller and much more fixable thing than this paragraph claimed. Those five are
> now tag-addressed and `vessel_registration_test` holds every shipped rule to being
> answerable by BOTH build paths.

`AGENTS.md`: *"Legacy compliance/budgets do not yet apply to
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
Asserts the bake stays merged — the demo workboat bakes to **3 mesh instances** (this said 4; re-measured), which is the
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

> **⚠ SUPERSEDED — this section describes the code BEFORE vertex colour landed.** The bucket
> key is material alone now. Measured: 22 colours and 64 colours both bake `demo_workboat` to 3
> mesh instances and 11 renderer draw calls. The paragraph below is kept because it is why the
> change was made, not because it is true. It contradicted the table at the top of this file for
> long enough that a doc audit had to find it.
`demo_workboat` bakes to 4. Therefore:

- Parts that reuse an existing (material, colour) pair cost **triangles and bake CPU, not
  draw calls**. A bulwark, a mast, forty bollards and a hatch coaming in colours the plan
  already declares add **zero** draw calls.
- ~~**Every new colour costs +1 draw call on every vessel in the harbour.**~~ — false since vertex colour; see the notice above.

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

### M2 — Ship parts vocabulary · PRIMITIVES DONE, AUTHORING LAYER IS THE REMAINDER

The five primitives are built, tested and shipping on the fleet, and the container feeder proved
they scale to a 150 m hull (603 items, 251 containers, 14 draw calls, 54,942 triangles, 2 mesh
surfaces). What M2 did NOT deliver, and what M4 now inherits, is the layer above them: pieces
exist, the tool to place them does not. See "The authoring layer" at the top of this file.

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

Rewritten 2026-08-10. The list this replaces was written on 2026-08-09 and had gone stale in the
same way the known-red list had — it named the bare-`assert()` conversion and lane B as pending
when both had long landed. **A stale next-actions list sends the next wave at work that is already
done.** Regenerate this from the tree, not from the last copy of itself.

### In flight

Regenerated 2026-08-15 at `29435d1`. The table this replaces still named the collision-batch
critic and the duplicate-id wave, both landed days ago — the exact staleness the paragraph above
warns about, repeated. **Rewrite this table when a wave lands, not when you next notice it.**

| Wave | Owns | Target |
|---|---|---|
| **Staged fit-out is still O(n²)** | `deck_fitout.gd`, `deck_fitout_job.gd`, `boat_body.gd` | the synchronous path went linear by lifting the WalkDeck body out of its physics space; `DeckFitoutJob` (>1000 bricks) never got it, so the vessels that most need it are the only ones that never do. Binding constraint: **at no point may a vessel a player is standing on become non-colliding.** Fenced from reducing collider count — that is the open slop decision. Briefed to measure the staged curve FIRST |
| **The three look questions** | render probes, `building_grid.gd`, `port_trade_profile.gd`, scratch copies | brick cell, apron density, raked-plate slop have sat in Owner decisions as prose while `REALITY.md` §2 forbids settling any of them with a metric — **and nobody has looked at a render of one.** Changes no default; delivers orthographic elevations with a 1.8 m figure in frame (the last misread of this warehouse was 2.4× off, from a perspective lens with the figure 12 m off-corner) and one answerable question each |
| **`BuildingCache` drops every non-mesh visual** | `building_cache.gd`, a new gate unit, render probes | `_flatten_visuals` and `_stamp_node` reconstruct `MeshInstance3D` and only that, so the warehouse sign is drawn on no building the game stamps. Briefed to **survey all 64 bricks before touching the filter** — the pass that found this checked three — and to end with a picture of the sign, looked at |

### WHERE THIS STANDS — every red is diagnosed, nothing is unexplained

Gate `20260815-021225-7388`, 107 units: **8 FAIL, 1 NOTRUN, 1 SKIP**, from 13 FAIL
at the previous baseline. Not one failure is a mystery. Three are owner decisions,
one is an owner decision on a *look* question, one is a product blocker, one needs
a live server, one is a deliberate stated trade, one is diagnosed to a mast, and
one is a fixture defect a wave is fixing now.

**That is the milestone, and as of `3dde22e` the last holes in it are closed.**
"No test that cannot fail" was an overstatement when written: the 107-unit sweep
found three units with no path to red. Both live ones are now handled —
`_winding_probe.gd` + `box_winding_test.gd`, and `_shipping_lane_traffic_profile.gd`
+ `shipping_lane_traffic_integrity_test.gd` — and the third was already NOTRUN. The instrument is honest: no bare `assert()`
anywhere, no unit that reports no outcome, every skip self-policing, and the
scratch-probe escape works in both lanes. What remains is not "unknown failures"
— it is decisions and product work.

Two things that sweep left behind and did not fix:

- **`VesselSkinBaker._emit_face` has no winding check.** `box_winding_test`
  covers `StructureBaker._append_box` only. The two emitters are supposed to
  agree on Godot's clockwise-front convention and **nothing checks that they
  do** — the comment in the file says so rather than implying coverage.
- **`port_expander`'s re-stamp is a decision, not a repair.** The guard
  regenerates a stale port at the current generation instead of refusing it.
  Regenerate-vs-refuse is a save-compatibility call; there is no migration table
  in the repo and none was invented.

### Next, when the two waves land

1. **The owner decisions below are the critical path**, not more code. Five of the
   eight block real product questions, and three of those (brick cell size, apron
   density, the raked-plate slop) are LOOK questions that no metric may settle —
   `REALITY.md` §2. A wave is rendering all three now so the owner is looking at
   pictures instead of paragraphs. **Note that the brick-cell one is only half a
   taste question:** on land it is a BUG — `BuildingGrid.CELL_M` 1.0 against a
   drawn brick of 0.5, factor exactly 2.000, so no blueprint data produces a
   solid wall. The taste half is which of the two fixes.
2. ~~`apply_staged` (>1000 bricks) is still O(n²)~~ — **closed 2026-08-15, see
   "STAGED FIT-OUT IS LINEAR TOO" below.** The premise of this line was that a
   batch cannot span frames without leaving a vessel non-colliding; the answer was
   that it need not span frames at all, because a collider built on a node that
   is never in the tree is in no space to begin with.
3. `plan_interior_test`'s 18 in-collider march starts: 17 are the mast, 1 is the
   raked plate. The mast is real geometry; the sweep's stand-off is the instrument.
4. `_prepare_gameplay` runs a 108–113 ms `VesselCompliance.validate` as one
   indivisible step. 72% is `VesselOutfit.validate`, which walks brick by brick and
   therefore HAS a seam.

### Settled since the last baseline

- **Doors open.** `piece_interior_test` 124 checks. Root cause was that an opening's
  `height` is a length on the plate SURFACE, so a raked wall's door shrank by
  `h/√(h²+r²)`. Silent clamping 21.5% → 0.0%.
- **Three of five untriaged reds fixed** — `shipyard_editor_ui_test` 36,
  `boat_physics_validation` 54 (a check that had never passed once),
  `hull_visual_capture` NOTRUN → 50.
- **`CONVENTIONS.md` §3a was false** and is now qualified: halving `DECK_CELL_M`
  moved no STRUCTURE-PLAN geometry but halved every BRICK. A `railing` is 0.5 m
  tall with a 0.44 m post, knee-high beside the 1.8 m figure.

### COLLISION BUILD IS LINEAR — and the cause was neither the tree nor shape creation

`500 → 8000` boxes (16×): **unbatched ×357.6, batched ×15.6.**

Both "quadratics" were the SAME one: **Jolt rebuilds the body's entire compound
shape on every `body_add_shape`, and only while the body is in a space.** Out of a
space, 8000 boxes cost **17.7 ms instead of 17942**. RID reuse bought 1.7× on a
still-quadratic curve; a trimesh was near-linear but changes what collision *is*,
and was beaten 17× by the option that doesn't.

`BoatBody.begin_walk_collider_batch()` / `end_walk_collider_batch()` lift the
WalkDeck out of its space for the loop. Same boxes, same sizes, same yaws, same
order — **box count untouched, `PLATE_COLLIDER_SLOP` not gone near.** Deliberately
NOT automatic: a batch closed by `call_deferred` leaves the WalkDeck with no
collision for the rest of the frame, which is mutation M2.

A second, independent quadratic surfaced once the first was gone: writing
`_walk_deck.global_transform` notifies every `CollisionShape3D` child, and at 8000
boxes **1408 ms of 1511 was that one assignment** — the same in a space as out of
one, so Godot rather than Jolt. Now runs once per batch.

| fixture | boxes | refit before → after |
|---|---|---|
| demo_workboat | 675 | 375 → 93 ms |
| probe_trawler_bulwark | 2118 | 3225 → 229 ms |
| probe_container_feeder | 3086 | **6095 → 597 ms** |

**MY EARLIER NUMBER WAS MISLABELLED.** I recorded 2109/3673 ms as the feeder's
*spawn* cost. It is the **refit** cost: `VesselSpawn.instantiate` fits out BEFORE
the boat enters the tree, so its WalkDeck has no space and those adds were already
linear. Refit is the shipyard editor, `apply_brick_layout`, and
`ReplicationDrawingService` — real, but not the spawn path I implied.

### STAGED FIT-OUT IS LINEAR TOO — 2026-08-15

The paragraph that stood here said `apply_staged` was *"still quadratic and
untouched"*, because a batch cannot span frames without leaving a vessel
non-colliding while a player stands on it. That reasoning was sound and it was
also the whole trap: **the vessels that most need the fix were the only ones that
never got it.** The way out is that the batch need not span frames — a collider
built as a child of a `Node3D` that **never enters the tree** is in no physics
space, so there is no compound to rebuild and no `body_add_shape` at all.

`BoatBody.begin_walk_collider_staging()` / `end_walk_collider_staging()`.
`DeckFitoutJob` opens the window lazily at its first mount and closes it in one
synchronous flush, declared as its own `INDIVISIBLE_STEPS` entry —
a declaration, not a hiding place, and mutation M3 is its guard.

GAMEPLAY phase, hull_90x24, `block` bricks. **The shapes are
machine-independent; the milliseconds are llvmpipe / 4 cores and are not:**

```
bricks                    1001   1500   2000   3000   4000    over 4x n
BEFORE, WalkDeck in space  596   1217   2091   4928   9416 ms   x15.8  QUADRATIC
BEFORE, control out of it  203    294    427    686    990 ms   x4.9
AFTER,  WalkDeck in space  175    249    322    500    665 ms   x3.80  LINEAR
AFTER,  control out of it  162    237    335    499    704 ms   x4.3
```

The control varies exactly one input — whether the body is in a space — holding
boxes, sizes, yaws and order identical (REALITY §4e). Before, that one input
controlled **66% → 89%** of the phase; after, **7% → −6%**, i.e. nothing. *The
cost the fix claimed to remove is the cost that stopped responding to the input.*
Whole fit-out at n=4000: **9649 → 934 ms**, wall clock 42836 → 6735, frames 1847
→ 181. Box count untouched — `body_get_shape_count` is n+2 in both runs and
`PLATE_COLLIDER_SLOP` was not gone near.

**Is a player-bearing vessel ever non-colliding? Two questions, different answers,
and both are stated because the second one reads as a regression alone.**

- *The body leaving its space (falling through the deck).* Once, in the flush,
  17.1 ms at n=3000, inside one synchronous `_process`. Sampled every physics
  frame of a 1200-brick fit-out: **0 of 64 / 93 / 104 / 313 frames** across four
  runs found the WalkDeck out of the world's space or its slab missing.
- *Brick collision (walking through walls).* This window exists either way — the
  staged path already cleared every collider at dispatch. At n=3000:

  ```
                first box on body   all 3000 on body   integrated missing / wall
  BEFORE           1643 ms             41577 ms          15411 of 41632 (37%)
  AFTER               —                 5180 ms           5115 of  5180 (99%)
  ```

  Exposure changes from *partial for a long time* to **total for a short time**.
  The integral is 3.0× better and full collidability arrives 8.0× sooner.

Verified independently by the orchestrator, not taken on report: `deck_fitout_staging_test`,
`deck_fitout_load_bench`, `plan_collision_physics_test`, `piece_interior_test` — **4/4 GREEN**;
and the flush deferred by one frame reddens it, control PASS (66) → **2/66 FAILED**.

**Still wrong, and stated by the wave rather than found later:** the flush is the
one un-budgeted moment and it grows linearly (23 ms at 4000 bricks in a single
frame; ~115 ms at 20000 — a hitch, not a stall, but nothing bounds it). A door
toggled *during* the staging window is not checked to keep its state across the
reparent. No player capsule was actually marched on a staged vessel — "never
non-colliding" is a per-frame space+slab sample. And **no shipped fixture exceeds
1000 bricks**, so the staged path has no fixture-based measurement at all: the
game reaches the path, but it is not established that the game's *data* does.

### EVERY RED NOW HAS A DIAGNOSIS — gate `20260815-021225-7388`, 107 units

**8 FAIL, 1 NOTRUN, 1 SKIP**, down from 13 FAIL at the last baseline. Not one is
unexplained:

| unit | cause | kind |
|---|---|---|
| `building_blueprint_test` | `BuildingLayout` ignores its `_building_grid` | owner decision |
| `land_field_geography_test` | two constants, two decisions | owner decision |
| `plan_entity_id_test` | **duplicate id 34 (edge+piece) in `probe_piece_tug.json`** | fixture bug, NEW |
| `plan_interior_test` | 17 of 18 stations are the mast; 1 is the raked plate | diagnosed |
| `port_perf_cache_test` | empty building catalogue since `aabdf198` | product blocker |
| `port_trade_profile_test` | apron density is a look question | owner decision |
| `remote_realtime_join_smoke` | needs a live server | opt-in |
| `structure_plate_test` | 3 declared cost bounds, left red as a stated trade | deliberate |

`plan_entity_id_test` was NOT on any known-red list — it is a real fixture defect
found by a wave that was looking at something else entirely.

### The last six untriaged reds: SIX distinct causes, no two shared

Gate run `20260815-020629-32459`. Three PASS, three red-with-a-diagnosis.

**Two were real product defects, not test problems:**

- **`lighting_material_test`** (3/80 → PASS 80). `Palette` held **65 keys pointing
  at 33 `StandardMaterial3D` objects** — `Palette.make()` gained an `exposed`
  dimension in `79f030e` and put it in *Palette's* key, but the instance comes from
  `MeshBuilder.make_material()`, whose key is only `(color, roughness, metallic,
  double_sided)`. Exposed and interior were **one object**. In the game, not just
  the test: rain wetted everything or nothing depending on call order, and emission
  set for `emission_glass` leaked onto any non-emissive surface sharing its colour.
- **`port_perf_cache_test`** (2/4 → 1/7). `PortExpander.expand_uncached` resolves a
  definition *in place*, and both mutated fields are in `PortDataCache`'s key — so
  the first expansion of every port was a guaranteed miss stored under a key nobody
  would look up again, and the caller got a **second full expansion**.
- **`port_trade_profile_test`** — `_apron_blocked_arcs` used a *berth-machinery*
  clearance (45.3 m at size 2) as a keep-out for *decorative* props. Three stations
  on a 301.54 m dock face merged to one interval covering **100%** of it. Strip test
  over 60 ports: **35 produced zero props, 99 total.** After: **0 zero-prop ports,
  320 props.**

### STATE.md WAS WRONG TWICE ABOUT `land_field_geography_test`

It is **not** environmental and does **not** fail to quit — it runs in 21 s and
reports honestly (now 2/43, on `TestReport` instead of a private accumulator that
de-duplicated labels and printed prose). And it needs **two** owner calls on **two
different constants**, not "an owner call on world constants".

### BUILDINGS COLLIDE — closed 2026-08-15. **15/37 red → 5/41 red, and all five
### remaining are the open cell decision, proved by mutation.**

Per-brick collision: **579 shapes for 516 bricks**, where there was 1. Measured
through `PhysicsServer3D` on bodies in the tree, not from dictionaries:

| | before | after |
|---|---|---|
| standing / kneeling capsule stopped by the wall | 206/206 walked through | **0/206** |
| dropped inside, lands on a floor | 0 of 25, all fell | **25 of 25** |
| collision floor vs drawn floor | 3.000 vs 0.250 m | **0.000 vs 0.250** |
| collision top vs drawn top | 10.000 vs 6.750 | **6.750 vs 6.750** |
| doorway carries an openable door | 0 for 2 | **2 for 2**, shut door stops at 0.672 m |
| deleting every brick removes collision | 1 → 1 | **579 → 0** |

**The vessel mechanism transferred for free, and that is the finding.** No
`begin_*` call was added: `BuildingCache.instance()` already assembles into a
**detached** root, so every `body_add_shape` happens out of a space. The one-input
control on a `StaticBody3D` reproduces Jolt's compound rebuild exactly —
128/577/2048 boxes cost 0.54/2.45/8.65 ms detached against 6.34/109.25/1443.63 ms
in a space (**×11.7 / ×44.5 / ×167.0**). A building is stamped whole and handed
over; a vessel is refitted while a player stands on it, which is why `BoatBody`
needs the staging window and this does not. **Written into the header as a rule:
do not put the returned root in a tree before the shapes are on it — that is the
44×.**

**The gap was NOT closed, deliberately.** Colliders are the size of the bricks, so
the 2.000 factor is now visible *in the collision*: 5560 of 7992 wall samples open
(69.6%, down from 100%), the longest run a horizontal slot at y = 0.90 that falls
between courses; 21 of 25 floor stations have no tile directly underfoot; the
doorway's physics head is one full cell above the drawn lintel. A capsule is
stopped at every station; a point, a ray and daylight are not. **Making the boxes
bigger would have turned four of the five red checks green by hiding an owner
decision.**

**And that decision now has a measured consequence.** Mutating `BrickCatalog.size_m`
to the grid it stands on — resolution **(a)** of owner decision #1 — and changing
nothing else takes `building_interior_test` to **PASS (41)**: wall scan 0 of 7704
open, floor 25/25, every doorway check green. Verified independently by the
orchestrator in an isolated copy. **Owner decision #1 is no longer only a look
question; it is the last thing between the buildings and a green subsystem.**

**Three mutations passed first time and all three are recorded as findings**, one of
which condemns a check that had been trusted: breaking collider harvesting entirely
left *"collides as more than one volume"* GREEN at `2 shapes for 516 bricks` — the
two being door slabs hanging in the air on a building with no wall, floor or roof
collision at all. **A count cannot tell a building from two doors**, and that was
the very check written to catch "one box for 516 bricks". It is kept, named as
blind in the file, and backed by a new parity check censusing both sides through
`PhysicsServer3D` (reddens 2 of 579 under that mutation).

**Cost:** stamp 7.57 → 14.01 ms, tree entry 2.46 → 5.30, +19% at 20 buildings — but
**4 distinct shape RIDs across 11580 shapes**. The port-scale curve is quadratic in
building count *and was already quadratic with collision off at 0 shapes, before and
after alike* — pre-existing, on the scene-graph side, unattributed. `PortStructureLod`
stamping lazily is what has been hiding it.

---

*(Historical — the defect as it stood before the fix:)*

### BUILDINGS DO NOT COLLIDE — measured through `PhysicsServer3D`, not read from code

`tests/building_interior_test.gd` (lane B, 37 checks, 15 red). The recorded guess
was *"one collision box; the warehouse is solid and its doors admit nobody."*
**Half right, and the wrong half is the important one.**

**One box: TRUE** — `PhysicsServer3D` holds **1 shape for 516 bricks**.
**Solid: FALSE, and backwards.** That box spans y 3.000…10.000; the building is
drawn y 0.250…6.750. Its underside stands **2.750 m above the building's own
base**. At ground level the warehouse is a hologram: a 1.8 m capsule walks through
**206 of 206** wall stations on all four faces, through both doorways, and falls
through the floor at **25 of 25** interior stations. What is solid is a slab of air
three metres up.

**The cause is one line of arithmetic**, `scripts/core/building_cache.gd:137`:
```gdscript
col.position = center + Vector3(0.0, shape.size.y * 0.5 - 0.5, 0.0)
```
`center` is already the MIDPOINT of the cell-centre bounds; the offset term assumes
it is the BOTTOM. Half the height is counted twice, so the box floats by exactly
`(max.y − min.y) / 2` = 3.000 m. **On a one-storey building it would float less and
nobody would notice.** Independent of the pitch bug.

**The doors are painted on.** `_flatten_visuals` / `_stamp_node` copy
`MeshInstance3D` and nothing else, so the leaf and jamb GEOMETRY survives the cache
while the `BrickDoor` that owns their colliders, interact areas and F-prompt is
discarded — **0 `BrickDoor` nodes for 2 doorways**. And the drawn opening is
**1.500 m tall with a 0.750 m sill**: a 1.8 m player is 0.300 m too tall and the
threshold is 0.300 m above his 0.45 m step.

**The wall is 50% air, and a player still cannot get through it.** 0.5 m bricks on
a 1.0 m lattice: a 0.70 m capsule is STOPPED at every join (0 of 206 through), but
a point scan reads `0.50 m solid, 0.50 m open` repeating, and **at y = 0.90 m the
whole wall is one continuous open slot 18.34 m long** — 5560 of 7992 samples are
air. A raycast, a projectile, a camera and daylight all pass. That is why the shell
needs TWO instruments: a march answers "is a player stopped", only a point scan
sees a wall that is half missing. **The floor has the same defect and it matters
more** — 21 of 25 interior stations have no floor directly beneath them.

**This is a DECISION, not a repair, which is why it was left red.** Correcting the
y-offset alone (mutation M1) turns the warehouse into a solid monolith whose doors
admit nobody — 12/37, with the doorway going red at 0.000 m clear. The composite
(per-brick colliders + the pitch resolution (a)) measures **PASS (39)**, so the
file is not red by construction. It belongs beside decision #1 below.

### Owner decisions outstanding

1. **The brick cell — and it is TWO questions, not one. The land half is a BUG.**

   **On vessels**, brick size and cell pitch are the SAME constant
   (`DeckGrid.CELL_M`), so bricks still tile — everything is simply half the size
   it was. A `railing` is 0.5 m tall with a 0.44 m post. That is a taste question.

   **On land they are two different constants and they disagree by exactly 2:**
   ```
   brick drawn   BrickCatalog.size_m("block") = (1,1,1) x DeckGrid.CELL_M = 0.500 m
   pitch         BuildingGrid.cell_center_local, CELL_M = 1.0        = 1.000 m
                                                                factor  2.000
   ```
   `a70bdbc` halved `WorldUnits.DECK_CELL_M` and did not touch
   `BuildingGrid.CELL_M`. **No blueprint data produces a solid wall.** Symptoms
   that do fall out of the one factor: 0.500 m of daylight per join (exactly one
   brick), `roof_flat_4x4` drawn 2.0 m on a 4.0 m pitch, a `block_door_double`
   that draws **1.5 m for a 1.8 m player**, and a ground course floating 0.25 m
   above y=0 — the building does not touch the ground. Measured on the first
   building the game has ever had; invisible for six days because
   `resources/data/buildings/` was empty.

   **"Every symptom falls out of the one factor" was wrong, and the roof is the
   counter-example** (measured 2026-08-15 while rendering the variants; the
   over-generalisation is REALITY §4d, and it survived here because one cause
   explaining five symptoms is a satisfying sentence). Daylight between wall top
   and roof underside: **0.820 m today, 0.820 m under (a), 0.320 m under (b)** —
   *unchanged* by the fix that closes every other symptom. The cause is
   elsewhere: `brick_catalog.gd:731-735` draws `roof_flat*` as a 0.18 m plate
   **pinned to the TOP of its cell**, and `warehouse.json` puts the roof course at
   y=6 with the walls ending at y=5. The roof floats by construction. The quoted
   "0.50 m" was wrong at every variant as well.

   **Rendered 2026-08-15** — `screenshots/decisions/q1_brick_cell__*`, orthographic
   elevation and quarter, 1.8 m figure in frame, one camera rig across all three
   (the "today" pass was re-run last and came back md5-identical, so the frames
   are comparable by construction rather than by assertion). Looked at, by the
   wave and by the orchestrator:

   - **today** is not a building. It is a regular lattice of separate grey cubes
     floating in the sky, one cube then one cube of daylight, the bottom course
     hanging clear of a ground band you can see straight under. The roof slabs
     are detached dark bars hovering over the tops of the cube columns. **The
     1.8 m figure stands taller than the double cargo door.**
   - **(a)** is a warehouse: continuous wall 20.07 × 7.00 × 12.03 m on the
     ground, window band, 3.00 m door the figure walks through.
   - **(b)** is a solid shed 10.04 × 3.50 × 6.02 m whose door is **1.50 m —
     shorter than the player.**

   Two resolutions, and there is no third that leaves both constants alone:
   **(a)** give `BrickCatalog.size_m` the cell size of the grid it is drawn on
   (buildings 1.0, vessels 0.5) — buildings become solid, **no vessel moves**, and
   `size_m` gains a parameter nearly every caller must pass.
   **(b)** set `BuildingGrid.CELL_M = 0.5` — buildings become solid at **half**
   their authored size (this warehouse measures 10.04 wide × 3.50 tall × 6.02
   deep; the "10 x 6 x 3.25 m" predicted here before it was rendered was wrong on
   two axes) and every existing blueprint needs re-authoring.

   **The first three frames settle *today* and nothing else.** Today is a
   pegboard, no taste involved. They did **not** settle (a) against (b): (b) was
   rendered against today's blueprint, and re-authoring the blueprint is precisely
   (b)'s stated cost, so the shed with the 1.5 m door was (b)-minus-the-work. That
   frame was re-shot.

   **(b) rendered fairly — `q1_brick_cell__b-grid-0.5m-reauthored__*`.** The
   blueprint was migrated in memory only (`git diff --quiet
   resources/data/buildings/warehouse.json` passes), by the one rule that
   preserves metres: a brick of footprint F covers F cells, so each primary
   becomes eight placements, two per axis at doubled coordinates; floor underlays
   take the bottom layer only. 336 content primaries → **2688**, 234 surfaces →
   **936**, 0 refused; cells 780 → 5520.

   **On the envelope, (b) is indistinguishable from (a)** — 20.04 × 7.00 ×
   12.02 m against 20.07 × 7.00 × 12.03, both on the ground, every course on the
   identical metre. The wall is the same wall.

   **What differs is one defect wearing four hats: a brick wider than one cell is
   drawn once per placement, so eight copies are eight of the thing, not one of it
   at twice the size.** Visible in the frame: the 3 m cargo door becomes a **2×2
   grid of four small doors**; the windows become 2×2 mullioned; `roof_flat_4x4`
   lands as **two roofs half a metre apart**; and `wall_text_lg` becomes **eight
   "WAREHOUSE" signs** — measured, `BuildingFitout` emits 1 `Label3D` today and 8
   migrated. There is no blueprint edit that fixes those: `size_m` caps the sign
   at footprint × 0.5, so it needs a catalogue footprint of (12,6,1).

   **So (b) requires a second migration — of the vocabulary, not the data.**
   Every multi-cell brick in `BrickCatalog` must be re-cut at double footprint.
   Nothing in this file's statement of (b) mentioned that, because nobody had
   rendered it. (b) also costs **6.5× the mesh count for the identical
   building** — 645 → 4176 `MeshInstance3D` per warehouse, each copied per
   instance by `BuildingCache._stamp_node`.

   Caveats the wave stated rather than let me find: the 0.03 m width/depth
   difference is unexplained and unchased; the migrated roof's 0.320 m daylight is
   **not** an improvement over (a)'s 0.820 m, it is an extra slab underneath; the
   "every blueprint" population is **one**, and the three multi-cell bricks tested
   are 3 of 64 in the catalogue, with more expected to fail the same way; and no
   frame in this whole pass had collision enabled.
1b. ~~**`BuildingCache` silently drops every non-mesh visual**~~ — **FIXED
   2026-08-15.** The survey found the defect was bigger than the sign that
   exposed it: **16 of 64 bricks lost a visual**, and the largest loss was not a
   non-mesh node at all. `_flatten_visuals` copied a `MeshInstance3D` **and did
   not recurse into it**, so `BrickCatalog._add_door_face`'s 9 panel/stile/rail/
   handle meshes — parented to the `DoorLeaf` *mesh* — were discarded: **72 of the
   warehouse's 717 meshes**, both cargo doors stamping as blank slabs. Nobody had
   suspected that; the brief was about `Label3D`.

   Also lost: `Label3D` from 4 text bricks and from any `sign_id` plaque;
   `OmniLight3D` from all 8 light-tagged bricks; and the
   `building_lens_base_emission` metadata, so the mesh survived but
   `BuildingLighting` could no longer dim its lens.

   **The line drawn is `VisualInstance3D`, not `Node3D`** — everything in Godot
   that puts pixels on screen is one, and everything else is a transform holder
   (whose contribution *is* the accumulated transform) or a behaviour node a
   flatten-and-stamp cache cannot carry anyway. Deliberate drops are now named
   with reasons in the header: `BuildingLighting` (re-created per instance),
   `BrickDoor` (behaviour, and its loss is already red in
   `building_interior_test`), `Marker3D` anchors. **A silent drop was the defect;
   a named drop is a decision.** The duplicated five-field mesh copy became one
   `_copy_visual` (§3b).

   `tests/building_cache_visual_test.{gd,tscn}` (lane B) asserts on the tree
   `BuildingCache.instance()` returns — never on `BuildingFitout`, which is the
   layer above the defect and where it hid. Property form: for every
   `VisualInstance3D` class the fit-out emitted, the stamped tree emits at least
   as many, **per class**, so 72 doorleaf meshes cannot be cancelled out by a
   surplus elsewhere and a class the file has never heard of is still covered.
   Verified independently by the orchestrator: HEAD's mesh-only filter against
   this test is **9/20 FAILED**; the fix is **PASS (34)**.

   Two mutations passed first time and both are recorded as findings. Deleting
   `_copy_metadata` was green — the light metadata rides on `duplicate()` and
   nothing was aimed at the mesh half; a new check now reddens it 1/34. The other
   was the *mutation* being wrong, not the check: `_copy_visual` does not own the
   transform, the caller assigns it one line later.

   Measured and corrected while in there: `model_cache.gd:97` claims
   "Node.duplicate deep-copies Resources by default". In 4.6 `duplicate()` shares
   `Font`, `Mesh` and `Material` by reference and carries metadata. **Cost:** 645
   → 717 meshes per warehouse (+11.2%) plus one `Label3D` at 0.041 ms; the +72 are
   door panelling that should always have been there. Full gate over 109 units
   moved nothing — all 6 FAIL / 1 NOTRUN / 1 SKIP are on the known list.
1c. ~~The same flatten/stamp pair duplicated in `model_cache.gd` and
   `land_decor_cache.gd`~~ — **RESOLVED 2026-08-15, and the answer was not the one
   the template predicted. Both other caches were CLEAN.**

   The census — producer vs stamped, per `VisualInstance3D` class — found **zero
   losses** across all 11 `ModelCache` documents (foghorn, lighthouse, container,
   bollard, fuel station, two cranes, npc study…) and all 8 `LandDecorCache`
   variants. Max visual nesting depth is 1 everywhere, and that is **structural,
   not luck**: `ModelAssembler` emits only `MeshTransformer` and nested
   `ModelAssembler` (plain `Node3D`) and hangs each mesh off a `MeshTransformer`,
   **never off another mesh** — it cannot express the shape the old filter dropped.
   `LandDecorCache._bake_house` builds a flat row in the same file. **No defect was
   manufactured to match the buildings template**, which was the trap in the brief.

   **My briefing premise was wrong and the wave corrected it:** `DeckFitout` does
   not feed `ModelCache` at all — its callers are `ContainerNode`,
   `LighthouseBuilding`, `FogHornBuilding`, `MooringPoint`, `MooringPost` and two
   showcases, and nothing in `scripts/ship/` uses it.

   **The vessel side never had this defect either**, which closes the §4d gap left
   open above. `DeckFitout` uses no prototype cache — `create_item_visual` /
   `create_cell_mounts` add `BrickCatalog.create_visual`'s node directly. The one
   lossy step on a hull is `VesselSkinBaker`, and **0 of 12** text/light bricks are
   swallowed by the skin bake (`LIVE_TAGS` covers both), while `_merge_node_tree`
   recurses *through* a mesh (a mesh-under-a-mesh contributes 48 vertices, not 24).

   **What did land is the one-derivation fix.** `scripts/core/visual_flatten.gd`
   (`VisualFlatten.flatten/.stamp/.copy_visual/.copy_metadata`) is now the single
   implementation all three caches call; three hand-written pairs deleted, 296 →
   218 lines plus 43 shared. It takes **no flags**, and that was established rather
   than assumed: the only candidate for per-cache behaviour was `BuildingCache`'s
   named `BuildingLighting` skip, and a mutation proved it a **no-op**
   (`BuildingLighting extends Node`, so it never reached the `Node3D` test) — so it
   was deleted on that evidence, because two mechanisms for one drop is the
   duplication this wave existed to remove. The deliberate drops stay *named* in
   both headers. Cost: **+14.5–21.5% per stamp**, ~35% of which is one
   `get_meta_list()` per mesh; node counts identical, renders byte-identical
   (md5 `449e64cd…`).

   Verified independently: `visual_stamp_cache_test` **PASS (104)**,
   `building_cache_visual_test` still **PASS (34)** unchanged, `port_perf_cache_test`
   PASS — and restoring the mesh-only filter inside the shared function reddens it
   **8/90**.

   **Four mutations passed first time and all four are recorded as findings**, two
   of which were the *check* being wrong: a `gi_mode` check written as
   prototype-vs-stamp compares two outputs of the same copy routine, so a dropped
   field matches itself at the default — green on the bug. Re-anchored on a source
   fixture with a non-default value it reddens 2/104. A third is a genuine
   non-defect: `stamp` via plain `duplicate()` is behaviourally identical and
   **3.6× slower** (house 0.0435 → 0.1570 ms), so the field copy is a cost decision
   recorded in the header and **not asserted** — a wall-clock threshold on llvmpipe
   would fail for the weather. **Nothing in the gate holds that field copy.**
2. ~~**`BuildingLayout.place_footprint` ignores its `_building_grid`**~~ — **FIXED
   2026-08-15, and the survey it prompted found a FAMILY of nine.**

   All four `building_blueprint_test` reds were **one** defect, established by
   measurement rather than assumed: placing at (9,0,0) in an 8-wide grid returned
   `true`, grew `grid_size` 8→12 and **shifted every stored cell by +2**, so the block
   authored at (1,1,1) ended up at (3,1,1). "got 8 children" was not a visual defect —
   8 is exactly 6 primaries + `BuildingLighting` + `Collision`. `PASS (132)` from
   4/119; `building_cache_visual_test` still PASS (34).

   The check runs **before** `ensure_fit_cells`, and that ordering is load-bearing
   rather than tidy: a refusal issued afterwards returns `false` having already moved
   the caller's whole building sideways. Mutation M2 (same check, moved after) reddens
   2/132.

   **The mutation that matters is M3, and it is a finding.** The obvious fix — bounds-
   check the **origin cell** — **passed the entire original 119-check file**, because
   the only rejection it exercised was a 1×1×1 block one cell past the width, where
   origin and footprint are the same cell. **A brick is not a point.** Thirteen new
   checks now cover a 2×3×1 door whose origin is in bounds but whose footprint leaves
   on X, on Y and on Z when yawed — and the *same origin* at 90° must be **accepted**,
   which holds the yaw arithmetic in the accepting direction too. Reproduced
   independently: origin-only reddens "no refused placement stored a cell" and "no
   refused placement grew the volume".

   **Shipped data rejected by the new validation: zero.** `warehouse.json` has 780
   cells, 0 outside its declared `grid_size`, and loads through `from_dict`, not
   `place_footprint`; the only production caller passes `null` (freeform-and-grow) on
   every call.

2b. **NINE unvalidated placement paths. One fixed, eight named.** Two grid classes
   exist (`BuildingGrid`, `DeckGrid`), which bounds the survey;
   `tests/_placement_grid_survey.{gd,tscn}` is the instrument and every row is a
   measurement.

   **CLOSED 2026-08-15 for the worst of the eight — see 2c. Seven remain named.**

   **The worst of the eight, measured in its worst form — a legally registered vessel
   with nothing on it.** A `BrickLayout` carrying every one of the eight bricks
   `general_vessel` requires (helm, three nav lights, four bollards), authored at
   20×56 indices and written onto a **10×30** hull:

   ```
   bricks stored 8, of which OFF-GRID 8
   VesselCompliance.validate   ok=true  errors [] warnings []  8/8 legal requirements
   VesselOutfit.validate       ok=true  errors []
   DeckFitout visuals drawn    0 of 8   (in-bounds control -> drawn)
   ```

   **A General Vessel with no helm, no navigation lights and no mooring points
   anywhere on it, certified green.** Three failures compound: `BrickLayout.set_brick`
   takes no grid and returns `void` so it *cannot* refuse; `VesselCompliance._measure`
   never consults the grid; and `DeckFitout._item_is_valid` — the one component that
   knows — **drops the brick silently, destroying the evidence instead of reporting
   it.** Not fixed here: the setter fix is a signature change touching
   `_prebuilt_gen.gd`, which another wave owns. The starter-vessel wave's `OFF-DECK`
   guard lives in the *generator*, which is a second derivation covering four files;
   the one-derivation fix is to move it into the setter.

2c. **The certified-empty vessel is dead.** `set_brick(grid, cell, brick_id, …) -> bool`
   — grid **first and required**, deliberately, so an un-updated caller is a *compile*
   error rather than a silently-defaulted null. All 22 showcase calls plus every other
   caller updated. The headline, before and after:

   ```
   before   stored 8, off-grid 8   validate ok=true   8/8 legal requirements
   after    accepted 0 of 8        validate ok=false  0/8, off_grid_bricks=8
            ERROR 8 bricks sit off the deck and are not fitted: Helm console at
            (5, 1, 55) is off the 10 x 30 deck · Nav light (port) at (1, 2, 55) …
   ```

   **One predicate, `BrickLayout.cell_on_grid`, and neither obvious bound was right.**
   `in_bounds` refuses the bow half cells the `diagonal_plan` bricks exist to fill;
   `has_deck_cell` accepts a full cube hanging over the water. Measured across five
   hulls (hull_15x5 270 FULL / 10 HALF, hull_150x32 18144 / 64). Both directions are
   asserted and both mutations redden — M6 `has_deck_cell` **2/74**, M7 bare
   `in_bounds` **1/74, 2/78**.

   **Both halves of the compliance fix were needed, and a mutation proved it.**
   `VesselOutfit` skips the brick *and* raises one error naming the cells — keeping
   the error but dropping the skip (M3) leaves **7 of 8 legal requirements met by
   bricks in the sea**.

   **`_item_is_valid` was never the leak.** It gated only `create_item_visual` /
   `mount_item_gameplay`, while `apply_sync` fed everything to the skin session first
   — `VesselSkinBaker.Session` never asks the grid, and an off-deck block bakes 36
   vertices exactly like an on-deck one. `DeckFitout.on_deck_items` now partitions
   once, at the top of both entry points, before anything draws. M4 quantifies the
   leak: **924 vs 828 vertices**.

   **The generator's guard is deleted** — `_on_deck` is gone from `_prebuilt_gen.gd`
   *and* from a second copy in `_house_iter.gd`; the generator keeps only its policy.
   Control: all four prebuilt JSONs re-emit **byte-identical, md5 unchanged, GEN OK,
   zero OFF-DECK** — verified independently. Shipped data rejected: **zero**, 1254
   cells re-measured, 0 off by either bound.

   **THE STRIP TEST IS THE FINDING (REALITY §3d): the report reached nothing.**
   `shipyard_brick_editor.gd:3058` read `if not errors.is_empty() and
   checklist.is_empty():` — so errors were shown **only when no registration was
   chosen**, i.e. never in the state you can actually build in. Every error the whole
   chain computed was discarded one line before the Label. Fixed, and
   `shipyard_editor_ui_test` now asserts the sentence is on screen with the deck's
   dimensions and the cell index. Restoring that clause reddens three checks
   — *"the rules panel TELLS the player which deck the brick missed"* — reproduced
   independently by the orchestrator.

   **From the killed attempt: taken and discarded, with reasons.** Taken — the single
   predicate and the grid-as-parameter argument, which is checkable and was checked:
   the headline layout's own `hull_id` resolves to a 20 × 56 deck on which all eight
   cells *are* in bounds, so a layout carrying its own grid would have certified the
   headline vessel green. Discarded — its 7-arg `_result` signature change, the thing
   that broke the tree, **was never needed** (`_result` already receives `outfit`, so
   the count comes off that dictionary); its `_accepted_on_grid` post-filter, wrong
   layer, re-walking slots that `VesselOutfit` builds with the grid already in hand;
   and its `set_meta("brick_placement_faults")`, which **nothing reads** — a meta with
   no consumer is not a delivery.

2d. **The plan side is fenced — CLOSED 2026-08-15.** `StructurePlan.add_wall/add_deck/
   add_stair/add_piece/add_item` still refuse nothing **at the setter, deliberately**:
   a plan entity has no grid at authoring time, so the fence is at the *consumer*.
   That is a different shape of fix from `BrickLayout.set_brick` and worth knowing.

   **"On the hull" is not "on the deck", and the number settles it.** Measured over 19
   shipped fixtures — 2342 entities, 15 057 drawn boxes:

   | rule | shipped entities refused |
   |---|---|
   | every corner inside the deck rectangle | **61** |
   | any corner inside the deck rectangle | 10 |
   | **every corner inside rect + `half_beam`** | **0** |
   | every corner inside rect + 1 m | 2 |

   Real ships legitimately cross the deck outline — stem faces, cap rails, rubbing
   strakes, a davit block. The margin is the hull's **own half-breadth**, not a chosen
   constant. Worst shipped entity stands 4.000 m clear against a 5.00 m bound; the
   off-hull slab stands **890 m** clear.

   ```
   as authored                  bake AABB 910.0 x 910.0 m   colliders 17
   after, through PhysicsServer3D   drawn 4.0 x 4.0 m       plan shapes  1
   ```

   **The killed patch's any-corner rule was discarded with a measurement**, and the
   reason generalises: on the buildings side "a wall has extent" made the check
   *stricter*; here it was being used to make it *looser*. A 900 m wall with one end
   bolted to the deck bakes a 902 m AABB and the any-corner rule refuses none of it.
   Both readings refuse 0 shipped entities, so the loose one bought nothing.

   **The warning/error gradient was deliberate and was kept.** Measured over the part
   catalog: slot fittings warn, cargo errors — and **12 parts are silent, including
   `bollard_pair` and `lantern_all_round`**, exactly the fittings `general_vessel`
   counts. The defect was the silent third case, not the gradient. The new hull fence
   is a separate coarser band; the deck-level split is untouched and pinned so
   collapsing either half reddens.

   **`PlanOutfit`'s warnings channel had no consumer anywhere in the project** —
   §3d again, and worse than the shipyard case, because `structure_studio.gd` (4205
   lines, the one place a plan is authored) **never called `PlanOutfit` at all.** The
   STRUCTURE panel now carries "N OFF THE HULL — NOT BUILT" and names the entity;
   lane C `studio_probe` 104 → **109 checks**, and blanking the line reddens 1.

   **A mutation passed first time and was a blind check**: baking the authored plan
   while colliders stayed partitioned left the test green — nothing asserted the
   *drawn* geometry through the production path, so a fix that kept the mesh would
   have left 910 m of visible steel. The added check reddens 1/45.

   **`part_local_aabb` answers for geometry it does not draw.** The first cut refused
   **9 shipped entities** — three fender lanyards and six trawl warps, all `wire`.
   `StructureBaker` draws `plate`/`spar`/`wire` from the item's own props, but the
   `wire` PART declares no `points`, so a **0.33 m lanyard was measured with the
   catalog's default 8.0 m run** and landed 8 m off the side of a 10 m boat. Because a
   wire is drawn and never collided, **every collider count stayed green while nine
   pieces of rigging would have vanished from the render** — which is why the fixture
   sweep now compares vertices as well as colliders. Verified independently: shrinking
   the envelope to the deck reddens the overhang checks. Shipped fixtures rejected:
   **0**. Cost: `compliance` restructured to one pass, feeder 277 → 170 ms.

2f. **`general_vessel` could never be met by a plan-built boat — CLOSED 2026-08-15,
   and the headline was FIVE of 8, not four.** Measured through the production path
   (`VesselSpawn.instantiate` → `DeckFitout.apply_plan` → the boat's own
   `vessel_outfit` meta, `tests/_reg_headline.tscn`), on a plan carrying every
   catalogue part that bears on the licence:

   ```
   BEFORE  general_vessel     3 of 8 met   FAILS 5   registration_ok=false
   AFTER   general_vessel     8 of 8 met   FAILS 0   registration_ok=true  ok=true
   BEFORE  fishing_vessel     5 of 10                AFTER 10 of 10
   BEFORE  passenger_vessel   6 of 12                AFTER 11 of 12  (cabin, below)
   ```

   The fifth failure this entry missed is `white_light_height`:
   `VesselCompliance._white_height_delta` hardcoded FOUR brick ids of its own and
   returned −1.0 for every plan ever authored. `plan_compliance_test` had it right
   all along — it listed five failing rule ids, and this entry said four.

   **THE SURVEY (step 1), and STATE.md:441 was wrong.** *"Every rule addresses brick
   ids and brick tags"* is false. Over **all five registrations, 51 resolved rules**
   (`tests/_reg_vocab_survey.gd`): 1 addresses an outfit slot, 3 a compliance tag,
   3 measured geometry, 1 a capacity field, 1 a capability, 1 a rating ceiling — and
   only **5 authored rules** addressed a brick id. Those five, inherited by all five
   registrations, were **26 of 51 resolved rules a plan could never satisfy**; a
   brick layout could satisfy **51 of 51**. The one non-light entry in that 26 is
   `passenger_vessel/cabin`, which is the separately-recorded `has_cabin` gap.

   **WHAT A PLAN CAN OFFER, measured, not assumed.** 15 catalogue parts carried tags
   `{mooring, helm, bulk_hold, light, nav_white, fishing}` and slots `{helm, fishing}`;
   64 bricks carry 51 distinct tags. **Zero part ids collide with brick ids.** So
   `white_light` (`tag_count nav_white`) was already the ONE `general_vessel`
   equipment rule a plan passed — same law, tag-addressed — and the addressing mode
   predicted the failure exactly.

   **THE VOCABULARY DECISION: tags, argued from that.** Not "the catalogue grows
   parts carrying the brick ids", because (a) 2e had just RENAMED two ids apart for
   colliding across two vocabularies and made `PartCatalog` refuse such an id at
   load — re-introducing cross-vocabulary id sharing one wave later contradicts a
   fence this repo had just built; (b) id-addressing had already failed inside the
   brick path alone, before any plan existed: `_white_height_delta` had to hardcode a
   LIST of two white ids because two bricks are one legal light, and that list was a
   tag written in GDScript; (c) it would have needed `light_nav_white` in the part
   catalogue as well, duplicating `lantern_all_round`, giving one lamp two ids.

   Landed: tags `nav_port` / `nav_stbd` on the two bricks AND on two new parts
   (`lantern_sidelight_port`, `lantern_sidelight_starboard`); `port_light` /
   `starboard_light` → `tag_count`; a new `tag_side` rule kind for the two side
   rules; `_white_height_delta` reading all three terms by tag; `tag_positions`
   built in the SAME loop as `tag_counts` on both sides (§3b).

   **THE LAW DID NOT MOVE.** A plan vessel must still carry a red light to port, a
   green one to starboard and a white one above both. Pinned from both directions:
   an UNLIT plan is still refused, by exactly those five rules, and deleting one
   sidelight from a certified plan refuses it again naming `port_light`,
   `port_light_side`, `white_light_height`.

   **No brick vessel stopped certifying.** All four prebuilt presets re-measured
   through `VesselCompliance.validate`: `28_10_m` 10/10, `bulk_small` 11/11,
   `fishing_trawler` 10/10, `sjark_15m` 10/10 — **GEN OK, four of four**, unchanged.

   **§5 — AND THE BLOCKER HAD ONLY MOVED.** Structure Studio had **no fitting tool
   at all**: `enum Tool` was `{SELECT, WALL, DECK, STAIR, OPENING, PIECE}` and
   `add_item` appeared **nowhere** in its 4205 lines, so **17 of 17 catalogue parts
   were unplaceable with a mouse** — every object a registration counts was
   authorable in JSON and nowhere else. `_recompute_bounds` did not bound items
   either, so a fitting in a loaded plan could not be clicked, focused or deleted.
   Landed: an `I` FITTING tool with a palette off `PartCatalog.ids()`, R turning by
   the part's OWN declared `yaw_step`, ghost-then-click sharing one placement
   function, item bounds derived from `PlanOutfit.item_world_points` (the one
   derivation). Lane C `studio_probe` **109 → 132 checks**, including
   *"A VESSEL BUILT WITH THE MOUSE IS CERTIFIED A GENERAL VESSEL"* — eight fittings
   placed through palette clicks, level presses and viewport clicks, never
   `_plan.add_item`. Capture: `screenshots/studio/structure_studio__fitting_tool.png`.

   **The check nobody had written.** `vessel_registration_test` (74 → 83) now asks of
   EVERY rule of EVERY registration whether both build paths can address it. It
   names the one remaining one-sided rule explicitly — `passenger_vessel/cabin` —
   by equality against a known set, so the NEXT one reddens rather than being
   absorbed. Its control is a made-up tag and the OLD sidelight rule, which it still
   reports as one-sided.

   **THE LIMIT NAMED:** a fitting is placed at its DECLARED DEFAULT parameters. A
   part's `params` is a continuous `{default, min, max}`, not the finite `values`
   list a kit piece declares, so there is no declared step to walk and this studio
   does not invent one. Sizing a fitting is the next tool.

2e. **The catalogue fittings drew nothing — CLOSED 2026-08-15.** The strip test, run
   through the production path (`VesselSpawn.instantiate` → `DeckFitout.apply_plan` →
   the scene tree, mesh census off the committed `ArrayMesh`, collider census off
   `PhysicsServer3D`), `tests/_fitting_strip.tscn`:

   ```
   AS AUTHORED     18 fittings | 12 triangles  1 mesh instance  1 plan collider
   ITEMS DELETED    0          | 12 triangles  1 mesh instance  1 plan collider
   ```

   Identical; the 12 triangles are the deck plate under them. **All 15 catalogue part
   ids drew nothing** — including `spar` and `wire`, whose ids collide with baker
   primitive names, so `_item_layers` took the primitive branch and `spar_path` found
   no `from`/`to` in a props bag carrying the part's `length`/`radius` parameters.
   Meanwhile `PlanOutfit` counted all 18: `brick_counts` 18, `tag_counts`
   `{mooring: 4, helm: 1, bulk_hold: 1, light: 1, nav_white: 1, fishing: 1}`.

   **NONE of them was abstract.** All 15 describe a physical object in their own
   `description` field. `part_catalog.gd`'s header had specified the fix verbatim —
   five emitters on `StructureBaker` named by `PRIMITIVES[p].emitter` — and
   `structure_edge.gd`'s header named two of the five again. Neither was ever
   written, so `baker_supports()` was **false for all five primitives**,
   `emit_boxes()` returned `[]` for every spec, and every part was unbuildable.
   Landed: the five emitters, one shared spec transform, one expansion feeding BOTH
   `_item_layers` and `_item_colliders`. After: **15 of 15 draw**, 18 fittings
   contribute **+1844 triangles, +123 collider shapes**. Shipped fixture diff: 19
   fixtures, **282 972 vertices, 94 324 triangles, 15 073 colliders, every bake AABB
   byte-identical to `3cd289d`** — no shipped item is a catalogue part, so nothing
   moved.

   **Compliance still counts them, deliberately.** With the fittings deleted the same
   plan loses `helm`, `nav_white`, `white_light_height` and `mooring_points` — 4 of
   `general_vessel`'s 8 requirements — so the boat stops certifying. "Stop counting
   what we cannot draw" trades an invisible bollard for an unregisterable boat, and
   `plan_fitting_draws_test` pins the counting alongside the drawing so neither half
   can be fixed by breaking the other.

   **The two colliding ids are renamed, not deleted:** `spar` → `spar_run`, `wire` →
   `wire_run`, matching `railing_run` / `sheer_band_run`, which never collided. 916
   shipped items spell `item_id: "spar"` / `"wire"` meaning the baker primitive, so the
   shadow could not be resolved the other way. `PartCatalog` now **refuses at load** a
   part whose id spells a primitive, naming it — the ambiguity is an error rather than
   a silent hole. `PlanOutfit` no longer calls a raw primitive an "unknown fitting":
   it is measured as geometry and carries no compliance identity, which is a different
   sentence from "the catalog has never heard of it" and saves 916 lines of noise.

   **Three checks asserted the defect (REALITY §4c)** and went RED on the fix:
   `part_catalog_test`'s *"no primitive is bakeable yet, so no part is buildable yet"*
   and *"StructureBaker has none of the five emitters yet (this test's premise)"*, and
   `plan_item_handoff_test`'s *"plate is declared-but-unbuildable, and says so"* /
   *"emit_boxes returns nothing for an unimplemented primitive"*. All four restated
   the missing feature as correct behaviour; all four are now the property
   (buildability AGREES with the baker's method list, in both directions).

   **`part_local_aabb`'s two other readers are one derivation now.**
   `item_hull_points`, `item_footprint_cells` and `max_stack_cells` all read
   `PlanOutfit.item_world_points`. The wire overstatement is **+4.00 m → +0.00 m**,
   but the wire was the small half: the same reading was applied to every `spar` item
   and `spar` was a catalog id, so air draught came out **31 cells / 15.5 m on
   `demo_workboat` against a drawn top of 10.04 m** and **30 / 15.0 m on
   `probe_trawler_bulwark` against 9.26 m**. Now 20 and 18, which floor the bake AABB
   exactly. `capabilities.max_stack_y` has no consumer, which is why a number 5.5 m
   wrong sat unread — §3d from the other end.

   **A mutation passed first time and was a blind check** (standing order 8): the
   first air-draught assertion used only a boom lying FLAT, which catches an
   overstatement. After the rename the failure mode inverted — `part_local_aabb`
   answers `ok=false` for an id the catalog no longer holds, so reverting the fix
   *understated* and the check stayed green. It now carries an upright post and a
   plate, and reddens 2/20.

   Renders in `screenshots/vessels/fittings/` (7 frames, orthographic where size
   could be misread, 1.8 m figure measured visible in every one). What they show:
   the guardrail, the bollards, the hold coaming and the mast all read at credible
   size against the figure, and the deck reads as a working deck where it was bare
   before. The one thing that does not read is `funnel_tapered` — a pure white
   flared drum that is the loudest value in the frame on a dark boat. That is
   catalogue data, not geometry, and it is named rather than tuned.

   Also named and left: `BrickLayout.from_dict` trusts a save file's cells verbatim,
   so an owned vessel is never re-checked against its hull; `StructurePlan.add_wall/
   add_deck/add_stair/add_piece/add_item` refuse nothing and the baker **draws and
   collides** whatever it is given (strip-tested: bake AABB 4×4 m → **910×910 m**,
   colliders 1 → 17); `add_container_pad(…, null)` skips its own check (latent — both
   production callers pass a grid); and `BuildingRules.validate`'s bounds check
   re-reads the *already-grown* grid, so it can never fire for anything built through
   `place_footprint`, and is a warning rather than an error.
3. ~~**`land_field`: does OPEN_WATER promise a distance?**~~ — **BROKEN CHECK over a
   REAL world change. Fixed 2026-08-15, and the history recorded here was wrong.**
   This entry said the bound had no derivation and framed it as a choice about world
   constants. Bisected instead, by restoring `c584530`'s generator and world data into
   a scratch tree and running the *old* test over all four combinations:

   | generator | `norway_coast.json` | result |
   |---|---|---|
   | day-one | day-one | **PASS (43)** |
   | today | day-one | 1/43 |
   | day-one | today | 1/43 |
   | today | today | 2/43 (the baseline) |

   **The bound was TRUE of the world as first shipped**, and either world change breaks
   it alone (`lobes_min/max` 2–4 → 3–5, `coast_amplitude_m` 1850 → 2800 — the
   archipelago reached west). It was a world-shape invariant nobody restated when the
   world was deliberately re-shaped, and it sat here for six days labelled a decision
   about constants. **What it reported was real; what it asserted was a number with no
   derivation and no consumer.**

   **Nothing outside `tests/` reads `Region.OPEN_WATER`.** `classify_region`'s only
   production caller is `CoastalPortPlacer`, which branches on MAINLAND/FJORD/
   ARCHIPELAGO and folds everything else to MAINLAND — so the label cannot promise a
   player anything, because no code the game runs asks it. (The exposure *field* is
   different: `WeatherComposer._exposure_at` consumes it for sea state, which is why
   `COASTAL_DISTANCE_M` is a genuine taste question and the region enum is not.)

   **Rendered rather than argued** (`screenshots/decisions/open_water_promise__*`):
   the plan view shows the cut as a straight red longitude line drawn without
   reference to where the islands landed, with the 5 km ring round the sample visibly
   clipping the northern island. Ray-marched at the player camera's own 75° FOV with a
   1.8 m post for scale, **3779.9 m and 6368.5 m (the sample that PASSED) are the same
   picture** — land as an 8–13 px strip on the horizon.

   Now: the premise is `> COASTAL_DISTANCE_M` (past the last distance-driven falloff,
   which is what the neighbouring shelter/exposure checks actually need), the
   deep-offshore twin is an **ordering** rather than a second copy of a threshold, and
   a **raster-wide property** replaced the single point — no OPEN_WATER cell is land,
   and every one clears the coast by more than one raster cell (0 of 10794, minimum
   1386.0 m against a 156.25 m cell). **The old check was blind where this is not:**
   moving the cut to −11000 puts 91 land cells inside OPEN_WATER and the baseline file
   still reports its usual 2/43, unchanged; the new one reddens 2/53 at −559.0 m
   (reproduced independently by the orchestrator).

   **What remains for the owner is smaller and sharper:** *should the world keep sea
   room offshore at all?* It is one bound in one function now, holding the whole label
   instead of one coordinate, and at 5000 m it goes red today (32.1% of open-water
   cells sit inside 5 km). It gates nothing.
4. ~~**`land_field`: `COASTAL_DISTANCE_M` vs the band sampled.**~~ — **BROKEN CHECK.
   Fixed 2026-08-15. This entry, and the orchestrator's framing of it, were both
   wrong about *why*.**

   The claim here — and my brief — said `coastal_exposure < 0.80` was *arithmetically
   impossible* past ~1306 m. **It is not.** `coastal_exposure = coastal_opening(d) ·
   mean_fetch^0.65`, and the smoothstep is only a **ceiling**: at 1383.4 m the check
   needs `mean_fetch < 0.9070`, and **308 of the 338 samples beyond 1306.1 m do read
   under 0.80** because their horizon is blocked. The bound is not impossible for the
   band. It is impossible for **the point the scan picks**.

   **The defect is sample selection.** `_find_water` returns the first raster-scan
   hit, `(-12500, -15000)` — the south-west fringe of the belt and **p99.7 of the
   2148-sample band** whose p90 is 0.7402. The file's own comment twelve lines below
   already said so ("the first hit lands on the seaward fringe of the belt, which is
   the most exposed water in the band") while the line above held that sample to the
   band's ninetieth percentile. It **passed** on 2026-08-09 at the same seed and the
   same bound, and its sibling on the same instrument (`fjord has low coastal
   exposure`) was failing then and passes now — two single-sample bounds swapping
   colour across world changes neither mentions.

   Now: `land_field.gd` names `COASTAL_RAMP_FOOT_M` (was a bare `80.0`) and exports
   `coastal_opening(d)`, which `coastal_exposure` calls — one derivation, shared by
   field and test. The check is three properties: the sample is inside the ramp,
   exposure stays under its own ceiling, and — **with no constant at all** — at a
   kilometre the wave field has saturated while the exposure field has not. Nothing
   depends on the value of `COASTAL_DISTANCE_M` any more.

   **A mutation passed first time and was closed.** Flooring `coastal_opening` at 0.95
   left the ceiling check GREEN at `0.9176 ≤ 0.9500` — **one derivation cuts both
   ways, and the bound moved with the break.** Four non-self-referential shape checks
   were added (zero at the foot, saturated at the top, monotone, actually rising);
   that mutation now reddens 6/53.

   **Still blind, stated:** weakening the fetch discount (0.65 → 0.20) passes both new
   exposure checks at `0.8434 ≤ 0.8524` — the ceiling bounds the proximity term and
   says nothing about the fetch term's strength. Only `fjord has low coastal exposure`
   catches it, 1/53.
5. **Apron props — NOT a density question. The props are never drawn at all.**
   Filed here for days as "how densely should an apron be dressed, a LOOK question
   no metric decides". Rendering it 2026-08-15 found the frame empty and then
   found why: **`PortLayoutGraphVisualizer._stamp_apron_decor()` has no callers
   anywhere in the repo** (verified independently — one definition,
   `port_layout_graph_visualizer.gd:1166`, zero call sites outside probes).
   `_rebuild()` does not call it and carries the comment *"Apron props deferred —
   layout first via asphalt/apron gizmos, then decorate"*. The decorate step never
   landed. `apron_decor` is produced by `PortLandPlan`, consumed by that dead
   function, by `port_trade_profile_test`, and by nothing else.

   **This is the piece-kit defect again** (REALITY §3): a subsystem measured,
   tested and argued about at length that the running game never reaches. The red
   `port_trade_profile_test` check "apron should sprinkle service props" is
   asserting a density on data that reaches no frame — it is 1/130 against
   geometry no player can see. `screenshots/decisions/q2_apron__asshipped-nothing-drawn__*`
   is the strip test in image form; every other q2 frame exists only because the
   probe called the dead function by hand.

   Also measured, and it kills the tuning premise independently:
   **`APRON_DECOR_STEP_M` is not the governing constant.** 20 m → 5 m is a 4×
   change and moves the count 2 → 4 → 4 → 7, and no prop ever lands past
   x ≈ 191 m of a 301.5 m face at any value. The real bound is elsewhere — the
   blocked-arc skip, `_near_quay_station`, or `APRON_DECOR_MIN_SPACING_M`. Tuning
   the step to satisfy `>= 3` would have been tuning the wrong knob to green a
   check on invisible data.

   **The owner question is no longer "how many" but "at all?"** — should aprons be
   dressed with props, yes or no? Nothing tuned, nothing wired.
5b. **The traffic simulator stalls at 250 vessels, and nothing in the gate would
   notice.** Found 2026-08-15 while replacing the traffic profiler, by a wave
   that considered `collisions == 0` as an assertion and measured it before
   asserting it. True at 24 vessels; at the profiler's own fleet — seed 42, 35
   ports, **250 vessels** — the simulator reports **3 collisions** and parks
   **226 of 250 in `scheduled_strategic`**, with `trips_completed` frozen at 25
   from t = 2000 s onward. The traffic stops.

   Deliberately **not** asserted: turning it red is a decision about a live
   product defect, not a test-instrument repair, and that wave was fenced to the
   instrument. It is recorded in both traffic files' headers so the next reader
   meets it. **After the profiler change nothing in the gate goes red if this gets
   worse** — the new unit runs 24 vessels, and the 250-vessel regime is now a
   hand-run instrument only. That is the honest cost of the −98 s.
5c. **`ShippingLaneNetworkBuilder.validate()` cannot see a port that publishes no
   gates at all.** Its `missing_port_gates` check iterates
   `network.port_gate_nodes.keys()`, so a port absent from that dictionary is
   absent from the check. Measured: a network missing one port's gates entirely
   reported **0 issues**. The new integrity test catches that case by comparing
   against the placed-port count; the validator still should.
5d. **The RSW fish hold overhung the starter boat by 1.130 m and stood over open
   water — CLOSED 2026-08-15.** The hold is now sized and placed by the boat it
   is on; **zero overhang on every hull**, held by a property check, four
   mutations verified.

   Was: `DeckFitout._mount_fishing` attached a `CatchHoldComponent` at a
   hull-independent size AND a hull-independent position —
   `hold.scale = Vector3(1.10, 1.0, 2.10)` and `gear_local + inward_z * 6.1` —
   so the same drawing landed on a 10 m beam and on a 5 m one. Measured identical
   in absolute metres on both hulls: local x **−3.168 … +3.630 m**.

   | measured, per hull | before | after |
   |---|---|---|
   | `hull_15x5` (half-beam 2.500) starboard overhang | **1.130 m** | **0.000** |
   | `hull_15x5` port overhang | **0.668 m** | **0.000** |
   | `hull_15x5` **bow** overhang (not in the original report) | **0.157 m** | **0.000** |
   | `hull_28x10` (half-beam 5.000) overhang | 0.000 | 0.000 |
   | brick columns standing inside the hatch, `sjark_15m` | the whole deckhouse — `railing block block_window roof_flat helm block_door mast_base mast_pole` | **none** |
   | brick columns standing inside the hatch, `fishing_trawler` | the whole deckhouse — same list minus the railings | **none** |
   | 1.8 m capsule standing positions clear around the hatch (`PhysicsServer3D`) | sjark **1 of 4**, trawler 4 of 4 | sjark **4 of 4**, trawler **4 of 4** |
   | `capacity_kg` on both hulls | 4000 | **4000 — unchanged** |

   **THE SURVEY — the count of affected vessels is two, and the previous wave's
   "shared with every existing fishing vessel" is right only because there are
   two.** `PrebuiltVesselCatalog` ships four presets; exactly two carry a brick
   tagged `fishing`/`trommel` and therefore a hold: `fishing_trawler`
   (`hull_28x10`) and `sjark_15m` (`hull_15x5`). `28_10_m` and `bulk_small` mount
   none. Both affected ones were wrong — the sjark over the side, and **both** with
   the hatch inside the wheelhouse, which the original report only noticed on the
   sjark. Two further facts the survey turned up: any player build gets one the
   moment a `trommel_small` is placed and accepted (`accepted_slots.fishing` is
   populated even when the registration verdict is `ok=false`), and **a
   structure-plan vessel can never have a hold at all** — `apply_plan` has no
   fishing branch, so the whole feature is reachable only from the brick path.

   **CAPACITY DOES NOT MOVE, and it never could have.** `capacity_kg` is a
   declared number passed to `configure()`; the drawn mesh feeds nothing.
   Verified by reading every consumer: `FishingSystem:448`,
   `FishLandingPump:102`, `GameState:199`, `crane_showcase:961` and
   `catch_hold_showcase:84` all read `state.capacity_kg`. Both hulls measure
   **4000 kg before and 4000 kg after.** The only thing that referred to the
   drawn size was a comment.

   **THE CONSTANT WAS NOT A VICTIM OF THE 2.000 FACTOR.** Its comment claimed the
   mesh was "authored in displayed metres" and needed expanding "into grid space",
   which is the `DeckGrid.CELL_M` 0.5 / authored-metre confusion of owner decision
   #1 — but a unit conversion would be **2.000 on both axes**, and this was
   **1.10 and 2.10**, with 1.000 in y. It was a hand-tuned fudge to fill the 28 m
   deck with the half-scale story attached afterwards. The replacement derives in
   METRES from `half_beam` and `half_loa`, which are **invariant** under that
   decision: measured over all nine registry hulls, `half_beam == beam_m / 2` to
   ±0.000000 (`floor(beam/C) · C · 0.5` cancels `C` for any beam that is a whole
   number of cells, which every shipped hull is at 0.5 **and** at 1.0). Nothing
   in `BrickCatalog.size_m`, `BuildingGrid.CELL_M` or `DeckGrid.CELL_M` was
   touched.

   **How it is derived now** (`DeckFitout._catch_hold_berth`): the clear deck is
   the set of cells the GRID calls `FULL` (so the bow taper and both deck ends
   bound it without being named) minus every column the LAYOUT has built on (so
   the hatch cannot land under the wheelhouse); the candidates are the runs
   immediately forward and immediately aft of the GEAR BRICK, larger wins, ties
   go to the one nearer midships; a 0.50 m walking margin is held on all four
   sides; and the result is capped at 0.60 × beam and 0.30 × LOA, plus an aspect
   cap so a hatch stays roughly square. `CatchHoldComponent.scale` is gone: the
   node now takes `footprint_m` and derives every internal dimension from it, so
   the declared size IS the drawn size.

   **The aspect cap exists because of a render, not a number.** The first version
   produced 6.0 × 2.0 m on the 28 m trawler, which photographs as a low ledge
   lying across the deck rather than as a hatch. Looked at, then constrained
   (REALITY §1). Resulting footprints: sjark **3.0 × 2.0 m** at z 4.5…6.5,
   trawler **6.0 × 6.0 m** at z 5.5…13.0.

   **Held by:** `catch_hold_test`, converted to `TestReport` (it reported a bare
   pass/fail and NO check count before) and extended with a
   section 7 that spawns every prebuilt vessel AND a synthetic winch-on-deck
   layout on **every hull in `HullRegistry.catalog()`** — 11 holds measured.
   The property is stated on the DRAWN meshes, not on the footprint constant:
   every corner of every `MeshInstance3D` the hold committed must stand over a
   cell that hull calls FULL deck. Each hold is FILLED to 3900 kg before it is
   measured, because the chilled water and the fish scatter are drawn only when
   there is catch aboard — corner counts go 88 → 160 (sjark) and 88 → 576
   (trawler), i.e. an empty hold hides most of its own geometry from any
   measurement. **Control PASS (95 checks).** Mutations, all four verified:
   restoring the shipped constants **6/95 red** (worst 0.900 m on hull_15x5);
   making `_cell_is_clear` stop consulting the hull and the layout **10/95 red**;
   letting the manifold escape its declared footprint by 0.42 m as it used to
   **11/95 red**; dropping the fish scatter's margin so it hangs through its own
   liner **11/95 red**.

   **That third mutation PASSED first time and is recorded as a finding.** With
   only the off-deck property, 0.42 m of undeclared growth lands on the 0.50 m
   walkway and is legitimately "not off the deck" — the check was blind to the
   exact seam the original bug lived in. A second, adjacent property was added
   (the drawn bounds must lie inside `footprint_m`, which is the guarantee the
   component's own header makes) and that is the one that reddens 11/95.

   **Renders, re-shot from `tests/_starter_shot`:** the two frames named in the
   original report both changed. `starter__bow_on_ortho` used to show a pipe stub
   projecting into clear air off the port side and a wide grey band spanning the
   whole beam at deck level — that band was the hold coaming, 6.34 m across a
   5.00 m boat, hiding the foredeck entirely. It is gone; the frame now reads
   bulwark to bulwark with the foredeck railings and bollards visible.
   `starter__profile_port_ortho` used to be a flat grey slab lying over the
   forward two-thirds of the boat, hiding the sheer and the whole railing run —
   now the railing runs unbroken bow to stern and the hold is a low band aft,
   which is what a hatch coaming should be in profile. `starter__stern_quarter`
   and `starter__plan_ortho` show a stainless rectangle on the after working deck
   with a walkway on all four sides and the manifold stub well inboard of the
   rail. The 28 m preset had no capture rig at all — `trawler_render_capture`
   shoots a structure-plan fixture, not this brick preset — so one was added:
   `screenshots/vessels/fishing_trawler_28m__stern_quarter.png`, figure_px 3521.

5e. **`catch_deck` cannot fail on any real hull.** `capabilities.exposed_deck_cells`
   comes straight from `VesselOutfit.budget_for_hull` — a count of `FULL` grid cells —
   so `min: 4` is met by any hull bigger than 1 × 4 **regardless of what is built on
   it**. Measured 270 on the sjark and 1010 on the 28 m, unchanged by covering the
   deck in blocks. A vessel with every deck cell blocked still certifies as having a
   catch deck. The rule does not measure a catch deck; it measures hull size.
5f. **The bow rail is a staircase.** At the 45° bow taper the generator places plain
   `railing` bricks, so the rail steps around the taper instead of following it.
   `railing_45` exists in the catalogue and **no preset uses it.**
5j. **The starter boat's fish hold was a hole you stood over in mid-air — CLOSED
   2026-08-15 (`bd548bc`), and the price is recorded with it.** The hold drew 28
   meshes including a 1.16 m pit and collided with **nothing** — 0 `CollisionObject3D`
   and 0 `CollisionShape3D` under it. What carried a deckhand across was the vessel's
   own 5.00 × 0.14 × 15.00 m deck slab, so a capsule stood **1.09 m above the nearest
   drawn surface**, shin-deep in the drawn chilled water; dropped down the hatch it
   stopped at 2.751 against a drawn pit floor at 1.660. Now **42 of 42 stations from
   0 of 42**, standing on hatch boards the hold itself draws.

   **The cheapest passing fix would have been to assert the deck slab, and it was
   refused.** The open-hold options need the *hull* cut open: `WalkHullCollider` tops
   out **0.51 m below the deck plane**, and the hull's deck plate mesh spans the
   aperture too, so "just open it" drops a player onto invisible steel with 0.65 m of
   drawn pit still beneath them. Against a 0.45 m step, a 1.16 m pit is a trap rather
   than a hazard until something lets a player climb out.

   **The price, stated rather than buried: a player can no longer see their catch**,
   and `catch_hold_showcase` — whose whole job is showing fill stages — shows a lid.
   **A wave is on the openable hatch now.**

   Two mutations earned their place. A collider shifted 0.30 m to starboard reddened
   only 5 of 161, because a wide hatch has boards under its middle — so the check
   became a **shape-for-shape match read back off `PhysicsServer3D`** in both
   directions. And butting the boards flush lets a downward ray pass **between** two
   of them and report the deck 0.250 m below (7 of 63 stations on the 19 m hatch),
   which is why `HATCH_LAP_M` exists — reproduced independently at the same 7 of 63.
   A third **passed and is recorded as a finding**: deleting the two-hold overlap
   memory changes nothing in any fixture, because the berth picker always takes the
   larger run beside its own gear brick, so that guard has never been shown the shape
   it guards. `MAX_FISHING` is 1, so the second hold is unreachable today regardless.

5k. **The studio's properties drawer had never been on screen — FIXED 2026-08-15
   (`2ab3eee`), and the registration checklist now closes the authoring loop.**
   `PRESET_RIGHT_WIDE` left offsets at zero, so on the project's 1920 × 1080 viewport
   the drawer sat at **x = 1920** and the context strip at **y = 1080**. That is the
   inspector, the surface library, SAVE JSON, LOAD SELECTED, the tool hints, the
   metrics — and **every status toast, including the off-hull refusal item 2d records
   as delivered, whose probe asserted the status STRING and never a rect.**
   Reproduced independently: restoring the offset puts the drawer at (1920, 60) and
   reddens the new check.

   The checklist reads from **one call** to `PlanOutfit.compliance` with the same
   arguments `DeckFitout.apply_plan` makes at spawn — no second evaluator — and a
   probe authors by clicking, **reads the text off the Label nodes**, spawns the same
   plan and compares rule by rule.

   **The cost answer was not cache, debounce or defer.** Measured on the 617-entity
   feeder: fence 101 ms, compliance 118 ms, both separately **219 ms** — and the fence
   is 100 of that, which `compliance` *already takes*. It now publishes the partition
   it holds: rebake **+6.4%** against +33% naive. A cache would also have been worse
   on correctness — a stale checklist says CERTIFIED about a plan that is not.

   Two more found by looking: `_load_plan` never rebuilt the deck grid, so loading the
   feeder into a studio booted on `hull_28x10` reported **596 of 617 entities off the
   hull**; and the wave's own first cut printed *"FITTED, BUT NOT ALL ON THE PORT
   SIDE"* under a boat with no lights, because `tag_side` fails identically for
   misplaced and missing — its own §5 check passed that, and the **capture** caught it.

   **Nobody has ever audited what is inside the drawer**, because until now nobody
   could see it. A wave is on that.

5g. **The deckhouse was a shoebox on every preset — REBUILT 2026-08-15 (`3582276`),
   and the vocabulary to fix it was already in the catalogue.** `_add_deckhouse` used
   **four brick ids out of 64**: five levels of `block`, `block_window` where the band
   crossed, `block_door`, and a solid slab of `roof_flat`. `roof_slope`, `roof_corner`,
   `block_45`, `block_windshield`, `block_window_45`, `block_window_corner`,
   `ledge_45` and `ledge_45_corner` were all present and **unused**. The shoebox was a
   limit of what the generator asked for, not of the vocabulary it was asking.

   Looked at before anything was touched: a pure white cube, dead-flat top, no trim or
   shadow line, and three window slots **the same value as the sky behind them** so
   they read as holes punched to daylight rather than glass — with a dark mast slab
   floating above, overhanging both ends, so the top read as two stacked plates. The
   28 m cargo's house is the **same drawing at a different size**, so this was never
   starter-specific.

   Now: a cantilevered brow, a hipped `roof_slope`/`roof_corner` cap, a full-width
   `block_windshield` band, two aft windows. Eleven rendered iterations
   (`screenshots/vessels/iter_house/`, 60 frames). Two findings cost most of them —
   **`ledge_45` is a RAMP**, widest at its base at *every* yaw, so it can flare a foot
   but cannot soffit a brow (three variants tried it); and **`roof_slope` fills its
   whole cell**, so an eave's soffit lands exactly on the wall plane and z-fights,
   which is why v10 drops the eave v8 and v9 had added.

   **The piece kit cannot reach a brick vessel**, measured both directions rather than
   assumed (`tests/_kit_reach_probe.gd`): `apply_any` routes on the single test
   `StructurePlan.is_plan(dict)`, and bolting 40 `wall_panel` placements onto the
   shipped sjark layout round-trips **byte-identical at 271 cells / 231 primaries** —
   the placements are dropped at parse. Converting wholesale fails too: **4 of
   `general_vessel`'s 8 rules address brick IDs** a plan does not carry. The kit is
   not a path to better vessels today.

   §5 holds: all 13 bricks the new house uses are in the shipyard editor's palette,
   0 of 18 unreachable with a made-up id as the control. Diff characterised and
   **verified independently**: +12 cells, 0 removed, 50 changed on all four presets,
   metadata byte-identical, all six door cells untouched, `GEN OK` on all four.

   **THE GAP, confirmed by the orchestrator rather than accepted on report: nothing in
   the gate can tell the new house from the shoebox.** Reverting the hipped cap to
   `roof_flat` and regenerating still emits `GEN OK` and leaves the gate at 104 PASS.
   The wave wrote a test for exactly this, found it could not distinguish the two
   because **`VesselSkinBaker` merges every static brick into a few meshes** so
   per-pane geometry is not addressable from the spawned scene, and **deleted it
   rather than ship a check it did not believe.** That is the right call and it leaves
   CONVENTIONS §3 unmet for this change. `DeckFitout.skin_enabled = false` is the
   route in — **and that turned out to be wrong in a useful way. CLOSED 2026-08-15.**

   **The merged-skin finding was true of NODES and false of GEOMETRY.**
   `VesselSkinBaker` merges bricks into a handful of `MeshInstance3D`s so no per-pane
   *node* exists — but the merged meshes still carry every *vertex*. Measured with the
   merger on and off across all four presets: roof fall 0.5000 m both ways, widest
   front pane 1.340 × 0.340 m both ways, front glazed 89.3% both ways, forward-most z
   per level identical, differing only by 552 culled interior triangles. So
   `tests/deckhouse_shape_test.gd` asserts **at the shipping configuration** — no
   `skin_enabled = false` needed, and REALITY §3's "asserting on a config the game
   does not use" was avoided rather than accepted. §4 of the test holds that parity
   open in the gate, with a guard that the merger is actually doing something
   (38336 < 38888) so the comparison is not a configuration against itself.

   **PASS (45), lane B, 14 s**, on the boat onboarding actually grants. It names and
   counts **no brick id** — three shape properties: the roof falls to its perimeter,
   the front is a glazed band (widest uninterrupted glass run ≥ 2× as wide as tall,
   spanning ≥ 25% of the beam), and the brow stands proud of the wall below.

   **The obvious formulation was blind and was nearly shipped:** "the top surface has
   more than one height" **passes on the shoebox**, because `roof_flat` draws a 0.18 m
   slab at the top of its cell and so already presents two vertex heights. Recorded in
   the test header. Two instrument bugs were caught the same way — a vertex-in-band
   level filter read a solid wall as an empty level (a `block` fills its cell exactly,
   so every vertex sits *on* the plane), and counting occupied rows rather than the
   tallest contiguous run turned a 3.94 aspect into 1.97, a hair above the 2.0 floor
   it feeds.

   Mutations, all red, none passed: flat cap **4/45** (fall 0.5000 → 0.0000 on all
   four presets — reproduced independently by the orchestrator, with `GEN OK` still
   returned, which is what proves the generator could never have caught it);
   windshield → punched panes **8/45** (pane 1.340×0.340 aspect 3.94 → 0.340×0.340
   aspect 1.00); brow removed **4/45**; one windshield per row **4/45**; and dropping
   brick yaw in the merger **5/45**, red on parity *and* on the roof, correctly,
   because with the merger on the roof really is drawn flat.

5h. **A player cannot get inside the wheelhouse of the boat they are given.** Measured
   with `BrickDoor` actually driven open (`toggle()`, the call `F` makes), which had
   never been done — every earlier sweep measured the closed state, so "blocked at the
   door" could not be told from "the doorway is too small".

   `block_door` is [2,3,1] cells → drawn 1.00 × 1.50 × 0.50 m; clear opening measured
   off the meshes **0.680 m wide × 1.180 m high**. Open, the leaf shape is *disabled*
   rather than removed (shape count 234 → 234) but the sweeps change, so the open
   state is effective. **The tallest capsule an OPEN door passes is 1.25 m** — against
   a 1.80 m player. Varying one input at a time: still 1.25 m at 0.70, 0.60, 0.40 and
   0.20 m across, so **height is the binding limit and width is not** — the head hits
   the wall block above the door brick. Fenced (open cell decision #1), not fixed.

5i. **The house is not sized to its hull, and on the 28 m presets it reads badly.**
   Rendered at working scale for the first time (`screenshots/vessels/starter_28m/`,
   15 frames) after being changed in `3582276` and never looked at. One absolute
   3.0 × 4.0 m box, 2.5 m to the eaves, identical on all four presets: 60% of the beam
   and 27% of the length on the 15 m sjark, where it reads as a wheelhouse — **30% and
   14% on the 28 m hulls, where it reads as a barge with a portacabin on the
   transom.** The 1.8 m figure's head reaches the eaves. Confirmed by eye.

   Three more, all visible in those frames: **the aft face is still the old drawing** —
   two 0.34 m punched squares beside a domestic brown door, which with the hipped cap
   above reads as a cottage gable, because the windscreen change reached the front and
   forward sides only. **More than half the house's length in profile is unbroken
   white.** And **the masthead light stands below the wheelhouse roof on all three
   28 m presets** (deck-stepped mast, light at 1.75 m against a 3.00 m roof) — the
   sjark's own comment names exactly this as why its mast is stepped on the roof, and
   the other three were left. All four still certify, because `white_light_height`
   only asks for white-above-sidelights and the sidelights are at 1.25 m. On
   `28_10_m` and `bulk_small` the mast is dead on the centreline forward of the house,
   so **the lantern sits in the middle of the windscreen at helm eye height.**

   **The new check set holds the forward face, the roof and the brow. Nothing holds
   the aft or side faces, so every finding in this item is unguarded.**

   Still weak in the picture, on record: the aft ~60% of both side walls is a blank
   2.5 × 2.5 m white field — the biggest remaining visual weakness — and the roof's
   45° fall reads slightly cottage-like, because that is the catalogue's only 1×1×1
   roof wedge.
6. `budget_caps.crane` is 0 on every registration, so any crane fails compliance.
7. No lifesaving requirement of any kind exists.
8. No hull under 28 m, though two of three reference vessels are ~22 m and the
   third ~15 m.
9. **Raked-plate `PLATE_COLLIDER_SLOP` — rendered 2026-08-15, still open.**
   `screenshots/decisions/q3_plate_slop__*`, on item 100 of
   `probe_plate_deckhouse.json` (shipped data, raked front overhanging 0.45 m,
   tapered in plan). Pale plate is `StructureBaker.bake`; red boxes are exactly
   what `collect_colliders` emits, drawn where they sit.

   | slop | boxes | worst phantom |
   |---|---|---|
   | 0.05 (today) | 82 | 0.0874 m |
   | 0.08 (the knee) | 47 | 0.1060 m |
   | 0.35 (bracket) | 18 | 0.2350 m |

   Looked at: at 0.05 the colliders are a fine-toothed red staircase hugging the
   diagonal; at 0.08 about half as many steps, each reaching visibly further into
   the air, but still following the rake; at 0.35 it stops being a staircase and
   becomes **a fat vertical slab the diagonal plate cuts through**, ~0.24 m of
   solid nothing standing in front of the wall. Window openings stay uncovered at
   all three. The owner question: is ~2 cm more air in front of a raked wall worth
   43% fewer boxes — 0.05 or 0.08?

   **Two limits on that evidence, both stated by the wave rather than found later.**
   The frames stop at the *producer* — the boxes `collect_colliders` returns — and
   do not go `VesselSpawn` → `apply_plan` → `PhysicsServer3D`, which is the exact
   layer the last plate bug lived in (REALITY §3). And **the cost side is
   unmeasured**: one plate's box count and nothing else — no whole-fixture totals,
   no timings, no re-run of `_plate_phantom_probe` at 0.08. The "knee" is still
   somebody else's number, unopened.

### CORRECTION to commit e9de76a, and to my own briefing of the catalogue wave

That commit claimed *"vessel_registration_test does not COMPILE in lane A"* and
concluded at least one of the ten catalogue reds was a lane problem. **That was my
error, not the test's.** `vessel_registration_test` HAS a `.tscn` and is a lane-B
unit; I ran it with `--script`, which registers no autoloads, and reported the
resulting compile error as a defect. Measured lane classification of the family:

| unit | lane |
|---|---|
| `building_blueprint_test` | **lane A, and it genuinely does not compile** |
| `vessel_outfit_test`, `vessel_registration_test`, `vessel_registration_audit_ui_test`, `hull_form_geometry_test`, `company_service_test`, `catch_hold_test`, `vessel_persistence_test` | lane B (`.tscn` present) |

So the lane defect is real but belongs to **`building_blueprint_test`** alone. Run
in lane A it emits `Identifier not found: WorldGateway` **and** a genuine assertion
failure (`placement outside the grid is rejected`) — a compile error on a depended
script, with the test still executing some checks past it. Two problems in one
unit, and the compile error masks how much of it never ran.

`vessel_registration_test` run correctly in lane B printed **no verdict line at
all** — it neither passed nor failed nor reported. A unit that produces no outcome
is not a test (same class as `staged_vessel_visual_demo`'s 240 s timeout). Not yet
diagnosed.

This is the trap the correction itself illustrates: **a compile failure and an
assertion failure are indistinguishable in a results table**, and so is running a
test in the wrong lane. Verify the lane before you diagnose the failure.

### Piece-built deckhouses: solid, but no door opens

`tests/piece_interior_test.gd` (arrived from a wave that died on the API limit;
I supplied the missing `.tscn`) goes through `VesselSpawn` → `apply_plan` → real
`PhysicsServer3D`. **83 of 93 pass.** The seam wired in `763dbdc` holds: a standing
player is stopped by every piece-built wall plate (0/115 through), kneeling too
(0/71), with coverage asserted and no march beginning inside its own plate.

The ten reds are one finding: **every doorway has 0.000 m of walkable play.** The
opening is drawn and the collider closes it. Also 44/72 loose corners on opening
casings (house, trawler), 200/240 on the tug, and 4 floor probes inside the tug's
deckhouse that begin in a collider.

Worth copying: that test contains a vacuous pass AND the guard that catches it.
*"a player on deck walks through a piece-built door"* passes at **0/0** because the
column had no stations; the next check, *"the door sweep planted stations (0)"*,
fails and exposes it.

### Then, in order

> **STALE — DO NOT PLAN FROM THIS LIST. Audited 2026-08-16.** It describes a tree with
> nineteen reds, an empty `BrickCatalog.BRICKS`, and a `resources/data/vessels/prebuilt/`
> holding only `.gitkeep`. The gate is now **119 units / 112 PASS with five reds**, the
> catalogue is populated, and items 4, 5 and 6 are closed. It is kept because items 1, 2
> and the *shape* of 7 are still live, and because deleting a superseded plan hides that
> it was ever believed — the same reason the "what is missing" list above carries its
> corrections rather than a rewrite. **Every unmarked number below is from 2026-08-10.**

1. **Judge the studio tool against the mouse test.** Not "does it compile" — can a player place a
   piece, turn it, edit its parameters and delete it without typing a number? If the palette or the
   parameter controls are hardcoded rather than read from `structure_pieces.json`, that is a
   rejection: the set-widening wave changes those values.
2. **Act on the critic's impossibilities.** Its findings are the spec for the kit's next pieces.
   Expect the diagonal cap and the seam constraints to be where it bites.
3. **Re-run the full gate over a QUIET tree** and re-measure the known-red list. The current
   measurement (`20260810-081647-26225`) ran while two writers were editing and is a snapshot of a
   moving target; treat it as indicative, not authoritative.
4. **`staged_vessel_visual_demo` never calls `quit()`** — 240 s timeout every run. Either it gets a
   verdict or it leaves the gate. A unit that cannot report an outcome is not a test.
5. **`ship_display_units_test` fails to COMPILE**, which is a different and worse thing than
   failing an assertion. Diagnose before the next sweep.
6. **The empty-catalogue family is ten of the nineteen reds** — `BrickCatalog.BRICKS` is `{}` and
   `resources/data/vessels/prebuilt/` holds only `.gitkeep`. One root cause, ten tests, and it is
   also STATE.md's missing-item 4: no starter vessel for any new player. This is the largest single
   lever left on the red count and it is blocked on the parts vocabulary, which has now landed.
7. **Owner decisions still outstanding** — `budget_caps.crane` is 0 on every registration so any
   crane fails compliance; no lifesaving requirement of any kind exists; `fishing_vessel` requires
   gear but not fishing lights; no hull is under 28 m though two of the three reference vessels are
   ~22 m and the third ~15 m.

### OPEN 2026-08-16 — the sheer is computed, the check is green, and I cannot see it

Opened after the orchestrator looked at `screenshots/hulls/hull_15x5__side.png` and
`hull_130x28__side.png` and read both as **flat-topped slabs with a straight red band** —
the "reads as a barge" failure `hull_stations.gd:53` says sheer exists to prevent. The
130 m reads as a pontoon with a stripe.

**This is not a proposal to curve the deck edge.** That argument is settled and stands:
`deck_y` is the floor of four other systems and the loft's headroom above it is zero
millimetres — an earlier wave lifted it and produced 0.666 m of walk-through plating at
the stem. The 2026-08-15 correction's move, putting the curve on the **rubbing strake**
one level down inside the freeboard, is sound and `sheer_rise_at` really is wired into
`from_form` at `strake_level = 3`.

The claim under attack is the correction's last clause: **"the hull has a curve in it
that a person can see."** The derivation lands on the Load Line Convention (0.896 m
against a standard 0.966 m for a 28 m hull) and `hull_sheer_test` is green. If the render
is still flat, then a number is standing in for a feel and the number is winning —
**REALITY §2, exactly the trap that killed the appearance metric.**

Three candidate causes, to be distinguished by measurement rather than argued:
1. **Not drawn at all on these hulls.** `strake_level` is `-1` on `from_box`,
   `from_pointed`, `from_design` and `from_hull_json` — four of five constructors have no
   band for the curve to live on. If a kit hull takes one of those, its sheer is computed
   and thrown away.
2. **Drawn, correct, and invisible.** 0.9 m of rise on an 8 m freeboard rendered at
   ~5 px/m is Convention-compliant and beneath notice. Amplitude must be measured in
   PIXELS; metres are what the check holds and metres are not what an eye receives.
3. **The instrument (REALITY §7).** `screenshots/hulls/*` is shot on near-black at
   960×540 while `screenshots/vessels/*` uses sky-and-sea at 1600×900. A dark navy
   topside on a near-black field has almost no edge contrast. **If the rig is at fault,
   every visual judgement ever made from that family is unreliable — a bigger finding
   than the sheer.** Related and possibly the real bug: `hull_livery.gd:11` records that a
   sheer-strake surface is read by nothing (§3d), so a band that curves may be the same
   colour as what it sits on.

### CLOSED 2026-08-16 — the claim was half true, and the instrument was worse than the geometry

Verdict: **"a curve a person can see" is true of three hulls of six and false of the other
three.** It was written from `hull_15x5`; nobody looked at a freighter. Confirmed by eye on
the refreshed frames — `hull_28x10__side` dips amidships and lifts at both ends;
`hull_150x32__side` is straight for its whole length.

**Both of the orchestrator's hypotheses were partly wrong.** Nothing is discarded: all six
kit hulls and both shipped vessels reach `from_form` with `strake_level = 3` (measured
through `HullRegistry.build_hull`, not re-derived — `hull_sheer_test` calls `from_form`
itself with its own station count, the artefact beside the path). The clearance clamp never
bites. **The rig was the bigger fault**: the deck edge measured **1.18:1** against its own
background on `hull_130x28__side`, against WCAG 1.4.11's 3:1 floor. At 1.18:1 it is not a
line, so **every visual judgement ever made from `screenshots/hulls/*__side.png` and
`*__front.png` was made against nothing.** The rig now shoots overcast and **asserts** the
contrast — mutation: dark ground → 12/78 FAILED, reproduced by the orchestrator.

**Two numbers in `hull_stations.gd` were wrong and are corrected.** `sheer_forward_m` is
the value at `z = -L/2`, where the band has zero width; the forwardmost drawing station is
at `u ≈ 0.86–0.95` and `u²` takes 7–27% of the rise. The headline **0.896 m is never drawn
anywhere** — the drawn figure on hull_28x10 is **0.671 m**.

**Why the big hulls are flat, and it is not a bug:** `rise = freeboard × bow_keel_rise`,
and freeboard tracks *depth*, which grows far slower than *length*. Sheer-as-slope falls
from 6.40% (28×10) to 1.68% (150×32). **`hull_150x32` curves by four pixels over seven
hundred and forty.**

**And the line carrying the curve is painted in the anti-fouling colour — 1.07:1** against
the plating above it, separating by hue alone at the bottom of the luminance range.
`MeshBuilder.lofted_hull_shell:536` routes the band into `keel_faces`;
`HullLivery.DEFAULT_ACCENT` is read by nothing (§3d), exactly as `hull_livery.gd:11` says.

**OPEN, AND THE OWNER'S:** how much sheer this game wants. Four levers with costs are in
`hull_stations.gd` — scale rise by LOA; raise `bow_keel_rise` on the three full-bodied
presets (re-rakes every forefoot and stem, must be re-rendered); lower
`shoulder_freeboard_fraction` (buys nothing alone, the clamp is not biting); or give the
strake its own paint (+2 draw calls, already reddened four budget tests — though vertex
colour, or simply re-picking the two default colours, costs zero). **Moving nine pixels to
fifteen on a 1.07:1 edge changes nothing**, so the paint is the highest ratio of visible
change to risk.

Named, not fixed: `hull_sheer_test._check_strake_is_painted:330` has a bare
`if s.strake_level < 0: return` that contributes zero checks and reports success (§4).

### CLOSED 2026-08-16 — a licence no player-built ship could ever hold

`PlanOutfit.has_cabin` was `return false` for every plan, so `passenger_vessel/cabin` was
unreachable by anything a player could draw. The header defended the refusal as "honest
rather than a wrong yes"; **the argument does not survive** — it conflates *no primitive
DECLARES enclosure* with *enclosure is not MEASURABLE*. It is measured now: a pocket of
air the sky cannot reach, ≥1.8 m tall, ≥1.2 m² of floor, **with a door into it**.

The instructive failure is in how it was built. The first implementation looked for a
horizontal ceiling plane and **reported false on every deckhouse in the repo** — a
`deck_tile` at fall 2 drops 0.25 m across its run, so no plane is wholly solid. Requiring
one was the deleted room primitive's shed assumption wearing a new hat. The column flood
assumes nothing about shape. Cross-check rather than calibration: 10 of 18 fixtures report
a cabin, and it agrees with all five deckhouses that `plan_interior_test` marches a real
capsule through **without being told**.

Pins were **strengthened, not weakened**: `has_cabin(null)` stays pinned false and a new
positive pin sits beside it, so the null pin cannot pass by being hardcoded again. The
one-sided rule set went from one member to **empty**. Verified independently before commit
— 66 / 93 / 137 / 65 / 225, and the `return false` mutation reddens the new positive pin.

**The brick path is worse than the old header said, and its citation was false.** Eight
`block` bricks in a line report a cabin; **one `block_door` alone on a bare deck reports a
cabin**, and the licence panel reads "required (current: true)". The header claimed
`plan_compliance_test` pinned that rule — it does not, and **no test in this repo asserts
anything about the brick reading.** Now an open wave.

### CLOSED 2026-08-16 — one door brick certified a passenger vessel

`VesselOutfit` answered the licence with `door_n >= 1 or wall_n >= 8`: eight `block` bricks
in a straight line reported a cabin, and **one `block_door` standing alone on the deck**
reported a cabin. It reads enclosure off the geometry now. **Neither recorded reason for
leaving it there survived contact.**

- *"The classifier publishes buried bricks, not enclosed air"* — **false of what it already
  knew.** `_flood_exterior_air` visits every air cell the sky reaches; enclosed air is the
  complement inside the same bounds. Computed independently — own flood, own bounds — on
  the hollow 5×5×3: **27 cells, exactly the 27 the old note said "appear nowhere"**, and it
  agrees cell-for-cell. Tenth value-computed-and-discarded of the session (§3d).
- *"A brick cell has no agreed metre size"* — real for LAND, **and never true of this
  path.** `BuildingGrid` is the land blueprint lattice with **zero references from
  `scripts/ship/`**; a vessel brick is positioned by `DeckGrid.CELL_M` and drawn at
  `BrickCatalog.size_m`, **the same 0.5 m constant**. Verified independently by the
  orchestrator. **THIS FILE ALREADY SAID SO** — the "TWO questions, not one" entry in Owner
  decisions has been right the whole time. The wave's blocker claim contradicted the record,
  and the orchestrator repeated the wave rather than checking the record first.

Third finding: **"a floor under it" is not a clause** on a voxel grid — the cell under an
enclosed run's base is always solid, so the branch could not fail. Deleted, with the proof,
rather than kept.

Both rows of the shipped defect are false under **every** candidate cell size, which is why
closing this never needed the owner's decision at all. All four shipped presets keep their
cabins and their full checklists — nothing a player owns is decertified.

Reach, measured not assumed: the wrong yes could **not** reach a player unaided (every
preset is cargo/bulk/fishing, and the only code choosing `passenger_vessel` authors plans).
But in authoring mode `report.ok` decides whether a preset is written **official** or draft,
and official presets are what the shipwright sells and the starter grant gives away — so it
could have got a fake cabin stamped official by an author.

### OPEN 2026-08-16 — the hulls improved and the superstructures did not

The critic frames now show boats carrying sheds. The ferry saloon is a constant-height
slab the full length of the deck, roofing ~85% of it — **there is nowhere to walk**, which
is a measurable property (`plan_interior_test`'s capsule) rather than a matter of taste. A
**thin spar runs forward past the yacht's stem into open air**, present in two views so it
is geometry, found by opening a frame a previous wave admitted it had not opened. A barge
deck plate cantilevers past the bow — pre-existing, not a regression.

**Instrument warning attached to that milestone:** `vessel_render_capture` places a 1.8 m
scale figure and **never counts its pixels**; on all four `critic_ferry` frames the figure
is hidden under the saloon roof, so those frames have **no absolute scale** — CONVENTIONS
§3a's exact failure, in the rig every other rig was copied from. Any proportion judgement
made on them, including the orchestrator's, is unanchored until that is fixed.

### CLOSED 2026-08-16 — the port's bounds excluded every pier, and the severity was the other consumer

Third stale reader from one migration (quays left `modules` for `berth_plan`). Re-measured
independently off the **drawn** `QuayPier/Deck` nodes, never the plan dictionary: **226.75 m**
worst overhang, the recorded figure held, and the recorded corner counts **omitted sizes 1–2**,
which lose 4 corners each.

**The orchestrator's severity premise was false.** `plot_depth` is short by up to 226.8 m —
and **nothing reads its magnitude**: `IslandMeshBuilder.build_polygon` has zero callers, the
`PortPlot` fields reach only a callerless helper, and the explicit-lane builders that consume
the island box are reached only from `_build_lane`, which has no caller. Measured through the
production path: **zero lane segments cross a pier at any size, with the broken value and the
fixed one identically.** `island_width` is short by 0.00 m everywhere — the `PortSizing` floor
always wins.

**The live defect was the label.** `port_plot.gd:129` centres the port's floating name on this
box, so it sat 25–113 m landward — 13–25% of the port's own span, **95–164 px on screen,
13–23% of frame height.** It floated over the town instead of the harbour.

The check takes pier corners **from the drawn nodes** and the helper is deliberately private so
nothing can measure tips through it. Mutation M2 is the independence proof: inflate the drawn
deck 1.5× in the visualizer only, leave `bounds()` correct, and it still fires 36/73.

**The sweep found two more stale readers and one hid the other.**
`coastal_port_placer_test` selected a quay from `modules` — **zero quay modules on all 35
ports**, so its "berth water stays open" check ran **zero times**. Repointing it exposed the
fourth: the same file dropped the `WorldLayout` that `world.gd:355` always passes. With it,
66/66 station origins in water; without it, **0/66, worst −130.52 m**. The test had been
measuring a port generated against no coast.

Named, not fixed: `flatten_zone_records()`'s site envelope is a third `bounds()` consumer,
dead on every live port (0 records / 18) and correct only by accident of an `elif`; the
asphalt branch of the new corner helper is **unexercised** (no fixture makes one);
`coastal_port_placer_test._finish()` prints "all checks passed" **with no check count**.

### OPEN 2026-08-16 — the instruments are the defect class

One day's findings, all instruments: a hull rig shooting silhouettes at **1.18:1** against its
own ground; a port rig **photographing an abandoned data model** as an 8×10-pixel square; a
render rig placing a scale figure and **never counting its pixels**, so seven fixtures
including a shipped one had no scale; a walk probe whose filter matched nothing and reported a
capsule walking through a sealed saloon as fully clear. **Four instruments, four silent
falsehoods, in one day.**

Three known-bad remain and are now a wave: `_fittings_shot` (3.79%), `_small_hull_shot`
(240 px), `_hull_iter_shot` (150 px) — none can reproduce its own output, so their sets are
stale by an unknown amount and nothing downstream of them is evidence. **Treat every rig's
recorded status as a claim:** `hull_visual_capture` is recorded byte-identical across six
pairs and produced **2.5118% at 241/255** in an ordinary gate run today, with a mask showing a
1–3 px wireframe — a grab/draw race, in a rig that *does* call `settle`.

### BASELINE 2026-08-16 — `20260816-083201-29255`, the orchestrator's own full gate

**122 units.** Five reds and one SKIP, and **every one of the five is the same red it was
this morning, unmoved by six waves of work**: `port_trade_profile_test` (apron props
nothing draws), `remote_realtime_join_smoke` (needs a live server), `structure_plate_test`
(open slop decision), `building_interior_test` (the open brick-cell decision — a mutation
takes it to PASS), `plan_interior_test` (the mast); `ocean_wake_gpu_smoke` SKIP.

**It caught a regression the orchestrator had committed.** `piece_kit_capture` and
`structure_plate_capture` were red in this run, PASS → FAIL on `f9aac33` — the
figure-visibility check applied to fixtures whose spot was never authored. The wave that
wrote that check said plainly it had not run the gate and that the rest of the tree was
unverified; it was, and the commit went in anyway. **Verifying what a wave CHANGED is not
verifying what a wave REACHES.** Fixed in `63a6d0a`; both green.

### Three instrument failures in one day, all of them the checker's own tools

Recorded together because the pattern is the lesson, not any one instance:

1. **A `pgrep` that matched itself.** The orchestrator's gate waiter grepped for
   `bash tools/gate.sh`; its own command line contained that string, so it reported the
   gate as running for an hour after it had finished, and a partially-written
   `results.tsv` was read as a 2-unit run.
2. **A `git status` used as a content check.** A wave reported frames "byte-identical" on
   the strength of `git status`, which reports `M` on a stat-cache mismatch when a file is
   rewritten with identical bytes and clean once the index refreshes — the same command
   answers differently depending on when it runs. Re-verified by content hash; the
   conclusion held, the instrument did not.
3. **A `pgrep -f` misread as proof of a clean machine.** A wave reported no live
   `_wave_walk_probe` process; **one had been running 2h55m at 184% CPU** and was still
   running hours after that wave finished. It burned two cores under a full gate run and
   under an in-flight capture-reproducibility investigation — **CPU contention being the
   one candidate cause that investigation had never tested.** Killed by the orchestrator;
   the wave was told which of its verdicts the window makes suspect.

Standing consequence: **use `ps -C <name>` rather than `pgrep -f <pattern>`** for process
checks, and never let a process check's own pattern appear in its own command line.

### CLOSED 2026-08-16 — three rigs could not repeat because the boat was still moving

**One cause for all three, and it was neither of the two on record.**
`BoatBody.automatic_physics_lod` defaults `true`; one second after a hull enters the tree
the LOD update finds nothing in the `PlayerVessel` group and executes
`freeze = physics_quality == SLEEP` — **`freeze = false`**. The rig's own `freeze = true`
is silently revoked and the hull rises to buoyancy equilibrium **while the rig photographs
it**. `shipyard_brick_editor.gd:2579` has carried a comment describing this all along.

**The wireframe mask is not a race signature** — it is what a subject that moved **0.2 px**
looks like (1.15 mm at 9 m across 1600 px). The orchestrator passed that wrong reading into
the brief and it was corrected by measurement. The old `_small_hull_shot` note was right
that transforms are bit-identical *across processes at the same frame index* and wrong to
conclude "it is not the hull": nobody had asked whether they were constant **over frames
within one process**. `_fittings_shot`'s weather diagnosis was named and never measured —
and is false: the four weather values each hold one float-bit value per run, the vessel
carries **zero `Light3D`s**, and `WeatherLighting`'s only writer is not an autoload.

**Contention HIDES this defect rather than causing it** — the opposite of the standing
assumption. Re-taken on a quiet box, both negative verdicts got slightly *worse*. Load lets
the transient damp before the first grab, so a loaded machine produces two runs that agree
**at the wrong pose**. A mutation that passed under saturating load was chased, not banked:
its frames differ from the fixed ones on 7 of 7.

**`_hull_iter_shot`'s "before" came back green with the defect still in it**, and four
back-to-back runs of that same unfixed rig moved 2–5 of 7 frames. **One clean pair closes
nothing** — which is exactly how `hull_visual_capture` got recorded as closed.

Refreshes were **decomposed, not blind**: committed → unfixed isolates drift predating the
change (2.73% small hull, 17.07% fittings); unfixed → fixed isolates the pose correction
(0.31%). At most 0.31% of the small-hull drift is this fix, and `profile_ortho` is
byte-identical, so the hull form did not move.

**Corrects REALITY §8a.** Its "'it settles under physics.' False" was measured on
`_starter_shot`, **which already carried the LOD line** — right about that rig, wrong as a
general claim (§4d, again).

### OPEN 2026-08-16 — the two SHIPPED rigs still carry it, and the split is 1:1

Eleven rigs stand a `BoatBody` and set `freeze = true`. **Every rig this file records as
closed carries `automatic_physics_lod = false`. The rigs without it are exactly
`hull_visual_capture` — recorded closed at "0 of 18, four runs, six pairs" and drifted
2.5118% today — plus the three just fixed.** No exceptions either way.

Still carrying the defect: **`hull_visual_capture:172` and `vessel_render_capture:306`**
(the two shipped ones, and therefore the milestone), plus `_boatbody_curve_probe`,
`_critic_window`, `_ensure_breakdown_probe`, `_repro_hull_yaw_probe`, `_sheer_look`,
`_strake_cost_probe`. **Every visual judgement taken from those two rigs was taken from a
possibly-moving subject** — which includes today's sheer verdict and the critic frames.
Not started yet only because a live wave owns `vessel_render_capture`.

Owner's, undecided: `_hull_iter_shot`'s `v0…v12` is 91 frames of thirteen hull variants
**whose code no longer exists**, so the series can never be re-shot. The current hull is
added as `v13`. Either delete down to the newest frame or make the variants data.

### CLOSED 2026-08-16 — the rigs could not repeat because the boat was still moving

**One cause for all three, and it was neither of the two on record.**
`BoatBody.automatic_physics_lod` defaults to `true`; one second after a hull enters the
tree the LOD update runs `freeze = physics_quality == SLEEP` — **`freeze = false`** —
revoking the rig's own freeze. `shipyard_brick_editor.gd:2579` has described this the whole
time.

**Every recorded diagnosis was wrong, including the orchestrator's.** The "1–3 px wireframe
plus a blob at the figure" was called a grab/draw race in a brief; it is **what a subject
that moved 0.2 px looks like**. The `_small_hull_shot` header's measurement was real and its
inference was not — transforms *are* bit-identical **across processes at the same frame
index**, and nobody asked whether they were constant **over frames within one process**. The
`_fittings_shot` weather diagnosis was named and never measured: the vessel carries **zero
`Light3D`s** and the only writer into `WeatherLighting` is not in the tree in a rig.

**Contention hides this defect rather than causing it** — the opposite of the assumption in
the brief. Both negative verdicts got *worse* on the quiet box. Load lets the transient damp
before the first grab, so a loaded box produces two runs that agree **at the wrong pose**.

**The split is 1:1 with no exceptions:** every rig recorded as closed carries the LOD line;
the ones without it are exactly the three known-bad plus `hull_visual_capture`. So REALITY
§8a's *"'it settles under physics.' False"* was measured on a rig that already had the line —
right about that rig, wrong as a general claim (§4d again).

**Frame evidence cannot discriminate this defect, in either direction.** A "before" run has
come back green with the defect fully present **three times**, once across **eight runs and
28 pairs**. Only a property probe can, and the probes are committed beside the rigs they
justify.

`hull_visual_capture` was latent-but-safe: its LOD timer reaches **0.93 s against a 1.0 s
threshold** under load — one settle short — and because that rig has no ocean, a crossing run
would **free-fall 951 mm at −4.88 m/s**, not drift. **This morning's sheer verdict is
therefore unharmed and now verified: 18/18 byte-identical across committed, unfixed, fixed
and a 780 s pair, with `hull_150x32` reproducing 4 px over 748.**

**Open and deliberately unexplained:** the **2.5118% at 241/255** recorded for
`hull_15x5__three_quarter` in gate `20260816-083201-29255` **could not be reproduced** — 16
runs, two 780 s pairs, nothing moved, and that gate's log prints per-frame numbers identical
to those runs. The root cause found here does **not** account for it. Retro-fitting it to the
convenient new explanation is exactly how the three wrong diagnoses got written.

### CLOSED 2026-08-16 — a scale figure could pass the pixel check while standing inside a wall

The check answered *"is there a scale reference in this picture"* and never *"is it standing
on the deck"*. Closed by a collider query at capture time — **~0.04 ms per box, 134 ms on the
heaviest fixture in the fleet**, inside a capture taking tens of seconds. The demonstration is
one output: the embedded spot **fails the collider check naming the breakwater box while the
pixel check passes at 63 px in the same run.**

The two-view rule survived a mechanical attack (roofed, sight-line-visible candidates all die
in the crop — the quarter view was seeing orange **through an open doorway**), and the obvious
relaxation *"visible in at least one view"* **would have passed a figure inside a deckhouse at
148 px**. A threshold raise was tried and reverted: **a pixel floor cannot be a fleet
constant**, because each view is framed to its vessel, so raising it fails the 150 m ship for
being 150 m long.

**Named limit, now an open wave:** the figure may still be **off the ship** — `y = 0` *is* the
deck plane, so open water passes both claims and the pixel check likes it *more*.

### Standing, not a task

Every model edit returns a render and the orchestrator looks at it. No metric for appearance —
that was tried, it passed three vessels the owner had just rejected, and it was deleted the hour it
was written. See `REALITY.md` §2.

## Milestone log

- **M0 — Honest instrument** · open · 2026-08-09
