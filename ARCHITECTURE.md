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
- `CargoSlotPadComponent` — visible container slot pads from `BrickLayout.container_pads`
- Bulk holds — ore/coal/grain via hold components (separate from containers)
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
- `CoastalPortPlacer` — fits deterministic terminal archetypes to navigable coastal sites; local `-Z` remains seaward
- `WorldTerrainStreamer` — incremental 1 km `ArrayMesh` chunks, distance LOD, nearby concave collision, compound facility footprints
- `ProximityLoader` — lazy-instantiates nodes near the player
- `WorldRenderer` — ocean shader plane, sky
- `AtmosphericEffects` — fog, atmospheric post-processing
- `WaterwayNavigation` (`navigation/`) — deterministic reachability and navigable route distance over generated centerlines

### `scripts/port/`

Ports are seeded as a coast-traced foundation plus a trade `berth_plan`. The
graph record (not a finished mesh) is what later growth must persist.
- `PortCatalog` autoload — live port directory for chart / proximity / spawn
- `PortTradeProfile` — deterministic destiny imports/exports; size unlocks commodities
- `PortBerthPlan` — asphalt pads vs dedicated quay arms from unlocked trade
- `PortLandPlan` — inland buildable zone + terrain stake grid (houses + role-correct trade yards)
- `PortCoastTracer` — shoreline fit / foundation for the harbour apron
- `PortModuleCatalog` / `PortModuleDefinition` — foundation root templates (module attach reserved for later growth)
- `PortLayoutGenerator` — coast foundation + berth_plan into `PortLayoutGraph` attrs
- `PortLayoutGraph` / `PortPlacedModule` — serialisable layout record (foundation + attrs)
- `PortLayoutGraphVisualizer` — foundation / berth pads / quays; only current port presentation
- `PortPlot` — streamed graph visualization root
- `PortData`, `PortDefinition` — lean site truth plus derived layout/trade data
- `PortExpander` — `PortDefinition` → trade → layout → `PortData`
- `PortSizing` — shared metres, trade size ceilings, berth length tables
- `BuildingBlueprintCatalog` — `buildings/*.json` addressed by filename stem
- `BuildingGrid` / `BuildingLayout` — portable JSON building instructions on the shared `BrickCatalog` kit
- `BuildingRules` / `BuildingFitout` — validation and identical editor/runtime assembly
- `PortShowcase` — inspect seeded coastal ports (`scenes/showcases/`)

### `scripts/apps/`

Engine authoring apps (run via `scenes/apps/*.tscn`, not in-game UI).
- `BuildingBrickEditor` — voxel buildings → `resources/data/buildings/`
- `ShipyardBrickEditor` — official vessel prebuilts → `resources/data/vessels/prebuilt/`

Player-owned port persistence/networking is deferred, but the data boundary is
already explicit: immutable geography and the initial graph/berth plan are
seed-derived; later ownership and expansion persist the exact `PortLayoutGraph`
by stable port/site ID instead of regenerating layout.

### `scripts/npc/`

All NPCs.
- `NpcBase` — shared base class
- `NpcInteractable` — the interactable wrapper for NPCs
- `ShipwrightNpc` — sells official ready-builts (parked from port spawn until replaced)

### `scripts/cargo/`

Trade commodity metadata and physical container units. Contract trade is deferred.
- `CommodityCatalog` — containers + bulk/liquid families, berth colours, playable trade helpers
- `ContainerUnit`, `ContainerFactory`, `ContainerNode` — cubed general-cargo units (4×4×4 m default)
- Bulk hold lots/rules (`bulk_hold_lot.gd`, `bulk_hold_rules.gd`) — ore/coal/grain in holds
- Ship pads live in `scripts/ship/cargo_slot_pad.gd` (`CargoSlotPadComponent`)

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
| `PortCatalog` | `port/` | `res://scripts/port/port_catalog.gd` |
| `PlayerSession` | `player/` | `res://scripts/player/player_session.gd` |
| `GameMenu` | `ui/` | `res://scripts/ui/game_menu.gd` |
| `GameState` | `state/` | `res://scripts/state/game_state.gd` |
| `DebugHud` | `ui/` | `res://scripts/ui/debug_hud.gd` |
| `Telemetry` | `state/` | `res://scripts/state/telemetry.gd` |
| `LocalPlayerView` | `state/` | `res://scripts/state/local_player_view.gd` |
| `Tutorial` | `state/` | `res://scripts/state/tutorial.gd` |

### `Telemetry` — the debug publishing seam

`Telemetry` is the central debug/performance registry. Runtime systems should
publish debug information there instead of adding new scene-tree searches to
the F3 overlay. Use `publish_metric()` for a single value, `publish_metrics()`
for a batch, or `register_provider()` when a node already exposes a cheap
debug-stat dictionary. Context useful during a later spike investigation belongs
in `set_context_flag()`; meaningful actions and lifecycle changes belong in
`record_event()` or the `begin_action()` / `end_action()` pair. Providers are
weakly held and must unregister on exit.

F3 is the consumer: its tabs show performance, world, vessel, events, and
context. It can switch between live and peak/worst values, reset retained peaks,
and copy `Telemetry.generate_report()` to the clipboard.

### `LocalPlayerView` — the MP seam

`LocalPlayerView` is a per-client view of the local player's projection of the world. UI consults it instead of touching `PlayerSession` / `PortCatalog` directly; gameplay-mutating code continues to use the autoloads. When multiplayer lands, every UI that reads through `LocalPlayerView` keeps working with no further changes — only the autoload's internals switch from "delegate to local autoloads" to "consume the server projection."

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
