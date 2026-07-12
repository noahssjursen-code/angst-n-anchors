class_name BrickCatalog
extends RefCounted

## Lego-like ship fit-out bricks.
## Footprint is in cells (x,y,z) = (width, height, length). Cell size = DeckGrid.CELL_M (1.0 m).

const BRICKS: Dictionary = {
	"block": {
		"display": "Block",
		"footprint": [1, 1, 1],
		"tags": ["wall", "solid"],
		"mass_kg": 80.0,
		"color": Color(0.78, 0.80, 0.84),
	},
	"block_window": {
		"display": "Window",
		## 2 m wide × 1 m tall × 1 m deep.
		"footprint": [2, 1, 1],
		"tags": ["window"],
		"mass_kg": 55.0,
		"color": Color(0.40, 0.62, 0.82, 0.72),
	},
	"block_door": {
		"display": "Door",
		## 2 m wide × 3 m tall × 1 m deep — spans three layers.
		"footprint": [2, 3, 1],
		"tags": ["door"],
		"mass_kg": 90.0,
		"color": Color(0.48, 0.32, 0.20),
	},
	"ledge_45": {
		"display": "45° wedge",
		## Full cell cut on the diagonal — triangle brick / ramp.
		"footprint": [1, 1, 1],
		"tags": ["slope", "solid"],
		"mass_kg": 40.0,
		"color": Color(0.78, 0.80, 0.84),
	},
	"railing": {
		"display": "Railing",
		"footprint": [1, 1, 1],
		"tags": ["railing", "edge"],
		"mass_kg": 15.0,
		"color": Color(0.35, 0.38, 0.42),
	},
	"bollard": {
		"display": "Bollard",
		## Mooring post — often on a bulwark / half-wall, not only bare deck.
		"footprint": [1, 1, 1],
		"tags": ["mooring", "cleat"],
		"mass_kg": 55.0,
		"color": Color(0.42, 0.40, 0.36),
	},
	"cargo_tile": {
		"display": "Cargo zone",
		"footprint": [1, 1, 1],
		"tags": ["cargo", "floor"],
		"mass_kg": 20.0,
		"color": Color(0.40, 0.36, 0.30),
	},
	"crane_base": {
		"display": "Crane base",
		## 2×2 m pad.
		"footprint": [2, 1, 2],
		"tags": ["crane_base"],
		"mass_kg": 400.0,
		"color": Color(0.55, 0.45, 0.22),
	},
	"crane": {
		"display": "Crane arm",
		"footprint": [1, 2, 1],
		"tags": ["crane"],
		"mass_kg": 600.0,
		"color": Color(0.62, 0.52, 0.24),
	},
	"hull_ladder": {
		"display": "Hull ladder",
		## 2×2 m pad on the deck edge; rungs hang outboard so you climb aboard from the quay.
		"footprint": [2, 1, 2],
		"tags": ["ladder", "edge"],
		"mass_kg": 45.0,
		"color": Color(0.42, 0.44, 0.48),
		"deck_only": true,
		"edge_only": true,
	},
}


static func ids() -> Array[String]:
	var out: Array[String] = []
	for k in BRICKS.keys():
		out.append(str(k))
	out.sort()
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


static func display_name(brick_id: String) -> String:
	return str(get_entry(brick_id).get("display", brick_id))


static func has_tag(brick_id: String, tag: String) -> bool:
	var tags = get_entry(brick_id).get("tags", [])
	return tags is Array and (tags as Array).has(tag)


static func create_visual(brick_id: String, opts: Dictionary = {}) -> Node3D:
	## Mesh is centred on the origin; caller places the node at the footprint AABB centre.
	## opts.preview_mesh — when true, cargo tiles get a temporary plate (ghost / palette thumb).
	var root := Node3D.new()
	root.name = brick_id
	var entry := get_entry(brick_id)
	var color: Color = entry.get("color", Color(0.7, 0.7, 0.7)) as Color
	var sz := size_m(brick_id)
	var s := DeckGrid.CELL_M
	match brick_id:
		"block", "block_door", "block_window":
			# Entire footprint is that brick type — solid volume, no wall+inset.
			root.add_child(MeshBuilder.box(sz, color, 0.85 if brick_id != "block_window" else 0.15, 0.05 if brick_id == "block_window" else 0.0))
		"ledge_45":
			root.add_child(MeshBuilder.wedge_45(sz, color, 0.92, 0.0))
		"railing":
			var post_a := MeshBuilder.cylinder(0.04, sz.y * 0.95, color, 0.7, 0.2)
			post_a.position = Vector3(-sz.x * 0.35, 0.0, 0.0)
			root.add_child(post_a)
			var post_b := MeshBuilder.cylinder(0.04, sz.y * 0.95, color, 0.7, 0.2)
			post_b.position = Vector3(sz.x * 0.35, 0.0, 0.0)
			root.add_child(post_b)
			var rail := MeshBuilder.box(Vector3(sz.x, 0.06, 0.06), color, 0.7, 0.25)
			rail.position = Vector3(0.0, sz.y * 0.4, 0.0)
			root.add_child(rail)
			var kick := MeshBuilder.box(Vector3(sz.x, 0.08, 0.08), color, 0.85, 0.1)
			kick.position = Vector3(0.0, -sz.y * 0.44, 0.0)
			root.add_child(kick)
		"bollard":
			_add_bollard_visual(root, sz, color)
		"cargo_tile":
			## Paint-only marker — the cargo zone is drawn as one bordered pad, not N tiles.
			if bool(opts.get("preview_mesh", false)):
				var tile := MeshBuilder.box(Vector3(sz.x * 0.92, 0.06, sz.z * 0.92), color, 0.95, 0.0)
				tile.position = Vector3(0.0, -sz.y * 0.5 + 0.03, 0.0)
				root.add_child(tile)
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
		_:
			root.add_child(MeshBuilder.box(sz, color, 0.85, 0.0))
	return root


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


static func _add_hull_ladder_visual(root: Node3D, sz: Vector3, color: Color) -> void:
	## Deck pad + outboard ladder hanging in local −X (yaw aims that toward the quay).
	var drop := 4.2
	var pad := MeshBuilder.box(Vector3(sz.x * 0.95, 0.08, sz.z * 0.95), color, 0.85, 0.15)
	pad.position = Vector3(0.0, -sz.y * 0.5 + 0.04, 0.0)
	root.add_child(pad)
	var rail_a := MeshBuilder.box(Vector3(0.08, drop, 0.08), color, 0.7, 0.25)
	rail_a.position = Vector3(-sz.x * 0.55, -drop * 0.5, -sz.z * 0.35)
	root.add_child(rail_a)
	var rail_b := MeshBuilder.box(Vector3(0.08, drop, 0.08), color, 0.7, 0.25)
	rail_b.position = Vector3(-sz.x * 0.55, -drop * 0.5, sz.z * 0.35)
	root.add_child(rail_b)
	var rung_n := 8
	for i in range(rung_n):
		var t := (float(i) + 0.5) / float(rung_n)
		var rung := MeshBuilder.box(Vector3(0.06, 0.06, sz.z * 0.72), Color(0.55, 0.5, 0.35), 0.75, 0.1)
		rung.position = Vector3(-sz.x * 0.55, -t * drop, 0.0)
		root.add_child(rung)
	# Quay-side foot plate so the climb target is obvious.
	var foot := MeshBuilder.box(Vector3(0.5, 0.08, sz.z * 0.8), color, 0.85, 0.1)
	foot.position = Vector3(-sz.x * 0.55 - 0.35, -drop, 0.0)
	root.add_child(foot)
