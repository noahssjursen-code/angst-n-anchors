class_name BulkMaterialDrop
extends Node3D

## Falling bulk payload. Carries a `BulkCargoLot` and deposits into ship holds on landing.

signal landed(lot: BulkCargoLot, hold: BulkHoldComponent)
signal spilled(lot: BulkCargoLot, world_position: Vector3)

const GRAVITY := 9.8
const MAX_LIFETIME_S := 8.0

var lot := BulkCargoLot.empty()
var _velocity := Vector3.ZERO
var _age := 0.0
var _visual: Node3D
var _bucket_capacity_t: float = BulkCargoRules.BASE_BUCKET_CAPACITY_T


static func spawn(
		parent: Node,
		lot_in: BulkCargoLot,
		world_pos: Vector3,
		initial_velocity: Vector3,
		bucket_capacity_t: float = BulkCargoRules.BASE_BUCKET_CAPACITY_T,
		visual_scale: float = 1.0,
) -> BulkMaterialDrop:
	var drop := BulkMaterialDrop.new()
	drop.name = "BulkDrop"
	drop.lot = lot_in.duplicate_lot() if lot_in != null else BulkCargoLot.empty()
	drop._bucket_capacity_t = maxf(bucket_capacity_t, BulkCargoLot.TONNES_EPS)
	drop._velocity = initial_velocity
	parent.add_child(drop)
	drop.global_position = world_pos
	drop._rebuild_visual(visual_scale)
	return drop


func _physics_process(delta: float) -> void:
	if lot.is_empty():
		queue_free()
		return
	_velocity.y -= GRAVITY * delta
	global_position += _velocity * delta
	_age += delta
	if _try_land_in_hold():
		return
	if _age >= MAX_LIFETIME_S or global_position.y < WaveSurface.WATER_LEVEL - 6.0:
		spilled.emit(lot.duplicate_lot(), global_position)
		queue_free()


func _try_land_in_hold() -> bool:
	var hold := BulkHoldComponent.find_accepting_hold_at(global_position, lot)
	if hold == null:
		return false
	var offered_t := lot.tonnes_t
	var commodity := lot.commodity_id
	var overflow := hold.accept_lot(lot)
	var accepted_t := maxf(offered_t - overflow.tonnes_t, 0.0)
	if accepted_t > BulkCargoLot.TONNES_EPS:
		landed.emit(BulkCargoLot.create(commodity, accepted_t), hold)
	lot = overflow
	_rebuild_visual(BulkCargoRules.visual_scale_for_lot(lot, _bucket_capacity_t))
	if lot.is_empty():
		queue_free()
		return true
	_velocity *= 0.35
	return false


func _rebuild_visual(visual_scale: float = 1.0) -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
		_visual = null
	if lot.is_empty():
		return
	var lump_scale := BulkCargoRules.visual_scale_for_lot(lot, _bucket_capacity_t) * maxf(visual_scale, 0.01)
	var lump_size := Vector3(1.6, 1.0, 1.4) * lump_scale
	_visual = OreMoundBuilder.build_mound(lot.commodity_id, lump_size, hash(global_position))
	add_child(_visual)
