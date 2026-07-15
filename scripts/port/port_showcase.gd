@tool
class_name PortShowcase
extends Node3D

## F6 gallery for socket graphs placed in their actual seeded world terrain.

const SEEDS: Array[int] = [424242, 111111, 777001, 90210, 314159]
const REGION_LABELS: Array[String] = ["mainland", "fjord", "archipelago"]
const SIZE_LABELS: Array[String] = [
	"landing", "local", "regional", "large", "industrial",
	"major", "deep", "mega", "hub",
]
const WORLD_LAYOUT_GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const COASTAL_PORT_PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const TERRAIN_STREAMER := preload("res://scripts/world/world_terrain_streamer.gd")
const WORLD_RENDERER := preload("res://scripts/world/world_renderer.gd")
const SHOWCASE_PORT_NAMES: Array[String] = [
	"Holmvik", "Sandvær", "Bergnes", "Kloven", "Strandnes", "Kvamsvik",
	"Bremsund", "Tysneset", "Fjelltun", "Grønnvik", "Harberg", "Innvær",
]
const REF_HULL_ID := "hull_28x10"
const LENGTH_PROFILES: Array[String] = ["compact", "standard", "extended"]

@export_range(0, 8) var port_size := 2:
	set(value):
		port_size = clampi(value, 0, 8)
		if is_inside_tree() and not _configuring:
			_request_rebuild()

@export_enum("Mainland", "Fjord", "Archipelago") var region_index := 0:
	set(value):
		region_index = clampi(value, 0, 2)
		if is_inside_tree() and not _configuring:
			_request_rebuild()

@export_range(0, 4) var seed_index := 0:
	set(value):
		seed_index = clampi(value, 0, SEEDS.size() - 1)
		if is_inside_tree() and not _configuring:
			_request_rebuild()

@export_range(0, 2) var length_profile_index := 1:
	set(value):
		length_profile_index = clampi(value, 0, LENGTH_PROFILES.size() - 1)
		if is_inside_tree() and not _configuring:
			_request_rebuild()

@export var has_lighthouse := true:
	set(value):
		has_lighthouse = value
		if is_inside_tree() and not _configuring:
			_request_rebuild()

@export var has_fog_horn := true:
	set(value):
		has_fog_horn = value
		if is_inside_tree() and not _configuring:
			_request_rebuild()

var _configuring := false
var _rebuild_seq := 0
var _camera: Camera3D
var _cam_yaw := -0.75
var _cam_pitch := -0.55
var _move_speed := 80.0
var _panning := false
var _looking := false
var _mouse_last := Vector2.ZERO
var _last_data: PortData
var _active_definition: PortDefinition
var _layout_cache: Dictionary = {}
var _definitions_cache: Dictionary = {}
var _terrain: WorldTerrainStreamer
var _last_terrain_seed := -1
var _terrain_boot_focus := Vector3.ZERO
var _title: Label
var _stats: Label
var _trade: RichTextLabel
var _instructions: Label


func _ready() -> void:
	_ensure_world()
	_ensure_hud()
	_rebuild()


func _request_rebuild() -> void:
	_rebuild_seq += 1
	var seq := _rebuild_seq
	await get_tree().process_frame
	if seq != _rebuild_seq:
		return
	_rebuild()


func _showcase_playing() -> bool:
	## @tool scenes stay live in the editor, but only F6/F5 sets current_scene.
	var tree := get_tree()
	return tree != null and tree.current_scene != null


func _process(delta: float) -> void:
	_update_terrain_boot_priority()
	if _showcase_playing():
		_ensure_ocean_renderer()
	if not _showcase_playing() or _camera == null:
		return
	var wish := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		wish.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		wish.z += 1.0
	if Input.is_key_pressed(KEY_A):
		wish.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		wish.x += 1.0
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
		wish.y += 1.0
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL):
		wish.y -= 1.0
	if wish != Vector3.ZERO:
		wish = wish.normalized()
		var speed := _move_speed * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		var flat_forward := Vector3(-sin(_cam_yaw), 0.0, -cos(_cam_yaw))
		var flat_right := Vector3(cos(_cam_yaw), 0.0, -sin(_cam_yaw))
		_camera.global_position += (
			flat_right * wish.x + Vector3.UP * wish.y + flat_forward * (-wish.z)
		) * speed * delta
		_apply_camera_basis()


## Boot priority is only for the first visible ring. Leaving it active makes
## every later showcase rebuild consume the streamer's elevated frame budget.
func _update_terrain_boot_priority() -> void:
	if _terrain == null or not is_instance_valid(_terrain) or not _terrain.is_boot_priority():
		return
	if _terrain.pending_near(_terrain_boot_focus, _terrain.visual_radius_m) == 0:
		_terrain.end_boot_priority()


func _apply_camera_basis() -> void:
	if _camera == null:
		return
	_camera.basis = Basis.from_euler(Vector3(_cam_pitch, _cam_yaw, 0.0))


func _frame_port() -> void:
	if _camera == null or _last_data == null or _last_data.layout_graph == null:
		return
	var target := _port_dock_focus_world()
	var span := _port_camera_span_m()
	_cam_yaw = -0.75
	_cam_pitch = -0.55
	_camera.global_position = target + Vector3(
		sin(_cam_yaw) * span,
		span * 0.48,
		cos(_cam_yaw) * span,
	)
	_camera.look_at(target, Vector3.UP)
	var euler := _camera.global_rotation
	_cam_yaw = euler.y
	_cam_pitch = euler.x


## Dock apron centre in world space — never the buried inland foundation wedge.
func _port_dock_focus_world() -> Vector3:
	if _last_data == null or _last_data.layout_graph == null:
		return Vector3.ZERO
	var graph := _last_data.layout_graph
	var port_basis := Basis(Vector3.UP, _last_data.rotation_y)
	var recipe := graph.initial_attributes.get("foundation", {}) as Dictionary
	var dock_poly := recipe.get("dock_face_polyline", []) as Array
	if dock_poly.is_empty():
		dock_poly = recipe.get("shore_line_polyline", recipe.get("coast_polyline", [])) as Array
	if not dock_poly.is_empty():
		var local := Vector3.ZERO
		for raw in dock_poly:
			var pt := raw as Array
			if pt.size() >= 2:
				local += Vector3(float(pt[0]), 0.0, float(pt[1]))
		local /= float(dock_poly.size())
		return _last_data.world_position + port_basis * local + Vector3(0.0, 1.5, 0.0)
	var root := graph.modules.get("root") as PortPlacedModule
	if root != null:
		return _last_data.world_position + port_basis * root.position_m + Vector3(0.0, 1.5, 0.0)
	return _last_data.world_position + Vector3(0.0, 1.5, 0.0)


## Camera distance from the dock — along-shore span only, not inland burial depth.
func _port_camera_span_m() -> float:
	if _last_data == null or _last_data.layout_graph == null:
		return 200.0
	var recipe := _last_data.layout_graph.initial_attributes.get("foundation", {}) as Dictionary
	var shore_length := float(recipe.get("shore_length_m", 120.0))
	return clampf(shore_length * 0.42 + 90.0, 140.0, 280.0)


func _unhandled_input(event: InputEvent) -> void:
	if not _showcase_playing():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_looking = mb.pressed
			_panning = false
			_mouse_last = mb.position
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			_looking = false
			_mouse_last = mb.position
			get_viewport().set_input_as_handled()
			return
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_move_speed = clampf(_move_speed * 1.12, 12.0, 400.0)
			if _camera != null:
				var focus := _port_dock_focus_world()
				var to_focus := focus - _camera.global_position
				if to_focus.length_squared() > 1.0:
					_camera.global_position += to_focus.normalized() * (_move_speed * 0.08)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_move_speed = clampf(_move_speed / 1.12, 12.0, 400.0)
			if _camera != null:
				var focus := _port_dock_focus_world()
				var to_focus := _camera.global_position - focus
				if to_focus.length_squared() > 1.0:
					_camera.global_position += to_focus.normalized() * (_move_speed * 0.08)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and _camera != null:
		var motion := event as InputEventMouseMotion
		var delta := motion.position - _mouse_last
		_mouse_last = motion.position
		if _looking:
			const LOOK_SENS := 0.004
			_cam_yaw -= delta.x * LOOK_SENS
			_cam_pitch = clampf(_cam_pitch - delta.y * LOOK_SENS, -1.35, -0.1)
			_apply_camera_basis()
			get_viewport().set_input_as_handled()
			return
		if _panning:
			## MMB drag pans in the ground plane (editor-style).
			var right := Vector3(cos(_cam_yaw), 0.0, -sin(_cam_yaw))
			var forward := Vector3(-sin(_cam_yaw), 0.0, -cos(_cam_yaw))
			var pan_scale := _move_speed * 0.012
			_camera.global_position += (-right * delta.x + forward * delta.y) * pan_scale
			get_viewport().set_input_as_handled()
			return
	if event is not InputEventKey or not event.is_pressed() or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_LEFT, KEY_BRACKETLEFT:
			port_size = wrapi(port_size - 1, 0, 9)
		KEY_RIGHT, KEY_BRACKETRIGHT:
			port_size = wrapi(port_size + 1, 0, 9)
		KEY_UP:
			region_index = wrapi(region_index - 1, 0, 3)
		KEY_DOWN:
			region_index = wrapi(region_index + 1, 0, 3)
		KEY_COMMA:
			length_profile_index = wrapi(length_profile_index - 1, 0, LENGTH_PROFILES.size())
		KEY_PERIOD:
			length_profile_index = wrapi(length_profile_index + 1, 0, LENGTH_PROFILES.size())
		KEY_MINUS:
			seed_index = wrapi(seed_index - 1, 0, SEEDS.size())
		KEY_EQUAL:
			seed_index = wrapi(seed_index + 1, 0, SEEDS.size())
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			port_size = int((event as InputEventKey).keycode) - int(KEY_1)
		KEY_L:
			has_lighthouse = not has_lighthouse
		KEY_F:
			has_fog_horn = not has_fog_horn
		KEY_R:
			_request_rebuild()
		KEY_HOME:
			_frame_port()
			_refresh_hud()


func _rebuild() -> void:
	## Tear down port/hulls only. Terrain is reused across rebuilds when the
	## world seed is unchanged — recreating the streamer every tweak was the hitch.
	var old_plot := get_node_or_null("GeneratedPort/PortPlot")
	if old_plot != null:
		old_plot.free()
	var old_hulls := get_node_or_null("GeneratedPort/DockedScaleHulls")
	if old_hulls != null:
		old_hulls.free()

	var generated := get_node_or_null("GeneratedPort") as Node3D
	if generated == null:
		generated = Node3D.new()
		generated.name = "GeneratedPort"
		add_child(generated)

	var layout := _world_layout()
	var definition := _select_world_port(layout)
	## Showcase entropy: same coastal site — size only extends the dock span.
	definition.site_seed = (
		int(definition.site_seed)
		^ SEEDS[seed_index]
		^ (region_index * 224737)
		^ definition.port_id.hash()
	)
	_active_definition = definition
	_last_data = PortExpander.expand(definition, layout.seed, layout, {
		"length_profile_override": LENGTH_PROFILES[length_profile_index],
	})
	_frame_port()
	var world_center := _port_dock_focus_world()

	var world_seed := SEEDS[seed_index]
	if _terrain == null or _last_terrain_seed != world_seed or not is_instance_valid(_terrain):
		var old_terrain := generated.get_node_or_null("WorldTerrain")
		if old_terrain != null:
			old_terrain.free()
		_terrain = TERRAIN_STREAMER.new() as WorldTerrainStreamer
		_terrain.name = "WorldTerrain"
		## Showcase only needs near-field context — full 1.8 km rebuilds hitch hard.
		_terrain.visual_radius_m = 2200.0
		_terrain.collision_radius_m = 0.0
		_terrain.build_budget_ms = 4.0
		_terrain.max_jobs_per_frame = 1
		generated.add_child(_terrain)
		_terrain.configure(layout, [_last_data])
		_last_terrain_seed = world_seed
		_terrain_boot_focus = world_center
		_terrain.begin_boot_priority(world_center)
	else:
		## Same world seed: retarget focus only — foundation is mesh-only.
		_terrain_boot_focus = world_center
		_terrain.begin_boot_priority(world_center)

	var plot := PortPlot.new()
	plot.name = "PortPlot"
	plot.show_site_gizmos = true
	plot.configure(_last_data)
	generated.add_child(plot)
	plot.global_position = _last_data.world_position
	call_deferred("_dock_scale_hulls", generated, plot)
	_refresh_hud()


## Design + reference hulls alongside the foundation dock for scale.
func _dock_scale_hulls(parent: Node3D, plot: PortPlot) -> void:
	if not is_instance_valid(parent) or not is_instance_valid(plot):
		return
	var graph := plot.layout_graph()
	if graph == null:
		return
	var existing := parent.get_node_or_null("DockedScaleHulls")
	if existing != null:
		existing.free()
	var foundation := graph.initial_attributes.get("foundation", {}) as Dictionary
	var segments := foundation.get("segments", []) as Array
	if segments.is_empty():
		return
	var design_hull_id := PortSizing.design_hull_id(port_size)
	var design_loa := PortSizing.design_hull_loa_m(port_size)
	var design_beam := PortSizing.design_hull_beam_m(port_size)
	var ref_entry := HullRegistry.get_by_id(REF_HULL_ID)
	var ref_loa := float(ref_entry.get("loa_m", 28.0))
	var ref_beam := float(ref_entry.get("beam_m", 10.0))
	var holder := Node3D.new()
	holder.name = "DockedScaleHulls"
	parent.add_child(holder)
	var best_segment: Dictionary = {}
	var best_length := 0.0
	for raw in segments:
		var segment := raw as Dictionary
		var length_m := float(segment.get("length_m", 0.0))
		if length_m > best_length:
			best_length = length_m
			best_segment = segment
	if best_segment.is_empty():
		return
	_spawn_foundation_hull(
		holder,
		plot,
		foundation,
		best_segment,
		0.5,
		design_hull_id,
		design_beam,
		Color(0.75, 0.88, 1.0),
		1.0,
	)
	var shore_length := float(foundation.get("shore_length_m", best_length))
	if shore_length >= ref_loa * 1.35 and design_hull_id != REF_HULL_ID:
		_spawn_foundation_hull(
			holder,
			plot,
			foundation,
			best_segment,
			0.22,
			REF_HULL_ID,
			ref_beam,
			Color(0.7, 0.95, 0.75),
			-1.0,
		)


func _spawn_foundation_hull(
		parent: Node3D,
		plot: PortPlot,
		foundation: Dictionary,
		segment: Dictionary,
		along_fraction: float,
		hull_id: String,
		beam_m: float,
		label_color: Color,
		side_sign: float,
) -> void:
	var entry := HullRegistry.get_by_id(hull_id)
	var boat := HullRegistry.build_hull(hull_id)
	if boat == null:
		push_warning("PortShowcase: failed to build hull %s" % hull_id)
		return
	var center_arr := segment.get("center", [0.0, 0.0]) as Array
	var dir_arr := segment.get("direction_local", [1.0, 0.0]) as Array
	var tangent := Vector2(float(dir_arr[0]), float(dir_arr[1])).normalized()
	var water_normal := Vector2(tangent.y, -tangent.x)
	var length_m := float(segment.get("length_m", 40.0))
	var dock_reach := float(foundation.get("dock_reach_m", 24.0))
	var along := (along_fraction - 0.5) * length_m
	var local := Vector3(
		float(center_arr[0]) + tangent.x * along + water_normal.x * (dock_reach + beam_m * 0.5 + 5.0) * side_sign,
		0.0,
		float(center_arr[1]) + tangent.y * along + water_normal.y * (dock_reach + beam_m * 0.5 + 5.0) * side_sign,
	)
	var port_basis := Basis(Vector3.UP, plot.rotation.y)
	var world_pos := plot.global_position + port_basis * local
	var world_dir := port_basis * Vector3(tangent.x, 0.0, tangent.y)
	var yaw_degrees := rad_to_deg(atan2(world_dir.x, world_dir.z))
	boat.name = "%s_%s" % [hull_id, str(int(along_fraction * 100.0))]
	boat.freeze = true
	parent.add_child(boat)
	boat.global_position = world_pos
	boat.global_rotation_degrees.y = yaw_degrees
	boat.place_at_waterline(WaveSurface.WATER_LEVEL)
	boat.freeze = true
	var loa := float(entry.get("loa_m", 0.0))
	var beam := float(entry.get("beam_m", 0.0))
	var label := Label3D.new()
	label.name = "%s_Label" % boat.name
	label.text = "%s\n%.0f×%.0f m" % [hull_id.to_upper(), loa, beam]
	label.pixel_size = 0.028
	label.modulate = label_color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	parent.add_child(label)
	label.global_position = world_pos + Vector3(0.0, maxf(beam * 0.65, 8.0), 0.0)


func _spawn_docked_hull(
		parent: Node3D,
		node_name: String,
		hull_id: String,
		world_position: Vector3,
		yaw_degrees: float,
		label_color: Color,
) -> void:
	var entry := HullRegistry.get_by_id(hull_id)
	var boat := HullRegistry.build_hull(hull_id)
	if boat == null:
		push_warning("PortShowcase: failed to build hull %s" % hull_id)
		return
	boat.name = node_name
	boat.freeze = true
	parent.add_child(boat)
	boat.global_position = world_position
	boat.global_rotation_degrees.y = yaw_degrees
	boat.place_at_waterline(WaveSurface.WATER_LEVEL)
	boat.freeze = true
	var loa := float(entry.get("loa_m", 0.0))
	var beam := float(entry.get("beam_m", 0.0))
	var label := Label3D.new()
	label.name = "%s_Label" % node_name
	label.text = "%s\n%.0f×%.0f m" % [hull_id.to_upper(), loa, beam]
	label.pixel_size = 0.028
	label.modulate = label_color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = world_position + Vector3(0.0, maxf(beam * 0.6, 8.0), 0.0)
	parent.add_child(label)


func _world_layout() -> WorldLayout:
	var seed := SEEDS[seed_index]
	if not _layout_cache.has(seed):
		var layout := WORLD_LAYOUT_GENERATOR.generate(seed)
		_layout_cache[seed] = layout
		_definitions_cache[seed] = _place_showcase_ports(layout)
	elif (_definitions_cache.get(seed, []) as Array).is_empty():
		_definitions_cache[seed] = _place_showcase_ports(_layout_cache[seed] as WorldLayout)
	return _layout_cache[seed] as WorldLayout


func _place_showcase_ports(layout: WorldLayout) -> Array:
	return COASTAL_PORT_PLACER.place_ports(
		layout,
		35,
		PackedStringArray(SHOWCASE_PORT_NAMES),
	)


func _select_world_port(layout: WorldLayout) -> PortDefinition:
	var seed := SEEDS[seed_index]
	var definitions := _definitions_cache.get(seed, []) as Array
	var desired_region := _region_kind()
	var regional: Array[PortDefinition] = []
	for raw in definitions:
		var candidate := raw as PortDefinition
		if candidate == null or candidate.region_kind != desired_region:
			continue
		regional.append(candidate)
	var pool: Array[PortDefinition] = regional
	if pool.is_empty():
		for raw in definitions:
			var candidate := raw as PortDefinition
			if candidate != null:
				pool.append(candidate)
	if pool.is_empty():
		_definitions_cache[seed] = _place_showcase_ports(layout)
		definitions = _definitions_cache.get(seed, []) as Array
		for raw in definitions:
			var candidate := raw as PortDefinition
			if candidate != null:
				pool.append(candidate)
	assert(not pool.is_empty(), "PortShowcase requires at least one generated port site")
	var picked := pool[seed_index % pool.size()]
	var definition := PortDefinition.from_dict(picked.to_dict())
	definition.display_name = "%s — TERRAIN FIT" % picked.display_name
	definition.size = port_size
	definition.has_lighthouse = has_lighthouse
	definition.has_fog_horn = has_fog_horn
	definition.ground_mode = PortDefinition.GroundMode.WORLD_TERRAIN
	definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
	return definition


func _region_kind() -> PortDefinition.RegionKind:
	match region_index:
		1:
			return PortDefinition.RegionKind.FJORD
		2:
			return PortDefinition.RegionKind.ARCHIPELAGO
		_:
			return PortDefinition.RegionKind.MAINLAND


func _ensure_world() -> void:
	_ensure_camera()
	if _showcase_playing():
		_ensure_ocean_renderer()
	elif get_node_or_null("WorldEnvironment") == null:
		_ensure_preview_lighting()


func _ensure_camera() -> void:
	_camera = get_node_or_null("Camera3D") as Camera3D
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		_camera.current = true
		_camera.fov = 58.0
		add_child(_camera)
	if _showcase_playing():
		_camera.far = 40000.0


func _ensure_preview_lighting() -> void:
	var node := WorldEnvironment.new()
	node.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.13, 0.16, 0.20)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.78, 0.86)
	environment.ambient_light_energy = 0.75
	node.environment = environment
	add_child(node)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)


func _ensure_ocean_renderer() -> void:
	if get_node_or_null("ShowcaseWorldRenderer") != null:
		return
	var preview_env := get_node_or_null("WorldEnvironment")
	if preview_env != null:
		preview_env.free()
	var preview_sun := get_node_or_null("Sun")
	if preview_sun != null:
		preview_sun.free()
	var renderer := WORLD_RENDERER.new() as WorldRenderer
	renderer.name = "ShowcaseWorldRenderer"
	renderer.force_runtime_build = true
	renderer.enable_volumetric_fog = false
	renderer.enable_ssao = false
	renderer.enable_weather_post_fx = false
	add_child(renderer)


func _ensure_hud() -> void:
	if Engine.is_editor_hint() or get_node_or_null("HudLayer") != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(500.0, 410.0)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_title)
	_stats = Label.new()
	box.add_child(_stats)
	_trade = RichTextLabel.new()
	_trade.bbcode_enabled = true
	_trade.fit_content = true
	_trade.scroll_active = false
	_trade.custom_minimum_size = Vector2(460.0, 150.0)
	box.add_child(_trade)
	_instructions = Label.new()
	_instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_instructions)


func _refresh_hud() -> void:
	if Engine.is_editor_hint() or _title == null:
		return
	_title.text = "TERRAIN-TRACED PORT — WORLD FIT"
	if _last_data == null or _last_data.layout_graph == null:
		return
	var graph := _last_data.layout_graph
	var graph_bounds := graph.bounds()
	var site_position := _last_data.world_position
	var port_area: Dictionary = graph.initial_attributes.get("port_area", {}) as Dictionary
	var recipe: Dictionary = graph.initial_attributes.get("foundation", {}) as Dictionary
	var pier_target_line := ""
	var bay_style := str(graph.initial_attributes.get("port_area", {}).get("harbour_style", ""))
	if not bay_style.is_empty():
		var profile := str(recipe.get("length_profile", port_area.get("length_profile", "standard")))
		pier_target_line = "%s dock · %.0f m shore (hull %.0f m) · %.0f m reach" % [
			profile,
			float(recipe.get("shore_length_m", 0.0)),
			float(recipe.get("design_hull_loa_m", PortSizing.design_hull_loa_m(port_size))),
			float(recipe.get("dock_reach_m", 0.0)),
		]
	var stat_lines: PackedStringArray = PackedStringArray([
		"Seed: %d (#%d)" % [SEEDS[seed_index], seed_index + 1],
		"Length: %s" % LENGTH_PROFILES[length_profile_index],
		"Size: %d — %s" % [port_size, SIZE_LABELS[port_size]],
		"Region: %s" % REGION_LABELS[region_index],
		"World site: %.0f, %.0f · terrain near-field 2.2 km" % [
			site_position.x, site_position.z,
		],
		"Modules: %d · Open slots: %d · coast verts: %d" % [
			graph.modules.size(),
			graph.open_slots().size(),
			(port_area.get("coast_polyline", []) as Array).size(),
		],
		"Port area: %.0f × %.0f m half · coast arc: %.0f m · quay: %.0f m" % [
			float(port_area.get("half_width_m", port_area.get("half_extent_m", 0.0))),
			float(port_area.get("half_depth_m", port_area.get("half_extent_m", 0.0))),
			float(recipe.get("total_coast_arc_m", 0.0)),
			graph.total_quay_length_m(),
		],
		"Scan box: %.0f × %.0f m · trace verts: %d" % [
			float(port_area.get("trace_half_width_m", 0.0)) * 2.0,
			float(port_area.get("trace_half_depth_m", 0.0)) * 2.0,
			(port_area.get("terrain_coast_polyline", []) as Array).size(),
		],
		"Gizmos: red=origin · green=size · yellow=scan · orange=trace · magenta=spine",
		"Design hull: %s (%.0f×%.0f m) · Quay half %.0f · Slot %.0f" % [
			PortSizing.design_hull_id(port_size),
			PortSizing.design_hull_loa_m(port_size),
			PortSizing.design_hull_beam_m(port_size),
			PortSizing.quay_half_length_m(port_size),
			PortSizing.slot_width_m(port_size),
		],
		"Bounds: %.0f × %.0f m" % [graph_bounds.size.x, graph_bounds.size.z],
		"Graph format: %d · generation: %d" % [
			PortLayoutGraph.FORMAT_VERSION,
			graph.generation_version,
		],
		"Move speed: %.0f m/s (scroll adjusts)" % _move_speed,
	])
	if not pier_target_line.is_empty():
		stat_lines.insert(6, pier_target_line)
	_stats.text = "\n".join(stat_lines)
	_trade.text = "[b]Exports[/b]\n%s\n\n[b]Imports[/b]\n%s\n\n" % [
		", ".join(_last_data.trade_profile.export_slots),
		", ".join(_last_data.trade_profile.import_slots),
	]
	var families: Array = graph.initial_attributes.get("terminal_families", [])
	if not families.is_empty():
		var family_labels: PackedStringArray = []
		for family in families:
			family_labels.append(CommodityCatalog.terminal_family_display(str(family)))
		_trade.text += "[b]Terminals[/b]\n%s\n\n" % ", ".join(family_labels)
	_trade.text += "[b]Reading the layout[/b]\n"
	_trade.text += "Natural shore → seaward dock growth → blended town backdrop\n"
	_trade.text += "Mash , . to compare length profiles (compact / standard / extended)\n"
	_trade.text += "Blue hull = design size · green = 28 m reference"
	_instructions.text = "WASD move · Q/E · Shift · RMB look · MMB pan · scroll · Home · ←→ size · ↑↓ region · , . length · - = seed · L/F · R rebuild"
