# CLAUDE.md — Angst 'n Anchors

Quick-start memory file for agents. Read this first, then go to source.
Full design: `Angst 'n Anchors.md`. Architecture: `ARCHITECTURE.md`. Agent rules: `AGENTS.md`.

---

## What the game is

Maritime trading game in **Godot 4.6** (GDScript, Jolt physics, Forward Plus renderer).
Player drives a boat, picks up cargo at one port, delivers it to another.
Ships are assembled at runtime from modular JSON templates — no hand-placed boat scenes for new ships.
Long-term goal: MMO. Architecture is being designed shared-session-aware from day one.

Runnable scene: `world.tscn`. Standalone port test: `port_test.tscn`. Hull comparison: `hull_lineup.tscn`.

---

## Current state (as of main — all branches merged)

**Working:**
- Physics-driven boat (strip buoyancy, hydrodynamics, propulsion, rudder, bow thruster, mooring)
- FFT ocean simulation with wave-height query
- Weather system (wind, rain, fog, lightning) with zone-based shelter
- Full port generation: procedural island terrain with heightmap + flat pad, dock, facilities, NPCs
- `ShipBuilder` pipeline: JSON template → complete `BoatBody` at runtime
- 8 hull sizes (13 m coastal trader → 60 m deep sea freighter) + 2 orphan hulls
- JSON-driven detailed bridge superstructures (16 parts each: deck house, funnel, mast, railings, etc.)
- Hull-declared cargo decks with correct per-hull dimensions
- `ShipLighting` wired: L cycles OFF / NAV / WORK / ALL presets; auto-nav at night/fog
- Scaled mooring bollards (0.7 → 1.5 across hull sizes)
- Shipwright NPC: catalog-driven ship commissioning; catalog params derived from hull geometry
- Articulated ambient walker NPCs with procedural walk animation at ports
- `ContractRegistry` autoload with port registry, 5 commodity types, contract generation
- Player carry component (placeholder — crates by hand until crane system)
- `Telemetry` autoload: 1 Hz performance + system-info sampling with ring buffer + load event API
- `DebugDraw` (F3): signal-driven redraws, HudStyle palette, system stats + loading log sections
- `WalkingHud`: signal-driven redraws (no per-frame polling)
- `MapOverlay`: `MapWeatherView` split out; weather rendering + grid cache separated
- `UiBuilder` static factory for maritime-styled UI fragments
- `ShipHud`: wind dial (bow-relative) + lights-preset badge
- `LocalPlayerView` autoload as multiplayer seam; `WalkingHud` migrated to it
- Perf pass: FFT grid at 512², LandField shelter baked to texture, lighthouse culling, volumetric fog skip

**Placeholder / not fully wired:**
- Fuel station building exists; no fuel consumption system
- `ShipData.hull_health` field exists; no damage/repair gameplay
- `PlayerCarryComponent` is the current cargo mechanic — to be replaced by crane system
- `DeliveryZone` / `CargoPickup` are the current delivery mechanism — will be replaced by crane + apron
- Fuel and depth gauges in `ShipHud` are placeholders (no fuel/bathymetry system yet)
- `ShipHud` and `DebugDraw` still reference `GameState`/`PlayerSession` directly (not yet migrated to `LocalPlayerView`)
- Map overlay: port panel, compass rose, scale bar not yet split into their own `MapXxxView` files

**Not started:**
- Crane system (designed in full in `CARGO_AND_CRANES.md` — Phase 1 is next)
- Palletized cargo grid on `CargoDeckComponent`
- Save / load
- Fuel economy
- Damage & repair
- Reputation / economy / pricing
- VHF radio / comms
- Networking / multiplayer

---

## Folder structure

```
scripts/
  core/         # Shared infra — no game knowledge (MeshTransformer, ModelAssembler, MeshBuilder, palette, interactable base, building_from_model base)
  player/       # CharacterBody3D controller, PlayerSession autoload, player data
  ship/         # BoatBody, controller, camera, propulsion, rudder, thruster, buoyancy, hydrodynamics, lights, audio, ShipBuilder
  ocean/        # FftWaterSystem, WaveSurface
  weather/      # WorldWeather + WeatherLighting autoloads, WeatherState, WeatherZone, rain, audio, HUD, debug presets
  time/         # WorldClock autoload
  world/        # World.gd (@tool), ProximityLoader, WorldRenderer, AtmosphericEffects
  port/         # PortPlot, PortDock, PortFacilities, FuelStation, LighthouseBuilding, FogHornBuilding
  npc/          # NpcBase, NpcInteractable, HarbourMasterNpc, ShipwrightNpc, ContractNpc, DeliveryNpc
  cargo/        # ContractRegistry autoload, Contract, CargoItem, CargoPickup, DeliveryZone, Warehouse
  ui/           # GameMenu + DebugHud autoloads, MapOverlay (+ map/ subdir), ShipHud, WalkingHud, UiBuilder, HudStyle
  state/        # GameState autoload, sub-states (PlayerState, ShipState, ContractState, WorldState), Telemetry autoload, LocalPlayerView autoload
```

NOTE: The above is the **target** structure from `SYSTEMS_AND_STRUCTURE.md`. The actual codebase (pre-migration on `fix/cleanup-folderstructure`) still has the old layout. Check what's real by looking at the files, not just the doc. The `fix/cleanup-folderstructure` branch was merged so the migration commit (`c354b41`) is on main — verify current paths in the editor/filesystem before assuming.

---

## Autoloads (registered in project.godot)

| Autoload | System | Role |
|---|---|---|
| `WorldWeather` | `weather/` | Wind, rain, fog state |
| `WeatherLighting` | `weather/` | Sun angle, sky colour, fog colour |
| `WorldClock` | `time/` | Game time |
| `ContractRegistry` | `cargo/` | Ports, contracts, commodities |
| `PlayerSession` | `player/` | Persistent player data (marks, name) |
| `GameMenu` | `ui/` | Pause / menu system |
| `GameState` | `state/` | Read model: player/ship/contract/world sub-states |
| `DebugHud` | `ui/` | F3 debug overlay |
| `Telemetry` | `state/` | 1 Hz perf + system info, load event timing |
| `LocalPlayerView` | `state/` | Per-client UI indirection (multiplayer seam) |

Do **not** reference `Economy`, `ContractBoard`, `FleetManager`, or `World` as autoloads — they don't exist yet.

---

## Ship building pipeline

```gdscript
var boat := ShipBuilder.build("res://resources/data/ships/fuel_tanker.json")
get_tree().current_scene.add_child(boat)
boat.place_at_waterline(water_y)
```

Three JSON layers:
1. `resources/data/models/hulls/<name>.json` — geometry parts + `slots` dict + `cargo_decks` array + `bollards` dict + `lights` array
2. `resources/data/ships/<name>.json` — hull ref, scale, physics params, superstructure key. Consumed by `ShipBuilder.build()`.
3. `resources/data/models/ships/<name>.json` — legacy wrappers, being phased out.

Hull JSON schema has been extended (ship-building-overhaul):
- `slots` — Vector3 attachment points (bridge, propulsion, bow_thruster, mooring × 4, cargo_main, cargo_aft, nav_light_bow)
- `cargo_decks` — array of `{ name, position, deck_width, deck_length, cell_size }` (replaces per-template deck lists)
- `bollards` — per-bollard `{ position, scale }` (scale is auto-derived from hull length if omitted)
- `lights` — array of `{ type, position }` (types: nav_port, nav_starboard, nav_masthead, nav_stern, work)

Superstructures are now JSON models at `resources/data/models/superstructures/bridge_*.json` loaded via `ModelAssembler`. The old `.tscn` bridge scenes in `scenes/shared/superstructures/` are retained as fallback but should be deleted after visual confirmation.

---

## Orientation — DO NOT GET THIS WRONG

**Bow = +Z, Stern = −Z, Port = −X, Starboard = +X.**

Hull mesh vertices are authored along local X (bow at +X). Every hull part uses `"rotation_degrees": [0, -90, 0]` to bake this into world space. Do NOT add extra rotation in ship model JSONs, ship template JSONs, or scene files.

`BoatController` negates throttle when sending to `PropulsionComponent` — this is correct and intentional (stage table convention). Do not remove the negation.

---

## Hull slots reference

| Slot | Purpose |
|---|---|
| `bridge` | Superstructure origin |
| `propulsion` | Propeller, stern, below waterline |
| `bow_thruster` | Bow tunnel thruster |
| `mooring_port_fwd` / `mooring_stbd_fwd` / `mooring_port_aft` / `mooring_stbd_aft` | Four mooring bollards |
| `cargo_main` / `cargo_aft` | Cargo deck origins (now also in `cargo_decks` array) |
| `nav_light_bow` | Bow nav light mast |

---

## Visual rules — hard constraints

- **No `.gltf` / `.glb` / `.fbx` / `.obj`. No imported texture files for in-world objects.**
- Geometry: Godot primitives (`BoxMesh`, `CylinderMesh`, etc.) in GDScript, OR JSON meshes under `resources/data/meshes/` loaded by `MeshTransformer`.
- Materials: `StandardMaterial3D` built at runtime. Shaders in `resources/shaders/`.
- JSON mesh format: `{ "vertices": [x,y,z,...], "indices": [i,i,i,...] }` — flat arrays, no normals, no UVs. `SurfaceTool` generates normals at load.
- Multi-part model format: `{ "parts": [ { "name", "mesh", "position", "rotation_degrees", "scale", "color", "roughness", "metallic", "collision" } ] }`
- `meshes/` contains ONLY `{vertices, indices}` files. `models/` contains ONLY `{parts}` files. No mixing.
- Do not hand-edit vertex data. Use the in-house mesh tool.

---

## Core code patterns

**State model:** UI subscribes to `GameState`. Systems write state. No UI polls the scene tree.
```gdscript
# BAD: var speed = $Ship/BoatBody.velocity.length()
# GOOD: var speed = GameState.ship.speed_knots
```

**Interactable pattern:** All "press E to do thing" goes through `scripts/core/interactable.gd`. Do not hand-roll prompt/interaction logic.

**Signals over direct calls:** Nodes communicate across system boundaries via signals or autoloads, not node paths.

**Data-driven:** Port definitions, ship templates, commodities live in `resources/data/`. Scripts read from data.

**Building-from-model pattern:** `LighthouseBuilding`-style buildings share `scripts/core/building_from_model.gd` base.

**Telemetry:** Use `Telemetry.mark_load_event(name)` / `Telemetry.end_load_event(handle)` around any slow spawn/load operations.

**Jolt concave shape warning:** Concave shapes are silently disabled on dynamic bodies in Jolt. Keep mesh collision shapes convex-friendly.

---

## What's next (priority order from design docs)

1. **Crane system — Phase 1** (`CARGO_AND_CRANES.md` §Phase 1): Pallet resource, extend `CargoDeckComponent` with grid, dock crane (kinematic), control booth, pickup/release with 4-point sling check, rewire Contract to spawn pallets on apron, rewire delivery to apron registration. Remove `PlayerCarryComponent` once loop is proven.
2. **Bridge JSON visual sign-off** — eyeball the 16-part bridge JSONs in-engine; delete `.tscn` bridge fallbacks once confirmed.
3. **Migrate ShipHud + DebugDraw to LocalPlayerView** (small lift, multiplayer prep).
4. **Further map_overlay split** — port panel and compass rose into their own `MapXxxView` files.
5. **Wire DialoguePanel to UiBuilder** so NPC dialogs match HudStyle.

---

## Active feature branches (all currently unmerged relative to each other — check git)

All listed branches show 0 commits ahead of main, meaning they have all been merged. There are no open unmerged feature branches as of the last log.

Branches that exist as remotes and may see future work:
- `origin/feature/cargo-cranes` — cargo/crane work (pallets, dock crane, grid cargo decks). Last commits were berth sign tuning; the full crane mechanics are unbuilt.
- `origin/feature/npc-system` — articulated walkers, shared dialogue panel (merged)
- `origin/feature/port-system` — heightmapped island terrain + flat port pad (merged)
- `origin/feature/weather-system-overhaul` — shelter, lightning, map weather chart (merged)
- `origin/fix/cleanup-folderstructure` — by-system folder migration (merged)
- `origin/perf/audit` — FFT, ocean, sky, fog, lighthouse performance passes (merged)

---

## Known issues / things to verify

1. **Folder structure migration status:** `fix/cleanup-folderstructure` is merged but the actual on-disk layout should be verified — the old structure (`scripts/systems/`, `scripts/entities/`, `scripts/autoloads/`, etc.) may still partially exist alongside the new layout.
2. **Bridge `.tscn` files retained:** `scenes/shared/superstructures/*.tscn` still exist as fallback. They should be deleted after visual confirmation of the JSON bridges.
3. **`hull_cargo_ship` and `hull_large` are orphan hulls** — now in the shipwright catalog (Phase 5 of ship-building-overhaul) but have geometry quirks: `hull_cargo_ship` has `cargo_fwd` instead of `cargo_aft`, no `nav_light_bow`. Double-check slot names before using.
4. **`scripts/util/` vs `scripts/utils/`** — duplicate folders (typo), should be merged into `core/`.
5. **Aft cargo deck bounding-box approximations** — deep_sea_freighter aft deck and cargo_ship small aft deck dimensions were estimated from bounding boxes; may need hand-tuning.
6. **No save/load system** — `PlayerSession.marks` persists but world state, contracts, cargo, and ship roster do not survive restarts.
7. **Crane control UX is unresolved** — `CARGO_AND_CRANES.md` open question #1: WASD + space/ctrl vs mouse-driven vs two-stick. Big feel decision; call it out to the user before building.
8. **Cable physics for crane** — open question #2: physics-driven (swing penalises sloppy operation) vs kinematic snap. Recommendation is physics with strong damping, but confirm before building.
9. **`BoatController` throttle negation** — intentional and documented. Do not remove it thinking it's a bug.
10. **MooringComponent bollard audit needed** — the component discovers cleats by group; should still work with the new scaled bollards but hasn't been verified post-ship-building-overhaul.
