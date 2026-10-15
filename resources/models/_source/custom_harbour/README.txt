CUSTOM HARBOUR KIT — 14 October 2026

Original, editable Blender geometry for the custom-port builder. Rebuild with
Blender background execution of build_custom_harbour.py. Individual .blend
sources and .glb exports remain separate reusable parts; no complete port mesh.
For a focused repair, append -- --only workshop_window_4m to the Blender command.
Other assets retain their existing exports and manifest records.

Units: metres. Blender +Y faces the water/exterior, +Z up. Exported Godot -Z
faces water/exterior and +Y up. Finished deck is y=0 for every placement.
Edge fittings descend beneath that datum. Roof tile underside is y=3m,
so building assembly does not introduce another user-selected build height.
Wall bays are 4m wide, 3m high. Roof tiles cover4x4m. Door opening1.32x2.30m;
open loading bay3.2x2.65m. Corner trim and gutters are independent fittings.

custom_harbour_assets.json records dimensions, footprint, snap, sockets,
physical collider boxes and bounds. DoorPivot/door leaf stay separate and the
moving collider follows the authored pivot. The fixed wall collider is split
around the opening. No invisible full-wall box crosses the doorway.

Use CustomHarbourAssetLibrary.instantiate() to apply shared materials and
collision; set_door_open() toggles the hinged door. The builder/authority owns
permissions and persisted open state. A visual does not create cargo quantity,
berth ownership, resource production or rescue gameplay.

Materials reuse approved marine source maps and provenance already under
resources/textures/marine. The local library applies Wood096 softwood to new
timber and vertical red cladding; existing global finish assignments are untouched.
Glass, lettering and optical parts retain their authored materials.

Existing port_kit/harbour_kit bollard, ladder, light, arch fender and drain are
referenced directly. No duplicate exported version of these assets is made.
Tractor tyre has a true open section, tread, linked chains and deck anchors.
Its close mesh is5240triangles. Godot imported mesh LODs are enabled. Small
fittings cull at220m, stock details360m and tall lights900m; their collision and
data remain independently present. Building shells do not use that small-item cutoff.

Review: tests/custom_harbour_asset_review.tscn -- --shipyard-playtest --capture
Six actual Godot views archive under Pictures/machinescreenshots. --verify runs
model/source/manifest dimension checks and tests door/open-bay collision without
opening a captain save. F6 controls1–6 views, right-drag orbit, wheel zoom, E door,
P archive screenshot. The plain water backdrop is review scenery, not game water.

DIAGONAL FOUNDATION TILES
Four additional Blender sources provide a foundation and a metal-edged quay
version of each shape. All use the 4 m grid and fixed finished deck Y=0.
Triangle footprint in Godot XZ: (-2,-2), (2,2), (-2,2), area 8 m2.
Chamfer footprint: (-2,-2), (1,-2), (2,-1), (2,2), (-2,2), area 15.5 m2.
The triangle exposes a full 45-degree face; the chamfer removes a 1 m corner.
Opposite triangles can share the same cell to reconstruct a full square.

The top cap remains 0.24 m thick. SupportDatum holds an independently scalable
lower wall, initially 0.76 m deep beneath the cap. Use
CustomHarbourAssetLibrary.set_foundation_depth(node, depth_m) to reach the seabed.
This updates the exact convex polygon collision and metre-scaled texture mapping
without lifting the walking surface. The removed corner has no invisible box.

Review: tests/custom_harbour_shape_review.tscn -- --shipyard-playtest --capture
Checks all four rotations, empty cut corners, variable support depth and the
shared seam between complementary triangles. Three native views are archived.
For an interactive review, omit --capture/--verify; use 1-3 views, right-drag orbit,
wheel zoom and P to archive a photograph.
