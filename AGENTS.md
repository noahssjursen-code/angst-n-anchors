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

## Visual Rules — Primitives Only

**No imported 3D models. No external meshes. No texture files for in-world objects.**

Every ship, dock, building, crate, buoy, and terrain piece is built in code from Godot primitives:
- `BoxMesh`, `CylinderMesh`, `SphereMesh`, `PlaneMesh`, `PrismMesh`
- Materials constructed from `StandardMaterial3D` with colour, roughness, and metallic values
- `MeshBuilder` (in `scripts/world/`) is the shared utility for constructing these

Shaders live in `resources/shaders/` and are applied to materials at runtime.

Textures and full shader passes come later. Build the geometry first, make it readable, make it correct. Visual polish is a later pass.

```gdscript
# Every in-world mesh follows this pattern:
var mesh := BoxMesh.new()
mesh.size = Vector3(2.0, 0.5, 4.0)
var mat := StandardMaterial3D.new()
mat.albedo_color = Color(0.3, 0.25, 0.2)
mat.roughness = 0.9
mat.metallic = 0.0
mesh_instance.mesh = mesh
mesh_instance.material_override = mat
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
