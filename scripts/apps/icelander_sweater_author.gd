extends SceneTree

## Authoring recipe for the first textured clothing proof. The sweater is a
## fitted chamfered shell, not a scaled box: shoulder, torso, sleeve, collar,
## cuff, and hem dimensions are independently controlled around the body rig.

const OUTPUT_PATH := "res://resources/data/models/characters/prototypes/icelander_sweater.json"
const TEXTURE_PROFILE := "icelander_knit"


func _init() -> void:
	var model := {
		"name": "icelander_sweater_proof",
		"slot": "top",
		"parts": _parts(),
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir()))
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("IcelanderSweaterAuthor: cannot write %s" % OUTPUT_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(model, "  "))
	file.close()
	print("IcelanderSweaterAuthor: wrote %d fitted parts to %s" % [model.parts.size(), OUTPUT_PATH])
	quit()


func _parts() -> Array:
	var parts: Array = []
	parts.append(_part("torso", "chest", _loft([
		# The torso stops before the texture's rib region. The separately
		# modelled hem below owns that detail so it stays a crisp knitted band
		# rather than stretching vertically across the lower body.
		_ring(-0.040, 0.170, 0.107, 0.024, 0.875),
		_ring(0.060, 0.174, 0.110, 0.026, 0.76),
		_ring(0.245, 0.178, 0.112, 0.027, 0.38),
		_ring(0.370, 0.170, 0.108, 0.025, 0.08),
	]), "knit"))
	parts.append(_part("hem", "chest", _loft([
		_ring(-0.050, 0.176, 0.112, 0.025, 1.00),
		_ring(0.005, 0.176, 0.112, 0.025, 0.89),
	]), "rib"))
	parts.append(_part("collar", "chest", _hollow_collar(), "rib"))
	for side in ["left", "right"]:
		parts.append(_part("upper_sleeve_%s" % side, "arm_%s" % side, _loft([
			_ring(0.035, 0.062, 0.069, 0.016, 0.04),
			_ring(-0.100, 0.061, 0.068, 0.015, 0.27),
			_ring(-0.305, 0.057, 0.064, 0.014, 0.58),
		]), "knit"))
		parts.append(_part("lower_sleeve_%s" % side, "forearm_%s" % side, _loft([
			_ring(0.025, 0.058, 0.065, 0.014, 0.56),
			_ring(-0.120, 0.056, 0.063, 0.013, 0.76),
			_ring(-0.225, 0.053, 0.060, 0.012, 0.90),
		]), "knit"))
		parts.append(_part("cuff_%s" % side, "forearm_%s" % side, _loft([
			_ring(-0.218, 0.057, 0.064, 0.013, 0.89),
			_ring(-0.258, 0.055, 0.062, 0.012, 1.00),
		]), "rib"))
	return parts


func _part(part_name: String, anchor: String, mesh: Dictionary, detail_role: String) -> Dictionary:
	return {
		"name": part_name,
		"anchor": anchor,
		"detail_role": detail_role,
		"mesh": mesh,
		"texture_profile": TEXTURE_PROFILE,
		"color": [1.0, 1.0, 1.0, 1.0],
		"roughness": 0.93,
		"metallic": 0.0,
	}


func _ring(y: float, half_x: float, half_z: float, chamfer: float, v: float) -> Dictionary:
	return {"y": y, "half_x": half_x, "half_z": half_z, "chamfer": chamfer, "v": v}


func _ring_points(spec: Dictionary) -> Array[Vector3]:
	var y := float(spec.y)
	var hx := float(spec.half_x)
	var hz := float(spec.half_z)
	var c := minf(float(spec.chamfer), minf(hx, hz) * 0.48)
	return [
		Vector3(-hx + c, y, -hz), Vector3(hx - c, y, -hz),
		Vector3(hx, y, -hz + c), Vector3(hx, y, hz - c),
		Vector3(hx - c, y, hz), Vector3(-hx + c, y, hz),
		Vector3(-hx, y, hz - c), Vector3(-hx, y, -hz + c),
	]


func _loft(rings: Array) -> Dictionary:
	var vertices: Array = []
	var uvs: Array = []
	var indices: Array = []
	for ring_spec in rings:
		var points := _ring_points(ring_spec)
		for segment in range(9):
			var point: Vector3 = points[segment % 8]
			vertices.append_array(_v3(point))
			uvs.append(float(segment) / 8.0)
			uvs.append(float(ring_spec.v))
	for ring_index in range(rings.size() - 1):
		var lower := ring_index * 9
		var upper := (ring_index + 1) * 9
		for segment in range(8):
			var a := lower + segment
			var b := lower + segment + 1
			var c := upper + segment + 1
			var d := upper + segment
			# MeshBuilder swaps the final two source indices. This authored order
			# yields outward generated normals after that conversion.
			indices.append_array([a, b, c, a, c, d])
	return {"vertices": vertices, "indices": indices, "uvs": uvs}


func _hollow_collar() -> Dictionary:
	var outer_bottom := _ring(0.365, 0.082, 0.070, 0.018, 0.04)
	var outer_top := _ring(0.418, 0.076, 0.066, 0.017, 0.00)
	var mesh := _loft([outer_bottom, outer_top])
	# A dark inset closes the obvious skin-to-sweater gap without producing a
	# rigid square collar. The body neck remains visible through the centre.
	return mesh


func _v3(value: Vector3) -> Array:
	return [snappedf(value.x, 0.000001), snappedf(value.y, 0.000001), snappedf(value.z, 0.000001)]
