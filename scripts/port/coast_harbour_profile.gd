class_name CoastHarbourProfile
extends RefCounted

## Site-driven harbour plan: a chain of shore-wall sections along the coast,
## with piers sprouting into the water where locals built them.
##
## Uses CoastalPortPlacer's measured quay_half_length_m when available so tight
## coves get short walls and open bays get long ones.

const SEGMENT_LENGTH_M := 32.0


static func site_quay_half_m(definition: PortDefinition) -> float:
	if definition.site_quay_half_m > 0.0:
		return definition.site_quay_half_m
	var size := PortSizing.normalized_size(definition.size)
	return PortSizing.quay_half_length_m(size) * 0.55


static func derive(
		definition: PortDefinition,
		families: Array[String],
		site_seed: int,
) -> Dictionary:
	var size := PortSizing.normalized_size(definition.size)
	var quay_half := site_quay_half_m(definition)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site_seed) ^ 0x434F4153 ^ (size * 7919)

	var max_segments := clampi(1 + size / 2, 1, 6)
	var along_span := clampf(quay_half * 2.0, SEGMENT_LENGTH_M * 0.85, SEGMENT_LENGTH_M * float(max_segments))
	var segment_count := clampi(ceili(along_span / SEGMENT_LENGTH_M), 1, max_segments)
	segment_count = maxi(
		segment_count,
		clampi(1 + PortSizing.berth_count(size) / 2, 1, max_segments),
	)

	var styles := _style_pool(size, quay_half, definition.region_kind)
	var style := str(styles[rng.randi_range(0, styles.size() - 1)])

	var yaw_deltas: Array[float] = []
	for index in range(segment_count):
		yaw_deltas.append(_segment_yaw_delta(style, index, segment_count, rng))

	var berth_target := PortSizing.berth_count(size)
	var arm_families := PortSizing.assign_families_to_arms(
		families,
		berth_target,
		_liquid_morphology(style),
		site_seed,
	)
	var pier_specs: Array[Dictionary] = []
	var pier_use: Array[int] = []
	for _i in range(segment_count):
		pier_use.append(0)

	for berth_index in range(berth_target):
		var segment_index := _pick_segment_index(segment_count, berth_index, style, rng)
		var slot_id := "pier_a" if pier_use[segment_index] % 2 == 0 else "pier_b"
		pier_use[segment_index] += 1
		var length_m := _pier_length_m(size, berth_index, berth_target, style, rng)
		pier_specs.append({
			"segment_index": segment_index,
			"slot_id": slot_id,
			"length_m": length_m,
			"yaw_offset_deg": _pier_yaw_offset(style, segment_index, berth_index, rng),
			"family": arm_families[berth_index] if berth_index < arm_families.size() else "general",
			"berth_index": berth_index,
		})

	_scale_pier_lengths_to_contract(pier_specs, size)

	return {
		"style": style,
		"style_display": style_display_name(style),
		"segment_count": segment_count,
		"segment_yaw_deltas": yaw_deltas,
		"quay_half_m": quay_half,
		"along_span_m": float(segment_count) * SEGMENT_LENGTH_M,
		"piers": pier_specs,
	}


static func style_display_name(style: String) -> String:
	match style:
		"straight_wharf":
			return "Straight wharf"
		"cove":
			return "Cove harbour"
		"dogleg":
			return "Dog-leg bend"
		"spread_marina":
			return "Marina spread"
		"industrial_tongue":
			return "Industrial tongue"
		_:
			return style.replace("_", " ").capitalize()


static func _liquid_morphology(style: String) -> String:
	return "liquid_jetty" if style == "industrial_tongue" else "solo_jetty"


static func _style_pool(size: int, quay_half_m: float, region: PortDefinition.RegionKind) -> PackedStringArray:
	var pool := PackedStringArray(["straight_wharf", "cove", "spread_marina"])
	if quay_half_m >= 80.0 or size >= 4:
		pool.append("dogleg")
	if size >= 5:
		pool.append("industrial_tongue")
	if region == PortDefinition.RegionKind.FJORD:
		pool.append("cove")
	return pool


static func _segment_yaw_delta(
		style: String,
		index: int,
		segment_count: int,
		rng: RandomNumberGenerator,
) -> float:
	if index == 0:
		return 0.0
	match style:
		"cove":
			return -rng.randf_range(5.0, 13.0)
		"dogleg":
			if index == segment_count / 2:
				return rng.randf_range(28.0, 42.0)
			return 0.0
		"spread_marina":
			return rng.randf_range(-4.0, 4.0)
		"industrial_tongue":
			if index == segment_count - 1:
				return rng.randf_range(-6.0, 6.0)
			return 0.0
		_:
			return 0.0


static func _pick_segment_index(
		segment_count: int,
		berth_index: int,
		style: String,
		rng: RandomNumberGenerator,
) -> int:
	if segment_count <= 1:
		return 0
	match style:
		"spread_marina":
			return berth_index % segment_count
		"industrial_tongue":
			if berth_index == 0:
				return segment_count - 1
			return rng.randi_range(0, segment_count - 2)
		_:
			return clampi(
				int(round(float(berth_index) / maxf(float(PortSizing.berth_count(4) - 1), 1.0) * float(segment_count - 1))),
				0,
				segment_count - 1,
			)


static func _pier_length_m(
		size: int,
		berth_index: int,
		berth_total: int,
		style: String,
		rng: RandomNumberGenerator,
) -> float:
	var loa := PortSizing.design_hull_loa_m(size)
	var berth := PortSizing.slot_width_m(size)
	var max_seg := float(PortSizing.max_quay_segments_per_arm(size))
	var ratio := 1.0
	match style:
		"spread_marina":
			ratio = [1.35, 0.85, 1.1, 0.7][berth_index % 4]
		"industrial_tongue":
			ratio = 1.45 if berth_index == 0 else 0.95
		"cove":
			ratio = 1.2 if berth_index % 2 == 0 else 0.78
		_:
			ratio = 1.0 + float(berth_index % 3) * 0.18
	ratio *= rng.randf_range(0.96, 1.04)
	if size >= 6:
		ratio *= 1.22
	var target_berths := clampf(1.0 + ratio * 1.1, 1.0, max_seg)
	var target := target_berths * berth
	target = clampf(target, loa * 1.05, loa * 2.4)
	return minf(target, max_seg * berth)


static func _scale_pier_lengths_to_contract(pier_specs: Array[Dictionary], size: int) -> void:
	if pier_specs.is_empty():
		return
	var contract := PortSizing.dock_length_m(size) * 0.88
	var loa := PortSizing.design_hull_loa_m(size)
	var max_arm := float(PortSizing.max_quay_segments_per_arm(size)) * PortSizing.slot_width_m(size)
	var total := 0.0
	for spec in pier_specs:
		total += float(spec.get("length_m", 0.0))
	if total >= contract:
		return
	var scale := contract / maxf(total, 1.0)
	for spec in pier_specs:
		var scaled := float(spec.get("length_m", 0.0)) * scale
		spec["length_m"] = clampf(scaled, loa * 1.05, max_arm)


static func _pier_yaw_offset(
		style: String,
		_segment_index: int,
		berth_index: int,
		rng: RandomNumberGenerator,
) -> float:
	match style:
		"spread_marina":
			return [-14.0, 0.0, 12.0, -8.0][berth_index % 4]
		"cove":
			return rng.randf_range(-8.0, 8.0)
		_:
			return 0.0
