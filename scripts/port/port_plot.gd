@tool
class_name PortPlot
extends Node3D

## Runtime composition root for the visualize-first port graph.
## Stamps foundation, berth_plan pads/quays, land decor, and harbour props.

signal rebuild_completed(duration_ms: float)


@export var port_id := ""
@export var port_label := "Port"
@export var plot_width := 80.0
@export var plot_depth := 140.0
@export var port_size := 1

## Master switch for site debug overlays. Geometry stays stamped; layers toggle visibility.
@export var show_site_gizmos := false:
	set(value):
		show_site_gizmos = value
		_sync_site_gizmo_layers()

var _data: PortData
var _layout_graph: PortLayoutGraph
## Optional per-layer overrides. Empty = all site layers follow show_site_gizmos.
var _gizmo_layer_overrides: Dictionary = {}


func _ready() -> void:
	add_to_group("port_plot")
	_wire_world_gizmos()
	call_deferred("_rebuild")


func _wire_world_gizmos() -> void:
	if Engine.is_editor_hint():
		return
	var hud := get_node_or_null("/root/DebugHud")
	if hud == null:
		return
	if hud.has_signal("world_gizmos_changed") \
			and not hud.world_gizmos_changed.is_connected(_on_world_gizmos_changed):
		hud.world_gizmos_changed.connect(_on_world_gizmos_changed)
	show_site_gizmos = bool(hud.get("world_gizmos_enabled"))


func _on_world_gizmos_changed(enabled: bool) -> void:
	show_site_gizmos = enabled


func configure(data: PortData) -> void:
	_data = data
	port_id = data.port_id
	port_label = data.display_name
	port_size = data.size
	plot_width = data.island_width
	plot_depth = data.plot_depth
	_layout_graph = data.layout_graph
	rotation.y = data.rotation_y
	if is_inside_tree():
		_rebuild()


func set_gizmo_layer(layer_id: String, enabled: bool) -> void:
	_gizmo_layer_overrides[layer_id] = enabled
	_sync_site_gizmo_layers()


func set_gizmo_layers(layer_visible: Dictionary) -> void:
	_gizmo_layer_overrides = layer_visible.duplicate()
	_sync_site_gizmo_layers()


func clear_gizmo_layer_overrides() -> void:
	_gizmo_layer_overrides.clear()
	_sync_site_gizmo_layers()


func gizmo_layer_state() -> Dictionary:
	var gizmos := get_node_or_null("PortDebugGizmos") as PortDebugGizmos
	if gizmos != null:
		return gizmos.layer_state()
	return PortDebugGizmos.default_layers(show_site_gizmos)


func _rebuild() -> void:
	var rebuild_started := Time.get_ticks_usec()
	var old_harbour := get_node_or_null("HarbourController") as HarbourController
	if old_harbour != null:
		old_harbour.unregister_all()
		old_harbour.deactivate()
	for child in get_children():
		child.free()
	if _layout_graph == null:
		rebuild_completed.emit(float(Time.get_ticks_usec() - rebuild_started) / 1000.0)
		return

	var harbour := HarbourController.new()
	harbour.setup(port_id if not port_id.is_empty() else "port")
	add_child(harbour)
	harbour.activate()

	var visualizer := PortLayoutGraphVisualizer.new()
	visualizer.name = "PortLayoutGraph"
	add_child(visualizer)
	visualizer.configure(_layout_graph, harbour)

	## Always stamp gizmos so layers can be toggled without a full rebuild.
	var gizmos := PortDebugGizmos.new()
	gizmos.name = "PortDebugGizmos"
	add_child(gizmos)
	gizmos.configure(_layout_graph, _resolved_gizmo_layers(), harbour)

	if not port_label.is_empty():
		var label := Label3D.new()
		label.name = "PortName"
		label.text = port_label.to_upper()
		label.pixel_size = 0.04
		label.modulate = Color(0.98, 0.94, 0.78)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		var graph_bounds := _layout_graph.bounds()
		label.position = graph_bounds.get_center() + Vector3(0.0, 12.0, 0.0)
		add_child(label)

	if not Engine.is_editor_hint():
		_spawn_harbour_staff()

	if is_inside_tree():
		_register_with_catalog()
	if Engine.is_editor_hint() and is_inside_tree():
		var root := get_tree().edited_scene_root
		if root != null:
			for child in get_children():
				_own_subtree(child, root)
	rebuild_completed.emit(float(Time.get_ticks_usec() - rebuild_started) / 1000.0)


func _spawn_harbour_staff() -> void:
	## Player spawn uses top_y+1 (CharacterBody origin). NPC feet sit on the deck.
	var apron := _staff_apron_local()
	var facing_seaward := PI  ## mesh faces +Z; seaward is typically −Z inland→sea flip

	var hm := HarbourMasterNpc.new()
	hm.name = "HarbourMaster"
	hm.port_id = port_id
	hm.interact_range = 6.0
	hm.position = apron + Vector3(-3.5, 0.0, 0.0)
	hm.rotation.y = facing_seaward
	add_child(hm)
	_add_staff_nameplate(hm, "HARBOUR MASTER")

	var sw := ShipwrightNpc.new()
	sw.name = "Shipwright"
	sw.interact_range = 6.0
	sw.clothing_color = Color(0.42, 0.28, 0.18)
	sw.trousers_color = Color(0.18, 0.20, 0.24)
	sw.position = apron + Vector3(3.5, 0.0, 0.0)
	sw.rotation.y = facing_seaward
	add_child(sw)
	_add_staff_nameplate(sw, "SHIPWRIGHT")
	sw.call_deferred("add_overlay", "hat", AssetPaths.HAT_FLAT_CAP)

	## Snap feet onto apron/foundation collision once StaticBodies exist.
	call_deferred("_snap_staff_to_ground", [hm, sw])


func _staff_apron_local() -> Vector3:
	if _layout_graph == null:
		return Vector3(0.0, PortCoastTracer.FOUNDATION_SURFACE_Y_M \
				+ PortCoastTracer.FOUNDATION_TERRAIN_CLEARANCE_M, 14.0)
	var foundation := _layout_graph.initial_attributes.get("foundation", {}) as Dictionary
	var surface_y := float(foundation.get(
		"surface_y_m",
		PortCoastTracer.FOUNDATION_SURFACE_Y_M,
	))
	var deck_y := surface_y + PortCoastTracer.FOUNDATION_TERRAIN_CLEARANCE_M
	var spawn := _layout_graph.spawn_local_position()
	## Keep XZ from spawn anchor; replace the player-body Y lift with deck height.
	return Vector3(spawn.x, deck_y, spawn.z)


func _add_staff_nameplate(npc: Node3D, text: String) -> void:
	if npc == null:
		return
	var label := Label3D.new()
	label.name = "StaffNameplate"
	label.text = text
	label.pixel_size = 0.012
	label.modulate = Color(0.98, 0.94, 0.78)
	label.outline_modulate = Color(0.05, 0.08, 0.10, 0.9)
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 2.25, 0.0)
	npc.add_child(label)


func _snap_staff_to_ground(staff: Array) -> void:
	if not is_inside_tree():
		return
	## Wait for quay/foundation StaticBodies from the visualizer.
	await get_tree().process_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state if get_world_3d() != null else null
	if space == null:
		return
	for node in staff:
		var npc := node as Node3D
		if npc == null or not is_instance_valid(npc):
			continue
		var origin := npc.global_position + Vector3(0.0, 8.0, 0.0)
		var query := PhysicsRayQueryParameters3D.create(
			origin,
			origin + Vector3(0.0, -40.0, 0.0),
		)
		query.collide_with_areas = false
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var ground: Vector3 = hit.get("position", npc.global_position)
		npc.global_position = Vector3(npc.global_position.x, ground.y, npc.global_position.z)


func _resolved_gizmo_layers() -> Dictionary:
	var layers := PortDebugGizmos.default_layers(show_site_gizmos)
	for layer_id in _gizmo_layer_overrides:
		if layer_id in PortDebugGizmos.LAYER_IDS:
			layers[layer_id] = bool(_gizmo_layer_overrides[layer_id])
	return layers


func _sync_site_gizmo_layers() -> void:
	var gizmos := get_node_or_null("PortDebugGizmos") as PortDebugGizmos
	if gizmos == null:
		return
	var layers := _resolved_gizmo_layers()
	for layer_id in PortDebugGizmos.LAYER_IDS:
		gizmos.set_layer_visible(layer_id, bool(layers.get(layer_id, false)))


func get_spawn_position() -> Vector3:
	if _layout_graph == null:
		return global_position
	return to_global(_layout_graph.spawn_local_position())


func layout_graph() -> PortLayoutGraph:
	return _layout_graph


func harbour_controller() -> HarbourController:
	return get_node_or_null("HarbourController") as HarbourController


func port_data() -> PortData:
	return _data


func _register_with_catalog() -> void:
	if not is_inside_tree():
		return
	var catalog := get_node_or_null("/root/PortCatalog")
	if catalog == null or _data == null:
		return
	var chart := _data.to_chart_dict()
	catalog.register_port(
		_data.port_id,
		_data.display_name,
		_data.world_position,
		get_spawn_position(),
		_data.commodity_export,
		_data.commodity_imports,
		_data.island_width,
		_data.plot_depth,
		_data.layout_seed,
		_data.population,
		_data.features,
		_data.rotation_y,
		_data.berth_count,
		_data.size,
		str(chart.get("region", "")),
		str(chart.get("max_ship_class_name", "")),
	)


func _own_subtree(node: Node, root: Node) -> void:
	node.owner = root
	for child in node.get_children():
		_own_subtree(child, root)
