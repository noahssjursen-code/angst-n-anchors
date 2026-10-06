class_name FishLandingPump
extends Node3D

## Dockside RSW fish landing plant. Inventory remains authoritative CatchLot data;
## this node only performs a timed transfer and presents the hose/pump/hopper.

signal state_changed(state: String)
signal transfer_completed(report: Dictionary)

const STATE_IDLE := "idle"
const STATE_CONNECTING := "connecting hose"
const STATE_PUMPING := "pumping catch ashore"
const STATE_FLUSHING := "flushing line"
const STATE_COMPLETE := "landing complete"

@export var pump_rate_kg_s := 520.0
@export var connect_seconds := 1.4
@export var flush_seconds := 1.1

var _state := STATE_IDLE
var _ship: BoatBody
var _receiver: ShoreRswTankBank
var _elapsed := 0.0
var _initial_mass_kg := 0.0
var _landed_mass_kg := 0.0
var _landed_value_marks := 0.0
var _landed_lots := 0
var _hose_root: Node3D
var _hose_segments: Array[MeshInstance3D] = []
var _receiver_fill: MeshInstance3D
var _connection_marker: Node3D


func _ready() -> void:
	_build_visual()
	set_process(false)


func start_unload(ship: BoatBody) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	var total := _ship_catch_mass(ship)
	if total <= CatchLot.MASS_EPS_KG:
		return false
	if _receiver != null and _receiver.available_kg() <= CatchLot.MASS_EPS_KG:
		return false
	_ship = ship
	_initial_mass_kg = total
	_landed_mass_kg = 0.0
	_landed_value_marks = 0.0
	_landed_lots = 0
	_elapsed = 0.0
	_set_state(STATE_CONNECTING)
	set_process(true)
	_update_hose(0.0)
	_update_receiver_fill()
	return true


func bind_receiver(receiver: ShoreRswTankBank) -> void:
	_receiver = receiver


func stop() -> void:
	_ship = null
	_elapsed = 0.0
	_set_state(STATE_IDLE)
	set_process(false)
	_set_hose_visible(false)


func state_label() -> String:
	return _state


func landed_mass_kg() -> float:
	return _landed_mass_kg


func landed_value_marks() -> int:
	return maxi(int(round(_landed_value_marks)), 0)


func focus_position() -> Vector3:
	if _ship != null and is_instance_valid(_ship):
		return (_connection_marker.global_position + _ship_connection_world()) * 0.5
	return _connection_marker.global_position


func get_status_lines() -> PackedStringArray:
	var remaining := _ship_catch_mass(_ship) if _ship != null and is_instance_valid(_ship) else 0.0
	var lines := PackedStringArray([
		"Landing plant  %s" % _state,
		"Flow  %.0f kg/s" % pump_rate_kg_s,
		"Ashore  %.2f t  ·  remaining %.2f t" % [_landed_mass_kg / 1000.0, remaining / 1000.0],
		"Landing value  %d marks" % landed_value_marks(),
	])
	if _receiver != null:
		lines.append(
			"Shore RSW  %.2f / %.2f t  ·  %.1f °C" % [
				_receiver.total_mass_kg() / 1000.0,
				_receiver.capacity_kg / 1000.0,
				float(_receiver.snapshot().get("temperature_c", 0.0)),
			]
		)
	return lines


func _process(delta: float) -> void:
	if _ship == null or not is_instance_valid(_ship):
		stop()
		return
	_elapsed += delta
	match _state:
		STATE_CONNECTING:
			var ratio := clampf(_elapsed / maxf(connect_seconds, 0.01), 0.0, 1.0)
			_update_hose(ratio)
			if ratio >= 1.0:
				_elapsed = 0.0
				_set_state(STATE_PUMPING)
		STATE_PUMPING:
			_update_hose(1.0)
			_transfer_mass(pump_rate_kg_s * delta)
			_update_receiver_fill()
			if _ship_catch_mass(_ship) <= CatchLot.MASS_EPS_KG or (
				_receiver != null and _receiver.available_kg() <= CatchLot.MASS_EPS_KG
			):
				_elapsed = 0.0
				_set_state(STATE_FLUSHING)
		STATE_FLUSHING:
			_update_hose(1.0)
			if _elapsed >= flush_seconds:
				## Capture the authoritative result before releasing the vessel.
				## Completion is also a disconnect: leaving the flexible hose
				## deployed here made a later Stop ineffective because the job had
				## already cleared its active ship.
				var report := _report()
				_set_state(STATE_COMPLETE)
				set_process(false)
				_set_hose_visible(false)
				_ship = null
				transfer_completed.emit(report)


func _transfer_mass(max_mass_kg: float) -> void:
	var remaining := maxf(max_mass_kg, 0.0)
	if _receiver != null:
		remaining = minf(remaining, _receiver.available_kg())
	for hold in _ship.get_catch_holds():
		if remaining <= CatchLot.MASS_EPS_KG:
			break
		var lots := hold.withdraw_oldest(remaining)
		for lot in lots:
			var accepted_kg := lot.mass_kg
			if _receiver != null:
				var overflow := _receiver.accept_lot(lot)
				accepted_kg -= overflow.mass_kg
				if not overflow.is_empty():
					hold.accept_lot(overflow)
			if accepted_kg <= CatchLot.MASS_EPS_KG:
				continue
			_landed_mass_kg += accepted_kg
			_landed_lots += 1
			_landed_value_marks += (
				accepted_kg / 100.0
				* FishingLandingService.MARKS_PER_100_KG
				* clampf(lot.quality, 0.0, 1.0)
				* maxf(lot.price_multiplier, 0.0)
			)
			remaining -= accepted_kg


func _report() -> Dictionary:
	return {
		"ok": _landed_mass_kg > CatchLot.MASS_EPS_KG,
		"complete": _ship_catch_mass(_ship) <= CatchLot.MASS_EPS_KG,
		"mass_kg": _landed_mass_kg,
		"lot_count": _landed_lots,
		"value_marks": landed_value_marks(),
	}


func _set_state(next: String) -> void:
	if _state == next:
		return
	_state = next
	state_changed.emit(_state)


func _ship_catch_mass(ship: BoatBody) -> float:
	if ship == null or not is_instance_valid(ship):
		return 0.0
	var total := 0.0
	for hold in ship.get_catch_holds():
		total += hold.get_state().total_mass_kg()
	return total


func _ship_connection_world() -> Vector3:
	if _ship == null or not is_instance_valid(_ship):
		return _connection_marker.global_position
	var holds := _ship.get_catch_holds()
	if not holds.is_empty():
		return holds[0].get_hose_drop_world()
	return _ship.global_position


func _build_visual() -> void:
	var models := Node3D.new()
	models.name = "ImportedLandingPlant"
	add_child(models)
	for part_name in ["landing_skid", "landing_separator", "landing_pump_drive", "landing_trough"]:
		var scene := load("res://resources/models/parts/port_kit/"+part_name+".glb") as PackedScene
		assert(scene != null)
		models.add_child(scene.instantiate())
	_connection_marker = models.find_child("HoseConnection",true,false) as Node3D
	assert(_connection_marker != null, "Landing drive requires an authored suction socket")
	var fill_datum := models.find_child("FillDatum",true,false) as Node3D
	assert(fill_datum != null)
	# Transient fill and deforming hose remain gameplay presentation, not static fittings.
	_receiver_fill = MeshBuilder.box(Vector3(2.18,.10,2.38),Color(.45,.62,.64),.25,.04)
	add_child(_receiver_fill)
	_receiver_fill.global_position = fill_datum.global_position
	_receiver_fill.visible = false
	_hose_root = Node3D.new()
	_hose_root.name = "FlexibleSuctionHose"
	add_child(_hose_root)
	for i in range(14):
		var segment := MeshBuilder.cylinder(.16,1.0,Color(.035,.055,.06),.82,.04)
		segment.name = "Hose_%02d" % i
		_hose_root.add_child(segment)
		_hose_segments.append(segment)
	_set_hose_visible(false)

func _update_hose(extension: float) -> void:
	if _connection_marker == null:
		return
	_set_hose_visible(true)
	var start := _connection_marker.global_position
	var target := _ship_connection_world()
	var end := start.lerp(target, clampf(extension, 0.0, 1.0))
	var span := start.distance_to(end)
	## Lift clear of the quay and vessel rail, cross high, then hang down into
	## the open RSW hold. A sagging chord cut through the pavement and hull.
	var lift := clampf(span * 0.23, 2.8, 5.5)
	var horizontal := end - start
	horizontal.y = 0.0
	var forward := horizontal.normalized() if horizontal.length_squared() > 0.001 else Vector3.RIGHT
	var control_a := start + Vector3.UP * lift + forward * minf(span * 0.20, 2.5)
	var control_b := end + Vector3.UP * (lift + 0.8) - forward * minf(span * 0.08, 1.2)
	var points: Array[Vector3] = []
	for i in range(_hose_segments.size() + 1):
		var t := float(i) / float(_hose_segments.size())
		var point := start.bezier_interpolate(control_a, control_b, end, t)
		points.append(point)
	for i in range(_hose_segments.size()):
		_pose_cylinder_between(_hose_segments[i], points[i], points[i + 1])


func _pose_cylinder_between(segment: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var delta := b - a
	var length := maxf(delta.length(), 0.001)
	var direction := delta / length
	var x_axis := direction.cross(Vector3.FORWARD)
	if x_axis.length_squared() < 0.001:
		x_axis = direction.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(direction).normalized()
	segment.global_transform = Transform3D(Basis(x_axis, direction, z_axis), (a + b) * 0.5)
	var mesh := segment.mesh as CylinderMesh
	if mesh != null:
		mesh.height = length * 1.03


func _set_hose_visible(value: bool) -> void:
	if _hose_root != null:
		_hose_root.visible = value


func _update_receiver_fill() -> void:
	if _receiver_fill == null:
		return
	var ratio := clampf(_landed_mass_kg / maxf(_initial_mass_kg, 1.0), 0.0, 1.0)
	_receiver_fill.scale = Vector3(1.0, 1.0, maxf(ratio, 0.02))
	_receiver_fill.visible = ratio > 0.001
