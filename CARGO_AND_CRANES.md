# Cargo & Cranes — Design Draft

Status: draft for review. Not implemented.

Goal: replace the player-carry placeholder with a crane-driven, palletized, grid-based cargo system that scales from a 5-pallet coastal trader to a hundreds-of-pallets freighter without becoming busywork or collapsing into "click to autofill."

---

## Core Idea

Cargo is **palletized**. The pallet is the atomic unit the crane moves. The ship's cargo deck is a **grid**. Loading is **Tetris**: pallets have footprints, multiple cargo types and multiple destinations share the same deck, and the player decides how to pack it.

Crane operation is **active gameplay** — position the hook, hook the four corners, lift, swing, place. One swing moves one pallet, but one pallet equals many crates of throughput. The skill ceiling is in speed and precision of operation, plus packing strategy.

Consequences this unlocks:
- Multi-pickup at a single port (several contracts, one ship)
- Multi-destination routes (cargo for ports A, B, C on the same deck)
- Load order matters (don't bury port A's pallets under port C's)
- Bigger ships are meaningfully different to load, not just "the same thing for longer"
- Mixed cargo types compete for deck space, forcing trade-offs

---

## Pallet

The atomic cargo unit.

### Data

```
Pallet {
    id:               String     # uuid
    cargo_type:       String     # "general", "timber_bundle", "drum_cluster", "container_20ft"
    commodity:        String     # "grain", "timber", "iron_ore" — references ContractRegistry.COMMODITIES
    footprint:        Vector2i   # grid cells, e.g. (1,1), (2,1), (1,2)
    height_cells:     int        # vertical cells consumed (stackability)
    mass_kg:          float
    contract_id:      String     # which contract this pallet belongs to
    destination_port: String     # where it gets paid out
    sling_points:     Array[Vector3]  # 4 local corners the crane hook latches to
    visual_mesh:      String     # JSON mesh path
}
```

### Standard footprints (first pass)

| Pallet type | Footprint | Height | Notes |
|---|---|---|---|
| `general` | 1×1 | 1 | Default. Crates, sacks, drums on a wood pallet. |
| `timber_bundle` | 2×1 | 1 | Break-bulk. Long. |
| `drum_cluster` | 1×1 | 1 | Heavier than general per cell. |
| `container_20ft` | 2×1 | 2 | Containers stack better but need gantry-capable berths. |
| `container_40ft` | 4×1 | 2 | Only on Handysize+. |

Bulk cargo (coal, iron ore, grain) does **not** use pallets — it uses dedicated bulk holds + a grab crane. Out of scope for this doc; see "Future" section.

---

## Ship Cargo Deck Grid

### Grid definition

`CargoDeckComponent` already exists and is placed at the hull's `cargo_main` (and optionally `cargo_aft`) slot by `ShipBuilder`. Extend the hull slot to carry grid dimensions:

```json
"cargo_main": {
    "position": [0.0, 1.1, 0.0],
    "grid": {
        "cells_x": 3,         // beam-wise (port↔stbd)
        "cells_z": 6,         // length-wise (bow↔stern)
        "cells_y": 2,         // stack height
        "cell_size": 1.4      // metres per cell at scale=1
    }
}
```

`ShipBuilder` multiplies `cell_size` by the template `scale`, identical to how it already handles slot positions. A scale-2 fuel tanker on a 3×6×2 base gives 3×6 cells of 2.8 m each — gives the same number of pallets but they're physically bigger.

### Grid suggested per hull class (starting point)

| Class | cells_x | cells_z | cells_y | Total slots |
|---|---|---|---|---|
| Coastal Trader | 2 | 3 | 1 | 6 |
| Short Sea Coaster | 3 | 5 | 1 | 15 |
| Handysize Feeder | 4 | 8 | 2 | 64 |
| Deep Sea Freighter | 6 | 14 | 3 | 252 |

Numbers are illustrative — they're tuned per hull JSON.

### Placement rules

- A pallet occupies `footprint.x × footprint.y` cells on the deck plane and `height_cells` stacked.
- Placement is valid if all required cells are free and supported (cells below are filled or it's the deck).
- The ship's mass distribution updates as pallets are placed: total cargo mass adds to `BoatBody.mass`; centre-of-mass shifts horizontally based on pallet positions. **This couples loading to handling** — front-heavy load = bow-down trim, lopsided load = list. Ties into the existing physics model.
- Hard limit on total mass per hull (`max_cargo_mass_kg` in ship template).

### Visual

- Grid lines drawn on the deck surface (low-opacity decal or shader). Visible at all times when ship is at berth; faded out at sea.
- Pallet at hook end shows a **footprint ghost** projected down onto the deck — green if valid, red if blocked.
- Each pallet's destination is colour-coded on its top face. Port A = teal, port B = amber, port C = magenta, etc.

---

## The Crane

### Dock crane

One general-cargo crane per general berth. Lives in `PortDock`, instantiated alongside the berth.

**Anatomy** (all primitives, in keeping with the project's visual rule):
- **Base** — fixed concrete pad at the quay edge
- **Tower** — vertical mast
- **Slew** — rotates around the tower (yaw)
- **Boom** — angled arm extending from the slew (luff angle controls reach)
- **Trolley** — slides along the boom (radius from tower)
- **Hoist** — cable down from the trolley to the hook
- **Hook frame** — 4-point spreader with four sling lines that attach to a pallet's corners

### Reach

A dock crane needs to cover:
- The **cargo apron** behind it (where pallets spawn from the warehouse)
- The full **footprint of the berthed ship** at the quay

Reach = max trolley radius. Slew = 270° (can't swing into the tower). Crane specs are in the dock JSON so different ports can have different crane sizes.

### Operation

Player walks to a **control booth** at the base of the crane and interacts (E). Camera moves to an over-shoulder operator view. The crane becomes the controlled entity until the player exits.

Controls (first pass — open to revision):
- **A/D** — slew left/right
- **W/S** — trolley out/in
- **Space (hold)** / **Ctrl (hold)** — hoist up / down
- **E** — engage/release hook (latches to a pallet's sling points if all four are in range; releases held pallet onto valid grid cells)
- **Shift** — precision mode (slower, finer control)
- **Q** — exit crane

Operation can be physics-driven (cargo actually swings on cables, requiring careful slewing) or kinematic-snap (hook treated as a kinematic body, no swing). **Recommendation: physics-driven, with a strong damping coefficient.** Swing penalises sloppy operation but doesn't make the crane unusable. This is a major feel decision — call out for the user.

### Pickup logic

1. Player positions hook above a pallet.
2. Lowers hook until all four sling lines reach the pallet's `sling_points`.
3. Presses E. If all four points are within a tolerance radius, lines attach and the pallet is now "rigged".
4. Player hoists, slews, places.
5. To release: position over deck cells, lower until pallet contacts deck or stack below, press E. If footprint is valid, pallet is dropped and registered with the `CargoDeckComponent`. If invalid, release fails (visual flash).

### Crane state

`Crane` node — child of `PortDock`, one per crane-typed berth.

```
Crane {
    base_position:  Vector3
    slew_yaw:       float      # current rotation, radians
    boom_pitch:     float
    trolley_radius: float
    hoist_height:   float
    hook_position:  Vector3    # computed from above
    mechanism_profile: MechanismProfile   # describes allowed DOFs (luffing, gantry, …)
    tool:           CraneTool              # end effector hanging from the cable
    max_radius:    float
    max_lift_kg:   float       # crane has a capacity — heavier loads refused
}
```

---

## Crane Architecture — Same Base, Different Tool

A coal berth, a container terminal, and a general-cargo berth all need a crane, but the cargo they move is fundamentally different. The architecture below makes that one system, not three forks.

### Three layers

1. **Crane mechanism** — base, tower, slew, boom, trolley, hoist, cable. Pure kinematics. Knows nothing about cargo.
2. **CraneTool** — the end effector that hangs from the cable. Defines what "pickup" and "release" mean for one kind of cargo. Polymorphic.
3. **CargoEndpoint** — abstract Source/Sink the tool interacts with: pallet apron, bulk pile, container yard, ship's pallet grid, ship's bulk hold, ship's container slot.

The crane operates the cable. The tool operates the cargo. The endpoint validates whether the cargo can come or go.

### Tools

| Tool | Pickup verb | Cargo handled | Notes |
|---|---|---|---|
| `SlingHookTool` | 4-point latch on pallet corners | Palletized general & break-bulk | The Phase 1 tool. |
| `GrabBucketTool` | Lower-into-pile, close clamshell | Bulk: coal, iron ore, grain | Volumetric. Rhythm-based. |
| `ContainerSpreaderTool` | Twistlocks at 4 container corners | ISO containers | Snap-to-corners, fastest cycle. |
| `HookTool` | Single hook + manual sling rigging | Awkward break-bulk (single drums, bundles) | Slow, fiddly. Niche. |
| `MagnetTool` (future) | Energise / de-energise | Scrap metal | One-shot lift, no precision. |

A tool implements two methods:

```gdscript
class_name CraneTool extends Node3D

func try_pickup(endpoint: CargoEndpoint) -> bool: ...
func try_release(endpoint: CargoEndpoint) -> bool: ...
func get_held_mass_kg() -> float: ...
func get_hud_state() -> Dictionary: ...   # tool-specific operator UI
```

### Endpoints

| Endpoint | Holds | Accepts tools |
|---|---|---|
| `PalletApron` | gridded pallets (no stack) | `SlingHookTool`, `HookTool` |
| `PalletGrid` (ship deck) | pallets in grid, optional stack | `SlingHookTool`, `HookTool` |
| `BulkPile` | volume of one bulk commodity | `GrabBucketTool` |
| `BulkHold` (ship) | volume per hold, single commodity when in use | `GrabBucketTool` |
| `ContainerYard` | container stack | `ContainerSpreaderTool` |
| `ContainerSlot` (ship deck) | one container | `ContainerSpreaderTool` |

An endpoint implements:

```gdscript
class_name CargoEndpoint extends Node3D

func can_offer_pickup(tool: CraneTool) -> bool: ...
func offer_pickup(tool: CraneTool) -> Variant: ...     # returns whatever the tool now holds
func can_accept_release(tool: CraneTool, world_pos: Vector3) -> bool: ...
func accept_release(tool: CraneTool, world_pos: Vector3) -> bool: ...
func accepted_tool_types() -> Array[String]: ...
```

### Compatibility & berth typing

- Each **Tool** declares `handled_cargo_types`.
- Each **Endpoint** declares `accepted_tool_types`.
- A **berth** is typed in the dock JSON (`general`, `bulk`, `container`, `mixed`). That type selects which crane mechanism + tool is installed.
- The harbour master already refuses ships carrying cargo the port can't handle. Now that refusal is grounded in real endpoint/tool compatibility.

### Mechanism profiles

The kinematics differ across real-world crane *forms*, but the same `Crane` class can express them all via a profile:

| Profile | Slew | Boom luff | Trolley | Notes |
|---|---|---|---|---|
| `dock_luffing` | 270° | yes | yes | The first crane. |
| `gantry` | 0° (none) | none | yes (along fixed beam) | Container terminals. |
| `level_luffing_portal` | 270° | yes (parallelogram — hook stays level) | yes | Big general-cargo ports. |
| `floating_heavy_lift` | 360° | yes | optional | Mounted on its own barge, sailed into position. Late game. |
| `derrick` | 180° | yes | no (cable directly off boom tip) | Onboard ship cranes. |

The Crane is one class. The profile decides which DOFs are active and what UI controls map to them. Visual variants are JSON-driven (same as hulls).

### Bulk loop specifics

Worth calling out because it's the most different from sling work:

- A **BulkPile** is a procedurally generated mound mesh. Volume drains as grabs happen; mesh visibly shrinks.
- A **BulkHold** is a sealed compartment on the ship with a fill level (0–1) and a single commodity locked in for the trip.
- `GrabBucketTool` has a `bucket_capacity_kg`. One full grab cycle: lower into pile (must be deep enough), close (animated, half-second), lift, swing, position over hold opening, open (dump). Bucket capacity scales per port — small coal berth has a 2-tonne bucket, industrial port has a 20-tonne bucket.
- Rhythm gameplay — many cycles per delivery, find the optimal arc that doesn't overshoot. Different feel from precision pallet placement, intentionally.
- Conveyor automation (much later): a `Conveyor` endpoint links a `BulkPile` to a `BulkHold` and moves volume over time. The player sets it up, then walks away. Slower than active grabbing, but hands-free. Mirrors the "hire a captain" pattern.

### Adding a new tool

1. Subclass `CraneTool`. Implement `try_pickup`, `try_release`, `get_held_mass_kg`, `get_hud_state`.
2. Declare which cargo types it handles.
3. Add endpoint subclasses if no existing endpoint can produce/consume that cargo form.
4. Add a berth type entry (or extend an existing one) and reference the new tool.

The crane mechanism, operator booth, camera, control bindings, mass-into-ship physics, and contract payout flow are **untouched**. New cargo paradigms don't ripple through the system.

---

## Dock Cargo Apron (pallet staging)

The apron behind a crane is where pallets queue. Today this is a flat area; with palletization it gets a grid too — but a simpler one, no stack.

When the player accepts a contract from the contract NPC:
1. The contract spawns its pallets on the apron belonging to the contract's pickup berth.
2. If apron is full, contract acceptance is blocked or pallets queue in the warehouse.
3. Pallets remain on apron until the player cranes them onto a ship.
4. If pallets sit on the apron too long, demurrage fee or contract penalty (later — out of scope v1).

---

## Unloading at Destination

At a destination port:
1. Player berths.
2. Walks to crane control booth.
3. Cranes pallets off the ship onto the destination's cargo apron.
4. When a pallet's `destination_port` matches the current port and it lands on a valid apron cell, the contract registers a delivery (`ContractRegistry.unit_delivered`). Reward credits hit `PlayerSession.marks`.
5. Pallets bound for other ports stay aboard.

This naturally creates the "don't bury other ports' cargo" tension. No special unload-all button.

---

## Multi-Destination Routes

A single ship's deck can carry pallets for multiple destination ports. The contract board at any port can offer contracts whose pickup is here but whose drop is elsewhere — and the player can stack several such contracts before sailing.

A **manifest panel** (hotkey or part of the map overlay) shows:
- Each pallet on deck — destination, commodity, mass, contract
- Grouped by destination
- Total mass, current trim/list

No optimal-route solver in the game. The player decides the route.

---

## Scaling Strategy

| Ship size | Loading time (estimate) | Crane swings | Feel |
|---|---|---|---|
| Coastal Trader (6 slots) | ~1 min | 6 | Fast, almost trivial |
| Short Sea Coaster (15) | ~3 min | 15 | A loading sequence |
| Handysize Feeder (64) | ~10 min | 64 | A session of loading |
| Deep Sea Freighter (252) | ~40 min | 252 | Hire a captain for it |

The Deep Sea Freighter time is intentionally large — that's where **hiring a port worker NPC** (late game) comes in. You pay them to load while you're off doing something else. Player can still do it manually if they want to.

This is the same arc as ship driving: in the late game you don't personally sail every route, you delegate. The crane mirrors that.

---

## Phasing

### Phase 1 — Prove the loop
- `Pallet` data + visual (one type: `general`, 1×1 footprint)
- Dock crane on one berth: base, slew, trolley, hoist, hook with 4 sling lines
- Player operation from control booth
- Ship `CargoDeckComponent` extended with grid (1×1 cells, no stacking)
- Pickup from apron → place on deck → sail → place on destination apron → contract pays out
- One general-cargo berth, one contract type
- Mass updates ship physics

**Acceptance:** a complete delivery using only the crane, with no player-carry fallback.

### Phase 2 — Mixed cargo & multi-destination
- Multiple pallet footprints (1×1, 2×1)
- Destination colour coding
- Manifest panel
- Accept multiple contracts to multiple destinations
- Trim/list from off-centre loading

### Phase 3 — Stacking & containers
- `height_cells` > 1 for stackable pallets
- Add `ContainerSpreaderTool` + `ContainerYard` / `ContainerSlot` endpoints
- Add `gantry` mechanism profile for container-typed berths (reuses `Crane` base)
- Different crane capacities per port

### Phase 4 — Bulk
- Add `GrabBucketTool` + `BulkPile` + `BulkHold` endpoints (reuses `Crane` base, same mechanism)
- Bulk-typed berths
- Wire `ContractRegistry`'s bulk commodities (coal, iron ore, grain) to bulk endpoints
- Conveyor endpoint as automated bulk-pile → bulk-hold link (optional)

### Phase 5 — Delegation
- Hire port workers to load/unload while player is away
- Configurable: "load all pallets bound for X, in this order"
- Costs marks; saves time

---

## How This Fits Existing Code

| Existing | Change |
|---|---|
| `CargoItem` | Becomes a property *on* a `Pallet` (or a `BulkParcel` for volumetric cargo). Pallet is the new physical unit; CargoItem stays as the contract-side accounting unit. |
| `CargoDeckComponent` | Gains a grid (`cells_x`, `cells_z`, `cells_y`, `cell_size`), an occupancy map, `place_pallet(pallet, cell)`, `remove_pallet(pallet)`, `get_total_mass()`, `get_centre_of_mass_offset()`. Specialises into `PalletGrid`, `BulkHold`, `ContainerSlot` variants — all are `CargoEndpoint`s. |
| `CargoPickup` | Replaced by pallet-spawning on the apron. Apron itself is a `PalletApron` endpoint. |
| `DeliveryZone` | Replaced by destination-port endpoints (`PalletApron`, `BulkPile`, `ContainerYard`). |
| `PlayerCarryComponent` | Removed in phase 1, once the crane loop is proven. Or kept for tiny coastal-trader special cargoes (chandlery resupply, mail bags). Open question. |
| `Contract` | Gains `pallets: Array[Pallet]` and `pickup_port_id`. Reward fires per pallet delivered, not on whole-contract completion. |
| Hull JSON `slots` | `cargo_main` and `cargo_aft` extended from `[x,y,z]` to a richer object with `position`, `grid`, and `endpoint_type` (`pallet_grid` / `bulk_hold` / `container_slot`). `ShipBuilder._read_slots` updated to accept both forms. |
| `PortDock` | Per-berth crane spec: mechanism profile + tool type + apron/endpoint spec. Drives Crane and Endpoint instantiation. |
| Ship template `cargo_decks` | Array of deck slot names — unchanged. Grid and endpoint type come from the hull. |

New abstractions introduced:

- **`Crane`** — mechanism, takes a `MechanismProfile` + a `CraneTool`. One class for all crane forms.
- **`CraneTool`** (base) → `SlingHookTool`, `GrabBucketTool`, `ContainerSpreaderTool`, `HookTool`, …
- **`CargoEndpoint`** (base) → `PalletApron`, `PalletGrid`, `BulkPile`, `BulkHold`, `ContainerYard`, `ContainerSlot`
- **`MechanismProfile`** — describes which DOFs the crane has and their limits (luffing, gantry, etc.)

---

## Open Questions

1. **Crane control scheme.** WASD + space/ctrl (described above)? Or mouse-driven (drag hook in 3D space)? Or two-stick gamepad-style? The feel of operation is the most important thing to get right.
2. **Cable physics.** Pallet swings on cables (realistic, punishes sloppy slewing) vs. kinematic hook (snappy, predictable)? My recommendation is physics with strong damping but it's a feel call.
3. **Cell size.** What's a pallet's physical footprint? Real-world Euro pallet is 1.2 m × 0.8 m, ISO container is 6 m × 2.4 m. I've sketched 1.4 m cells (close to a US pallet). Open to changing.
4. **Stacking rules.** Can any pallet stack on any pallet? Or do stackable pallets need a flat top (containers stack, drums don't)?
5. **Keep player-carry for anything?** Tiny items, captain's personal stores, single-crate odd jobs?
6. **Cargo securing.** Pallets unsecured at sea = shift around in heavy weather? Or treat all loaded pallets as fixed? (Securing as a mechanic could be cool but adds friction.)
7. **Crane access.** Walk to a control booth and interact, or sit in a captain's-chair-style cab high up on the crane? The booth is simpler; the cab feels more like the game's existing helm pattern.
8. **Visibility of the hook from the control position.** Realistic crane operators have terrible sight lines and rely on signalmen. Do we lean into that (camera locked to operator's view) or grant a free over-shoulder camera?
9. **Multiplayer.** One player drives the ship, another operates the crane? Worth designing for now or defer? Pallet ownership and crane state are the things multiplayer would touch first.
10. **Bulk cargo timing.** Build the grab-crane mechanic in Phase 4 as drafted, or earlier — given bulk cargo (coal, iron ore, grain) is already in `ContractRegistry.COMMODITIES`?

---

## What I'd Build First (Phase 1, in branch order)

1. `Pallet` resource + a primitive visual (a wood-coloured slab with four corner posts as sling points).
2. Extend hull slot format: `cargo_main` accepts `{ position, grid }`. Update `ShipBuilder._read_slots`. Update `hull_coastal_trader.json` as the test bed.
3. `CargoDeckComponent.grid` — occupancy, placement validation, mass aggregation, COM offset to `BoatBody`.
4. Apron grid in `PortDock`, one per general berth.
5. `Crane` node — pure kinematic for v1 (slew, trolley, hoist), hook as kinematic body. Add cable physics in phase 1.5 if it doesn't break the feel.
6. Crane control booth interactable. Camera mode switch on interact.
7. Pickup/release logic with 4-point sling check.
8. Rewire `Contract` to spawn pallets on the pickup apron instead of crates in front of the player.
9. Rewire delivery: pallet placed on destination apron registers as delivered.
10. Decommission `PlayerCarryComponent` (or scope it down to special items per Q5).

End of Phase 1: one full delivery — accept contract, crane pallets onto coastal trader, sail to destination, crane pallets onto destination apron, get paid. No player-carry fallback.
