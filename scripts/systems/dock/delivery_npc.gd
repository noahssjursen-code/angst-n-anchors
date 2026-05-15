class_name DeliveryNpc
extends StaticBody3D

## Destination-side NPC. Joins DELIVERY_GROUP so PlayerCarryComponent delivers
## to it using the same mechanic as any other delivery zone — no special casing.

const DELIVERY_GROUP := "cargo_delivery_zone"
const LAYER_WORLD    := 1

signal gold_earned(amount: int)

@export var port_id: String = ""
@export var interact_range: float = 4.0
@export var npc_color: Color = Color(0.22, 0.58, 0.32)

var _prompt_layer: CanvasLayer
var _reward_label: Label
var _reward_timer: float = 0.0


func _ready() -> void:
	_build_body()
	if not Engine.is_editor_hint():
		add_to_group(DELIVERY_GROUP)
		_build_ui()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _reward_timer > 0.0:
		_reward_timer -= delta
		if _reward_timer <= 0.0 and _reward_label != null:
			_reward_label.visible = false


# ── DeliveryZone interface (used by PlayerCarryComponent) ─────────────────────

func accepts(item: CargoItem) -> bool:
	if item == null or port_id.is_empty():
		return false
	return item.destination_port_id == port_id


func deliver(item: CargoItem) -> bool:
	if not accepts(item):
		return false
	var registry := _registry()
	var reward   := 0
	if registry != null:
		reward = int(registry.deliver_cargo(item))
	else:
		reward = item.value_gold
	gold_earned.emit(reward)
	_flash_reward(reward)
	return true


# ── Visuals ───────────────────────────────────────────────────────────────────

func _flash_reward(amount: int) -> void:
	if _reward_label == null:
		return
	_reward_label.text    = "+%d gold" % amount
	_reward_label.visible = true
	_reward_timer         = 2.5


func _build_body() -> void:
	collision_layer = LAYER_WORLD
	collision_mask  = 0

	var shape      := BoxShape3D.new()
	shape.size     = Vector3(0.7, 1.8, 0.7)
	var col        := CollisionShape3D.new()
	col.name       = "Body"
	col.shape      = shape
	col.position   = Vector3.UP * 0.9
	add_child(col)

	var body       := MeshBuilder.box(shape.size, npc_color, 0.6, 0.0)
	body.name      = "NpcVisual"
	body.position  = Vector3.UP * 0.9
	add_child(body)

	var hat        := MeshBuilder.box(Vector3(0.75, 0.12, 0.75), npc_color.lightened(0.15), 0.5, 0.0)
	hat.name       = "NpcHat"
	hat.position   = Vector3.UP * 1.86
	add_child(hat)


func _build_ui() -> void:
	_prompt_layer      = CanvasLayer.new()
	_prompt_layer.name = "DeliveryNpcLayer"
	add_child(_prompt_layer)

	_reward_label                      = Label.new()
	_reward_label.visible              = false
	_reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reward_label.add_theme_font_size_override("font_size", 24)
	_reward_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_reward_label.offset_left   = -180.0
	_reward_label.offset_right  =  180.0
	_reward_label.offset_top    = -200.0
	_reward_label.offset_bottom = -160.0
	_reward_label.modulate      = Color(1.0, 0.88, 0.2)
	_prompt_layer.add_child(_reward_label)


func _nearest_player() -> CharacterBody3D:
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as CharacterBody3D
		if body != null and global_position.distance_to(body.global_position) <= interact_range:
			return body
	return null


func _registry() -> Node:
	return get_node_or_null("/root/ContractRegistry")
