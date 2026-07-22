class_name ShoreRswTankBank
extends Node3D

## Shore-side refrigerated seawater buffer storage. Catch lots remain data;
## tank and sight-glass visuals are derived from the authoritative inventory.

signal inventory_changed(snapshot: Dictionary)

@export var bank_id := "shore_rsw_bank"
@export var capacity_kg := 120000.0
@export var tank_count := 2

var _inventory := CatchHoldState.new()
var _sight_fills: Array[MeshInstance3D] = []
var _temperature_c := -0.8


func _ready() -> void:
	_inventory.hold_id = bank_id
	_inventory.capacity_kg = maxf(capacity_kg, 0.0)
	if not _inventory.changed.is_connected(_on_inventory_changed):
		_inventory.changed.connect(_on_inventory_changed)
	_build_visual()
	_update_fill_visuals()


func available_kg() -> float:
	return _inventory.available_kg()


func total_mass_kg() -> float:
	return _inventory.total_mass_kg()


func fill_ratio() -> float:
	return _inventory.fill_ratio()


func accept_lot(lot: CatchLot) -> CatchLot:
	return _inventory.accept_lot(lot)


func withdraw_oldest(max_mass_kg: float) -> Array[CatchLot]:
	return _inventory.withdraw_oldest(max_mass_kg)


func snapshot() -> Dictionary:
	return {
		"bank_id": bank_id,
		"capacity_kg": capacity_kg,
		"stored_kg": total_mass_kg(),
		"available_kg": available_kg(),
		"temperature_c": _temperature_c,
		"inventory": _inventory.to_dict(),
	}


func inlet_world() -> Vector3:
	var marker := get_node_or_null("Inlet") as Node3D
	return marker.global_position if marker != null else global_position


func _on_inventory_changed(_state: CatchHoldState) -> void:
	_update_fill_visuals()
	inventory_changed.emit(snapshot())


func _build_visual() -> void:
	var stainless := Color(0.66, 0.70, 0.71)
	var band_color := Color(0.24, 0.29, 0.30)
	var refrigeration_blue := Color(0.08, 0.30, 0.40)
	var foundation := MeshBuilder.box(
		Vector3(10.4, 0.28, 11.5), Color(0.25, 0.27, 0.27), 0.92, 0.04
	)
	foundation.position.y = 0.14
	add_child(foundation)

	_sight_fills.clear()
	for i in range(maxi(tank_count, 1)):
		var z := -2.35 + float(i) * 4.7
		var tank := MeshBuilder.cylinder(2.02, 4.2, stainless, 0.30, 0.78)
		tank.name = "InsulatedRswTank_%d" % (i + 1)
		tank.position = Vector3(-1.0, 2.45, z)
		add_child(tank)
		for y in [0.65, 2.45, 4.25]:
			var ring := MeshBuilder.cylinder(2.08, 0.12, band_color, 0.46, 0.62)
			ring.position = Vector3(-1.0, y, z)
			add_child(ring)
		var cap := MeshBuilder.sphere(1.88, stainless.lightened(0.025), 0.30, 0.76)
		cap.scale.y = 0.36
		cap.position = Vector3(-1.0, 4.57, z)
		add_child(cap)
		var glass := MeshBuilder.box(
			Vector3(0.18, 3.25, 0.42), Color(0.035, 0.08, 0.095), 0.18, 0.20
		)
		glass.position = Vector3(1.04, 2.42, z)
		add_child(glass)
		var fill := MeshBuilder.box(
			Vector3(0.20, 3.05, 0.30), Color(0.12, 0.58, 0.68), 0.18, 0.08
		)
		fill.position = Vector3(1.15, 2.35, z)
		add_child(fill)
		_sight_fills.append(fill)
		var tank_label := Label3D.new()
		tank_label.text = "RSW %d" % (i + 1)
		tank_label.font = HudStyle.font_display()
		tank_label.font_size = 42
		tank_label.pixel_size = 0.006
		tank_label.position = Vector3(1.07, 3.75, z)
		tank_label.rotation_degrees.y = 90.0
		tank_label.modulate = Color(0.08, 0.28, 0.34)
		tank_label.outline_size = 4
		add_child(tank_label)

	## Shared top fill manifold and lower chilled-water circulation loop.
	_add_pipe(PackedVector3Array([
		Vector3(-1.0, 5.15, -2.35), Vector3(-1.0, 5.15, 2.35),
	]), 0.19, band_color)
	for z in [-2.35, 2.35]:
		_add_pipe(PackedVector3Array([
			Vector3(-1.0, 5.15, z), Vector3(-1.0, 4.75, z),
		]), 0.16, band_color)
		_add_pipe(PackedVector3Array([
			Vector3(-1.0, 0.55, z), Vector3(3.15, 0.55, z),
		]), 0.15, band_color)
	_add_pipe(PackedVector3Array([
		Vector3(-1.0, 5.15, 0.0), Vector3(3.65, 5.15, 0.0),
		Vector3(3.65, 1.55, 0.0), Vector3(4.65, 1.55, 0.0),
	]), 0.20, stainless)
	var inlet := Node3D.new()
	inlet.name = "Inlet"
	inlet.position = Vector3(4.85, 1.55, 0.0)
	add_child(inlet)

	## Refrigeration/circulation skid beside the tanks.
	var skid := MeshBuilder.box(
		Vector3(3.4, 0.22, 5.8), Color(0.19, 0.22, 0.23), 0.82, 0.20
	)
	skid.position = Vector3(3.65, 0.48, 0.0)
	add_child(skid)
	var compressor := MeshBuilder.cylinder(0.55, 1.55, refrigeration_blue, 0.38, 0.70)
	compressor.rotation_degrees.z = 90.0
	compressor.position = Vector3(3.25, 1.20, -1.55)
	add_child(compressor)
	var condenser := MeshBuilder.box(
		Vector3(1.25, 1.65, 2.15), Color(0.40, 0.45, 0.46), 0.48, 0.48
	)
	condenser.position = Vector3(3.65, 1.35, 1.15)
	add_child(condenser)
	for i in range(5):
		var fin := MeshBuilder.box(
			Vector3(1.32, 0.06, 2.20), band_color, 0.55, 0.40
		)
		fin.position = Vector3(3.65, 0.76 + float(i) * 0.28, 1.15)
		add_child(fin)
	var gauge := Label3D.new()
	gauge.text = "−0.8 °C"
	gauge.font = HudStyle.font_display()
	gauge.font_size = 44
	gauge.pixel_size = 0.007
	gauge.position = Vector3(4.30, 2.28, 1.15)
	gauge.rotation_degrees.y = 90.0
	gauge.modulate = Color(0.55, 0.92, 1.0)
	gauge.outline_size = 5
	add_child(gauge)


func _update_fill_visuals() -> void:
	if _sight_fills.is_empty():
		return
	var per_tank := capacity_kg / float(_sight_fills.size())
	var remaining := total_mass_kg()
	for fill in _sight_fills:
		var ratio := clampf(remaining / maxf(per_tank, 1.0), 0.0, 1.0)
		fill.visible = ratio > 0.001
		fill.scale.y = maxf(ratio, 0.01)
		fill.position.y = 0.83 + 1.525 * ratio
		remaining = maxf(remaining - per_tank, 0.0)


func _add_pipe(points: PackedVector3Array, radius: float, color: Color) -> void:
	for i in range(points.size() - 1):
		var segment := MeshBuilder.cylinder(radius, 1.0, color, 0.42, 0.68)
		add_child(segment)
		_pose_between(segment, points[i], points[i + 1])


func _pose_between(segment: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var delta := b - a
	var length := maxf(delta.length(), 0.001)
	var direction := delta / length
	var x_axis := direction.cross(Vector3.FORWARD)
	if x_axis.length_squared() < 0.001:
		x_axis = direction.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(direction).normalized()
	segment.transform = Transform3D(Basis(x_axis, direction, z_axis), (a + b) * 0.5)
	var mesh := segment.mesh as CylinderMesh
	if mesh != null:
		mesh.height = length * 1.03
