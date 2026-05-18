class_name CargoPickup
extends StaticBody3D

## Physical world crate. Used by both Warehouse and CargoDeckComponent —
## the player always interacts with cargo through this same node type.

const PICKUP_GROUP        := "cargo_pickup"
const LAYER_CARGO_PICKUP  := 16

signal picked_up(item: CargoItem)

var cargo_item: CargoItem

@export_file("*.json") var mesh_path: String = "res://resources/data/meshes/props/crate_wooden.json"
@export var mesh_scale: float = 0.78
@export var box_size: Vector3 = Vector3(0.95, 0.95, 0.95)


func _ready() -> void:
	collision_layer = LAYER_CARGO_PICKUP
	collision_mask  = 0
	add_to_group(PICKUP_GROUP)
	_build()


func setup(item: CargoItem) -> void:
	cargo_item = item


## Called by PlayerCarryComponent. Returns the CargoItem and queues self for removal.
func pick_up() -> CargoItem:
	var item := cargo_item
	picked_up.emit(item)
	queue_free()
	return item


func _build() -> void:
	var scaled := box_size * mesh_scale

	var box          := BoxShape3D.new()
	box.size         = scaled
	var col          := CollisionShape3D.new()
	col.name         = "PickupCollision"
	col.shape        = box
	col.position     = Vector3.UP * (scaled.y * 0.5)
	add_child(col)

	var asm                  := ModelAssembler.new()
	asm.name                 = "PickupModel"
	asm.model_data_path      = mesh_path
	asm.absolute_scale       = mesh_scale
	asm.build_part_colliders = false
	asm.position             = Vector3.UP * (scaled.y * 0.5)
	add_child(asm)
