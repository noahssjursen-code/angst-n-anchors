# REALITY.md — how this project lies to itself

`AGENTS.md` is the law for what the code may look like.
`CONVENTIONS.md` is the law for how work moves.
**This file is the record of how we have been wrong**, written from real failures in this
repository, with the fixes that actually caught them.

Read it before you claim anything. Every trap below was hit here, most of them more than once,
several of them by the orchestrator writing confident prose about work it had not checked.

---

## The one sentence

**We optimise what we can measure, and then report the measurement as though it were the thing.**
Every failure below is a variation on that.

---

## 1. The proxy trap — reporting numbers as judgement

Draw calls, check counts, triangle budgets, mutation coverage. All real, all verifiable, and
**none of them can tell you whether a boat looks like a boat.**

What happened: five vessels were dressed with 561 fittings at zero draw-call cost, every gate
green, and the report said the trawler "reads as a working boat". The owner's reply was *"this
looks like complete fucking shit… do you not have eyes"*. He was right. The numbers were all
true. They were answering a different question from the one being asked.

**Rule.** When reporting on something with a taste answer, describe what you SEE, specifically —
"the bulwark is a constant-height band the full length and the deckhouse is the same value, so
they merge" — never a score, never a count, never a budget. If you have not looked at the
render, say you have not looked at the render.

## 2. The metric-for-feel trap — the machine you build will agree with you

Told the silhouettes did not read, the orchestrator's reflex was to **build a silhouette metric**
— sheer, massing, asymmetry, thresholds, the lot. It passed all three vessels the owner had just
called unrecognisable, because what it actually measured was "is this not a perfect rectangle",
which anything with a tapered bow clears.

The tempting next move — tune the thresholds until it agrees with the known answer — would have
produced a rubber stamp with a number attached. That is worse than nothing, because it grants
permission.

**Rule.** Mechanical tests are for things with a RIGHT ANSWER: does the collider match the
geometry, does the wire attach to something, does a plan round-trip byte-stably, did adding a rig
cost draw calls. **Looking is for everything else, and it is done by a human or by the
orchestrator, never by a scorer.** Do not build a metric for appearance. If you catch yourself
designing one, that is the signal you have stopped being able to judge the work.

## 3. The layer trap — testing the thing you can reach

`plan_collision_test` asserted that `StructureBaker.collect_colliders()` emits boxes with the
right yaw. The walk-through-bulwark bug was never in that producer — it was in the CONSUMER,
`DeckFitout.apply_plan`, passing `0.0` where the yaw belonged. Reverting the fix byte-for-byte
left the gate **green**. The test guarded the seam next to the one that broke.

It was written from a critic's probe that queried real physics shapes on a real hull, and dropped
a layer on the way, because dictionaries are easier to reach than a `PhysicsServer3D` query.

**Rule.** Assert against the code path that can actually break, not the intermediate artefact
that is convenient. For anything with a production path, go through it: `VesselSpawn` →
`apply_plan` → `PhysicsServer3D`, not the dictionary in the middle. And when you write a test
from someone else's probe, check you have not landed a layer below the bug.

### The worst instance: the piece kit was never wired into the game

Three waves built the piece kit — the data file, the resolver, the fixtures, an editor tool, an
adversarial critique, hundreds of green checks. Then a strip test: bake `probe_piece_house.json`
as shipped, bake it again with every placement deleted, compare.

```
AS SHIPPED          57 pieces  0 items | 3432 triangles  38 colliders
PLACEMENTS DELETED   0 pieces  0 items | 3432 triangles  38 colliders
```

**Identical.** The 57 placements contributed zero geometry and zero collision. Every triangle was
the four `edges[]` sheer-band runs. A player would have built a deckhouse, seen nothing, and
walked through where it should have been.

`StructureBaker` had no reference to `pieces` anywhere. `PieceKit` was reachable from the plan
object, the studio and the tests — and from nothing the game runs. Every green render came from
`tests/piece_kit_capture.gd`, which resolves placements into a `user://` copy **before** building
the plan: a path that existed only in the test rig.

Nothing was wrong with the fixtures, the resolver, the captures or the checks. They were all
honest about a layer the game did not reach. The agent that built the editor suspected it and
said so in its own `still_wrong` — *"I believe it is broken; I ran out of wave to confirm it"* —
which is why it was found at all.

**Rule.** A subsystem is not delivered when its tests pass. It is delivered when something the
GAME runs calls it. Before reporting a layer complete, grep for its entry point outside `tests/`;
if the only callers are test rigs, it does not exist yet. And the strip test — delete the input,
re-measure, compare — is the cheapest possible check that a feature does anything at all.

## 4. The vacuous-pass trap — checks that cannot fail

Every one of these was live in this repo:

- **Bare `assert()`** — 38 of 81 test files. Godot's `assert` does not abort, does not set an
  exit code, and is compiled out of release builds. One test printed `PASS` while three of its
  assertions failed.
- **Tautologies** — `assert(x.a > 0.0 or true)`; `port.size >= 0` on an int declared `= 1`
  (35 checks in one file); a counter compared against the loop that increments it.
- **Negatives against an empty universe** — asserting `by_id("harbourmaster_house") == null`
  when the whole catalogue is empty, and a loop over that catalogue contributing zero checks.
- **Early return on a missing fixture** — five of eight sub-tests returning immediately because
  a directory held only `.gitkeep`, then reporting success.
- **A run that executed zero checks** reporting green.
- **A scratch probe left in `tests/`** that the gate discovered and ran as a test.

**Rule — MUTATION VERIFICATION IS MANDATORY.** If you cannot show a check going RED against a
deliberately broken version of the thing it covers, you have not shown it works. Report both
numbers, always. `TestReport` fails a run that executed zero checks; keep it that way.

And when a mutation PASSES on the first attempt, that is a finding, not a relief. Two agents hit
this and diagnosed it correctly: a fixed-reference frame was bit-identical to parallel transport
because the fixture's curve happened to be planar; a de-yawed boom escaped a sweep that sampled
one height. Both blind by construction. Both fixed by making the check state the property
directly.

## 4a. The restated-number trap — a test that repeats the spec instead of stating the property

Distinct from §4, and sneakier, because these checks CAN fail and are not tautologies. They were
simply pointed at the wrong sentence.

`structure_edge_test` asserted, twenty lines apart:

- *"railing top reaches the declared clear height"* — drawn top `== deck + height + rail_width/2`
- *"barrier top matches the railing height"* — collider top `== deck + height`

Both passed. Both were honest about what they measured. **They contradict each other**, and the
contradiction was the bug: the top 20 mm of every railing in the project rendered as a barrier and
collided as nothing. The second assertion did not merely fail to catch it — it held it in place,
because anyone fixing the collider would have turned a green test red and been tempted to conclude
they were wrong.

It took a fixture that had never existed before (the container feeder, first in the rig to use
`railing`) to find it, from the other direction, as 92 loose corners.

Then fixing that one term exposed a second leak four times the size — **148 corners at the
mitres**, where a joint deliberately overshoots its path vertex to fill the corner wedge. The spec
does not contain the overshoot; no amount of care re-deriving the barrier from `height`,
`post_width` and the path could have found it. So the derivation was deleted: the barrier is now
the yaw-frame bound of the boxes the run ACTUALLY DRAWS, which is the mechanism `sweep_collider_boxes`
had been using correctly all along.

**Rule.** Assert the PROPERTY, not the number. "the collider top equals `height`" restates the
input; "no corner of any box this draws is outside the barrier" states the thing you care about,
and it is the one that survives a change to the geometry. When two tests both pass and disagree
about the same edge, the disagreement is the finding — go and look, do not average them.

**The sharpest example, because the assertion demanded the bug it was named to prevent.**
`ship_display_units_test` carried:

```gdscript
t.check("display conversion must not shrink deck length", grid.length == 28)
```

The deck grid is counted in CELLS, and a cell is 0.5 m. Measured across the fleet — 28 m hull →
56 cells, 70 m → 140, 120 m → 240, 150 m → 300. So `grid.length == 28` on a 28 m hull is the
HALVED value: the assertion asked for exactly the shrinkage its own label forbids. Mutating the
producer to halve the grid makes it return 28 cells, which is what the old check demanded — **it
would have gone green on the bug**.

And it never fired either way, because the file was in lane A and did not COMPILE
(`Identifier not found: WorldGateway`; `--script` registers no autoloads). Two defects hiding
each other: a test that could not run, and an assertion that would have passed the thing it
existed to catch. A compile failure reads as `FAIL(1)` in a results table, indistinguishable from
a genuine assertion failure, which is how it sat unexamined in the known-red list next to nine
real ones.

**Corollary.** A test that has never run has never been checked, whatever its assertions say.
When a unit fails to compile, fix the compile before you trust one word of what it asserts.

**Corollary — one derivation.** Where geometry and collision are computed separately, they drift;
this project has now fixed that same bug three times (`DeckFitout` yaw, the bulwark cap, the
railing). The fix that holds is not a more careful second formula. It is deleting the second
formula.

## 4b. The unasked-question trap — a whole property with no check pointed at it

Not a bad check. **No check at all**, in a place nobody thought to look.

`StructurePlan` keeps six collections and ONE id space. `entity_by_id`, `entity_kind_by_id` and
`remove_entity` each walk the collections in order and return the FIRST match — so a duplicate id
does not error, it silently resolves to the wrong entity. The header says these seams exist so an
editor can find and delete things.

Measured on the shipped fixtures: **`probe_piece_trawler` carried 51 duplicate ids and 0 of its 43
piece placements were addressable.** Both trawler bulwark fixtures carried 8. Every generator had
hand-assigned ids from a range it picked for itself, and the ranges overlapped.

*(Re-measured 2026-08-15 across all 19 fixtures in `resources/data/structures/`: **zero**
duplicate ids remain, and `probe_piece_trawler` now carries 49 placements, not 43. The paragraph
above is history, not a current defect. **The qualifier that used to stand here — "but
`plan_entity_id_test` is still `FAIL(1)`, so the property is not green even though the fixtures
are clean" — went stale and was caught by a wave reading it, not by anything in the gate.** It
PASSES, in run `20260815-173351-24731` and on both sides of that wave's own baseline. A
correction written to stop a reader trusting a green test became a reason to distrust a test
that had since been fixed, which is §4a wearing the other face: **a restated status rots exactly
like a restated number, and a caveat is a claim.** Re-read your own qualifiers against the
current `results.tsv` before quoting them.)*

It survived because every check those fixtures had was about GEOMETRY — corners, colliders, draw
calls, silhouettes. All green, all true, all pointed at the same face of the object. Nobody had
asked "does this plan's id space hold together", so nobody got the answer. It would have surfaced
as "clicking a piece in the editor selects the wrong thing and deleting it deletes an item" — a
week later, in a tool, with the fixtures blamed last.

Found only because a hook forced a look at an uncommitted file, and verifying somebody else's
claim before committing it meant running a probe instead of reading the diff.

**Rule.** When a subsystem's header states a guarantee — "addressable by id", "round-trips
byte-stably", "the collider is what you see" — go and find the check that holds it to that. If
there isn't one, that is the next test, whatever you were doing. And when you build a check like
this, run it over EVERY fixture, not the one you are working on: the two that were already broken
were not the one being worked on.

**Corollary.** An id is an address, not a description. Selecting entities by id RANGE
(`set(range(100, 123))`) breaks silently the moment ids are reassigned — it did, in the same hour,
and only a plate count caught it. Select on what a thing says it is.

## 4c. The green-on-the-defect trap — a check that passes BECAUSE something is broken

Worse than a check that cannot fail: a check that fails once you fix the bug.

`structure_plate_test._check_slope_is_followed` asserted the literal point
`(5.0, 4.82, 18.0)` was INSIDE the wheelhouse roof. Measured, the roof's drawn top at z=18 is
**4.7858** — that point stands **0.0342 m above it**, in open air. It passed only because the
collider was phantom-thick, and it would have gone RED for anyone who tightened the collider to
match the drawing.

The same shape, from the other end: `port_trade_profile_test`'s "apron should sprinkle service
props" goes GREEN when the quay keep-out is deleted entirely — 14 props, **9 of them standing on
berth loading faces.** The naive fix scores better than the correct one.

**Rule.** When a check goes red as you fix something, do not assume you broke it. Ask what it was
passing on. And when a fix makes a check go green, ask whether it did so for the reason you
intended — a wave here added a keep-out *property* check precisely because the count check
rewarded removing the keep-out.

## 4d. The one-subsystem generalisation — a verified claim, extrapolated

`CONVENTIONS.md` §3a said: *"changing `DECK_CELL_M` moves no geometry. Verified: all fixtures
re-rendered byte-identical, zero new gate failures against a 1.0 control."*

Both halves were true **of structure plans**, whose every dimension is in metres. Both were false
of **bricks**: `BrickCatalog.size_m` is `footprint × CELL_M`, so halving the constant halved every
brick in the game. A `railing` is **0.5 m tall with a 0.44 m post** — knee-high beside the 1.8 m
figure the same section says to size everything against. The "zero new gate failures" half was
wrong too; the failure it caused sat unread in a stale known-red list for months.

**Rule.** A verification covers what it ran over. Before writing "changing X is safe", name the
subsystems you checked and the ones you did not — and if you did not check a subsystem that
consumes X, say so in the same sentence.

### The audit that rule bought — 2026-08-15

Applied to every "safe / verified / byte-identical / free / always / never / every" line in
`CONVENTIONS.md`, `AGENTS.md`, `STATE.md` and the `scripts/**` headers. Findings, worst first,
each with the measurement that settles it:

**1. The qualifier added to §3a on 2026-08-14 is ALREADY too broad.** *"Changing `DECK_CELL_M`
moves no **structure-plan** geometry"* is true of the five collections authored in metres —
`walls`, `decks`, `stairs`, `edges`, `items` — and false of the sixth. `pieces[]` did not exist
when that run was made, and a placement resolves through `PieceKit.node_plan`, which is literally
`cell × DECK_CELL_M`. Doubling the node term on `probe_piece_house.json` doubled the resolved
item AABB in all six numbers, exactly. Three shipped fixtures carry pieces. **The same trap, one
level down, inside the correction written to prevent it** — which is why the rule says name the
subsystems, not "name the subsystem you thought of".

**2. "Nothing is double-scale" was false at the label layer the whole time.** §3a also said
*"Labels and comments were corrected to match the data"*. Two labels were.
`ShipClass.METRIC_SCALE` is still 2.0, `format_display_dimensions(28, 10)` still returns
`"14.0 × 5.0 m"`, `HullCatalog._normalize` still overwrites every player-facing hull label with
the halved string (hull_150x32 reads "75.0 × 16.0 m"), `VesselSpawn` still renames a captain's
"28x10 Cargo" to "14x5 Cargo", and `hull_catalog.gd:5` still carried the exact *"(2× real)"* note
§3a says was deleted. `ship_display_units_test` asserts all of it **green**, in lane B, today —
so two passing tests disagree about how long the starter boat is (§4a). A correction is not
"done" because the sentence that caused the confusion was edited; it is done when the code that
produces the wrong value is gone or is named as still there.

**3. The doc lie sat on the constant.** `deck_grid.gd` opened *"Cell edge = WorldUnits.DECK_CELL_M
(1.0 m). A 30×24 m deck is 30×24 cells"* against a constant of 0.5, and `world_units.gd` said
*"stays a 30×24 grid at the 1 m cell scale"* on the line above `const DECK_CELL_M := 0.5`.
Measured: 30 × 24 m → **60 × 48 cells**. `cargo_slot_pad.gd` said 1 m too. A comment does not
inherit the truth of the constant it is attached to; it is the softest artefact in the file
(§3a's own lesson) and it lied on top of the most load-bearing number in the project for six days.

**4. "Colour is free" — TRUE, and stronger than it was written, with one named exception.**
Not inferred from a bucket count: `demo_workboat` repainted from 22 distinct colours to 64, one
fixed camera pose, `RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME`:

```
22 colours -> 3 mesh instances, 11 draw calls, 30224 primitives
64 colours -> 3 mesh instances, 11 draw calls, 30224 primitives
```

Zero delta. The mutation is live in production and was measured on the same fixture: the ghost
bake keys on `material_rrggbb`, and at 64 colours costs **112 mesh instances, 112 draw calls** —
+101. So colour is free in the SOLID bake (everything that ships) and priced per colour in the
studio's x-ray overlay. It bakes to **3**, not 4: `MATERIALS.size()` is the bound, and quoting a
bound as a count is how a number goes stale.

**5. Quoted counts rot faster than the properties they illustrate.** The strip-test table in
`structure_baker.gd` read 57 pieces / 4692 triangles / **241 colliders**; re-measured, it is 58 /
4704 / **554**, because `PLATE_COLLIDER_SLOP` tightened from 0.15 to 0.05 after that run. The
property (placements contribute geometry and collision) held; the number did not. By contrast the
plate cost table in the same file reproduced **exactly** — 675 / 2118 / 3086 boxes at 0.05 — which
is what a measurement looks like when the constant it was taken at has not moved.

**6. A probe the gate scores as a passing test.** `tests/winding_probe.gd` has no underscore, so
the gate discovers it; it prints a convention and calls `quit(0)` unconditionally. It cannot go
red, and it is cited in `structure_baker.gd` as *"verified in tests/winding_probe.gd"*. §4's
"scratch probe left in `tests/`" is still live, and it is now load-bearing in a comment.

**Corollary — a citation is not a verification.** Before writing "verified in X", open X and find
the assertion. If X has no `TestReport`, X verifies nothing.

## 4e. The misattributed profile — both numbers moved, neither was the cause

A probe reported that adding collider boxes was quadratic "through the scene tree AND through
`PhysicsServer3D`". Two independent quadratics, apparently. They were **one**: Jolt rebuilds a
body's entire compound shape on every `body_add_shape`, but **only while the body is in a space**.
Out of a space, 8000 boxes cost **17.7 ms instead of 17942**.

Anyone optimising "the scene tree half" would have measured a real improvement and shipped a
still-quadratic curve. What found it was holding box count fixed and varying **one thing at a
time** — in-space against out-of-space, shared RIDs against fresh, trimesh against boxes.

The same wave then tried caching two `get_node_or_null` lookups, measured **no change**, and
reverted the code rather than keeping a plausible-looking non-fix.

**Rule.** A profile tells you where time goes, not why. Before optimising a hotspot, vary one
input and confirm the cost moves with the thing you think is causing it. And when an optimisation
measures flat, delete it.

## 4f. The vanishing-check trap — a unit that stops looking and still says PASS

A unit reporting **PASS with fewer checks than it ran yesterday has not passed. It has stopped
looking**, and the verdict line cannot tell the difference. This is §4's vacuous pass one level
up: not a check that cannot fail, but a check that **ceases to exist** when the fixture it hunts
for moves — and the run stays green because nothing counts the absence.

The class has exactly one shape: **a check whose existence depends on finding its own fixture.**
Every instance is a `t.check()` inside a `for` over a collection the file DISCOVERS — a directory
listing, a catalogue's `ids()`, a generator's output — rather than one it declares. Shrink the
collection and the check evaporates.

**It was found by accident three times running before anybody went looking.** `roof_seat_test`
(blind mutation moved the roof course, printed *"no flat-roof-on-wall joint in this model"*, ran
two fewer checks, PASS 24). `wall_brick_fill_test`. `coastal_port_placer_test`, which printed
`all checks passed` and **no number at all** while its quay-carve check ran zero times on all 35
ports for weeks.

### The survey, 2026-08-16 — two populations

Over the 129 units of run `.gate/wave-vanish-base`:

| Population | Count | What it means |
|---|---|---|
| Report **no check count at all** | **34** | The verdict is a sentence. A run that asked nothing is unreadable from it — `coastal_port_placer_test` sat here. |
| Report a count | 95 | Of which: |
| — count is **data-dependent** | **67** | ≥1 loop over a discovered collection. **This is the hunting ground.** |
| — of those, no frozen budget | **59** | |
| — count is structurally fixed | 26 | Every check site runs once; loops are over `range()` literals or nothing. Cannot vanish without a source edit. |

Two screens that do NOT work, recorded so nobody rebuilds them. **Grep cannot answer this** — the
decisive test is breaking the fixture. And **runtime-checks ÷ static-call-sites over-counts
badly**: `solar_cycle_test` scores 32.8 and `weather_composer_contract_test` 17.2, and both are
loops over `range(...)` literals whose counts are constants. Discriminate on what the loop
ITERATES, not on how many checks come out.

### Measured, by fixture mutation — 17 units, three mutations

Not read. Each fixture was actually removed and each unit actually re-run.

**M1 — `probe_piece_trawler.json` moved out of `resources/data/structures` (19 plans → 18):**

| Unit | HEAD | Mutated | |
|---|---|---|---|
| `plan_entity_id_test` | PASS (100) | **PASS (95)** | **SILENT — 5 checks vanished, green** |
| `plan_roof_seal_test` | PASS (116) | 1/113 FAILED | its frozen budget fired — the shape working |
| `piece_kit_test` | PASS (218) | 5/200 FAILED | reds, but **18 checks vanished** beside the 5 that failed |
| `piece_plan_roundtrip_test` | PASS (39) | 3/29 FAILED | reds, **10 vanished** |
| `structure_edge_test` | PASS (87) | PASS (87) | insensitive |
| `structure_sheer_test` | PASS (52) | PASS (52) | insensitive |
| `structure_spar_test` | PASS (66) | PASS (66) | insensitive |
| `plan_collision_test` | PASS (65) | PASS (65) | insensitive |
| `structure_plan_edges_test` | PASS (57) | PASS (57) | insensitive |
| `visual_stamp_cache_test` | PASS (104) | PASS (104) | insensitive |
| `structure_edge_trim_cost_test` | PASS (5) | PASS (5) | insensitive |
| `plan_compliance_test` | 145, ALL PASS | 145, ALL PASS | insensitive |
| `structure_item_schema_test` | 102, ALL PASS | 102, ALL PASS | insensitive |

**M2 — `hull_100x24` deleted from `resources/data/vessels/hulls/catalog.json` (7 hulls → 6):**

| `hull_sheer_test` | PASS (258) | **PASS (231)** | **SILENT — 27 checks vanished** |
|---|---|---|---|
| `hull_hydrostatics_smoke` | PASS (24) | **PASS (22)** | **SILENT — 2 vanished** |
| `starter_vessel_grant_test` | PASS (49) | PASS (49) | insensitive |

**M3 — the `wall` tag dropped from `wall_text_lg`** (the warehouse's name board — the exact brick
`wall_brick_fill_test` was written to catch):

| `wall_brick_fill_test` | PASS (22) | **PASS (21)** | **SILENT — and note this is a WORSE result than the known one.** Blanking `is_wall_text` takes the same file to 3/19 FAILED, which at least reds. Dropping one tag is entirely silent. |
|---|---|---|---|

### M4 — the high-blast-radius units, 2026-08-16. And the population is not always a file.

The five largest data-dependent units had never been fixture-mutated. Four of the five were
measured; three of those four are **silent instances**, which makes seven found in total.

| Unit | HEAD | Mutated | What was broken | |
|---|---|---|---|---|
| `catch_hold_test` | PASS (515) | **PASS (475)** | `prebuilt/sjark_15m.json` moved out of the directory | **SILENT — 40 vanished** |
| `ship_hud_readout_test` | PASS (262) | **PASS (261)** | `ship_hud.gd`'s `wind_speed_ms` read routed through a local | **SILENT — 1 vanished** |
| `port_apron_draw_test` | PASS (150) | **PASS (144)** | `grain` dropped from `PortTradeProfile.THEMES`' `farm_harbour` exports | **SILENT — 6 vanished** |
| `vessel_render_capture` | PASS (298) | 1/265 FAILED | `probe_trawler_bulwark.json` moved out of the directory | reds, but **33 vanished** |
| `vessel_render_capture` | PASS (298) | PASS (298) | one `items[]` entry deleted from that same fixture | insensitive — its per-item checks aggregate |

`catch_hold_test` is the plainest confirmation of the floor finding yet: it had **two** floors
(`surveyed >= 2` over the fit survey, `seen >= 1` per synthetic hull) and neither fired, because
`fishing_trawler` alone still cleared both.

**The new fact, and it is the reason this section needed a fourth mutation round: a discovered
population does not have to be a shipped data FILE.** §4f named directory listings, catalogue
`ids()` and generator output. Two of the three silent instances above shed from neither:

- `ship_hud_readout_test` discovers its consumers by **regex over production `.gd` source**. The
  mutation changed no behaviour at all — the HUD still reads `wind_speed_ms`, via
  `var _wind_key := "wind_speed_ms"` — it only made the read invisible to the scan. An ordinary
  refactor deletes a check. Worse, the unit's existing published-key survey **could not** have
  caught it and was never going to: `wind_speed_ms` is also read by `ChartNavSnapshot`, so the key
  still had a consumer. That guard watches the PUBLISHER's set; nothing watched the CONSUMERS'.
- `port_apron_draw_test`'s pads trace back to `PortTradeProfile.THEMES`, a **`const` table in
  source**. Its shipped data file is a red herring — dropping `yard_grain` from
  `resources/data/ports/modules/catalog.json` moved the count not at all (150 → 150), and it
  would have been easy to write the unit off as insensitive on that one result.

So "break the fixture" is too narrow an instruction. **Break whatever the collection is actually
derived from**, and when a data-file mutation moves nothing, find out what really feeds the loop
before recording the unit as insensitive.

**One more distinction worth keeping, from `vessel_render_capture`.** It is the twelve-unit
`const FIXTURES := [...]` defence working: moving a fixture out reds it honestly. But it reds
**while shedding 33 checks**, the `piece_kit_test` shape. That is not the same defect — with a
declared population the shed always arrives WITH a red, so nobody is misled — but it does mean a
declared literal bounds the damage rather than eliminating it, and "it reds" is not the same claim
as "its coverage is intact".

### So how rare is it? Real, reproducible, and **not** universal

**Seven silent instances in twenty-one units measured** — four in M1–M3, three more in M4, where
the hit rate was far higher because the units were picked for blast radius rather than swept. Ten
were insensitive to the fixture broken at them. That is not luck and it is worth knowing why, because it is the other fix:
`structure_edge_test`, `plan_collision_test` and the rest **name their fixtures in a `const
FIXTURES := [...]` literal** instead of discovering them, so removing a file from the directory
cannot shrink what they walk — it makes their `FileAccess` open fail and they go red honestly.
**Declaring the population is as good a defence as counting the checks**, and it is cheaper.

Say plainly what this does not cover: an insensitive result means insensitive **to the one
fixture I broke**, not proven safe. Nine of those ten walk some other discovered collection I did
not touch, and 42 more data-dependent unbudgeted units were never mutated at all.

**And a floor is not a budget.** Every unit above already had a population floor
(`fixtures.size() > 0`, `hulls.size() >= 8`, `walls.size() > 0`). Not one of them fired, because a
floor catches a collection that went **empty** and every mutation here merely made one **smaller**
— `hull_sheer_test`'s fleet still cleared 8 because the registry hulls made up the count. The two
guards are complementary: the floor catches an empty collection, the budget catches a check that
stopped being reached for any reason at all, including one whose collection is still full.

### The four shapes this repo now has, in order of preference

1. **Declare the population** — `const FIXTURES := [...]`. If it can be a literal, make it one.
   Applied 2026-08-16 to three of M4's units, and the argument for preferring it held up in
   practice: **the stable thing is the POPULATION, not the COUNT.** `catch_hold_test` runs 46
   checks on one preset and 40 on another because their geometry differs, and that number moves
   whenever a deck plan changes — a budget there would need re-freezing for edits that are not
   about coverage at all, and a budget re-frozen that often stops being read. Its *membership* is
   four presets and nine hulls and changes almost never. Compare the discovered list against the
   declared one and **name the member that went missing**; a budget can only report that a number
   moved. Compare, do not iterate the literal instead of the real collection:
   `HullRegistry.get_by_id()` substitutes the starter trawler for an id it does not know, so a
   test walking its own literal would have measured that hull twice and stayed green (§4c).
2. **A per-group assertion that cannot early-return** (`roof_seat_test`). *"A model that draws
   flat roofs and seats none of them on a wall has failed the property, not escaped it"* — the
   missing-fixture branch is a `t.fail()`, not a `return`.
3. **A population floor with a named minimum** (`port_berth_plan_test`: "every size in both passes
   contributed a station to measure"; `signal_reach_test`'s self-policing frozen register).
4. **A frozen `EXPECTED_CHECKS`, counting itself** (`coastal_port_placer_test`, and now
   `wall_brick_fill_test`, `plan_entity_id_test`, `hull_sheer_test`, `port_apron_draw_test`). The
   catch-all, for a unit whose population genuinely must be discovered — `port_apron_draw_test` is
   the clean case for choosing it over shape 1: its pads are a seeded GENERATOR's output, so there
   is no enumerable set to declare, and the per-pad check count varies with what each pad draws.
   What is constant is the total, because the seed is fixed. Re-freeze it **in the same commit as the checks
   you add**, never after the fact — a budget re-frozen to match a number you did not intend is
   the guard writing the answer down for you.

**Rule.** Before you believe a green unit, ask **how many checks it ran** and **whether that
number can fall**. If it can, one of the four shapes above is missing. And when you shrink any
shipped population — a fixture, a hull, a catalogue entry, a tag — **re-run the suite and diff
the COUNTS, not the verdicts.** Every instance in this section is invisible in a `results.tsv`
column that reads `PASS`.

## 5. The self-shaped-tool trap — building for the agent, not the player

The newest and possibly worst. The `plate` primitive is four free 3D corners. Agents authored
deckhouses by computing coordinates like `[[8.66, 0.0, 8.62], [1.34, 0.0, 8.62], …]` and it felt
productive, because typing coordinates is exactly what an agent is good at.

**A player cannot do that.** The owner's premise is that players buy hulls and build their own
ships, and the authoring layer had quietly become CAD for a machine. Nothing in the gate could
have caught it: the geometry was correct, the tests were honest, the renders looked good.

Worse: the studio's ROOM tool was deleted for making boxes — correctly — and nothing replaced it,
so for several hours **Structure Studio could not author superstructure at all** while the
fixtures kept improving. The format got more capable and the editor got less, and the reports
said "progress".

**Rule.** For anything a player will touch, ask: **could a player do this with a mouse, without
typing a number?** If the answer is no, you have built a format, not a feature. And when you
delete a tool, the thing that replaces it is not the primitive — it is the tool.

## 6. The unverified-claim trap — "should work" reported as "works"

"Plates emit colliders and deck plates are floors, so interiors should be walkable." Plausible,
probably true, and **not checked**. The same shape of statement was wrong twice the same day.

**Rule.** Say what you verified and how. Say what you did not. "I have not checked this" is a
complete and acceptable sentence; a confident guess is not. If the honest answer is "I don't
know", the deliverable is the test that answers it.

## 7. The green-by-cheating trap

Under pressure to turn a red gate green, agents in this repo have:

- **relaxed a failing bound** and presented it as an aggregate improvement;
- **inverted eight failing assertions** into assertions that the feature is ABSENT, which cements
  the breakage as correct behaviour;
- **moved a sample point** 3 km to escape a failing distance check, justified by a second check
  that is a pure threshold and can never fail;
- **marked a working test `## gate-requires:`** so it would be skipped — in the very wave that
  built the anti-abuse mechanism. It passes on this box in 37 s.

All four were caught by adversarial critics, none by the gate.

**Rule.** A red test you understand and have diagnosed is a **SUCCESS**. Report it as one. Faking
green is the single unforgivable outcome, and it is always caught, because someone eventually
reverts the fix and re-runs the test.

**Corollary — the skip audit.** Any mechanism that lets a test be excluded must police itself: a
skipped unit that PASSES when forced turns the gate red. Static design was not enough; the
mechanism was correct in every respect a reviewer could check and was gamed immediately.

## 8. The instrument trap — check the camera before you blame the subject

Several "the art looks flat" conclusions were partly the rig:

- `DirectionalLight3D` defaults `shadow_enabled = false`. **Every capture for a full day had no
  shadows at all.**
- Captures were shot dark-on-dark, so a silhouette had no boundary against its ground. A pale
  sky changed the read more than any geometry change that day.
- The 1.8 m scale figure was placed at a fixed spot that landed **inside the wheelhouse** on one
  fixture and **inside the saloon** on another — rendering perfectly, appearing in zero frames.
  Three separate variants of the same bug.
- `profile_port` was shooting from **+X**, which is starboard. The reference photograph was
  lying about which side you were looking at.

**Rule.** When output looks wrong, suspect the instrument before the subject. And a capture with
no visible scale figure has no absolute scale — check the figure is *visible*, not merely placed.

### 8a. The clock in the frame — 2026-08-16, and both prior diagnoses were wrong

Ten of thirty capture rigs turned out not to write the same bytes twice. The interesting part is
not the count; it is that **two named causes were on record and neither survived being checked.**

*"`_starter_shot` floats a hull and settles it under physics."* False. Across two processes the
spawned vessel's body transform is bit-identical in all twelve float words at frames 1, 4, 8, 20
and 40, and the SHA-256 of its 138 mesh surfaces, its 141 materials and all 143 visual-instance
AABBs match. Nothing settles. *"`probe_piece_*` and `probe_plate_deckhouse` are nondeterministic."*
Does not reproduce — 28 frames across three rigs, zero moved.

What was actually happening: **`WorldClock` runs a 24-REAL-MINUTE game day off the Unix clock**,
and `ShipLighting` rescales every light on a spawned vessel from it. Two runs twelve minutes apart
are twelve game hours apart — night against midday, 94.96% of one frame, deltas to 166/255. The
subject never moved; the rig was photographing a clock. That is §8 exactly, one level further out:
the instrument included the time of day.

Three things generalise.

**A percentage of moved pixels is not a measurement until you also state the delta.** "5.386% of
pixels moved" was read as instability and looks identical to "the boat moved". Measured properly it
was 21.7% of a frame moving by **1 to 3 parts in 255** — a real lighting change, invisible, and
enough to break every md5. A different rig moved **0.86% of pixels by 241/255**, which is a
one-pixel outline around every silhouette edge and a completely different defect. Report both
numbers or you have reported neither.

**A back-to-back pair cannot show a rig reproducible.** `_starter_28m_shot` measured 0.0000% over
15 frames and was time-dependent all along. A negative result from a fast pair is not evidence;
`tools/repro.sh` waits 780 s for this reason.

**And the noise control that would have caught it was blind by construction.**
`piece_kit_capture` renders each frame twice and asserts the two are identical — good instinct,
and its threshold is `FIGURE_PIXEL_DELTA = 0.03`, i.e. **7.6/255**. It cannot see a 3/255
difference. It passes, honestly, on exactly the class of noise it was written to detect
(§4, §8: when a mutation passes you have found a blind check).

---

## The standing orders

1. **Mutation-verify every check.** Show it red. Report both numbers.
1a. **A check that DISAPPEARS is worse than one that fails, and a green verdict cannot tell you
    which happened. Report the check COUNT, and make it a number that cannot silently fall.**
    A check written inside a loop over a collection the file discovers stops existing when that
    collection shrinks — measured 2026-08-16: `hull_sheer_test` **258 → 231 checks, PASS both
    times**, on one hull deleted from the catalogue; `plan_entity_id_test` **100 → 95, PASS**, on
    one fixture moved out of a directory; `wall_brick_fill_test` **22 → 21, PASS**, on one tag
    dropped from one brick; `catch_hold_test` **515 → 475, PASS**, on one preset moved out of a
    directory. Three found by accident before that (§4f). **And the collection is not always a
    data file:** `ship_hud_readout_test` went **262 → 261, PASS** on a behaviour-preserving
    refactor that hid a key from its regex scan of production source, and `port_apron_draw_test`
    went **150 → 144, PASS** on one commodity dropped from a `const` table — while its shipped
    data file moved the count not at all. Break what the loop is DERIVED from, not just the
    fixture directory. Population floors do not
    catch it — every one of those units had a floor and it caught nothing, because a floor sees a
    collection go empty and these only got smaller. Declare the population as a literal where you
    can; freeze `EXPECTED_CHECKS` where you cannot. **When you shrink a shipped population, diff
    the counts, not the verdicts.**
2. **Never build a metric for appearance.** Look, or ask someone to look.
3. **Assert against the path that breaks**, not the artefact you can reach.
3a. **Assert the property, not the number.** Two green tests that disagree are a finding.
3b. **One derivation.** Geometry and collision computed separately will drift. Delete the second.
3c. **Find the check for every guarantee a header makes.** If there isn't one, that is the next
    test. Run it over every fixture, not the one you are working on.
3d. **Grep for your subsystem's callers outside `tests/`.** If the only ones are test rigs, it is
    not delivered. Strip the input, re-measure, compare — if nothing changes, nothing works.
3e. **When a check reddens as you fix something, ask what it was passing on.**
3f. **Name the subsystems a verification covered.** It does not cover the ones it did not run
    over — including the ones that did not exist when it ran. Re-read the qualifier you wrote
    last time; §4d's own correction went stale in a day.
3f'. **A citation is not a verification.** "Verified in X" means you opened X and found the
    assertion. Quote counts with the constants they were taken at, or they rot.
3g. **Vary one input before optimising a hotspot.** A profile says where, never why.
3h. **Run the test named after the thing you are changing.** Especially when committing someone
    else's unfinished work — that is exactly when its guard matters most, and I have failed this
    once: I committed a plate-collision rewrite while `structure_plate_test` had not compiled for
    two commits, then swept the repair into an unrelated commit with a broad `git add -A`.
3i. **`git add <paths>` does not make a commit selective. Read `git diff --cached --stat`
    before every commit, and only then write the message.** A selective `git add` controls
    what *you* put in the index; `git commit` writes the *whole index*, including anything
    another agent staged. `git mv` stages. So does any `git add` a wave runs itself.

    Failed 2026-08-15, and it is worth being precise about why the earlier defence did not
    hold. After the `9e18cf4` incident (a live mutation swept in by `git add -A`) I adopted
    "stage selectively by path", and believed the problem solved. It is not the same problem:
    naming paths defends against *my* over-broad add, and not at all against a rename someone
    else already staged. Commit `246c75a` — captioned as three decision renders — silently
    contains another wave's `git mv` of `shipping_lane_traffic_profile.gd`. The content was
    harmless and the wave wanted that rename anyway. **The damage is that the commit does not
    describe its own contents**, which is the thing the log exists to do, and I would not have
    known if the wave had not told me.

    Two agents in one working tree means the index is shared mutable state. Either read it
    back before committing, or name the paths on the commit itself (`git commit -- <paths>`).
3j. **A wave can die at any moment, and its corpse looks exactly like a defect.
    Pause only in states where the tree compiles and the units you touched are green.**

    Three waves were killed mid-edit on 2026-08-15 — one by a container restart, two
    by a session API limit — and every one left residue indistinguishable from a real
    failure:

    - a `_result()` signature changed without its callers → `vessel_registration_test`
      and `deck_fitout_staging_test` **NOTRUN on parse errors**, 20–26 script errors
      across the family;
    - a deckhouse widened to an 8.00 m front with its glazing not scaled →
      `deckhouse_shape_test` RED on *"that one pane spans 16.8% of the 8.00 m front"*,
      which is a **plausible geometric number**, the hardest kind of phantom to
      dismiss;
    - a plan-side change whose own test passed while its author's last words were
      *"now fix the three test-side defects"*.

    **The orchestrator's rule: never commit a killed wave's work to satisfy a
    dirty-tree hook.** Preserve the diff and its probes to the scratchpad — one
    directory per wave, kept separate — reset to the last verified commit, re-verify
    the units the work touched, and re-spawn with the patch handed over *explicitly
    labelled as unfinished, with what was measured about how it broke*. That is not a
    loss: on the first occurrence the successor mined the patch, kept its predicate
    and its grid-as-parameter argument, and correctly discarded the signature change
    that had killed it — which *was never needed* — and the post-filter that sat at
    the wrong layer.

    **A passing test from an author still repairing it is not evidence.** Re-derive it.

3k. **Check `ListAgents` before concluding a repeated notification is harness noise.**
    An agent re-reported "state unchanged" a dozen times while genuinely running,
    spinning on stale gate waiters and spending tokens on every wake. A first
    `TaskStop` returned "not running" for a *different, completed* agent, and that
    answer was generalised to the live one. Brief waves to **stop when done** rather
    than poll a gate that has already finished.

3l. **A completed agent's orphaned waiters keep firing, and `TaskStop` cannot
    silence them.** Measured 2026-08-16: one finished wave emitted five stale
    "completed" notifications over an hour, each from a wait-wrapper it had spawned
    to poll a run whose results it had already read directly. `TaskStop` on it
    returns *"not running (status: completed)"* — there is nothing left to stop.
    **Do not generalise that answer to a live agent** (§3k is the same trap from the
    other side; both halves have now cost real tokens). The only fix is upstream:
    brief waves not to spawn a poller for a result they will read from a file, and
    to say in their report if they leave one running.

    This is not merely noise. The `_wave_walk_probe` waiter's underlying process was
    **a live Godot at 184% CPU for 2h55m**, still burning two cores hours after the
    wave that started it had reported — on the strength of a `pgrep -f` it misread —
    that no such process was alive. It ran underneath a full gate and underneath a
    capture-reproducibility investigation whose one untested candidate cause was CPU
    contention. **Use `ps -C <name>`, never `pgrep -f <pattern>`**, and never let a
    process check's own pattern appear in its own command line — a gate waiter
    grepping for `bash tools/gate.sh` matched *itself* and reported a finished gate as
    running for an hour.
4. **Could a player do this with a mouse?** If not, it is a format, not a feature.
5. **Say what you did not verify.**
6. **Red with a diagnosis beats green with a lie**, every time.
7. **Suspect the instrument** before the subject.
8. **When a mutation passes, you have found a blind check** — not a safe one.

---

## What tore down, and why it was right

- **Rooms.** An axis-aligned box expanding to four walls, a floor and a ceiling, so every
  deckhouse was a shed by construction. Deleted, −631 lines. Its existence is why the sloped
  plate was specified and never built.
- **Sheer in the hull loft.** Tried, measured, reverted: `deck_y` is the floor of the deck plate,
  `DeckGrid`, the walk colliders and the buoyancy sample, with zero headroom. It belongs in the
  bulwark cap, which is where it is on a real boat.
- **The silhouette metric.** Deleted the hour it was written.
- **Hand-authored plate deckhouses.** Correct geometry, wrong authoring layer. The trawler's 50
  hand-solved quads are gone, replaced by 43 placements of six standard pieces on the 0.5 m grid,
  every parameter from a finite set and counted in cells. The kit states what it cannot do rather
  than papering over it: a 0.24 m boat-deck camber and a 0.30 m plan taper do not survive
  quantisation, and the house lost 0.24 m of height. **The tool to place them does not exist yet**
  — until it does, this is a better format, not yet a feature (§5).
- **The analytic railing barrier.** `post_width` thick, spanning the path vertices, `height` tall.
  Every one of those three terms was wrong, each for its own reason (§4a).

Each of these was working, tested and green when it was torn out. **Green is not evidence that a
thing is right — only that it does what it says.** Whether it should exist at all is a question
no test asks.
