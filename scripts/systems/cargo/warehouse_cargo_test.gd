class_name WarehouseCargoTest
extends Node3D

const LAYER_WORLD := 1
const CRATE_GROUP := "warehouse_pickup_crate"
const MESH_TRANSFORMER_SCRIPT := preload("res://scripts/systems/mesh_transformer.gd")

@export var warehouse_root_path: NodePath
@export var ship_spawner_path: NodePath
@export var contract_zone_path: NodePath
@export var pickup_range: float = 4.2
@export var deposit_range: float = 6.0
@export var crate_mass_kg: float = 400.0
@export_file("*.json") var crate_mesh_path: String = "res://resources/data/meshes/crate_wooden.json"
@export var crate_scale: float = 0.78
@export var crate_color: Color = Color(0.56, 0.43, 0.30)
@export var crate_positions_local: Array[Vector3] = []
@export var contract_demo_crate_count: int = 8
@export var contract_active_demo: bool = true
@export var carry_visual_scale: float = 0.46
@export var carry_visual_offset_local: Vector3 = Vector3(0.38, -0.44, -1.15)

var _carried_units: int = 0
var _carried_cargo_id: String = ""
var _ui_layer: CanvasLayer
var _prompt_label: Label
var _carried_visual: Node3D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_ensure_ui()
	call_deferred("refresh_demo_contract")


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _prompt_label == null:
		return
	_prompt_label.text = _status_text()
	_prompt_label.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not event.is_action_pressed("interact"):
		return

	if _carried_units > 0:
		if _try_deposit_to_ship():
			get_viewport().set_input_as_handled()
		return
	if _try_pickup_crate():
		get_viewport().set_input_as_handled()


func _status_text() -> String:
	var remaining := _remaining_crate_count()
	var carrying := "yes" if _carried_units > 0 else "no"
	var contract_state := "active" if contract_active_demo else "inactive"
	return (
		"Contract demo (" + contract_state + ") | crates left: "
		+ str(remaining)
		+ " | carrying: "
		+ carrying
		+ " | E = pickup / load to ship deck"
	)


func _spawn_starting_crates() -> void:
	var warehouse := _warehouse_root()
	if warehouse == null:
		push_warning("WarehouseCargoTest: warehouse root not found")
		return

	if not contract_active_demo:
		return

	var zone := _contract_zone()
	if zone != null and zone.has_method("get_capacity_units"):
		var cap := int(zone.call("get_capacity_units"))
		var count := mini(maxi(contract_demo_crate_count, 0), cap)
		for i in range(count):
			var local_slot := warehouse.to_local(zone.call("get_world_slot_position", i, 0.02))
			warehouse.add_child(_make_crate_body(local_slot))
		return

	var points := crate_positions_local
	if points.is_empty():
		points = _default_crate_positions()

	for p in points:
		warehouse.add_child(_make_crate_body(p))


func refresh_demo_contract() -> void:
	if Engine.is_editor_hint():
		return
	_clear_spawned_crates()
	_spawn_starting_crates()


func _clear_spawned_crates() -> void:
	var warehouse := _warehouse_root()
	if warehouse == null:
		return
	for node in warehouse.get_children():
		if node is StaticBody3D and node.is_in_group(CRATE_GROUP):
			node.queue_free()
	_carried_units = 0
	_carried_cargo_id = ""
	_clear_carried_visual()


func _make_crate_body(local_pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "WarehouseCrate"
	body.position = local_pos
	body.add_to_group(CRATE_GROUP)
	body.set_meta("cargo_id", "warehouse_crate")
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0

	var shape := CollisionShape3D.new()
	shape.name = "CrateCollision"
	var box := BoxShape3D.new()
	box.size = Vector3(0.95, 0.95, 0.95) * crate_scale
	shape.shape = box
	shape.position = Vector3(0.0, box.size.y * 0.5, 0.0)
	body.add_child(shape)

	var visual_y := box.size.y * 0.5
	if _json_root_has_parts(crate_mesh_path):
		var assembler := ModelAssembler.new()
		assembler.name = "CrateModel"
		assembler.model_data_path = crate_mesh_path
		assembler.absolute_scale = crate_scale
		assembler.build_part_colliders = false
		assembler.position = Vector3(0.0, visual_y, 0.0)
		body.add_child(assembler)
	else:
		var mesh_node := Node3D.new()
		mesh_node.name = "CrateMesh"
		mesh_node.set_script(MESH_TRANSFORMER_SCRIPT)
		mesh_node.set("mesh_data_path", crate_mesh_path)
		mesh_node.set("absolute_scale", crate_scale)
		mesh_node.set("mesh_color", crate_color)
		mesh_node.set("create_collision", false)
		mesh_node.position = Vector3(0.0, visual_y, 0.0)
		body.add_child(mesh_node)

	return body


func _default_crate_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var x0 := -2.4
	var z0 := -4.8
	var dx := 1.65
	var dz := 1.65
	for row in range(3):
		for col in range(4):
			out.append(Vector3(x0 + float(col) * dx, 0.0, z0 + float(row) * dz))
	return out


func _try_pickup_crate() -> bool:
	if _carried_units > 0:
		return false
	var player := _nearest_player()
	if player == null:
		return false

	var hit := _forward_raycast_from_player(player, pickup_range)
	if hit.is_empty():
		return false

	var collider := hit.get("collider") as Node
	var crate := _resolve_crate_body(collider)
	if crate == null:
		return false

	_carried_cargo_id = str(crate.get_meta("cargo_id", "warehouse_crate"))
	crate.queue_free()
	_carried_units = 1
	_spawn_carried_visual(player)
	return true


func _try_deposit_to_ship() -> bool:
	var player := _nearest_player()
	if player == null:
		return false
	var spawner := get_node_or_null(ship_spawner_path) as ShipSpawner
	if (
		spawner == null
		or spawner.current_ship == null
		or not is_instance_valid(spawner.current_ship)
	):
		return false
	if not spawner.current_ship.has_method("get_cargo_decks"):
		return false

	var decks: Array = spawner.current_ship.call("get_cargo_decks")
	var best_deck: Node = null
	var best_drop := Vector3.ZERO
	var best_dist := INF
	for d in decks:
		var deck := d as Node
		if deck == null:
			continue
		if not deck.has_method("get_available_units"):
			continue
		if int(deck.call("get_available_units")) <= 0:
			continue
		if not deck.has_method("get_nearest_free_slot_world_position"):
			continue
		var drop: Vector3 = deck.call(
			"get_nearest_free_slot_world_position",
			player.global_position,
		)
		if drop == Vector3.INF:
			continue
		var dist := drop.distance_to(player.global_position)
		if dist < best_dist and dist <= deposit_range:
			best_dist = dist
			best_deck = deck
			best_drop = drop

	if best_deck == null:
		return false

	var ticket: int = best_deck.call(
		"add_cargo",
		_carried_cargo_id,
		1,
		crate_mass_kg,
		best_drop,
	)
	if ticket <= 0:
		return false

	_carried_units = 0
	_carried_cargo_id = ""
	_clear_carried_visual()
	return true


func _resolve_crate_body(hit_node: Node) -> StaticBody3D:
	var n := hit_node
	while n != null:
		if n is StaticBody3D and n.is_in_group(CRATE_GROUP):
			return n as StaticBody3D
		n = n.get_parent()
	return null


func _warehouse_root() -> Node3D:
	var n := get_node_or_null(warehouse_root_path)
	return n as Node3D


func _contract_zone() -> Node:
	return get_node_or_null(contract_zone_path)


func _remaining_crate_count() -> int:
	var warehouse := _warehouse_root()
	if warehouse == null:
		return 0
	var count := 0
	for node in warehouse.get_children():
		if node is StaticBody3D and node.is_in_group(CRATE_GROUP):
			count += 1
	return count


func _nearest_player() -> CharacterBody3D:
	var best: CharacterBody3D = null
	var best_d2 := INF
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as CharacterBody3D
		if body == null:
			continue
		var d2 := global_position.distance_squared_to(body.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = body
	return best


func _forward_raycast_from_player(player: CharacterBody3D, range_m: float) -> Dictionary:
	var camera := player.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return {}
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * range_m
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _ensure_ui() -> void:
	if _ui_layer != null and is_instance_valid(_ui_layer):
		return
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "WarehouseCargoTestUI"
	add_child(_ui_layer)

	_prompt_label = Label.new()
	_prompt_label.name = "Prompt"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 18)
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.offset_left = -360.0
	_prompt_label.offset_right = 360.0
	_prompt_label.offset_top = -120.0
	_prompt_label.offset_bottom = -86.0
	_prompt_label.visible = true
	_ui_layer.add_child(_prompt_label)


func _spawn_carried_visual(player: CharacterBody3D) -> void:
	_clear_carried_visual()
	var anchor := player.get_node_or_null("Camera3D") as Node3D
	if anchor == null:
		anchor = player
	_carried_visual = Node3D.new()
	_carried_visual.name = "CarriedCrateVisual"
	anchor.add_child(_carried_visual)
	_carried_visual.position = carry_visual_offset_local

	if _json_root_has_parts(crate_mesh_path):
		var assembler := ModelAssembler.new()
		assembler.name = "CarriedCrateModel"
		assembler.model_data_path = crate_mesh_path
		assembler.absolute_scale = carry_visual_scale
		assembler.build_part_colliders = false
		_carried_visual.add_child(assembler)
	else:
		var mesh_node := Node3D.new()
		mesh_node.name = "CarriedCrateMesh"
		mesh_node.set_script(MESH_TRANSFORMER_SCRIPT)
		mesh_node.set("mesh_data_path", crate_mesh_path)
		mesh_node.set("absolute_scale", carry_visual_scale)
		mesh_node.set("mesh_color", crate_color)
		mesh_node.set("create_collision", false)
		_carried_visual.add_child(mesh_node)


func _clear_carried_visual() -> void:
	if _carried_visual != null and is_instance_valid(_carried_visual):
		_carried_visual.queue_free()
	_carried_visual = null


func _json_root_has_parts(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return false
	var data = json.get_data()
	return typeof(data) == TYPE_DICTIONARY and data.has("parts")
