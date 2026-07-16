class_name BulkMaterialDrop
extends Node3D

## Short-lived bulk chunk — falls when the bucket closes; later targets cargo holds.

const GRAVITY := 9.8
const MAX_LIFETIME_S := 6.0

var _velocity := Vector3.ZERO
var _age := 0.0
var _visual: Node3D


static func spawn(
		parent: Node,
		commodity_id: String,
		world_pos: Vector3,
		initial_velocity: Vector3,
		volume: float = 1.0,
		visual_scale: float = 1.0,
) -> BulkMaterialDrop:
	var drop := BulkMaterialDrop.new()
	drop.name = "BulkDrop"
	parent.add_child(drop)
	drop.global_position = world_pos
	drop._velocity = initial_velocity
	var lump_size := Vector3(1.6, 1.0, 1.4) * clampf(volume, 0.35, 1.0) * maxf(visual_scale, 0.01)
	drop._visual = OreMoundBuilder.build_mound(commodity_id, lump_size, hash(world_pos))
	drop.add_child(drop._visual)
	return drop


func _physics_process(delta: float) -> void:
	_velocity.y -= GRAVITY * delta
	global_position += _velocity * delta
	_age += delta
	if _age >= MAX_LIFETIME_S or global_position.y < WaveSurface.WATER_LEVEL - 6.0:
		queue_free()
