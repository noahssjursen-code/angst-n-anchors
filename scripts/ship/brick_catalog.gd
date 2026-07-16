class_name BrickCatalog
extends RefCounted

## Shared construction kit for vessel decks and land buildings.
## Footprint is in cells (x,y,z) = (width, height, length). Cell size = 1.0 m.
## Tag `ship_only` hides a brick from the land building editor palette.

## Shared window frame / glass metrics so corners seam with straight panes.
const WIN_POST := 0.08
const WIN_PANE_T := 0.04
const WIN_FRAME := Color(0.72, 0.74, 0.78)

const BRICKS: Dictionary = {
	"block": {
		"display": "Block",
		"footprint": [1, 1, 1],
		"tags": ["wall", "solid"],
		"mass_kg": 80.0,
		"color": Color(0.78, 0.80, 0.84),
	},
	"block_45": {
		"display": "45° angled block",
		## Vertical triangular prism for diagonal walls and pointed hull edges.
		## Missing plan corner is local (+X,+Z).
		"footprint": [1, 1, 1],
		"tags": ["wall", "solid", "diagonal_plan"],
		"mass_kg": 40.0,
		"color": Color(0.78, 0.80, 0.84),
	},
	"block_window": {
		"display": "Window",
		## 1×1×1 — glass flush on local −Z face.
		"footprint": [1, 1, 1],
		"tags": ["window"],
		"mass_kg": 35.0,
		"color": Color(0.55, 0.72, 0.88, 0.22),
	},
	"block_window_45": {
		"display": "45° angled window",
		## Triangular plan piece; glazing follows the diagonal cut face.
		"footprint": [1, 1, 1],
		"tags": ["window", "diagonal_plan"],
		"mass_kg": 28.0,
		"color": Color(0.55, 0.72, 0.88, 0.22),
	},
	"block_windshield": {
		"display": "Panoramic windshield",
		## One uninterrupted 3 m pane with only a perimeter frame.
		"footprint": [3, 1, 1],
		"tags": ["window", "ship_only", "windshield"],
		"mass_kg": 90.0,
		"color": Color(0.48, 0.68, 0.84, 0.20),
	},
	"block_window_corner": {
		"display": "Window corner",
		## 1×1×1 outer L — glass on −Z and −X; seams with straight windows.
		"footprint": [1, 1, 1],
		"tags": ["window", "corner"],
		"mass_kg": 40.0,
		"color": Color(0.55, 0.72, 0.88, 0.22),
	},
	"block_door": {
		"display": "Door",
		## 2 m wide × 3 m tall × 1 m deep — spans three layers (player ~1.8 m).
		"footprint": [2, 3, 1],
		"tags": ["door"],
		"mass_kg": 90.0,
		"color": Color(0.48, 0.32, 0.20),
	},
	"block_door_double": {
		"display": "Double door",
		## 4 m wide × 3 m tall × 1 m deep — paired leaves, yaw aims the passage along ±Z.
		"footprint": [4, 3, 1],
		"tags": ["door", "double_door"],
		"mass_kg": 200.0,
		"color": Color(0.48, 0.32, 0.20),
	},
	"block_door_fixed": {
		"display": "Door (fixed)",
		## Same look as Door — sealed / non-interactable prop (no BrickDoor).
		"footprint": [2, 3, 1],
		"tags": ["solid", "door_fixed"],
		"mass_kg": 90.0,
		"color": Color(0.48, 0.32, 0.20),
	},
	"block_door_double_fixed": {
		"display": "Double door (fixed)",
		## Same look as Double door — sealed / non-interactable prop (no BrickDoor).
		"footprint": [4, 3, 1],
		"tags": ["solid", "door_fixed"],
		"mass_kg": 200.0,
		"color": Color(0.48, 0.32, 0.20),
	},
	"foundation": {
		"display": "Foundation",
		"footprint": [1, 1, 1],
		"tags": ["solid", "foundation"],
		"mass_kg": 110.0,
		"color": Color(0.34, 0.35, 0.36),
	},
	"floor": {
		"display": "Floor",
		## Thin surface underlay — shares a cell with walls/props placed on top.
		"footprint": [1, 1, 1],
		"tags": ["floor", "surface"],
		"mass_kg": 35.0,
		"color": Color(0.48, 0.38, 0.27),
	},
	"roof_flat": {
		"display": "Flat roof",
		"footprint": [1, 1, 1],
		"tags": ["solid", "roof"],
		"mass_kg": 45.0,
		"color": Color(0.22, 0.24, 0.25),
	},
	"roof_flat_2x2": {
		"display": "Flat roof 2×2",
		"footprint": [2, 1, 2],
		"tags": ["solid", "roof"],
		"mass_kg": 160.0,
		"color": Color(0.22, 0.24, 0.25),
	},
	"roof_flat_4x4": {
		"display": "Flat roof 4×4",
		"footprint": [4, 1, 4],
		"tags": ["solid", "roof"],
		"mass_kg": 600.0,
		"color": Color(0.22, 0.24, 0.25),
	},
	"roof_slope": {
		"display": "Sloped roof",
		"footprint": [1, 1, 1],
		"tags": ["solid", "roof", "slope"],
		"mass_kg": 40.0,
		"color": Color(0.25, 0.27, 0.28),
	},
	"roof_slope_2x2x4": {
		"display": "Sloped roof 2×2×4",
		## 2 m wide × 2 m rise × 4 m run — high edge at −Z, slopes toward +Z.
		"footprint": [2, 2, 4],
		"tags": ["solid", "roof", "slope"],
		"mass_kg": 280.0,
		"color": Color(0.25, 0.27, 0.28),
	},
	"roof_slope_1x2x4": {
		"display": "Sloped roof 1×2×4",
		## 1 m wide × 2 m rise × 4 m run — high edge at −Z, slopes toward +Z.
		"footprint": [1, 2, 4],
		"tags": ["solid", "roof", "slope"],
		"mass_kg": 140.0,
		"color": Color(0.25, 0.27, 0.28),
	},
	"roof_slope_inv": {
		"display": "Inverted sloped roof",
		"footprint": [1, 1, 1],
		"tags": ["solid", "roof", "slope"],
		"mass_kg": 40.0,
		"color": Color(0.25, 0.27, 0.28),
	},
	"roof_slope_inv_2x2x4": {
		"display": "Inverted sloped roof 2×2×4",
		## 2 m wide × 2 m rise × 4 m run — high edge at −Z, underside slopes toward +Z.
		"footprint": [2, 2, 4],
		"tags": ["solid", "roof", "slope"],
		"mass_kg": 280.0,
		"color": Color(0.25, 0.27, 0.28),
	},
	"roof_corner": {
		"display": "Corner roof",
		## Hip / outer corner — peak at local (−X, −Z); yaw to seat against two slopes.
		"footprint": [1, 1, 1],
		"tags": ["solid", "roof", "slope", "corner"],
		"mass_kg": 35.0,
		"color": Color(0.25, 0.27, 0.28),
	},
	"roof_corner_4x2x4": {
		"display": "Corner roof 4×2×4",
		## Large hip / outer corner — peak at local (−X, −Z).
		"footprint": [4, 2, 4],
		"tags": ["solid", "roof", "slope", "corner"],
		"mass_kg": 560.0,
		"color": Color(0.25, 0.27, 0.28),
	},
	"roof_corner_inv": {
		"display": "Inverted corner roof",
		"footprint": [1, 1, 1],
		"tags": ["solid", "roof", "slope", "corner"],
		"mass_kg": 35.0,
		"color": Color(0.25, 0.27, 0.28),
	},
	"roof_corner_inner": {
		"display": "Inner corner roof",
		## Valley / inside corner — high L along (−X, −Z); yaw to seat between two slopes.
		"footprint": [1, 1, 1],
		"tags": ["solid", "roof", "slope", "corner"],
		"mass_kg": 40.0,
		"color": Color(0.25, 0.27, 0.28),
	},
	"roof_corner_inner_4x2x4": {
		"display": "Inner corner roof 4×2×4",
		## Large valley / inside corner — high L along (−X, −Z).
		"footprint": [4, 2, 4],
		"tags": ["solid", "roof", "slope", "corner"],
		"mass_kg": 560.0,
		"color": Color(0.25, 0.27, 0.28),
	},
	"roof_corner_inner_inv": {
		"display": "Inverted inner corner roof",
		"footprint": [1, 1, 1],
		"tags": ["solid", "roof", "slope", "corner"],
		"mass_kg": 40.0,
		"color": Color(0.25, 0.27, 0.28),
	},
	"beam": {
		"display": "Beam",
		"footprint": [1, 1, 1],
		"tags": ["solid", "structure"],
		"mass_kg": 30.0,
		"color": Color(0.30, 0.22, 0.15),
	},
	"ledge_45": {
		"display": "45° wedge",
		## Full cell cut on the diagonal — triangle brick / ramp.
		"footprint": [1, 1, 1],
		"tags": ["slope", "solid"],
		"mass_kg": 40.0,
		"color": Color(0.78, 0.80, 0.84),
	},
	"ledge_45_corner": {
		"display": "45° corner wedge",
		## Peak at local (−X, −Z) — ship-coloured hip / corner piece.
		"footprint": [1, 1, 1],
		"tags": ["slope", "solid", "corner"],
		"mass_kg": 35.0,
		"color": Color(0.78, 0.80, 0.84),
	},
	"ledge_45_corner_inv": {
		"display": "Inverted 45° corner wedge",
		"footprint": [1, 1, 1],
		"tags": ["slope", "solid", "corner"],
		"mass_kg": 35.0,
		"color": Color(0.78, 0.80, 0.84),
	},
	"ledge_45_inner": {
		"display": "45° inner corner wedge",
		## High L along (−X, −Z), low tip at (+X, +Z) — valley piece.
		"footprint": [1, 1, 1],
		"tags": ["slope", "solid", "corner"],
		"mass_kg": 40.0,
		"color": Color(0.78, 0.80, 0.84),
	},
	"ledge_45_inner_inv": {
		"display": "Inverted 45° inner corner wedge",
		"footprint": [1, 1, 1],
		"tags": ["slope", "solid", "corner"],
		"mass_kg": 40.0,
		"color": Color(0.78, 0.80, 0.84),
	},
	"stairs": {
		"display": "Companionway",
		## Tight 1×1×1 hatch stair — steep; prefer staircase for deck-to-deck.
		"footprint": [1, 1, 1],
		"tags": ["stairs", "slope"],
		"mass_kg": 55.0,
		"color": Color(0.58, 0.48, 0.36),
		"stair_steps": 4,
	},
	"staircase": {
		"display": "Staircase",
		## 2 m wide × 4 m tall × 2 m run — spans four layers.
		"footprint": [2, 4, 2],
		"tags": ["stairs", "slope"],
		"mass_kg": 320.0,
		"color": Color(0.55, 0.46, 0.34),
		## 4 m rise / 10 ≈ 0.4 m risers (under player max_step_height).
		"stair_steps": 10,
	},
	"helm": {
		"display": "Helm console",
		## Bridge console — place in the bridge; F only when looking at this brick.
		"footprint": [1, 1, 1],
		"tags": ["helm", "ship_only"],
		"mass_kg": 55.0,
		"color": Color(0.32, 0.34, 0.38),
	},
	"passenger_seat": {
		"display": "Passenger seat",
		## One certified passenger place. Capacity is derived from these bricks.
		"footprint": [1, 1, 1],
		"tags": ["passenger", "seat", "ship_only"],
		"passenger_capacity": 1,
		"equipment_rating": 1,
		"mass_kg": 24.0,
		"color": Color(0.20, 0.32, 0.46),
	},
	"light_deck": {
		"display": "Deck flood",
		## Sits on a block roof / deck; yaw aims across deck; housing ~25° down.
		"footprint": [1, 1, 1],
		"tags": ["light", "work", "top_mount", "ship_only"],
		"light_type": 4, ## ShipLight.LightType.WORK
		"housing_pitch_deg": -25.0,
		"spot_pitch_deg": 0.0, ## Beam parented under FloodHead.
		"spot_range_m": 22.0,
		"spot_energy": 95.0,
		"spot_angle_deg": 48.0,
		"yaw_step": 45,
		"mass_kg": 18.0,
		"color": Color(0.72, 0.70, 0.62),
	},
	"light_external": {
		"display": "External flood",
		## Roof / deck pedestal flood for quay / sea — yaw aims out; nearly level throw.
		"footprint": [1, 1, 1],
		"tags": ["light", "work", "external", "top_mount", "ship_only"],
		"light_type": 4,
		"housing_pitch_deg": 5.0,
		"spot_pitch_deg": 0.0,
		"spot_range_m": 42.0,
		"spot_energy": 120.0,
		"spot_angle_deg": 40.0,
		"yaw_step": 45,
		"mass_kg": 22.0,
		"color": Color(0.78, 0.76, 0.68),
	},
	"light_cabin": {
		"display": "Cabin light",
		## Bulkhead / overhead dome — warm omni.
		"footprint": [1, 1, 1],
		"tags": ["light", "cabin_light", "attach"],
		"light_type": 5, ## ShipLight.LightType.WINDOW (warm omni)
		"yaw_step": 45,
		"mass_kg": 8.0,
		"color": Color(0.85, 0.78, 0.55),
	},
	"light_ceiling": {
		"display": "Ceiling light",
		## Flush ceiling pan + frosted disc — hang from the cell soffit.
		"footprint": [1, 1, 1],
		"tags": ["light", "cabin_light", "ceiling", "attach"],
		"light_type": 5, ## ShipLight.LightType.WINDOW (warm omni)
		"omni_range_m": 7.0,
		"omni_energy": 3.2,
		"yaw_step": 90,
		"mass_kg": 10.0,
		"color": Color(0.88, 0.86, 0.78),
	},
	"light_nav_port": {
		"display": "Nav light (port)",
		## Mounts on a block; yaw aims the lens (−Z) in 45° steps.
		"footprint": [1, 1, 1],
		"tags": ["light", "nav", "attach", "ship_only"],
		"light_type": 0,
		"yaw_step": 45,
		"mass_kg": 10.0,
		"color": Color(0.75, 0.12, 0.10),
	},
	"light_nav_stbd": {
		"display": "Nav light (stbd)",
		"footprint": [1, 1, 1],
		"tags": ["light", "nav", "attach", "ship_only"],
		"light_type": 1,
		"yaw_step": 45,
		"mass_kg": 10.0,
		"color": Color(0.10, 0.65, 0.18),
	},
	"light_nav_white": {
		"display": "Nav light (white)",
		## All-round white point light — visible from every bearing.
		"footprint": [1, 1, 1],
		"tags": ["light", "nav", "nav_white", "attach", "ship_only"],
		"light_type": 2,
		"yaw_step": 90,
		"mass_kg": 12.0,
		"color": Color(0.92, 0.92, 0.88),
	},
	"light_mast_white": {
		"display": "Mast light (white)",
		## 2×2 all-round masthead lantern — centres on the mast column.
		"footprint": [2, 1, 2],
		"tags": ["light", "nav", "nav_white", "mast", "ship_only"],
		"light_type": 2,
		"yaw_step": 90,
		"mass_kg": 35.0,
		"color": Color(0.92, 0.92, 0.88),
	},
	"railing": {
		"display": "Railing",
		## Sits on local −Z face (yaw so −Z points outboard), matching windows.
		"footprint": [1, 1, 1],
		"tags": ["railing", "edge"],
		"mass_kg": 15.0,
		"color": Color(0.35, 0.38, 0.42),
	},
	"railing_mooring": {
		"display": "Railing + mooring",
		## Edge railing with a cell-centred mooring bit — rail hugs −Z, bit sits mid-cell.
		"footprint": [1, 1, 1],
		"tags": ["railing", "edge", "mooring", "cleat", "ship_only"],
		"mass_kg": 35.0,
		"color": Color(0.35, 0.38, 0.42),
	},
	"railing_45": {
		"display": "45° angled railing",
		## Same diagonal as block_45: missing (+X,+Z). Posts land on cell corners
		## so edge-aligned straight railings meet the run without a gap.
		"footprint": [1, 1, 1],
		"tags": ["railing", "edge", "diagonal_plan", "diagonal_railing"],
		"mass_kg": 20.0,
		"color": Color(0.35, 0.38, 0.42),
	},
	"bollard": {
		"display": "Bollard",
		## Vertical mooring post for open deck / bulwark tops.
		"footprint": [1, 1, 1],
		"tags": ["mooring", "cleat", "ship_only"],
		"mass_kg": 55.0,
		"color": Color(0.42, 0.40, 0.36),
	},
	"mast_base": {
		"display": "Mast base",
		## 2×2 m deck tabernacle — centred on four cells; stack mast_pole above.
		"footprint": [2, 1, 2],
		"tags": ["mast", "mast_base", "prop", "ship_only"],
		"mass_kg": 120.0,
		"color": Color(0.38, 0.36, 0.32),
	},
	"mast_pole": {
		"display": "Mast pole",
		## 1 m spar segment on the same 2×2 column — stack layers for mast height.
		"footprint": [2, 1, 2],
		"tags": ["mast", "mast_pole", "prop", "ship_only"],
		"mass_kg": 45.0,
		"color": Color(0.40, 0.38, 0.34),
	},
	"chimney_2x3x2": {
		"display": "Chimney 2×3×2",
		## Compact funnel / stack — 2 m × 3 m tall × 2 m.
		"footprint": [2, 3, 2],
		"tags": ["chimney", "prop"],
		"mass_kg": 220.0,
		"color": Color(0.22, 0.23, 0.24),
	},
	"chimney_4x5x4": {
		"display": "Chimney 4×5×4",
		## Large funnel / stack — 4 m × 5 m tall × 4 m.
		"footprint": [4, 5, 4],
		"tags": ["chimney", "prop"],
		"mass_kg": 980.0,
		"color": Color(0.20, 0.21, 0.22),
	},
	"container_pad": {
		"display": "Container pad",
		"footprint": [2, 1, 2],
		"tags": ["container_pad", "cargo", "floor", "zone", "ship_only"],
		"place_mode": "rect",
		"deck_only": true,
		"mass_kg": 80.0,
		"color": Color(0.16, 0.22, 0.32),
	},
	"bulk_hold_6x12": {
		"display": "Bulk hold 6×12",
		"footprint": [6, 1, 12],
		"tags": ["bulk_hold", "cargo", "floor", "zone", "ship_only"],
		"place_mode": "fixed_rect",
		"deck_only": true,
		"mass_kg": 540.0,
		"color": Color(0.04, 0.04, 0.05),
		"hold_depth_m": 2.5,
	},
	"crane_base": {
		"display": "Crane base",
		## 2×2 m pad.
		"footprint": [2, 1, 2],
		"tags": ["crane_base", "ship_only"],
		"mass_kg": 400.0,
		"color": Color(0.55, 0.45, 0.22),
	},
	"crane": {
		"display": "Crane arm",
		"footprint": [1, 2, 1],
		"tags": ["crane", "ship_only"],
		"mass_kg": 600.0,
		"color": Color(0.62, 0.52, 0.24),
	},
	"hull_ladder": {
		"display": "Hull ladder",
		## 2×2 m pad on the deck edge; rungs hang outboard so you climb aboard from the quay.
		"footprint": [2, 1, 2],
		"tags": ["ladder", "edge", "ship_only"],
		"mass_kg": 45.0,
		"color": Color(0.42, 0.44, 0.48),
		"deck_only": true,
		"edge_only": true,
	},
	"trommel_small": {
		"display": "Trommel (small)",
		## 2×4 m deck winch — mounts FishingSystem for trawl cast/haul.
		"footprint": [2, 1, 4],
		"tags": ["fishing", "trommel", "ship_only"],
		"mass_kg": 1800.0,
		"color": Color(0.22, 0.24, 0.26),
		"deck_only": true,
	},
	"deck_text": {
		"display": "Floor text",
		## Flat Label3D on the deck — vessel name, draft marks, etc.
		"footprint": [6, 1, 1],
		"tags": ["text", "sign", "floor", "ship_only"],
		"mass_kg": 5.0,
		"color": Color(0.92, 0.86, 0.55),
		"deck_only": true,
		"default_text": "NAME",
		"text_mount": "floor",
	},
	"wall_text_sm": {
		"display": "Wall text (small)",
		## Painted letters on the bulkhead — no plaque. Yaw aims the face (−Z).
		"footprint": [2, 1, 1],
		"tags": ["text", "sign", "wall"],
		"mass_kg": 4.0,
		"color": Color(0.92, 0.86, 0.55),
		"default_text": "NAME",
		"text_mount": "wall",
	},
	"wall_text": {
		"display": "Wall text",
		## Painted letters on the bulkhead — no plaque. Yaw aims the face (−Z).
		"footprint": [3, 2, 1],
		"tags": ["text", "sign", "wall"],
		"mass_kg": 8.0,
		"color": Color(0.92, 0.86, 0.55),
		"default_text": "NAME",
		"text_mount": "wall",
	},
	"wall_text_lg": {
		"display": "Wall text (large)",
		## Painted letters on the bulkhead — no plaque. Yaw aims the face (−Z).
		"footprint": [6, 3, 1],
		"tags": ["text", "sign", "wall"],
		"mass_kg": 14.0,
		"color": Color(0.92, 0.86, 0.55),
		"default_text": "NAME",
		"text_mount": "wall",
	},
	"bench": {
		"display": "Bench",
		## 2×2×2 m — yaw aims the sit face (+Z). Backrest on −Z.
		"footprint": [2, 2, 2],
		"tags": ["prop", "furniture"],
		"mass_kg": 55.0,
		"color": Color(0.42, 0.30, 0.20),
	},
	"table": {
		"display": "Table",
		## 2×1×2 m mess table.
		"footprint": [2, 1, 2],
		"tags": ["prop", "furniture"],
		"mass_kg": 55.0,
		"color": Color(0.48, 0.34, 0.22),
	},
}


static func ids() -> Array[String]:
	var out: Array[String] = []
	for k in BRICKS.keys():
		out.append(str(k))
	out.sort()
	return out


static func ids_for_buildings() -> Array[String]:
	## Land building editor palette — shared kit minus marine-only systems.
	var out: Array[String] = []
	for brick_id in ids():
		if has_tag(brick_id, "ship_only"):
			continue
		out.append(brick_id)
	return out


static func has(brick_id: String) -> bool:
	return BRICKS.has(brick_id.strip_edges())


static func get_entry(brick_id: String) -> Dictionary:
	var id := brick_id.strip_edges()
	if not BRICKS.has(id):
		return {}
	return (BRICKS[id] as Dictionary).duplicate(true)


static func footprint_of(brick_id: String) -> Vector3i:
	var e := get_entry(brick_id)
	if e.is_empty():
		return Vector3i(1, 1, 1)
	var raw: Variant = e.get("footprint", [1, 1, 1])
	if raw is Vector3i:
		return raw as Vector3i
	if raw is Array:
		var a: Array = raw
		return Vector3i(int(a[0]), int(a[1]) if a.size() > 1 else 1, int(a[2]) if a.size() > 2 else 1)
	return Vector3i(1, 1, 1)


static func size_m(brick_id: String) -> Vector3:
	var fp := footprint_of(brick_id)
	var s := DeckGrid.CELL_M
	return Vector3(float(fp.x) * s, float(fp.y) * s, float(fp.z) * s)


static func yaw_step_of(brick_id: String) -> int:
	return maxi(int(get_entry(brick_id).get("yaw_step", 90)), 1)


static func display_name(brick_id: String) -> String:
	return str(get_entry(brick_id).get("display", brick_id))


static func has_tag(brick_id: String, tag: String) -> bool:
	var tags = get_entry(brick_id).get("tags", [])
	return tags is Array and (tags as Array).has(tag)


static func _painted_palette_material(preset: Dictionary, color: Color, exposed: bool) -> StandardMaterial3D:
	var painted := preset.duplicate()
	painted["color"] = color
	return Palette.make(painted, false, exposed)


static func create_visual(brick_id: String, opts: Dictionary = {}) -> Node3D:
	## Mesh is centred on the origin; caller places the node at the footprint AABB centre.
	## opts.preview_mesh — when true, cargo tiles get a temporary plate (ghost / palette thumb).
	## opts.color — optional Color override (painted buildings / custom bricks).
	var root := Node3D.new()
	root.name = brick_id
	var entry := get_entry(brick_id)
	var color: Color = entry.get("color", Color(0.7, 0.7, 0.7)) as Color
	if opts.has("color") and opts["color"] is Color:
		color = opts["color"] as Color
	var sz := size_m(brick_id)
	var s := DeckGrid.CELL_M
	match brick_id:
		"block":
			root.add_child(MeshBuilder.box(sz, color, 0.85, 0.0))
		"block_45":
			root.add_child(MeshBuilder.wedge_45_plan(sz, color, 0.85, 0.0))
		"block_window":
			_add_window_visual(root, sz, color)
		"block_window_45":
			_add_window_45_visual(root, sz, color)
		"block_windshield":
			_add_window_visual(root, sz, color)
		"block_window_corner":
			_add_window_corner_visual(root, sz, color)
		"block_door", "block_door_fixed":
			_add_door_visual(root, sz, color)
		"block_door_double", "block_door_double_fixed":
			_add_double_door_visual(root, sz, color)
		"foundation":
			root.add_child(MeshBuilder.box(sz, color, 0.92, 0.0))
		"floor":
			var floor_plate := MeshBuilder.box(Vector3(sz.x, 0.12, sz.z), color, 0.9, 0.0)
			floor_plate.position = Vector3(0.0, -sz.y * 0.5 + 0.06, 0.0)
			root.add_child(floor_plate)
		"roof_flat", "roof_flat_2x2", "roof_flat_4x4":
			var roof := MeshBuilder.box(Vector3(sz.x, 0.18, sz.z), color, 0.8, 0.1)
			roof.material_override = _painted_palette_material(Palette.CLADDING, color, true)
			roof.position = Vector3(0.0, sz.y * 0.5 - 0.09, 0.0)
			root.add_child(roof)
		"roof_slope", "roof_slope_1x2x4", "roof_slope_2x2x4":
			var roof := MeshBuilder.wedge_45(sz, color, 0.82, 0.08)
			roof.material_override = _painted_palette_material(Palette.CLADDING, color, true)
			root.add_child(roof)
		"roof_slope_inv", "roof_slope_inv_2x2x4":
			var roof := MeshBuilder.wedge_45_inverted(sz, color, 0.82, 0.08)
			roof.material_override = _painted_palette_material(Palette.CLADDING, color, true)
			root.add_child(roof)
		"roof_corner", "roof_corner_4x2x4":
			var roof := MeshBuilder.wedge_45_corner(sz, color, 0.82, 0.08)
			roof.material_override = _painted_palette_material(Palette.CLADDING, color, true)
			root.add_child(roof)
		"roof_corner_inv":
			var roof := MeshBuilder.wedge_45_corner_inverted(sz, color, 0.82, 0.08)
			roof.material_override = _painted_palette_material(Palette.CLADDING, color, true)
			root.add_child(roof)
		"roof_corner_inner", "roof_corner_inner_4x2x4":
			var roof := MeshBuilder.wedge_45_inner(sz, color, 0.82, 0.08)
			roof.material_override = _painted_palette_material(Palette.CLADDING, color, true)
			root.add_child(roof)
		"roof_corner_inner_inv":
			var roof := MeshBuilder.wedge_45_inner_inverted(sz, color, 0.82, 0.08)
			roof.material_override = _painted_palette_material(Palette.CLADDING, color, true)
			root.add_child(roof)
		"beam":
			root.add_child(MeshBuilder.box(Vector3(0.22, sz.y, 0.22), color, 0.88, 0.0))
		"ledge_45":
			root.add_child(MeshBuilder.wedge_45(sz, color, 0.92, 0.0))
		"ledge_45_corner":
			root.add_child(MeshBuilder.wedge_45_corner(sz, color, 0.92, 0.0))
		"ledge_45_corner_inv":
			root.add_child(MeshBuilder.wedge_45_corner_inverted(sz, color, 0.92, 0.0))
		"ledge_45_inner":
			root.add_child(MeshBuilder.wedge_45_inner(sz, color, 0.92, 0.0))
		"ledge_45_inner_inv":
			root.add_child(MeshBuilder.wedge_45_inner_inverted(sz, color, 0.92, 0.0))
		"stairs", "staircase":
			_add_stairs_visual(root, sz, color, int(entry.get("stair_steps", 4)))
		"helm":
			_add_helm_visual(root, sz, color)
		"passenger_seat":
			var cushion := MeshBuilder.box(Vector3(0.62, 0.14, 0.58), color, 0.72, 0.0)
			cushion.position = Vector3(0.0, -0.24, 0.05)
			root.add_child(cushion)
			var back := MeshBuilder.box(Vector3(0.62, 0.66, 0.12), color, 0.72, 0.0)
			back.position = Vector3(0.0, 0.05, 0.30)
			root.add_child(back)
			var pedestal := MeshBuilder.cylinder(0.08, 0.42, Color(0.18, 0.19, 0.21), 0.65, 0.3)
			pedestal.position = Vector3(0.0, -0.40, 0.0)
			root.add_child(pedestal)
		"light_deck":
			_add_light_deck_visual(root, sz, color, float(entry.get("housing_pitch_deg", -25.0)))
			if bool(opts.get("show_aim_gizmo", false)):
				_add_light_aim_gizmo(root, brick_id)
		"light_external":
			_add_light_external_visual(root, sz, color, float(entry.get("housing_pitch_deg", 5.0)))
			if bool(opts.get("show_aim_gizmo", false)):
				_add_light_aim_gizmo(root, brick_id)
		"light_cabin":
			_add_light_cabin_visual(root, sz, color)
			if bool(opts.get("show_aim_gizmo", false)):
				_add_light_aim_gizmo(root, brick_id)
		"light_ceiling":
			_add_light_ceiling_visual(root, sz, color)
			if bool(opts.get("show_aim_gizmo", false)):
				_add_light_aim_gizmo(root, brick_id)
		"light_nav_port", "light_nav_stbd":
			_add_light_nav_visual(root, sz, color, brick_id)
			if bool(opts.get("show_aim_gizmo", false)):
				_add_light_aim_gizmo(root, brick_id)
		"light_nav_white":
			_add_light_nav_white_visual(root, sz, color)
			if bool(opts.get("show_aim_gizmo", false)):
				_add_light_aim_gizmo(root, brick_id)
		"light_mast_white":
			_add_light_mast_white_visual(root, sz, color)
			if bool(opts.get("show_aim_gizmo", false)):
				_add_light_aim_gizmo(root, brick_id)
		"railing":
			## Exact cell span on the −Z face so neighbours + 45° corners meet.
			_add_railing_visual(root, sz.x, sz.y, color, _railing_edge_z(sz))
		"railing_mooring":
			_add_railing_mooring_visual(root, sz, color)
		"railing_45":
			_add_railing_45_visual(root, sz, color)
		"bollard":
			_add_bollard_visual(root, sz, color)
		"mast_base":
			_add_mast_base_visual(root, sz, color)
		"mast_pole":
			_add_mast_pole_visual(root, sz, color)
		"chimney_2x3x2", "chimney_4x5x4":
			_add_chimney_visual(root, sz, color)
		"container_pad":
			var pad := MeshBuilder.box(Vector3(sz.x, 0.08, sz.z), color, 0.9, 0.05)
			pad.position = Vector3(0.0, -sz.y * 0.5 + 0.04, 0.0)
			root.add_child(pad)
			var rim := MeshBuilder.box(Vector3(sz.x * 0.98, 0.02, sz.z * 0.98), color.lightened(0.15), 0.85, 0.1)
			rim.position = Vector3(0.0, -sz.y * 0.5 + 0.09, 0.0)
			root.add_child(rim)
		"bulk_hold_6x12":
			var depth_m := float(entry.get("hold_depth_m", 2.5))
			var hold_visual := BulkHoldComponent.build_visual(sz.x, sz.z, depth_m, true)
			hold_visual.position = Vector3(0.0, -sz.y * 0.5 + 0.02, 0.0)
			root.add_child(hold_visual)
		"crane_base":
			var base := MeshBuilder.box(Vector3(sz.x, sz.y * 0.5, sz.z), color, 0.85, 0.15)
			base.position = Vector3(0.0, -sz.y * 0.25, 0.0)
			root.add_child(base)
		"crane":
			var pedestal := MeshBuilder.box(Vector3(sz.x * 0.7, sz.y * 0.85, sz.z * 0.7), color, 0.85, 0.2)
			pedestal.position = Vector3(0.0, -sz.y * 0.05, 0.0)
			root.add_child(pedestal)
			var boom := MeshBuilder.box(Vector3(0.16, 0.16, maxf(sz.z, s) * 2.2), color, 0.8, 0.25)
			boom.position = Vector3(0.0, sz.y * 0.35, -sz.z * 0.55)
			boom.rotation_degrees = Vector3(-20.0, 0.0, 0.0)
			root.add_child(boom)
		"hull_ladder":
			_add_hull_ladder_visual(root, sz, color)
		"trommel_small":
			_add_trommel_visual(root, sz, color)
		"deck_text":
			_add_deck_text_visual(
				root, sz, color,
				str(opts.get("text", entry.get("default_text", "NAME"))),
				"floor",
			)
		"wall_text_sm", "wall_text", "wall_text_lg":
			_add_deck_text_visual(
				root, sz, color,
				str(opts.get("text", entry.get("default_text", "NAME"))),
				"wall",
			)
		"bench":
			_add_bench_visual(root, sz, color)
		"table":
			_add_table_visual(root, sz, color)
		_:
			root.add_child(MeshBuilder.box(sz, color, 0.85, 0.0))
	return root


static func _add_bench_visual(root: Node3D, sz: Vector3, color: Color) -> void:
	## Fills the footprint AABB. Sit face = local +Z; backrest on −Z.
	var wood := Color(color.r, color.g, color.b)
	var dark := Color(color.r * 0.72, color.g * 0.72, color.b * 0.75)
	var metal := Color(0.32, 0.34, 0.36)
	var floor_y := -sz.y * 0.5
	var seat_h := sz.y * 0.22
	var seat_t := maxf(sz.y * 0.04, 0.05)
	var seat_d := sz.z * 0.72
	var seat_w := sz.x * 0.94
	var back_h := sz.y * 0.72
	var back_t := maxf(sz.z * 0.04, 0.05)
	var seat_z := sz.z * 0.08

	var seat := MeshBuilder.box(Vector3(seat_w, seat_t, seat_d), wood, 0.88, 0.02)
	seat.position = Vector3(0.0, floor_y + seat_h, seat_z)
	root.add_child(seat)

	var back := MeshBuilder.box(Vector3(seat_w, back_h, back_t), wood, 0.88, 0.02)
	back.position = Vector3(
		0.0,
		floor_y + seat_h + back_h * 0.5,
		seat_z - seat_d * 0.5 + back_t * 0.5
	)
	root.add_child(back)

	for side in [-1.0, 1.0]:
		var leg := MeshBuilder.box(Vector3(0.08, seat_h, seat_d * 0.9), dark, 0.9, 0.05)
		leg.position = Vector3(side * (seat_w * 0.5 - 0.08), floor_y + seat_h * 0.5, seat_z)
		root.add_child(leg)
		var foot := MeshBuilder.box(Vector3(0.14, 0.05, seat_d * 0.95), metal, 0.7, 0.35)
		foot.position = Vector3(side * (seat_w * 0.5 - 0.08), floor_y + 0.025, seat_z)
		root.add_child(foot)

	var brace := MeshBuilder.box(Vector3(seat_w * 0.8, 0.05, 0.06), metal, 0.7, 0.3)
	brace.position = Vector3(0.0, floor_y + seat_h * 0.4, seat_z)
	root.add_child(brace)


static func _add_table_visual(root: Node3D, sz: Vector3, color: Color) -> void:
	## Fills the footprint AABB — top near the top of the brick.
	var wood := Color(color.r, color.g, color.b)
	var dark := Color(color.r * 0.7, color.g * 0.7, color.b * 0.72)
	var metal := Color(0.34, 0.36, 0.38)
	var floor_y := -sz.y * 0.5
	var top_h := sz.y * 0.92
	var top_t := maxf(sz.y * 0.04, 0.05)
	var top_w := sz.x * 0.9
	var top_d := sz.z * 0.9
	var leg_w := maxf(minf(sz.x, sz.z) * 0.05, 0.06)
	var inset := minf(sz.x, sz.z) * 0.1

	var top := MeshBuilder.box(Vector3(top_w, top_t, top_d), wood, 0.85, 0.02)
	top.position = Vector3(0.0, floor_y + top_h, 0.0)
	root.add_child(top)

	var apron := MeshBuilder.box(Vector3(top_w * 0.84, maxf(sz.y * 0.05, 0.06), top_d * 0.84), dark, 0.9, 0.04)
	apron.position = Vector3(0.0, floor_y + top_h - top_t * 0.5 - maxf(sz.y * 0.03, 0.04), 0.0)
	root.add_child(apron)

	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var leg_h := top_h - top_t * 0.5 - 0.02
			var leg := MeshBuilder.box(Vector3(leg_w, leg_h, leg_w), dark, 0.9, 0.05)
			leg.position = Vector3(
				x * (top_w * 0.5 - inset),
				floor_y + leg_h * 0.5,
				z * (top_d * 0.5 - inset)
			)
			root.add_child(leg)
			var foot := MeshBuilder.cylinder(leg_w * 0.7, 0.04, metal, 0.7, 0.3)
			foot.position = Vector3(
				x * (top_w * 0.5 - inset),
				floor_y + 0.02,
				z * (top_d * 0.5 - inset)
			)
			root.add_child(foot)


static func _add_trommel_visual(root: Node3D, sz: Vector3, color: Color) -> void:
	## Static preview — runtime DeckFitout swaps in FishingSystem for spin + net.
	var steel := Color(color.r, color.g, color.b)
	var accent := Color(0.35, 0.32, 0.28)
	var pad := MeshBuilder.box(Vector3(sz.x * 0.92, 0.1, sz.z * 0.92), accent, 0.9, 0.1)
	pad.position = Vector3(0.0, -sz.y * 0.5 + 0.05, 0.0)
	root.add_child(pad)
	var drum_len := minf(sz.z * 0.55, 2.4)
	var drum_r := minf(sz.x * 0.22, 0.35)
	var drum_y := -sz.y * 0.5 + drum_r + 0.85
	var drum := MeshBuilder.cylinder(drum_r, drum_len, steel, 0.3, 0.85)
	drum.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	drum.position = Vector3(0.0, drum_y, 0.0)
	root.add_child(drum)
	for side in [-1.0, 1.0]:
		var flange := MeshBuilder.cylinder(drum_r * 1.55, 0.08, steel, 0.25, 0.9)
		flange.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		flange.position = Vector3(0.0, drum_y, side * drum_len * 0.48)
		root.add_child(flange)
		for tilt in [-1.0, 1.0]:
			var leg_h := drum_y - (-sz.y * 0.5 + 0.1)
			var leg := MeshBuilder.box(Vector3(0.1, leg_h, 0.08), steel, 0.45, 0.7)
			leg.position = Vector3(tilt * sz.x * 0.28, -sz.y * 0.5 + 0.1 + leg_h * 0.5, side * drum_len * 0.42)
			root.add_child(leg)


static func _add_deck_text_visual(
	root: Node3D,
	sz: Vector3,
	color: Color,
	text: String,
	mount: String = "floor",
) -> void:
	var label_text := text if not text.strip_edges().is_empty() else "NAME"
	if mount == "wall":
		## Letters only — no plaque. Slight stick-out so they clear the wall mesh.
		## Bebas Neue (display) reads like painted harbour / warehouse signage.
		var stick_out := 0.06
		var face_z := -sz.z * 0.5 - stick_out
		var font_size := 128
		## Letter height tracks footprint height; width footprint is the authoring pad.
		var letter_h_m := clampf(sz.y * 0.62, 0.45, 2.4)
		var pixel_size := letter_h_m / float(font_size)

		var label := Label3D.new()
		label.name = "WallText"
		label.text = label_text.to_upper()
		label.font = HudStyle.font_display()
		label.font_size = font_size
		label.pixel_size = pixel_size
		## Upright, facing out (−Z) so letters read horizontally on the wall.
		label.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		label.position = Vector3(0.0, 0.0, face_z)
		label.modulate = color
		## Soft dark outline for contrast on light cladding — not a solid backer.
		label.outline_modulate = Color(0.08, 0.07, 0.05, 0.85)
		label.outline_size = 8
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.shaded = false
		label.double_sided = true
		label.render_priority = 1
		root.add_child(label)
		return

	## Floor mount — text lying flat on the deck (keeps a thin plate for ship marks).
	var floor_plate := MeshBuilder.box(
		Vector3(sz.x * 0.98, 0.03, sz.z * 0.55),
		Color(0.12, 0.12, 0.14),
		0.95,
		0.0,
	)
	floor_plate.position = Vector3(0.0, -sz.y * 0.5 + 0.02, 0.0)
	root.add_child(floor_plate)

	var floor_label := Label3D.new()
	floor_label.name = "FloorText"
	floor_label.text = label_text
	floor_label.font = HudStyle.font_display()
	floor_label.font_size = 96
	floor_label.pixel_size = 0.008
	floor_label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	floor_label.position = Vector3(0.0, -sz.y * 0.5 + 0.05, 0.0)
	floor_label.modulate = color
	floor_label.outline_modulate = Color(0.05, 0.05, 0.06, 0.95)
	floor_label.outline_size = 12
	floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	floor_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	floor_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	floor_label.shaded = false
	floor_label.double_sided = true
	floor_label.render_priority = 1
	root.add_child(floor_label)


static func _add_stairs_visual(root: Node3D, sz: Vector3, color: Color, steps: int = 4) -> void:
	## Solid stepped fills. Low at +Z, high at −Z (yaw aims the climb).
	## Treads abut with a hair of overlap so seams don't show gaps.
	var n := maxi(steps, 2)
	var riser := sz.y / float(n)
	var tread := sz.z / float(n)
	var hy := sz.y * 0.5
	var hz := sz.z * 0.5
	var overlap := 0.004
	for k in range(n):
		var h := riser * float(k + 1)
		var depth := tread + overlap
		var mi := MeshBuilder.box(Vector3(sz.x, h, depth), color, 0.9, 0.0)
		## k=0 = lowest tread near +Z; k=n-1 = full rise near −Z.
		mi.position = Vector3(0.0, -hy + h * 0.5, hz - (float(k) + 0.5) * tread)
		root.add_child(mi)


static func _add_helm_visual(root: Node3D, sz: Vector3, color: Color) -> void:
	## Bridge console — no wheel. Local −Z = look-out (yaw the brick).
	var panel := Color(0.14, 0.15, 0.17)
	var body_col := Color(color.r * 0.85, color.g * 0.85, color.b * 0.88)
	var screen := Color(0.25, 0.55, 0.48)
	var metal := Color(0.42, 0.44, 0.48)
	var accent := Color(0.75, 0.55, 0.18)

	## Floor plinth.
	var plinth := MeshBuilder.box(Vector3(0.92, 0.08, 0.78), Color(0.12, 0.12, 0.13), 0.9, 0.05)
	plinth.position = Vector3(0.0, -sz.y * 0.5 + 0.04, 0.05)
	root.add_child(plinth)

	## Console cabinet.
	var cabinet := MeshBuilder.box(Vector3(0.9, 0.72, 0.55), body_col, 0.82, 0.08)
	cabinet.position = Vector3(0.0, -sz.y * 0.5 + 0.44, 0.08)
	root.add_child(cabinet)

	## Angled instrument face toward the helmsman (+Z).
	var face := MeshBuilder.box(Vector3(0.86, 0.06, 0.48), panel, 0.45, 0.2)
	face.position = Vector3(0.0, 0.12, -0.02)
	face.rotation_degrees = Vector3(-32.0, 0.0, 0.0)
	root.add_child(face)

	## Twin chart / radar screens.
	for x in [-0.22, 0.22]:
		var bezel := MeshBuilder.box(Vector3(0.28, 0.02, 0.22), metal, 0.5, 0.35)
		bezel.position = Vector3(x, 0.18, -0.1)
		bezel.rotation_degrees = Vector3(-32.0, 0.0, 0.0)
		root.add_child(bezel)
		var glass := MeshBuilder.box(Vector3(0.24, 0.015, 0.18), screen, 0.15, 0.05)
		glass.position = Vector3(x, 0.195, -0.11)
		glass.rotation_degrees = Vector3(-32.0, 0.0, 0.0)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(glass)

	## Centre status strip.
	var strip := MeshBuilder.box(Vector3(0.14, 0.015, 0.2), Color(0.08, 0.09, 0.1), 0.4, 0.2)
	strip.position = Vector3(0.0, 0.18, -0.1)
	strip.rotation_degrees = Vector3(-32.0, 0.0, 0.0)
	root.add_child(strip)
	for i in range(3):
		var led := MeshBuilder.box(
			Vector3(0.03, 0.012, 0.03),
			Color(0.2, 0.85, 0.35) if i == 1 else accent,
			0.3,
			0.1,
		)
		led.position = Vector3(0.0, 0.2, -0.04 - float(i) * 0.06)
		led.rotation_degrees = Vector3(-32.0, 0.0, 0.0)
		root.add_child(led)

	## Desktop ledge for controls.
	var desk := MeshBuilder.box(Vector3(0.88, 0.05, 0.28), panel, 0.55, 0.15)
	desk.position = Vector3(0.0, -sz.y * 0.5 + 0.82, 0.28)
	root.add_child(desk)

	## Twin throttle / clutch levers.
	for x in [-0.28, 0.28]:
		var slot := MeshBuilder.box(Vector3(0.1, 0.03, 0.16), metal, 0.5, 0.4)
		slot.position = Vector3(x, -sz.y * 0.5 + 0.86, 0.28)
		root.add_child(slot)
		var lever := MeshBuilder.box(Vector3(0.028, 0.16, 0.028), accent, 0.4, 0.35)
		lever.position = Vector3(x, -sz.y * 0.5 + 0.94, 0.26)
		lever.rotation_degrees = Vector3(-20.0, 0.0, 0.0)
		root.add_child(lever)
		var knob := MeshBuilder.sphere(0.03, Color(0.1, 0.1, 0.11), 0.35, 0.15)
		knob.position = Vector3(x, -sz.y * 0.5 + 1.02, 0.22)
		root.add_child(knob)

	## Centre joystick / heading control.
	var stick_base := MeshBuilder.cylinder(0.06, 0.04, metal, 0.45, 0.4)
	stick_base.position = Vector3(0.0, -sz.y * 0.5 + 0.86, 0.3)
	root.add_child(stick_base)
	var stick := MeshBuilder.cylinder(0.02, 0.14, Color(0.2, 0.2, 0.22), 0.4, 0.2)
	stick.position = Vector3(0.0, -sz.y * 0.5 + 0.94, 0.3)
	root.add_child(stick)
	var stick_top := MeshBuilder.sphere(0.035, accent, 0.4, 0.3)
	stick_top.position = Vector3(0.0, -sz.y * 0.5 + 1.02, 0.3)
	root.add_child(stick_top)

	## Side handrails on the console.
	for x in [-0.48, 0.48]:
		var rail := MeshBuilder.cylinder(0.02, 0.55, metal, 0.5, 0.45)
		rail.position = Vector3(x, -sz.y * 0.5 + 0.55, 0.2)
		root.add_child(rail)

	## Eye — standing at the desk looking out (−Z) over the screens.
	var eye := Marker3D.new()
	eye.name = "HelmEye"
	eye.position = Vector3(0.0, 0.72, 0.55)
	root.add_child(eye)


static func _add_light_deck_visual(root: Node3D, sz: Vector3, color: Color, pitch_deg: float = -25.0) -> void:
	## Rectangular deck flood on a roof / deck pedestal — throw along local −Z.
	var metal := Color(0.28, 0.30, 0.32)
	var dark := Color(0.18, 0.19, 0.20)
	var steel := _painted_palette_material(Palette.PAINTED_STEEL, metal, true)
	var housing := _painted_palette_material(Palette.PAINTED_STEEL, color, true)
	var y0 := -sz.y * 0.5

	var pad := MeshBuilder.box(Vector3(0.42, 0.05, 0.42), dark, 0.88, 0.15)
	pad.material_override = steel
	pad.position = Vector3(0.0, y0 + 0.03, 0.0)
	root.add_child(pad)

	var post := MeshBuilder.cylinder(0.045, 0.28, metal, 0.7, 0.3)
	post.material_override = steel
	post.position = Vector3(0.0, y0 + 0.20, 0.0)
	root.add_child(post)

	var pivot_y := y0 + 0.38
	## Twin yoke arms from the post to the can.
	for x in [-0.12, 0.12]:
		var yoke := MeshBuilder.box(Vector3(0.04, 0.04, 0.18), metal, 0.7, 0.3)
		yoke.material_override = steel
		yoke.position = Vector3(x, pivot_y, -0.02)
		root.add_child(yoke)

	var head := Node3D.new()
	head.name = "FloodHead"
	head.position = Vector3(0.0, pivot_y, 0.0)
	head.rotation_degrees = Vector3(pitch_deg, 0.0, 0.0)
	root.add_child(head)

	var can := MeshBuilder.box(Vector3(0.34, 0.22, 0.28), color, 0.75, 0.2)
	can.material_override = housing
	can.position = Vector3(0.0, 0.0, -0.20)
	can.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(can)

	var rear := MeshBuilder.box(Vector3(0.30, 0.18, 0.04), dark, 0.8, 0.15)
	rear.material_override = steel
	rear.position = Vector3(0.0, 0.0, -0.04)
	head.add_child(rear)

	for i in range(4):
		var fin := MeshBuilder.box(Vector3(0.28, 0.02, 0.03), metal, 0.7, 0.25)
		fin.material_override = steel
		fin.position = Vector3(0.0, 0.13, -0.10 - float(i) * 0.05)
		head.add_child(fin)

	var lip := MeshBuilder.box(Vector3(0.36, 0.24, 0.03), dark, 0.65, 0.2)
	lip.material_override = steel
	lip.position = Vector3(0.0, 0.0, -0.35)
	head.add_child(lip)

	var lens := MeshBuilder.box(Vector3(0.30, 0.18, 0.04), Color(0.55, 0.52, 0.42), 0.12, 0.0)
	lens.name = "Lens"
	lens.position = Vector3(0.0, 0.0, -0.34)
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(lens)


static func _add_light_external_visual(root: Node3D, sz: Vector3, color: Color, pitch_deg: float = 5.0) -> void:
	## Round marine flood on a deck pedestal — throw along local −Z.
	var metal := Color(0.30, 0.32, 0.34)
	var dark := Color(0.16, 0.17, 0.18)
	var steel := _painted_palette_material(Palette.PAINTED_STEEL, metal, true)
	var housing := _painted_palette_material(Palette.PAINTED_STEEL, color, true)
	var y0 := -sz.y * 0.5

	var pad := MeshBuilder.box(Vector3(0.48, 0.06, 0.48), dark, 0.88, 0.15)
	pad.material_override = steel
	pad.position = Vector3(0.0, y0 + 0.04, 0.0)
	root.add_child(pad)

	var column := MeshBuilder.cylinder(0.07, 0.32, metal, 0.7, 0.3)
	column.material_override = steel
	column.position = Vector3(0.0, y0 + 0.24, 0.0)
	root.add_child(column)

	var collar := MeshBuilder.cylinder(0.10, 0.05, metal, 0.65, 0.35)
	collar.material_override = steel
	collar.position = Vector3(0.0, y0 + 0.42, 0.0)
	root.add_child(collar)

	var pivot_y := y0 + 0.48
	var yoke_bar := MeshBuilder.box(Vector3(0.36, 0.05, 0.05), metal, 0.7, 0.3)
	yoke_bar.material_override = steel
	yoke_bar.position = Vector3(0.0, pivot_y, 0.0)
	root.add_child(yoke_bar)
	for x in [-0.16, 0.16]:
		var arm := MeshBuilder.box(Vector3(0.05, 0.05, 0.22), metal, 0.7, 0.3)
		arm.material_override = steel
		arm.position = Vector3(x, pivot_y, -0.08)
		root.add_child(arm)

	var head := Node3D.new()
	head.name = "FloodHead"
	head.position = Vector3(0.0, pivot_y, -0.02)
	head.rotation_degrees = Vector3(pitch_deg, 0.0, 0.0)
	root.add_child(head)

	var drum := MeshBuilder.cylinder(0.18, 0.32, color, 0.72, 0.22)
	drum.material_override = housing
	drum.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	drum.position = Vector3(0.0, 0.0, -0.22)
	drum.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(drum)

	var back_cap := MeshBuilder.cylinder(0.16, 0.05, dark, 0.8, 0.15)
	back_cap.material_override = steel
	back_cap.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	back_cap.position = Vector3(0.0, 0.0, -0.04)
	head.add_child(back_cap)

	for x in [-0.20, 0.20]:
		var knob := MeshBuilder.cylinder(0.035, 0.06, metal, 0.6, 0.4)
		knob.material_override = steel
		knob.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		knob.position = Vector3(x, 0.0, -0.08)
		head.add_child(knob)

	var guard := MeshBuilder.torus(0.18, 0.22, metal, 0.65, 0.35)
	guard.material_override = steel
	guard.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	guard.position = Vector3(0.0, 0.0, -0.40)
	head.add_child(guard)

	var dish := MeshInstance3D.new()
	var dish_mesh := CylinderMesh.new()
	dish_mesh.top_radius = 0.20
	dish_mesh.bottom_radius = 0.12
	dish_mesh.height = 0.07
	dish_mesh.radial_segments = 20
	dish.mesh = dish_mesh
	dish.material_override = MeshBuilder.make_material(Color(0.48, 0.48, 0.45), 0.45, 0.4)
	dish.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	dish.position = Vector3(0.0, 0.0, -0.36)
	dish.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(dish)

	var lens := MeshBuilder.cylinder(0.12, 0.035, Color(0.58, 0.55, 0.45), 0.12, 0.0)
	lens.name = "Lens"
	lens.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	lens.position = Vector3(0.0, 0.0, -0.40)
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(lens)


static func _add_light_cabin_visual(root: Node3D, sz: Vector3, color: Color) -> void:
	## Bulkhead / ceiling lamp — warm dome with a clear glass face.
	var metal := Color(0.4, 0.4, 0.42)
	var mount := MeshBuilder.cylinder(0.08, 0.05, metal, 0.7, 0.3)
	mount.position = Vector3(0.0, sz.y * 0.5 - 0.06, 0.0)
	root.add_child(mount)
	var shade := MeshBuilder.cylinder(0.14, 0.06, color, 0.55, 0.15)
	shade.position = Vector3(0.0, sz.y * 0.5 - 0.12, 0.0)
	root.add_child(shade)
	var bowl := MeshBuilder.sphere(0.12, Color(0.45, 0.38, 0.28), 0.25, 0.0)
	bowl.name = "Lens"
	bowl.position = Vector3(0.0, sz.y * 0.5 - 0.2, 0.0)
	root.add_child(bowl)


static func _add_light_ceiling_visual(root: Node3D, sz: Vector3, color: Color) -> void:
	## Flush ceiling fixture: rose → stem → frosted disc diffuser (glowing face = Lens).
	var metal := Color(0.38, 0.39, 0.41)
	var trim := Color(color.r * 0.72, color.g * 0.72, color.b * 0.70)
	var frost := Color(0.92, 0.88, 0.78)
	var top_y := sz.y * 0.5

	var rose := MeshBuilder.cylinder(0.16, 0.04, metal, 0.65, 0.35)
	rose.position = Vector3(0.0, top_y - 0.02, 0.0)
	root.add_child(rose)

	var stem := MeshBuilder.cylinder(0.035, 0.12, metal, 0.6, 0.4)
	stem.position = Vector3(0.0, top_y - 0.10, 0.0)
	root.add_child(stem)

	var pan := MeshBuilder.cylinder(0.28, 0.05, trim, 0.72, 0.2)
	pan.position = Vector3(0.0, top_y - 0.18, 0.0)
	root.add_child(pan)

	## Shallow dish rim (wider top, narrower bottom) hanging under the pan.
	var rim := MeshInstance3D.new()
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = 0.34
	rim_mesh.bottom_radius = 0.30
	rim_mesh.height = 0.06
	rim_mesh.radial_segments = 20
	rim.mesh = rim_mesh
	rim.material_override = MeshBuilder.make_material(trim, 0.7, 0.25)
	rim.position = Vector3(0.0, top_y - 0.22, 0.0)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rim)

	var lens := MeshBuilder.cylinder(0.30, 0.04, frost, 0.2, 0.0)
	lens.name = "Lens"
	lens.position = Vector3(0.0, top_y - 0.24, 0.0)
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(lens)


static func _add_light_nav_visual(root: Node3D, sz: Vector3, color: Color, brick_id: String) -> void:
	## Compact running-light housing; lens faces local −Z (port / starboard arcs).
	var metal := Color(0.3, 0.32, 0.34)
	var body := MeshBuilder.box(Vector3(0.22, 0.18, 0.28), metal, 0.7, 0.35)
	body.position = Vector3(0.0, -sz.y * 0.15, 0.05)
	root.add_child(body)
	var lens := MeshBuilder.box(Vector3(0.16, 0.12, 0.06), color, 0.2, 0.05)
	lens.name = "Lens"
	lens.position = Vector3(0.0, -sz.y * 0.15, -0.12)
	root.add_child(lens)
	var post := MeshBuilder.cylinder(0.04, 0.35, metal, 0.7, 0.3)
	post.position = Vector3(0.0, -sz.y * 0.35, 0.05)
	root.add_child(post)


static func _add_light_nav_white_visual(root: Node3D, sz: Vector3, color: Color) -> void:
	## Compact all-round white lantern — point light, visible from every bearing.
	var metal := Color(0.32, 0.34, 0.36)
	var stem := MeshBuilder.cylinder(0.035, 0.28, metal, 0.7, 0.3)
	stem.position = Vector3(0.0, -sz.y * 0.32, 0.0)
	root.add_child(stem)
	var base := MeshBuilder.cylinder(0.08, 0.04, metal, 0.75, 0.25)
	base.position = Vector3(0.0, -sz.y * 0.18, 0.0)
	root.add_child(base)
	var globe := MeshBuilder.sphere(0.09, color, 0.08, 0.02)
	globe.name = "Lens"
	globe.position = Vector3(0.0, -sz.y * 0.05, 0.0)
	globe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(globe)
	var cap := MeshBuilder.cylinder(0.07, 0.03, metal, 0.65, 0.35)
	cap.position = Vector3(0.0, 0.05, 0.0)
	root.add_child(cap)
	var emitter := Marker3D.new()
	emitter.name = "Emitter"
	emitter.position = Vector3(0.0, 0.12, 0.0)
	root.add_child(emitter)


static func _add_light_mast_white_visual(root: Node3D, sz: Vector3, color: Color) -> void:
	## 2×2 masthead lantern — open cage so the all-round globe (and OmniLight) are not buried.
	var metal := Color(0.30, 0.32, 0.34)
	var steel := _painted_palette_material(Palette.PAINTED_STEEL, metal, true)
	var y0 := -sz.y * 0.5

	var pad := MeshBuilder.box(Vector3(0.55, 0.06, 0.55), metal, 0.85, 0.2)
	pad.material_override = steel
	pad.position = Vector3(0.0, y0 + 0.04, 0.0)
	root.add_child(pad)

	var column := MeshBuilder.cylinder(0.06, 0.38, metal, 0.7, 0.3)
	column.material_override = steel
	column.position = Vector3(0.0, y0 + 0.26, 0.0)
	root.add_child(column)

	var platform := MeshBuilder.cylinder(0.16, 0.04, metal, 0.75, 0.25)
	platform.material_override = steel
	platform.position = Vector3(0.0, y0 + 0.46, 0.0)
	root.add_child(platform)

	## Open wire cage — bars only, so the globe stays visible from every bearing.
	var cage_y := y0 + 0.62
	for i in range(6):
		var ang := float(i) * TAU / 6.0
		var bar := MeshBuilder.box(Vector3(0.025, 0.28, 0.025), metal, 0.65, 0.35)
		bar.material_override = steel
		bar.position = Vector3(cos(ang) * 0.14, cage_y, sin(ang) * 0.14)
		root.add_child(bar)
	var ring := MeshBuilder.torus(0.13, 0.155, metal, 0.65, 0.35)
	ring.material_override = steel
	ring.position = Vector3(0.0, cage_y + 0.12, 0.0)
	root.add_child(ring)

	var globe := MeshBuilder.sphere(0.12, color, 0.08, 0.02)
	globe.name = "Lens"
	globe.position = Vector3(0.0, cage_y, 0.0)
	globe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(globe)

	var hood := MeshBuilder.cylinder(0.17, 0.045, metal, 0.65, 0.35)
	hood.material_override = steel
	hood.position = Vector3(0.0, cage_y + 0.16, 0.0)
	root.add_child(hood)

	## Emitter sits above the hood so the OmniLight is never inside solid mesh.
	var emitter := Marker3D.new()
	emitter.name = "Emitter"
	emitter.position = Vector3(0.0, cage_y + 0.22, 0.0)
	root.add_child(emitter)


static func _add_light_aim_gizmo(root: Node3D, brick_id: String) -> void:
	## Editor-only translucent cone / sphere so aim is obvious while placing.
	var entry := get_entry(brick_id)
	var lt := int(entry.get("light_type", 4))
	var gizmo := Node3D.new()
	gizmo.name = "AimGizmo"
	root.add_child(gizmo)
	match lt:
		4: ## WORK / flood — cone matches FloodHead pitch (toward deck / quay).
			var pitch := float(entry.get("housing_pitch_deg", entry.get("spot_pitch_deg", -45.0)))
			var length := float(entry.get("spot_range_m", 10.0)) * 0.55
			length = clampf(length, 6.0, 18.0)
			var end_r := 2.4 if has_tag(brick_id, "external") else 3.0
			var aim := Node3D.new()
			aim.rotation_degrees = Vector3(pitch, 0.0, 0.0)
			gizmo.add_child(aim)
			var cone := _make_aim_cone(Color(1.0, 0.92, 0.55, 0.18), length, end_r)
			cone.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			cone.position = Vector3(0.0, 0.0, -length * 0.5)
			aim.add_child(cone)
		2, 5: ## Masthead white / cabin omni — soft sphere (all bearings).
			var radius := 4.0 if has_tag(brick_id, "nav_white") else 2.5
			var ball_col := (
				Color(0.95, 0.95, 0.9, 0.14) if has_tag(brick_id, "nav_white")
				else Color(1.0, 0.75, 0.4, 0.12)
			)
			var ball := MeshBuilder.sphere(radius, ball_col, 0.9, 0.0)
			ball.position = Vector3.ZERO
			ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gizmo.add_child(ball)
		_: ## Port / stbd directional — cone along −Z.
			var nav_cone := _make_aim_cone(Color(0.7, 0.85, 1.0, 0.2), 6.0, 2.2)
			nav_cone.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			nav_cone.position = Vector3(0.0, 0.0, -3.0)
			gizmo.add_child(nav_cone)


static func _make_aim_cone(color: Color, length_m: float, end_radius: float) -> MeshInstance3D:
	## Tip (narrow) at −Y, wide at +Y. Callers rotate so −Y points toward the fixture
	## and +Y toward the throw (after a −90° X rot: −Y → +Z local of parent aim…).
	## With the usual aim setup (cone −90° X, centred along −Z): tip at the light, wide at deck.
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	## Godot cylinder: top = +Y, bottom = −Y. After parent −90° X, +Y → −Z (far), −Y → +Z (toward light).
	mesh.top_radius = end_radius
	mesh.bottom_radius = 0.02
	mesh.height = length_m
	mesh.radial_segments = 16
	mi.mesh = mesh
	var mat := MeshBuilder.make_material(color, 0.95, 0.0, true)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _window_glass_color(glass_color: Color) -> Color:
	var glass := Color(glass_color.r, glass_color.g, glass_color.b, minf(glass_color.a, 0.28))
	if glass.a >= 0.999:
		glass.a = 0.22
	return glass


static func _add_window_visual(root: Node3D, sz: Vector3, glass_color: Color) -> void:
	## Frame + glass flush on the local −Z face (yaw aims that outward).
	var post_w := WIN_POST
	var pane_t := WIN_PANE_T
	var frame_col := WIN_FRAME
	var face_z := -sz.z * 0.5 + pane_t * 0.5
	var frame_d := maxf(sz.z * 0.22, 0.16)

	var left := MeshBuilder.box(Vector3(post_w, sz.y, frame_d), frame_col, 0.85, 0.05)
	left.position = Vector3(-sz.x * 0.5 + post_w * 0.5, 0.0, face_z + frame_d * 0.25)
	root.add_child(left)
	var right := MeshBuilder.box(Vector3(post_w, sz.y, frame_d), frame_col, 0.85, 0.05)
	right.position = Vector3(sz.x * 0.5 - post_w * 0.5, 0.0, face_z + frame_d * 0.25)
	root.add_child(right)
	var top := MeshBuilder.box(Vector3(sz.x, post_w, frame_d), frame_col, 0.85, 0.05)
	top.position = Vector3(0.0, sz.y * 0.5 - post_w * 0.5, face_z + frame_d * 0.25)
	root.add_child(top)
	var bottom := MeshBuilder.box(Vector3(sz.x, post_w, frame_d), frame_col, 0.85, 0.05)
	bottom.position = Vector3(0.0, -sz.y * 0.5 + post_w * 0.5, face_z + frame_d * 0.25)
	root.add_child(bottom)

	var glass := _window_glass_color(glass_color)
	var pane := MeshBuilder.box(
		Vector3(sz.x - post_w * 2.0, sz.y - post_w * 2.0, pane_t),
		glass,
		0.05,
		0.15,
	)
	pane.position = Vector3(0.0, 0.0, face_z)
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pane)


static func _railing_edge_z(sz: Vector3) -> float:
	## Centre the thin rail on the local −Z cell face (outboard when yaw matches).
	return -sz.z * 0.5 + 0.028


static func _add_railing_visual(
	root: Node3D,
	length: float,
	height: float,
	color: Color,
	edge_z: float = 0.0,
) -> void:
	## Tileable maritime pipe railing.
	## Rails / toe plate span the full cell. Stanchions sit only on the ± cell
	## edges so neighbouring tiles share one post at each joint instead of
	## reading as many short independent railings. `edge_z` shifts the run onto
	## a face (straight bricks use the −Z face; 45° bricks stay on the diagonal).
	var material := _painted_palette_material(Palette.PAINTED_STEEL, color, true)
	var post_height := height * 0.88
	var half := length * 0.5
	## Tiny overlap so rail seams don't flash a gap under perspective.
	var rail_span := length + 0.02
	for x in [-half, half]:
		var post := MeshBuilder.cylinder(0.035, post_height, color, 0.68, 0.25)
		post.material_override = material
		post.position = Vector3(x, -height * 0.03, edge_z)
		root.add_child(post)
	for rail_data in [
		{"y": height * 0.41, "radius": 0.045},
		{"y": height * 0.10, "radius": 0.032},
	]:
		var rail := MeshBuilder.cylinder(
			float(rail_data["radius"]), rail_span, color, 0.65, 0.28
		)
		rail.material_override = material
		rail.position = Vector3(0.0, float(rail_data["y"]), edge_z)
		rail.rotation_degrees.z = 90.0
		root.add_child(rail)
	var toe_plate := MeshBuilder.box(
		Vector3(rail_span, height * 0.14, 0.055), color, 0.78, 0.18
	)
	toe_plate.material_override = material
	toe_plate.position = Vector3(0.0, -height * 0.42, edge_z)
	root.add_child(toe_plate)


static func _add_railing_mooring_visual(root: Node3D, sz: Vector3, color: Color) -> void:
	## Edge railing on −Z; mooring bit stays cell-centred so ropes clear the sheer rail.
	_add_railing_visual(root, sz.x, sz.y, color, _railing_edge_z(sz))
	var steel := _painted_palette_material(Palette.PAINTED_STEEL, color, true)
	var accent := Color(0.55, 0.52, 0.46)
	var bit_h := sz.y * 0.55
	var bit := MeshBuilder.cylinder(0.09, bit_h, color, 0.68, 0.3)
	bit.material_override = steel
	bit.position = Vector3(0.0, -sz.y * 0.5 + bit_h * 0.5 + 0.04, 0.0)
	root.add_child(bit)
	var base := MeshBuilder.cylinder(0.16, 0.05, Color(color.r * 0.85, color.g * 0.85, color.b * 0.85), 0.8, 0.2)
	base.material_override = steel
	base.position = Vector3(0.0, -sz.y * 0.5 + 0.05, 0.0)
	root.add_child(base)
	var horn := MeshBuilder.cylinder(0.04, 0.32, accent, 0.6, 0.4)
	horn.material_override = steel
	horn.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	horn.position = Vector3(0.0, -sz.y * 0.5 + bit_h * 0.72, 0.0)
	root.add_child(horn)
	var cap := MeshBuilder.cylinder(0.11, 0.05, accent, 0.55, 0.4)
	cap.material_override = steel
	cap.position = Vector3(0.0, -sz.y * 0.5 + bit_h + 0.02, 0.0)
	root.add_child(cap)


static func _add_railing_45_visual(root: Node3D, sz: Vector3, color: Color) -> void:
	## Diagonal matches block_45 / window_45 (missing corner = local +X,+Z).
	## Posts land on the two kept outer corners so an edge-aligned straight
	## railing on a neighbour cell meets the run with no centre-cell gap.
	var diagonal_len := sqrt(sz.x * sz.x + sz.z * sz.z)
	var yaw_deg := rad_to_deg(atan2(sz.z, sz.x))
	var segment := Node3D.new()
	segment.rotation_degrees.y = yaw_deg
	root.add_child(segment)
	_add_railing_visual(segment, diagonal_len, sz.y, color, 0.0)


static func _add_window_45_visual(root: Node3D, sz: Vector3, glass_color: Color) -> void:
	## Pane lies on the triangular block's diagonal face; missing corner is (+X,+Z).
	var post_w := WIN_POST
	var pane_t := WIN_PANE_T
	var frame_col := WIN_FRAME
	var glass := _window_glass_color(glass_color)
	var diagonal := sqrt(sz.x * sz.x + sz.z * sz.z)
	var tangent := Vector3(sz.x, 0.0, -sz.z).normalized()
	var outward := Vector3(sz.z, 0.0, sz.x).normalized()
	var yaw_deg := rad_to_deg(atan2(sz.z, sz.x))
	var frame_d := maxf(minf(sz.x, sz.z) * 0.22, 0.16)
	var face_offset := outward * pane_t * 0.5
	var frame_offset := outward * frame_d * 0.25

	for side in [-1.0, 1.0]:
		var post := MeshBuilder.box(Vector3(post_w, sz.y, frame_d), frame_col, 0.85, 0.05)
		post.rotation_degrees.y = yaw_deg
		post.position = tangent * side * (diagonal * 0.5 - post_w * 0.5) + frame_offset
		root.add_child(post)

	for side in [-1.0, 1.0]:
		var rail := MeshBuilder.box(Vector3(diagonal, post_w, frame_d), frame_col, 0.85, 0.05)
		rail.rotation_degrees.y = yaw_deg
		rail.position = Vector3(0.0, side * (sz.y * 0.5 - post_w * 0.5), 0.0) + frame_offset
		root.add_child(rail)

	var pane := MeshBuilder.box(
		Vector3(diagonal - post_w * 2.0, sz.y - post_w * 2.0, pane_t),
		glass,
		0.05,
		0.15,
	)
	pane.rotation_degrees.y = yaw_deg
	pane.position = face_offset
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pane)


static func _add_window_corner_visual(root: Node3D, sz: Vector3, glass_color: Color) -> void:
	## Outer corner: glass on −Z and −X faces, shared stile at the outer edge.
	var post_w := WIN_POST
	var pane_t := WIN_PANE_T
	var frame_col := WIN_FRAME
	var glass := _window_glass_color(glass_color)
	var frame_d := maxf(minf(sz.x, sz.z) * 0.22, 0.16)
	var face_z := -sz.z * 0.5 + pane_t * 0.5
	var face_x := -sz.x * 0.5 + pane_t * 0.5
	var open_x := sz.x - post_w
	var open_z := sz.z - post_w

	var corner_post := MeshBuilder.box(Vector3(post_w, sz.y, post_w), frame_col, 0.85, 0.05)
	corner_post.position = Vector3(face_x + post_w * 0.25, 0.0, face_z + post_w * 0.25)
	root.add_child(corner_post)

	var top_z := MeshBuilder.box(Vector3(open_x, post_w, frame_d), frame_col, 0.85, 0.05)
	top_z.position = Vector3(-post_w * 0.5, sz.y * 0.5 - post_w * 0.5, face_z + frame_d * 0.25)
	root.add_child(top_z)
	var bot_z := MeshBuilder.box(Vector3(open_x, post_w, frame_d), frame_col, 0.85, 0.05)
	bot_z.position = Vector3(-post_w * 0.5, -sz.y * 0.5 + post_w * 0.5, face_z + frame_d * 0.25)
	root.add_child(bot_z)
	var pane_z := MeshBuilder.box(
		Vector3(open_x - post_w, sz.y - post_w * 2.0, pane_t),
		glass,
		0.05,
		0.15,
	)
	pane_z.position = Vector3(-post_w * 0.5, 0.0, face_z)
	pane_z.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pane_z)

	var top_x := MeshBuilder.box(Vector3(frame_d, post_w, open_z), frame_col, 0.85, 0.05)
	top_x.position = Vector3(face_x + frame_d * 0.25, sz.y * 0.5 - post_w * 0.5, -post_w * 0.5)
	root.add_child(top_x)
	var bot_x := MeshBuilder.box(Vector3(frame_d, post_w, open_z), frame_col, 0.85, 0.05)
	bot_x.position = Vector3(face_x + frame_d * 0.25, -sz.y * 0.5 + post_w * 0.5, -post_w * 0.5)
	root.add_child(bot_x)
	var pane_x := MeshBuilder.box(
		Vector3(pane_t, sz.y - post_w * 2.0, open_z - post_w),
		glass,
		0.05,
		0.15,
	)
	pane_x.position = Vector3(face_x, 0.0, -post_w * 0.5)
	pane_x.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pane_x)


static func _add_door_visual(root: Node3D, sz: Vector3, color: Color) -> void:
	## Wall-cutout doorway with a real two-faced leaf (panels + handles both sides).
	## Hinge on local -X; yaw aims the passage along +/-Z.
	var frame := _add_door_frame(root, sz, color)
	var open_w: float = frame["open_w"]
	var leaf_h: float = frame["leaf_h"]
	var hinge_y: float = frame["hinge_y"]
	var post_w: float = frame["post_w"]
	var leaf_col: Color = frame["leaf_col"]
	var panel_col: Color = frame["panel_col"]
	var brass: Color = frame["brass"]
	var leaf_w := open_w - 0.05
	_add_door_leaf(
		root,
		"DoorHinge",
		Vector3(-sz.x * 0.5 + post_w + 0.01, hinge_y, 0.0),
		leaf_w,
		leaf_h,
		leaf_col,
		panel_col,
		brass,
		false,
	)


static func _add_double_door_visual(root: Node3D, sz: Vector3, color: Color) -> void:
	## Paired leaves meeting at centre — DoorHinge (port) + DoorHingeR (starboard).
	var frame := _add_door_frame(root, sz, color)
	var open_w: float = frame["open_w"]
	var leaf_h: float = frame["leaf_h"]
	var hinge_y: float = frame["hinge_y"]
	var post_w: float = frame["post_w"]
	var leaf_col: Color = frame["leaf_col"]
	var panel_col: Color = frame["panel_col"]
	var brass: Color = frame["brass"]
	var gap := 0.04
	var leaf_w := (open_w - gap) * 0.5
	_add_door_leaf(
		root,
		"DoorHinge",
		Vector3(-sz.x * 0.5 + post_w + 0.01, hinge_y, 0.0),
		leaf_w,
		leaf_h,
		leaf_col,
		panel_col,
		brass,
		false,
	)
	_add_door_leaf(
		root,
		"DoorHingeR",
		Vector3(sz.x * 0.5 - post_w - 0.01, hinge_y, 0.0),
		leaf_w,
		leaf_h,
		leaf_col,
		panel_col,
		brass,
		true,
	)


static func _add_door_frame(root: Node3D, sz: Vector3, color: Color) -> Dictionary:
	var frame_col := Color(color.r * 0.72, color.g * 0.72, color.b * 0.72)
	var leaf_col := Color(minf(color.r * 1.12, 1.0), color.g * 0.98, color.b * 0.88)
	var panel_col := Color(leaf_col.r * 0.86, leaf_col.g * 0.86, leaf_col.b * 0.86)
	var trim_col := Color(color.r * 0.55, color.g * 0.55, color.b * 0.55)
	var brass := Color(0.78, 0.64, 0.30)
	var post_w := 0.16
	var lintel_h := 0.22
	var sill_h := 0.10
	var frame_d := sz.z

	var left := MeshBuilder.box(Vector3(post_w, sz.y, frame_d), frame_col, 0.88, 0.04)
	left.position = Vector3(-sz.x * 0.5 + post_w * 0.5, 0.0, 0.0)
	root.add_child(left)
	var right := MeshBuilder.box(Vector3(post_w, sz.y, frame_d), frame_col, 0.88, 0.04)
	right.position = Vector3(sz.x * 0.5 - post_w * 0.5, 0.0, 0.0)
	root.add_child(right)

	var open_w := sz.x - post_w * 2.0
	var lintel := MeshBuilder.box(Vector3(open_w, lintel_h, frame_d), frame_col, 0.88, 0.04)
	lintel.position = Vector3(0.0, sz.y * 0.5 - lintel_h * 0.5, 0.0)
	root.add_child(lintel)
	var sill := MeshBuilder.box(Vector3(open_w, sill_h, frame_d), trim_col, 0.9, 0.04)
	sill.position = Vector3(0.0, -sz.y * 0.5 + sill_h * 0.5, 0.0)
	root.add_child(sill)

	return {
		"open_w": open_w,
		"leaf_h": sz.y - lintel_h - sill_h - 0.06,
		"hinge_y": (sill_h - lintel_h) * 0.5,
		"post_w": post_w,
		"leaf_col": leaf_col,
		"panel_col": panel_col,
		"brass": brass,
	}


static func _add_door_leaf(
		root: Node3D,
		hinge_name: String,
		hinge_pos: Vector3,
		leaf_w: float,
		leaf_h: float,
		leaf_col: Color,
		panel_col: Color,
		brass: Color,
		hinge_on_right: bool,
) -> void:
	var leaf_t := 0.10
	var hinge := Node3D.new()
	hinge.name = hinge_name
	hinge.position = hinge_pos
	root.add_child(hinge)

	## Visible hinge barrels on the jamb edge.
	for i in range(3):
		var t := (float(i) + 0.5) / 3.0
		var barrel := MeshBuilder.cylinder(0.035, 0.14, brass, 0.45, 0.55)
		barrel.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		barrel.position = Vector3(
			-0.02 if hinge_on_right else 0.02,
			-leaf_h * 0.5 + t * leaf_h,
			0.0,
		)
		hinge.add_child(barrel)

	var leaf := MeshBuilder.box(Vector3(leaf_w, leaf_h, leaf_t), leaf_col, 0.78, 0.05)
	leaf.name = "DoorLeaf"
	leaf.position = Vector3(-leaf_w * 0.5 if hinge_on_right else leaf_w * 0.5, 0.0, 0.0)
	hinge.add_child(leaf)

	_add_door_face(leaf, leaf_w, leaf_h, leaf_t * 0.5 + 0.01, panel_col, brass, false, hinge_on_right)
	_add_door_face(leaf, leaf_w, leaf_h, -(leaf_t * 0.5 + 0.01), panel_col, brass, true, hinge_on_right)


static func _add_door_face(
		leaf: Node3D,
		leaf_w: float,
		leaf_h: float,
		face_z: float,
		panel_col: Color,
		brass: Color,
		back_face: bool,
		mirror_handle: bool = false,
) -> void:
	var stile_w := 0.12
	var rail_h := 0.12
	var inset := 0.02
	var left_stile := MeshBuilder.box(Vector3(stile_w, leaf_h - inset * 2.0, inset), panel_col, 0.8, 0.04)
	left_stile.position = Vector3(-leaf_w * 0.5 + stile_w * 0.5 + inset, 0.0, face_z)
	leaf.add_child(left_stile)
	var right_stile := MeshBuilder.box(Vector3(stile_w, leaf_h - inset * 2.0, inset), panel_col, 0.8, 0.04)
	right_stile.position = Vector3(leaf_w * 0.5 - stile_w * 0.5 - inset, 0.0, face_z)
	leaf.add_child(right_stile)
	var top_rail := MeshBuilder.box(Vector3(leaf_w - inset * 2.0, rail_h, inset), panel_col, 0.8, 0.04)
	top_rail.position = Vector3(0.0, leaf_h * 0.5 - rail_h * 0.5 - inset, face_z)
	leaf.add_child(top_rail)
	var mid_rail := MeshBuilder.box(Vector3(leaf_w - stile_w * 2.0 - inset, rail_h * 0.85, inset), panel_col, 0.8, 0.04)
	mid_rail.position = Vector3(0.0, leaf_h * 0.08, face_z)
	leaf.add_child(mid_rail)
	var bot_rail := MeshBuilder.box(Vector3(leaf_w - inset * 2.0, rail_h, inset), panel_col, 0.8, 0.04)
	bot_rail.position = Vector3(0.0, -leaf_h * 0.5 + rail_h * 0.5 + inset, face_z)
	leaf.add_child(bot_rail)

	var panel_w := leaf_w - stile_w * 2.0 - 0.08
	var upper := MeshBuilder.box(Vector3(panel_w, leaf_h * 0.42, 0.015), panel_col, 0.84, 0.03)
	upper.position = Vector3(0.0, leaf_h * 0.28, face_z)
	leaf.add_child(upper)
	var lower := MeshBuilder.box(Vector3(panel_w, leaf_h * 0.28, 0.015), panel_col, 0.84, 0.03)
	lower.position = Vector3(0.0, -leaf_h * 0.26, face_z)
	leaf.add_child(lower)

	var handle_x := (leaf_w * 0.5 - 0.18) * (-1.0 if mirror_handle else 1.0)
	var handle_z := face_z + (0.035 if face_z > 0.0 else -0.035)
	var plate := MeshBuilder.box(Vector3(0.08, 0.28, 0.02), brass, 0.45, 0.55)
	plate.position = Vector3(handle_x, 0.0, handle_z)
	leaf.add_child(plate)
	var lever := MeshBuilder.box(Vector3(0.16, 0.04, 0.04), brass, 0.45, 0.55)
	var lever_dx := 0.04 if mirror_handle else -0.04
	lever.position = Vector3(handle_x + lever_dx, 0.0, handle_z + (0.03 if not back_face else -0.03))
	leaf.add_child(lever)


static func _add_bollard_visual(root: Node3D, sz: Vector3, color: Color) -> void:
	## Compact bollard — sits on deck or on a bulwark cell (half-wall).
	var post_h := sz.y * 0.55
	var post := MeshBuilder.cylinder(0.11, post_h, color, 0.7, 0.35)
	post.position = Vector3(0.0, -sz.y * 0.5 + post_h * 0.5 + 0.02, 0.0)
	root.add_child(post)
	var base := MeshBuilder.cylinder(0.20, 0.06, Color(color.r * 0.85, color.g * 0.85, color.b * 0.85), 0.85, 0.2)
	base.position = Vector3(0.0, -sz.y * 0.5 + 0.05, 0.0)
	root.add_child(base)
	var horn := MeshBuilder.cylinder(0.045, sz.x * 0.5, Color(0.55, 0.52, 0.45), 0.65, 0.4)
	horn.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	horn.position = Vector3(0.0, -sz.y * 0.5 + post_h * 0.7, 0.0)
	root.add_child(horn)


static func _add_mast_base_visual(root: Node3D, sz: Vector3, color: Color) -> void:
	## 2×2 deck tabernacle with a short spar stub — stack mast_pole layers above.
	var steel := _painted_palette_material(Palette.PAINTED_STEEL, color, true)
	var dark := Color(color.r * 0.75, color.g * 0.75, color.b * 0.78)
	var y0 := -sz.y * 0.5

	var pad := MeshBuilder.box(Vector3(sz.x * 0.92, 0.10, sz.z * 0.92), dark, 0.88, 0.18)
	pad.material_override = steel
	pad.position = Vector3(0.0, y0 + 0.05, 0.0)
	root.add_child(pad)

	var plinth := MeshBuilder.box(Vector3(0.85, 0.16, 0.85), color, 0.8, 0.22)
	plinth.material_override = steel
	plinth.position = Vector3(0.0, y0 + 0.18, 0.0)
	root.add_child(plinth)

	var collar := MeshBuilder.cylinder(0.18, 0.14, color, 0.7, 0.3)
	collar.material_override = steel
	collar.position = Vector3(0.0, y0 + 0.34, 0.0)
	root.add_child(collar)

	var stub_h := sz.y - 0.40
	var stub := MeshBuilder.cylinder(0.095, stub_h, color, 0.68, 0.28)
	stub.material_override = steel
	stub.position = Vector3(0.0, y0 + 0.40 + stub_h * 0.5, 0.0)
	root.add_child(stub)

	var joint := MeshBuilder.cylinder(0.11, 0.06, Color(0.55, 0.52, 0.46), 0.65, 0.35)
	joint.material_override = steel
	joint.position = Vector3(0.0, y0 + sz.y - 0.03, 0.0)
	root.add_child(joint)


static func _add_mast_pole_visual(root: Node3D, sz: Vector3, color: Color) -> void:
	## One-metre spar segment centred on the 2×2 mast column. Stack for height.
	var steel := _painted_palette_material(Palette.PAINTED_STEEL, color, true)
	var accent := Color(0.55, 0.52, 0.46)
	## Slight length overlap so stacked segments read as one continuous spar.
	var spar_h := sz.y + 0.04
	var spar := MeshBuilder.cylinder(0.085, spar_h, color, 0.66, 0.28)
	spar.material_override = steel
	spar.position = Vector3.ZERO
	root.add_child(spar)

	for side in [-1.0, 1.0]:
		var cuff := MeshBuilder.cylinder(0.105, 0.05, accent, 0.6, 0.35)
		cuff.material_override = steel
		cuff.position = Vector3(0.0, side * (sz.y * 0.5 - 0.02), 0.0)
		root.add_child(cuff)


static func _add_chimney_visual(root: Node3D, sz: Vector3, color: Color) -> void:
	## Marine funnel / stack scaled to the brick footprint (base → trunk → cowl).
	var steel := _painted_palette_material(Palette.PAINTED_STEEL, color, true)
	var dark := Color(color.r * 0.7, color.g * 0.7, color.b * 0.72)
	var soot := Color(0.12, 0.12, 0.13)
	var accent := Color(0.55, 0.18, 0.14)
	var y0 := -sz.y * 0.5
	var plan := minf(sz.x, sz.z)
	var trunk_r := plan * 0.28
	var base_h := clampf(sz.y * 0.12, 0.22, 0.55)
	var cowl_h := clampf(sz.y * 0.14, 0.28, 0.70)
	var trunk_h := maxf(sz.y - base_h - cowl_h, sz.y * 0.5)

	var plinth := MeshBuilder.box(
		Vector3(sz.x * 0.88, base_h, sz.z * 0.88), dark, 0.88, 0.15
	)
	plinth.material_override = steel
	plinth.position = Vector3(0.0, y0 + base_h * 0.5, 0.0)
	root.add_child(plinth)

	var skirt := MeshBuilder.cylinder(trunk_r * 1.25, base_h * 0.55, color, 0.75, 0.2)
	skirt.material_override = steel
	skirt.position = Vector3(0.0, y0 + base_h * 0.75, 0.0)
	root.add_child(skirt)

	var trunk := MeshBuilder.cylinder(trunk_r, trunk_h, color, 0.72, 0.22)
	trunk.material_override = steel
	trunk.position = Vector3(0.0, y0 + base_h + trunk_h * 0.5, 0.0)
	root.add_child(trunk)

	## Mid banding rings.
	var band_n := 2 if sz.y < 4.0 else 3
	for i in range(band_n):
		var t := (float(i) + 1.0) / float(band_n + 1)
		var band := MeshBuilder.cylinder(trunk_r * 1.08, 0.06, dark, 0.7, 0.3)
		band.material_override = steel
		band.position = Vector3(0.0, y0 + base_h + trunk_h * t, 0.0)
		root.add_child(band)

	## Top cowl / lip with a dark soot throat.
	var cowl_y := y0 + base_h + trunk_h
	var cowl := MeshBuilder.cylinder(trunk_r * 1.22, cowl_h * 0.55, color, 0.7, 0.25)
	cowl.material_override = steel
	cowl.position = Vector3(0.0, cowl_y + cowl_h * 0.28, 0.0)
	root.add_child(cowl)

	var lip := MeshInstance3D.new()
	var lip_mesh := CylinderMesh.new()
	lip_mesh.top_radius = trunk_r * 1.35
	lip_mesh.bottom_radius = trunk_r * 1.05
	lip_mesh.height = cowl_h * 0.4
	lip_mesh.radial_segments = 20
	lip.mesh = lip_mesh
	lip.material_override = MeshBuilder.make_material(dark, 0.75, 0.2)
	lip.position = Vector3(0.0, cowl_y + cowl_h * 0.65, 0.0)
	root.add_child(lip)

	var throat := MeshBuilder.cylinder(trunk_r * 0.72, cowl_h * 0.2, soot, 0.95, 0.0)
	throat.position = Vector3(0.0, cowl_y + cowl_h * 0.78, 0.0)
	root.add_child(throat)

	## Small recognition band near the top (ship funnel cue).
	var stripe := MeshBuilder.cylinder(trunk_r * 1.06, 0.08, accent, 0.6, 0.15)
	stripe.material_override = steel
	stripe.position = Vector3(0.0, cowl_y - trunk_h * 0.12, 0.0)
	root.add_child(stripe)


static func _add_hull_ladder_visual(root: Node3D, sz: Vector3, color: Color) -> void:
	## Deck pad + outboard ladder hanging in local −X (yaw aims that toward the quay).
	var drop := 2.0
	var pad := MeshBuilder.box(Vector3(sz.x * 0.95, 0.08, sz.z * 0.95), color, 0.85, 0.15)
	pad.position = Vector3(0.0, -sz.y * 0.5 + 0.04, 0.0)
	root.add_child(pad)
	var rail_a := MeshBuilder.box(Vector3(0.08, drop, 0.08), color, 0.7, 0.25)
	rail_a.position = Vector3(-sz.x * 0.55, -drop * 0.5, -sz.z * 0.35)
	root.add_child(rail_a)
	var rail_b := MeshBuilder.box(Vector3(0.08, drop, 0.08), color, 0.7, 0.25)
	rail_b.position = Vector3(-sz.x * 0.55, -drop * 0.5, sz.z * 0.35)
	root.add_child(rail_b)
	var rung_n := 4
	for i in range(rung_n):
		var t := (float(i) + 0.5) / float(rung_n)
		var rung := MeshBuilder.box(Vector3(0.06, 0.06, sz.z * 0.72), Color(0.55, 0.5, 0.35), 0.75, 0.1)
		rung.position = Vector3(-sz.x * 0.55, -t * drop, 0.0)
		root.add_child(rung)
	# Quay-side foot plate so the climb target is obvious.
	var foot := MeshBuilder.box(Vector3(0.5, 0.08, sz.z * 0.8), color, 0.85, 0.1)
	foot.position = Vector3(-sz.x * 0.55 - 0.35, -drop, 0.0)
	root.add_child(foot)
