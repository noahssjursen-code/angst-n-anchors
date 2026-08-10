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

---

## The standing orders

1. **Mutation-verify every check.** Show it red. Report both numbers.
2. **Never build a metric for appearance.** Look, or ask someone to look.
3. **Assert against the path that breaks**, not the artefact you can reach.
3a. **Assert the property, not the number.** Two green tests that disagree are a finding.
3b. **One derivation.** Geometry and collision computed separately will drift. Delete the second.
3c. **Find the check for every guarantee a header makes.** If there isn't one, that is the next
    test. Run it over every fixture, not the one you are working on.
3d. **Grep for your subsystem's callers outside `tests/`.** If the only ones are test rigs, it is
    not delivered. Strip the input, re-measure, compare — if nothing changes, nothing works.
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
