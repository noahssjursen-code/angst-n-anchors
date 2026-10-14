# Coastal gull workshop

Run `res://scenes/showcases/gull_showcase.tscn` with F6. For command-line runs,
append `-- --shipyard-playtest` to isolate existing captain saves.

The workshop contains flight, glide, folded-wing, boids, floating, landing-cycle
and flock-water-break views. Water views render the actual FFT ocean. Drag the empty
view to orbit, scroll to zoom, and press Space to pause. Sliders control age,
size, wingbeat frequency, flock count, per-bird variation, separation, cohesion
and alignment. Water controls adjust rest duration in minutes and wave strength; the
landing button restarts an approach or triggers takeoff from rest. Appearance changes preserve the flock's positions. Changing the
count or seed creates a new flock. Maximum count is 64.

## Model and age

The original Blender source is `resources/models/_source/wildlife/coastal_gull.blend`.
It includes editable wing pivots and a flight timeline. `tools/build_coastal_gull.py`
rebuilds the GLB, adult/juvenile atlases, source and archived review renders. The
GLB has shared geometry split by articulation; Godot drives its wings directly
so each bird can have a different phase and blend between flapping and gliding.
Folded plumage is a separate mesh on the same bird. Water landing flares the
wings, extends the feet, then folds the wings and tucks the feet while floating.

Visual reference: European herring gull, especially the long swept flight
silhouette, grey mantle, pale body, yellow bill, black primaries and white
primary markings. References consulted:

- [BTO: Herring Gull](https://www.bto.org/learn/about-birds/birdfacts/herring-gull)
- [Waterbird Monitoring: flight photograph](https://waterbirdmonitoring.info/species/68-racek-stribrity/)
- [Gull Research: immature plumage](https://gull-research.org/hg/HG2CY07.htm)

Age is a visual approximation blending fledged juvenile plumage into adult
plumage by four years. It does not model individual moult seasons. The minimum
age is six months; this is not a chick model. Size is independent of age.

## Data and future behaviour

- `GullProfile`: stable bird ID, species, age, size, cruise speed, wingbeat rate,
  and phase. Supports JSON-safe records.
- `GullFlockSimulation`: fixed 30 Hz data-only local-space boids. A spatial grid
  limits neighbour queries. Separation, alignment, cohesion, a broad circling
  tendency and an altitude floor steer the flock.
- `CoastalGull`: appearance and pose only; shared mesh/material, per-instance age.
- `GullWaterBehaviour`: serializable descent, resting and takeoff state.
- `GullFlock`: interpolates the simulation into visible birds and samples
  `WaveSurface` for floating height and damped pitch/roll.

`set_goal(bird_id, local_target)` and `clear_goal(bird_id)` are the first decision
seam. Future feeding, avoidance and perching can issue goals and extend
the behaviour state without replacing appearance or flock simulation.

Snapshots contain profiles, position, velocity, active goals, simulation time
and tuning, including an active water-landing/rest/takeoff cycle. Wave physics
are not saved in bird records. Restore starts from a simulation tick boundary; presentation
interpolation is deliberately not persistent state. This is tested locally,
not a claim of cross-platform bit-identical floating-point results.

The original workshop remains isolated. Normal gameplay now installs
`CoastalBirdWorld` after geography and harbour exclusion zones are available.
Autonomous feeding/perching and any wildlife impact on fishing/economy remain
unimplemented; tern foraging is visual only.

Validation: `tests/gull_flock_test.gd` covers seeded identity, frame-rate
independence, finite/bounded flight, JSON reconstruction and continuation,
goal persistence, rejection without mutation, appearance parameters and poses.

## Water behaviour

Set `GullFlock.water_rest_enabled` to opt into staggered water breaks. Individual
birds descend to mean sea level, flare, fold their wings, drift gently while
resting, then take off and rejoin the flock. `rest_duration_seconds` defaults to
240 seconds, varied by 20% per bird; `flight_duration_seconds` defaults to 180
seconds before considering another landing. Resting birds do not pull airborne boids
below their flight altitude.

The presentation reads the same `WaveSurface.sample_at` API as vessel buoyancy.
Heave follows the sampled height directly; pitch/roll is damped and limited on
steep crests. This is lightweight surface following, not a rigid-body bird.
`water_sample_provider` allows an alternate sampler; `can_land_provider` allows
a habitat system to reject land/obstacles. Until connected to the world, water
breaks must only be enabled over known open water. Landings currently do not
avoid terrain and do not create splash/ripple effects.

Most resting time is quiet. A deterministic schedule from each bird's `idle_seed`
and resting elapsed time inserts occasional wing stretches, neck lifts and looks
to either side. The Blender source and GLB contain a separate `WaterRest` morph
with an upright neck and level bill. `NeckLift`, `LookLeft`, and `LookRight` add
movement on top of that resting posture; body wave following stays independent. Wing
stretches do not use the flight flap cycle or change the resting state. The
dedicated floating view rests indefinitely, until the takeoff/startle button.

`react_to_vessel(position, velocity, hull_radius, clearance)` is a data-only
authority hook. It interrupts rest or landing if the hull is too close or will
approach within the next two seconds, turns away from its path and initiates
takeoff. Distant departing vessels do not disturb birds. There is no automatic
world-vessel query yet: call from local authority, or apply a server-approved
disturbance/checkpoint. Receiving clients must not choose their own scare events.
The workshop's startle button exercises the same proximity decision.

Run `tests/gull_water_test.tscn -- --shipyard-playtest` to check the complete
cycle, JSON continuation, invalid-record rejection, world-space surface height,
wave tilt, folded wings and tucked feet. The dedicated scene is needed so the
ocean's authority/clock autoloads exist before the test script loads.

Start the workshop with `-- --gull-water` to open the water cycle directly.
`--capture-gull-water` saves real engine review captures to the machine screenshot
archive. The workshop scene is automatically isolated from captain saves on F6.

## Individual gull calls

`GullCallAudio` attaches a mono spatial source to each bird's head. Twelve
ElevenLabs-generated clips cover four contact calls, three long calls, three quiet
resting calls and two alarm calls. They are packaged WAV assets; the game does not
call ElevenLabs or need an API key. Prompts, receipts and signal measurements are
in `resources/audio/wildlife/gulls/generation.json`; the reusable generation tool
reads credentials only from the environment or stdin.

Call timing and variations derive from bird identity and simulation time. Age and
size introduce small pitch differences. Resting birds mostly use quiet calls;
startled takeoffs use alarm calls. Calls pan with their world position, attenuate
with distance (8 m unit distance, 140 m cutoff), and use the existing obstruction
system. A broad forward emission cone slightly softens calls heard from behind.
At most eight sources play simultaneously; hidden, out-of-range or muted birds
stop playback. These audio limits do not alter flock behaviour.

The workshop includes a spatial-audio toggle and **Hear next call**, which cycles
through all twelve clips. In flock modes it auditions successive birds. Pausing
also stops calls. `--gull-water` auditions a call after opening the floating view.

`tests/gull_audio_test.tscn -- --shipyard-playtest` checks mono assets, repeatable
schedules after JSON reconstruction, source attachment, mute, range and voice
limits. It measures the actual stereo mix to check left/right positioning and
distance falloff.

## Gameplay and multiplayer (version 1)

Normal `World` creates `CoastalBirdWorld` after terrain/harbour planning. Habitat
cells are 256 m across, with stable IDs and seeds derived from the world seed.
Only clear coastal water 100-650 m offshore is eligible; the flight envelope is
checked against terrain/skerries and harbour/settlement exclusion bounds.
No terrain sampling or flock construction is added to the server.

Herring gulls fly, descend, rest for several minutes and take off. White-tailed
eagles are uncommon single birds with broad high wandering routes. Arctic terns use faster
low flight, pauses and plunge/climb sequences. Each has a separate original
Blender model and editable wing animation. These are initial game representations,
not complete ecology: no nests, ground perching, seasonal migrations or predation.
Eagles and terns are currently silent rather than reusing gull calls.

For the shared world, `CoastalBirdMotion` evaluates bounded tracks directly from
identity and shared time. This deliberately differs from the workshop's free
boids: it has no accumulating integration error, no late-join catch-up simulation,
and no per-bird transform packets. Future autonomous boids need authority
checkpoints before replacing these tracks. Stable identity, shared timing and
versioned events already have that separation from presentation.

The MP server generates a cell disturbance from an accepted ship publication
within 100 m of the cell centre. It holds the flock airborne until 60 seconds
after the last nearby vessel update. Clients blend takeoff/return over shared
start/end timestamps; their own visible vessels never choose MP scare events.
`GET /v2/wildlife` requires an authority session and returns only disturbances
within 1.4 km of that actor's published observer. At most one request is pending;
nearby state is polled every 0.5 seconds. Empty responses contain no bird records.
The endpoint is read-only and cannot be used to inject client-authored scares.
Single-player uses the same cell/range/hold rules with actual BoatBody nodes.

The matching server change lives on `feature/coastal-birds` in the adjacent MP
repository. Servers without the endpoint show no wildlife (one warning), rather
than falsely presenting independently startled birds as synchronized. This pass
does not deploy the public DigitalOcean server. Disturbances are transient like
ship presence; normal movement reconstructs after a server restart.

Detailed animated birds appear within 180 m (230 m exit hysteresis). Farther away,
shared simplified meshes are instanced in a MultiMesh per pose per flock. Groups unload
at 1.1 km; up to eight nearest groups render, with a bounded habitat cache. Wave
heave, plumage, wing animation and directional calls remain local presentation.
Distant gulls switch between flying and folded-wing resting silhouettes, with
the raised resting neck baked into the water model. Exact near poses resume on approach.

Gull beaks now use a Blender `Call` morph driven by the actual generated clip's
50 Hz amplitude envelope, so silences close the lower bill. Regenerating clips
also rebuilds `envelopes.json` without any runtime API use.

### Review scenes and verification

- `scenes/showcases/coastal_birds_showcase.tscn`: true-size model comparison;
  drag to orbit, wheel to zoom, Space switches flap/glide.
- `scenes/showcases/coastal_birds_world_showcase.tscn`: gameplay streaming component
  against real seeded geography, terrain and production ocean. Space simulates
  a nearby vessel through the same local-authority proximity rule.
- `tests/coastal_birds_test.tscn`: complete motion cycles, finite positions,
  JSON late-join reconstruction, imported detailed/far models, LOD unloading,
  actual seeded coastline habitat and streamer bounds.
- MP `internal/world/wildlife_test.go` and HTTP endpoint test: two observers see
  identical disturbances, distant observers are filtered, negative coordinates,
  expiry, vessel-only input, stale packet rejection and authenticated reads.

All Godot command-line tests should include `-- --shipyard-playtest`.
Machine review captures go to `C:/Users/noahs/Pictures/machinescreenshots`.

Species references used for the new authored silhouettes:
- [RSPB: white-tailed eagle](https://www.rspb.org.uk/birds-and-wildlife/white-tailed-eagle)
- [BTO: arctic tern](https://www.bto.org/learn/about-birds/birdfacts/arctic-tern)
- [Cornell Lab: arctic tern identification](https://www.allaboutbirds.org/guide/Arctic_Tern/id)

### Natural flock motion revision

World birds follow seeded, non-looping cubic spline routes with a shared flock
route and individual deviations. Every flock varies its pace and spread; every
gull has its own 90-240 second flight and 240-660 second rest durations, phase,
and 7-12 second transitions. Terns have independent 43-113 second dive intervals.
Water positions are irregular loose patches with rejection-sampled personal
space, slow drift, independent headings and small changes between visits.
Ship scares retain the server event but stagger individual reactions by up to
1.4 seconds. This remains deterministic ambient motion, not reactive free boids;
it can be reconstructed from identity and time without per-bird replication.

### Vessel interest

Up to six gulls per nearby flock approach vessels within 260 m of their habitat.
Over twelve seconds they blend into loose circling passes 18-32 m around a stopped
boat, 8-15 m above mean water. Moving vessels draw them astern instead. Birds return
to their habitat when the vessel leaves the area; this is bounded coastal interest,
not a flock following a ship across the whole ocean. No deck perching or explicit
fishing/bait signal yet. Vessel observations come from the authenticated wildlife
endpoint in MP (12-second expiry), or actual local vessel bodies in singleplayer.
Transient approach smoothing is client presentation; shared boat observations and
seeded paths govern the target. Exact per-frame trajectories are not lockstep.
Eagle habitat chance is now 12%, and streaming reserves space for available eagle
and tern groups instead of allowing nearest gull patches to crowd them out.
Swallows are not implemented; arctic terns are a separate species.

### Actual-vessel reaction fix

BoatBody registers in `_enter_tree`, because catalog/trawler/catamaran subclasses
replace `_ready`. Tests now instantiate a real VesselSpawn hull and verify the
production sensor detects it, rather than manually assigning a dummy node group.
Scene-visible boats (including network replicas) supply proximity observations in
both authority modes; optional HTTP boat records are a fallback. Player bodies
also trigger close-range flight. Speed is measured from observed motion, including
kinematic replicas. Curiosity now approaches over five seconds with lower passes.
Per-bird presented positions and 1.5-second vessel approach predictions trigger
escape, overriding attraction. Moving boats scare within 18 m, stationary boats
within 7 m and people within 3.5 m; these are centre distances, not hull bounds.
Reaction blend/escape history is client presentation and is not exact lockstep
across clients. No per-bird network traffic is introduced.

Boat-interest approach now integrates velocity with a 3 m/s² acceleration limit,
5.5-8 m/s cruise target and bounded vertical speed. Birds pursue a point ahead
of their circuit rather than crossfading between unrelated positions. Regression
checks cover thirty seconds of approach displacement, acceleration and convergence.
