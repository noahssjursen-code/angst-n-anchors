@tool
class_name CatchHoldComponent
extends Node3D

## Insulated fish hold. Catch inventory is data; this node renders coarse fill stages.

signal fill_changed(state: CatchHoldState)

@export var hold_id: String = "catch_hold"
@export var capacity_kg: float = 4000.0

var state := CatchHoldState.new()
var _fill_root: Node3D
var _boat: BoatBody
var _pump_connection: Node3D
var _hose_drop: Node3D


func _ready() -> void:
	_boat = _find_boat()
	state.hold_id = hold_id
	state.capacity_kg = maxf(capacity_kg, 0.0)
	if not state.changed.is_connected(_on_state_changed):
		state.changed.connect(_on_state_changed)
	_build_visual()
	_sync_payload_mass()


func configure(id_in: String, capacity_kg_in: float) -> void:
	hold_id = id_in.strip_edges()
	if hold_id.is_empty():
		hold_id = "catch_hold"
	capacity_kg = maxf(capacity_kg_in, 0.0)
	state.hold_id = hold_id
	state.capacity_kg = capacity_kg


func get_state() -> CatchHoldState:
	return state


func get_pump_connection_world() -> Vector3:
	if _pump_connection != null and is_instance_valid(_pump_connection):
		return _pump_connection.global_position
	return global_position


func get_hose_drop_world() -> Vector3:
	if _hose_drop != null and is_instance_valid(_hose_drop):
		return _hose_drop.global_position
	return global_position


func apply_state(data: Dictionary) -> void:
	state = CatchHoldState.from_dict(data)
	state.hold_id = hold_id
	state.capacity_kg = capacity_kg
	if not state.changed.is_connected(_on_state_changed):
		state.changed.connect(_on_state_changed)
	_on_state_changed(state)


func accept_lot(lot: CatchLot) -> CatchLot:
	var before := state.total_mass_kg()
	var overflow := state.accept_lot(lot)
	if not is_equal_approx(before, state.total_mass_kg()):
		fill_changed.emit(state)
	return overflow


func withdraw_oldest(max_mass_kg: float) -> Array[CatchLot]:
	var before := state.total_mass_kg()
	var lots := state.withdraw_oldest(max_mass_kg)
	if not is_equal_approx(before, state.total_mass_kg()):
		fill_changed.emit(state)
	return lots


static func get_all_for_ship(boat: Node) -> Array[CatchHoldComponent]:
	var out: Array[CatchHoldComponent] = []
	if boat == null:
		return out
	for child in boat.find_children("*", "CatchHoldComponent", true, false):
		var hold := child as CatchHoldComponent
		if hold != null:
			out.append(hold)
	return out


static func first_for_ship(boat: Node) -> CatchHoldComponent:
	var holds := get_all_for_ship(boat)
	return holds[0] if not holds.is_empty() else null


func _on_state_changed(_state: CatchHoldState) -> void:
	_sync_payload_mass()
	_update_fill_visual()


func _sync_payload_mass() -> void:
	if _boat == null:
		_boat = _find_boat()
	if _boat == null:
		return
	_boat.set_mass_entry(
		"catch:%s" % hold_id,
		state.total_mass_kg(),
		_boat.to_local(global_position) + Vector3(0.0, -0.8, 0.0),
		"cargo",
	)


func _find_boat() -> BoatBody:
	var node: Node = self
	while node != null:
		if node is BoatBody:
			return node as BoatBody
		node = node.get_parent()
	return null


func _build_visual() -> void:
	for child in get_children():
		child.queue_free()
	var hold := Node3D.new()
	hold.name = "OpenRswFishHold"
	add_child(hold)
	var steel := Color(0.34, 0.39, 0.42)
	var inner := Color(0.025, 0.045, 0.055)
	## Deep false floor and dark liner make this read as a volume below deck,
	## matching the open bulk-hold language used elsewhere on vessels.
	var pit := MeshBuilder.box(Vector3(5.42, 0.08, 4.02), inner, 0.96, 0.03)
	pit.position = Vector3(0.0, -1.12, 0.0)
	hold.add_child(pit)
	for wall in [
		[Vector3(-2.67, -0.52, 0.0), Vector3(0.08, 1.12, 4.02)],
		[Vector3(2.67, -0.52, 0.0), Vector3(0.08, 1.12, 4.02)],
		[Vector3(0.0, -0.52, -1.97), Vector3(5.42, 1.12, 0.08)],
		[Vector3(0.0, -0.52, 1.97), Vector3(5.42, 1.12, 0.08)],
	]:
		var liner := MeshBuilder.box(wall[1], inner, 0.92, 0.04)
		liner.position = wall[0]
		hold.add_child(liner)
	## Low stainless coaming around the open access hatch.
	for wall in [
		[Vector3(-2.82, 0.13, 0.0), Vector3(0.12, 0.26, 4.34)],
		[Vector3(2.82, 0.13, 0.0), Vector3(0.12, 0.26, 4.34)],
		[Vector3(0.0, 0.13, -2.11), Vector3(5.76, 0.26, 0.12)],
		[Vector3(0.0, 0.13, 2.11), Vector3(5.76, 0.26, 0.12)],
	]:
		var mesh := MeshBuilder.box(wall[1], steel, 0.7, 0.15)
		mesh.position = wall[0]
		hold.add_child(mesh)
	## Capped discharge manifold for a future fish-landing pump hose.
	var pipe := MeshBuilder.cylinder(0.10, 0.46, steel, 0.42, 0.72)
	pipe.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	pipe.position = Vector3(3.00, 0.25, 1.48)
	hold.add_child(pipe)
	var flange := MeshBuilder.cylinder(0.18, 0.08, Color(0.12, 0.16, 0.18), 0.5, 0.55)
	flange.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	flange.position = Vector3(3.26, 0.25, 1.48)
	hold.add_child(flange)
	_pump_connection = Node3D.new()
	_pump_connection.name = "PumpConnection"
	_pump_connection.position = Vector3(3.31, 0.25, 1.48)
	hold.add_child(_pump_connection)
	## Loose fish is landed through the open hatch. The hose hangs above this
	## point and drops into the RSW water rather than piercing the hull side.
	_hose_drop = Node3D.new()
	_hose_drop.name = "HoseDrop"
	_hose_drop.position = Vector3(0.0, -0.38, 0.0)
	hold.add_child(_hose_drop)
	_fill_root = Node3D.new()
	_fill_root.name = "FishAndChilledWater"
	add_child(_fill_root)
	_update_fill_visual()


func _update_fill_visual() -> void:
	if _fill_root == null:
		return
	for child in _fill_root.get_children():
		child.queue_free()
	var ratio := state.fill_ratio()
	if ratio <= CatchLot.MASS_EPS_KG:
		return
	var surface_y := lerpf(-1.04, 0.08, ratio)
	var water := MeshBuilder.box(
		Vector3(5.26, 0.045, 3.86),
		Color(0.16, 0.42, 0.48, 0.86),
		0.22,
		0.06,
	)
	water.position = Vector3(0.0, surface_y, 0.0)
	_fill_root.add_child(water)
	## A deterministic surface scatter reads as loose fish in chilled seawater
	## without creating one scene object per kilogram of catch.
	var fish_count := maxi(4, ceili(ratio * 42.0))
	for i in range(fish_count):
		var lane := i % 8
		var row := i / 8
		var jitter_x := sin(float(i * 17 + 3)) * 0.10
		var jitter_z := cos(float(i * 11 + 5)) * 0.09
		var fish_root := Node3D.new()
		fish_root.name = "Fish_%02d" % i
		fish_root.position = Vector3(
			-2.18 + float(lane) * 0.62 + jitter_x,
			surface_y + 0.07 + float(i % 3) * 0.012,
			-1.52 + float(row % 5) * 0.76 + jitter_z,
		)
		fish_root.rotation_degrees.y = float((i * 47) % 170) - 85.0
		## DeckFitout may enlarge the hold footprint to match the vessel's
		## half-scale display convention. Keep individual fish life-sized.
		fish_root.scale = Vector3(
			1.0 / maxf(scale.x, 0.001),
			1.0,
			1.0 / maxf(scale.z, 0.001),
		)
		_fill_root.add_child(fish_root)
		var fish_color := Color(0.56, 0.64, 0.66) if i % 3 else Color(0.32, 0.42, 0.46)
		var body := MeshBuilder.sphere(0.18, fish_color, 0.32, 0.18)
		body.scale = Vector3(1.0, 0.28, 0.42)
		fish_root.add_child(body)
		var tail := MeshBuilder.prism(Vector3(0.14, 0.06, 0.12), fish_color, 0.38, 0.12)
		tail.position = Vector3(0.21, 0.0, 0.0)
		tail.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		fish_root.add_child(tail)
