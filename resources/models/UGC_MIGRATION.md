# UGC model migration

Historical planning notes: the accepted current hull, railing kit, paint contract,
and authoring rules are in `README.md` under "Ship model authoring contract".
The original 64 brick definitions have now been removed. The current trawler kit
has library placement, per-instance paint and draft saving; gameplay migration is
still incomplete. Older prototype inventories below are not the active catalog.

## Direction

Replace the game's old procedural/JSON model geometry with original Blender
assets. Players must still design custom boats. A single imported whole-boat
model or a baked cabin is not the construction system. The existing 64 bricks
are all candidates for retirement; matching their appearance or their exact
one-metre voxel restrictions is not a goal.

The new `parts/marine_kit/` is a first visual prototype, authored in Blender
from new geometry. Each asset has its own GLB and its own Blender source scene
under `_source/marine_kit/<asset_id>/`. The master `marine_kit.blend` contains
linked instances for inspection and an example custom layout. These files
are not yet connected to the live ShipyardBrickEditor, saves or multiplayer.

## Current construction path and replacement boundary

1. `HullRegistry` chooses either a hand-authored hull script or a catalog hull.
   `HullPhysicsProfile`/`HullStations` feed buoyancy, hydrodynamics, visual lofts
   and hull collision. `DeckGrid` supplies a tapered one-metre placement grid.
2. `ShipyardBrickEditor` freezes a hull preview and uses
   `BrickCatalog.create_visual()` for placed parts, ghosts and thumbnails.
3. `BrickLayout` stores brick IDs and grid cells, including occupied-cell
   markers for multi-cell pieces. Cargo pads and bulk holds have extra records.
4. `VesselSpawn` validates owned records and builds a BoatBody. `DeckFitout`
   creates each part's visual and then mounts its functional components.
5. `VesselCompliance`/`VesselOutfit` derive equipment counts and legal capacity
   from brick IDs, tags and placement. Saves/network replication preserve the
   layout rather than a baked combined mesh.

Keep those responsibilities explicit as implementations change. New UGC records
need stable model IDs, transforms, paint, equipment configuration and hull
identity. They should reference GLB assets, not embed vertices or a full
duplicated vessel mesh. Clients need the same versioned asset catalog. Unknown
assets, invalid equipment and incompatible layouts must not silently spawn.

The prototype uses real metres, 0.5 m horizontal snapping as a starting point,
2.2 m cabin panels and 65 mm walls. Placement origins sit on mounting planes;
the old cell-centre convention does not apply. Blender +Y is bow and +Z is up;
the GLB conversion gives Godot -Z bow and +Y up. Exported component origins and
dimensions are recorded in `parts/marine_kit/manifest.json`.

The current starter hull code uses a 2x feel scale (28 x 10 in-world metres for
a 14 x 5 label), despite WorldUnits claiming there are no feel multipliers.
The new hull is genuinely 14 m long. Physics, deck placement and berth handling
must be calibrated to that size before it becomes a playable vessel.

## Existing block families to replace

| Existing IDs/family | New visual approach | Gameplay that must survive/rework |
|---|---|---|
| `block`, `block_45`, `beam`, `foundation` | Thin 1/2 m wall panels, structural posts, real corner modules | Structural placement, mass and collision; stop treating every wall as a solid metre cube |
| `block_window`, `block_window_45`, `block_window_corner`, `block_windshield` | Window-wall panels, raked glazing and curved corners | Glass materials, line of sight, hull/cabin bounds |
| `block_door`, `block_door_double`, fixed variants | Door-wall assembly with independent leaf, frame, hinges and handle | `BrickDoor` currently expects `DoorHinge/DoorLeaf`; replace with a documented model adapter and synchronized open state |
| `floor`, flat roofs (3), sloped/inverted roofs (5), roof corners (6) | Thin deck/roof panels and purpose-built sloped/curved variants | Separate walk surface and collision. Flat prototype panels exist; slope/hip variants remain to model |
| `ledge_45` and four corner/inner variants | Purpose-built coamings, edge profiles and trim | Walk collision and joins; no obligation to preserve wedge IDs |
| `stairs`, `staircase`, `hull_ladder` | Realistically sized stairs and boarding ladder | Step height, head clearance, ladder/climb interaction; actual player traversal remains untested |
| `railing`, `railing_45`, `railing_mooring`, `bollard` | Tubular rails, corner rails and separate double bollards | Safety collision and mooring attachment anchors; mooring should not depend on a combined rail brick |
| `helm` | Instrument console, steering wheel, throttle and displays | Helm interaction area, control ownership and camera anchor |
| `passenger_seat`, `bench`, `table` | Marine seating, storage and furniture | Passenger capacity is explicit equipment metadata; table remains to model |
| Eight `light_*` IDs | Independent nav/work/interior light housings | Light emitters and aiming stay functional components; white nav and interior fixtures remain to model |
| `mast_base`, `mast_pole`, two chimney sizes | Signal mast, radome, aerial, exhaust sections | Attachment origins and mass; varying mast heights need compatible extensions |
| `container_pad`, `bulk_hold_6x12` | Cargo securing fittings, hatch/coaming, hold opening | Authoritative cargo zones/capacity and load/unload access. Hatch is modelled; pad fittings and bulk opening remain |
| `crane_base`, `crane` | Separate pedestal, slew, boom, cylinders, hook | Ship crane budget is currently zero; visual presence is not an implemented crane |
| `trommel_small` | Proper winch/drum/frame/hydraulic assemblies | FishingSystem, animated drum, net path and catch handling. Prototype winch is visual only |
| `deck_text`, three `wall_text*` IDs | Runtime lettering/decal attachment | Player-authored names must stay editable; do not bake `NAME` into a permanent model |

## Wider game scope

Replacement is not limited to ships. Existing JSON folders include buildings,
cargo, characters, dockyard and hulls; mesh folders additionally include cranes,
docks, foghorn, lighthouse, props and terrain. Procedural render builders are
also spread through ship, port, world, character, cargo and other systems.

Pending asset families: other hull sizes/forms, cranes and fishing machinery,
cargo/container sets, port buildings and businesses, quay/dock equipment,
lighthouses/foghorns, landscape props, vegetation and characters/wardrobes.
Terrain and ocean are continuous simulation surfaces; their generator/shader
integration must be evaluated separately from replacing placeable object models.
None of these wider families is claimed complete by this first marine kit.

## UGC example and validation limits

`parts/marine_kit/example_ugc_layout.json` is an illustrative placement record:
81 instances referencing the individual model IDs. Its cabin is assembled from
separate wall/window/door/roof pieces. It is not a new save-format contract.
The Blender sheet uses display scaling so small fittings remain visible; the
individual source/export files retain metre dimensions.

Models are visual prototypes. Mesh import checks and screenshots do not certify
watertight hull physics, collision, walking, door animation, naval stability,
performance budgets, networking, save migration or UGC validation. Those require
integration work. The current runtime has not had its models deleted yet.
