# Systems Inventory & Folder Structure — Audit

Status: audit + proposal. Nothing renamed or moved yet.

Two questions answered:
1. **What systems do we have today, and what will we need?** (Inventory)
2. **How should the folders and services be organised to keep them sane?** (Proposal)

---

## Part 1 — Current Systems (what exists today)

A "system" here = a coherent area of responsibility, not a single file. Counted: **18 distinct systems** spread across the codebase.

| # | System | Where it lives today | What it owns |
|---|---|---|---|
| 1 | Game state (read model) | `scripts/state/` + `GameState` autoload | Player/ship/contract/world sub-states; UI subscribes here |
| 2 | Player (character) | `scripts/entities/player.gd` + `scripts/player/` + `PlayerSession` autoload | Movement, camera, jump, water rescue, persistence, marks |
| 3 | World generation & loading | `scripts/world/` (world.gd, proximity_loader, world_renderer, atmospheric_effects, island_mesh_builder, palette) | Seeded port definitions, proximity-based loading, sky/atmosphere |
| 4 | Time / clock | `WorldClock` autoload | Game time |
| 5 | Weather | `scripts/systems/weather/` + `WorldWeather` & `WeatherLighting` autoloads + `scripts/ui/weather_debug_presets.gd` | Wind, rain, fog, lighting reactions, weather zones |
| 6 | Ocean / water | `scripts/systems/fft_water_system.gd` + `scripts/systems/boat/wave_surface.gd` | FFT water simulation, wave query for buoyancy |
| 7 | Ship (the boat) | `scripts/systems/boat/` (15 files) | BoatBody, controller, camera, propulsion, rudder, thruster, buoyancy, hydrodynamics, cargo deck, captain's chair, bridge interactable, ship lights, audio |
| 8 | Ship building | `scripts/systems/ship_builder.gd` | Builds a BoatBody from a ship template JSON |
| 9 | Mesh & model loading | `scripts/systems/mesh_transformer.gd`, `model_assembler.gd`, `scripts/world/mesh_builder.gd` | Loads JSON meshes/models, builds geometry + collision |
| 10 | Port (the place) | `scripts/world/port/` (port_plot, fuel_station, lighthouse_building, fog_horn_building) + `scripts/systems/port/port_facilities.gd` | Procedural port layout, ground, buildings |
| 11 | Dock / berthing | `scripts/systems/dock/` (port_dock, mooring_component, mooring_point, mooring_post, ship_spawner, dock_facilities, dock_terminal, dock_cargo_ramp) | Berths, mooring, ship spawning at port |
| 12 | NPCs | `scripts/world/npc/` (base + interactable) + `scripts/systems/dock/` (harbour_master, shipwright, contract, delivery NPCs) | NPC base class, interactable pattern, four port NPCs |
| 13 | Cargo & contracts | `scripts/systems/cargo/` (contract, cargo_item, cargo_pickup, delivery_zone, warehouse, warehouse_contract_zone) + `scripts/data/` (cargo_manifest, cargo_entry, cargo_berth_type) + `ContractRegistry` autoload | Contract data, cargo items, pickup/delivery zones, warehouse |
| 14 | Player carry (placeholder) | `scripts/systems/player/player_carry_component.gd` | Player picks up and carries crates by hand |
| 15 | Audio | `scripts/systems/audio/` (boat_audio_system, weather_audio_system) + `scripts/entities/fog_horn.gd` | Ship engine sounds, weather ambience, foghorn |
| 16 | Lighting (in-world) | `scripts/systems/boat/ship_light.gd`, `ship_lighting.gd` + lighthouse beam | Nav/work lights on ships, lighthouse beam |
| 17 | UI / HUD | `scripts/ui/` (debug_draw, hud_style, map_overlay, ship_hud, walking_hud, weather_debug_presets) + `GameMenu` & `DebugHud` autoloads | Map overlay, ship HUD, walking HUD, debug overlay, pause menu |
| 18 | Data classes (no behaviour) | `scripts/data/` (PortData, PortDefinition, PortExpander, ShipData, ShipClass, CargoManifest, CargoEntry, CargoBerthType) | Typed records used across systems |

### Things that aren't really systems but should be flagged

- **`scripts/util/` (just `uuid_util.gd`) + `scripts/utils/` (just `navigation_axes.gd`)** — duplicate folders, almost certainly a typo. Merge.
- **`scripts/entities/` (just `player.gd` + `fog_horn.gd`)** — sparse, no shared concept. Player belongs with the player system; fog_horn belongs with the port system.
- **`scripts/data/` vs `scripts/state/`** — both hold data classes. `state/` has the `*State` runtime-mutable ones; `data/` has the `*Data` / `*Definition` ones. The distinction is real but not signalled.

### Patterns scattered across multiple systems

- **Interactable / prompt system.** `NpcInteractable`, `BridgeInteractable`, `CaptainsChair`, `CargoPickup` all implement variants of "show prompt → press E → do thing". Not a system in its own folder; a recurring pattern with no shared base.
- **Building-from-model scaffolding.** `LighthouseBuilding` and `FogHornBuilding` duplicate the same boilerplate (instantiate `ModelAssembler`, hold `MODEL_PATH`, clean up children on rebuild, handle editor ownership).
- **State wiring.** `GameState._ready` reaches into autoloads (`PlayerSession`, `ContractRegistry`, `WeatherLighting`) by name. Works, but couples the read model to specific autoloads.

---

## Part 2 — Future Systems (what's coming)

Anything mentioned in the design or implied by the MMO goal, but not in code yet. Counted: **about 20.**

### Near-term (next-12-months tier)

| System | Purpose | Cost to build |
|---|---|---|
| Cranes & palletised cargo | The replacement for player-carry. See `CARGO_AND_CRANES.md`. | Large |
| Fuel economy | Fuel station exists as a building but doesn't consume fuel. Refuelling, fuel cost, range pressure. | Small–medium |
| Save / load | No persistence beyond `PlayerSession.marks`. World seed + player state + contracts + cargo + ship roster. | Medium |
| Reputation | Mentioned in design. Per-port standing affects contract availability and pricing. | Small if data-only |
| Economy / pricing | Currently commodity values are flat constants in `ContractRegistry`. Per-port supply/demand pricing, time-varying. | Medium |
| Dialogue runner | NPC dialogue is currently hand-rolled per-NPC (`HarbourMasterNpc._build_ui`, etc). Shared runner + data-driven trees. | Small–medium |
| VHF radio / comms | Harbour master check-in, weather reports, contract calls. Becomes the diegetic UI surface. | Medium |
| Damage & repair | `ShipData.hull_health` exists as a field, no gameplay. Collision damage, marine engineer repairs. | Medium |
| Marine engineer / chandlery / customs | Port facilities exist as buildings only. Become gameplay services. | Small per service |
| Settings / options | Audio, controls, graphics. Currently no UI. | Small |
| Tutorial / onboarding | None. | Small–medium |

### Mid-term

| System | Purpose | Cost |
|---|---|---|
| Crew / hired captains | Late-game progression — delegate routes to AI captains | Medium |
| Fleet management | Multi-ship ownership, route assignment, payroll | Medium |
| AI ships / ambient traffic | "World already in motion" — rival shipping seen on the water | Medium–large |
| Quest / story arcs | Beyond per-contract; named characters, recurring jobs, multi-step | Medium |
| Bank / loans | Borrow to buy bigger hull, scheduled payments | Small |
| Navigation aids | Charts, lighthouses as nav, RDF, harbour pilotage | Medium |
| Crane delegation (hired loaders) | Pay NPC to load while you're away. Last phase of cargo system. | Small once cargo is done |

### MMO-tier (much later, designing for now)

| System | Purpose | Cost |
|---|---|---|
| Networking | Authoritative server, client prediction, state replication | Very large |
| Player accounts / auth | Login, identity, friend lists | Medium |
| Chat / social | Text, channels, VHF as in-game chat | Medium |
| Berth reservation (multi-client) | Harbour master mediates between clients (designed-for now) | Small once net is built |
| Telemetry / analytics | Gameplay metrics, balance data | Small |
| Anti-cheat | Server-authoritative validation of trades, deliveries, positions | Medium–large |
| Localization | String tables, translation pipeline | Small ongoing |

### Total scope

- Today: ~18 systems.
- After near-term: ~28.
- After mid-term: ~33.
- MMO-complete: ~40.

The folder structure has to survive a roughly **2.2× growth** in system count, with the heaviest additions being **cargo/cranes, networking, and economy**.

---

## Part 3 — Proposed Structure

### Principle: organise by system, not by node type

Today's structure mixes axes:
- `autoloads/` (by **how it runs**)
- `entities/` (by **what node type it inherits**)
- `systems/` (by **what it does**)
- `state/` and `data/` (by **what kind of class**)
- `world/` (by **where in the scene it lives**)

These overlap. A weather system has an autoload, a state class, a hud, an audio system, and a Node3D zone — they're scattered across five folders.

One axis: **system folder owns everything that system does**, regardless of node type, regardless of whether it's an autoload.

### Top-level folders

```
scripts/
  core/         framework — no game knowledge, used by everything
  player/       the human at the helm or on the deck
  ship/         the boat: physics, components, controls
  ocean/        water surface, wave simulation
  weather/      wind, rain, fog, weather lighting
  time/         world clock, day/night
  world/        world generation, seeding, proximity loading, atmosphere
  port/         the port as a place: plot, dock, facilities, buildings
  npc/          NPC base + the NPCs themselves
  cargo/        contracts, cargo data, pickup/delivery, warehouse — and later cranes
  economy/      pricing, reputation, supply/demand           [FUTURE]
  comms/        dialogue, VHF radio, prompts                 [partly FUTURE]
  ui/           HUDs, menus, overlays
  fleet/        multi-ship ownership, hired captains          [FUTURE]
  save/         persistence                                    [FUTURE]
  net/          multiplayer / MMO                              [FUTURE]
  state/        GameState aggregate + sub-states (cross-system read model)
```

### Inside a system folder

Each folder holds whatever that system needs:
- Autoload script (if it has one)
- Sub-state class (if it has one)
- Components, nodes, services
- Data classes specific to it
- A `services/` subfolder if there are many

Example:

```
scripts/weather/
  world_weather.gd          # autoload — wind/rain/fog state
  weather_lighting.gd       # autoload — sun, fog colour
  weather_state.gd          # data
  weather_zone.gd           # in-world Area3D
  rain_field.gd             # particle field
  weather_audio.gd          # sound
  weather_hud.gd            # UI panel
  weather_debug_presets.gd  # debug tooling
```

Everything weather-related, one place. Same for ship, cargo, port, etc.

### `core/` is special

Anything used by multiple systems with no game knowledge of its own:

```
scripts/core/
  mesh_transformer.gd       # JSON mesh → MeshInstance3D + collision
  model_assembler.gd        # JSON model parts → tree of MeshTransformers
  mesh_builder.gd           # primitive helpers
  island_mesh_builder.gd    # primitive helpers (terrain-specific)
  building_from_model.gd    # NEW shared base for LighthouseBuilding-style buildings
  interactable.gd           # NEW shared base for prompt → E pattern
  palette.gd                # colour constants
  util_uuid.gd              # was util/uuid_util.gd
  util_navigation_axes.gd   # was utils/navigation_axes.gd
```

No game logic in here. If a system needs game-aware behaviour, it lives in that system's folder.

### `state/` stays — it's the cross-system read model

`GameState` aggregates sub-states from many systems. It's the one place a UI can subscribe without knowing which system produced a change. Each sub-state class lives next to GameState here, even though it mirrors data owned elsewhere — the aggregation point is itself a thing.

### Data classes follow their system

`PortData` and `PortDefinition` go to `port/`. `ShipData`, `ShipClass` go to `ship/`. `CargoManifest`, `CargoEntry`, `CargoBerthType` go to `cargo/`. The `scripts/data/` folder disappears.

### Autoloads consolidated

Today: 8 autoloads, all in `scripts/autoloads/`. After: ~8–12 autoloads, **each living in its own system folder**, registered in `project.godot` from those paths.

| Autoload | Owns | Folder |
|---|---|---|
| `GameState` | Cross-system read model | `state/` |
| `PlayerSession` | Player persistence, marks | `player/` |
| `WorldWeather` | Weather sim | `weather/` |
| `WeatherLighting` | Lighting reaction | `weather/` |
| `WorldClock` | Time | `time/` |
| `ContractRegistry` | Contracts + commodities | `cargo/` |
| `GameMenu` | Pause / menu | `ui/` |
| `DebugHud` | Debug overlay | `ui/` |
| **`Economy`** (FUTURE) | Pricing, supply/demand | `economy/` |
| **`SaveLoad`** (FUTURE) | Persistence | `save/` |
| **`Net`** (FUTURE) | Multiplayer transport | `net/` |
| **`Comms`** (FUTURE) | Dialogue + radio routing | `comms/` |

### `resources/data/` mirrors the system layout

The data tree gets the same shape as the script tree:

```
resources/data/
  meshes/                # raw {vertices, indices} only — no parts arrays here
    hulls/               # NEW — geometry extracted from current models/hulls
    bridges/             # NEW — geometry for superstructures
    docks/
    port_buildings/
    lighthouse/  foghorn/  props/  characters/  terrain/
    cranes/              [FUTURE]
    pallets/             [FUTURE]
    containers/          [FUTURE]
  models/                # parts arrays only — reference external meshes, no inline geometry
    hulls/  ships/  superstructures/  buildings/
    cranes/              [FUTURE]
  ships/                 # ship templates → ShipBuilder
  buildings/             [FUTURE if needed] building templates
  cranes/                [FUTURE] crane templates (mechanism + tool + endpoint specs)
  ports/                 # port definitions
  contracts/             # contract templates if/when they leave code
  commodities/           # commodity definitions (currently inline in ContractRegistry)
  lights/                # nav-light JSONs
```

(The full meshes/models migration rule is the topic of `MODEL_SYSTEM.md` — to be written next if you want.)

### Scenes follow the same axis

```
scenes/
  world.tscn
  port_test.tscn         # standalone port test
  hull_lineup.tscn       # hull comparison
  player/                # player.tscn
  ship/                  # boat scenes (today: fuel_tanker, test_boat — both pending migration)
  port/                  # port_dock.tscn, port_facilities.tscn, fuel_station.tscn, lighthouse_building.tscn, fog_horn_building.tscn
  npc/                   # npc_base.tscn
  ship/superstructures/  # bridge scenes
  ui/                    # menu/HUD scenes
```

The current `scenes/shared/` becomes meaningless — every scene is shared. Things go where they belong.

---

## Migration approach

Don't do this in one PR. Migrations of this size land safest in passes:

1. **Names & duplicates first** — merge `util/` + `utils/`, kill `entities/` (move its two files to their systems), kill `scripts/data/` (distribute to systems). Lowest risk.
2. **Consolidate weather** — pull `WorldWeather`, `WeatherLighting`, `weather_audio_system`, `weather_debug_presets` into `scripts/weather/`. Single-system pilot.
3. **Consolidate ship & ocean** — `boat/` → `ship/`, extract `wave_surface` and `fft_water_system` to `ocean/`.
4. **Consolidate port & dock & NPC** — the messiest area. `world/port/` + `systems/port/` + `systems/dock/` (NPC bits) → split into `port/` and `npc/`.
5. **Move autoloads into their system folders** — update `project.godot` paths.
6. **Promote `core/`** — move shared infrastructure out of `systems/`.
7. **Mirror in `resources/data/`** — the model-system migration is a separate big task; do it once the script side is stable.

Each pass is a self-contained branch that compiles and runs. Worktree-friendly.

---

## What changes for daily work

After:
- Adding a new system = one new folder. Everything related goes there.
- Adding a new autoload = it lives in its system's folder. Register the path in `project.godot`.
- Adding a new mesh = `resources/data/meshes/<category>/<name>.json` (raw geometry only). Reference it from a model JSON.
- Adding a new model = `resources/data/models/<category>/<name>.json` (parts array referencing meshes).
- Adding a new ship = `resources/data/ships/<name>.json` template → `ShipBuilder`.
- Adding a new building = same pattern as ships, once `BuildingFromModel` and a `BuildingBuilder` exist.

If you can't tell which folder a new file belongs in, the structure has failed and the folder list needs a new entry.
