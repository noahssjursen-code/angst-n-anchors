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
## The FLAT BUILD PLANE **and** the ceiling of the loft. DeckGrid cells, StructurePlan
## offsets, the deck plate and the walk colliders all key off this one Y, and the lofted
## shell is guaranteed never to rise above it — see the sheer note below for why that
## guarantee is load-bearing rather than incidental.
@export var deck_y: float = 0.0
@export var displacement_volume_m3: float = 0.0  ## fully-submerged hull volume at scale 1
@export var design_draft_m: float = 0.0
@export var design_displacement_m3: float = 0.0
@export var section_fullness_exponent: float = 1.0
@export var form_id: String = ""
## Sheer: how far a bulwark cap / rail should stand above `deck_y` at the stem and at the
## transom. Zero amidships. Derived by `sheer_ends`. The loft does not lift its DECK EDGE
## by this — it carries the curve on the rubbing strake instead. See below.
@export var sheer_forward_m: float = 0.0
@export var sheer_aft_m: float = 0.0
## Index of the section level where the rubbing strake BEGINS; the band is the gap
## between `strake_level` and `strake_level + 1`. −1 on lattices that have no strake
## (`from_box`, `from_pointed`, `from_design`, `from_hull_json`). The loft NAMES the
## level rather than leaving consumers to infer one from the section size — an inferred
## index shipped once and painted the wrong band. `hull_sheer_test` reads it to hold the
## sheer curve on the band; a mesh builder that wanted to paint the band would read the
## same field rather than counting levels from the top.
@export var strake_level: int = -1


## ── Sheer: the curve lives here, the plating does not ────────────────────────────
## A working boat's deck edge is a curve, not a line: it rises toward the bow so the stem
## stays dry, and rises less toward the transom. Without it a hull reads as a barge.
##
## An earlier wave put that curve into the loft directly, by lifting the Y of every
## section level above the design waterline. It was hydrostatically clean and
## geometrically destructive, and the reason is a single sentence:
##
##     `deck_y` is not just the build plane — it is the FLOOR of four other systems'
##     geometry, and the loft is the only thing underneath it.
##
## Everything the deck carries starts exactly at `deck_y` and goes up:
##   • the deck plate       `pointed_deck_plate` fills [deck_y, deck_y + 0.1];
##   • the build plane      `DeckGrid.deck_y` = deck_y + 0.12, and every StructurePlan
##                          wall, plate strip and box collider sits on it;
##   • the walking plane    BoatBody's WalkDeck slab tops out ~deck_y + 0.23, and its
##                          WalkHullCollider stops at 0.85 × depth — far below;
##   • the buoyancy lever   StripBuoyancyComponent takes `half_beam_at(i, deck_y)` as the
##                          station's lateral lever arm.
## So the loft's headroom above the build plane is exactly **zero millimetres**. Any
## plating the loft raises above `deck_y` lands inside the deck plate, inside the plan's
## colliders, and above the walking plane with nothing on the player's mask to stop them
## — measured: 0.666 m of walk-through plating at the stem on hull_28x10, 0.90% of shell
## samples inside the deck plate over 84% of LOA, and up to 0.098 m deep inside the
## colliders of all three shipped fixtures. Control (no sheer): 0 on every one.
##
## And there is no version of the trade that survives. Plating that shows sheer in
## silhouette must be the TOPMOST thing at its station; the topmost thing is the flat
## weather deck, which cannot undulate (a grid that undulates is unusable to a builder
## and turns every panel into a sloped prism — STATE.md, still true). Anchoring the curve
## the other way, so its peak is `deck_y` and it dips amidships, keeps the shell legal
## but opens a `sheer_forward_m`-deep slot between the shell top and the deck plate along
## both sides — 0.90 m on the trawler — and closing that slot with plate thickness draws
## a band that is thickest amidships, which is sheer upside down.
##
## The thing that is allowed to stand above a flat deck, and that every real working boat
## puts there, has a name: a **bulwark**. It is drawn AND collided by the same owner —
## the StructurePlan / StructureBaker layer, which already emits oriented box colliders
## and already runs a diagonal bulwark along the stem. Sheer is that bulwark's CAP
## HEIGHT, one scalar per run, which is not a sloped grid and does not slope a panel.
##
## Therefore the split, and it is the whole decision:
##   • THE CURVE lives here, derived per hull, and is the single authority: `sheer_ends`,
##     `sheer_rise_at`, `sheer_cap_y_at`.
##   • THE DECK EDGE does not follow it. The loft tops out flat at `deck_y` on every
##     station of every hull, and `tests/hull_sheer_test.gd` holds it there.
##
## ── What that argument does NOT forbid, and did not say — corrected 2026-08-15 ────
## Everything above is about the CEILING. It was re-measured before this correction and
## every number in it still holds. But it was read, by the wave that wrote it and by the
## one after, as "a bare hull cannot show sheer", and that is a stronger claim than the
## evidence supports. The constraint is `deck_y`; it says nothing about the freeboard
## BELOW `deck_y`, which was flat because nobody had drawn anything there.
##
## So the loft now draws the curve one level down, on the RUBBING STRAKE: a band of
## constant height, standing proud of the deck edge, whose Y is
## `strake_base + band + sheer_rise_at(z)`, clamped to stay `STRAKE_MIN_CLEAR_FRACTION`
## of the freeboard under the deck edge. Nothing enters the deck plate, the plan's
## colliders or the space above the walking plane — the ceiling checks are unchanged and
## still zero — and the hull has a curve in it that a person can see. What a bare hull
## still cannot do is curve its TOP LINE; that is the bulwark cap's job and this note's
## original argument for it stands.
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
## Line Convention's standard sheer profile — and it lands on it: the Convention's
## standard forward sheer for a 28 m hull is 50 × (L/3 + 10) mm = 0.966 m; this rule gives
## 0.896 m on hull_28x10.
const SHEER_BOW_KEY := "bow_keel_rise"
const SHEER_STERN_KEY := "stern_keel_rise"

## ── Where the shape is, and where the stations were ──────────────────────────────
## Evenly-spaced stations spend their budget in the parallel midbody, where nothing
## changes, and starve the ends, where everything does. Measured before this constant
## existed: on `hull_15x5` the bow taper is 4.05 m long and contained exactly ONE
## station, so the entry, the forefoot and the stem were all resolved by a single
## vertex — which is why every hull's bow read as a blunt wedge regardless of form.
##
## `station_z` keeps the endpoints exactly on ±L/2 and pulls the interior toward
## them with a cosine, blended with the uniform spacing so the midbody still gets
## strips. `station_length`'s midpoint rule already handles uneven spacing, so the
## strip integration and the collision decomposition follow for free.
const STATION_CLUSTER := 0.65
## The strake's minimum clearance under the deck edge, as a fraction of freeboard.
const STRAKE_MIN_CLEAR_FRACTION := 0.10
## The strake band's height, as a fraction of freeboard. Constant along the hull.
const STRAKE_BAND_FRACTION := 0.16


## Ship-local Z of station `index` of `count`, clustered toward the ends.
static func station_z(index: int, count: int, length: float) -> float:
	if count <= 1:
		return 0.0
	var t := float(index) / float(count - 1)
	var clustered := 0.5 * (1.0 - cos(PI * t))
	return lerpf(-length * 0.5, length * 0.5, lerpf(t, clustered, STATION_CLUSTER))


## The station lattice for one form hull: clustered toward the ends, then with one
## station SNAPPED ONTO each longitudinal kink in the shape.
##
## The snap is what lets the loft agree with anything else. A loft is piecewise linear
## between stations, so it reproduces a straight taper exactly — but only if a station
## sits on the corner where that taper starts. Without the snap the chord cuts the
## corner and the deck edge falls INSIDE `pointed_deck_plate` by the size of the cut:
## measured on hull_15x5 at −0.3409 m per side with a straight deck taper and no snap,
## which is worse than the +0.2181 m the smoothstep used to be out by.
static func form_station_zs(
	length: float,
	count: int,
	deck_bow_length: float,
	underwater_bow_length: float,
	stern_length: float,
	stem_rake_run: float = 0.0,
) -> Array[float]:
	var zs: Array[float] = []
	for i in range(count):
		zs.append(station_z(i, count, length))
	var kinks: Array[float] = []
	## Order matters: the nearest free station is claimed per kink in this order, so the
	## stem rake — the shortest run and the one the eye reads first — gets first refusal.
	for run in [stem_rake_run, deck_bow_length, underwater_bow_length]:
		if run > 0.001 and run < length * 0.5:
			kinks.append(-length * 0.5 + run)
	if stern_length > 0.001 and stern_length < length * 0.5:
		kinks.append(length * 0.5 - stern_length)
	var claimed := {}
	for kink in kinks:
		var best := -1
		var best_d := 1e18
		for i in range(1, zs.size() - 1):
			if claimed.has(i):
				continue
			var d := absf(zs[i] - kink)
			if d < best_d:
				best_d = d
				best = i
		if best >= 0:
			zs[best] = kink
			claimed[best] = true
	zs.sort()
	return zs


## (forward, aft) sheer rise in metres for one hull form.
static func sheer_ends(depth_m: float, draft_m: float, form: Dictionary) -> Vector2:
	var freeboard := maxf(depth_m - draft_m, 0.0)
	return Vector2(
		freeboard * clampf(float(form.get(SHEER_BOW_KEY, 0.2)), 0.0, 0.7),
		freeboard * clampf(float(form.get(SHEER_STERN_KEY, 0.05)), 0.0, 0.5)
	)


## Sheer rise above `deck_y` at ship-local Z. Bow is −Z.
func sheer_rise_at(z: float) -> float:
	var half_length := maxf(length_m * 0.5, 0.001)
	var u := clampf(absf(z) / half_length, 0.0, 1.0)
	return (sheer_forward_m if z < 0.0 else sheer_aft_m) * u * u


## Y a bulwark cap, rail or sheer strake should reach at ship-local Z.
##
## This is deliberately NOT the top of the hull shell — the shell tops out flat at
## `deck_y`, and the geometry that follows this curve has to be built by whoever can also
## collide it. Named `sheer_cap_y_at` rather than `deck_edge_y_at` for exactly that
## reason: a name that claimed to describe the loft would be a lie the loft does not tell.
func sheer_cap_y_at(z: float) -> float:
	return deck_y + sheer_rise_at(z)


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
	## The caller's count is respected. Raising the floor to 12 was tried and MEASURED:
	## it cost `plan_collision_physics_test` its 240 s budget (118 s -> TIMEOUT) and put
	## `deck_fitout_load_bench` 2.3x over its staged-frame budget, for a shape the kink
	## snapping in `form_station_zs` already resolves at 8. Spend the stations you have
	## where the shape is; do not buy more.
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
	## THE RUBBING STRAKE — a band of CONSTANT height that the sheer curve moves bodily.
	##
	## Two levels, not one, and that is the whole reason it works. With a single level the
	## band ran from the strake to the flat deck edge, so its height WAS the sheer rise:
	## fat amidships, thin at the ends, which is a wedge and reads as reverse sheer. With
	## two the band keeps its height and slides, and what curves is a stripe rather than a
	## taper. Rendered both on hull_15x5 — v7 and v8 of this change.
	##
	## `shoulder_freeboard_fraction` places the band's bottom, `shoulder_width` is how far
	## it stands PROUD of the deck edge. That field used to be clamped to 1.0, i.e. inboard
	## of the deck, which draws nothing: a panel that flares outward going up and another
	## panel that flares outward going up have the same normal, so both sides of the
	## "knuckle" shaded identically. Measured on hull_15x5 at 0.96 and again at 0.88 — two
	## renders, no visible difference. Above 1.0 there is flare below the band and
	## tumblehome above it, which is two normals a light can tell apart.
	var freeboard := maxf(depth - draft, 0.0)
	var strake_base_y := lerpf(
		draft,
		depth,
		clampf(float(form.get("shoulder_freeboard_fraction", 0.58)), 0.1, 0.95)
	)
	var strake_band := maxf(freeboard * STRAKE_BAND_FRACTION, 0.03)
	var strake_proud := clampf(float(form.get("shoulder_width", 0.98)), 0.02, 1.15)
	var base_widths := [
		clampf(float(form.get("bottom_width", 0.5)) * fullness, 0.02, 1.0),
		clampf(float(form.get("chine_width", 0.75)) * fullness, 0.02, 1.0),
		clampf(float(form.get("waterline_width", 0.88)) * fullness, 0.02, 1.0),
		strake_proud,
		strake_proud,
		1.0,
	]
	var bow_rise := depth * clampf(float(form.get("bow_keel_rise", 0.2)), 0.0, 0.7)
	var stern_rise := depth * clampf(float(form.get("stern_keel_rise", 0.05)), 0.0, 0.5)
	var stern_width := clampf(float(form.get("stern_underwater_width", 0.72)), 0.1, 1.0)
	var sheer := sheer_ends(depth, draft, form)
	result.sheer_forward_m = sheer.x
	result.sheer_aft_m = sheer.y
	## The strake never merges with the deck edge, however hard the sheer pushes: a band
	## that closed to zero at the stem would read as a crease running INTO the deck edge
	## rather than sweeping parallel to it.
	var strake_clear := maxf((depth - draft) * STRAKE_MIN_CLEAR_FRACTION, 0.04)

	var station_zs := form_station_zs(
		length, station_count, deck_bow_length, underwater_bow_length, stern_length,
		bow_rise
	)
	for i in range(station_zs.size()):
		var z := station_zs[i]
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
		## THE STEM LINE — the hull's forward edge in PROFILE. Everything below it at
		## this station is outside the hull, so those levels collapse onto it and the
		## silhouette's front edge rakes aft as it goes down.
		##
		## Zeroing the half-beam alone was NOT enough and this is the whole trap: a
		## level at its nominal Y with `half_beam == 0` still puts a VERTEX at
		## z = −L/2, so the projected outline still reached the tip at every height and
		## the stem rendered exactly plumb. Measured on hull_15x5 — v1 of this change
		## raked the widths and left the profile picture unchanged. The Y has to move.
		var stem_floor := depth * (1.0 - clampf(bow_distance / maxf(bow_rise, 0.001), 0.0, 1.0))
		var section_floor := maxf(local_keel, stem_floor)
		## THE SHEER, DRAWN. The strake band is the part of the freeboard that is free to
		## move, and it carries `sheer_rise_at` — the curve this file has derived and never
		## used. It sweeps up at both ends, bow-dominant, and stays under the deck edge, so
		## the loft still tops out flat on the build plane and nothing above it moves.
		var strake_top := clampf(
			strake_base_y + strake_band + result.sheer_rise_at(z),
			draft + 0.02,
			depth - strake_clear
		)
		var strake_bottom := clampf(strake_top - strake_band, draft + 0.01, strake_top - 0.01)
		var vertical_y := [0.0, chine_y, draft, strake_bottom, strake_top, depth]
		result.strake_level = 3
		var section: Array[Vector2] = []
		for j in range(vertical_y.size()):
			var y := maxf(float(vertical_y[j]), section_floor)
			var y_normalized := clampf(y / depth, 0.0, 1.0)
			## THE STEM RAKE — the hull's forward extremity at this height, set back
			## from the deck-level stem. Zero at the deck edge, `bow_rise` at the keel,
			## linear between: the stem and the forefoot are cut away by the same
			## number, so a form that lifts its forefoot also rakes its stem.
			##
			## The transom does NOT get the mirror treatment. The stern taper reaches
			## `stern_underwater_width`, never zero, because the aft station IS the
			## transom face; setting it back the same way zeroes that station and turns
			## every hull in the fleet into a double-ender. Measured, then reverted.
			var stem_setback := bow_rise * (1.0 - y_normalized)
			var raked_bow := bow_distance - stem_setback
			var bow_length := maxf(
				lerpf(
					underwater_bow_length,
					deck_bow_length,
					smoothstep(0.45, 1.0, y_normalized)
				) - stem_setback,
				0.001
			)
			var longitudinal := 1.0
			if raked_bow <= 0.0:
				longitudinal = 0.0
			elif raked_bow < bow_length:
				## The entry blends from an S-curve underwater to a STRAIGHT chamfer at
				## the deck edge, and the straight half is not a taste decision — it is
				## the §3b fix. `pointed_deck_plate` and `DeckGrid.cell_shape` both cut
				## the bow with a linear 45 degree chamfer over `bow_taper_m`; the loft
				## cut it with a smoothstep over the same interval, and a straight line
				## and an S-curve over one interval cannot agree. Measured worst
				## disagreement at the deck edge, shell minus plate, per side:
				## hull_15x5 +0.2181 m and hull_28x10 +0.4788 m before this line.
				## A linear deck-level taper is also reproduced EXACTLY by the loft's
				## own piecewise-linear interpolation between stations, so the residual
				## is only the corner the chord cuts at the chamfer shoulder.
				var raw := clampf(raked_bow / bow_length, 0.0, 1.0)
				longitudinal *= lerpf(
					smoothstep(0.0, 1.0, raw), raw, smoothstep(0.45, 1.0, y_normalized)
				)
			if stern_length > 0.001 and stern_distance < stern_length:
				var stern_blend := smoothstep(0.0, stern_length, stern_distance)
				var stern_edge_width := lerpf(stern_width, 1.0, y_normalized)
				longitudinal *= lerpf(stern_edge_width, 1.0, stern_blend)
			section.append(Vector2(
				y,
				half_beam * float(base_widths[j]) * longitudinal
			))
		## No sheer is applied to the TOP level, and that is a decision, not an
		## omission — see the sheer note at the top of this file. The top level stays at
		## exactly `depth` on every station so that `deck_y` remains both the flat build
		## plane and the ceiling of the loft: nothing this file emits may enter the deck
		## plate, the plan's colliders or the space above the walking plane. The curve is
		## drawn one level down, where it costs nothing and reaches nothing.
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
