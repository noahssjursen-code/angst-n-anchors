# AGENTS.md — Angst 'n Anchors

Guidance for AI agents working in this codebase. Read this before writing any code.

---

## What This Game Is

A maritime trading game built in Godot 4.6 (GDScript, Jolt, Forward Plus). The player starts small and competes in a world that's already running. Ports export and import goods. You move cargo. Contracts are binding. Rival companies exist before you do.

Full design: [`Angst 'n Anchors.md`](Angst%20'n%20Anchors.md)

---

## Folder Structure

```
scenes/
  islands/          # One subfolder per island (starting_island/, etc.)
  shared/           # Reusable packed scenes (interactable, dialogue, prompt UI, etc.)
  ui/               # HUD, menus, overlay panels

scripts/
  autoloads/        # Singleton services — registered in project settings
  systems/          # Shared game systems (interaction, dialogue, contracts, economy)
  entities/         # Per-entity scripts (Port, Ship, Captain, Cargo, etc.)
  world/            # World generation: MeshBuilder, terrain, ocean, docks
  ui/               # UI logic scripts
  utils/            # Pure utility functions (math, formatting, random helpers)

resources/
  data/             # Port definitions, cargo types, contract templates (.tres or .json)
  shaders/          # .gdshader files
  themes/           # UI Theme resources
```

---

## Core Patterns

### 1. Shared Services First

Before writing custom logic for a specific scene, check if a system already handles it. If the mechanic will appear more than once — interactions, dialogue, prompts, objectives — build it as a shared system first.

**Autoloads** are the global services. They do not depend on scene structure.

Current intended autoloads (register in project settings as singletons):
- `GameState` — time, player money, reputation, flags
- `Economy` — port prices, supply/demand tracking
- `ContractBoard` — active contracts, posting, deadlines, consequences
- `FleetManager` — ships, captains, crew, routes
- `World` — map data, port registry, island registry

A scene that needs port prices asks `Economy`, not its own parent node.

### 2. Jigsaw Components — Plug and Play

Scenes should be composable. A `Port` scene doesn't hardcode its dock NPC — it has an `Interactable` child that any NPC or board can slot into. An `Interactable` doesn't know what happens when triggered — it signals outward and lets its parent or a system handle it.

Aim for: **add the component, wire one signal, it works.**

Avoid: a node that reaches up to its grandparent, or hardcodes the name of a sibling.

```gdscript
# BAD — brittle, scene-specific
get_parent().get_parent().get_node("HUD").show_prompt(text)

# GOOD — signal or autoload
InteractionSystem.show_prompt(text)
```

### 3. Signals Over Direct Calls (for decoupled nodes)

Nodes that don't own each other communicate via signals or autoloads. Direct method calls are fine within the same logical unit (a ship calling its own engine). Across units, signal or use a service.

### 4. Generic Before Specific

Before building the dock NPC, build `DialogueRunner`. Before building the contract board UI, build the generic scrollable list. The first implementation of any repeating pattern must be the reusable one — not a one-off you refactor later.

### 5. Data-Driven Where Possible

Port definitions, cargo types, and contract templates live in `resources/data/` as `.tres` Resource files or `.json`. Scripts read from these; they do not hardcode game data.

```gdscript
# BAD
var exports = ["Fish", "Timber"]  # hardcoded in script

# GOOD
var port_data: PortData = load("res://resources/data/ports/port_verde.tres")
var exports = port_data.exports
```

---

## Visual Rules — Primitives + In-House JSON Meshes

**No imported DCC assets. No `.gltf` / `.glb` / `.fbx` / `.obj`. No texture files for in-world objects.**

Every ship, dock, building, crate, buoy, and terrain piece comes from one of two sources:

1. **Godot primitives** composed in GDScript via `MeshBuilder` (`scripts/world/mesh_builder.gd`).
2. **In-house JSON meshes** in `resources/data/meshes/`, produced by our own low-poly mesh AI tool, loaded at runtime by `MeshTransformer` (`scripts/systems/mesh_transformer.gd`).

Both are first-class. Pick whichever fits the shape — primitives for boxy/symmetric objects, JSON meshes for hulls and anything organic.

Materials are always `StandardMaterial3D` constructed at runtime with colour, roughness, and metallic values. Shaders live in `resources/shaders/` and are applied to materials at runtime. Textures come later — geometry first, readable, correct.

### Primitive pattern

```gdscript
var mesh := BoxMesh.new()
mesh.size = Vector3(2.0, 0.5, 4.0)
var mat := StandardMaterial3D.new()
mat.albedo_color = Color(0.3, 0.25, 0.2)
mat.roughness = 0.9
mat.metallic = 0.0
mesh_instance.mesh = mesh
mesh_instance.material_override = mat
```

### JSON mesh pattern

JSON shape:

```json
{ "vertices": [x, y, z, ...], "indices": [i, i, i, ...] }
```

Flat arrays of floats and ints. No normals, no UVs — `SurfaceTool` generates normals; colour is applied at load time. Authored exclusively by the in-house mesh AI; do not hand-edit.

Always load through `MeshTransformer`. It normalises bounds, scales to `target_size`, applies the material, and builds a `ConvexPolygonShape3D` parented to the owning `RigidBody3D`. Concave shapes are silently disabled on dynamic bodies in Jolt — keep meshes convex-friendly or split them into convex pieces.

```gdscript
var transformer := preload("res://scripts/systems/mesh_transformer.gd").new()
add_child(transformer)
transformer.mesh_data_path = "res://resources/data/meshes/your_mesh.json"
transformer.target_size = Vector3(6.0, 2.0, 14.0)
transformer.mesh_color = Color(0.18, 0.20, 0.22)
```

---

## Build Discipline

- **Small steps.** Build the smallest thing that proves the system works, then expand.
- **No premature optimisation.** Readable code first. Profile before you optimise.
- **Validate before breadth.** One NPC using the shared dialogue runner correctly is worth more than five NPCs with custom one-offs.
- **The starting island is the test bed.** Every system gets proven there before it goes anywhere else.

---

## Godot Specifics

- Godot **4.6**, GDScript only (no C#)
- Physics: **Jolt**
- Renderer: **Forward Plus**
- Scene tree is not the data model — game state lives in autoloads, not node hierarchies
- Use `@export` for designer-facing values; keep logic in scripts
- Prefer `Resource` subclasses for structured data over plain `Dictionary`
