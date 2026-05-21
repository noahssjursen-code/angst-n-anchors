# ARCHITECTURE.md — Angst 'n Anchors

Detailed architecture reference. See also:
- [`AGENTS.md`](AGENTS.md) — quick-start for AI agents
- [`SYSTEMS_AND_STRUCTURE.md`](SYSTEMS_AND_STRUCTURE.md) — migration rationale, future systems, migration plan
- [`Angst 'n Anchors.md`](Angst%20'n%20Anchors.md) — game design overview

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

Everything the boat does. `BoatBody` (RigidBody3D root), plus components all composed by `ShipBuilder`:
- `BuoyancyComponent`, `HydrodynamicsComponent`
- `PropulsionComponent`, `RudderComponent`, `BowThrusterComponent`
- `BoatController`, `BoatCamera`
- `MooringComponent`, `CargoDeckComponent`
- `ShipLight`, `ShipLighting`
- `BoatAudioSystem`
- `ShipBuilder` (factory — reads ship template JSON, produces a complete `BoatBody`)

### `scripts/ocean/`

Water physics. `FftWaterSystem` (the FFT simulation node) and `WaveSurface` (query API used by `BuoyancyComponent` and anything else that needs wave height).

### `scripts/weather/`

`WorldWeather` autoload (wind, rain, fog state), `WeatherLighting` autoload (sky/fog colour, sun angle), `WeatherState` (data class), `WeatherZone` (Area3D), `RainField`, `WeatherAudioSystem`, weather HUD panel, weather debug presets.

### `scripts/time/`

`WorldClock` autoload. Game time, day/night cycle.

### `scripts/world/`

World-level generation. No port content — just where ports are placed and how the world looks.
- `World` (`@tool` Node3D, scene root) — generates port definitions from seed, sets up `ProximityLoader`
- `ProximityLoader` — lazy-instantiates nodes near the player
- `WorldRenderer` — ocean shader plane, sky
- `AtmosphericEffects` — fog, atmospheric post-processing

### `scripts/port/`

One port as a place.
- `PortPlot` — composition root: island ground, `PortDock`, `PortFacilities`
- `PortDock` — berths, mooring, cargo aprons, fuel point, ship spawner
- `PortFacilities` — land-side layout: buildings, NPC spawn positions
- `FuelStation`, `LighthouseBuilding`, `FogHornBuilding` — physical buildings
- `DockTerminal`, `DockCargoRamp` — dock interaction points
- `PortData`, `PortDefinition` — typed data records for ports
- `PortExpander` — expands `PortDefinition` → `PortData`

### `scripts/npc/`

All NPCs.
- `NpcBase` — shared base class
- `NpcInteractable` — the interactable wrapper for NPCs
- `HarbourMasterNpc` — berth assignment, vessel info, dues
- `ShipwrightNpc` — commission ships, hull catalog
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
- `MapOverlay`, `ShipHud`, `WalkingHud`

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

## Ship Building Pipeline

Ships are pure data → runtime assembly. Never hand-place ship components in the scene editor for new ships.

```
resources/data/models/hulls/hull_name.json    — geometry parts + slots
resources/data/ships/ship_name.json           — hull ref + scale + physics params + cargo decks
          ↓
ShipBuilder.build("res://resources/data/ships/ship_name.json")
          ↓
BoatBody (RigidBody3D)
  ├── MeshTransformer parts (hull geometry)
  ├── BuoyancyComponent
  ├── HydrodynamicsComponent
  ├── PropulsionComponent
  ├── RudderComponent
  ├── BowThrusterComponent
  ├── BoatController
  ├── BoatCamera
  ├── MooringComponent
  │     ├── MooringPoint (×4, from slots)
  ├── CargoDeckComponent (×N, from template)
  └── Bridge superstructure (loaded from scenes/shared/superstructures/)
```

Hull orientation: **Bow = +Z, Stern = −Z, Port = −X, Starboard = +X.**
All hull parts use `"rotation_degrees": [0, -90, 0]` to bake authored orientation into world space. No extra rotation anywhere else in the pipeline.

---

## Data Folder Layout

```
resources/data/
  ships/              # Ship templates → ShipBuilder
  models/
    hulls/            # Hull JSONs with slots (geometry + attachment points)
    ships/            # Ship model JSONs (legacy, being phased out)
    superstructures/  # Bridge scene references
    buildings/        # Building model JSONs
  meshes/             # Raw {vertices, indices} JSON by category
    hulls/
    bridges/
    docks/
    port_buildings/
    lighthouse/ foghorn/ props/ characters/ terrain/
  lights/             # Nav-light configs
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
