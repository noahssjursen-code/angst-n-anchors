@tool
class_name PortFacilities
extends Node3D

## Land-side port facilities.
## Local Z = 0 is the dock inner edge; +Z goes inland.
##
## Layout: a central main street runs from dock face (+Z) through the island.
## Service buildings (HarbourMaster, ShippingAgent, MarineEngineer, Customs) flank
## the street in left/right columns, facing the dock (-Z). Warehouses sit at the
## far island flanks (high X offset), not blocking the street. Town tiles run as
## L/R pairs along the street further inland. Seeded RNG assigns sides per port.

const HARBOURMASTER_MESH_PATH   := "res://resources/data/meshes/harbour_master_building.json"
const SHIPPINGAGENT_MESH_PATH   := "res://resources/data/meshes/shipping_agent_building.json"
const CUSTOMS_MESH_PATH         := "res://resources/data/meshes/customs_building.json"
const MARINE_ENGINEER_MESH_PATH := "res://resources/data/meshes/marine_engineer_building.json"
const WAREHOUSE_MESH_PATH       := "res://resources/data/meshes/warehouse_building.json"
const TOWN_MESH_PATH            := "res://resources/data/meshes/town_building.json"
const FOGHORN_SCENE            := preload("res://scenes/systems/fog_horn_building.tscn")

const C_AUTHORITY := Color(0.78, 0.62, 0.14)
const C_COMMERCE  := Color(0.24, 0.64, 0.36)
const C_SERVICES  := Color(0.72, 0.34, 0.14)
const C_STORAGE   := Color(0.52, 0.56, 0.64)
const C_TOWN      := Color(0.64, 0.44, 0.28)
const C_ROAD      := Color(0.36, 0.34, 0.30)

## First building row starts this far from the dock inner edge.
const ROW_START_Z   : float = 8.0
## Z gap between consecutive street rows.
const ROW_Z_GAP     : float = 5.0
## Z gap between street section end and first tiled section (warehouse).
const SECTION_GAP   : float = 7.0
## Half of the central street width. Buildings start at ±(STREET_HALF + LANE_GAP).
const STREET_HALF   : float = 4.0
## Gap between street edge and nearest building face.
const LANE_GAP      : float = 1.5
## Lateral margin when centering tiled buildings (warehouse, town).
const EDGE_MARGIN   : float = 4.0

var _rng: RandomNumberGenerator = null

var _spawn_local_pos:          Vector3 = Vector3.ZERO
var _harbour_master_local_pos: Vector3 = Vector3.ZERO
var _contract_npc_local_pos:   Vector3 = Vector3.ZERO
var _delivery_npc_local_pos:   Vector3 = Vector3.ZERO

@export var port_size: int = 1:
	set(v): port_size = v; if is_inside_tree(): _rebuild()

@export var plot_width: float = 80.0:
	set(v): plot_width = v; if is_inside_tree(): _rebuild()

@export var plot_depth: float = 74.0:
	set(v): plot_depth = v; if is_inside_tree(): _rebuild()

@export var layout_seed: int = 0:
	set(v): layout_seed = v; if is_inside_tree(): _rebuild()

@export var has_lighthouse: bool = false:
	set(v): has_lighthouse = v; if is_inside_tree(): _rebuild()

@export var has_fog_horn: bool = false:
	set(v): has_fog_horn = v; if is_inside_tree(): _rebuild()


func _ready() -> void:
	call_deferred("_rebuild")


func _rebuild() -> void:
	for child in get_children():
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()

	_build_facilities()

	if Engine.is_editor_hint():
		var esc := get_tree().edited_scene_root
		if esc != null:
			for child in get_children():
				_own_subtree(child, esc)


func _build_facilities() -> void:
	_spawn_local_pos          = Vector3.ZERO
	_harbour_master_local_pos = Vector3.ZERO
	_contract_npc_local_pos   = Vector3.ZERO
	_delivery_npc_local_pos   = Vector3.ZERO

	_rng = RandomNumberGenerator.new()
	_rng.seed = layout_seed

	# Separate defs into street buildings, warehouse, and town
	var street_defs: Array = []
	var warehouse_def: Dictionary = {}
	var town_def: Dictionary = {}

	for def in _facility_defs():
		var d  := def as Dictionary
		var id := str(d["id"])
		if int(d["min_size"]) > port_size:
			continue
		if id == "Warehouse":
			warehouse_def = d
		elif id == "Town":
			town_def = d
		else:
			street_defs.append(d)

	# Group street buildings by priority (lower = dock-side)
	var priority_groups: Dictionary = {}
	for def in street_defs:
		var d   := def as Dictionary
		var pri := int(d["priority"])
		if not priority_groups.has(pri):
			priority_groups[pri] = []
		(priority_groups[pri] as Array).append(d)

	var priorities: Array = priority_groups.keys()
	priorities.sort()

	var cursor_z := ROW_START_Z

	for priority in priorities:
		var row := priority_groups[priority] as Array
		_shuffle_array(row)

		var row_depth := 0.0
		for def in row:
			row_depth = maxf(row_depth, float((def as Dictionary)["d"]))

		_place_street_row(row, cursor_z + row_depth * 0.5)
		cursor_z += row_depth + ROW_Z_GAP

	# Entry posts mark the street entrance at dock edge
	_box(Vector3(0.18, 1.2, 0.18), Vector3(-(STREET_HALF + 0.3), 0.6, 0.4),
		 Color(0.20, 0.20, 0.22), "StreetPostL")
	_box(Vector3(0.18, 1.2, 0.18), Vector3(+(STREET_HALF + 0.3), 0.6, 0.4),
		 Color(0.20, 0.20, 0.22), "StreetPostR")

	var service_end_z := cursor_z
	cursor_z += SECTION_GAP

	# Warehouses — beside the town section, at island flanks
	if not warehouse_def.is_empty():
		var wh_z := cursor_z + float(warehouse_def["w"]) * 0.5
		_place_warehouses_aside(warehouse_def, wh_z)

	# Town — L/R pairs along the street, running inland
	var road_end_z := service_end_z
	if not town_def.is_empty():
		road_end_z = _place_town_street_pairs(town_def, cursor_z)

	# Road strip extends through full town section
	_road_strip(road_end_z + 4.0)

	# Landmarks (Lighthouse, Fog Horn)
	_place_landmarks()


# ── Street layout ─────────────────────────────────────────────────────────────

func _place_street_row(defs: Array, center_z: float) -> void:
	if defs.is_empty():
		return

	if defs.size() == 1:
		# Single building — place on seeded side
		var d  := defs[0] as Dictionary
		var id := str(d["id"])
		var bw := float(d["w"])
		var bd := float(d["d"])
		var side := _rng.randi() % 2
		var bx := _street_x(bw, side)
		_place_facility(id, Vector3(bx, 0.0, center_z))
		_track_npc_pos(id, bx, center_z, bd)
		return

	# Two buildings: index 0 → left (side 0), index 1 → right (side 1)
	for i in range(mini(2, defs.size())):
		var d  := defs[i] as Dictionary
		var id := str(d["id"])
		var bw := float(d["w"])
		var bd := float(d["d"])
		var bx := _street_x(bw, i)
		_place_facility(id, Vector3(bx, 0.0, center_z))
		_track_npc_pos(id, bx, center_z, bd)


func _street_x(building_w: float, side: int) -> float:
	# side 0 = left (negative X), side 1 = right (positive X)
	var offset := STREET_HALF + LANE_GAP + building_w * 0.5
	return -offset if side == 0 else offset


func _road_strip(length: float) -> void:
	var mi               := MeshInstance3D.new()
	mi.name              = "MainStreet"
	var mesh             := BoxMesh.new()
	mesh.size            = Vector3(STREET_HALF * 2.0, 0.06, length)
	mi.mesh              = mesh
	var mat              := StandardMaterial3D.new()
	mat.albedo_color     = C_ROAD
	mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position          = Vector3(0.0, 0.03, length * 0.5)
	add_child(mi)


# ── Tiled rows (warehouse, town) ──────────────────────────────────────────────

func _place_tiled_row(def: Dictionary, center_z: float) -> void:
	var id        := str(def["id"])
	var tile_w    := float(def["w"])
	var tile_gap  := float(def.get("tile_gap", 2.0))
	var mt_arr    := def.get("max_tiles", [1]) as Array
	var sz_idx    := clampi(port_size, 0, mt_arr.size() - 1)
	var max_tiles := int(mt_arr[sz_idx])

	var available_w := plot_width - EDGE_MARGIN * 2.0
	var tile_step   := tile_w + tile_gap
	var fit_tiles   := maxi(1, int(available_w / tile_step))
	var n_tiles     := mini(fit_tiles, max_tiles)

	var total_w  := float(n_tiles) * tile_w + float(n_tiles - 1) * tile_gap
	var slack    := maxf(0.0, available_w - total_w)
	var shift    := _rng.randf_range(-slack * 0.20, slack * 0.20)
	var cursor_x := -total_w * 0.5 + shift

	for i in range(n_tiles):
		var bx := cursor_x + tile_w * 0.5
		_place_facility(id, Vector3(bx, 0.0, center_z))
		_track_npc_pos(id, bx, center_z, float(def["d"]))
		cursor_x += tile_step


# ── Side / street-pair placements ────────────────────────────────────────────

func _place_warehouses_aside(def: Dictionary, center_z: float) -> void:
	var wh_w   := float(def["w"])  # 24m — Z extent after 90° rotation
	var wh_d   := float(def["d"])  # 12m — X extent after 90° rotation
	var n_arr  := [1, 1, 1, 2, 2]
	var sz_idx := clampi(port_size, 0, n_arr.size() - 1)
	var n_wh   := int(n_arr[sz_idx])
	# Post-rotation X footprint is wh_d wide; inner edge must clear town tile outer edge (~33.5 m)
	var cx_abs := plot_width * 0.5 - EDGE_MARGIN - wh_d * 0.5
	if cx_abs - wh_d * 0.5 < STREET_HALF + LANE_GAP + 30.0:
		return  # island too narrow — warehouse would overlap town tiles
	if n_wh == 1:
		var side := _rng.randi() % 2
		var cx   := -cx_abs if side == 0 else cx_abs
		_warehouse_building(Vector3(cx, 0.0, center_z), PI * 0.5)
		_track_npc_pos("Warehouse", cx, center_z, wh_w)
	else:
		_warehouse_building(Vector3(-cx_abs, 0.0, center_z), PI * 0.5)
		_track_npc_pos("Warehouse", -cx_abs, center_z, wh_w)
		_warehouse_building(Vector3(cx_abs, 0.0, center_z), PI * 0.5)


func _place_town_street_pairs(def: Dictionary, start_z: float) -> float:
	var tile_w  := float(def["w"])
	var tile_d  := float(def["d"])
	var n_arr   := [0, 1, 2, 3, 3]
	var sz_idx  := clampi(port_size, 0, n_arr.size() - 1)
	var n_pairs := int(n_arr[sz_idx])
	var cx      := STREET_HALF + LANE_GAP + tile_w * 0.5  # outer edge must fit inside island half

	# Fallback: size 0 has no pairs, or island too narrow for street-side tiles
	if n_pairs == 0 or plot_width * 0.5 < cx + tile_w * 0.5:
		_place_tiled_row(def, start_z + tile_d * 0.5)
		return start_z + tile_d

	var cursor_z := start_z
	for _i in range(n_pairs):
		var pair_z := cursor_z + tile_d * 0.5
		_place_facility("Town", Vector3(-cx, 0.0, pair_z))
		_place_facility("Town", Vector3( cx, 0.0, pair_z))
		cursor_z += tile_d + ROW_Z_GAP

	return cursor_z - ROW_Z_GAP  # Z of last pair's far edge


# ── Shared placement helpers ──────────────────────────────────────────────────

func _place_landmarks() -> void:
	print("[PortFacilities] Placing landmarks. FogHorn: ", has_fog_horn, " Lighthouse: ", has_lighthouse)
	if not has_lighthouse and not has_fog_horn:
		return

	# Place them at the far left/right edges of the dock-side area.
	# We want them to be visible from the sea, so near Z=0 but at the island flanks.
	var edge_x := plot_width * 0.5 - 6.0
	var edge_z := 2.0 # Near the dock face

	var lighthouse_side := -1

	if has_lighthouse:
		lighthouse_side = _rng.randi() % 2
		var lx := -edge_x if lighthouse_side == 0 else edge_x
		_lighthouse_building(Vector3(lx, 0.0, edge_z))

	if has_fog_horn:
		var side := 1
		if lighthouse_side != -1:
			side = 1 - lighthouse_side # Opposite of lighthouse
		else:
			side = _rng.randi() % 2

		var fx := -edge_x if side == 0 else edge_x
		_fog_horn_building(Vector3(fx, 0.0, edge_z))


func _place_facility(id: String, pos: Vector3) -> void:
	if id == "HarbourMaster":
		_harbourmaster_building(pos)
	elif id == "ShippingAgent":
		_shippingagent_building(pos)
	elif id == "Customs":
		_customs_building(pos)
	elif id == "MarineEngineer":
		_marine_engineer_building(pos)
	elif id == "Warehouse":
		_warehouse_building(pos)
	elif id == "Town":
		_town_building(pos)


func _track_npc_pos(id: String, cx: float, center_z: float, depth: float) -> void:
	match id:
		"HarbourMaster":
			_harbour_master_local_pos = Vector3(cx, 0.0, center_z)
			_spawn_local_pos          = Vector3(0.0, 0.02, center_z - depth * 0.5 - 2.0)
		"ShippingAgent":
			_contract_npc_local_pos   = Vector3(cx, 0.0, center_z)
		"Warehouse":
			_delivery_npc_local_pos   = Vector3(cx, 0.0, center_z)


func _shuffle_array(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j        := _rng.randi() % (i + 1)
		var tmp: Variant = arr[i]
		arr[i]       = arr[j]
		arr[j]       = tmp


# ── Facility definitions ──────────────────────────────────────────────────────

func _facility_defs() -> Array:
	## priority 0 = dock row (placed first, closest to water)
	## Warehouse and Town use tile=true with max_tiles[size 0..4].
	return [
		{ "id": "HarbourMaster",  "w":  8.0, "h": 5.0, "d":  7.0, "priority": 0, "color": C_AUTHORITY, "min_size": 0 },
		{ "id": "ShippingAgent",  "w": 10.0, "h": 5.0, "d":  8.0, "priority": 0, "color": C_COMMERCE,  "min_size": 1 },
		{ "id": "MarineEngineer", "w": 11.0, "h": 4.0, "d":  9.0, "priority": 1, "color": C_SERVICES,  "min_size": 2 },
		{ "id": "Customs",        "w":  8.0, "h": 5.0, "d":  7.0, "priority": 1, "color": C_AUTHORITY, "min_size": 2 },
		{ "id": "Warehouse",      "w": 24.0, "h": 6.0, "d": 12.0, "priority": 2, "color": C_STORAGE,   "min_size": 0, "tile": true, "tile_gap": 2.5, "max_tiles": [1, 1, 2, 3,  5] },
		{ "id": "Town",           "w": 28.0, "h": 5.0, "d": 14.0, "priority": 3, "color": C_TOWN,      "min_size": 0, "tile": true, "tile_gap": 2.0, "max_tiles": [2, 3, 4, 6, 10] },
	]


# ── Accessors ─────────────────────────────────────────────────────────────────

func get_spawn_position() -> Vector3:
	return to_global(_spawn_local_pos)

func get_harbour_master_local_pos() -> Vector3:
	return _harbour_master_local_pos

func get_contract_npc_local_pos() -> Vector3:
	return _contract_npc_local_pos

func get_delivery_npc_local_pos() -> Vector3:
	return _delivery_npc_local_pos


# ── Building constructors ─────────────────────────────────────────────────────

func _harbourmaster_building(pos: Vector3) -> void:
	var body      := StaticBody3D.new()
	body.name     = "HarbourMaster"
	body.position = pos
	var col       := CollisionShape3D.new()
	var box       := BoxShape3D.new()
	box.size      = Vector3(8.0, 5.0, 7.0)
	col.shape     = box
	col.position  = Vector3(0.0, 2.5, 0.0)
	body.add_child(col)
	var ma                  := ModelAssembler.new()
	ma.name                 = "Model"
	ma.model_data_path      = HARBOURMASTER_MESH_PATH
	ma.build_part_colliders = false
	body.add_child(ma)
	add_child(body)


func _shippingagent_building(pos: Vector3) -> void:
	var body      := StaticBody3D.new()
	body.name     = "ShippingAgent"
	body.position = pos
	var col       := CollisionShape3D.new()
	var box       := BoxShape3D.new()
	box.size      = Vector3(10.0, 5.0, 8.0)
	col.shape     = box
	col.position  = Vector3(0.0, 2.5, 0.0)
	body.add_child(col)
	var ma                  := ModelAssembler.new()
	ma.name                 = "Model"
	ma.model_data_path      = SHIPPINGAGENT_MESH_PATH
	ma.build_part_colliders = false
	body.add_child(ma)
	add_child(body)


func _customs_building(pos: Vector3) -> void:
	var body      := StaticBody3D.new()
	body.name     = "Customs"
	body.position = pos
	var col       := CollisionShape3D.new()
	var box       := BoxShape3D.new()
	box.size      = Vector3(8.0, 5.0, 7.0)
	col.shape     = box
	col.position  = Vector3(0.0, 2.5, 0.0)
	body.add_child(col)
	var ma                  := ModelAssembler.new()
	ma.name                 = "Model"
	ma.model_data_path      = CUSTOMS_MESH_PATH
	ma.build_part_colliders = false
	body.add_child(ma)
	add_child(body)


func _marine_engineer_building(pos: Vector3) -> void:
	var body      := StaticBody3D.new()
	body.name     = "MarineEngineer"
	body.position = pos
	var col       := CollisionShape3D.new()
	var box       := BoxShape3D.new()
	box.size      = Vector3(11.0, 4.0, 9.0)
	col.shape     = box
	col.position  = Vector3(0.0, 2.0, 0.0)
	body.add_child(col)
	var ma                  := ModelAssembler.new()
	ma.name                 = "Model"
	ma.model_data_path      = MARINE_ENGINEER_MESH_PATH
	ma.build_part_colliders = false
	body.add_child(ma)
	add_child(body)


func _warehouse_building(pos: Vector3, rot_y: float = 0.0) -> void:
	var body           := StaticBody3D.new()
	body.name          = "Warehouse"
	body.position      = pos
	body.rotation.y    = rot_y
	var col       := CollisionShape3D.new()
	var box       := BoxShape3D.new()
	box.size      = Vector3(24.0, 6.0, 12.0)
	col.shape     = box
	col.position  = Vector3(0.0, 3.0, 0.0)
	body.add_child(col)
	var ma                  := ModelAssembler.new()
	ma.name                 = "Model"
	ma.model_data_path      = WAREHOUSE_MESH_PATH
	ma.build_part_colliders = false
	body.add_child(ma)
	add_child(body)


func _town_building(pos: Vector3) -> void:
	var body      := StaticBody3D.new()
	body.name     = "Town"
	body.position = pos
	var col       := CollisionShape3D.new()
	var box       := BoxShape3D.new()
	box.size      = Vector3(28.0, 6.0, 14.0)
	col.shape     = box
	col.position  = Vector3(0.0, 3.0, 0.0)
	body.add_child(col)
	var ma                  := ModelAssembler.new()
	ma.name                 = "Model"
	ma.model_data_path      = TOWN_MESH_PATH
	ma.build_part_colliders = false
	body.add_child(ma)
	add_child(body)


func _lighthouse_building(pos: Vector3) -> void:
	var body      := StaticBody3D.new()
	body.name     = "Lighthouse"
	body.position = pos

	# Placeholder: a tall cylinder
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 2.0
	mesh.bottom_radius = 3.5
	mesh.height = 20.0
	mi.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.9, 0.9) # White
	mat.roughness = 0.8
	mi.material_override = mat
	mi.position.y = 10.0
	body.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 3.5
	shape.height = 20.0
	col.shape = shape
	col.position.y = 10.0
	body.add_child(col)

	add_child(body)


func _fog_horn_building(pos: Vector3) -> void:
	print("[PortFacilities] Instantiating FogHorn at ", pos)
	var building := FOGHORN_SCENE.instantiate()
	building.name = "FogHornBuilding"
	building.position = pos
	# Rotate to face the sea (-Z)
	building.rotation.y = PI
	add_child(building)


func _box(size: Vector3, pos: Vector3, color: Color, node_name: String) -> MeshInstance3D:
	var mi               := MeshInstance3D.new()
	mi.name              = "Mesh"
	var mesh             := BoxMesh.new()
	mesh.size            = size
	mi.mesh              = mesh
	var mat              := StandardMaterial3D.new()
	mat.albedo_color     = color
	mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	var body             := StaticBody3D.new()
	body.name            = node_name
	body.position        = pos
	var col              := CollisionShape3D.new()
	var box              := BoxShape3D.new()
	box.size             = size
	col.shape            = box
	body.add_child(mi)
	body.add_child(col)
	add_child(body)
	return mi


func _own_subtree(node: Node, esc: Node) -> void:
	node.owner = esc
	for child in node.get_children():
		_own_subtree(child, esc)
