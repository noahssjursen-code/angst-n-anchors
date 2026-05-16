@tool
class_name DeliveryNpc
extends NpcBase

## Destination-side NPC. Joins DELIVERY_GROUP so PlayerCarryComponent delivers
## to it using the same mechanic as any other delivery zone.

const DELIVERY_GROUP  := "cargo_delivery_zone"
const FLAT_CAP_PATH   := "res://resources/data/meshes/hat_flat_cap.json"

signal gold_earned(amount: int)

@export var port_id: String = ""

var _reward_layer: CanvasLayer
var _reward_label: Label
var _reward_timer: float = 0.0


func _ready() -> void:
	clothing_color = Color(0.22, 0.58, 0.32)
	trousers_color = Color(0.14, 0.32, 0.18)
	super._ready()
	if not Engine.is_editor_hint():
		add_to_group(DELIVERY_GROUP)
		call_deferred("_build_ui")
	else:
		call_deferred("_add_hat")


func _add_hat() -> void:
	add_overlay("hat", FLAT_CAP_PATH)


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
	_reward_label.text    = "+%d ℳ" % amount
	_reward_label.visible = true
	_reward_timer         = 2.5


func _build_ui() -> void:
	add_overlay("hat", FLAT_CAP_PATH)

	_reward_layer      = CanvasLayer.new()
	_reward_layer.name = "DeliveryNpcLayer"
	add_child(_reward_layer)

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
	_reward_layer.add_child(_reward_label)


func _registry() -> Node:
	return get_node_or_null("/root/ContractRegistry")
