@tool
class_name PortShowcase
extends Node3D

## Editor-visible, directly runnable port fixture. It goes through PortExpander
## and PortPlot so changes here match runtime composition.

@export var rebuild: bool = false:
	set(value):
		rebuild = false
		if value and is_inside_tree():
			_rebuild()

@export_range(0, 4) var port_size: int = 2:
	set(value):
		port_size = value
		if is_inside_tree():
			_rebuild()

@export var has_lighthouse := true:
	set(value):
		has_lighthouse = value
		if is_inside_tree():
			_rebuild()

@export var has_fog_horn := true:
	set(value):
		has_fog_horn = value
		if is_inside_tree():
			_rebuild()

var _orbit_angle := -0.82


func _ready() -> void:
	_rebuild()


func _exit_tree() -> void:
	# Standalone showcase owns the static prototype cache for its generated dock.
	if not Engine.is_editor_hint():
		ModelCache.clear()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var camera := get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return
	_orbit_angle += delta * 0.035
	var target := Vector3(0.0, 7.0, 4.0)
	camera.position = target + Vector3(
		sin(_orbit_angle) * 105.0,
		58.0,
		cos(_orbit_angle) * 105.0,
	)
	camera.look_at(target, Vector3.UP)


func _rebuild() -> void:
	var existing := get_node_or_null("GeneratedPort")
	if existing != null:
		existing.free()
	var generated := Node3D.new()
	generated.name = "GeneratedPort"
	add_child(generated)

	var definition := PortDefinition.new()
	definition.port_id = "port-showcase"
	definition.display_name = "SHOWCASE"
	definition.size = port_size
	definition.has_lighthouse = has_lighthouse
	definition.has_fog_horn = has_fog_horn
	var data := PortExpander.expand(definition, 73191)
	data.has_lighthouse = has_lighthouse
	data.has_fog_horn = has_fog_horn

	var plot := PortPlot.new()
	plot.name = "PortPlot"
	plot.configure(data)
	generated.add_child(plot)

	var water := MeshInstance3D.new()
	water.name = "WaterPlane"
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2(420.0, 420.0)
	water.mesh = water_mesh
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(0.08, 0.22, 0.28)
	water_material.roughness = 0.26
	water_material.metallic = 0.18
	water.material_override = water_material
	water.position.y = -0.32
	generated.add_child(water)

	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		_own_subtree(generated, get_tree().edited_scene_root)


func _own_subtree(node: Node, scene_owner: Node) -> void:
	node.owner = scene_owner
	for child in node.get_children():
		_own_subtree(child, scene_owner)
