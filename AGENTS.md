# AGENTS.md — Angst 'n Anchors

Guidance for AI agents working in this codebase. Read this before writing any code.
Full design: [`Angst 'n Anchors.md`](Angst%20'n%20Anchors.md)
Full architecture: [`ARCHITECTURE.md`](ARCHITECTURE.md)

---

## What This Game Is

A maritime trading game built in Godot 4.6 (GDScript, Jolt, Forward Plus). The player drives a boat,
picks up cargo at one port, and delivers it to another. Ships are assembled at runtime from modular
JSON templates so players can build custom vessels without touching the scene editor. Long-term goal: MMO.

---

## Folder Structure — One Axis: By System

Every system owns everything it does — autoload, state class, components, data, UI bits. Nothing scattered across node-type folders.

```
scripts/
  core/         # Shared infrastructure — no game knowledge (MeshTransformer, ModelAssembler, ModelCache, MeshBuilder, palette, interactable base)
  player/       # CharacterBody3D controller, PlayerSession autoload, player data
  ship/         # BoatBody, controller, camera, propulsion, rudder, thruster, buoyancy, hydrodynamics, lights, audio
  ocean/        # FFT water simulation (FftWaterSystem), WaveSurface query
  weather/      # Deterministic field/front/composer, WorldWeather API, local presentation, rain/audio/HUD
  time/         # WorldClock autoload
  world/        # Norway macro layout/SDF, coastal ports, streamed terrain, renderer/loading
  port/         # PortPlot, PortDock, PortFacilities, PortSlotEditor, FuelStation, LighthouseBuilding, FogHornBuilding
  npc/          # NpcBase, NpcInteractable, HarbourMasterNpc, ShipwrightNpc, ContractNpc, DeliveryNpc
  cargo/        # Contract, CargoItem, CargoPickup, DeliveryZone, Warehouse, ContractRegistry autoload — and later cranes
  ui/           # HUDs, menus, overlays, GameMenu + DebugHud autoloads
  state/        # GameState autoload (cross-system read model), sub-states: PlayerState, ShipState, ContractState, WorldState

resources/data/
  buildings/    # Voxel building blueprints (filename stem = id); BuildingBrickEditor
  ports/        # default_service_slots.json authored by PortSlotEditor
  models/
    buildings/  # Fog horn, lighthouse
  meshes/       # Raw {vertices, indices} JSON by category (hulls/, docks/, buildings/, props/, …)
  lights/       # Nav-light JSON configs
  world/        # Procedural archetype parameters only; never generated mesh vertices
scenes/vessels/ # Hand-authored vessel scenes (workboat.tscn)
```

---

## Autoloads (Singletons)

Each autoload lives in its system folder and is registered in `project.godot`.

| Autoload | System | Role |
|---|---|---|
| `GameSettings` | `state/` | Client prefs plus session-only world seed/version/checksum handoff |
| `WorldWeather` | `weather/` | Deterministic weather query API: composed samples, routes, fronts, local projection |
| `WeatherLighting` | `weather/` | Smoothed local presentation only: sky, fog, ocean, audio, wind |
| `WorldClock` | `time/` | Game time. Emits `day_changed` + `hour_changed` (1 game hr = 60 real s) |
| `ContractRegistry` | `cargo/` | Port registry, contracts, commodities, restock loop |
| `PlayerSession` | `player/` | Persistent player data (marks, name, contracts, ship pose, world clock). Autosaves every 60 s + on focus loss |
| `GameMenu` | `ui/` | Pause / map / settings / journal / hint overlay |
| `GameState` | `state/` | Read model: player/ship/contract/world sub-states |
| `DebugHud` | `ui/` | F3 debug overlay |
| `Telemetry` | `state/` | Spawn-timing / load-events telemetry |
| `LocalPlayerView` | `state/` | **The MP seam.** Per-client view of the local player's world. UI reads through here, not direct autoloads |
| `Tutorial` | `state/` | First-time hint chain (fires once per captain, persisted) |

The autoloads listed above are the **actual** registered singletons. Do not reference `Economy`, `ContractBoard`, `FleetManager`, or `World` — those don't exist yet.

### Convention — `LocalPlayerView` is the MP seam

UI code (HUDs, menus, debug overlays, hint banners) should **only** read per-player state through `LocalPlayerView`. NPCs and gameplay-mutating systems (`VesselSpawn`, `PortDock`, contract acceptance) may continue to consult the autoloads directly — they're the world-authority side, not a per-client view.

Weather has a parallel read seam: gameplay/map queries call `WorldWeather.sample_at()` /
`sample_route()` / `active_fronts()`. Local VFX reads `WorldWeather.local_presentation`
(currently exposed by the `WeatherLighting` compatibility autoload). Never sample
`WeatherField` directly outside the weather implementation.

### World generation contract

`WorldLayoutGenerator.generate(seed)` creates the immutable 40×40 km
`WorldLayout`: macro SDF, terrain heights, coastline contours, regional tags,
and waterway graph. It is the shared geographic truth for terrain, `LandField`,
ports, charting, weather, and navigation.

- `CoastalPortPlacer` owns `PortDefinition` position/yaw; local `-Z` faces water.
- `WorldTerrainStreamer` owns 1 km terrain chunks, LOD, nearby collision, and port pads.
- `LandField.wave_shelter()` is short-range wave attenuation. Weather/fishing
  use `coastal_exposure()` / `directional_fetch()`.
- Do not reintroduce island-disk geography or per-port weather calm.
- Seed + generation version + layout checksum identify a world. Coordinate
  saves must not restore into a mismatched context.

In multiplayer this autoload becomes a per-client object the network layer populates with the local player's projection of the world. Every UI that already reads from here will keep working unchanged; the gameplay-mutating code stays on the (per-server) authority.

---

## Vessel System — Deck-grid bricks

Hand-authored vessel scenes (`scenes/vessels/`) own hull geometry and core systems. Deck fit-out is a **1×1×1 m brick grid** painted in the shipwright fullscreen editor (`ShipyardBrickEditor`). Layout persists as `brick_layout` on the owned-vessel ledger; spawn rebuilds via `DeckFitout`.

```gdscript
var boat := VesselSpawn.instantiate_from_record(owned_vessel_record)
get_tree().current_scene.add_child(boat)
boat.place_at_waterline(water_y)
```

| Always on BoatBody (core) | Brick fit-out (player) |
|---|---|
| Hull visual + collision | Wall / window / door / ledge / railing bricks |
| Strip buoyancy + hydro | Cargo tiles → cargo deck |
| Propulsion, rudder, thruster | Crane base + crane → ship crane |
| BoatController / Camera / Audio | Enclosed cabin + door → helm boarding |
| MooringComponent + auto cleats/lights | |
| WalkDeck | |

Role (ferry / cargo / trawler-with-crane) comes from bricks + rules (`BrickRules`), not kit ids. Do **not** revive `WheelhouseVisual`, hull JSON `bridge` slots, or `ShipBuilder`.

`BrickCatalog` is the shared construction kit for vessel decks and land buildings. Marine-only pieces carry the `ship_only` tag and are filtered out of the building editor palette.

### Orientation (workboat)

**Bow = −Z, Stern = +Z, Port = −X, Starboard = +X.** Grid cells are vessel metres.

---

## Visual Rules — No Imported Assets

**No `.gltf` / `.glb` / `.fbx` / `.obj`. No imported texture files for in-world objects.**

Everything comes from:
1. **Godot primitives** (`BoxMesh`, `CylinderMesh`, etc.) composed in GDScript.
2. **JSON meshes** under `resources/data/meshes/`, loaded by `MeshTransformer`.

Materials are always `StandardMaterial3D` built at runtime. Shaders live in `resources/shaders/`.

### MeshTransformer (single part)

```gdscript
var mt := preload("res://scripts/core/mesh_transformer.gd").new()
add_child(mt)
mt.mesh_data_path = "res://resources/data/meshes/hulls/your_mesh.json"
mt.absolute_scale  = 1.0
mt.mesh_color      = Color(0.18, 0.20, 0.22)
```

### ModelAssembler (multiple parts)

```gdscript
var ma := preload("res://scripts/core/model_assembler.gd").new()
add_child(ma)
ma.model_data_path = "res://resources/data/models/buildings/lighthouse.json"
```

`ModelAssembler` is generic — no ship, dock, or NPC terms in the mesh layer.
Use it when you need live part/role lookups, articulation, or per-instance collision from mesh parts (ships, NPCs, cranes, lighthouse).

### ModelCache (static visuals — stamp copies)

For repeated static props (port street buildings, bollards), build once and stamp:

```gdscript
var visual := ModelCache.instance("res://resources/data/models/buildings/foghorn_building.json")
visual.name = "Model"
body.add_child(visual)
```

`ModelCache` runs `ModelAssembler` on first miss, bakes a dumb `Node3D` of `MeshInstance3D`s (shared `ArrayMesh`es), and returns cheap stamps afterward. Do not use it when you need `get_part` / `get_first_part_by_role`. Editor builds bypass the prototype store so JSON edits stay visible.

### JSON mesh format

```json
{ "vertices": [x, y, z, ...], "indices": [i, i, i, ...] }
```

Flat arrays, no normals, no UVs. `SurfaceTool` generates normals at load time. Only authored by the in-house mesh tool — do not hand-edit vertex data.

### Multi-part model format

```json
{
  "parts": [
    {
      "name": "body", "mesh": "hull_body.json", "role": "physics_body",
      "position": [0, 0, 0], "rotation_degrees": [0, -90, 0], "scale": 1.0,
      "color": [0.15, 0.15, 0.18], "roughness": 0.9, "metallic": 0.0, "collision": "convex"
    }
  ]
}
```

---

## Core Patterns

### State model

UI subscribes to `GameState`. Systems write state. No UI polls the scene tree.

```gdscript
# BAD — polling a node
var speed = $Ship/BoatBody.velocity.length()

# GOOD — read model
var speed = GameState.ship.speed_knots
```

### Interactable pattern

All "press E to do thing" interactions go through a shared base. Do not hand-roll per-object interaction prompts.

### Signals over direct calls

Nodes communicate across system boundaries via signals or autoloads, not node paths.

```gdscript
# BAD
get_parent().get_parent().get_node("HUD").show_prompt(text)

# GOOD
signal interaction_triggered(context: Dictionary)
```

### Data-driven

Port definitions, ship templates, commodities live in `resources/data/`. Scripts read from data.

---

## Godot Specifics

- Godot **4.6**, GDScript only, no C#
- Physics: **Jolt**
- Renderer: **Forward Plus**, D3D12 on Windows
- Use `class_name` for any script used by multiple others — it makes the type available globally without preload
- Use `@export` for designer-facing values; keep logic in scripts
- Scene tree is not the data model — game state lives in autoloads, not node hierarchies
- Concave shapes are silently disabled on dynamic bodies in Jolt — keep meshes convex-friendly

---

## Save Format

Persistence flows through `PlayerSession.save_now()` → `_snapshot_into_player_data()` (via `LocalPlayerView`) → `PlayerSaveStore.save_player()`. The save envelope is `{version, player, saved_at_unix}`; format version is currently **3**. See [`SAVE_FORMAT.md`](SAVE_FORMAT.md) for the field schema and upgrade behaviour.

Saved per-captain state covers: marks, lifetime stats, appearance, active vessel ledger record, accepted contracts (with delivered counts; in-flight cargo is forfeited on load), ship runtime state (position, yaw, throttle, fuel fraction), world identity, world-clock hours, and tutorial-hint-seen flags. Autosave heartbeats every 60 s of wall-clock; `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` and window focus loss both force a flush.

---

## Input Map

Actions registered in `project.godot` that gameplay code reads via `Input.is_action_pressed` / `event.is_action_pressed`:

| Action | Default key | Used by |
|---|---|---|
| `ui_cancel` | Esc | Pause menu, close dialogues, leave UI |
| `open_map` | M | Sea chart overlay |
| `open_journal` | J | Cargo journal overlay (toggle) |
| `toggle_camera` | V | First / third-person camera switch |
| `jump` | Space | Player jump |
| `boat_lights_toggle` | L | Boat nav lights |
| `boat_horn_press` | E | Foghorn |
| `boat_docking_thrusters` | T | Bow thruster mode |

Add new actions to `project.godot` directly; there is no separate input-map JSON.
