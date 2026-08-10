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
- **Hand-authored plate deckhouses.** Correct geometry, wrong authoring layer. Being rebuilt from
  a piece kit.

Each of these was working, tested and green when it was torn out. **Green is not evidence that a
thing is right — only that it does what it says.** Whether it should exist at all is a question
no test asks.
