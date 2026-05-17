class_name PlayerCarryComponent
extends Node

## Attach as a child of the player CharacterBody3D.
## Manages pickup, carry state, deposit to ship deck, and delivery.
## No knowledge of warehouses, specific ships, or ports — all via groups.

const PICKUP_GROUP     := "cargo_pickup"
const DECK_GROUP       := "cargo_deck"
const DELIVERY_GROUP   := "cargo_delivery_zone"
const WAREHOUSE_GROUP  := "warehouse"

@export var pickup_range: float  = 4.0
@export var deposit_range: float = 5.0

@export_group("Carry visual")
@export_file("*.json") var carry_mesh_path: String = "res://resources/data/meshes/props/crate_wooden.json"
@export var carry_scale: float   = 0.46
@export var carry_offset: Vector3 = Vector3(0.38, -0.44, -1.15)

var _carried: CargoItem = null
var _player: CharacterBody3D
var _camera: Camera3D
var _carry_visual: Node3D
var _ui_layer: CanvasLayer
var _prompt: Label


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if _player == null:
		push_warning("PlayerCarryComponent: must be a child of CharacterBody3D")
		return
	_camera = _player.get_node_or_null("Camera3D") as Camera3D
	_ensure_ui()


func _process(_delta: float) -> void:
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("load_ship"):
		if _try_bulk_load():
			get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("interact"):
		return
	if _carried != null:
		if _try_deliver() or _try_deposit():
			get_viewport().set_input_as_handled()
	else:
		if _try_pickup():
			get_viewport().set_input_as_handled()


func is_carrying() -> bool:
	return _carried != null


func get_carried() -> CargoItem:
	return _carried


# ── Interactions ──────────────────────────────────────────────────────────────

func _try_pickup() -> bool:
	var pickup := _find_looked_at_pickup()
	if pickup == null:
		return false
	_carried = pickup.pick_up()
	_spawn_carry_visual()
	return true


func _try_deposit() -> bool:
	var deck := _find_nearest_deck()
	if deck == null:
		return false
	var drop: Vector3 = deck.call("get_nearest_free_slot_world_position", _player.global_position)
	var ticket: int   = deck.call("add_cargo", _carried, drop)
	if ticket <= 0:
		return false
	_carried = null
	_clear_carry_visual()
	return true


func _try_deliver() -> bool:
	var zone := _find_nearest_delivery_zone()
	if zone == null:
		return false
	if not bool(zone.call("deliver", _carried)):
		return false
	_carried = null
	_clear_carry_visual()
	return true


func _try_bulk_load() -> bool:
	var decks: Array[Node] = []
	for n in get_tree().get_nodes_in_group(DECK_GROUP):
		if n.has_method("add_cargo"):
			decks.append(n)
	if decks.is_empty():
		return false
	var loaded := 0
	for n in get_tree().get_nodes_in_group(WAREHOUSE_GROUP):
		var wh := n as Warehouse
		if wh == null or wh.item_count() == 0:
			continue
		var overflow: Array[CargoItem] = []
		for item in wh.take_all():
			var placed := false
			for deck in decks:
				if int(deck.call("get_available_units")) > 0 and int(deck.call("add_cargo", item, Vector3.INF)) > 0:
					loaded += 1
					placed  = true
					break
			if not placed:
				overflow.append(item)
		if not overflow.is_empty():
			wh.set_inventory(overflow)
	return loaded > 0


# ── Discovery ─────────────────────────────────────────────────────────────────

func _find_looked_at_pickup() -> CargoPickup:
	if _camera == null:
		return null
	var from  := _camera.global_position
	var to    := from - _camera.global_transform.basis.z * pickup_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude            = [_player.get_rid()]
	query.collide_with_bodies = true
	query.collide_with_areas  = false
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return _resolve_pickup(hit.get("collider") as Node)


func _resolve_pickup(node: Node) -> CargoPickup:
	var n := node
	while n != null:
		if n is CargoPickup:
			return n as CargoPickup
		n = n.get_parent()
	return null


func _find_nearest_deck() -> Node:
	var best: Node   = null
	var best_d2: float = deposit_range * deposit_range
	for n in get_tree().get_nodes_in_group(DECK_GROUP):
		if not n.has_method("add_cargo") or not n.has_method("get_available_units"):
			continue
		if int(n.call("get_available_units")) <= 0:
			continue
		var d2 := _player.global_position.distance_squared_to((n as Node3D).global_position)
		if d2 < best_d2:
			best_d2 = d2
			best    = n
	return best


func _find_nearest_delivery_zone() -> Node:
	var best: Node   = null
	var best_d2: float = deposit_range * deposit_range
	for n in get_tree().get_nodes_in_group(DELIVERY_GROUP):
		if not n.has_method("accepts") or not bool(n.call("accepts", _carried)):
			continue
		var d2 := _player.global_position.distance_squared_to((n as Node3D).global_position)
		if d2 < best_d2:
			best_d2 = d2
			best    = n
	return best


# ── Visual ────────────────────────────────────────────────────────────────────

func _spawn_carry_visual() -> void:
	_clear_carry_visual()
	if _camera == null:
		return
	_carry_visual          = Node3D.new()
	_carry_visual.name     = "CarryVisual"
	_camera.add_child(_carry_visual)
	_carry_visual.position = carry_offset

	var asm                  := ModelAssembler.new()
	asm.name                 = "CarryModel"
	asm.model_data_path      = carry_mesh_path
	asm.absolute_scale       = carry_scale
	asm.build_part_colliders = false
	_carry_visual.add_child(asm)


func _clear_carry_visual() -> void:
	if _carry_visual != null and is_instance_valid(_carry_visual):
		_carry_visual.queue_free()
	_carry_visual = null


# ── Prompt ────────────────────────────────────────────────────────────────────

func _update_prompt() -> void:
	if _prompt == null:
		return
	if _carried != null:
		var deck := _find_nearest_deck()
		if deck != null:
			_prompt.text    = "Press E to load onto ship"
			_prompt.visible = true
			return
		var zone := _find_nearest_delivery_zone()
		if zone != null:
			_prompt.text    = "Press E to deliver " + _carried.display_name
			_prompt.visible = true
			return
		_prompt.visible = false
		return

	var pickup := _find_looked_at_pickup()
	if pickup != null and pickup.cargo_item != null:
		_prompt.text    = "Press E to pick up " + pickup.cargo_item.display_name
		_prompt.visible = true
	else:
		_prompt.visible = false


func _ensure_ui() -> void:
	_ui_layer      = CanvasLayer.new()
	_ui_layer.name = "CarryPromptLayer"
	add_child(_ui_layer)

	_prompt                    = Label.new()
	_prompt.name               = "CarryPrompt"
	_prompt.visible            = false
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 20)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left        = -240.0
	_prompt.offset_right       = 240.0
	_prompt.offset_top         = -148.0
	_prompt.offset_bottom      = -108.0
	_ui_layer.add_child(_prompt)
