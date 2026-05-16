@tool
class_name World
extends Node3D

## Main scene root. Generates port definitions from seed, expands them to PortData,
## eagerly loads the home port, and lazy-loads all others via ProximityLoader.

const PLAYER_SCENE := preload("res://scenes/islands/starting_island/player.tscn")

const LOAD_RADIUS : float = 350.0

const PORT_NAMES : Array[String] = [
	"Stonehaven", "Greywater", "Saltholm", "Ironharbour",
	"Westport",   "Millcove",  "Dunreach", "Coppergate",
]

@export var world_seed: int = 42:
	set(v): world_seed = v; if is_inside_tree(): _rebuild()


func _ready() -> void:
	call_deferred("_rebuild")


func _rebuild() -> void:
	for child in get_children():
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()

	_add_world_renderer()

	var defs := _generate_definitions()

	if Engine.is_editor_hint():
		_add_editor_preview(defs)
		var esc := get_tree().edited_scene_root
		if esc != null:
			for child in get_children():
				_own_subtree(child)
	else:
		_add_atmospheric_effects()
		_setup_ports(defs)
		call_deferred("_spawn_player")


func _add_world_renderer() -> void:
	var renderer  := WorldRenderer.new()
	renderer.name = "WorldRenderer"
	add_child(renderer)


func _add_atmospheric_effects() -> void:
	var fx  := AtmosphericEffects.new()
	fx.name = "AtmosphericEffects"
	add_child(fx)


func _add_editor_preview(defs: Array[PortDefinition]) -> void:
	for i in range(defs.size()):
		var def  := defs[i]
		var data := PortExpander.expand(def, world_seed)
		var plot  := PortPlot.new()
		plot.name = "Port_%s" % def.port_id
		plot.configure(data)
		add_child(plot)
		plot.position = def.world_position


func _setup_ports(defs: Array[PortDefinition]) -> void:
	var loader  := ProximityLoader.new()
	loader.name = "ProximityLoader"
	add_child(loader)

	var registry := get_node_or_null("/root/ContractRegistry")

	for i in range(defs.size()):
		var def  := defs[i]
		var data := PortExpander.expand(def, world_seed)

		if registry != null:
			registry.register_port(data.port_id, data.display_name, data.world_position)

		if i == 0:
			# Home port: always present, added directly so spawn position is available.
			var plot := PortPlot.new()
			plot.name = "HomePort"
			plot.configure(data)
			add_child(plot)
			plot.global_position = def.world_position
		else:
			var captured := data
			loader.register(
				def.world_position,
				func() -> Node3D:
					var plot := PortPlot.new()
					plot.configure(captured)
					return plot,
				LOAD_RADIUS,
			)


func _generate_definitions() -> Array[PortDefinition]:
	var defs: Array[PortDefinition] = []

	var home            := PortDefinition.new()
	home.port_id        = "port-home"
	home.display_name   = "Home Port"
	home.world_position = Vector3.ZERO
	home.size           = 1
	defs.append(home)

	var rng  := RandomNumberGenerator.new()
	rng.seed = world_seed

	var port_count := 4 + rng.randi() % 4   # 4–7 additional ports

	for i in range(port_count):
		var p           := PortDefinition.new()
		p.port_id       = "port-%d" % (i + 1)
		p.display_name  = PORT_NAMES[i % PORT_NAMES.size()]
		var angle       := (float(i) / float(port_count)) * TAU
		var radius      := 400.0 + float(rng.randi() % 400)
		p.world_position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		p.size           = rng.randi() % 5
		defs.append(p)

	return defs


func _spawn_player() -> void:
	# PortPlot._rebuild and PortFacilities._rebuild are both deferred.
	# Two frames is enough for that chain to settle before we query spawn_pos.
	await get_tree().process_frame
	await get_tree().process_frame

	var home      := get_node_or_null("HomePort") as PortPlot
	var spawn_pos := Vector3(0.0, 0.5, 0.0)
	if home != null:
		spawn_pos = home.get_spawn_position()

	var player      := PLAYER_SCENE.instantiate()
	player.position = spawn_pos
	add_child(player)


func _own_subtree(node: Node) -> void:
	var esc := get_tree().edited_scene_root
	if esc == null:
		return
	node.owner = esc
	for child in node.get_children():
		_own_subtree(child)
