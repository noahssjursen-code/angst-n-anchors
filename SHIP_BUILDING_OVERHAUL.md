# Ship Building Overhaul — Design Document

Audit and plan for the ship building system rework requested on
`feature/ship-building-overhaul`. Goal: clean up the shipwright +
ShipBuilder pipeline so commissioned ships are properly equipped (cargo,
lights, bollards) and visually pleasing (JSON-model superstructures
instead of primitive BoxMeshes).

This document is the spec for the work that follows on this branch.
Work proceeds in phases; each phase ships as its own commit so it can
be reverted independently.

---

## 1 — System overview as it stands

### 1.1 The pipeline

```
Shipwright NPC (catalog dialog)
   ↓ commits commission
JSON template written to user://shipwright_orders/<id>.json
   ↓
ShipBuilder.build(template_path) → BoatBody
   ↓
Scene tree, placed at berth
```

### 1.2 Key files

| File | Role |
| --- | --- |
| `scripts/npc/shipwright_npc.gd` | Hard-coded HULL_CATALOG, dialog UI, writes template JSON |
| `scripts/ship/ship_builder.gd` | Reads template, loads hull JSON, builds BoatBody with components |
| `scripts/ship/hull_stations.gd` | Strip-theory hull cross-sections derived from JSON verts |
| `scripts/ship/strip_buoyancy_component.gd` | Per-station Archimedes lift |
| `scripts/ship/hydrodynamics_component.gd` | Resistance, wave-making drag, wind drag |
| `scripts/ship/cargo_deck_component.gd` | Grid-based pallet storage, fully configurable size |
| `scripts/ship/ship_light.gd` | Single light fixture (6 types) with model + Light3D |
| `scripts/ship/ship_lighting.gd` | Group-discovers ShipLight nodes, preset cycle (OFF/NAV/WORK/ALL), auto-nav at night/fog |
| `scripts/port/mooring_point.gd` | Bollard — loads docking_bollard.json model, configurable scale/rotation |
| `resources/data/models/hulls/*.json` | 8 hulls + 2 orphans, each with a `slots` dict |
| `resources/data/models/superstructures/*.json` | 2 JSON bridge models, **currently unused** |
| `scenes/shared/superstructures/*.tscn` | 5 procedural BoxMesh bridges, **what ShipBuilder actually uses** |
| `resources/data/lights/*.json` | 5 light fixture models (port, stbd, masthead, stern, work) |
| `resources/data/meshes/docks/docking_bollard.json` | Mooring bollard model (also used by ports) |

### 1.3 Hull catalog (current state)

Eight catalog entries × hulls and their measurements at `scale = 1.0`:

| Hull file | Length | Beam | Height | Cargo slots | Has nav_light_bow? | In shipwright? |
| --- | ---:| ---:| ---:| --- | --- | --- |
| `hull_coastal_trader` | 13 m | 3.5 m | 1.3 m | `cargo_main` | ✅ | ✅ |
| `hull_coastal_trader_long` | 15 m | 3.5 m | 1.3 m | `cargo_main` | ✅ | ✅ |
| `hull_short_sea_coaster` | 22 m | 5.5 m | 2.0 m | `cargo_main` | ✅ | ✅ |
| `hull_short_sea_coaster_long` | 25 m | 5.5 m | 2.0 m | `cargo_main` | ✅ | ✅ |
| `hull_handysize_feeder` | 35 m | 8.0 m | 2.7 m | `cargo_main` | ✅ | ✅ |
| `hull_handysize_feeder_long` | 40 m | 8.0 m | 2.7 m | `cargo_main` | ✅ | ✅ |
| `hull_deep_sea_freighter` | 50 m | 11.0 m | 4.0 m | `cargo_main`, `cargo_aft` | ✅ | ✅ |
| `hull_deep_sea_freighter_long` | 60 m | 11.0 m | 4.0 m | `cargo_main`, `cargo_aft` | ✅ | ✅ |
| `hull_cargo_ship` | 20 m | 4.0 m | 2.0 m | `cargo_main`, `cargo_fwd` | ❌ | ❌ orphan |
| `hull_large` | 60 m | 10.0 m | 4.0 m | `cargo_main`, `cargo_aft` | ✅ | ❌ orphan |

### 1.4 What ShipBuilder currently attaches

For every commissioned ship:

- `BoatBody` (RigidBody3D, `auto_mass_from_hull` on, derives mass from `displacement_volume_m3 × ρ_water`)
- `ModelAssembler` for hull mesh (via scratch JSON written to `user://ship_builder_cache/`)
- `StripBuoyancyComponent` (with `HullStations`)
- `HydrodynamicsComponent` (with `HullStations`)
- `PropulsionComponent` (positioned at `propulsion` slot)
- `RudderComponent`
- `BowThrusterComponent` (positioned at `bow_thruster` slot)
- `BoatController` (input handler)
- `BoatCamera`
- `ShipGameplay` Node3D, with:
  - `Superstructure` (PackedScene instance from `scenes/shared/superstructures/*.tscn`)
  - `MooringComponent` (rope physics + cleats discovery)
  - 4 × `MooringPoint` at slots `mooring_{port,stbd}_{fwd,aft}`
  - `CargoDeckComponent` per name in `template.cargo_decks`

### 1.5 What ShipBuilder does **not** attach (gaps)

- **`ShipLighting` controller** — never added to the boat root. Even though some bridge scenes contain `ShipLight` nodes, nothing drives them. Lights stay off forever.
- **Hull-mounted lights** — slot `nav_light_bow` is defined in every hull JSON but never read. Lights only exist on bridges.
- **Stern light** — no slot, no scene-embedded fixture. The boat is missing the regulatory white stern light.
- **Work lights** — defined as `LightType.WORK` in `ship_light.gd` (deck floods) but no hull or bridge places any.
- **Cargo decks of correct size** — `CargoDeckComponent` defaults to 5×8 m / 1.5 m cells regardless of hull. A coastal trader (3.5 m beam) gets the same deck as a deep sea freighter (11 m beam).
- **Cargo decks at all on commissions** — shipwright's `_build_template()` returns `"cargo_decks": []`. **Every commissioned vessel has zero cargo capacity.**

### 1.6 Visual quality gaps

- Bridge `.tscn` files are 5 procedural `BoxMesh` primitives stacked. A coastal trader bridge is literally a 2.2×2.3×1.8 m white cube with two 0.4-thick wing strips and a tiny stack box.
- No funnel beyond a 0.45×0.85×0.35 black box.
- No masts, antennas, mast lights, lifebuoys, railings, ladders, or any other vessel detail.
- The JSON bridges `bridge_medium.json` / `bridge_small.json` exist (visually nicer — house + deck + windows + funnel) but are unreferenced.

### 1.7 Mooring bollards

`MooringPoint` already does the right thing on its own:

- Loads `docking_bollard.json` via `ModelAssembler` so the player sees an actual bollard
- Exposes `bollard_scale`, `bollard_rotation_degrees`, `anchor_local_position` properties
- Default rotation `(0, 90, 0)` aligns the bollard along the ship's centerline

Problems:

- **Scale is always 1.0.** A bollard sized for a 13 m coastal trader looks toy-like on a 60 m freighter and oversized on a launch.
- **Y position taken from hull JSON slots** — but those Y values were authored assuming a flat deck at Y=1.0. Bigger hulls have deck at Y=1.5 (cargo ship) or Y=3.0 (freighter). Bollards on big ships sit below the deck.
- **No visual placement guide.** Bollards are placed at the hull slot center; the actual lining-up of the line to the cleat happens through `anchor_local_position = (0, 0.52, 0)`. Hardcoded.

---

## 2 — Required outcomes

Direct from the brief, with my interpretation:

1. **Use hull sizes as measurements.** Derive component sizing (cargo deck dimensions, bollard scale, camera distance, propulsion thrust) from `HullStations.length_m`/`beam_m`/`height_m` rather than hand-tuned per catalog entry.
2. **Cargo decks of multiple sizes.** Per-ship JSON declares one or more cargo decks with explicit `width`/`length`/`cell_size`/`position`. Hulls already have multiple cargo slots — feed real dimensions into the `CargoDeckComponent`.
3. **Superstructures visually nice (JSON models).** Migrate the procedural `BoxMesh` `.tscn` superstructures to `ModelAssembler`-driven JSON with detail parts (bridge house, deck, windows, funnel, mast, antennas, railings). ShipBuilder loads them via JSON path, not PackedScene path.
4. **Lighting and beacons.** Every commissioned vessel gets the correct nav-light suite (port, starboard, masthead, stern), optional work lights, and an active `ShipLighting` controller. Auto-nav at night and in fog.
5. **Proper placement of mooring bollards on ships.** Bollards positioned at the **deck level** of the specific hull, scaled to the hull size, and laid out so the four cardinal points are unambiguously inside the dock's mooring tolerance.

---

## 3 — Target architecture

### 3.1 Hull JSON: expanded schema

Add three sibling sections to every hull JSON:

```jsonc
{
  "name": "hull_coastal_trader",
  "parts": [ /* unchanged: mesh parts with collision/visual/role */ ],

  // existing — basic positional anchors (Vector3 at scale 1.0)
  "slots": {
    "bridge":        [0, 1.2, -4.5],
    "propulsion":    [0, -0.3, -6.2],
    "bow_thruster": [0, -0.3,  6.2]
  },

  // NEW — cargo decks with explicit dimensions
  "cargo_decks": [
    {
      "name":         "main",
      "position":     [0, 1.05, 0],
      "deck_width":   2.8,
      "deck_length":  6.5,
      "cell_size":    1.0
    }
  ],

  // NEW — bollard placement with per-bollard scale
  "bollards": {
    "port_fwd":  {"position": [-1.55, 1.0,  5.5], "scale": 0.6},
    "stbd_fwd":  {"position": [ 1.55, 1.0,  5.5], "scale": 0.6},
    "port_aft":  {"position": [-1.55, 1.0, -5.5], "scale": 0.6},
    "stbd_aft":  {"position": [ 1.55, 1.0, -5.5], "scale": 0.6}
  },

  // NEW — light fixtures
  "lights": [
    {"type": "nav_port",     "position": [-1.55, 1.2,  5.5]},
    {"type": "nav_starboard","position": [ 1.55, 1.2,  5.5]},
    {"type": "nav_masthead", "position": [ 0.0,  4.5,  3.0]},
    {"type": "nav_stern",    "position": [ 0.0,  1.5, -6.4]},
    {"type": "work",         "position": [ 0.0,  3.0,  0.0]}
  ]
}
```

`ShipBuilder` reads these and instantiates the right component nodes
with the right parameters. The hull JSON becomes the single source of
truth for ship dimensions.

### 3.2 Superstructure JSON: detailed multi-part models

Replace the 5 procedural `.tscn` files with 5 JSON model files at
`resources/data/models/superstructures/<name>.json`. Each contains:

```jsonc
{
  "name": "bridge_coastal_trader",
  "parts": [
    {"name": "deck_house",    /* boxy house */},
    {"name": "bridge_windows",/* dark glass strip */},
    {"name": "wing_port",     /* outrigger walkways */},
    {"name": "wing_starboard"},
    {"name": "roof",          /* overhang */},
    {"name": "funnel",        /* exhaust stack */},
    {"name": "mast",          /* signal mast */},
    {"name": "antenna_array", /* radar/comms */},
    {"name": "rail_fwd",      /* safety rail */},
    {"name": "rail_aft"},
    {"name": "ladder_port",   /* deck-to-roof access */}
  ],
  "slots": {
    "bridge_entry":   [0,    1.15, -1.4],
    "light_masthead": [0,    3.6,   0.5],
    "light_window":   [0,    1.8,   1.0]
  }
}
```

`ShipBuilder` instantiates via `ModelAssembler`. The `slots` dict on the
superstructure JSON tells ShipBuilder where to attach interactables
(BridgeInteractable, captain's chair, ShipLight nodes etc.) inside the
bridge.

### 3.3 ShipBuilder additions

Three new private functions:

```gdscript
static func _add_cargo_decks(parent: Node3D, hull_data: Dictionary, scale: float) -> void:
    # Read hull_data.cargo_decks (each: position, deck_width, deck_length, cell_size)
    # Create one CargoDeckComponent per entry at the right scale.
    # Honours optional template overrides for cells_x/cells_z if specified.

static func _add_lights(parent: Node3D, hull_data: Dictionary, scale: float) -> void:
    # Read hull_data.lights, create ShipLight nodes by type and position.
    # Also reads superstructure's own light slots for masthead/window.

static func _add_lighting_controller(boat: BoatBody) -> void:
    # One ShipLighting node attached to boat root.
    # _gather_lights() scans group "ship_light" for all descendants.
```

`build()` orchestration becomes:

```gdscript
boat.add_child(_make_strip_buoyancy(...))
boat.add_child(_make_hydrodynamics(...))
boat.add_child(_make_propulsion(...))
boat.add_child(_make_rudder(...))
boat.add_child(_make_bow_thruster(...))
boat.add_child(_make_controller())
boat.add_child(_make_camera(...))
boat.add_child(_make_lighting_controller())   # NEW

var gameplay := Node3D.new() ; gameplay.name = "ShipGameplay"
boat.add_child(gameplay)

# Superstructure: now JSON-driven via ModelAssembler
_add_superstructure(gameplay, tmpl, slots)

gameplay.add_child(MooringComponent.new())
_add_mooring_bollards(gameplay, hull_data, scale)        # was _add_mooring_points
_add_cargo_decks(gameplay, hull_data, tmpl, scale)        # NEW
_add_hull_lights(gameplay, hull_data, scale)              # NEW
```

### 3.4 Shipwright catalog: derive thrust from hull

Right now every catalog entry hardcodes `propulsion_thrust`,
`bow_thrust`, `cam_dist`, `cam_height`. With `HullStations`
computing `length_m`/`beam_m`/`displacement_volume_m3` automatically,
those can be derived:

```gdscript
# Rough target: 0.15 m/s² steady-state acceleration at design displacement.
# F = m × a. m = displacement_volume × ρ_water.
var displacement_kg := stations.displacement_volume_m3 * 1025.0
var propulsion_thrust := displacement_kg * 0.15
var bow_thrust := propulsion_thrust * 0.18

# Camera scales with hull length.
var cam_dist   := stations.length_m * 1.4 + 12.0
var cam_height := stations.length_m * 0.35 + 4.0
```

That collapses 9 fields per catalog entry to 3 (`id`, `display`,
`hull_file`, `superstructure`) plus optional overrides. Adding a new
hull is then a one-line entry.

### 3.5 Bollard placement rules

Bollard placement is currently a hull JSON slot Vector3 + a default
scale and rotation. Three improvements:

1. **Scale derived from hull size.** A bollard's visible bulk should be
   `~0.5 m` cube for a 13 m coastal trader, `~1.0 m` cube for a 60 m
   freighter. Linear-interpolate over hull length:
   `scale = 0.4 + 0.6 × clamp((length - 13) / 47, 0, 1)`.
2. **Y position derived from deck top.** Hull JSON declares `deck_y`
   per hull (or HullStations computes it). Bollards sit at `deck_y +
   ε`. Removes the bollard-below-deck bug on tall hulls.
3. **X position derived from hull beam at station.** Bollards sit at
   `±(half_beam_at_z - inset)` where `inset = 0.4` m. Authoring no
   longer has to guess the right X for each hull.

The hull JSON's `bollards` block then becomes minimal:

```jsonc
"bollards": {
  "port_fwd":  {"station": "fwd"},
  "stbd_fwd":  {"station": "fwd"},
  "port_aft":  {"station": "aft"},
  "stbd_aft":  {"station": "aft"}
}
```

Station-to-Z mapping: `fwd` = 75 % of `length_m` toward bow, `aft` =
75 % toward stern. Computed by `HullStations`.

### 3.6 Light suite per hull

Every vessel gets:

- 1 × NAV_PORT (red) — fwd port, on the bridge wing or hull bow
- 1 × NAV_STARBOARD (green) — fwd stbd, symmetric to port
- 1 × NAV_MASTHEAD (white, forward arc) — on the mast at superstructure top
- 1 × NAV_STERN (white) — aft, low on transom
- 1 × WINDOW (warm amber) — inside the wheelhouse
- Optional WORK lights — deck floods, scaled to hull size:
  - Coastal trader: 1
  - Short sea coaster: 2
  - Handysize feeder: 3
  - Deep sea freighter: 4

Positions split between the hull JSON (port, starboard, stern, work)
and the superstructure JSON (masthead, window) since the latter pair
moves with the bridge.

### 3.7 Multi-size cargo decks

`CargoDeckComponent` already supports `deck_width_m`, `deck_length_m`,
`cell_size_x_m`, `cell_size_z_m`, `max_cells_override`. The work is
purely plumbing: read the hull JSON `cargo_decks` array, instantiate
one component per entry with the right dimensions.

Hull-by-hull plan (m, at scale 1.0):

| Hull | Deck | Width | Length | Cells (x×z) | Position |
| --- | --- | ---:| ---:| --- | --- |
| coastal_trader | main | 2.8 | 6.5 | 2×4 | (0, 1.05, 0) |
| coastal_trader_long | main | 2.8 | 8.0 | 2×5 | (0, 1.05, 0) |
| short_sea_coaster | main | 4.4 | 12.0 | 3×8 | (0, 1.55, 0) |
| short_sea_coaster_long | main | 4.4 | 14.5 | 3×10 | (0, 1.55, 0) |
| handysize_feeder | main | 6.4 | 22.0 | 4×15 | (0, 2.05, 0) |
| handysize_feeder_long | main | 6.4 | 26.0 | 4×17 | (0, 2.05, 0) |
| deep_sea_freighter | main | 8.8 | 22.0 | 6×15 | (0, 3.05, 5) |
| deep_sea_freighter | aft  | 8.8 | 18.0 | 6×12 | (0, 3.05, -10) |
| deep_sea_freighter_long | main | 8.8 | 26.0 | 6×17 | (0, 3.05, 6) |
| deep_sea_freighter_long | aft  | 8.8 | 22.0 | 6×15 | (0, 3.05, -10) |

Numbers reflect ~80 % of hull beam (leaving room for railings and a
walkway) and split the length so the bridge stands at the aft end and
the cargo block fills the rest.

---

## 4 — Implementation phases

Each phase is a single commit. Ordered so the gameplay-critical fixes
(cargo, lights) ship first, then visuals.

### Phase 0 — this doc (committed)

Already on this branch (`SHIP_BUILDING_OVERHAUL.md`). No code changes.

### Phase 1 — wire up `ShipLighting` and hull lights

Smallest-impact gameplay fix. Adds the missing lighting controller and
spawns light fixtures off the hull JSON.

- Extend hull JSONs with a `lights` array per §3.1 (initially based on
  the existing `nav_light_bow` slot + sensible derived positions).
- `ShipBuilder._add_hull_lights()`.
- `ShipBuilder._add_lighting_controller()`.

After this commit: pressing L cycles light presets, ships glow at
night, auto-nav engages in fog.

### Phase 2 — populate cargo decks at proper sizes

Restores cargo capability to commissioned ships.

- Extend hull JSONs with a `cargo_decks` array per §3.1 and the table
  in §3.7.
- `ShipBuilder._add_cargo_decks()` reads it and instantiates
  `CargoDeckComponent` per entry, with correct sizing.
- Shipwright's `_build_template()` no longer needs to set `cargo_decks`
  — the hull defines them.

After this commit: every commissioned vessel has cargo capacity scaled
to its hull.

### Phase 3 — bollard placement and scale

- Add per-hull bollard Y from deck height and X from beam half-width
  (auto-derivation in ShipBuilder).
- Pass `bollard_scale` to `MooringPoint` based on hull length.
- Optionally use the hull JSON's `bollards.<key>.scale` override.

After this commit: bollards sit cleanly on the deck, sized for the
hull.

### Phase 4 — JSON superstructures

- Author 5 new superstructure JSONs at
  `resources/data/models/superstructures/bridge_*.json` with deck
  house, deck, windows, funnel, mast, antennas, railings, ladders.
- `ShipBuilder._add_superstructure()` switches to `ModelAssembler`
  instead of `PackedScene` instantiation.
- Bridge JSONs carry their own light slot positions for masthead +
  window lights (`§3.6`).
- Delete the obsolete `scenes/shared/superstructures/*.tscn`.

After this commit: bridges look like ships, not boxes.

### Phase 5 — hull-derived shipwright catalog

- `HullStations` exposes `displacement_volume_m3` (already there) and
  computed `length_m`.
- Shipwright catalog entries drop `propulsion_thrust`, `bow_thrust`,
  `cam_dist`, `cam_height`. Default formulas in `_build_template()`.
- Add the missing catalog entries (`hull_cargo_ship`, `hull_large`).

After this commit: shipwright is data-driven; adding a hull is a
one-liner.

### Phase 6 — fold up cleanup

- Remove `SHIPS_BASE_DIR` / `resources/data/ships/` references from
  `ShipBuilder` (the directory doesn't exist).
- Audit `resources/data/models/ships/fuel_tanker.json` — vestigial?
- Update `AGENTS.md` ship-building section to match new format.

---

## 5 — Open design questions left for later

- **Crane attachment.** Cranes currently live on the dock, not the ship.
  Whether a ship can mount its own cargo crane (and how that interacts
  with cargo deck reach) is out of scope here.
- **Customisable bridge per hull.** Right now a "bridge_coastal_trader"
  always pairs with a coastal trader hull. Whether the player should be
  able to pick a different bridge or specify funnel colour at
  commission time is for a later pass.
- **Hull damage / repair visualisation.** Out of scope. `ShipData` has
  `hull_health` but nothing visualises it.
- **Multiple cargo deck cell sizes per deck (mixed pallets).**
  `CargoDeckComponent` already supports a fixed cell size per deck. If
  a single deck wanting mixed pallet sizes becomes necessary, that's a
  separate refactor.

---

## 6 — Files I will touch

```
scripts/ship/ship_builder.gd                                — rewrite orchestration
scripts/npc/shipwright_npc.gd                               — catalog cleanup + derive params
resources/data/models/hulls/*.json                          — add lights/cargo_decks/bollards
resources/data/models/superstructures/bridge_*.json         — author 5 new files
scenes/shared/superstructures/*.tscn                        — delete after Phase 4
scripts/ship/cargo_deck_component.gd                        — minor: accept hull-derived size hints
AGENTS.md                                                    — sync docs after Phase 6
```

The 749-line `mooring_component.gd` and the strip-theory hydro stack
stay untouched — they're working and not part of the brief.

---

## 7 — Status log

Will be updated as phases land.

- **Phase 0 — design doc (this file)** — drafting

---

*Document lives on `feature/ship-building-overhaul`. Will be merged
with the implementation as Phase 0.*
