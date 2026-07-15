# ARCHITECTURE.md — Angst 'n Anchors

Detailed architecture reference. See also:
- [`AGENTS.md`](AGENTS.md) — quick-start for AI agents
- [`Angst 'n Anchors.md`](Angst%20'n%20Anchors.md) — game design overview
- [`SHIP_BUILDING.md`](SHIP_BUILDING.md) — hull slots and ship JSON pipeline
- [`SAVE_FORMAT.md`](SAVE_FORMAT.md) — player save schema

---

## Organising Principle: One Folder Per System

The folder structure follows a single axis: **by system**. A system owns everything it needs — its autoload, its sub-state, its node scripts, its data classes, its UI bits — regardless of node type or runtime role.

Old axes that are rejected:
- `autoloads/` (by how it runs)
- `entities/` (by what node type it inherits)
- `systems/` (by what it does, but too broad)
- `data/` vs `state/` (by class kind, not domain)

After migration, you can open one folder and find everything a system does. Searching for "anything weather" means looking in `scripts/weather/`.

---

## System Folders

### `scripts/core/` — Shared Infrastructure

No game knowledge. Used by multiple systems. Nothing in here knows about ships, ports, NPCs, or cargo.

| File | Role |
|---|---|
| `mesh_transformer.gd` | Loads raw `{vertices, indices}` JSON → `MeshInstance3D` + optional collision |
| `model_assembler.gd` | Loads `{parts}` JSON → tree of `MeshTransformer` nodes |
| `model_cache.gd` | Build-once / stamp-copies for static JSON visuals (shared `ArrayMesh`) |
| `json_util.gd` | Path-keyed JSON parse cache (read-only Dictionaries) |
| `mesh_builder.gd` | Primitive shape helpers (box, cylinder, etc.) |
| `island_mesh_builder.gd` | Terrain-specific polygon helpers |
| `palette.gd` | Colour constants |
| `uuid_util.gd` | UUID generation |
| `navigation_axes.gd` | Axis helpers |

Two shared bases to be added during cleanup:
- `interactable.gd` — base for the "show prompt → press E → signal" pattern
- `building_from_model.gd` — base for `LighthouseBuilding`-style model assemblies

### `scripts/player/`

`CharacterBody3D` controller, `PlayerSession` autoload (marks, persistence), player data class.

### `scripts/ship/`

Everything the boat does. Reusable hull components plus brick-built store ships:
- Core: buoyancy, hydro, propulsion, rudder, thruster, controller, camera, mooring solver, walk deck
- `HullRegistry` / `HullCatalog` own geometry platforms identified by dimensions
- `PrebuiltVesselCatalog` owns store ships: hull + bricks + shaft power + price
- `VesselSpawn` builds the hull, applies the brick fit-out, then applies ship power
- `VesselKits`, `VesselLoadout`, and attachment sockets are quarantined legacy code

### `scripts/ocean/`

Water physics. `FftWaterSystem` (the FFT simulation node) and `WaveSurface` (query API used by `BuoyancyComponent` and anything else that needs wave height).

### `scripts/weather/`

Deterministic `WeatherField` + `Season`, analytic `WeatherFrontField`, coastal
`LandField`, and `WeatherComposer` produce one authoritative sample from seed,
position, and `WorldClock`. `WorldWeather` is the public API for point, route,
and front queries. `WeatherLighting` remains the autoload facade for the
smoothed local presentation consumed by sky/fog/ocean/audio. `RainField`,
`WeatherAudioSystem`, the weather HUD, and scoped debug presets are presentation
consumers. `LandField` reads the generated macro SDF in O(1): local
`wave_shelter` feeds physical ocean attenuation once, while kilometre-scale
`coastal_exposure` and directional fetch feed weather, sea state, and fishing.

### `scripts/time/`

`WorldClock` autoload. Game time, day/night cycle.

### `scripts/world/`

World-level generation. A deterministic 40×40 km Norway archetype is the shared
truth for rendering, weather, ports, charting, and navigation.
- `World` (`@tool` Node3D, scene root) — resolves seed/version, owns layout bootstrap and consumers
- `WorldLayoutGenerator` / `WorldLayout` — eastern mainland, branching navigable fjords, western skerries, SDF, heights, contours, waterway graph, checksum
- `CoastalPortPlacer` — validates coast sites and aligns existing ports with local `-Z` seaward
- `WorldTerrainStreamer` — incremental 1 km `ArrayMesh` chunks, distance LOD, nearby concave collision, flattened port pads
- `ProximityLoader` — lazy-instantiates nodes near the player
- `WorldRenderer` — ocean shader plane, sky
- `AtmosphericEffects` — fog, atmospheric post-processing
- `WaterwayNavigation` (`navigation/`) — deterministic reachability and navigable route distance over generated centerlines

### `scripts/port/`

One port as a place. Macro worlds retain the existing port content and replace
only its placement and ground.
- `PortPlot` — composition root: optional legacy island ground, `PortDock`, `PortFacilities`
- `PortDock` — berths, mooring, cargo aprons, fuel point, ship spawner
- `PortFacilities` — service slots from `PortServiceSlotCatalog` plus lighthouse/fog-horn landmarks
- `PortServiceSlotCatalog` — default-port slot poses + optional building JSON bindings
- `FuelStation`, `LighthouseBuilding`, `FogHornBuilding` — physical buildings
- `DockTerminal`, `DockCargoRamp` — dock interaction points
- `PortData`, `PortDefinition` — lean site truth plus derived runtime dock data
- `PortExpander` — expands `PortDefinition` → `PortData`
- `PortSizing` — shared dock, facilities, coast-validation, and terrain-pad dimensions
- `BuildingBlueprintCatalog` — `buildings/*.json` addressed by filename stem
- `BuildingGrid` / `BuildingLayout` — portable JSON building instructions on the shared `BrickCatalog` kit
- `BuildingRules` / `BuildingFitout` — validation and identical editor/runtime assembly
- `PortShowcase` — inspect runtime port shell (`scenes/showcases/`)

### `scripts/apps/`

Engine authoring apps (run via `scenes/apps/*.tscn`, not in-game UI).
- `BuildingBrickEditor` — voxel buildings → `resources/data/buildings/`
- `PortSlotEditor` — default-port service slots → `resources/data/ports/`
- `ShipyardBrickEditor` — official vessel prebuilts → `resources/data/vessels/prebuilt/`

Player-owned ports are a future authoritative overlay, not part of world
generation. Immutable `WorldLayout` geography stays seed-derived; ownership,
expansion, and player building diffs will be persisted separately by stable
port/site ID.

### `scripts/npc/`

All NPCs.
- `NpcBase` — shared base class
- `NpcInteractable` — the interactable wrapper for NPCs
- `HarbourMasterNpc` — berth assignment, vessel info, dues
- `ShipwrightNpc` — sells official ready-builts from `PrebuiltVesselCatalog`
- `ContractNpc` — post/accept contracts
- `DeliveryNpc` — receive deliveries

### `scripts/cargo/`

Contracts, cargo, and eventually cranes.
- `ContractRegistry` autoload — single source of truth for contracts and commodities
- `Contract`, `CargoItem`, `CargoManifest` — data classes
- `CargoPickup`, `DeliveryZone` — world interaction nodes
- `Warehouse`, `WarehouseContractZone` — warehouse system
- `CargoBerthType` — berth capability data

### `scripts/ui/`

- `GameMenu` autoload (pause/menu)
- `DebugHud` autoload (F3 overlay)
- `MapOverlay` marine-chart shell with cached macro coastline, port markers,
  waterway route distance, and layered components under `ui/chart/`
- `ShipHud`, `WalkingHud`

### `scripts/state/`

The cross-system read model. `GameState` aggregates sub-states so UI can subscribe without knowing which system produced a change.

- `GameState` autoload — aggregates sub-states
- `PlayerState`, `ShipState`, `ContractState`, `WorldState` — sub-state classes

---

## Autoloads

Each autoload lives in its system folder and is registered in `project.godot` from that path.

| Autoload | System Folder | Registered Path |
|---|---|---|
| `GameSettings` | `state/` | `res://scripts/state/game_settings.gd` |
| `WorldWeather` | `weather/` | `res://scripts/weather/world_weather.gd` |
| `WeatherLighting` | `weather/` | `res://scripts/weather/weather_lighting.gd` |
| `WorldClock` | `time/` | `res://scripts/time/world_clock.gd` |
| `ContractRegistry` | `cargo/` | `res://scripts/cargo/contract_registry.gd` |
| `PlayerSession` | `player/` | `res://scripts/player/player_session.gd` |
| `GameMenu` | `ui/` | `res://scripts/ui/game_menu.gd` |
| `GameState` | `state/` | `res://scripts/state/game_state.gd` |
| `DebugHud` | `ui/` | `res://scripts/ui/debug_hud.gd` |
| `Telemetry` | `state/` | `res://scripts/state/telemetry.gd` |
| `LocalPlayerView` | `state/` | `res://scripts/state/local_player_view.gd` |
| `Tutorial` | `state/` | `res://scripts/state/tutorial.gd` |

### `LocalPlayerView` — the MP seam

`LocalPlayerView` is a per-client view of the local player's projection of the world. UI consults it instead of touching `PlayerSession` / `ContractRegistry` directly; gameplay-mutating code (NPC commerce, ship spawning, contract acceptance) continues to use the autoloads. When multiplayer lands, every UI that reads through `LocalPlayerView` keeps working with no further changes — only the autoload's internals switch from "delegate to local autoloads" to "consume the server projection."

---

## State Model

UI and other read-only consumers subscribe to `GameState`. Systems write their own state and expose it through `GameState`'s sub-states.

```
[Ship system] writes → GameState.ship (ShipState)
[Weather system] writes → GameState.world.weather (inside WorldState)
[Contract system] writes → GameState.contract (ContractState)
[Player system] writes → GameState.player (PlayerState)

[UI, HUD, map] reads ← GameState.*
```

No UI node should reach into a system node to read values. No system should reach into the UI.

---

## Vessel Pipeline

Hull components and store ships are separate data:

```
resources/data/vessels/hulls/catalog.json
          ↓ reusable L×B hull component
registration catalog + ShipyardBrickEditor
          ↓ {id, name, hull_id, registration_id, price_marks, shaft_power_kw, brick_layout}
resources/data/vessels/prebuilt/<store_ship>.json
          ↓
Shipwright → owned ledger → VesselSpawn
          ↓
VesselCompliance → hull geometry + DeckFitout + per-ship propulsion override
```

Vessel orientation: **Bow = −Z, Stern = +Z, Port = −X, Starboard = +X.**
One hull can support any number of differently outfitted and powered store ships.
`ShipClass` is physical size; `VesselRegistration` is declared legal role.
`VesselCompliance` intersects registration law with `VesselOutfit`'s physical budget.
Save, commission, and deployment require a passing checklist; `DeckFitout` mounts only
accepted gear and `BoatBody` discovery is the gameplay seam.

Developer paperwork runs from `scenes/apps/vessel_registration_audit.tscn`. It edits
`resources/data/vessels/registrations/catalog.json` and audits raw prebuilt files,
including invalid files that the runtime catalog correctly refuses to list.

---

## Data Folder Layout

```
resources/data/
  models/
    buildings/        # Building model JSONs
  meshes/             # Raw {vertices, indices} JSON by category
    docks/
    port_buildings/
    lighthouse/ foghorn/ props/ characters/ terrain/
  lights/             # Nav-light configs
  world/              # Procedural archetype parameters (no generated geometry)
scenes/vessels/       # Hand-authored BoatBody scenes
```

Rule: `meshes/` contains only `{vertices, indices}` files. `models/` contains only `{parts}` files that reference meshes. No mixing.

---

## Interactable Pattern

All "press E to do thing" interactions share one base. Do not hand-roll prompt/interaction logic per object.

```
Interactable (base — scripts/core/interactable.gd)
  ├── shows/hides prompt label (world-space)
  ├── detects player in range (Area3D)
  ├── emits signal: activated(interactable)
  └── subclasses override: _on_activated()

NpcInteractable extends Interactable
BridgeInteractable extends Interactable
CargoPickup extends Interactable
```

---

## Building-From-Model Pattern

`LighthouseBuilding`, `FogHornBuilding`, and future buildings share a common base for instantiating a `ModelAssembler`, cleaning up children on rebuild, and handling editor ownership. The base lives in `scripts/core/building_from_model.gd`.

```gdscript
class_name BuildingFromModel extends Node3D

const MODEL_PATH: String = ""  # override in subclass

func _rebuild() -> void:
    for child in get_children(): child.queue_free()
    var ma := ModelAssembler.new()
    add_child(ma)
    ma.model_data_path = MODEL_PATH
```

---

## Adding a New System

1. Create `scripts/<system_name>/`.
2. Put everything that system owns in that folder — autoload, state class, nodes, data classes, UI panels.
3. If it has an autoload, register it in `project.godot` from the new path.
4. If it has a sub-state, wire it into `GameState`.
5. If it has a HUD panel, it belongs in the system folder (not `ui/`), but `ui/` autoloads may reference it.

If you can't tell which folder a new file belongs in, the system list needs a new entry.
