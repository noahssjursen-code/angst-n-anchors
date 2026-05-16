@tool
class_name PortPlot
extends Node3D

## Composition root: positions PortDock (water side) and PortFacilities (land side)
## as a matched pair. Drives both from port_size and plot dimensions.

const C_GROUND := Color(0.72, 0.68, 0.58)

const SHIP_CLASS_BY_SIZE: Dictionary = {
	0: ShipClass.Type.COASTAL_TRADER,
	1: ShipClass.Type.COASTAL_TRADER,
	2: ShipClass.Type.SHORT_SEA_COASTER,
	3: ShipClass.Type.HANDYSIZE_FEEDER,
	4: ShipClass.Type.DEEP_SEA_FREIGHTER,
}

@export var port_id: String = ""

@export var port_label: String = "Port":
	set(v): port_label = v; if is_inside_tree() and not _configuring: _rebuild()

@export var plot_width: float = 80.0:
	set(v): plot_width = v; if is_inside_tree() and not _configuring: _rebuild()

@export var plot_depth: float = 110.0:
	set(v): plot_depth = v; if is_inside_tree() and not _configuring: _rebuild()

@export var port_size: int = 1:
	set(v): port_size = v; if is_inside_tree() and not _configuring: _rebuild()

var _configuring:         bool       = false
var _berth_types_data:    Array[int] = []
var _has_fuel_point_data: bool       = true


func _ready() -> void:
	call_deferred("_rebuild")


func _rebuild() -> void:
	for child in get_children():
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()

	var hd         := plot_depth * 0.5
	var ship_class := SHIP_CLASS_BY_SIZE.get(clampi(port_size, 0, 4),
		ShipClass.Type.COASTAL_TRADER) as ShipClass.Type

	# Ground slab — full land area from dock face to back of plot.
	# Neither PortDock nor PortFacilities owns the ground; this node does.
	var gsize                := Vector3(plot_width, 0.4, plot_depth)
	var gbody                := StaticBody3D.new()
	gbody.name               = "Ground"
	gbody.position           = Vector3(0.0, -0.2, 0.0)
	var ground               := MeshInstance3D.new()
	ground.name              = "Mesh"
	var gmesh                := BoxMesh.new()
	gmesh.size               = gsize
	ground.mesh              = gmesh
	var gmat                 := StandardMaterial3D.new()
	gmat.albedo_color        = C_GROUND
	gmat.shading_mode        = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground.material_override = gmat
	gbody.add_child(ground)
	var gcol                 := CollisionShape3D.new()
	var gbox                 := BoxShape3D.new()
	gbox.size                = gsize
	gcol.shape               = gbox
	gbody.add_child(gcol)
	add_child(gbody)

	var dock              := PortDock.new()
	dock.name             = "PortDock"
	dock.dock_length      = plot_width
	dock.max_ship_class   = ship_class
	dock.berth_types      = _berth_types_data.duplicate()
	dock.has_fuel_point   = _has_fuel_point_data
	dock.position         = Vector3(0.0, 0.0, -hd)
	add_child(dock)

	var facilities            := PortFacilities.new()
	facilities.name           = "PortFacilities"
	facilities.port_size      = port_size
	facilities.plot_width     = plot_width
	facilities.plot_depth     = plot_depth - PortDock.INLAND_DEPTH
	facilities.position       = Vector3(0.0, 0.0, -hd + PortDock.INLAND_DEPTH)
	add_child(facilities)

	if not Engine.is_editor_hint():
		call_deferred("_build_npcs")

	if Engine.is_editor_hint():
		var esc := get_tree().edited_scene_root
		if esc != null:
			for child in get_children():
				_own_subtree(child, esc)


func _build_npcs() -> void:
	var facilities := get_node_or_null("PortFacilities") as PortFacilities
	if facilities == null:
		return

	var hm          := HarbourMasterNpc.new()
	hm.name         = "HarbourMasterNpc"
	hm.port_id      = port_id
	hm.position     = facilities.get_harbour_master_position() + Vector3(0.0, 0.0, -4.5)
	add_child(hm)

	if not port_id.is_empty():
		call_deferred("_register_with_registry")


func _register_with_registry() -> void:
	var registry  := get_node_or_null("/root/ContractRegistry")
	if registry == null:
		return
	var facilities := get_node_or_null("PortFacilities") as PortFacilities
	var spawn_pos  := facilities.get_spawn_position() if facilities != null else global_position
	registry.register_port(port_id, port_label, global_position, null, spawn_pos)


## Wire a PortData record into this plot. Triggers one rebuild.
## Call before or after add_child — both are safe.
func configure(data: PortData) -> void:
	_configuring             = true
	port_id                  = data.port_id
	port_label               = data.display_name
	port_size                = data.size
	plot_width               = data.dock_length
	_berth_types_data        = data.berth_types.duplicate()
	_has_fuel_point_data     = data.has_fuel_point
	_configuring             = false
	if is_inside_tree():
		_rebuild()


func get_spawn_position() -> Vector3:
	var dock := get_node_or_null("PortDock") as PortDock
	return dock.get_spawn_position() if dock != null else global_position


func _own_subtree(node: Node, esc: Node) -> void:
	node.owner = esc
	for child in node.get_children():
		_own_subtree(child, esc)
