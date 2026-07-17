extends Node

## Autoload — owns the F3 debug overlay. F4 weather presets + E midday/calm while panel is open.
## F3 then G toggles world gizmos (ports, berth pockets, crane targets, …).
## Layer 100: always above every other UI element.

signal visibility_changed(visible: bool)
signal world_gizmos_changed(enabled: bool)

const _WEATHER_PANEL := preload("res://scripts/weather/weather_debug_presets.gd")

var _layer:   CanvasLayer
var _overlay: DebugDraw
var _weather_preset_panel: Control
var _shown:   bool = false
var _scale_probe: Node3D = null

## Master playtest flag — every `world_gizmo` node + PortPlot site overlays follow this.
var world_gizmos_enabled := false


func is_open() -> bool:
	return _shown


func set_world_gizmos_enabled(enabled: bool) -> void:
	if world_gizmos_enabled == enabled:
		return
	world_gizmos_enabled = enabled
	_apply_world_gizmos()
	world_gizmos_changed.emit(world_gizmos_enabled)
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null and telemetry.has_method("set_context_flag"):
		telemetry.set_context_flag(&"debug.world_gizmos", enabled, &"debug_hud")
	if _overlay != null:
		_overlay.queue_redraw()


func toggle_world_gizmos() -> void:
	set_world_gizmos_enabled(not world_gizmos_enabled)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_layer              = CanvasLayer.new()
	_layer.layer        = 100
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)

	_overlay              = DebugDraw.new()
	_overlay.name         = "DebugDraw"
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.visible      = false
	_layer.add_child(_overlay)

	_weather_preset_panel          = _WEATHER_PANEL.new()
	_weather_preset_panel.name    = "WeatherDebugPresets"
	_weather_preset_panel.visible = false
	_layer.add_child(_weather_preset_panel)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.physical_keycode == KEY_F3:
			_shown           = not _shown
			_overlay.visible = _shown
			if not _shown:
				_weather_preset_panel.visible = false
			visibility_changed.emit(_shown)
			var telemetry := get_node_or_null("/root/Telemetry")
			if telemetry != null and telemetry.has_method("set_context_flag"):
				telemetry.set_context_flag(&"debug.f3_open", _shown, &"debug_hud")
			_refresh_lane_debug_draw()
			get_viewport().set_input_as_handled()
		elif ke.pressed and not ke.echo and ke.physical_keycode == KEY_F4 and _shown:
			_weather_preset_panel.visible = not _weather_preset_panel.visible
			get_viewport().set_input_as_handled()
		elif ke.pressed and not ke.echo and ke.physical_keycode == KEY_E and _shown:
			_apply_debug_day_calm_preset()
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _shown:
		return
	if not event is InputEventKey:
		return
	var ke := event as InputEventKey
	if not ke.pressed or ke.echo:
		return
	match ke.physical_keycode:
		KEY_TAB:
			_overlay.cycle_tab(-1 if ke.shift_pressed else 1)
			get_viewport().set_input_as_handled()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_overlay.select_tab(int(ke.physical_keycode - KEY_1))
			get_viewport().set_input_as_handled()
		KEY_H:
			_overlay.toggle_value_mode()
			get_viewport().set_input_as_handled()
		KEY_C:
			_overlay.copy_report()
			get_viewport().set_input_as_handled()
		KEY_R:
			_overlay.reset_peaks()
			get_viewport().set_input_as_handled()
		KEY_B:
			BerthApproachLanes.toggle_debug()
			_refresh_lane_debug_draw()
			_overlay.queue_redraw()
			get_viewport().set_input_as_handled()
		KEY_G:
			toggle_world_gizmos()
			get_viewport().set_input_as_handled()
		KEY_P:
			_toggle_scale_probe()
			get_viewport().set_input_as_handled()


func _apply_world_gizmos() -> void:
	var tree := get_tree()
	if tree == null:
		return
	WorldGizmos.apply_all(tree, world_gizmos_enabled)
	## Port site overlays (spine / quay roots / harbour berths / …).
	for node in tree.get_nodes_in_group("port_plot"):
		var plot := node as PortPlot
		if plot != null:
			plot.show_site_gizmos = world_gizmos_enabled
	## Crane auto-aim targets.
	for node in tree.get_nodes_in_group("bulk_crane_auto"):
		if node != null and node.has_method("set_show_target_gizmos"):
			node.call("set_show_target_gizmos", world_gizmos_enabled)
		elif node != null and "show_target_gizmos" in node:
			node.set("show_target_gizmos", world_gizmos_enabled)


func _apply_debug_day_calm_preset() -> void:
	var wl := get_node_or_null("/root/WeatherLighting") as WeatherLightingState
	if wl != null:
		wl.apply_weather_state(WeatherState.create_clear_calm())

	WorldWeather.set_blend_to_lighting_paused(true)

	var wc := get_node_or_null("/root/WorldClock")
	if wc != null and wc.has_method("snap_time_of_day"):
		wc.snap_time_of_day(0.5)


## F3 + P — drops a measured scale rig 3 m in front of the player: a 1.8 m
## mannequin, a 1 m red stick, and live-measured AABB labels for the nearest
## boat. Ground truth for "how big is X really" arguments.
func _toggle_scale_probe() -> void:
	if _scale_probe != null and is_instance_valid(_scale_probe):
		_scale_probe.queue_free()
		_scale_probe = null
		return

	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var player := tree.get_first_node_in_group("player") as Node3D
	if player == null:
		return

	_scale_probe = Node3D.new()
	_scale_probe.name = "ScaleProbe"
	tree.current_scene.add_child(_scale_probe)

	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	_scale_probe.global_position = player.global_position + fwd * 3.0

	# 1.8 m mannequin (same rig as the player body).
	var dummy := NpcBase.new()
	dummy.name = "Mannequin18"
	_scale_probe.add_child(dummy)
	_probe_label("1.8 m — same mesh as you", Vector3(0.0, 2.15, 0.0), Color(0.95, 0.8, 0.3))

	# 1 m stick.
	var stick := MeshBuilder.box(Vector3(0.06, 1.0, 0.06), Color(0.95, 0.2, 0.15), 0.5, 0.0)
	stick.position = Vector3(0.8, 0.5, 0.0)
	_scale_probe.add_child(stick)
	_probe_label("1 m", Vector3(0.8, 1.25, 0.0), Color(0.95, 0.35, 0.3))

	# Live-measured nearest boat AABB — what the renderer actually draws,
	# not what any constant claims.
	var boat := _nearest_boat(player.global_position)
	if boat != null:
		var aabb := _measure_visual_aabb(boat)
		_probe_label(
			"boat measured: %.1f long × %.1f wide × %.1f tall" % [aabb.size.z, aabb.size.x, aabb.size.y],
			Vector3(0.0, 2.6, 0.0),
			Color(0.4, 0.85, 1.0),
		)
	else:
		_probe_label("no boat within 200 m", Vector3(0.0, 2.6, 0.0), Color(0.6, 0.6, 0.6))


func _probe_label(text: String, pos: Vector3, color: Color) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 40
	lbl.pixel_size = 0.006
	lbl.position = pos
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.modulate = color
	lbl.outline_size = 8
	_scale_probe.add_child(lbl)


func _nearest_boat(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := 200.0
	for n in get_tree().get_nodes_in_group("player_boat"):
		if n is Node3D:
			var d := (n as Node3D).global_position.distance_to(from)
			if d < best_d:
				best_d = d
				best = n
	if best == null:
		# Fall back to any BoatBody in the scene.
		for n in get_tree().current_scene.get_children():
			if n is BoatBody:
				var d2 := (n as Node3D).global_position.distance_to(from)
				if d2 < best_d:
					best_d = d2
					best = n
	return best


static func _measure_visual_aabb(root: Node3D) -> AABB:
	## World-space union of every visible MeshInstance3D under root.
	var result := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var local := mi.get_aabb()
		var xf := mi.global_transform
		for i in range(8):
			var corner := xf * local.get_endpoint(i)
			if first:
				result = AABB(corner, Vector3.ZERO)
				first = false
			else:
				result = result.expand(corner)
	return result


func _refresh_lane_debug_draw() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if tree.get_first_node_in_group("berth_lane_debug") == null:
		var scene := tree.current_scene
		if scene != null:
			var draw := BerthApproachLanesDebugDraw.new()
			draw.name = "BerthApproachLanesDebugDraw"
			scene.add_child(draw)
	BerthApproachLanesDebugDraw.refresh_if_enabled(tree)
