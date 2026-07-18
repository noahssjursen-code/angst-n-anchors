# Angst 'n Anchors

A maritime trading game built in Godot. The player drives a boat, picks up cargo at one port, and delivers it to another. Ships are assembled at runtime from modular JSON parts so players (and the dev) can build custom vessels without touching the scene editor. The long-term goal is an MMO.

---

## Pillars

1. **Driving the boat is the game.** Physics-driven helm — propulsion, rudder, bow thruster, hydrodynamics, buoyancy on a wave surface. Distance and weather matter. Sailing the route yourself is the loop.
2. **Cargo delivery between ports.** Accept a movement at one port, load, sail, unload, get paid. First Freight currently generates deterministic container offers from compatible port exports/imports; physical crane-ledger integration is the active slice.
3. **Modular ship design.** A hull is a reusable L×B geometry component. Finished store ships add their own name, price, shaft power, and deck-brick fit-out; many ships with different roles and performance can share one hull.
4. **MMO is the destination.** State model (berth reservation, harbour master mediation, contract registry) is being designed shared-session-aware from the start, even though the game currently runs single-player.

---

## Tech Foundation

- **Engine:** Godot 4.6, GDScript only (no C#)
- **Physics:** Jolt
- **Renderer:** Forward Plus, D3D12 on Windows
- **Geometry:** primitives composed in code via `MeshBuilder`, plus in-house JSON meshes loaded by `MeshTransformer` / `ModelAssembler`. No GLTF/FBX/OBJ. No imported textures for in-world objects.
- **Materials:** `StandardMaterial3D` built at runtime — colour, roughness, metallic. Shaders in `resources/shaders/`.
- **Data-driven:** ports, ships, hulls, commodities, contracts live as JSON/`.tres` under `resources/data/`. Scripts read from data; they don't hardcode game content.
- **Event-driven state:** `GameState` autoload with `PlayerState`, `ShipState`, `ContractState`, `WorldState`. Systems write, UI subscribes — no polling.

---

## Vessel System (active focus)

Reusable hull components own SI geometry and core systems. Official store ships are authored in `ShipyardBrickEditor` by choosing a hull, painting a **1×1×1 m deck brick grid**, and setting product name, price, and `shaft_power_kw`. The shipwright sells those prebuilts. The ledger stores hull, power, and layout; `VesselSpawn` rebuilds the finished ship.

```gdscript
var boat := VesselSpawn.instantiate_from_record(owned_vessel_record)
get_tree().current_scene.add_child(boat)
boat.place_at_waterline(water_y)
```

Owned vessels persist `hull_id`, `shaft_power_kw`, and `brick_layout: { hull_id, cells }`. Role and appearance come from bricks. Do not revive socket kits, `VesselLoadout`, `WheelhouseVisual`, hull JSON bridge slots, or `ShipBuilder`.

### Vessel orientation

**Bow = −Z, Stern = +Z, Port = −X, Starboard = +X.** Grid cells are vessel metres.

### Deck bricks (starter catalog)

| Brick | Role |
|---|---|
| `block` / `block_window` / `block_door` | Cabin walls |
| `ledge_45` | Roof / sheer break |
| `railing` | Deck edge |
| `container_pad` | Deck container slot rectangle (corner A → B) |
| `crane_base` / `crane` | Ship-mounted crane |

### Available hulls

Generic platforms live in `resources/data/vessels/hulls/catalog.json` with dimension-based ids such as `hull_90x24`. The trawler and catamaran scenes are frozen exceptions; new store stock uses catalog hulls.

### Ship components

Core on every vessel: `BoatBody`, buoyancy, hydrodynamics, propulsion, rudder, thruster, controller, camera, `MooringComponent`, walk deck, auto cleats/lights. Deck fit-out is a 1×1×1 m brick grid (`BrickCatalog` / `DeckFitout`) — walls, container pads, bulk holds, crane, helm from layout. Shipwright fullscreen editor paints the grid; `BrickRules` keeps builds legal.

### Authoring entry points

- **By hand:** author a vessel scene/script with a deck grid; register it in `HullRegistry`.
- **In-game:** Shipwright catalog → fullscreen brick editor → commission writes `brick_layout` on the ledger. Harbour Master deploys via `VesselSpawn` + `DeckFitout`.

---

## Ports & World

- **`world.tscn`** is the runnable scene. `World` generates port definitions from a seed (default `world_seed=42`, `port_count=35`) and uses `ProximityLoader` (radius 1500) to instantiate ports near the player. The home port loads eagerly.
- Pipeline: `PortDefinition` (seeded site/size, geography×trade ceiling) → `PortTradeProfile` → `PortLayoutGenerator` (coast foundation + `berth_plan`) → `PortLayoutGraph`.
- **`PortPlot`** currently stamps foundation, asphalt pads, and dedicated quays from `berth_plan`.
- Trade berths are planned attributes, not socket-filled harbour modules. Later growth must persist the evolved graph/plan.
- Ports currently provide Harbour Master, Shipwright, and Cargo Agent services, mooring, and operable quay equipment. Final assets and persistent player-driven harbour growth remain deferred.
- **Naming:** Norwegian-style names from a fixed pool (`Holmvik`, `Sandvær`, `Bergnes`, …).

---

## Cargo & Contracts

- **`PortCatalog`** is the live port directory. **`CommodityCatalog`** owns commodity metadata (containers + bulk/liquid families, berth colours).
- General cargo is cubed **containers** (`ContainerUnit` / `ContainerNode`) on ship **`CargoSlotPadComponent`** grids. Bulk ore/coal/grain use hold systems separately.
- `FreightService` owns accepted movements. Cargo Agents only expose offers after the player's active vessel is physically moored at that port, and filter by berth commodity, installed cargo system, free capacity, and existing manifest reservations. Completed handling modes are general cargo, containers, and dry bulk (grain, iron ore, coal). Liquid movements remain filtered until tanker holds and liquid-terminal handling are playable.

---

## Player

- `CharacterBody3D` first-person controller (`scripts/entities/player.gd`). WASD + space + shift, mouse look, head bob, water rescue behaviour (player can't walk on water; gets pulled up after a short delay).
- Boards a ship via `BridgeInteractable` → `CaptainsChair`. Helm activation triggers `GameState.ship.data` population for HUD/UI.
- Inputs: `interact` (E), `load_ship` (K), `boat_thrust_left`/`right` (Q/R), `boat_docking_thrusters` (T), `open_map` (M).

---

## Autoloads (registered in `project.godot`)

| Autoload | Role |
|---|---|
| `WorldWeather` | World-level weather state |
| `WeatherLighting` | Lighting driven by weather |
| `WorldClock` | Game time |
| `PortCatalog` | Live port directory |
| `PlayerSession` | Persistent player data (`marks`, name) |
| `GameMenu` | Pause / menu system |
| `GameState` | Read model: `player`, `ship`, `contract`, `world` sub-states |
| `DebugHud` | F3 debug overlay |

---

## Multiplayer / MMO Notes

- Port catalog + seed-derived trade profiles fit a server-authoritative model.
- Nothing networked is fully wired yet. The architecture is the prep work, not the implementation.

---

## Project Layout

```
scenes/
  vessels/                   # Hand-authored vessel scenes
  shared/                    # player.tscn, npc_base.tscn
  systems/                   # port_dock, port_facilities, fuel_station, lighthouse, fog_horn
  ui/
  world.tscn                 # main scene

scripts/
  ship/                      # BoatBody, VesselSpawn, AttachmentMount, attachments/, vessels/
  port/  npc/  cargo/  player/  state/  ui/  world/  ocean/  weather/  time/  core/

resources/
  data/
    models/buildings/
    meshes/                  # primitive JSON mesh library by category
    lights/
  materials/  shaders/  themes/  audio/
```

---

## Reference Docs

- [AGENTS.md](AGENTS.md) — Guidance for AI agents working in this codebase. Visual rules, autoload conventions, vessel sockets/attachments.
- [resources/data/README.md](resources/data/README.md) — Data folder conventions.
- [resources/data/meshes/GUIDE.md](resources/data/meshes/GUIDE.md) — Mesh JSON authoring.
