# Angst 'n Anchors

A maritime trading game built in Godot. The player drives a boat, picks up cargo at one port, and delivers it to another. Ships are assembled at runtime from modular JSON parts so players (and the dev) can build custom vessels without touching the scene editor. The long-term goal is an MMO.

---

## Pillars

1. **Driving the boat is the game.** Physics-driven helm — propulsion, rudder, bow thruster, hydrodynamics, buoyancy on a wave surface. Distance and weather matter. Sailing the route yourself is the loop.
2. **Cargo delivery between ports.** Buy or accept a contract at one port, load, sail, unload, get paid. Spot trading and contract board both exist as concepts; contracts are the working path in code today.
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
| `cargo_zone` | Deck cargo rectangle (corner A → B) |
| `crane_base` / `crane` | Ship-mounted crane |

### Available hulls

Generic platforms live in `resources/data/vessels/hulls/catalog.json` with dimension-based ids such as `hull_90x24`. The trawler and catamaran scenes are frozen exceptions; new store stock uses catalog hulls.

### Ship components

Core on every vessel: `BoatBody`, buoyancy, hydrodynamics, propulsion, rudder, thruster, controller, camera, `MooringComponent`, walk deck, auto cleats/lights. Deck fit-out is a 1×1×1 m brick grid (`BrickCatalog` / `DeckFitout`) — walls, cargo tiles, crane, helm from layout. Shipwright fullscreen editor paints the grid; `BrickRules` keeps builds legal.

### Authoring entry points

- **By hand:** author a vessel scene/script with a deck grid; register it in `HullRegistry`.
- **In-game:** Shipwright catalog → fullscreen brick editor → commission writes `brick_layout` on the ledger. Harbour Master deploys via `VesselSpawn` + `DeckFitout`.

---

## Ports & World

- **`world.tscn`** is the runnable scene. `World` generates port definitions from a seed (default `world_seed=42`, `port_count=35`) and uses `ProximityLoader` (radius 1500) to instantiate ports near the player. The home port loads eagerly.
- **`PortPlot`** is the composition root for one port: ground polygon (organic visual, box collision), `PortDock` on the water side, `PortFacilities` on the land side. Driven by `port_size` (0–4) and plot dimensions.
- **`PortDock`** owns berths, typed cranes (placeholder), cargo aprons, fuel point. Berth slots sized to the port's max ship class.
- **Ship classes** (`ShipClass.Type`): `COASTAL_TRADER`, `SHORT_SEA_COASTER`, `HANDYSIZE_FEEDER`, `DEEP_SEA_FREIGHTER`. `port_size → max ship class` mapping lives in `PortPlot.SHIP_CLASS_BY_SIZE`.
- **Port NPCs:** `HarbourMasterNpc` (berth assignment, vessel info, dues — VHF planned), `ShipwrightNpc` (commission ships), `ContractNpc` (post / accept contracts), `DeliveryNpc`, plus a `Warehouse` with `WarehouseContractZone`.
- **Port facilities (props):** `FuelStation`, `LighthouseBuilding`, `FogHornBuilding`.
- **Naming:** Norwegian-style names from a fixed pool (`Holmvik`, `Sandvær`, `Bergnes`, …).

---

## Cargo & Contracts

- **`ContractRegistry`** (autoload) is the single source of truth for ports and contracts. No knowledge of the physical world.
- **Commodities** (current set): `grain`, `timber`, `iron_ore`, `coal`, `provisions`. Each has `mass_kg` and `value`.
- **Contracts:** `Contract`, `CargoItem`, `CargoManifest`. `MAX_ACTIVE_CONTRACTS = 3`, generation radius 3500.
- **Pickup / delivery:** `CargoPickup`, `DeliveryZone`, `CargoDeckComponent` on the ship, `PlayerCarryComponent` for the placeholder player-carry mechanic (until crane systems are built).
- **Player flow:** talk to a contract NPC → accept contract → pick up at warehouse → load onto ship → sail → unload at delivery port → reward.

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
| `ContractRegistry` | Ports and contracts (data only) |
| `PlayerSession` | Persistent player data (`marks`, name) |
| `GameMenu` | Pause / menu system |
| `GameState` | Read model: `player`, `ship`, `contract`, `world` sub-states |
| `DebugHud` | F3 debug overlay |

---

## Multiplayer / MMO Notes

- Berths have explicit state (free / reserved / occupied). Harbour master is the mediator, by design.
- `ContractRegistry` is a single registry — fits a server-authoritative model.
- `ShipBuilder` produces a deterministic ship from a template path — replicable across clients.
- Nothing networked is wired up yet. The architecture is the prep work, not the implementation.

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
