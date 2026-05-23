@tool
class_name ShipShowcase
extends Node3D

## Lays out the full shipwright hull catalog in a grid for visual review.
## Tick `rebuild` in the inspector after changing layout options.

const ROTATION_MARGIN := 12.0
const LABEL_H := 7.5

@export var rebuild: bool = false:
	set(v):
		if v and is_inside_tree():
			_rebuild()

@export_group("Display Options")
@export var show_ground_pad: bool = true:
	set(v):
		show_ground_pad = v
		if is_inside_tree():
			_rebuild()

@export var show_labels: bool = true:
	set(v):
		show_labels = v
		if is_inside_tree():
			_rebuild()

@export var spin_ships: bool = false:
	set(v):
		spin_ships = v
		for preview in _previews:
			if is_instance_valid(preview):
				preview.set_spin_enabled(v)

@export var show_cargo_decks: bool = true:
	set(v):
		show_cargo_decks = v
		if is_inside_tree():
			_rebuild()

@export var frame_camera: bool = true:
	set(v):
		frame_camera = v
		if is_inside_tree():
			_frame_camera(_grid_min, _grid_max)


var _previews: Array[ShipwrightPreview] = []
var _grid_min := Vector3(INF, 0.0, INF)
var _grid_max := Vector3(-INF, 0.0, -INF)


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()
	_previews.clear()
	_grid_min = Vector3(INF, 0.0, INF)
	_grid_max = Vector3(-INF, 0.0, -INF)

	var grid_definition := _get_grid_definition()
	if grid_definition.is_empty():
		return

	var z_cursor := 0.0

	for row_idx in grid_definition.size():
		var row_def: Dictionary = grid_definition[row_idx]
		var row_label: String = row_def["name"]
		var entries: Array = row_def["entries"]
		if entries.is_empty():
			continue

		var ship_data: Array = []
		var row_max_clearance := 0.0
		for item: Dictionary in entries:
			var stations := _load_stations(item["entry"])
			var clearance := _rotation_clearance(stations)
			row_max_clearance = maxf(row_max_clearance, clearance)
			ship_data.append({
				"entry": item["entry"],
				"label": item["label"],
				"stations": stations,
				"clearance": clearance,
			})

		var z_pos: float
		if row_idx == 0:
			z_pos = row_max_clearance
			z_cursor = z_pos + row_max_clearance
		else:
			z_pos = z_cursor + ROTATION_MARGIN + row_max_clearance
			z_cursor = z_pos + row_max_clearance

		if show_labels:
			var category_lbl := Label3D.new()
			category_lbl.text = "=== %s ===" % row_label.to_upper()
			category_lbl.font_size = 36
			category_lbl.modulate = HudStyle.C_AMBER
			category_lbl.outline_size = 12
			category_lbl.position = Vector3(-8.0, 2.0, z_pos)
			category_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			add_child(category_lbl)
			category_lbl.owner = _scene_owner()

		var x_cursor := 0.0
		for col_idx in ship_data.size():
			var data: Dictionary = ship_data[col_idx]
			var clearance: float = data["clearance"]
			var x_pos: float
			if col_idx == 0:
				x_pos = clearance
				x_cursor = x_pos + clearance
			else:
				x_pos = x_cursor + ROTATION_MARGIN + clearance
				x_cursor = x_pos + clearance

			var preview := ShipwrightPreview.new()
			preview.name = "ShipPreview_%d_%d" % [row_idx, col_idx]
			add_child(preview)
			preview.position = Vector3(x_pos, 0.0, z_pos)
			preview.owner = _scene_owner()
			preview.set_spin_enabled(spin_ships)
			preview.set_show_cargo_decks(show_cargo_decks)
			preview.show_entry(data["entry"])
			_previews.append(preview)

			_expand_bounds(x_pos, z_pos, clearance)

			if show_labels:
				var price := ShipwrightPricing.quote_price_marks(data["stations"])
				var lbl := Label3D.new()
				lbl.text = "%s\n%s" % [data["label"], ShipwrightPricing.price_label(price)]
				lbl.font_size = 22
				lbl.modulate = Color.WHITE
				lbl.outline_size = 8
				lbl.position = Vector3(x_pos, maxf(LABEL_H, clearance * 0.35), z_pos)
				lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				add_child(lbl)
				lbl.owner = _scene_owner()

	if show_ground_pad:
		_spawn_ground_pad_from_bounds()

	if frame_camera:
		_frame_camera(_grid_min, _grid_max)


func _rotation_clearance(stations: HullStations) -> float:
	if stations == null:
		return 14.0
	var half_len := stations.length_m * 0.5
	var half_beam := maxf(stations.beam_m * 0.5, 1.0)
	return sqrt(half_len * half_len + half_beam * half_beam)


func _load_stations(entry: Dictionary) -> HullStations:
	var hull_path := ShipBuilder.HULL_BASE_DIR + str(entry.get("hull_file", ""))
	var hull_data := JsonUtil.load(hull_path)
	return HullStations.from_hull_json(hull_data, 10)


func _expand_bounds(x_pos: float, z_pos: float, clearance: float) -> void:
	_grid_min.x = minf(_grid_min.x, x_pos - clearance)
	_grid_min.z = minf(_grid_min.z, z_pos - clearance)
	_grid_max.x = maxf(_grid_max.x, x_pos + clearance)
	_grid_max.z = maxf(_grid_max.z, z_pos + clearance)


func _spawn_ground_pad_from_bounds() -> void:
	var pad_w := _grid_max.x - _grid_min.x + 20.0
	var pad_d := _grid_max.z - _grid_min.z + 20.0
	var center := Vector3(
		(_grid_min.x + _grid_max.x) * 0.5,
		0.06,
		(_grid_min.z + _grid_max.z) * 0.5
	)

	var pad := MeshInstance3D.new()
	pad.name = "GroundPad"
	var bm := BoxMesh.new()
	bm.size = Vector3(pad_w, 0.12, pad_d)
	pad.mesh = bm
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.12, 0.14)
	mat.roughness = 0.88
	pad.material_override = mat
	pad.position = center
	add_child(pad)
	pad.owner = _scene_owner()

	var water := MeshInstance3D.new()
	water.name = "WaterStrip"
	var wm := BoxMesh.new()
	wm.size = Vector3(pad_w + 8.0, 0.04, pad_d + 8.0)
	water.mesh = wm
	water.position = center + Vector3(0.0, -0.02, 0.0)
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.08, 0.18, 0.28, 0.85)
	water_mat.roughness = 0.35
	water_mat.metallic = 0.05
	water.material_override = water_mat
	add_child(water)
	water.owner = _scene_owner()


func _frame_camera(grid_min: Vector3, grid_max: Vector3) -> void:
	if grid_min.x == INF:
		return
	var root := get_parent()
	if root == null:
		return
	var cam := root.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		return

	var center := Vector3(
		(grid_min.x + grid_max.x) * 0.5,
		4.0,
		(grid_min.z + grid_max.z) * 0.5
	)
	var span := maxf(grid_max.x - grid_min.x, grid_max.z - grid_min.z)
	var dist := span * 0.92 + 32.0
	var height := span * 0.42 + 22.0
	var cam_pos := center + Vector3(dist * 0.52, height, dist * 0.78)
	var xf := Transform3D.IDENTITY
	xf.origin = cam_pos
	cam.transform = xf.looking_at(center, Vector3.UP)


func _scene_owner() -> Node:
	return get_tree().edited_scene_root if Engine.is_editor_hint() else self


func _get_grid_definition() -> Array:
	var by_role: Dictionary = {}

	for def: Dictionary in HullRegistry.catalog():
		var role_type: VesselRole.Type = def.get("role", VesselRole.Type.CARGO)
		var role_label: String = VesselRole.display_name(role_type)
		if not by_role.has(role_label):
			by_role[role_label] = {"name": role_label, "entries": []}
		by_role[role_label]["entries"].append({
			"entry": def,
			"label": str(def.get("display", def.get("id", "Hull"))),
		})

	var rows: Array = []
	for role_label in [
		"Fishing Vessel",
		"Liquid Tanker",
		"Cargo Freighter",
		"Passenger Ferry",
		"Container Carrier",
	]:
		if by_role.has(role_label):
			var row: Dictionary = by_role[role_label]
			if not row["entries"].is_empty():
				rows.append(row)
	return rows
