# AGENTS.md — Angst 'n Anchors

Guidance for AI agents working in this codebase. Read this before writing any code.
Full design: [`Angst 'n Anchors.md`](Angst%20'n%20Anchors.md)
Full architecture: [`ARCHITECTURE.md`](ARCHITECTURE.md)

---

## What This Game Is

A maritime company sandbox built in Godot 4.6 (GDScript, Jolt, Forward Plus). The player begins as
a working captain, then grows into an owner of custom vessels, hired crews, commercial routes, and
eventually coastal industry. Ships are assembled at runtime from modular JSON templates so players
can build custom vessels without touching the scene editor.

The long-term game supports the same company rules in two authority modes: local authority with NPC
competitor companies in single-player, and server authority with persistent player companies in
multiplayer. `CompanyContracts` and `CompanyService` now provide the first local-authority slice:
identity, account ledger, starter vessel, inventory lots, warehouse leases, and idempotent commands.
Crews, markets, rival companies, land, and facilities remain product direction. Extend the existing
contracts deliberately; do not invent parallel economy or fleet-manager singletons.

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
  port/         # PortCatalog, trade profiles, berth_plan + land_plan, PortPlot presentation
  npc/          # NpcBase, ShipwrightNpc (parked; port NPCs rebuilt later)
  cargo/        # CommodityCatalog, ContainerUnit/Node/Factory, bulk hold lots/rules
  company/      # Company/economy contracts + local authority service (future server seam)
  apps/         # Engine authoring apps (BuildingBrickEditor, PortSlotEditor, ShipyardBrickEditor)
  ui/           # HUDs, menus, overlays, GameMenu + DebugHud autoloads
  state/        # GameState autoload (cross-system read model), sub-states: PlayerState, ShipState, ContractState, WorldState

resources/data/
  buildings/    # Voxel building blueprints (filename stem = id); BuildingBrickEditor
  ports/        # Service-slot authoring data (trade slots are code+seed, not JSON metres)
  vessels/prebuilt/  # Official ready-built vessels; ShipyardBrickEditor
  models/
    buildings/  # Fog horn, lighthouse
  meshes/       # Raw {vertices, indices} JSON by category (hulls/, docks/, buildings/, props/, …)
  lights/       # Nav-light JSON configs
  world/        # Procedural archetype parameters only; never generated mesh vertices
scenes/apps/       # Authoring apps (run directly in Godot)
scenes/showcases/  # F6 visual demos — one playable inspect scene per feature
scenes/vessels/    # Hand-authored vessel scenes (trawler, catamaran)
```

### Visual demos (F6 pattern)

Every new system/feature should ship a **runnable inspect scene** under
`scenes/showcases/` (or `tests/` for pipeline demos that started there) so you
can F6 it in the editor, cycle examples, and review without launching the full
game.

Conventions:
- Self-contained: builds its own lighting / camera / HUD
- Keyboard cycling for variants (sizes, seeds, modes)
- No dependence on a running world scene, saves, or multiplayer. A showcase may
  invoke deterministic world generation when that context is the feature under inspection.
- Name it `<feature>_showcase.tscn` or `<feature>_visual_demo.tscn`

Current demos:
- `scenes/showcases/port_showcase.tscn` — terrain-traced port pipeline at real seeded coastal terrain sites
- `scenes/showcases/ship_showcase.tscn` / `player_showcase.tscn`
- `scenes/showcases/crane_showcase.tscn` — bulk grab + provision T-crane (containers)
- `scenes/showcases/marine_autopilot_showcase.tscn` — deterministic sea route + replicated progress viewer
- `tests/staged_vessel_visual_demo.tscn` — staged deck fitout construction

---

## Autoloads (Singletons)

Each autoload lives in its system folder and is registered in `project.godot`.

| Autoload | System | Role |
|---|---|---|
| `GameSettings` | `state/` | Client prefs plus session-only world seed/version/checksum handoff |
| `WorldWeather` | `weather/` | Deterministic weather query API: composed samples, routes, fronts, local projection |
| `WeatherLighting` | `weather/` | Smoothed local presentation only: sky, fog, ocean, audio, wind |
| `WorldClock` | `time/` | Game time. Emits `day_changed` + `hour_changed` (1 game hr = 60 real s) |
| `PortCatalog` | `port/` | Live port directory (ids, names, positions, spawn, commodities) |
| `FreightService` | `cargo/` | Authoritative accepted container movements and deterministic port offers |
| `PlayerSession` | `player/` | Persistent player data (marks, name, ship ledger, world clock). Autosaves every 60 s + on focus loss |
| `GameMenu` | `ui/` | Pause / map / settings / hint overlay |
| `GameState` | `state/` | Read model: player/ship/contract/world sub-states |
| `DebugHud` | `ui/` | F3 debug overlay |
| `Telemetry` | `state/` | Central debug/performance service: hardware samples, published metrics, peaks, context flags, events, and copyable reports |
| `LocalPlayerView` | `state/` | **The MP seam.** Per-client view of the local player's world. UI reads through here, not direct autoloads |
| `WorldGateway` | `network/` | Command/event/projection authority seam shared by local and remote backends |
| `Tutorial` | `state/` | First-time hint chain (fires once per captain, persisted) |

The autoloads listed above are the **actual** registered singletons. Do not reference `Economy`, `ContractBoard`, `FleetManager`, `ContractRegistry`, `PortOperations`, or `World` — those don't exist (or were purged).

### Convention — `LocalPlayerView` is the MP seam

UI code (HUDs, menus, debug overlays, hint banners) should **only** read per-player state through `LocalPlayerView`. Gameplay-mutating systems may consult autoloads directly — they're the world-authority side, not a per-client view.

Weather has a parallel read seam: gameplay/map queries call `WorldWeather.sample_at()` /
`sample_route()` / `active_fronts()`. Local VFX reads `WorldWeather.local_presentation`
(currently exposed by the `WeatherLighting` compatibility autoload). Never sample
`WeatherField` directly outside the weather implementation.

### World generation contract

`WorldLayoutGenerator.generate(seed)` creates the immutable 40×40 km
`WorldLayout`: macro SDF, terrain heights, coastline contours, regional tags,
and waterway graph. It is the shared geographic truth for terrain, `LandField`,
ports, charting, weather, and navigation.

- `CoastalPortPlacer` places `PortDefinition` sites (pose, size class, region); local `-Z` faces water.
- `PortExpander` derives seeded attributes + `PortTradeProfile`, then `PortLayoutGenerator` traces the coast, fits a foundation, and builds `berth_plan` (asphalt pads + dedicated quays) plus `land_plan` (inland buildable zone covering apron + hinterland) on a foundation-anchor `PortLayoutGraph`.
- `PortLayoutGraph` holds the foundation anchor plus layout attrs (`berth_plan`, `land_plan`, basin, coast polylines). Persist/sync this graph, never generated meshes. Module attach/open-slot APIs are reserved for later growth — they are not how trade berths are placed today.
- `PortLayoutGraphVisualizer` stamps foundation, berth pads/quays, cheap inland land decor (primitive houses + trade yards from `land_plan.terrain_grid`), and debug gizmos (including the land buildable zone). This is intentionally the only port presentation for now.
- `WorldTerrainStreamer` owns 1 km terrain chunks, LOD, nearby collision, and layout footprint flattening.
- `LandField.wave_shelter()` is short-range wave attenuation. Weather/fishing
  use `coastal_exposure()` / `directional_fetch()`.
- Do not reintroduce island-disk geography or per-port weather calm.
- Seed + generation version + layout checksum identify a world. Coordinate
  saves must not restore into a mismatched context.

### Port pipeline contract

Ports follow a strict rebuild order:

1. **Seeded initial record** — site, size (clamped by geography × trade product count), destiny imports/exports
2. **Coast foundation + berth_plan** — shoreline fit, basin soft-clamp on pier length, asphalt vs dedicated quays from unlocked trade
3. **Layout visualization** — foundation, berth pads/quays, inland land decor from `land_plan` (primitive houses + trade yards on terrain), optional site gizmos
4. **Gameplay functionality** — explicitly deferred (operable businesses, NPCs)

Do not regenerate a finished harbour after players modify it. Seed generation
creates only the initial graph + berth plan; later growth must persist the evolved record.

Trade contracts and harbour NPCs are purged for now. Starter vessels come from
`PlayerSession` / `VesselSpawn`. Commodity packing/pricing lives in `CommodityCatalog`.

`CargoConsignment` is the JSON-safe authority record shared by freight families.
Physical `ContainerUnit`s and `BulkCargoLot`s reference its `consignment_id`; do
not derive payment or routing authority from scene nodes. A future server should
issue/revise consignments and validate delivered cargo.

---

## Vessel System — Deck-grid bricks + outfit budget

Hulls are reusable geometry components, not ships. A finished store ship (prebuilt)
combines one `hull_id` with a name, price, `shaft_power_kw`, and **1×1×1 m brick
grid**. Many differently powered and outfitted ships may share the same hull.

A vessel is a **fair, registered data model** (same hard rules for official store ships and UGC):

1. **Hull** — geometry platform (L×B), physical `ShipClass`, and outfit ceiling
2. **Registration** — declared before building; legal requirements and stricter limits
3. **Brick layout** — visuals + which slots are filled (surplus functional gear fails validate)
4. **Live components** — `DeckFitout` mounts only compliance-accepted slots
5. **Discovery** — gameplay asks `BoatBody` (`get_fishing_systems()`, `get_cargo_pads()`,
 `get_bridge_stations()`), never hunts brick names

| Slot (v1) | Budget rule |
|---|---|
| `fishing` | max 1 |
| `helm` | max 1 |
| `cargo_cells` | container pads + bulk holds (deck metres; y = 0 pads only) |
| `crane` / `tow` | 0 until those systems exist |

`VesselCompliance.validate` is the final authority. It intersects the hull budget from
`VesselOutfit` with the declared rules in
`resources/data/vessels/registrations/catalog.json`. `BrickRules` is its editor wrapper.
Illegal or unregistered ships hard-fail save, commission, and deployment; spawn still
mounts only accepted slots so network/save cheats cannot activate surplus gear.

`ShipClass` means physical berth/length category. `registration_id` means legal
operating type (`general_vessel`, `fishing_vessel`, `cargo_vessel`,
`passenger_vessel`). Never infer registration from installed bricks.

Run `scenes/apps/vessel_registration_audit.tscn` to edit the source-controlled legal
code and batch-audit every official prebuilt. Registration reports are derived, never
stored as a stale “passed” flag.

Official prebuilts are authored in `ShipyardBrickEditor` and sold from
`resources/data/vessels/prebuilt/`. The owned-vessel ledger persists the hull,
power, and `brick_layout`; spawn rebuilds via `VesselSpawn` + `DeckFitout`.

```gdscript
var boat := VesselSpawn.instantiate_from_record(owned_vessel_record)
get_tree().current_scene.add_child(boat)
boat.place_at_waterline(water_y)
```

| Always on BoatBody (core) | Brick fit-out (player) |
|---|---|
| Hull visual + collision | Wall / window / door / ledge / railing bricks |
| Strip buoyancy + hydro | Container pads + bulk holds (within cargo_cells) |
| Propulsion, rudder, thruster | Fishing trommel → one FishingSystem when accepted |
| BoatController / Camera / Audio | Enclosed cabin + door → helm boarding |
| MooringComponent + auto cleats/lights | |
| WalkDeck | |

Operating role comes from declared registration plus a passing checklist, not kit ids. Do **not**
revive `WheelhouseVisual`, hull JSON `bridge` slots, `ShipBuilder`, `VesselKits`,
`VesselLoadout`, or the attachment socket stack.

New hull platforms belong in `resources/data/vessels/hulls/catalog.json` and use
dimension-based ids such as `hull_90x24`. Do not name hulls after cargo, tanker,
fishing, passenger, or other ship roles. Do not add new hand-authored vessel
scenes for store stock; the trawler and catamaran scenes are frozen exceptions.

`BrickCatalog` is the shared construction kit for vessel decks and land buildings. Marine-only pieces carry the `ship_only` tag and are filtered out of the building editor palette.

### Vessel orientation

**Bow = −Z, Stern = +Z, Port = −X, Starboard = +X.** Grid cells are vessel metres.

### Navigation and autonomous vessels

`MarineRoutePlanner` produces deterministic `MarineRoutePlan` data from the
shared `WorldLayout`. `VesselAutopilot` is the only passage route follower for
both player and NPC vessels; do not create separate player/NPC steering math.
Compact authority snapshots send route identity, endpoints, progress, pose, and
algorithm/layout versions so clients can rebuild and verify the route locally.

`ShippingLaneNetwork` is the newer traffic-infrastructure authority. It derives
quay manoeuvre blocks, port gates, holding queues, connectors, directional
highways, regular signals, and chain signals from the immutable `WorldLayout`
plus seeded port berth plans. The network is data only: **do not attach an
autonomous vessel controller to it until the traffic layout has been reviewed.**
`ShippingLaneReservationService` is likewise a pure atomic reservation model,
usable by a local single-player authority or a persistent server. Clients may
render the network and consume authority snapshots, but must not independently
resolve reservations or collision outcomes.

`AutonomousVesselCaptain` layers harbour procedure around that shared follower:
reserve berth → release lines → crab clear → passage → acquire approach lane →
align/crab in → secure lines. `HarbourController` owns berth reservations and
exclusive manoeuvre-lane leases. Player passage autopilot carries a three-minute
`BridgeWatchAlarm`; NPC captains own their watch continuously and do not use it.

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

Persistence flows through `PlayerSession.save_now()` → `_snapshot_into_player_data()` (via `LocalPlayerView`) → `PlayerSaveStore.save_player()`. The save envelope is `{version, player, saved_at_unix}`; format version is currently **6**. See [`SAVE_FORMAT.md`](SAVE_FORMAT.md) for the field schema and upgrade behaviour.

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
| `boat_autopilot_toggle` | P | Engage/disengage active freight route autopilot |

Add new actions to `project.godot` directly; there is no separate input-map JSON.
