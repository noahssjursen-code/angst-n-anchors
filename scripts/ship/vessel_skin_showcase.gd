extends Node3D

## Side-by-side comparison of the two vessel render paths on real prebuilts:
## LEFT boat  — legacy per-brick rendering (one node per brick)
## RIGHT boat — VesselSkinBaker merged skin (culled faces + baked AO + trim)
##
## Keys: 1-3 select vessel pair · arrows orbit · wheel zoom · TAB swap sides
## HUD shows brick counts and measured MeshInstance/node counts per side.
## Headless: prints the measurements and quits (used as the regression probe).

const PAIR_SPACING := 60.0
const SIDE_OFFSET := 14.0

var _pairs: Array[Dictionary] = []
var _camera: Camera3D
var _hud: RichTextLabel
var _focus := 0
var _orbit_yaw := 0.6
var _orbit_pitch := 0.45
var _orbit_distance := 42.0


func _ready() -> void:
	_build_environment()
	_build_hud()
	call_deferred("_spawn_all")


func _spawn_all() -> void:
	## Parametric construction era: the primary demo is a ship written by hand
	## in JSON (bulwark walls with window and door cuts, a deck plate with a
	## stairwell hole) rendered through the StructurePlan path.
	var demos: Array[Dictionary] = [_demo_plan_ship(), _demo_bare_hull()]
	for index in demos.size():
		var record := demos[index]
		var origin := Vector3(0.0, 0.0, float(index) * PAIR_SPACING)
		var legacy := _spawn_variant(record, false, origin + Vector3(-SIDE_OFFSET, 0, 0))
		var baked := _spawn_variant(record, true, origin + Vector3(SIDE_OFFSET, 0, 0))
		var layout_dict := record.get("brick_layout", {}) as Dictionary
		var parts := 0
		if StructurePlan.is_plan(layout_dict):
			parts = StructurePlan.from_dict(layout_dict).entity_count()
		else:
			parts = BrickLayout.from_dict(layout_dict).iter_primary_cells().size()
		_pairs.append({
			"name": str(record.get("name", record.get("id", "vessel"))),
			"bricks": parts,
			"legacy": legacy,
			"baked": baked,
			"origin": origin,
		})
	_update_hud()
	if DisplayServer.get_name() == "headless":
		for pair in _pairs:
			print(_pair_stats_line(pair))
		get_tree().quit(0)


func _demo_plan_ship() -> Dictionary:
	var file := FileAccess.open("res://resources/data/structures/demo_workboat.json", FileAccess.READ)
	if file == null:
		return _demo_bare_hull()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary:
		return _demo_bare_hull()
	return {
		"id": "demo_workboat",
		"name": "JSON plan workboat",
		"hull_id": str((parsed as Dictionary).get("hull_id", "hull_28x10")),
		"brick_layout": parsed as Dictionary,
	}


func _demo_bare_hull() -> Dictionary:
	var layout := BrickLayout.new()
	layout.hull_id = "hull_28x10"
	return {"id": "bare_hull", "name": "Bare hull", "hull_id": "hull_28x10", "brick_layout": layout.to_dict()}


## Demo built from the fine-building vocabulary: thin-panel cabin with window
## band and door, half-block bulwarks, quarter ledge, 45° pieces at the bow.
## Dormant while the catalog is empty; revives as the new vocabulary lands.
func _demo_workboat() -> Dictionary:
	var layout := BrickLayout.new()
	layout.hull_id = "hull_28x10"
	## Half-block bulwarks along both rails and the stern.
	for z in range(8, 27):
		layout.set_brick(Vector3i(0, 0, z), "block_half")
		layout.set_brick(Vector3i(9, 0, z), "block_half")
	for x in range(0, 10):
		layout.set_brick(Vector3i(x, 0, 27), "block_half")
	## 45° half wedges close the bulwark run toward the bow.
	layout.set_brick(Vector3i(0, 0, 7), "block_45_half", 90)
	layout.set_brick(Vector3i(9, 0, 7), "block_45_half", 180)
	## Quarter-block ledge across the working deck.
	for x in range(1, 9):
		layout.set_brick(Vector3i(x, 0, 12), "block_quarter")
	## Cabin: corner columns, thin panel walls, window band, aft door, roof.
	for corner_x in [2, 7]:
		for corner_z in [19, 25]:
			for y in range(0, 3):
				layout.set_brick(Vector3i(corner_x, y, corner_z), "block")
	for x in range(3, 7):
		layout.set_brick(Vector3i(x, 0, 19), "wall_panel", 0)
		layout.set_brick(Vector3i(x, 1, 19), "block_window", 0)
		layout.set_brick(Vector3i(x, 2, 19), "wall_panel", 0)
	layout.set_brick(Vector3i(3, 0, 25), "wall_panel", 180)
	layout.set_brick(Vector3i(3, 1, 25), "wall_panel", 180)
	layout.set_brick(Vector3i(3, 2, 25), "wall_panel", 180)
	layout.set_brick(Vector3i(6, 2, 25), "wall_panel", 180)
	layout.set_brick(Vector3i(4, 0, 25), "block_door", 180)
	for z in range(20, 25):
		for y in range(0, 3):
			layout.set_brick(Vector3i(2, y, z), "wall_panel", 270)
			layout.set_brick(Vector3i(7, y, z), "wall_panel", 90)
	for x in range(2, 8):
		for z in range(19, 26):
			layout.set_brick(Vector3i(x, 3, z), "roof_flat")
	## Diagonal thin panels as a chamfered windbreak ahead of the cabin.
	layout.set_brick(Vector3i(2, 0, 18), "wall_panel_45", 0)
	layout.set_brick(Vector3i(7, 0, 18), "wall_panel_45", 90)
	return {"id": "panel_workboat", "name": "Panel workboat (new blocks)", "hull_id": "hull_28x10", "brick_layout": layout.to_dict()}


## One of each new vocabulary piece in a row, for direct judgment.
func _demo_sampler() -> Dictionary:
	var layout := BrickLayout.new()
	layout.hull_id = "hull_28x10"
	var pieces: Array[String] = [
		"block", "block_half", "block_quarter",
		"block_45", "block_45_half", "block_45_quarter",
		"wall_panel", "wall_panel_half", "wall_panel_quarter",
		"wall_panel_45", "wall_panel_45_half", "wall_panel_45_quarter",
	]
	for index in pieces.size():
		layout.set_brick(Vector3i(3, 0, 8 + index), pieces[index])
		layout.set_brick(Vector3i(6, 0, 8 + index), pieces[index], 90)
	return {"id": "block_sampler", "name": "Block sampler (yaw 0 + 90)", "hull_id": "hull_28x10", "brick_layout": layout.to_dict()}


func _spawn_variant(record: Dictionary, skin: bool, at: Vector3) -> BoatBody:
	var previous := DeckFitout.skin_enabled
	DeckFitout.skin_enabled = skin
	var boat := VesselSpawn.instantiate(
		str(record.get("hull_id", "hull_28x10")),
		record.get("brick_layout", {}) as Dictionary,
		"",
	)
	DeckFitout.skin_enabled = previous
	if boat == null:
		return null
	boat.name = "%s_%s" % [str(record.get("id", "vessel")), "baked" if skin else "legacy"]
	add_child(boat)
	boat.global_position = at
	boat.place_at_waterline(0.0)
	boat.freeze = true
	boat.sleeping = true
	var label := Label3D.new()
	label.text = "BAKED SKIN" if skin else "LEGACY"
	label.font_size = 220
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 14, 0)
	label.modulate = Color(0.4, 1.0, 0.55) if skin else Color(1.0, 0.72, 0.35)
	boat.add_child(label)
	return boat


static func _count_stats(root: Node) -> Dictionary:
	var stats := {"nodes": 0, "meshes": 0}
	if root == null:
		return stats
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stats["nodes"] = int(stats["nodes"]) + 1
		if node is MeshInstance3D:
			stats["meshes"] = int(stats["meshes"]) + 1
		for child in node.get_children():
			stack.append(child)
	return stats


func _pair_stats_line(pair: Dictionary) -> String:
	var legacy_stats := _count_stats(pair.get("legacy"))
	var baked_stats := _count_stats(pair.get("baked"))
	return "[skin-showcase] %s (%d bricks): legacy meshes=%d nodes=%d | baked meshes=%d nodes=%d" % [
		pair.get("name"), int(pair.get("bricks", 0)),
		int(legacy_stats["meshes"]), int(legacy_stats["nodes"]),
		int(baked_stats["meshes"]), int(baked_stats["nodes"]),
	]


func _process(_delta: float) -> void:
	if _pairs.is_empty():
		return
	var pair := _pairs[clampi(_focus, 0, _pairs.size() - 1)]
	var center: Vector3 = (pair.get("origin") as Vector3) + Vector3(0, 4, 0)
	var offset := Vector3(
		cos(_orbit_pitch) * sin(_orbit_yaw),
		sin(_orbit_pitch),
		cos(_orbit_pitch) * cos(_orbit_yaw),
	) * _orbit_distance
	_camera.position = center + offset
	_camera.look_at(center, Vector3.UP)
	if Input.is_key_pressed(KEY_LEFT):
		_orbit_yaw -= 0.9 * _delta_safe()
	if Input.is_key_pressed(KEY_RIGHT):
		_orbit_yaw += 0.9 * _delta_safe()
	if Input.is_key_pressed(KEY_UP):
		_orbit_pitch = clampf(_orbit_pitch + 0.6 * _delta_safe(), 0.08, 1.35)
	if Input.is_key_pressed(KEY_DOWN):
		_orbit_pitch = clampf(_orbit_pitch - 0.6 * _delta_safe(), 0.08, 1.35)


func _delta_safe() -> float:
	return get_process_delta_time()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		var wheel := event as InputEventMouseButton
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = maxf(12.0, _orbit_distance * 0.88)
		elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = minf(160.0, _orbit_distance * 1.14)
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		match (event as InputEventKey).keycode:
			KEY_1, KEY_2, KEY_3:
				_focus = clampi((event as InputEventKey).keycode - KEY_1, 0, _pairs.size() - 1)
				_update_hud()


func _update_hud() -> void:
	if _hud == null:
		return
	_hud.clear()
	_hud.append_text("[b]Vessel skin bake — side by side[/b]  (1-3 vessels · arrows orbit · wheel zoom)\n")
	for index in _pairs.size():
		var marker := "▶ " if index == _focus else "   "
		_hud.append_text(marker + _pair_stats_line(_pairs[index]) + "\n")


func _build_environment() -> void:
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000, 2000)
	sea.mesh = plane
	var sea_material := StandardMaterial3D.new()
	sea_material.albedo_color = Color(0.10, 0.18, 0.26)
	sea_material.roughness = 0.25
	sea_material.metallic = 0.1
	sea.material_override = sea_material
	sea.position = Vector3(0, -0.35, PAIR_SPACING)
	add_child(sea)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, 35, 0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	add_child(light)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.55, 0.65, 0.75)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.7, 0.78)
	environment.ambient_light_energy = 0.6
	env.environment = environment
	add_child(env)
	_camera = Camera3D.new()
	_camera.far = 4000.0
	add_child(_camera)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := ColorRect.new()
	panel.color = Color(0.03, 0.05, 0.07, 0.78)
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.custom_minimum_size = Vector2(0, 110)
	layer.add_child(panel)
	_hud = RichTextLabel.new()
	_hud.bbcode_enabled = true
	_hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud.offset_left = 16.0
	_hud.offset_top = 8.0
	_hud.offset_right = -16.0
	_hud.offset_bottom = 110.0
	layer.add_child(_hud)
