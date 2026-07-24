extends Node3D

## F6 inspect scene for the parametric structure engine.
## Cycles demo plans / material presets and shows live bake stats.
## No dependence on the full game world.

const DEMO_PATHS := [
	"res://resources/data/structures/demo_workboat.json",
	"res://resources/data/structures/demo_harbour_shed.json",
]

var _camera: Camera3D
var _bake_root: Node3D
var _hull: Node3D
var _plan := StructurePlan.new()
var _status: Label
var _yaw := 0.85
var _pitch := 0.75
var _distance := 28.0
var _focus := Vector3(0, 2, 0)
var _orbiting := false
var _preset := 0
var _demo_index := 0


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
	var studio := UiBuilder.compact_button("Studio notes", 120.0)
	studio.pressed.connect(func() -> void:
		_status.text = "Run scenes/apps/structure_studio.tscn to author. This showcase only inspects bakes."
	)
	row.add_child(studio)
	var hint := Label.new()
	hint.text = "RMB orbit · wheel zoom · N materials · M next demo"
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
			_paint_all("painted", "wood", Color(0.92, 0.93, 0.94), Color(0.78, 0.70, 0.58))
		1:
			_paint_all("steel", "wood", Color(0.55, 0.58, 0.62), Color(0.70, 0.58, 0.42))
		2:
			_paint_all("brick", "painted", Color(0.78, 0.52, 0.42), Color(0.90, 0.86, 0.76))
		3:
			_paint_all("corrugated", "concrete", Color(0.58, 0.60, 0.63), Color(0.72, 0.72, 0.70))
	_rebuild()


func _paint_all(out_mat: String, in_mat: String, out_col: Color, in_col: Color) -> void:
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


func _rebuild() -> void:
	if _bake_root != null and is_instance_valid(_bake_root):
		_bake_root.free()
		_bake_root = null
	if _hull != null and is_instance_valid(_hull):
		_hull.free()
		_hull = null
	_hull = Node3D.new()
	add_child(_hull)
	if _plan.context == "vessel" and not _plan.hull_id.is_empty():
		var boat := VesselSpawn.instantiate(_plan.hull_id, {}, "")
		if boat != null:
			var grid := HullRegistry.make_grid(_plan.hull_id)
			boat.position = Vector3(0, -grid.deck_y, 0)
			boat.freeze = true
			boat.process_mode = Node.PROCESS_MODE_DISABLED
			_hull.add_child(boat)
			var offset := Vector3(-grid.half_beam, 0.0, -grid.half_loa)
			_bake_root = StructureBaker.bake(_plan, offset)
		else:
			_bake_root = StructureBaker.bake(_plan)
	else:
		## Land building — ground slab host.
		var slab := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(32, 1, 32)
		slab.mesh = mesh
		slab.position = Vector3(0, -0.5, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.24, 0.30, 0.22)
		slab.material_override = mat
		_hull.add_child(slab)
		_bake_root = StructureBaker.bake(_plan, Vector3(-12, 0, -12))
	add_child(_bake_root)
	var meshes := _bake_root.get_child_count()
	var mats := StructureMaterialLibrary.ids().size()
	var demo_name: String = String(DEMO_PATHS[_demo_index]).get_file().get_basename()
	_status.text = "%s · %s · entities %d · meshes %d · library %d · mat preset %d" % [
		demo_name, _plan.context, _plan.entity_count(), meshes, mats, _preset,
	]


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _bake_root != null and is_instance_valid(_bake_root):
			_bake_root.free()
			_bake_root = null
		if _hull != null and is_instance_valid(_hull):
			_hull.free()
			_hull = null
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
