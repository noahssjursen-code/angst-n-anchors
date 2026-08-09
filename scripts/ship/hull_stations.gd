class_name HullStations
extends Resource

## Strip-theory hull data: the hull sliced into N stations along its length, each carrying
## a cross-section profile. Built once per vessel (HullStations.from_box for box hulls, or
## from_hull_json for legacy mesh-derived profiles), then consumed by StripBuoyancyComponent
## each physics tick to compute per-station submerged area → lift force.
##
## Coordinates are ship-local metres (1 unit = 1 m). No world scale multipliers.
## −Z is bow (forward / Godot forward), +Z is stern. Y is up, X is beam (starboard +X).
##
## Each `stations[i]` is a Dictionary:
##   z       — ship-local Z position of the station (length axis)
##   section — Array[Vector2], sorted by y ascending. Each Vector2 = (y, half_beam).
##             half_beam = max |X| at this Y for the slice of hull around station Z.
##             A linear interpolation between adjacent y samples defines the section.

## Legacy mesh bake only — unused by hand-authored metre vessels.
const BODY_FRAME_Y_ROT := deg_to_rad(-90.0)

@export var stations: Array = []
@export var length_m: float = 0.0           ## bow-to-stern span (Z range)
@export var beam_m: float = 0.0             ## widest full beam in the hull
@export var height_m: float = 0.0           ## keel-bottom to deck-top
@export var keel_y: float = 0.0             ## lowest Y in the hull (ship-local)
## The FLAT BUILD PLANE, not the highest point of the hull. Sheer lifts the lofted deck
## edge above this line toward the ends (see `sheer_forward_m`); `deck_y` deliberately
## stays level so DeckGrid cells, StructurePlan offsets and colliders keep one Y.
@export var deck_y: float = 0.0
@export var displacement_volume_m3: float = 0.0  ## fully-submerged hull volume at scale 1
@export var design_draft_m: float = 0.0
@export var design_displacement_m3: float = 0.0
@export var section_fullness_exponent: float = 1.0
@export var form_id: String = ""
## Sheer: how far the lofted deck edge stands above `deck_y` at the stem / at the transom.
## Zero amidships. Set by `from_form`; see `sheer_ends()` for the derivation.
@export var sheer_forward_m: float = 0.0
@export var sheer_aft_m: float = 0.0


## ── Sheer ────────────────────────────────────────────────────────────────────────
## A working boat's deck edge is a curve, not a line: it rises toward the bow so the
## stem stays dry, and rises less toward the transom. Without it a hull reads as a barge.
##
## Sheer lives HERE, in the loft, and nowhere else:
##   • the build plane must stay flat — DeckGrid cells, StructurePlan wall/plate strips
##     and their box colliders all key off one `deck_y`, and a grid that undulates is
##     unusable to a builder and would turn every panel into a sloped prism;
##   • the loft already runs per station, so a per-station deck rise is contained to
##     this file and costs no extra surface — the shell is still one mesh, two
##     materials, and the ONLY thing that moves is the Y of section levels that were
##     already there. No new vertices, no new draw call.
## So: sheer is hull geometry, the build plane is flat, and anything that wants to
## follow the curve (bulwark cap, rail, sheer strake) asks `deck_edge_y_at(z)`.
##
## The rule, derived per hull from fields the catalog already carries — never a magic
## number per hull:
##
##     freeboard  = depth_m − draft_m
##     rise_fwd   = freeboard × form.bow_keel_rise
##     rise_aft   = freeboard × form.stern_keel_rise
##     rise(z)    = rise_end × (|z| / (L/2))²        parabolic, zero amidships
##
## Why those two: freeboard is what sheer exists to add, so it sets the scale; and
## `bow_keel_rise` / `stern_keel_rise` are already this codebase's statement of how much
## a form lifts its ends — the forefoot rise and the deck-edge rise are the same design
## axis seen from below and from above. A fine-entry trawler (0.32 / 0.10) gets a marked
## curve; a full-bodied box freighter (0.18 / 0.05) stays nearly flat, which is what those
## ships actually look like. Retuning a keel rise therefore also retunes sheer, on purpose.
## The parabola with its vertex amidships and a bow-dominant fore:aft ratio is the Load
## Line Convention's standard sheer profile.
const SHEER_BOW_KEY := "bow_keel_rise"
const SHEER_STERN_KEY := "stern_keel_rise"


## (forward, aft) deck-edge rise in metres for one hull form.
static func sheer_ends(depth_m: float, draft_m: float, form: Dictionary) -> Vector2:
	return Vector2.ZERO  ## CONTROL MUTATION
	var freeboard := maxf(depth_m - draft_m, 0.0)
	return Vector2(
		freeboard * clampf(float(form.get(SHEER_BOW_KEY, 0.2)), 0.0, 0.7),
		freeboard * clampf(float(form.get(SHEER_STERN_KEY, 0.05)), 0.0, 0.5)
	)


## Deck-edge rise above `deck_y` at ship-local Z. Bow is −Z.
func sheer_rise_at(z: float) -> float:
	var half_length := maxf(length_m * 0.5, 0.001)
	var u := clampf(absf(z) / half_length, 0.0, 1.0)
	return (sheer_forward_m if z < 0.0 else sheer_aft_m) * u * u


## Y of the lofted deck edge (top of the hull shell) at ship-local Z. This is the line a
## bulwark cap or rail should follow; `deck_y` is the flat plane bricks are placed on.
func deck_edge_y_at(z: float) -> float:
	return deck_y + sheer_rise_at(z)


## Vertical share of the sheer rise carried by a section level at height `y`. The design
## waterline and everything under it never moves, so the displacement solve is untouched;
## the topsides sweep up with the deck edge, which takes the full rise.
static func _sheer_level_share(y: float, draft: float, depth: float) -> float:
	return clampf((y - draft) / maxf(depth - draft, 0.001), 0.0, 1.0)


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


## Horizontal centroid of one submerged half-section, measured outward from
## the centerline. Integrates the piecewise-linear section exactly.
func half_section_centroid_x_below(station_idx: int, waterline_y: float) -> float:
	if station_idx < 0 or station_idx >= stations.size():
		return 0.0
	var section: Array = stations[station_idx]["section"]
	if section.size() < 2 or waterline_y <= section[0].x:
		return 0.0
	var area := 0.0
	var first_moment := 0.0
	for i in range(section.size() - 1):
		var p0: Vector2 = section[i]
		var p1: Vector2 = section[i + 1]
		if waterline_y <= p0.x:
			break
		var upper_y := minf(waterline_y, p1.x)
		var dy := upper_y - p0.x
		if dy <= 0.0:
			continue
		var segment_h := maxf(p1.x - p0.x, 1e-6)
		var t := clampf(dy / segment_h, 0.0, 1.0)
		var hb1 := lerpf(p0.y, p1.y, t)
		area += (p0.y + hb1) * 0.5 * dy
		# Integral of x over 0..half_beam is half_beam² / 2.
		first_moment += (p0.y * p0.y + p0.y * hb1 + hb1 * hb1) * dy / 6.0
		if waterline_y < p1.x:
			break
	return first_moment / area if area > 1e-6 else 0.0


func half_section_centroid_y_below(station_idx: int, waterline_y: float) -> float:
	if station_idx < 0 or station_idx >= stations.size():
		return keel_y
	var section: Array = stations[station_idx]["section"]
	if section.size() < 2 or waterline_y <= section[0].x:
		return keel_y
	var area := 0.0
	var first_moment := 0.0
	for i in range(section.size() - 1):
		var p0: Vector2 = section[i]
		var p1: Vector2 = section[i + 1]
		if waterline_y <= p0.x:
			break
		var upper_y := minf(waterline_y, p1.x)
		var dy := upper_y - p0.x
		if dy <= 0.0:
			continue
		var segment_h := maxf(p1.x - p0.x, 1e-6)
		var t := clampf(dy / segment_h, 0.0, 1.0)
		var hb1 := lerpf(p0.y, p1.y, t)
		var slope := (hb1 - p0.y) / dy
		area += (p0.y + hb1) * 0.5 * dy
		var y0 := p0.x
		var y1 := upper_y
		var square_delta := y1 * y1 - y0 * y0
		first_moment += (
			p0.y * square_delta * 0.5
			+ slope * (
				(y1 * y1 * y1 - y0 * y0 * y0) / 3.0
				- y0 * square_delta * 0.5
			)
		)
		if waterline_y < p1.x:
			break
	return first_moment / area if area > 1e-6 else keel_y


func volume_below(waterline_y: float) -> float:
	var volume := 0.0
	for i in range(stations.size()):
		volume += half_section_area_below(i, waterline_y) * 2.0 * station_length(i)
	return volume


func center_of_buoyancy_z_below(waterline_y: float) -> float:
	var volume := 0.0
	var moment := 0.0
	for i in range(stations.size()):
		var strip_volume := (
			half_section_area_below(i, waterline_y) * 2.0 * station_length(i)
		)
		volume += strip_volume
		moment += float(stations[i]["z"]) * strip_volume
	return moment / volume if volume > 1e-6 else 0.0


func waterplane_area_at(waterline_y: float) -> float:
	var area := 0.0
	for i in range(stations.size()):
		area += half_beam_at(i, waterline_y) * 2.0 * station_length(i)
	return area


## Length of hull represented by station `idx` for strip integration (m at scale 1).
## Midpoint-rule: half the distance to neighbors. Endpoints get half the distance to one neighbor.
func station_length(idx: int) -> float:
	if idx < 0 or idx >= stations.size():
		return 0.0
	var z: float = stations[idx]["z"]
	var z_prev: float = stations[idx - 1]["z"] if idx > 0 else z
	var z_next: float = stations[idx + 1]["z"] if idx < stations.size() - 1 else z
	return 0.5 * (z_next - z_prev)


## Rectangular barge stations in metres (bow −Z, stern +Z, keel y=0).
static func from_box(length_m: float, beam_m: float, depth_m: float, station_count: int = 10) -> HullStations:
	return from_pointed(length_m, beam_m, depth_m, 0.0, station_count)


## Parallel midbody with optional bow taper (bow_frac of LOA → tip at −Z).
static func from_pointed(
	length_m: float,
	beam_m: float,
	depth_m: float,
	bow_frac: float = 0.28,
	station_count: int = 10,
) -> HullStations:
	var result := HullStations.new()
	var L := maxf(length_m, 1.0)
	var B := maxf(beam_m, 1.0)
	var D := maxf(depth_m, 0.5)
	var hb := B * 0.5
	var n := maxi(station_count, 3)
	var bow_len := clampf(bow_frac, 0.0, 0.5) * L
	var tip_z := -L * 0.5
	var shoulder_z := tip_z + bow_len
	result.length_m = L
	result.beam_m = B
	result.height_m = D
	result.keel_y = 0.0
	result.deck_y = D
	var vol := 0.0
	for i in range(n):
		var t := float(i) / float(maxi(n - 1, 1))
		var z := lerpf(-L * 0.5, L * 0.5, t)
		var half := hb
		if bow_len > 0.01 and z < shoulder_z:
			## Linear taper from shoulder → tip.
			var u := inverse_lerp(tip_z, shoulder_z, z)
			half = hb * clampf(u, 0.0, 1.0)
		var section: Array = [Vector2(0.0, half), Vector2(D, half)]
		result.stations.append({"z": z, "section": section.duplicate()})
		## Trapezoid station volume approx (station spacing added below).
		vol += 2.0 * half * D
	var dz := L / float(maxi(n - 1, 1))
	result.displacement_volume_m3 = vol * dz
	return result


## Build a flared displacement hull whose integrated submerged volume at the
## declared draft exactly matches the declared displacement. The vertical
## section follows half_beam ~ (height / draft)^p below the design waterline;
## p is solved numerically against the same strip integration used at runtime.
static func from_design(
	length_m: float,
	beam_m: float,
	depth_m: float,
	draft_m: float,
	displacement_t: float,
	water_density: float = 1025.0,
	bow_frac: float = 0.2,
	station_count: int = 10,
) -> HullStations:
	var result := HullStations.new()
	var length := maxf(length_m, 1.0)
	var beam := maxf(beam_m, 1.0)
	var depth := maxf(depth_m, 0.5)
	var draft := clampf(draft_m, 0.05, depth * 0.98)
	var count := maxi(station_count, 5)
	var target_volume := maxf(displacement_t * 1000.0 / maxf(water_density, 1.0), 0.01)

	result.length_m = length
	result.beam_m = beam
	result.height_m = depth
	result.keel_y = 0.0
	result.deck_y = depth
	result.design_draft_m = draft
	result.design_displacement_m3 = target_volume

	var station_geometry: Array[Dictionary] = []
	for i in range(count):
		var t := float(i) / float(count - 1)
		var z := lerpf(-length * 0.5, length * 0.5, t)
		var taper := 1.0
		var bow_length := clampf(bow_frac, 0.0, 0.5) * length
		if bow_length > 0.001:
			var shoulder_z := -length * 0.5 + bow_length
			if z < shoulder_z:
				taper = clampf(inverse_lerp(-length * 0.5, shoulder_z, z), 0.0, 1.0)
		station_geometry.append({"z": z, "taper": taper})

	var low := 0.05
	var high := 12.0
	for _iteration in range(48):
		var exponent := (low + high) * 0.5
		_assign_design_sections(result, station_geometry, beam, depth, draft, exponent)
		var volume := result.volume_below(draft)
		if volume > target_volume:
			low = exponent
		else:
			high = exponent

	result.section_fullness_exponent = (low + high) * 0.5
	_assign_design_sections(
		result,
		station_geometry,
		beam,
		depth,
		draft,
		result.section_fullness_exponent
	)
	result.displacement_volume_m3 = result.volume_below(depth)
	return result


## Build a faceted, flared hull from one normalized form preset. The underwater
## widths are solved against declared displacement while the deck edge remains
## exactly the declared beam.
static func from_form(
	length_m: float,
	beam_m: float,
	depth_m: float,
	draft_m: float,
	displacement_t: float,
	form: Dictionary,
	water_density: float = 1025.0,
	deck_bow_taper_m: float = 0.0,
	station_count: int = 12,
) -> HullStations:
	var result := HullStations.new()
	var length := maxf(length_m, 1.0)
	var beam := maxf(beam_m, 1.0)
	var depth := maxf(depth_m, 0.5)
	var draft := clampf(draft_m, 0.05, depth * 0.98)
	var target_volume := maxf(
		displacement_t * 1000.0 / maxf(water_density, 1.0),
		0.01
	)
	var count := maxi(station_count, 7)
	result.length_m = length
	result.beam_m = beam
	result.height_m = depth
	result.keel_y = 0.0
	result.deck_y = depth
	result.design_draft_m = draft
	result.design_displacement_m3 = target_volume
	result.form_id = str(form.get("id", HullFormProfile.DEFAULT_ID))

	var low := 0.05
	var high := 1.35
	for _iteration in range(44):
		var fullness := (low + high) * 0.5
		_assign_form_sections(
			result, length, beam, depth, draft, form,
			deck_bow_taper_m, count, fullness
		)
		var volume := result.volume_below(draft)
		if volume < target_volume:
			low = fullness
		else:
			high = fullness

	result.section_fullness_exponent = (low + high) * 0.5
	_assign_form_sections(
		result, length, beam, depth, draft, form,
		deck_bow_taper_m, count, result.section_fullness_exponent
	)
	var actual := result.volume_below(draft)
	if absf(actual - target_volume) / target_volume > 0.01:
		push_warning(
			"HullStations: form '%s' cannot match %.1f t inside %.1f × %.1f × %.1f m"
			% [result.form_id, displacement_t, length, beam, draft]
		)
	result.displacement_volume_m3 = result.volume_below(depth)
	return result


static func _assign_form_sections(
	result: HullStations,
	length: float,
	beam: float,
	depth: float,
	draft: float,
	form: Dictionary,
	deck_bow_taper_m: float,
	station_count: int,
	fullness: float,
) -> void:
	result.stations.clear()
	var half_beam := beam * 0.5
	var deck_bow_length := clampf(deck_bow_taper_m, 0.0, length * 0.45)
	var underwater_bow_length := maxf(
		deck_bow_length,
		length * clampf(float(form.get("underwater_bow_fraction", 0.22)), 0.02, 0.45)
	)
	var stern_length := length * clampf(
		float(form.get("stern_taper_fraction", 0.08)), 0.0, 0.35
	)
	var chine_y := draft * clampf(
		float(form.get("chine_draft_fraction", 0.36)), 0.12, 0.85
	)
	var shoulder_y := lerpf(
		draft,
		depth,
		clampf(float(form.get("shoulder_freeboard_fraction", 0.58)), 0.1, 0.95)
	)
	var base_widths := [
		clampf(float(form.get("bottom_width", 0.5)) * fullness, 0.02, 1.0),
		clampf(float(form.get("chine_width", 0.75)) * fullness, 0.02, 1.0),
		clampf(float(form.get("waterline_width", 0.88)) * fullness, 0.02, 1.0),
		clampf(float(form.get("shoulder_width", 0.98)), 0.02, 1.0),
		1.0,
	]
	var vertical_y := [0.0, chine_y, draft, shoulder_y, depth]
	var bow_rise := depth * clampf(float(form.get("bow_keel_rise", 0.2)), 0.0, 0.7)
	var stern_rise := depth * clampf(float(form.get("stern_keel_rise", 0.05)), 0.0, 0.5)
	var stern_width := clampf(float(form.get("stern_underwater_width", 0.72)), 0.1, 1.0)
	var sheer := sheer_ends(depth, draft, form)
	result.sheer_forward_m = sheer.x
	result.sheer_aft_m = sheer.y

	for i in range(station_count):
		var t := float(i) / float(station_count - 1)
		var z := lerpf(-length * 0.5, length * 0.5, t)
		var bow_distance := z + length * 0.5
		var stern_distance := length * 0.5 - z
		var bow_keel_factor := 1.0 - smoothstep(
			0.0, maxf(underwater_bow_length, 0.001), bow_distance
		)
		var stern_keel_factor := 1.0 - smoothstep(
			0.0, maxf(stern_length, 0.001), stern_distance
		) if stern_length > 0.001 else 0.0
		var local_keel := maxf(
			bow_rise * bow_keel_factor,
			stern_rise * stern_keel_factor
		)
		local_keel = minf(local_keel, chine_y * 0.82)
		var section: Array[Vector2] = []
		for j in range(vertical_y.size()):
			var y := maxf(float(vertical_y[j]), local_keel) if j == 0 else float(vertical_y[j])
			var y_normalized := clampf(y / depth, 0.0, 1.0)
			var bow_length := lerpf(
				underwater_bow_length,
				deck_bow_length,
				smoothstep(0.45, 1.0, y_normalized)
			)
			var longitudinal := 1.0
			if bow_length > 0.001 and bow_distance < bow_length:
				longitudinal *= smoothstep(0.0, bow_length, bow_distance)
			if stern_length > 0.001 and stern_distance < stern_length:
				var stern_blend := smoothstep(0.0, stern_length, stern_distance)
				var stern_edge_width := lerpf(stern_width, 1.0, y_normalized)
				longitudinal *= lerpf(stern_edge_width, 1.0, stern_blend)
			section.append(Vector2(
				y,
				half_beam * float(base_widths[j]) * longitudinal
			))
		## Sheer, applied AFTER the widths are solved so the plan shape is untouched:
		## only the Y of levels above the design waterline moves, so the loft gains a
		## curved deck edge without gaining a vertex, a surface or a draw call.
		## The curve comes from `sheer_rise_at` so the geometry and the line that
		## consumers follow are one piece of code and cannot drift apart.
		var rise := result.sheer_rise_at(z)
		if rise > 0.0:
			for j in range(section.size()):
				var level: Vector2 = section[j]
				section[j] = Vector2(
					level.x + rise * _sheer_level_share(level.x, draft, depth),
					level.y
				)
		result.stations.append({"z": z, "section": section})


static func _assign_design_sections(
	result: HullStations,
	station_geometry: Array[Dictionary],
	beam: float,
	depth: float,
	draft: float,
	exponent: float,
) -> void:
	result.stations.clear()
	var vertical_samples := 10
	for station in station_geometry:
		var taper := float(station["taper"])
		var max_half_beam := beam * 0.5 * taper
		var section: Array[Vector2] = []
		for j in range(vertical_samples + 1):
			var t := float(j) / float(vertical_samples)
			var y := draft * t
			section.append(Vector2(y, max_half_beam * pow(t, exponent)))
		if depth > draft + 0.001:
			section.append(Vector2(depth, max_half_beam))
		result.stations.append({"z": float(station["z"]), "section": section})


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
			v = v.rotated(Vector3.UP, BODY_FRAME_Y_ROT)
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

	# 3. Resample to `target_count` evenly-spaced stations along the hull length.
	# At each station, slice nearby hull vertices into a local (y, half_beam) profile.
	# Sampling global Y curves per station left gaps (hb = 0) between valid rings and
	# severely under-estimated submerged area — ships sank far below design draft.
	var y_tol: float = 0.05 * maxf(result.height_m, 0.1)
	var z_tol: float = 0.005 * maxf(result.length_m, 0.1)
	var z_min: float = min_v.z
	var z_max: float = max_v.z
	for i in range(target_count):
		var t: float = float(i) / float(target_count - 1) if target_count > 1 else 0.5
		var z_target: float = lerpf(z_min, z_max, t)
		var z_prev: float = (
			lerpf(z_min, z_max, float(i - 1) / float(target_count - 1))
			if target_count > 1 and i > 0 else z_target
		)
		var z_next: float = (
			lerpf(z_min, z_max, float(i + 1) / float(target_count - 1))
			if target_count > 1 and i < target_count - 1 else z_target
		)
		var z_band: float = maxf(0.5 * (z_next - z_prev), z_tol * 4.0)

		var y_to_hb: Dictionary = {}
		for v in verts:
			if absf(v.z - z_target) > z_band:
				continue
			var y_key: float = roundf(v.y / y_tol) * y_tol
			var existing: float = float(y_to_hb.get(y_key, 0.0))
			y_to_hb[y_key] = maxf(existing, absf(v.x))

		var section: Array[Vector2] = []
		var y_keys: Array = y_to_hb.keys()
		y_keys.sort()
		for y_key in y_keys:
			section.append(Vector2(float(y_key), float(y_to_hb[y_key])))
		result.stations.append({"z": z_target, "section": section})

	# 6. Compute total displacement volume (sum of station full-beam area × station_length).
	# Used by BoatBody mass model to derive realistic displacement-based mass.
	var total_vol: float = 0.0
	for i in range(result.stations.size()):
		var full_area: float = result.half_section_area_below(i, result.deck_y) * 2.0
		total_vol += full_area * result.station_length(i)
	result.displacement_volume_m3 = total_vol

	return result


static func _read_vec3(arr) -> Vector3:
	if typeof(arr) != TYPE_ARRAY or arr.size() < 3:
		return Vector3.ZERO
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
