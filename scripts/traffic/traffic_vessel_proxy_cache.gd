class_name TrafficVesselProxyCache
extends RefCounted

## Shared, complete low-cost traffic silhouettes. These are not placeholder
## hull boxes: every stamp includes hull, deck, aft superstructure and the
## vessel's visible cargo outfit. Meshes/materials are shared by every stamp.

static var _prototypes: Dictionary = {}
static var _materials: Dictionary = {}


static func instance(kind: String, length_m: float, beam_m: float) -> Node3D:
	var length_bin := snappedf(clampf(length_m, 24.0, 90.0), 4.0)
	var beam_bin := snappedf(clampf(beam_m, 7.0, 24.0), 2.0)
	var normalized_kind := "bulk" if kind == "bulk" else "general_cargo"
	var key := "%s:%.0f:%.0f" % [normalized_kind, length_bin, beam_bin]
	if not _prototypes.has(key):
		_prototypes[key] = _build(normalized_kind, length_bin, beam_bin)
	return (_prototypes[key] as Node3D).duplicate()


static func clear() -> void:
	for prototype_value in _prototypes.values():
		var prototype := prototype_value as Node
		if prototype != null and is_instance_valid(prototype):
			prototype.free()
	_prototypes.clear()
	_materials.clear()


static func _build(kind: String, length_m: float, beam_m: float) -> Node3D:
	var root := Node3D.new()
	root.name = "TrafficProxy_%s" % kind
	_add_box(root, "RedKeel", Vector3(beam_m * 0.82, 1.4, length_m * 0.86),
		Vector3(0.0, -0.45, 0.5), Color(0.34, 0.045, 0.035))
	_add_box(root, "Hull", Vector3(beam_m, 2.4, length_m),
		Vector3(0.0, 0.8, 0.0), Color(0.055, 0.065, 0.075))
	_add_box(root, "WhiteSheer", Vector3(beam_m * 0.94, 0.55, length_m * 0.90),
		Vector3(0.0, 2.15, 0.0), Color(0.84, 0.87, 0.88))
	_add_box(root, "Deck", Vector3(beam_m * 0.82, 0.35, length_m * 0.82),
		Vector3(0.0, 2.55, 0.4), Color(0.32, 0.24, 0.17))

	var house_length := clampf(length_m * 0.22, 7.0, 14.0)
	var house_z := length_m * 0.5 - house_length * 0.62
	_add_box(root, "Superstructure", Vector3(beam_m * 0.78, 4.8, house_length),
		Vector3(0.0, 5.05, house_z), Color(0.91, 0.92, 0.90))
	_add_box(root, "BridgeWindows", Vector3(beam_m * 0.80, 1.05, house_length * 0.62),
		Vector3(0.0, 6.0, house_z - house_length * 0.20), Color(0.055, 0.15, 0.20))
	_add_box(root, "BridgeTop", Vector3(beam_m * 0.82, 0.45, house_length * 0.90),
		Vector3(0.0, 7.65, house_z), Color(0.86, 0.88, 0.88))
	_add_box(root, "Mast", Vector3(0.28, 5.0, 0.28),
		Vector3(0.0, 10.0, house_z), Color(0.32, 0.34, 0.34))

	var cargo_end_z := house_z - house_length * 0.72
	var cargo_start_z := -length_m * 0.34
	var cargo_length := maxf(cargo_end_z - cargo_start_z, 8.0)
	if kind == "bulk":
		var hatch_count := maxi(2, floori(cargo_length / 9.0))
		for index in range(hatch_count):
			var t := (float(index) + 0.5) / float(hatch_count)
			_add_box(root, "Hatch_%02d" % index,
				Vector3(beam_m * 0.66, 0.65, cargo_length / hatch_count * 0.72),
				Vector3(0.0, 3.05, lerpf(cargo_start_z, cargo_end_z, t)),
				Color(0.48, 0.22, 0.095))
	else:
		var rows := maxi(2, floori(cargo_length / 7.0))
		for row in range(rows):
			for side in [-1, 1]:
				var t := (float(row) + 0.5) / float(rows)
				_add_box(root, "Container_%02d_%d" % [row, side],
					Vector3(beam_m * 0.36, 3.0, cargo_length / rows * 0.76),
					Vector3(float(side) * beam_m * 0.205, 4.1,
						lerpf(cargo_start_z, cargo_end_z, t)),
					Color(0.055, 0.24 + 0.025 * float(row % 3), 0.48))
	return root


static func _add_box(
		parent: Node3D,
		name: String,
		size: Vector3,
		position: Vector3,
		color: Color,
) -> void:
	var instance := MeshInstance3D.new()
	instance.name = name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	instance.material_override = _material(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


static func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	_materials[key] = material
	return material
