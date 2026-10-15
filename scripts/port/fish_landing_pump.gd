class_name FishLandingPump
extends Node3D

## Dockside RSW fish landing plant. Inventory remains authoritative CatchLot data;
## this node only performs a timed transfer and presents the hose/pump/hopper.

signal state_changed(state: String)
signal transfer_completed(report: Dictionary)
## Separate from the production completion signal, which may trigger settlement.
signal projection_completed(report: Dictionary)

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
var _transfer_credit := 0.0
var _hose_root: Node3D
var _hose_mesh: MeshInstance3D
var _receiver_fill: MeshInstance3D
var _connection_marker: Node3D
var _connection_direction: Node3D
var _projection := false
var _projection_hold: CatchHoldComponent
var _projection_loading := false
var _projection_reach_m := 24.0


func _ready() -> void:
	_build_visual()
	set_process(false)


func start_unload(ship: BoatBody) -> bool:
	if _projection: stop()
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
	_transfer_credit = 0.0
	_elapsed = 0.0
	_set_state(STATE_CONNECTING)
	set_process(true)
	_update_hose(0.0)
	_update_receiver_fill()
	return true


func bind_receiver(receiver: ShoreRswTankBank) -> void:
	_receiver = receiver


func stop() -> void:
	if _projection and is_instance_valid(_receiver_fill): _receiver_fill.hide()
	_projection = false
	_projection_hold = null
	_ship = null
	_elapsed = 0.0
	_set_state(STATE_IDLE)
	set_process(false)
	_set_hose_visible(false)


## Animate an ALREADY committed transfer. This path never reads or writes the
## inventory, calls a production job, or emits transfer_completed/payment hooks.
## The caller advances step_projection(), so replay has one clock and owner.
func start_projection(ship: BoatBody, hold: CatchHoldComponent, mass_kg: float, loading: bool, reach_m := 24.0) -> bool:
	if not is_inside_tree() or not is_instance_valid(ship) or not ship.is_inside_tree() or not is_instance_valid(hold): return false
	if not ship.is_ancestor_of(hold) or not is_finite(mass_kg) or mass_kg <= 0 or not is_finite(reach_m) or reach_m <= 0: return false
	if not can_project_to(hold, reach_m): return false
	stop()
	_projection = true
	_projection_hold = hold
	_projection_loading = loading
	_projection_reach_m = reach_m
	_ship = ship
	_initial_mass_kg = mass_kg
	_landed_mass_kg = 0
	_landed_value_marks = 0
	_landed_lots = 0
	_elapsed = 0
	_set_state(STATE_CONNECTING)
	set_process(false)
	_update_hose(0)
	_update_receiver_fill()
	return true


func can_project_to(hold: CatchHoldComponent, reach_m := 24.0) -> bool:
	if not is_instance_valid(_connection_marker) or not _connection_marker.is_inside_tree() or not is_instance_valid(hold) or not hold.is_inside_tree(): return false
	var target := hold.get_hose_drop_world()
	return target.is_finite() and _connection_marker.global_position.distance_to(target) <= reach_m + .001


func is_projecting() -> bool:
	return _projection


func projection_progress() -> float:
	return clampf(_landed_mass_kg / maxf(_initial_mass_kg, .001), 0, 1)


func projection_label() -> String:
	if _state == STATE_PUMPING: return "Pumping catch aboard" if _projection_loading else "Pumping catch ashore"
	return _state.capitalize()


func step_projection(delta: float) -> void:
	if not _projection: return
	if not is_finite(delta) or delta <= 0: return
	if not is_instance_valid(_ship) or not _ship.is_inside_tree() or not can_project_to(_projection_hold, _projection_reach_m):
		stop()
		return
	_elapsed += delta
	match _state:
		STATE_CONNECTING:
			var ratio := clampf(_elapsed / maxf(connect_seconds, .01), 0, 1)
			_update_hose(ratio)
			if ratio >= 1:
				_elapsed = 0
				_set_state(STATE_PUMPING)
		STATE_PUMPING:
			_update_hose(1)
			_landed_mass_kg = minf(_initial_mass_kg, _landed_mass_kg + maxf(pump_rate_kg_s, .001) * delta)
			_update_receiver_fill()
			if _landed_mass_kg >= _initial_mass_kg:
				_elapsed = 0
				_set_state(STATE_FLUSHING)
		STATE_FLUSHING:
			_update_hose(1)
			if _elapsed >= flush_seconds:
				_set_state(STATE_COMPLETE)
				_set_hose_visible(false)
				_receiver_fill.hide()
				_projection = false
				_projection_hold = null
				_ship = null
				projection_completed.emit({"mass_kg": _initial_mass_kg, "loading": _projection_loading})


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
		"Landing value  %s" % PlayerData.format_money(landed_value_marks()),
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
	if _projection:
		step_projection(delta)
		return
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
			if not _has_transferable_catch():
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


func _has_transferable_catch() -> bool:
	if WorldGateway.is_remote():return _landed_mass_kg < _initial_mass_kg
	var room := _receiver.available_kg() if _receiver != null else INF
	if room <= CatchLot.MASS_EPS_KG: return false
	for hold in _ship.get_catch_holds():
		var lots: Array[CatchLot] = hold.get_state().lots
		if not lots.is_empty() and (not lots[0].specimen or lots[0].mass_kg <= room):
			return true
	return false


func _transfer_mass(max_mass_kg: float) -> void:
	if WorldGateway.is_remote():
		# Animate throughput only. The server removes lots and pays atomically
		# after the owner submits the completed operation; observers never mutate.
		_landed_mass_kg=minf(_initial_mass_kg,_landed_mass_kg+maxf(0,max_mass_kg))
		return
	_transfer_credit += maxf(max_mass_kg, 0.0)
	var remaining := _transfer_credit
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
			_landed_value_marks += FishingLandingService.lot_value(lot,accepted_kg)
			remaining -= accepted_kg
			_transfer_credit = maxf(0, _transfer_credit - accepted_kg)


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
	if _projection and is_instance_valid(_projection_hold): return _projection_hold.get_hose_drop_world()
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
	SurfaceMaterialLibrary.apply(models)
	_connection_marker = models.find_child("HoseConnection",true,false) as Node3D
	_connection_direction = models.find_child("HoseDeparture",true,false) as Node3D
	assert(_connection_marker != null, "Landing drive requires an authored suction socket")
	assert(_connection_direction != null, "Landing drive requires an axial hose departure")
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
	_hose_mesh = MeshInstance3D.new()
	_hose_mesh.name = "ContinuousHose"
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color(.035,.055,.06);material.roughness=.82
	_hose_mesh.material_override=material
	_hose_root.add_child(_hose_mesh)
	_set_hose_visible(false)

func _update_hose(extension: float) -> void:
	if _connection_marker == null:
		return
	if extension<=.001:
		_set_hose_visible(false)
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
	var departure:=(_connection_direction.global_position-start).normalized()
	var bend:=start+departure*.8+Vector3.UP*.8
	var control_a := bend + Vector3.UP * lift + forward * minf(span * 0.20, 2.5)
	var control_b := end + Vector3.UP * (lift + 0.8) - forward * minf(span * 0.08, 1.2)
	var points: Array[Vector3] = []
	for i in range(9):
		points.append(start.bezier_interpolate(start+departure*.5,bend-Vector3.UP*.4,bend,float(i)/8))
	for i in range(1,33):
		points.append(bend.bezier_interpolate(control_a,control_b,end,float(i)/32))
	_build_hose_surface(points)


func _build_hose_surface(points: Array[Vector3]) -> void:
	const SIDES := 16
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var indices:=PackedInt32Array()
	var local_from_world:=_hose_mesh.global_transform.affine_inverse()
	var previous_axis:=Vector3.ZERO
	for i in points.size():
		var tangent:Vector3=(points[mini(i+1,points.size()-1)]-points[maxi(i-1,0)]).normalized()
		# Parallel-transport the ring frame to avoid flips at vertical bends.
		var u:=previous_axis-tangent*previous_axis.dot(tangent)
		if u.length_squared()<.001:
			u=tangent.cross(Vector3.UP)
			if u.length_squared()<.001:u=tangent.cross(Vector3.RIGHT)
		u=u.normalized();previous_axis=u
		var v:=tangent.cross(u).normalized()
		for j in SIDES:
			var angle:=TAU*float(j)/SIDES
			var normal:=u*cos(angle)+v*sin(angle)
			vertices.append(local_from_world*(points[i]+normal*.16))
			normals.append((local_from_world.basis*normal).normalized())
			if i<points.size()-1:
				var a:=i*SIDES+j;var b:=i*SIDES+(j+1)%SIDES
				indices.append_array(PackedInt32Array([a,a+SIDES,b,b,a+SIDES,b+SIDES]))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_hose_mesh.mesh=mesh


func _set_hose_visible(value: bool) -> void:
	if _hose_root != null:
		_hose_root.visible = value


func _update_receiver_fill() -> void:
	if _receiver_fill == null:
		return
	var ratio := clampf(_landed_mass_kg / maxf(_initial_mass_kg, 1.0), 0.0, 1.0)
	_receiver_fill.scale = Vector3(1.0, 1.0, maxf(ratio, 0.02))
	_receiver_fill.visible = ratio > 0.001
