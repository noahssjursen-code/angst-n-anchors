extends Node3D

## F6 inspect scene for the parametric structure engine.
## Cycles demo plans / material presets and shows live bake stats.
## No dependence on the full game world.

const DEMO_PATHS := [
	"res://resources/data/structures/demo_workboat.json",
	"res://resources/data/structures/demo_bridge_cabin.json",
	"res://resources/data/structures/demo_fish_hold.json",
	"res://resources/data/structures/demo_harbour_shed.json",
	"res://resources/data/structures/demo_quay_office.json",
	"res://resources/data/structures/demo_canopy.json",
	"res://resources/data/structures/demo_pier_shack.json",
]

var _camera: Camera3D
var _bake_root: Node3D
var _hull: Node3D
var _collider_root: Node3D
var _plan := StructurePlan.new()
var _status: Label
var _yaw := 0.85
var _pitch := 0.75
var _distance := 28.0
var _focus := Vector3(0, 2, 0)
var _orbiting := false
var _preset := 0
var _demo_index := 0
var _show_colliders := false


func _ready() -> void:
	StructureMaterialLibrary.reload()
	_build_scene()
	_build_ui()
	_load_demo(DEMO_PATHS[0])


func _build_scene() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 35, 0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 210, 0)
	fill.light_energy = 0.4
	add_child(fill)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.07, 0.09, 0.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.22, 0.24, 0.28)
	environment.ambient_light_energy = 0.9
	env.environment = environment
	add_child(env)
	_camera = Camera3D.new()
	_camera.far = 500.0
	add_child(_camera)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = HudStyle.make_theme()
	layer.add_child(root)
	var bar := UiBuilder.inner_panel()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, 52)
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	var title := Label.new()
	title.text = "STRUCTURE ENGINE"
	HudStyle.apply_display_font(title, 22, HudStyle.C_AMBER)
	row.add_child(title)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudStyle.apply_body_font(_status, 13, HudStyle.C_LABEL)
	row.add_child(_status)
	var cycle := UiBuilder.compact_button("Materials  [N]", 120.0)
	cycle.pressed.connect(func() -> void: _cycle_preset())
	row.add_child(cycle)
	var demo_btn := UiBuilder.compact_button("Next demo  [M]", 120.0)
	demo_btn.pressed.connect(func() -> void: _cycle_demo())
	row.add_child(demo_btn)
	var colliders := UiBuilder.compact_button("Colliders  [C]", 120.0)
	colliders.pressed.connect(func() -> void: _toggle_colliders())
	row.add_child(colliders)
	var studio := UiBuilder.compact_button("Studio notes", 120.0)
	studio.pressed.connect(func() -> void:
		_status.text = "Run scenes/apps/structure_studio.tscn to author. This showcase only inspects bakes."
	)
	row.add_child(studio)
	var hint := Label.new()
	hint.text = "RMB orbit · wheel zoom · N materials · M next demo · C colliders"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -36
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HudStyle.apply_body_font(hint, 12, HudStyle.C_LABEL)
	root.add_child(hint)


func _load_demo(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_status.text = "missing %s" % path.get_file()
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary:
		_status.text = "demo parse failed"
		return
	_plan = StructurePlan.from_dict(parsed as Dictionary)
	_preset = 0
	_rebuild()


func _cycle_demo() -> void:
	_demo_index = (_demo_index + 1) % DEMO_PATHS.size()
	_load_demo(DEMO_PATHS[_demo_index])


func _cycle_preset() -> void:
	_preset = (_preset + 1) % 4
	match _preset:
		0:
			_paint_all("painted", "wood", "antislip", Color(0.92, 0.93, 0.94), Color(0.78, 0.70, 0.58), Color(0.28, 0.28, 0.27))
		1:
			_paint_all("steel", "wood", "asphalt", Color(0.55, 0.58, 0.62), Color(0.70, 0.58, 0.42), Color(0.30, 0.30, 0.28))
		2:
			_paint_all("brick", "painted", "concrete", Color(0.78, 0.52, 0.42), Color(0.90, 0.86, 0.76), Color(0.72, 0.72, 0.70))
		3:
			_paint_all("corrugated", "plaster", "tar", Color(0.58, 0.60, 0.63), Color(0.90, 0.88, 0.82), Color(0.22, 0.22, 0.22))
	_rebuild()


func _paint_all(
	out_mat: String, in_mat: String, deck_mat: String,
	out_col: Color, in_col: Color, deck_col: Color
) -> void:
	for room_variant in _plan.rooms:
		var room := room_variant as Dictionary
		room["material_out"] = out_mat
		room["material_in"] = in_mat
		room["color_out"] = [out_col.r, out_col.g, out_col.b]
		room["color_in"] = [in_col.r, in_col.g, in_col.b]
	for wall_variant in _plan.walls:
		var wall := wall_variant as Dictionary
		wall["material"] = out_mat
		wall["material_out"] = out_mat
		wall["color"] = [out_col.r, out_col.g, out_col.b]
		wall["color_out"] = [out_col.r, out_col.g, out_col.b]
		if wall.has("material_in") or wall.has("color_in"):
			wall["material_in"] = in_mat
			wall["color_in"] = [in_col.r, in_col.g, in_col.b]
	for deck_variant in _plan.decks:
		var deck := deck_variant as Dictionary
		deck["material"] = deck_mat
		deck["color"] = [deck_col.r, deck_col.g, deck_col.b]


func _plan_bounds() -> AABB:
	var bounds := _plan.bounds()
	if bounds.size.length() <= 0.01:
		return AABB(Vector3(-8, 0, -8), Vector3(16, 4, 16))
	return bounds


func _rebuild() -> void:
	if _bake_root != null and is_instance_valid(_bake_root):
		_bake_root.free()
		_bake_root = null
	if _hull != null and is_instance_valid(_hull):
		_hull.free()
		_hull = null
	if _collider_root != null and is_instance_valid(_collider_root):
		_collider_root.free()
		_collider_root = null
	_hull = Node3D.new()
	add_child(_hull)
	var offset := Vector3.ZERO
	var bounds := _plan_bounds()
	if _plan.context == "vessel" and not _plan.hull_id.is_empty():
		var boat := VesselSpawn.instantiate(_plan.hull_id, {}, "")
		if boat != null:
			var grid := HullRegistry.make_grid(_plan.hull_id)
			boat.position = Vector3(0, -grid.deck_y, 0)
			boat.freeze = true
			boat.process_mode = Node.PROCESS_MODE_DISABLED
			_hull.add_child(boat)
			offset = Vector3(-grid.half_beam, 0.0, -grid.half_loa)
			_bake_root = StructureBaker.bake(_plan, offset)
		else:
			_bake_root = StructureBaker.bake(_plan)
	else:
		var plot := maxf(maxf(bounds.size.x, bounds.size.z) + 8.0, 16.0)
		var slab := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(plot, 1, plot)
		slab.mesh = mesh
		slab.position = Vector3(0, -0.5, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.24, 0.30, 0.22)
		slab.material_override = mat
		_hull.add_child(slab)
		offset = Vector3(-bounds.get_center().x, 0.0, -bounds.get_center().z)
		_bake_root = StructureBaker.bake(_plan, offset)
	add_child(_bake_root)
	_fit_camera(bounds, offset)
	if _show_colliders:
		_build_collider_debug(offset)
	var meshes := _bake_root.get_child_count()
	var mats := StructureMaterialLibrary.ids().size()
	var demo_name: String = String(DEMO_PATHS[_demo_index]).get_file().get_basename()
	var report := _plan.validate(int(ceil(bounds.size.x + 4.0)), int(ceil(bounds.size.z + 4.0)))
	var warn_n: int = (report.get("warnings", PackedStringArray()) as PackedStringArray).size()
	_status.text = "%s · %s · entities %d · meshes %d · library %d · preset %d%s" % [
		demo_name, _plan.context, _plan.entity_count(), meshes, mats, _preset,
		" · colliders" if _show_colliders else (" · %d warn" % warn_n if warn_n > 0 else ""),
	]


func _fit_camera(bounds: AABB, offset: Vector3) -> void:
	var world_bounds := AABB(bounds.position + offset, bounds.size)
	_focus = world_bounds.get_center() + Vector3(0, world_bounds.size.y * 0.15, 0)
	var span := maxf(maxf(world_bounds.size.x, world_bounds.size.z), world_bounds.size.y)
	_distance = clampf(span * 1.6 + 8.0, 14.0, 70.0)


func _toggle_colliders() -> void:
	_show_colliders = not _show_colliders
	_rebuild()


func _build_collider_debug(offset: Vector3) -> void:
	_collider_root = Node3D.new()
	_collider_root.name = "ColliderDebug"
	add_child(_collider_root)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(HudStyle.C_AMBER, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for box_variant in StructureBaker.collect_colliders(_plan):
		var box := box_variant as Dictionary
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = box["size"] as Vector3
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = (box["center"] as Vector3) + offset
		_collider_root.add_child(mi)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _bake_root != null and is_instance_valid(_bake_root):
			_bake_root.free()
			_bake_root = null
		if _hull != null and is_instance_valid(_hull):
			_hull.free()
			_hull = null
		if _collider_root != null and is_instance_valid(_collider_root):
			_collider_root.free()
			_collider_root = null
		StructureMaterialLibrary.clear_runtime_caches()


func _process(_delta: float) -> void:
	var offset := Vector3(
		cos(_pitch) * sin(_yaw), sin(_pitch), cos(_pitch) * cos(_yaw)
	) * _distance
	_camera.position = _focus + offset
	_camera.look_at(_focus, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_N:
				_cycle_preset()
			KEY_M:
				_cycle_demo()
			KEY_C:
				_toggle_colliders()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = button.pressed
		elif button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_distance = maxf(8.0, _distance * 0.9)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_distance = minf(80.0, _distance * 1.1)
	elif event is InputEventMouseMotion and _orbiting:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * 0.008
		_pitch = clampf(_pitch + motion.relative.y * 0.006, 0.2, 1.4)
