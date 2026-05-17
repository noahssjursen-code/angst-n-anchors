# Ship Building System

## How it works

Ships are built from three layers of JSON:

1. **Hull JSON** (`resources/data/models/hulls/*.json`) — mesh geometry, materials, collision. Also carries a `"slots"` section with named attachment points at scale=1.
2. **Ship model JSON** (`resources/data/models/ships/*.json`) — references a hull, applies scale. Used by `BoatBody.model_data_path` for existing .tscn scenes.
3. **Ship template JSON** (`resources/data/ships/*.json`) — full ship definition: hull, scale, physics, component tuning. Consumed by `ShipBuilder` to assemble a complete playable ship at runtime.

### Making a new ship

1. Pick a hull from `resources/data/models/hulls/`. All hulls expose slots.
2. Create `resources/data/ships/my_ship.json` using the template format (copy `fuel_tanker.json` as a base).
3. In code: `var boat := ShipBuilder.build("res://resources/data/ships/my_ship.json")`
4. Add the returned node to the scene and call `place_at_waterline(water_y)`.

No scene editor needed. No 180° rotation hacks. No manual mooring point placement.

### Hull orientation convention

**Bow = +Z, Stern = −Z, Port = −X, Starboard = +X.**

Hull mesh vertices are authored with the long axis along the mesh-local X axis (bow at +X). A `rotation_degrees: [0, -90, 0]` in each part bakes this into the correct world orientation at load time.

Do not add extra rotation to ship model JSONs. Do not flip hulls in scene files. If the bow visually appears at the wrong end, check that all hull parts use `[0, -90, 0]` and that no outer ModelAssembler node has a Y rotation set.

### Controls

`BoatController` uses a stage table where positive values = ahead intent. It sends the **negated** value to `PropulsionComponent` because propulsion treats negative throttle as ahead thrust (force in +body.z = toward bow). This is an established internal convention — do not remove the negation.

---

## Slots

Each hull JSON has a `"slots"` dictionary at the end. Positions are at **scale = 1**. `ShipBuilder` multiplies by the template `"scale"` field.

| Slot name | Purpose |
|---|---|
| `bridge` | Superstructure / bridge scene origin |
| `propulsion` | Propeller position (stern, below waterline) |
| `bow_thruster` | Bow tunnel thruster (bow, below waterline) |
| `mooring_port_fwd` | Port mooring point, forward (bow side) |
| `mooring_stbd_fwd` | Starboard mooring point, forward |
| `mooring_port_aft` | Port mooring point, aft (stern side) |
| `mooring_stbd_aft` | Starboard mooring point, aft |
| `cargo_main` | Primary cargo deck origin |
| `cargo_aft` | Secondary aft cargo deck (large hulls only) |
| `nav_light_bow` | Bow navigation light mast |

---

## Stupid things found and fixed

### 1. Triple-layered orientation hack

Hull meshes have vertices along the X axis (bow at +X). A `[0, 90, 0]` rotation was applied to each mesh part, which put the bow in the **−Z** direction. To make it visible from the "right" side, every ship model JSON applied a second `[0, 180, 0]` rotation, flipping the whole hull so the bow landed at **+Z**. Then `BoatController` negated the throttle because someone documented this as "bow at +Z so we invert."

The controls were backwards on every new ship that didn't have the 180° flip because the flip and the controller negation cancelled each other out — remove either one and it breaks.

**Fix:** Changed all hull part rotations from `[0, 90, 0]` to `[0, -90, 0]`. The bow now lands at +Z directly. Removed the `[0, 180, 0]` from `fuel_tanker.json`. The controller negation stays (it's the correct behaviour for the stage table convention).

### 2. Crab mode pushed the wrong direction

`BowThrusterComponent` crab mode negated `lateral_input` with the comment: *"Negate: hull body is authored rotated 180° Y so basis.x points to port."* The `RigidBody3D` body has no rotation — `basis.x` is always world +X regardless of what the mesh looks like. The negation made crab mode push port when you commanded starboard and vice versa.

**Fix:** Removed the negation.

### 3. Mooring point bow/stern labels were swapped in fuel_tanker.tscn

`MooringPoint_PortBow` was placed at Z=−10 (the aft/stern end of the ship). `MooringPoint_PortStern` was at Z=+10 (the forward/bow end). Functionally harmless but deeply confusing.

**Not changed** in the existing .tscn (no reason to break a working scene). New ships from `ShipBuilder` use the correct `fwd`/`aft` naming from hull slots.

### 4. PropulsionComponent default stern_offset was at the bow

Default `stern_offset = Vector3(0, 0, 5.8)` placed the propeller at +Z which is the **bow** end in the corrected orientation.

**Fix:** Changed default to `Vector3(0, 0, -5.8)` (stern = −Z).

### 5. BowThrusterComponent default offsets were also swapped

`bow_offset` default pointed toward −Z (stern), `stern_offset` pointed toward +Z (bow).

**Fix:** Swapped both defaults to match the corrected orientation convention.

### 6. RudderComponent comment said "positive = moving ahead"

`fwd_speed = -velocity.dot(basis.z)` produces a **negative** value when the ship moves forward (+Z direction). The comment was wrong. The variable is actually "astern speed" semantically (positive = moving astern). The direction flip for reverse steering is correct maritime behaviour.

**Fix:** Replaced the comment with an accurate description.

### 7. Everything is manual with no pipeline

No new ship could be created without: writing a hull JSON, writing a ship model JSON, opening Godot's scene editor, placing all components, tuning physics by trial and error, manually positioning bridge, mooring points, and lights.

**Fix:** `ShipBuilder` + ship template JSONs. Slots in hull JSONs drive automatic placement.

---

## Available hulls

| Hull | Length (unscaled) | Beam | Ship class |
|---|---|---|---|
| hull_coastal_trader | 13 m | 3.5 m | Coastal Trader |
| hull_coastal_trader_long | 15 m | 3.5 m | Coastal Trader |
| hull_short_sea_coaster | 22 m | 5.5 m | Short Sea Coaster |
| hull_short_sea_coaster_long | 25 m | 5.5 m | Short Sea Coaster |
| hull_handysize_feeder | 35 m | 8 m | Handysize Feeder |
| hull_handysize_feeder_long | 40 m | 8 m | Handysize Feeder |
| hull_deep_sea_freighter | 50 m | 11 m | Deep Sea Freighter |
| hull_deep_sea_freighter_long | 60 m | 11 m | Deep Sea Freighter |
| hull_large | 60 m | 10 m | (large variant) |

Scale in the template multiplies all hull dimensions and all slot positions.
