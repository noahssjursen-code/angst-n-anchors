# Angst 'n Anchors

A maritime trading game built in Godot. The player drives a boat, picks up cargo at one port, and delivers it to another. Ships are assembled at runtime from modular JSON parts so players (and the dev) can build custom vessels without touching the scene editor. The long-term goal is an MMO.

---

## Pillars

1. **Driving the boat is the game.** Physics-driven helm — propulsion, rudder, bow thruster, hydrodynamics, buoyancy on a wave surface. Distance and weather matter. Sailing the route yourself is the loop.
2. **Cargo delivery between ports.** Buy or accept a contract at one port, load, sail, unload, get paid. Spot trading and contract board both exist as concepts; contracts are the working path in code today.
3. **Modular ship design.** A ship = hull JSON + scale + superstructure key + component tuning. `ShipBuilder` assembles a complete `BoatBody` at runtime from a single template file. New hulls, new ships, new variants are all data.
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

## Ship Building System (active focus)

Ships are built from three layers of JSON:

1. **Hull JSON** — `resources/data/models/hulls/*.json`. Mesh parts, materials, collision, plus a `"slots"` dict of named attachment points at scale=1.
2. **Ship model JSON** — `resources/data/models/ships/*.json`. References a hull, applies scale. Used by existing `.tscn` scenes via `BoatBody.model_data_path`.
3. **Ship template JSON** — `resources/data/ships/*.json`. Full ship: hull, scale, superstructure key, physics, buoyancy, hydrodynamics, propulsion, rudder, bow thruster, camera, cargo decks. Consumed by `ShipBuilder.build()`.

### Pipeline

```gdscript
var boat := ShipBuilder.build("res://resources/data/ships/fuel_tanker.json")
get_tree().current_scene.add_child(boat)
boat.place_at_waterline(water_y)
```

`ShipBuilder` reads the template, loads the hull, multiplies slot positions by the template scale, and instantiates all components in one go.

### Orientation convention

**Bow = +Z, Stern = −Z, Port = −X, Starboard = +X.** Hull mesh parts use `rotation_degrees: [0, -90, 0]` to bake authored vertex orientation into world space. Do not add extra rotation in ship model JSONs or scene files. See [SHIP_BUILDING.md](SHIP_BUILDING.md) for the full convention and the historical bugs that have already been fixed.

### Hull slots

| Slot | Purpose |
|---|---|
| `bridge` | Superstructure origin |
| `propulsion` | Propeller, stern, below waterline |
| `bow_thruster` | Bow tunnel thruster |
| `mooring_port_fwd` / `mooring_stbd_fwd` / `mooring_port_aft` / `mooring_stbd_aft` | Four mooring points |
| `cargo_main` / `cargo_aft` | Cargo deck origins |
| `nav_light_bow` | Bow nav light |

### Available hulls

`hull_coastal_trader`, `..._long`, `hull_short_sea_coaster`, `..._long`, `hull_handysize_feeder`, `..._long`, `hull_deep_sea_freighter`, `..._long`, `hull_large`. Lengths range from 13 m up to 60 m at scale 1. Template `scale` multiplies hull dimensions and all slot positions.

### Ship components

Composed onto every built ship: `BoatBody` (RigidBody3D root), `BuoyancyComponent`, `HydrodynamicsComponent`, `PropulsionComponent`, `RudderComponent`, `BowThrusterComponent`, `BoatController`, `BoatCamera`, `MooringComponent`, mooring points, and `CargoDeckComponent` per declared cargo slot. Superstructure scenes live in `scenes/shared/superstructures/` (currently `bridge_small`, `bridge_medium`).

### Authoring entry points

- **By hand:** drop a template JSON in `resources/data/ships/`.
- **In-game:** the `ShipwrightNpc` at a port offers a catalog of hulls and writes a template to `user://shipwright_orders/`, then calls `ShipBuilder.build()`. Catalog selection only at this stage — there is no in-game free-mix UI yet.

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
  boats/                     # fuel_tanker.tscn, test_boat.tscn (legacy authored scenes)
  islands/                   # future: island compositions
  shared/                    # player.tscn, npc_base.tscn, superstructures/
  systems/                   # port_dock, port_facilities, fuel_station, lighthouse, fog_horn
  ui/
  world.tscn                 # main scene
  port_test.tscn             # standalone port test
  hull_lineup.tscn           # hull comparison scene

scripts/
  autoloads/                 # weather, clock, contract_registry, player_session, game_menu, debug_hud
  state/                     # game_state + player/ship/contract/world sub-states
  entities/                  # player, fog_horn
  player/                    # player_data
  systems/
    boat/                    # boat_body, controller, camera, propulsion, rudder, bow_thruster, buoyancy, hydrodynamics, cargo_deck, captains_chair, bridge_interactable, ship_light(ing), wave_surface
    dock/                    # port_dock, harbour_master, shipwright, contract/delivery npcs, mooring, dock_facilities, ship_spawner, dock_cargo_ramp, dock_terminal
    cargo/                   # cargo_item, cargo_pickup, contract, delivery_zone, warehouse, warehouse_contract_zone
    port/                    # port_facilities
    player/                  # player_carry_component
    audio/                   # boat_audio_system, weather_audio_system
    weather/                 # rain_field, weather_hud, weather_state, weather_zone
    fft_water_system.gd, mesh_transformer.gd, model_assembler.gd, ship_builder.gd
  world/
    world.gd, world_renderer.gd, proximity_loader.gd, atmospheric_effects.gd
    mesh_builder.gd, island_mesh_builder.gd, palette.gd
    port/                    # port_plot, fuel_station, lighthouse_building, fog_horn_building
    npc/                     # npc_base, npc_interactable
  ui/  util/  utils/

resources/
  data/
    ships/                   # ship templates (fuel_tanker.json)
    models/
      hulls/                 # 9 hull JSONs with slots
      ships/                 # ship model JSONs (legacy wrappers)
      superstructures/       # bridge_small, bridge_medium
      buildings/             # foghorn_building, lighthouse_building
    meshes/                  # primitive JSON mesh library by category
    lights/
  materials/  shaders/  themes/  audio/  textures/
```

---

## Reference Docs

- [AGENTS.md](AGENTS.md) — Guidance for AI agents working in this codebase. Visual rules, autoload conventions, build discipline.
- [SHIP_BUILDING.md](SHIP_BUILDING.md) — Ship building system in depth: pipeline, slots, orientation, known historical bugs and their fixes.
- [resources/data/README.md](resources/data/README.md) — Data folder conventions.
- [resources/data/meshes/GUIDE.md](resources/data/meshes/GUIDE.md) — Mesh JSON authoring.
