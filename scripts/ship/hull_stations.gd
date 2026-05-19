class_name HullStations
extends Resource

## Strip-theory hull data: the hull sliced into N stations along its length, each carrying
## a cross-section profile. Built once per hull at ShipBuilder time from the hull JSON's
## raw vertices, then consumed by StripBuoyancyComponent each physics tick to compute
## per-station submerged area → lift force.
##
## Coordinates are ship-local at scale 1.0. Multiply geometry by mesh_scale at runtime.
## Z axis is the length axis (+Z = bow), Y is up, X is beam.
##
## Each `stations[i]` is a Dictionary:
##   z       — ship-local Z position of the station (length axis)
##   section — Array[Vector2], sorted by y ascending. Each Vector2 = (y, half_beam).
##             half_beam = max |X| at this Y for the slice of hull around station Z.
##             A linear interpolation between adjacent y samples defines the section.

@export var stations: Array = []
@export var length_m: float = 0.0           ## bow-to-stern span (Z range)
@export var beam_m: float = 0.0             ## widest full beam in the hull
@export var height_m: float = 0.0           ## keel-bottom to deck-top
@export var keel_y: float = 0.0             ## lowest Y in the hull (ship-local)
@export var deck_y: float = 0.0             ## highest Y in the hull (ship-local)
@export var displacement_volume_m3: float = 0.0  ## fully-submerged hull volume at scale 1


## Submerged half-section area at one station, given a waterline Y in ship-local space.
## Integrates the half-beam profile from keel_y up to waterline_y. Returns m² (one side).
## Multiply by 2 for full-beam area; multiply by station's representative length for volume.
func half_section_area_below(station_idx: int, waterline_y: float) -> float:
	if station_idx < 0 or station_idx >= stations.size():
		return 0.0
	var section: Array = stations[station_idx]["section"]
	if section.size() < 2:
		return 0.0
	if waterline_y <= section[0].x:
		return 0.0

	var area: float = 0.0
	for i in range(section.size() - 1):
		var p0: Vector2 = section[i]
		var p1: Vector2 = section[i + 1]
		# p0/p1 = (y, half_beam). Trapezoid integral of half_beam(y) dy from p0.x to p1.x.
		if waterline_y >= p1.x:
			# Full segment submerged
			area += (p0.y + p1.y) * 0.5 * (p1.x - p0.x)
		elif waterline_y > p0.x:
			# Partial segment: integrate from p0.x up to waterline_y
			var t: float = (waterline_y - p0.x) / maxf(p1.x - p0.x, 1e-6)
			var hb_wl: float = lerpf(p0.y, p1.y, t)
			area += (p0.y + hb_wl) * 0.5 * (waterline_y - p0.x)
			break
		else:
			break
	return area


## Half-beam at a given Y in ship-local space for one station (used to find lift application point).
## Returns 0 if Y is outside the section profile.
func half_beam_at(station_idx: int, y_local: float) -> float:
	if station_idx < 0 or station_idx >= stations.size():
		return 0.0
	var section: Array = stations[station_idx]["section"]
	if section.size() == 0:
		return 0.0
	if y_local <= section[0].x:
		return section[0].y
	if y_local >= section[section.size() - 1].x:
		return section[section.size() - 1].y
	for i in range(section.size() - 1):
		var p0: Vector2 = section[i]
		var p1: Vector2 = section[i + 1]
		if y_local >= p0.x and y_local <= p1.x:
			var t: float = (y_local - p0.x) / maxf(p1.x - p0.x, 1e-6)
			return lerpf(p0.y, p1.y, t)
	return 0.0


## Length of hull represented by station `idx` for strip integration (m at scale 1).
## Midpoint-rule: half the distance to neighbors. Endpoints get half the distance to one neighbor.
func station_length(idx: int) -> float:
	if idx < 0 or idx >= stations.size():
		return 0.0
	var z: float = stations[idx]["z"]
	var z_prev: float = stations[idx - 1]["z"] if idx > 0 else z
	var z_next: float = stations[idx + 1]["z"] if idx < stations.size() - 1 else z
	return 0.5 * (z_next - z_prev)


## Build a HullStations resource from a hull JSON dictionary at scale 1.0.
## Algorithm: for each Y level present in the hull mesh, build a piecewise-linear
## half_beam(z) curve from vertex samples. For each target station Z, sample each
## Y level's curve independently — Z values outside a curve's range give half_beam=0,
## which correctly captures bow/stern wedge tapering (keel ends before the bow tip).
static func from_hull_json(hull_data: Dictionary, target_count: int = 10) -> HullStations:
	var result := HullStations.new()
	if not hull_data.has("parts"):
		push_warning("HullStations: hull JSON has no 'parts' key")
		return result

	# 1. Collect hull-contributing vertices in ship-local space (post-rotation, pre-scale).
	# `deck` part is a flat top — skip it (already represented by hull_upper top ring).
	var verts: Array[Vector3] = []
	for part in hull_data["parts"]:
		if typeof(part) != TYPE_DICTIONARY:
			continue
		if str(part.get("name", "")) == "deck":
			continue
		var mesh = part.get("mesh", null)
		if typeof(mesh) != TYPE_DICTIONARY:
			continue
		var raw_verts = mesh.get("vertices", [])
		if typeof(raw_verts) != TYPE_ARRAY:
			continue
		var rot_deg: Vector3 = _read_vec3(part.get("rotation_degrees", [0, 0, 0]))
		var part_scale: float = float(part.get("scale", 1.0))
		var part_pos: Vector3 = _read_vec3(part.get("position", [0, 0, 0]))
		var part_basis := Basis.from_euler(rot_deg * (PI / 180.0))
		for i in range(0, raw_verts.size(), 3):
			if i + 2 >= raw_verts.size():
				break
			var v := Vector3(float(raw_verts[i]), float(raw_verts[i + 1]), float(raw_verts[i + 2]))
			v *= part_scale
			v = part_basis * v
			v += part_pos
			verts.append(v)

	if verts.is_empty():
		push_warning("HullStations: no usable vertices in hull JSON")
		return result

	# 2. Overall bounds
	var min_v := verts[0]
	var max_v := verts[0]
	for v in verts:
		min_v = Vector3(minf(min_v.x, v.x), minf(min_v.y, v.y), minf(min_v.z, v.z))
		max_v = Vector3(maxf(max_v.x, v.x), maxf(max_v.y, v.y), maxf(max_v.z, v.z))
	result.length_m = max_v.z - min_v.z
	result.beam_m = max_v.x - min_v.x
	result.height_m = max_v.y - min_v.y
	result.keel_y = min_v.y
	result.deck_y = max_v.y

	# 3. Cluster Y values into discrete levels (typically 3: keel-bottom, mid, deck).
	var y_vals: Array = []
	for v in verts:
		y_vals.append(v.y)
	var y_tol: float = 0.05 * maxf(result.height_m, 0.1)
	var y_levels := _cluster_values(y_vals, y_tol)

	# 4. For each Y level, build a piecewise-linear (z, max_half_beam) curve.
	var z_tol: float = 0.005 * maxf(result.length_m, 0.1)
	var y_curves: Dictionary = {}  # y_level → Array[Vector2] sorted by z
	for y_lvl in y_levels:
		var z_to_hb: Dictionary = {}
		for v in verts:
			if absf(v.y - y_lvl) > y_tol:
				continue
			# Quantize Z so near-duplicate samples collapse into one entry.
			var z_key: float = roundf(v.z / z_tol) * z_tol
			var existing: float = float(z_to_hb.get(z_key, 0.0))
			z_to_hb[z_key] = maxf(existing, absf(v.x))
		var curve: Array[Vector2] = []
		for z_key in z_to_hb.keys():
			curve.append(Vector2(float(z_key), float(z_to_hb[z_key])))
		curve.sort_custom(func(a, b): return a.x < b.x)
		y_curves[y_lvl] = curve

	# 5. Resample to `target_count` evenly-spaced stations along the full hull length.
	# At each station Z, sample each Y level's curve. Y values are sorted in `y_levels`
	# (ascending after cluster sort), so the resulting section profile is keel-to-deck.
	var z_min: float = min_v.z
	var z_max: float = max_v.z
	for i in range(target_count):
		var t: float = float(i) / float(target_count - 1) if target_count > 1 else 0.5
		var z_target: float = lerpf(z_min, z_max, t)
		var section: Array[Vector2] = []
		for y_lvl in y_levels:
			var hb := _sample_curve(y_curves[y_lvl], z_target)
			section.append(Vector2(y_lvl, hb))
		result.stations.append({"z": z_target, "section": section})

	# 6. Compute total displacement volume (sum of station full-beam area × station_length).
	# Used by BoatBody mass model to derive realistic displacement-based mass.
	var total_vol: float = 0.0
	for i in range(result.stations.size()):
		var full_area: float = result.half_section_area_below(i, result.deck_y) * 2.0
		total_vol += full_area * result.station_length(i)
	result.displacement_volume_m3 = total_vol

	return result


## Linear-interpolate a (z, half_beam) curve at a target z. Returns 0 outside the curve's
## Z range (this is correct for hull geometry — the keel curve, for instance, doesn't reach
## the bow tip, so half_beam is genuinely 0 forward of the keel's bow shoulder vertex).
static func _sample_curve(curve: Array, z_target: float) -> float:
	if curve.is_empty():
		return 0.0
	if z_target < curve[0].x or z_target > curve[curve.size() - 1].x:
		return 0.0
	for i in range(curve.size() - 1):
		var p0: Vector2 = curve[i]
		var p1: Vector2 = curve[i + 1]
		if z_target >= p0.x and z_target <= p1.x:
			var t: float = (z_target - p0.x) / maxf(p1.x - p0.x, 1e-6)
			return lerpf(p0.y, p1.y, t)
	return 0.0


## Cluster a list of floats into discrete levels. Values within `tol` of the running cluster
## extent merge into the same level. Returns sorted Array of cluster mean values.
static func _cluster_values(values: Array, tol: float) -> Array:
	if values.is_empty():
		return []
	var sorted := values.duplicate()
	sorted.sort()
	var clusters: Array = []
	var current_sum: float = float(sorted[0])
	var current_count: int = 1
	var current_min: float = float(sorted[0])
	for i in range(1, sorted.size()):
		var v := float(sorted[i])
		if v - current_min <= tol:
			current_sum += v
			current_count += 1
		else:
			clusters.append(current_sum / float(current_count))
			current_sum = v
			current_count = 1
			current_min = v
	clusters.append(current_sum / float(current_count))
	return clusters


static func _read_vec3(arr) -> Vector3:
	if typeof(arr) != TYPE_ARRAY or arr.size() < 3:
		return Vector3.ZERO
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
