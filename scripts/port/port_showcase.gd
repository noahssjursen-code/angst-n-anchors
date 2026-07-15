@tool
class_name PortShowcase
extends Node3D

## F6 gallery for terrain-traced ports (foundation + berth_plan) on seeded coast.
## Each F6 run rolls a fresh world seed so ports don't always look identical.

const REGION_LABELS: Array[String] = ["mainland", "fjord", "archipelago"]
const SIZE_LABELS: Array[String] = [
	"landing", "local", "regional", "large", "industrial",
	"major", "deep", "mega", "hub",
]
const WORLD_LAYOUT_GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const COASTAL_PORT_PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const TERRAIN_STREAMER := preload("res://scripts/world/world_terrain_streamer.gd")
const WORLD_RENDERER := preload("res://scripts/world/world_renderer.gd")
const BERTH_PLAN := preload("res://scripts/port/port_berth_plan.gd")
const SHOWCASE_PORT_NAMES: Array[String] = [
	"Holmvik", "Sandvær", "Bergnes", "Kloven", "Strandnes", "Kvamsvik",
	"Bremsund", "Tysneset", "Fjelltun", "Grønnvik", "Harberg", "Innvær",
]
const REF_HULL_ID := "hull_28x10"
const LENGTH_PROFILES: Array[String] = ["compact", "standard", "extended"]

## G cycles these packs (index 0 = off). Add a new debug pack here when you need one:
## {
##   "id": "my_pack",
##   "label": "My pack",
##   "hint": "short colour legend",
##   "site_layers": { PortDebugGizmos.LAYER_SPINE: true },  # optional subset
## }
const GIZMO_PACKS: Array[Dictionary] = [
	{
		"id": "site",
		"label": "Site",
		"hint": "origin · size · scan · coast · spine",
		"site_layers": {
			PortDebugGizmos.LAYER_ORIGIN: true,
			PortDebugGizmos.LAYER_AXES: true,
			PortDebugGizmos.LAYER_SIZE_BOX: true,
			PortDebugGizmos.LAYER_TRACE_BOX: true,
			PortDebugGizmos.LAYER_TERRAIN_TRACE: true,
			PortDebugGizmos.LAYER_SPINE: true,
			PortDebugGizmos.LAYER_SHORE_SPAN: true,
			PortDebugGizmos.LAYER_DOCK_FACE: true,
			PortDebugGizmos.LAYER_GRAPH_ROOT: true,
		},
	},
	{
		"id": "quays",
		"label": "Quays",
		"hint": "dock face · asphalt · quay markers (terminals always on)",
		"site_layers": {
			PortDebugGizmos.LAYER_DOCK_FACE: true,
			PortDebugGizmos.LAYER_ASPHALT_BERTHS: true,
			PortDebugGizmos.LAYER_QUAY_ROOTS: true,
			PortDebugGizmos.LAYER_QUAY_ARMS: true,
		},
	},
]

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

@export_range(0, 2) var length_profile_index := 1:
	set(value):
		length_profile_index = clampi(value, 0, LENGTH_PROFILES.size() - 1)
		if is_inside_tree() and not _configuring:
			_request_rebuild()

## Active world seed. Rolled on each F6 start; - / = rolls a new one in-session.
@export var world_seed := 424242:
	set(value):
		world_seed = value if value != 0 else 1
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

## 0 = gizmos off. 1..N = GIZMO_PACKS[index - 1]. G / Shift+G cycles.
@export_range(0, 16) var gizmo_pack_index := 0:
	set(value):
		gizmo_pack_index = clampi(value, 0, GIZMO_PACKS.size())
		_apply_gizmo_pack()

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
var _status: Label
var _stats: Label
var _gizmo_line: Label
var _controls: Label
var _meta_title: Label
var _meta_identity: Label
var _meta_trade: RichTextLabel
var _meta_sizing: Label
var _meta_foundation: Label
var _meta_graph: Label
var _meta_panel: PanelContainer


func _ready() -> void:
	_ensure_world()
	_ensure_hud()
	## F6 / play: fresh world every run. Editor preview keeps the exported seed.
	if not Engine.is_editor_hint():
		_roll_world_seed(false)
	_rebuild()


func _roll_world_seed(rebuild_now: bool = true) -> void:
	_configuring = true
	world_seed = randi()
	if world_seed == 0:
		world_seed = 1
	_configuring = false
	if rebuild_now and is_inside_tree():
		_request_rebuild()


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
			_cycle_port_size(-1)
		KEY_RIGHT, KEY_BRACKETRIGHT:
			_cycle_port_size(1)
		KEY_UP:
			region_index = wrapi(region_index - 1, 0, 3)
		KEY_DOWN:
			region_index = wrapi(region_index + 1, 0, 3)
		KEY_COMMA:
			length_profile_index = wrapi(length_profile_index - 1, 0, LENGTH_PROFILES.size())
		KEY_PERIOD:
			length_profile_index = wrapi(length_profile_index + 1, 0, LENGTH_PROFILES.size())
		KEY_MINUS, KEY_EQUAL:
			_roll_world_seed(true)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			var requested := int((event as InputEventKey).keycode) - int(KEY_1)
			port_size = clampi(requested, PortSizing.MIN_SIZE, _size_cycle_max())
		KEY_L:
			has_lighthouse = not has_lighthouse
		KEY_F:
			has_fog_horn = not has_fog_horn
		KEY_G:
			var step := -1 if (event as InputEventKey).shift_pressed else 1
			gizmo_pack_index = wrapi(gizmo_pack_index + step, 0, GIZMO_PACKS.size() + 1)
			_refresh_hud()
		KEY_R:
			_request_rebuild()
		KEY_HOME:
			_frame_port()
			_refresh_hud()


## Wrap size within this port's live ceiling so capped harbours don't dead-cycle 5→8.
func _size_cycle_max() -> int:
	if _last_data != null and _last_data.layout_graph != null:
		return clampi(
			int(_last_data.layout_graph.initial_attributes.get(
				"site_max_size",
				PortSizing.MAX_SIZE,
			)),
			PortSizing.MIN_SIZE,
			PortSizing.MAX_SIZE,
		)
	if _active_definition != null:
		return clampi(
			_active_definition.site_max_size if _active_definition.site_max_size > 0 \
					else PortSizing.MAX_SIZE,
			PortSizing.MIN_SIZE,
			PortSizing.MAX_SIZE,
		)
	return PortSizing.MAX_SIZE


func _cycle_port_size(delta: int) -> void:
	var lo := PortSizing.MIN_SIZE
	var hi := _size_cycle_max()
	var span := hi - lo + 1
	var current := clampi(port_size, lo, hi)
	port_size = lo + posmod(current - lo + delta, span)


func _gizmo_pack_label() -> String:
	if gizmo_pack_index <= 0 or gizmo_pack_index > GIZMO_PACKS.size():
		return "Off"
	return str(GIZMO_PACKS[gizmo_pack_index - 1].get("label", "Pack"))


func _gizmo_pack_hint() -> String:
	if gizmo_pack_index <= 0 or gizmo_pack_index > GIZMO_PACKS.size():
		return "G cycle packs"
	return str(GIZMO_PACKS[gizmo_pack_index - 1].get("hint", ""))


func _apply_gizmo_pack() -> void:
	var plot := get_node_or_null("GeneratedPort/PortPlot") as PortPlot
	if plot == null:
		return
	if gizmo_pack_index <= 0 or gizmo_pack_index > GIZMO_PACKS.size():
		plot.clear_gizmo_layer_overrides()
		plot.show_site_gizmos = false
		return
	var pack: Dictionary = GIZMO_PACKS[gizmo_pack_index - 1]
	var site_layers: Dictionary = pack.get("site_layers", {}) as Dictionary
	if site_layers.is_empty():
		plot.clear_gizmo_layer_overrides()
		plot.show_site_gizmos = true
	else:
		## Explicit subset: start all site layers off, then enable listed ones.
		plot.show_site_gizmos = false
		var resolved := PortDebugGizmos.default_layers(false)
		for layer_id in site_layers:
			resolved[str(layer_id)] = bool(site_layers[layer_id])
		plot.set_gizmo_layers(resolved)


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
		^ world_seed
		^ (region_index * 224737)
		^ definition.port_id.hash()
	)
	_active_definition = definition
	_last_data = PortExpander.expand(definition, layout.seed, layout, {
		"length_profile_override": LENGTH_PROFILES[length_profile_index],
	})
	## Keep the size dial on the live clamped size so cycling wraps at the ceiling.
	if _last_data != null and port_size != _last_data.size:
		_configuring = true
		port_size = PortSizing.normalized_size(_last_data.size)
		_configuring = false
	_frame_port()
	var world_center := _port_dock_focus_world()

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
	plot.configure(_last_data)
	generated.add_child(plot)
	plot.global_position = _last_data.world_position
	_apply_gizmo_pack()
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
	var design_size := PortSizing.normalized_size(_last_data.size if _last_data != null else port_size)
	var design_hull_id := PortSizing.design_hull_id(design_size)
	var design_loa := PortSizing.design_hull_loa_m(design_size)
	var design_beam := PortSizing.design_hull_beam_m(design_size)
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
	var pad_local_y := float(foundation.get("surface_y_m", PortCoastTracer.FOUNDATION_SURFACE_Y_M)) \
			+ PortCoastTracer.FOUNDATION_TERRAIN_CLEARANCE_M
	var pad_world_y := plot.to_global(Vector3(local.x, pad_local_y, local.z)).y
	if boat.global_position.y < pad_world_y + 0.05:
		boat.global_position.y = pad_world_y + 0.05
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
	var seed := world_seed
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
	var seed := world_seed
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
	var picked := pool[absi(world_seed) % pool.size()]
	var definition := PortDefinition.from_dict(picked.to_dict())
	definition.display_name = "%s — TERRAIN FIT" % picked.display_name
	## Geography ceiling from placement. Trade volume clamps further in PortExpander.
	var geo_max := clampi(
		picked.site_max_size if picked.site_max_size > 0 else PortSizing.MAX_SIZE,
		PortSizing.MIN_SIZE,
		PortSizing.MAX_SIZE,
	)
	definition.site_max_size = geo_max
	definition.size = port_size
	definition.set_meta("showcase_geo_max_size", geo_max)
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
	panel.name = "HudPanel"
	panel.position = Vector2(16.0, 16.0)
	panel.custom_minimum_size = Vector2(340.0, 0.0)
	panel.add_theme_stylebox_override("panel", _hud_panel_style())
	layer.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	box.add_child(_title)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(0.72, 0.78, 0.84))
	box.add_child(_status)

	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 12)
	_stats.add_theme_color_override("font_color", Color(0.86, 0.88, 0.90))
	box.add_child(_stats)

	_gizmo_line = Label.new()
	_gizmo_line.add_theme_font_size_override("font_size", 12)
	_gizmo_line.add_theme_color_override("font_color", Color(0.78, 0.90, 0.72))
	box.add_child(_gizmo_line)

	_controls = Label.new()
	_controls.add_theme_font_size_override("font_size", 11)
	_controls.add_theme_color_override("font_color", Color(0.58, 0.62, 0.68))
	_controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls.custom_minimum_size = Vector2(312.0, 0.0)
	box.add_child(_controls)

	_ensure_meta_panel(layer)


func _hud_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.78)
	style.set_content_margin_all(14.0)
	style.set_corner_radius_all(6)
	return style


func _ensure_meta_panel(layer: CanvasLayer) -> void:
	_meta_panel = PanelContainer.new()
	_meta_panel.name = "MetaPanel"
	_meta_panel.custom_minimum_size = Vector2(360.0, 0.0)
	_meta_panel.add_theme_stylebox_override("panel", _hud_panel_style())
	_meta_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_meta_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_meta_panel.offset_left = -376.0
	_meta_panel.offset_right = -16.0
	_meta_panel.offset_top = 16.0
	_meta_panel.offset_bottom = 16.0
	layer.add_child(_meta_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_meta_panel.add_child(box)

	_meta_title = Label.new()
	_meta_title.text = "Port data"
	_meta_title.add_theme_font_size_override("font_size", 18)
	_meta_title.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	box.add_child(_meta_title)

	_meta_identity = _meta_section_label(Color(0.72, 0.78, 0.84))
	box.add_child(_meta_identity)

	_meta_trade = RichTextLabel.new()
	_meta_trade.bbcode_enabled = true
	_meta_trade.fit_content = true
	_meta_trade.scroll_active = false
	_meta_trade.custom_minimum_size = Vector2(332.0, 0.0)
	_meta_trade.add_theme_font_size_override("normal_font_size", 12)
	box.add_child(_meta_trade)

	_meta_sizing = _meta_section_label(Color(0.86, 0.88, 0.90))
	box.add_child(_meta_sizing)

	_meta_foundation = _meta_section_label(Color(0.86, 0.88, 0.90))
	box.add_child(_meta_foundation)

	_meta_graph = _meta_section_label(Color(0.70, 0.74, 0.78))
	box.add_child(_meta_graph)


func _meta_section_label(color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(332.0, 0.0)
	return label


func _refresh_hud() -> void:
	if Engine.is_editor_hint() or _title == null:
		return
	_title.text = "Port showcase"
	if _last_data == null or _last_data.layout_graph == null:
		_status.text = "No port loaded"
		_stats.text = ""
		_gizmo_line.text = "Gizmos  Off"
		_controls.text = "G cycle · R rebuild"
		_refresh_meta()
		return

	var graph := _last_data.layout_graph
	var recipe: Dictionary = graph.initial_attributes.get("foundation", {}) as Dictionary
	var profile := str(recipe.get("length_profile", LENGTH_PROFILES[length_profile_index]))
	var port_name := _last_data.display_name
	if port_name.is_empty() and _active_definition != null:
		port_name = _active_definition.display_name

	var live_size := PortSizing.normalized_size(_last_data.size)
	var geo_max := PortSizing.MAX_SIZE
	if _active_definition != null and _active_definition.has_meta("showcase_geo_max_size"):
		geo_max = int(_active_definition.get_meta("showcase_geo_max_size"))
	geo_max = int(graph.initial_attributes.get(
		"site_max_size",
		geo_max,
	))
	_status.text = "%s  ·  %s  ·  size %d %s" % [
		port_name,
		REGION_LABELS[region_index],
		live_size,
		SIZE_LABELS[live_size],
	]
	_stats.text = "\n".join(PackedStringArray([
		"Seed %d   length %s" % [world_seed, profile],
		"Shore %.0f m   reach %.0f m   hull %s" % [
			float(recipe.get("shore_length_m", 0.0)),
			float(recipe.get("dock_reach_m", 0.0)),
			PortSizing.design_hull_id(live_size),
		],
		"Quay½ %.0f m   geo ceiling %d   gen %d" % [
			PortSizing.quay_half_length_m(live_size),
			geo_max,
			graph.generation_version,
		],
	]))

	var pack_label := _gizmo_pack_label()
	var pack_hint := _gizmo_pack_hint()
	if pack_hint.is_empty():
		_gizmo_line.text = "Gizmos  %s   ·  G / Shift+G" % pack_label
	else:
		_gizmo_line.text = "Gizmos  %s   ·  %s" % [pack_label, pack_hint]

	_controls.text = "←→ size  ↑↓ region  , . length  - = roll seed\nWASD move  RMB look  Home frame  R rebuild  G gizmos"
	_refresh_meta()


func _refresh_meta() -> void:
	if Engine.is_editor_hint() or _meta_identity == null:
		return
	if _last_data == null or _last_data.layout_graph == null:
		_meta_identity.text = "No port loaded"
		_meta_trade.text = ""
		_meta_sizing.text = ""
		_meta_foundation.text = ""
		_meta_graph.text = ""
		return

	var data := _last_data
	var graph := data.layout_graph
	var recipe: Dictionary = graph.initial_attributes.get("foundation", {}) as Dictionary
	var spine := recipe.get("spine", []) as Array
	var size := PortSizing.normalized_size(data.size)
	var region := "legacy"
	match data.region_kind:
		PortDefinition.RegionKind.MAINLAND:
			region = "mainland"
		PortDefinition.RegionKind.FJORD:
			region = "fjord"
		PortDefinition.RegionKind.ARCHIPELAGO:
			region = "archipelago"
		_:
			region = "legacy"

	var port_name := data.display_name
	if port_name.is_empty() and _active_definition != null:
		port_name = _active_definition.display_name

	var trade := data.trade_profile
	var geo_ceiling := int(graph.initial_attributes.get("site_max_size", PortSizing.MAX_SIZE))
	if _active_definition != null and _active_definition.has_meta("showcase_geo_max_size"):
		geo_ceiling = int(_active_definition.get_meta("showcase_geo_max_size"))
	var trade_ceiling := int(graph.initial_attributes.get(
		"trade_max_size",
		PortTradeProfile.max_size_for_profile(trade) if trade != null else PortSizing.MAX_SIZE,
	))
	_meta_identity.text = "\n".join(PackedStringArray([
		"%s" % port_name,
		"id  %s" % data.port_id,
		"size  %d — %s" % [size, SIZE_LABELS[size]],
		"ceiling  %d  (geo %d · trade %d · %d products)" % [
			int(graph.initial_attributes.get("site_max_size", size)),
			geo_ceiling,
			trade_ceiling,
			PortTradeProfile.destiny_product_count(trade) if trade != null else 0,
		],
		"region  %s" % region,
		"site seed  %d" % data.layout_seed,
		"generation  %d" % data.port_generation_version,
	]))

	var primary := ""
	if trade != null:
		primary = trade.primary_export()
	var trade_bb := "[b]Trade[/b]\n"
	if trade != null and not str(trade.theme_id).is_empty():
		trade_bb += "theme  %s  (destiny fixed)\n" % str(trade.theme_id).replace("_", " ")
	trade_bb += "unlocked  %d export / %d import at this size" % [
		trade.export_slots.size() if trade != null else 0,
		trade.import_slots.size() if trade != null else 0,
	]
	if size >= PortSizing.TRADE_COMPLETE_SIZE:
		trade_bb += "  ·  trade complete\n"
	else:
		trade_bb += "  ·  full by size %d\n" % PortSizing.TRADE_COMPLETE_SIZE
	if primary.is_empty():
		trade_bb += "primary export  —\n"
	else:
		trade_bb += "primary export  %s\n" % CommodityCatalog.commodity_display(primary)
	trade_bb += "\n[b]Exports[/b]\n"
	trade_bb += _format_trade_slots(trade.export_slots if trade != null else [])
	if trade != null:
		for id in trade.locked_export_slots():
			trade_bb += "  [color=#666666]□[/color] %s  ·  locked\n" % CommodityCatalog.commodity_display(id)
	trade_bb += "\n[b]Imports[/b]\n"
	trade_bb += _format_trade_slots(trade.import_slots if trade != null else [])
	if trade != null:
		for id in trade.locked_import_slots():
			trade_bb += "  [color=#666666]□[/color] %s  ·  locked\n" % CommodityCatalog.commodity_display(id)
	var berth_plan: Dictionary = graph.initial_attributes.get("berth_plan", {}) as Dictionary
	if not berth_plan.is_empty():
		trade_bb += "\n[b]Berth plan[/b]\n"
		trade_bb += "asphalt docks  %d   dedicated quays  %d\n" % [
			int(berth_plan.get("asphalt_slot_count", 0)),
			int(berth_plan.get("quay_count", 0)),
		]
		for note in berth_plan.get("notes", []) as Array:
			trade_bb += "%s\n" % str(note)
		for raw in berth_plan.get("quay_stations", []) as Array:
			var station := raw as Dictionary
			if str(station.get("layout", "")) == "twin_joined":
				trade_bb += "  twin quay  ·  dock|crane|cargo|road|cargo|crane|dock\n"
				for side_raw in station.get("sides", []) as Array:
					var side := side_raw as Dictionary
					for zone_raw in side.get("zones", []) as Array:
						var zone := zone_raw as Dictionary
						var cid := str(zone.get("commodity_id", ""))
						var zcolor := CommodityCatalog.commodity_color(cid) if not cid.is_empty() \
								else CommodityCatalog.terminal_family_color(str(side.get("family", "")))
						trade_bb += "  [color=#%s]■[/color] %s  ·  twin side  %.0f m\n" % [
							zcolor.to_html(false),
							str(zone.get("label", cid)).replace("\n", " · "),
							float(station.get("length_m", 0.0)),
						]
				continue
			for zone_raw in station.get("zones", []) as Array:
				var zone := zone_raw as Dictionary
				var cid := str(zone.get("commodity_id", ""))
				var zcolor := CommodityCatalog.commodity_color(cid) if not cid.is_empty() \
						else CommodityCatalog.terminal_family_color(str(station.get("family", "")))
				trade_bb += "  [color=#%s]■[/color] %s  ·  %.0f m quay\n" % [
					zcolor.to_html(false),
					str(zone.get("label", cid)).replace("\n", " · "),
					float(station.get("length_m", 0.0)) * maxf(
						float(zone.get("t1", 1.0)) - float(zone.get("t0", 0.0)),
						0.05,
					),
				]
		for raw in berth_plan.get("asphalt_stations", []) as Array:
			var station := raw as Dictionary
			var commodity_id := str(station.get("commodity_id", ""))
			var color := CommodityCatalog.terminal_family_color(
				CommodityCatalog.commodity_terminal_family(commodity_id),
			)
			trade_bb += "  [color=#%s]●[/color] %s  ·  apron  %.0f×%.0f m\n" % [
				color.to_html(false),
				CommodityCatalog.commodity_display(commodity_id),
				float(station.get("length_m", 0.0)),
				float(station.get("depth_m", 0.0)),
			]
	_meta_trade.text = trade_bb

	var planned_quays := int(berth_plan.get("quay_count", 0))
	var planned_asphalt := int(berth_plan.get("asphalt_slot_count", 0))
	var live_berths := data.berth_count
	var berth_note := "live modules %d   planned quays %d + asphalt %d" % [
		live_berths, planned_quays, planned_asphalt,
	]
	if live_berths <= 1 and planned_quays > 0:
		berth_note += "\n(wide berth terminals on foundation · max %d quays)" % PortSizing.max_dedicated_quays(size)
	_meta_sizing.text = "\n".join(PackedStringArray([
		"[Sizing]",
		"quay½  %.0f m   deck  %.0f m" % [
			PortSizing.quay_half_length_m(size),
			PortSizing.quay_deck_width_m(size),
		],
		"pad  %.0f × %.0f m" % [
			PortSizing.terrain_pad_width_m(size),
			PortSizing.terrain_pad_depth_m(size),
		],
		"hull  %s  (%.0f×%.0f m)" % [
			PortSizing.design_hull_id(size),
			PortSizing.design_hull_loa_m(size),
			PortSizing.design_hull_beam_m(size),
		],
		berth_note,
	]))

	_meta_foundation.text = "\n".join(PackedStringArray([
		"[Foundation]",
		"profile  %s" % str(recipe.get("length_profile", LENGTH_PROFILES[length_profile_index])),
		"shore  %.0f m   reach  %.0f m" % [
			float(recipe.get("shore_length_m", 0.0)),
			float(recipe.get("dock_reach_m", 0.0)),
		],
		"spine  %d verts" % spine.size(),
		_basin_hud_line(graph.initial_attributes.get("basin", recipe.get("basin", {}))),
	]))

	_meta_graph.text = "\n".join(PackedStringArray([
		"[Layout graph]",
		"modules  %d   open slots  %d" % [graph.modules.size(), graph.open_slots().size()],
		"graph format  %d" % PortLayoutGraph.FORMAT_VERSION,
	]))


func _basin_hud_line(basin: Variant) -> String:
	if typeof(basin) != TYPE_DICTIONARY or (basin as Dictionary).is_empty():
		return "basin  —"
	var b := basin as Dictionary
	if bool(b.get("probe_failed", false)):
		return "basin  probe skipped — no length clamp"
	var arm := float(b.get("max_arm_m", 0.0))
	var arm_txt := "∞" if not is_finite(arm) else "%.0f m" % arm
	return "basin  sea %.0f m  across %.0f m  arm≤%s  site≤%d  tight %.0f%%" % [
		float(b.get("seaward_clear_m", 0.0)),
		float(b.get("across_clear_m", 0.0)),
		arm_txt,
		int(b.get("site_max_size", PortSizing.MAX_SIZE)),
		float(b.get("tightness", 0.0)) * 100.0,
	]


func _format_trade_slots(slots: Array) -> String:
	if slots.is_empty():
		return "  —\n"
	var lines := ""
	for raw in slots:
		var commodity_id := str(raw)
		var color := CommodityCatalog.commodity_color(commodity_id)
		var hex := color.to_html(false)
		var dock := "asphalt" if BERTH_PLAN.uses_asphalt_dock(commodity_id) else "quay"
		lines += "  [color=#%s]■[/color] %s  ·  %s\n" % [
			hex,
			CommodityCatalog.commodity_display(commodity_id),
			dock,
		]
	return lines
