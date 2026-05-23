class_name DeckGridOverlay
extends RefCounted

## Dev-only deck overlay: computed deck planform for planning structures
## that sit on the deck plate (e.g. bridge). Hull machinery slots are excluded.
## Built only when `Engine.is_editor_hint()` — hidden in exported / runtime play.

const DEFAULT_SIDE_TRIM := 0.12
const DEFAULT_END_MARGIN_FRAC := 0.07
const BEAM_WIDTH_SCALE := 0.92
const SLICE_COUNT := 32
const BRIDGE_HALF_W := 1.15
## Placement anchor — bridge slot in ShipFrame space (matches ShipwrightPreview).
const SUPERSTRUCTURE_OFFSET := Vector3.ZERO

const COLOR_DECK := Color(0.82, 0.86, 0.90, 0.14)
const COLOR_MARGIN := Color(0.92, 0.32, 0.28, 0.48)
const COLOR_STRUCTURE := Color(0.96, 0.76, 0.28, 0.52)
const COLOR_SIDE := Color(0.55, 0.62, 0.72, 0.38)

const OPEN_PALETTE: Array[Color] = [
	Color(0.18, 0.82, 0.52, 0.42),
	Color(0.22, 0.58, 0.95, 0.42),
	Color(0.62, 0.38, 0.92, 0.40),
	Color(0.95, 0.62, 0.22, 0.40),
]


static func attach(
	parent: Node3D,
	stations: HullStations,
	mesh_scale: float,
	slots: Dictionary = {},
	registry_entry: Dictionary = {},
	hull_data: Dictionary = {}
) -> Node3D:
	if not Engine.is_editor_hint():
		return null

	var root := Node3D.new()
	root.name = "DeckPlanOverlay"
	parent.add_child(root)

	if stations == null or stations.stations.is_empty():
		return root

	var role: VesselRole.Type = registry_entry.get("role", VesselRole.Type.CARGO)
	var slices := _build_slices(stations, mesh_scale, hull_data)
	if slices.size() < 2:
		return root

	var zones := _compute_zones(slots, mesh_scale, role, slices, registry_entry, stations.deck_y)
	if zones.is_empty():
		return root

	var deck_y: float = stations.deck_y * mesh_scale + 0.012
	var z_center: float = _deck_z_center(slices)
	var label_fs: int = clampi(int(11 + mesh_scale * 3.5), 11, 20)
	var label_y: float = deck_y + 0.065
	var layer: float = 0.0

	for zone: Dictionary in zones:
		layer += 0.001
		var color: Color = zone["color"] as Color
		var label: String = str(zone["label"])
		var label_pos: Vector3
		if zone.has("polygon_xz"):
			var poly: PackedVector2Array = zone["polygon_xz"]
			_spawn_polygon_mesh(root, str(zone["id"]), poly, deck_y + layer, color)
			label_pos = _polygon_label_pos(poly, label_y)
		else:
			var x_lo: float = float(zone["x_lo"])
			var x_hi: float = float(zone["x_hi"])
			_spawn_band_mesh(root, str(zone["id"]), slices, deck_y + layer, x_lo, x_hi, color)
			label_pos = Vector3((x_lo + x_hi) * 0.5, label_y, z_center)
		if not label.is_empty():
			var label_color := Color(0.95, 0.97, 1.0, 0.98)
			if color.get_luminance() > 0.55:
				label_color = Color(0.08, 0.10, 0.12, 0.95)
			_spawn_zone_label(root, label, label_pos, label_color, label_fs)

	_spawn_side_trim_zones(root, slices, deck_y + 0.0005, label_y, label_fs)
	return root


static func _compute_zones(
	slots: Dictionary,
	mesh_scale: float,
	role: VesselRole.Type,
	slices: Array,
	registry_entry: Dictionary,
	_deck_y_unscaled: float = 0.0
) -> Array:
	var x_bounds := _deck_x_bounds(slices)
	var bow_x: float = x_bounds.x
	var stern_x: float = x_bounds.y
	var span: float = stern_x - bow_x
	if span < 0.5:
		return []

	var end_margin: float = maxf(0.4, span * DEFAULT_END_MARGIN_FRAC)
	var build_lo: float = bow_x + end_margin
	var build_hi: float = stern_x - end_margin
	if build_hi <= build_lo:
		return []

	var zones: Array = []

	zones.append({
		"id": "deck_mask",
		"label": "DECK",
		"x_lo": bow_x,
		"x_hi": stern_x,
		"color": COLOR_DECK,
	})

	zones.append({
		"id": "bow_margin",
		"label": "BOW\nMARGIN",
		"x_lo": bow_x,
		"x_hi": build_lo,
		"color": COLOR_MARGIN,
	})

	zones.append({
		"id": "stern_margin",
		"label": "STERN\nMARGIN",
		"x_lo": build_hi,
		"x_hi": stern_x,
		"color": COLOR_MARGIN,
	})

	var reservations: Array = _deck_structure_reservations(
		slots, mesh_scale, build_lo, build_hi, registry_entry
	)
	reservations.sort_custom(func(a, b): return float(a["x_lo"]) < float(b["x_lo"]))

	for res: Dictionary in reservations:
		var zone: Dictionary = {
			"id": "structure_%s" % res["key"],
			"label": str(res["label"]),
			"x_lo": float(res["x_lo"]),
			"x_hi": float(res["x_hi"]),
			"color": COLOR_STRUCTURE,
		}
		if res.has("polygon_xz"):
			zone["polygon_xz"] = res["polygon_xz"]
		zones.append(zone)

	var open_spans: Array = _open_spans_around(build_lo, build_hi, reservations, role)
	var open_idx := 0
	for span_def: Dictionary in open_spans:
		var x0: float = float(span_def["x_lo"])
		var x1: float = float(span_def["x_hi"])
		if x1 - x0 < 0.15:
			continue
		var pal: Color = OPEN_PALETTE[open_idx % OPEN_PALETTE.size()]
		open_idx += 1
		zones.append({
			"id": "open_%d" % open_idx,
			"label": _open_segment_label(open_idx, open_spans.size(), role, x0, x1, build_lo, build_hi),
			"x_lo": x0,
			"x_hi": x1,
			"color": pal,
		})

	return zones


static func _deck_structure_reservations(
	slots: Dictionary,
	mesh_scale: float,
	build_lo: float,
	build_hi: float,
	registry_entry: Dictionary
) -> Array:
	if not slots.has("bridge"):
		return []

	var anchor := _superstructure_anchor(slots, mesh_scale)
	var center_x: float = anchor.x
	var half_w: float = BRIDGE_HALF_W * mesh_scale
	var x_lo: float = maxf(center_x - half_w, build_lo)
	var x_hi: float = minf(center_x + half_w, build_hi)
	if x_hi - x_lo < 0.05:
		return []
	return [{
		"key": "bridge",
		"label": "BRIDGE",
		"x_lo": x_lo,
		"x_hi": x_hi,
	}]


static func _superstructure_anchor(slots: Dictionary, mesh_scale: float) -> Vector3:
	var bridge: Vector3 = slots["bridge"] as Vector3
	return (bridge + SUPERSTRUCTURE_OFFSET * mesh_scale).rotated(
		Vector3.UP, ShipBuilder.HULL_AUTHORED_Y_ROT
	)


static func _read_vec3(raw: Variant) -> Vector3:
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 3:
		return Vector3.ZERO
	var arr: Array = raw as Array
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


static func _polygon_label_pos(poly: PackedVector2Array, label_y: float) -> Vector3:
	var cx := 0.0
	var cz := 0.0
	for p: Vector2 in poly:
		cx += p.x
		cz += p.y
	var n: float = float(poly.size())
	return Vector3(cx / n, label_y, cz / n)


static func _open_spans_around(
	build_lo: float,
	build_hi: float,
	reservations: Array,
	role: VesselRole.Type
) -> Array:
	var spans: Array = []
	var cursor: float = build_lo
	for res: Dictionary in reservations:
		var x_lo: float = float(res["x_lo"])
		var x_hi: float = float(res["x_hi"])
		if x_lo > cursor + 0.05:
			spans.append({"x_lo": cursor, "x_hi": x_lo})
		cursor = maxf(cursor, x_hi)
	if build_hi > cursor + 0.05:
		spans.append({"x_lo": cursor, "x_hi": build_hi})
	if not spans.is_empty() or not reservations.is_empty():
		return spans
	return _deck_open_spans(build_lo, build_hi, role)


static func _deck_open_spans(build_lo: float, build_hi: float, role: VesselRole.Type) -> Array:
	if build_hi - build_lo < 0.15:
		return []
	if role == VesselRole.Type.FISHING:
		var mid: float = (build_lo + build_hi) * 0.5
		return [
			{"x_lo": build_lo, "x_hi": mid},
			{"x_lo": mid, "x_hi": build_hi},
		]
	return [{"x_lo": build_lo, "x_hi": build_hi}]


static func _open_segment_label(
	index: int,
	total: int,
	role: VesselRole.Type,
	x_lo: float,
	x_hi: float,
	build_lo: float,
	build_hi: float
) -> String:
	var mid: float = (x_lo + x_hi) * 0.5
	var build_mid: float = (build_lo + build_hi) * 0.5
	if role == VesselRole.Type.FISHING:
		if mid < build_mid:
			return "FWD\nOPEN"
		return "AFT\nOPEN"
	if total == 1:
		return "OPEN\nDECK"
	return "OPEN\n%d" % index


static func _build_slices(
	stations: HullStations,
	mesh_scale: float,
	hull_data: Dictionary
) -> Array:
	var verts := _deck_outline_vertices(hull_data)
	if verts.is_empty():
		return _build_slices_from_stations(stations, mesh_scale)

	var poly := _deck_polygon_xz(verts)
	if poly.size() < 3:
		return _build_slices_from_stations(stations, mesh_scale)

	return _slices_from_polygon(poly, mesh_scale)


static func _slices_from_polygon(poly: PackedVector2Array, mesh_scale: float) -> Array:
	var z_min := INF
	var z_max := -INF
	for p: Vector2 in poly:
		z_min = minf(z_min, p.y)
		z_max = maxf(z_max, p.y)
	if z_max - z_min < 0.2:
		return []

	var z_center: float = (z_min + z_max) * 0.5
	var slices: Array = []
	for i in SLICE_COUNT:
		var t: float = float(i) / float(SLICE_COUNT - 1) if SLICE_COUNT > 1 else 0.5
		var z_logical: float = lerpf(z_min, z_max, t)
		var x_span := _polygon_x_span_at_beam(poly, z_logical)
		var z_display: float = z_center + (z_logical - z_center) * BEAM_WIDTH_SCALE
		var x_lo: float = x_span.x * mesh_scale
		var x_hi: float = x_span.y * mesh_scale
		if x_span.x > x_span.y:
			x_lo = 0.0
			x_hi = -1.0
		slices.append({
			"z": z_display * mesh_scale,
			"hb": maxf(absf(x_lo), absf(x_hi)),
			"x_neg": x_lo,
			"x_pos": x_hi,
		})
	return slices


static func _deck_polygon_xz(verts: Array[Vector3]) -> PackedVector2Array:
	var points := PackedVector2Array()
	for v: Vector3 in verts:
		points.append(Vector2(v.x, v.z))
	if points.size() < 3:
		return PackedVector2Array()
	return Geometry2D.convex_hull(points)


## Intersect deck outline with a beam-axis line; returns (x_min, x_max) or empty.
static func _polygon_x_span_at_beam(poly: PackedVector2Array, beam_z: float) -> Vector2:
	var xs: Array = []
	var n: int = poly.size()
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		if absf(a.y - b.y) < 0.00001:
			if absf(a.y - beam_z) < 0.00001:
				xs.append(a.x)
				xs.append(b.x)
			continue
		if (a.y <= beam_z and b.y > beam_z) or (b.y <= beam_z and a.y > beam_z):
			var t: float = (beam_z - a.y) / (b.y - a.y)
			xs.append(lerpf(a.x, b.x, t))
		elif absf(a.y - beam_z) < 0.00001:
			xs.append(a.x)
	if xs.is_empty():
		return Vector2(INF, -INF)
	var x_min: float = float(xs[0])
	var x_max: float = float(xs[0])
	for x: Variant in xs:
		var xf: float = float(x)
		x_min = minf(x_min, xf)
		x_max = maxf(x_max, xf)
	return Vector2(x_min, x_max)


static func _build_slices_from_stations(stations: HullStations, mesh_scale: float) -> Array:
	var curve := _stations_planform_curve(stations)
	if curve.is_empty():
		return []

	var points := PackedVector2Array()
	for pt: Dictionary in curve:
		var z_raw: float = float(pt["z"])
		var hb: float = float(pt["hb"])
		points.append(Vector2(hb, z_raw))
		points.append(Vector2(-hb, z_raw))
	var poly := Geometry2D.convex_hull(points)
	if poly.size() < 3:
		return []
	return _slices_from_polygon(poly, mesh_scale)


static func _deck_outline_vertices(hull_data: Dictionary) -> Array[Vector3]:
	var deck := _part_vertices(hull_data, "deck")
	if not deck.is_empty():
		return deck
	return _part_vertices(hull_data, "hull_upper")


## Beam-axis planform curve from strip stations (fallback when no deck part exists).
static func _stations_planform_curve(stations: HullStations) -> Array:
	var s_arr: Array = stations.stations
	var z_to_hb: Dictionary = {}
	for idx in s_arr.size():
		var st: Dictionary = s_arr[idx]
		var length_z: float = float(st["z"])
		var beam_half: float = stations.half_beam_at(idx, stations.deck_y)
		if beam_half <= 0.01:
			continue
		var x_extent: float = absf(length_z)
		for side: float in [-1.0, 1.0]:
			var beam_z: float = snappedf(side * beam_half, 0.04)
			z_to_hb[beam_z] = maxf(float(z_to_hb.get(beam_z, 0.0)), x_extent)
	if z_to_hb.is_empty():
		return []
	var keys: Array = z_to_hb.keys()
	keys.sort()
	var curve: Array = []
	for key: Variant in keys:
		curve.append({"z": float(key), "hb": float(z_to_hb[key])})
	return curve


static func _sample_half_beam_curve(curve: Array, z_raw: float) -> float:
	if curve.is_empty():
		return 0.0
	var z_min: float = float(curve[0]["z"])
	var z_max: float = float(curve[curve.size() - 1]["z"])
	if z_raw <= z_min:
		return float(curve[0]["hb"])
	if z_raw >= z_max:
		return float(curve[curve.size() - 1]["hb"])
	for i in range(curve.size() - 1):
		var a: Dictionary = curve[i]
		var b: Dictionary = curve[i + 1]
		var z0: float = float(a["z"])
		var z1: float = float(b["z"])
		if z_raw >= z0 and z_raw <= z1:
			var denom: float = z1 - z0
			if denom <= 0.0001:
				return float(a["hb"])
			var t: float = (z_raw - z0) / denom
			return lerpf(float(a["hb"]), float(b["hb"]), t)
	return 0.0


static func _part_vertices(hull_data: Dictionary, part_name: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not hull_data.has("parts"):
		return out
	for part: Variant in hull_data["parts"]:
		if typeof(part) != TYPE_DICTIONARY:
			continue
		if str((part as Dictionary).get("name", "")) != part_name:
			continue
		var mesh = (part as Dictionary).get("mesh", null)
		if typeof(mesh) != TYPE_DICTIONARY:
			continue
		var raw_verts = (mesh as Dictionary).get("vertices", [])
		if typeof(raw_verts) != TYPE_ARRAY:
			continue
		var rot_deg := _read_vec3((part as Dictionary).get("rotation_degrees", [0, 0, 0]))
		var part_scale: float = float((part as Dictionary).get("scale", 1.0))
		var part_pos := _read_vec3((part as Dictionary).get("position", [0, 0, 0]))
		var part_basis := Basis.from_euler(rot_deg * (PI / 180.0))
		for i in range(0, raw_verts.size(), 3):
			if i + 2 >= raw_verts.size():
				break
			var v := Vector3(float(raw_verts[i]), float(raw_verts[i + 1]), float(raw_verts[i + 2]))
			v *= part_scale
			v = part_basis * v
			v += part_pos
			out.append(v)
		break
	return out


static func _deck_z_center(slices: Array) -> float:
	if slices.is_empty():
		return 0.0
	return (float(slices[0]["z"]) + float(slices[slices.size() - 1]["z"])) * 0.5


static func _deck_x_bounds(slices: Array) -> Vector2:
	var x_min := INF
	var x_max := -INF
	for sl: Dictionary in slices:
		x_min = minf(x_min, float(sl["x_neg"]))
		x_max = maxf(x_max, float(sl["x_pos"]))
	return Vector2(x_min, x_max)


static func _spawn_zone_label(
	parent: Node3D,
	text: String,
	pos: Vector3,
	color: Color,
	font_size: int
) -> void:
	var lbl := Label3D.new()
	lbl.name = "Label_%s" % text.replace("\n", "_")
	lbl.text = text
	lbl.font_size = font_size
	lbl.modulate = color
	lbl.outline_size = 8
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.88)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.position = pos
	parent.add_child(lbl)


static func _spawn_polygon_mesh(
	parent: Node3D,
	node_name: String,
	poly: PackedVector2Array,
	deck_y: float,
	color: Color
) -> void:
	if poly.size() < 3:
		return
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for p: Vector2 in poly:
		verts.append(Vector3(p.x, deck_y, p.y))
	for i in range(1, poly.size() - 1):
		indices.append_array([0, i, i + 1])
	if indices.is_empty():
		return
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = mesh
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)


static func _spawn_band_mesh(
	parent: Node3D,
	node_name: String,
	slices: Array,
	deck_y: float,
	x_lo: float,
	x_hi: float,
	color: Color
) -> void:
	if x_hi <= x_lo:
		return

	var verts: PackedVector3Array = []
	var indices: PackedInt32Array = []

	for i in range(slices.size() - 1):
		var a: Dictionary = slices[i]
		var b: Dictionary = slices[i + 1]
		var seg_a := _clip_x_span(float(a["x_neg"]), float(a["x_pos"]), x_lo, x_hi)
		var seg_b := _clip_x_span(float(b["x_neg"]), float(b["x_pos"]), x_lo, x_hi)
		if seg_a.is_empty() or seg_b.is_empty():
			continue
		var z_a: float = float(a["z"])
		var z_b: float = float(b["z"])
		_add_quad(
			verts, indices,
			Vector3(float(seg_a["lo"]), deck_y, z_a),
			Vector3(float(seg_a["hi"]), deck_y, z_a),
			Vector3(float(seg_b["hi"]), deck_y, z_b),
			Vector3(float(seg_b["lo"]), deck_y, z_b)
		)

	if indices.is_empty():
		return

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)

	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = mesh
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)


static func _spawn_side_trim_zones(
	root: Node3D,
	slices: Array,
	deck_y: float,
	label_y: float,
	label_fs: int
) -> void:
	var x_bounds := _deck_x_bounds(slices)
	var bow_x: float = x_bounds.x
	var stern_x: float = x_bounds.y
	if stern_x - bow_x < 0.5:
		return
	_spawn_side_trim(root, "SideTrimPort", slices, deck_y, bow_x, stern_x, true, COLOR_SIDE)
	_spawn_side_trim(root, "SideTrimStbd", slices, deck_y, bow_x, stern_x, false, COLOR_SIDE)
	var mid: Dictionary = slices[slices.size() / 2]
	var trim_x: float = maxf(float(mid["hb"]) - DEFAULT_SIDE_TRIM, float(mid["hb"]) * 0.82)
	var z_center: float = _deck_z_center(slices)
	_spawn_zone_label(
		root, "PORT", Vector3(-trim_x, label_y, z_center),
		Color(0.78, 0.86, 0.96, 0.95), maxi(label_fs - 2, 10)
	)
	_spawn_zone_label(
		root, "STBD", Vector3(trim_x, label_y, z_center),
		Color(0.78, 0.86, 0.96, 0.95), maxi(label_fs - 2, 10)
	)


static func _spawn_side_trim(
	parent: Node3D,
	node_name: String,
	slices: Array,
	deck_y: float,
	_x_lo: float,
	_x_hi: float,
	port_side: bool,
	color: Color
) -> void:
	var verts: PackedVector3Array = []
	var indices: PackedInt32Array = []
	var trim_w := DEFAULT_SIDE_TRIM

	for i in range(slices.size() - 1):
		var a: Dictionary = slices[i]
		var b: Dictionary = slices[i + 1]
		var z_a: float = float(a["z"])
		var z_b: float = float(b["z"])

		if port_side:
			var outer_a: float = float(a["x_neg"])
			var outer_b: float = float(b["x_neg"])
			var inner_a: float = clampf(outer_a + trim_w, outer_a, float(a["x_pos"]))
			var inner_b: float = clampf(outer_b + trim_w, outer_b, float(b["x_pos"]))
			if inner_a - outer_a < 0.02:
				continue
			_add_quad(
				verts, indices,
				Vector3(outer_a, deck_y, z_a), Vector3(inner_a, deck_y, z_a),
				Vector3(inner_b, deck_y, z_b), Vector3(outer_b, deck_y, z_b)
			)
		else:
			var outer_a: float = float(a["x_pos"])
			var outer_b: float = float(b["x_pos"])
			var inner_a: float = clampf(outer_a - trim_w, float(a["x_neg"]), outer_a)
			var inner_b: float = clampf(outer_b - trim_w, float(b["x_neg"]), outer_b)
			if outer_a - inner_a < 0.02:
				continue
			_add_quad(
				verts, indices,
				Vector3(inner_a, deck_y, z_a), Vector3(outer_a, deck_y, z_a),
				Vector3(outer_b, deck_y, z_b), Vector3(inner_b, deck_y, z_b)
			)

	if indices.is_empty():
		return

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)

	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = mesh
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)


static func _clip_x_span(x_neg: float, x_pos: float, band_lo: float, band_hi: float) -> Dictionary:
	var lo: float = maxf(x_neg, band_lo)
	var hi: float = minf(x_pos, band_hi)
	if hi - lo < 0.04:
		return {}
	return {"lo": lo, "hi": hi}


static func _add_quad(
	verts: PackedVector3Array,
	indices: PackedInt32Array,
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	p3: Vector3
) -> void:
	var base: int = verts.size()
	verts.append_array([p0, p1, p2, p3])
	indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
