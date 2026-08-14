extends SceneTree

## Scratch probe (leading underscore — not a gate unit).
## Authors the three starter vessels through the real BrickLayout API, validates
## each against VesselCompliance, and writes the prebuilt JSON only when the
## report says ok. Re-runnable: same input, same file.

const OUT_DIR := "res://resources/data/vessels/prebuilt"


func _initialize() -> void:
	var ok := true
	ok = _emit(_trawler(), {
		"id": "fishing_trawler",
		"name": "Coastal trawler",
		"registration_id": "fishing_vessel",
		"price_marks": 48000,
		"shaft_power_kw": 1871.0,
	}) and ok
	ok = _emit(_cargo(), {
		"id": "28_10_m",
		"name": "Coastal cargo vessel",
		"registration_id": "cargo_vessel",
		"price_marks": 52000,
		"shaft_power_kw": 1871.0,
	}) and ok
	ok = _emit(_bulk(), {
		"id": "bulk_small",
		"name": "Coastal bulk vessel",
		"registration_id": "bulk_vessel",
		"price_marks": 56000,
		"shaft_power_kw": 1871.0,
	}) and ok
	print("GEN %s" % ("OK" if ok else "REFUSED"))
	quit(0 if ok else 1)


# ── shared hull furniture ───────────────────────────────────────────────────

const HULL := "hull_28x10"


func _base(grid: DeckGrid) -> BrickLayout:
	var layout := BrickLayout.new()
	layout.hull_id = HULL
	## Deck-edge railing all round, the same mechanism `_paint_edge_railings`
	## uses — one railing per edge cell, so it follows the bow taper exactly.
	for ix in range(grid.width):
		for iz in range(grid.length):
			if not grid.is_edge_cell(ix, iz):
				continue
			layout.set_brick(Vector3i(ix, 0, iz), "railing", 0)
	return layout


## Four mooring points, two a side, fore and aft — the general-vessel minimum.
func _add_mooring(layout: BrickLayout, grid: DeckGrid) -> void:
	for z in [14, grid.length - 4]:
		for x in [0, grid.width - 1]:
			layout.set_brick(Vector3i(x, 0, z), "railing_mooring", 0)


## Deckhouse: a walled box with a glazed forward face, a door aft and a flat
## roof. `x0..x1` / `z0..z1` are inclusive perimeter cells; five levels is
## 2.5 m of headroom at the 0.5 m cell (CONVENTIONS §3a).
func _add_deckhouse(
	layout: BrickLayout, grid: DeckGrid, x0: int, x1: int, z0: int, z1: int
) -> Dictionary:
	var door_cells := {}
	for dx in range(2):
		for dy in range(3):
			door_cells[Vector3i(x0 + 2 + dx, dy, z1)] = true
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			var on_edge := x == x0 or x == x1 or z == z0 or z == z1
			if not on_edge:
				continue
			for y in range(5):
				var c := Vector3i(x, y, z)
				if door_cells.has(c):
					continue
				## Window band across the forward face and the front third of
				## each side, at eye height for the 1.8 m figure.
				var glazed := (y == 2 or y == 3) and (z == z0 or (x == x0 or x == x1) and z <= z0 + 2)
				layout.set_brick(c, "block_window" if glazed else "block", 0)
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			layout.set_brick(Vector3i(x, 5, z), "roof_flat", 0)
	layout.place_footprint(Vector3i(x0 + 2, 0, z1), "block_door", 0, grid)
	return {"port_wall": Vector3i(x0, 2, z0 + 2), "stbd_wall": Vector3i(x1, 2, z0 + 2)}


## Sidelights ride on the deckhouse walls as MOUNTED lights, which is what makes
## `brick_side` measurable: the host cell is the light's position, and the port
## light is on a cell whose local x is negative.
func _add_nav_lights(layout: BrickLayout, house: Dictionary, mast_top: Vector3i) -> void:
	layout.attach_light(house["port_wall"] as Vector3i, "light_nav_port", 270)
	layout.attach_light(house["stbd_wall"] as Vector3i, "light_nav_stbd", 90)
	layout.attach_light(mast_top, "light_mast_white", 0)


## Mast: a tabernacle base and three pole segments. The masthead light sits on
## the top segment, which is what puts it above the sidelights.
func _add_mast(layout: BrickLayout, grid: DeckGrid, x: int, z: int) -> Vector3i:
	layout.place_footprint(Vector3i(x, 0, z), "mast_base", 0, grid)
	for y in range(1, 4):
		layout.place_footprint(Vector3i(x, y, z), "mast_pole", 0, grid)
	return Vector3i(x, 3, z)


# ── the three starters ──────────────────────────────────────────────────────


func _trawler() -> Dictionary:
	var grid := HullRegistry.make_grid(HULL)
	var layout := _base(grid)
	_add_mooring(layout, grid)
	## Wheelhouse forward, open working deck aft — the sjark arrangement.
	var house := _add_deckhouse(layout, grid, 7, 12, 16, 23)
	layout.set_brick(Vector3i(9, 0, 18), "helm", 0)
	var mast_top := _add_mast(layout, grid, 9, 26)
	_add_nav_lights(layout, house, mast_top)
	## Net drum on the working deck aft of the house.
	layout.place_footprint(Vector3i(9, 0, 34), "trommel_small", 0, grid)
	return {"layout": layout, "registration_id": "fishing_vessel"}


func _cargo() -> Dictionary:
	var grid := HullRegistry.make_grid(HULL)
	var layout := _base(grid)
	_add_mooring(layout, grid)
	## Superstructure aft, clear cargo deck forward — the coaster arrangement.
	var house := _add_deckhouse(layout, grid, 7, 12, 40, 47)
	layout.set_brick(Vector3i(9, 0, 42), "helm", 0)
	var mast_top := _add_mast(layout, grid, 9, 36)
	_add_nav_lights(layout, house, mast_top)
	## Two container pads on the open deck. Spans tile the 4×4-cell container
	## footprint, which `add_container_pad` refuses otherwise.
	layout.add_container_pad(Vector3i(4, 0, 14, ), Vector3i(11, 0, 21), grid)
	layout.add_container_pad(Vector3i(4, 0, 22), Vector3i(11, 0, 29), grid)
	return {"layout": layout, "registration_id": "cargo_vessel"}


func _bulk() -> Dictionary:
	var grid := HullRegistry.make_grid(HULL)
	var layout := _base(grid)
	_add_mooring(layout, grid)
	var house := _add_deckhouse(layout, grid, 7, 12, 40, 47)
	layout.set_brick(Vector3i(9, 0, 42), "helm", 0)
	var mast_top := _add_mast(layout, grid, 9, 36)
	_add_nav_lights(layout, house, mast_top)
	## One hold amidships. `add_bulk_hold` registers the zone, which is what
	## `count_tag("bulk_hold")` reads — a placed brick would not count.
	layout.add_bulk_hold(Vector3i(7, 0, 16), "bulk_hold_6x12", 0, grid)
	return {"layout": layout, "registration_id": "bulk_vessel"}


# ── emit ────────────────────────────────────────────────────────────────────


func _emit(built: Dictionary, meta: Dictionary) -> bool:
	var layout: BrickLayout = built["layout"]
	var registration_id := str(meta["registration_id"])
	var grid := HullRegistry.make_grid(HULL)
	var report := VesselCompliance.validate(layout, HULL, registration_id, grid)
	var cells_n := (layout.to_dict().get("cells", {}) as Dictionary).size()
	print("--- %s (%s) cells=%d primaries=%d" % [
		meta["id"], registration_id, cells_n, layout.iter_primary_cells().size(),
	])
	for raw in report.get("checklist", []) as Array:
		var item := raw as Dictionary
		print("    %-24s %s  current=%s" % [
			str(item.get("id", "")), "ok " if bool(item.get("ok", false)) else "RED", str(item.get("current", "")),
		])
	for e in report.get("errors", PackedStringArray()):
		print("    ERR " + str(e))
	if not bool(report.get("ok", false)):
		return false
	var preset := {
		"format_version": 2,
		"id": str(meta["id"]),
		"name": str(meta["name"]),
		"hull_id": HULL,
		"registration_id": registration_id,
		"price_marks": int(meta["price_marks"]),
		"shaft_power_kw": float(meta["shaft_power_kw"]),
		"draft": false,
		"brick_layout": layout.to_dict(),
	}
	var path := "%s/%s.json" % [OUT_DIR, meta["id"]]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("    CANNOT WRITE " + path)
		return false
	f.store_string(JSON.stringify(preset, "  ", true) + "\n")
	f.close()
	print("    wrote " + path)
	return true
