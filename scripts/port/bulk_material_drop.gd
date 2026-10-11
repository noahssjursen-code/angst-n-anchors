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
var _source_ship: BoatBody


static func spawn(
		parent: Node,
		lot_in: BulkCargoLot,
		world_pos: Vector3,
		initial_velocity: Vector3,
		bucket_capacity_t: float = BulkCargoRules.BASE_BUCKET_CAPACITY_T,
		visual_scale: float = 1.0,
		source_ship: BoatBody = null,
) -> BulkMaterialDrop:
	var drop := BulkMaterialDrop.new()
	drop.name = "BulkDrop"
	drop.lot = lot_in.duplicate_lot() if lot_in != null else BulkCargoLot.empty()
	drop._bucket_capacity_t = maxf(bucket_capacity_t, BulkCargoLot.TONNES_EPS)
	drop._velocity = initial_velocity
	drop._source_ship = source_ship
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
	if _try_land_on_mound():
		return
	if _age >= MAX_LIFETIME_S or global_position.y < WaveSurface.WATER_LEVEL - 6.0:
		spilled.emit(lot.duplicate_lot(), global_position)
		queue_free()


func _try_land_in_hold() -> bool:
	var hold := BulkHoldComponent.find_accepting_hold_at(global_position, lot)
	if hold == null:
		return false
	var ship_node := hold.get_parent()
	while ship_node != null and not ship_node is BoatBody:
		ship_node = ship_node.get_parent()
	if not lot.consignment_id.is_empty() and (not ship_node is BoatBody or FreightService.bulk_contract(lot, ship_node as BoatBody).is_empty()):
		return false
	var offered_t := lot.tonnes_t
	var commodity := lot.commodity_id
	var shipment := lot.consignment_id
	var overflow := hold.accept_lot(lot)
	var accepted_t := maxf(offered_t - overflow.tonnes_t, 0.0)
	if accepted_t > BulkCargoLot.TONNES_EPS:
		var received := BulkCargoLot.create(commodity, accepted_t, shipment)
		if ship_node is BoatBody and not shipment.is_empty():
			FreightService.record_bulk_loaded(received, ship_node as BoatBody)
		landed.emit(received, hold)
	lot = overflow
	_rebuild_visual(BulkCargoRules.visual_scale_for_lot(lot, _bucket_capacity_t))
	if lot.is_empty():
		queue_free()
		return true
	_velocity *= 0.35
	return false


func _try_land_on_mound() -> bool:
	for node in get_tree().get_nodes_in_group("ore_mound"):
		if node is not OreMound: continue
		var mound := node as OreMound
		if mound.commodity_id != lot.commodity_id: continue
		var local := mound.to_local(global_position)
		if absf(local.x) > mound._size.x * 0.5 or absf(local.z) > mound._size.z * 0.5: continue
		if local.y > mound._size.y * 0.42 or local.y < -1.0: continue
		var port_node := mound.get_parent()
		while port_node != null and not port_node is PortPlot:
			port_node = port_node.get_parent()
		if port_node is PortPlot and is_instance_valid(_source_ship):
			FreightService.record_bulk_delivered(lot, (port_node as PortPlot).port_id, _source_ship)
		lot = BulkCargoLot.empty()
		queue_free()
		return true
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
