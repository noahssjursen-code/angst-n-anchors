@tool
class_name PortPlot
extends Node3D

## Runtime composition root for the visualize-first port graph.
## Stamps module footprints, rough equipment silhouettes, and scale hulls.

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
	call_deferred("_rebuild")


func configure(data: PortData, _legacy_brick_mode: bool = true) -> void:
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
	for child in get_children():
		child.free()
	if _layout_graph == null:
		return
	var visualizer := PortLayoutGraphVisualizer.new()
	visualizer.name = "PortLayoutGraph"
	visualizer.configure(_layout_graph)
	add_child(visualizer)

	## Always stamp gizmos so layers can be toggled without a full rebuild.
	var gizmos := PortDebugGizmos.new()
	gizmos.name = "PortDebugGizmos"
	gizmos.configure(_layout_graph, _resolved_gizmo_layers())
	add_child(gizmos)

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
	if is_inside_tree():
		_register_with_catalog()
	if Engine.is_editor_hint() and is_inside_tree():
		var root := get_tree().edited_scene_root
		if root != null:
			for child in get_children():
				_own_subtree(child, root)


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


func _register_with_catalog() -> void:
	if not is_inside_tree():
		return
	var catalog := get_node_or_null("/root/PortCatalog")
	if catalog == null or _data == null:
		return
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
	)


func _own_subtree(node: Node, root: Node) -> void:
	node.owner = root
	for child in node.get_children():
		_own_subtree(child, root)
