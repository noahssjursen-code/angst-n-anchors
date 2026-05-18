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
  core/         # Shared infrastructure — no game knowledge (MeshTransformer, ModelAssembler, MeshBuilder, palette, interactable base)
  player/       # CharacterBody3D controller, PlayerSession autoload, player data
  ship/         # BoatBody, controller, camera, propulsion, rudder, thruster, buoyancy, hydrodynamics, lights, audio
  ocean/        # FFT water simulation (FftWaterSystem), WaveSurface query
  weather/      # WorldWeather + WeatherLighting autoloads, WeatherState, WeatherZone, rain, audio, HUD, debug presets
  time/         # WorldClock autoload
  world/        # World generation, seeding, ProximityLoader, WorldRenderer, AtmosphericEffects
  port/         # PortPlot, PortDock, PortFacilities, FuelStation, LighthouseBuilding, FogHornBuilding
  npc/          # NpcBase, NpcInteractable, HarbourMasterNpc, ShipwrightNpc, ContractNpc, DeliveryNpc
  cargo/        # Contract, CargoItem, CargoPickup, DeliveryZone, Warehouse, ContractRegistry autoload — and later cranes
  ui/           # HUDs, menus, overlays, GameMenu + DebugHud autoloads
  state/        # GameState autoload (cross-system read model), sub-states: PlayerState, ShipState, ContractState, WorldState

resources/data/
  ships/        # Ship templates (fuel_tanker.json) → consumed by ShipBuilder
  models/
    hulls/      # Hull model JSONs with "slots" dict (attachment points)
    ships/      # Ship model JSONs (legacy wrappers, being phased out)
    superstructures/  # Bridge scenes referenced by hull slots
    buildings/  # Fog horn, lighthouse
  meshes/       # Raw {vertices, indices} JSON by category (hulls/, docks/, buildings/, props/, …)
  lights/       # Nav-light JSON configs
```

---

## Autoloads (Singletons)

Each autoload lives in its system folder and is registered in `project.godot`.

| Autoload | System | Role |
|---|---|---|
| `WorldWeather` | `weather/` | Wind, rain, fog state; weather zones |
| `WeatherLighting` | `weather/` | Sun angle, sky colour, fog colour |
| `WorldClock` | `time/` | Game time |
| `ContractRegistry` | `cargo/` | Port registry, contracts, commodities |
| `PlayerSession` | `player/` | Persistent player data (marks, name) |
| `GameMenu` | `ui/` | Pause / menu system |
| `GameState` | `state/` | Read model: player/ship/contract/world sub-states |
| `DebugHud` | `ui/` | F3 debug overlay |

The autoloads listed above are the **actual** registered singletons. Do not reference `Economy`, `ContractBoard`, `FleetManager`, or `World` — those don't exist yet.

---

## Ship Building System

Ships are built at runtime by `ShipBuilder` from a JSON template. There is no hand-placed boat scene for new ships.

### Pipeline

```gdscript
var boat := ShipBuilder.build("res://resources/data/ships/fuel_tanker.json")
get_tree().current_scene.add_child(boat)
boat.place_at_waterline(water_y)
```

### Three layers of JSON

1. **Hull JSON** — `resources/data/models/hulls/<name>.json`. Geometry parts + a `"slots"` dict of named attachment points.
2. **Ship template JSON** — `resources/data/ships/<name>.json`. References a hull, sets scale, superstructure key, physics params, buoyancy, cargo decks. Consumed by `ShipBuilder.build()`.
3. **Ship model JSON** — `resources/data/models/ships/<name>.json`. Legacy wrapper, being phased out. Use ship templates instead.

### Orientation convention — do not get this wrong

**Bow = +Z, Stern = −Z, Port = −X, Starboard = +X.**

Hull parts always use `"rotation_degrees": [0, -90, 0]` to bake authored vertex orientation into world space. Do not add extra rotation in ship model JSONs, ship template JSONs, or scene files.

### Slots

| Slot | Purpose |
|---|---|
| `bridge` | Superstructure origin |
| `propulsion` | Propeller attachment, below waterline |
| `bow_thruster` | Bow tunnel thruster |
| `mooring_port_fwd` / `mooring_stbd_fwd` / `mooring_port_aft` / `mooring_stbd_aft` | Four mooring points |
| `cargo_main` / `cargo_aft` | Cargo deck origins |
| `nav_light_bow` | Bow nav light |

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
