class_name PortBerthPlan
extends RefCounted

## Plans docking stations from trade slots.
## Every current vessel-facing trade receives a generated quay finger. The
## asphalt mode remains only as a compatibility path for older layout records.

const CoastTracer := preload("res://scripts/port/port_coast_tracer.gd")
const CoastalPortPlacer := preload("res://scripts/world/coastal_port_placer.gd")
const FishLandingLayout := preload("res://scripts/port/fish_landing_layout.gd")

const MODE_ASPHALT := "asphalt"
const MODE_QUAY := "quay"
## Keep a working pocket past the pier tip so ships are not pinned against land.
const ARM_WATER_TAIL_M := 28.0
const BASIN_PROBE_MAX_M := 480.0


## Compatibility hook for older layout records; current commodities return false.
static func uses_asphalt_dock(commodity_id: String) -> bool:
	return CommodityCatalog.uses_asphalt_dock(commodity_id)


static func dock_mode_for_commodity(commodity_id: String) -> String:
	return MODE_ASPHALT if uses_asphalt_dock(commodity_id) else MODE_QUAY


## Measures open-water envelope for this harbour pocket.
## Soft-clamps pier length from seaward clearance — must never starve pier
## count or rewrite the live size ceiling mid-build.
static func measure_basin(
		layout: WorldLayout,
		definition: PortDefinition,
		foundation: Dictionary,
) -> Dictionary:
	var dock_face := _polyline_from_array(foundation.get("dock_face_polyline", []) as Array)
	if dock_face.size() < 2:
		dock_face = _polyline_from_array(foundation.get("spine", []) as Array)
	var seaward_local := _consensus_seaward(dock_face)
	var along_local := Vector2(-seaward_local.y, seaward_local.x)
	if along_local.dot(Vector2(1.0, 0.0)) < 0.0:
		along_local = -along_local
	var region_kind := int(definition.region_kind) if definition != null \
			else int(PortDefinition.RegionKind.MAINLAND)
	var port_origin := definition.world_position if definition != null else Vector3.ZERO
	var port_yaw := definition.rotation_y if definition != null else 0.0
	var placed_max := PortSizing.MAX_SIZE
	if definition != null:
		placed_max = clampi(definition.site_max_size, PortSizing.MIN_SIZE, PortSizing.MAX_SIZE)
	var seaward_world := CoastTracer.port_local_dir_to_world(seaward_local, port_yaw)
	var along_world := CoastTracer.port_local_dir_to_world(along_local, port_yaw)
	if seaward_world.length_squared() < 0.25:
		seaward_world = seaward_local
	if along_world.length_squared() < 0.25:
		along_world = along_local
	var samples := _sample_face(dock_face, 10.0) if dock_face.size() >= 2 else []
	var seaward_min := BASIN_PROBE_MAX_M
	var across_min := BASIN_PROBE_MAX_M
	var wet_span_m := 0.0
	var wet_count := 0
	if layout != null and not samples.is_empty():
		var wet_proj_min := INF
		var wet_proj_max := -INF
		for sample in samples:
			var local_origin: Vector2 = sample["position"]
			var world_origin := CoastTracer.port_local_to_world(local_origin, port_origin, port_yaw)
			var clear := CoastalPortPlacer.seaward_water_clearance_m(
				layout, world_origin, seaward_world, BASIN_PROBE_MAX_M
			)
			if clear < 36.0:
				continue
			wet_count += 1
			seaward_min = minf(seaward_min, clear)
			var across := CoastalPortPlacer.across_water_clearance_m(
				layout,
				world_origin + seaward_world * minf(clear * 0.35, 40.0),
				along_world,
				320.0,
			)
			across_min = minf(across_min, across)
			var proj: float = sample["proj"]
			wet_proj_min = minf(wet_proj_min, proj)
			wet_proj_max = maxf(wet_proj_max, proj)
		if wet_count >= 2:
			wet_span_m = maxf(wet_proj_max - wet_proj_min, 0.0)
		elif wet_count == 1:
			wet_span_m = PortSizing.quay_deck_width_m(0)
		elif not samples.is_empty():
			var best_clear := 0.0
			for sample in samples:
				var local_origin: Vector2 = sample["position"]
				var world_origin := CoastTracer.port_local_to_world(
					local_origin, port_origin, port_yaw
				)
				best_clear = maxf(
					best_clear,
					CoastalPortPlacer.seaward_water_clearance_m(
						layout, world_origin, seaward_world, BASIN_PROBE_MAX_M
					),
				)
			seaward_min = best_clear
			across_min = 0.0
	elif samples.is_empty():
		seaward_min = BASIN_PROBE_MAX_M if layout == null else 0.0
		across_min = BASIN_PROBE_MAX_M if layout == null else 0.0
	if seaward_min >= BASIN_PROBE_MAX_M - 0.01:
		seaward_min = BASIN_PROBE_MAX_M if layout == null or wet_count > 0 else 0.0
	if across_min >= BASIN_PROBE_MAX_M - 0.01:
		across_min = BASIN_PROBE_MAX_M if layout == null or wet_count > 0 else 0.0

	var probe_failed := layout != null and wet_count == 0
	var max_arm_m := INF
	var tightness := 0.0
	var site_max_size := placed_max
	if not probe_failed and layout != null:
		max_arm_m = maxf(seaward_min - ARM_WATER_TAIL_M, 0.0)
		if seaward_min < 220.0:
			tightness = maxf(tightness, 1.0 - seaward_min / 220.0)
		if across_min < 90.0:
			tightness = maxf(tightness, 1.0 - across_min / 90.0)
		if region_kind == int(PortDefinition.RegionKind.FJORD):
			tightness = maxf(tightness, 0.15)
			max_arm_m *= lerpf(1.0, 0.88, tightness)
		## Geography hint for HUD only — never raise above the expander ceiling,
		## and never invent TRADE_COMPLETE headroom the arm budget cannot support.
		var arm_size := PortSizing.max_size_for_arm_budget_m(max_arm_m)
		site_max_size = clampi(mini(placed_max, arm_size), PortSizing.MIN_SIZE, PortSizing.MAX_SIZE)
	return {
		"region_kind": region_kind,
		"seaward_clear_m": seaward_min,
		"across_clear_m": across_min,
		"wet_span_m": wet_span_m,
		"max_arm_m": max_arm_m,
		"site_max_size": site_max_size,
		"tightness": tightness,
		"has_layout": layout != null,
		"probe_failed": probe_failed,
	}


static func build(
		profile: PortTradeProfile,
		size: int,
		foundation: Dictionary,
		site_seed: int,
		layout: WorldLayout = null,
		definition: PortDefinition = null,
) -> Dictionary:
	var n := PortSizing.normalized_size(size)
	var asphalt_slots: Array = []
	var quay_families: Dictionary = {} ## family → {family, trade_slots, mode}

	_collect_slot(profile.export_slots if profile != null else [], "export", asphalt_slots, quay_families)
	_collect_slot(profile.import_slots if profile != null else [], "import", asphalt_slots, quay_families)

	var quay_list: Array = []
	for family in quay_families:
		quay_list.append(quay_families[family])

	## Stable order: liquid first, then by family name.
	quay_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var fa := str(a.get("family", ""))
		var fb := str(b.get("family", ""))
		if fa == "liquid" and fb != "liquid":
			return true
		if fb == "liquid" and fa != "liquid":
			return false
		return fa < fb
	)

	var basin: Dictionary = foundation.get("basin", {}) as Dictionary
	if basin.is_empty():
		basin = measure_basin(layout, definition, foundation)
	## Place every unlocked pad. Destiny is already trimmed to ≤3 quay groups.
	var development := definition != null and definition.development_facilities
	if not development:
		quay_list = _cap_quay_families(quay_list, n)
	asphalt_slots = _merge_asphalt_slots(asphalt_slots)

	var dock_face := _polyline_from_array(foundation.get("dock_face_polyline", []) as Array)
	if dock_face.size() < 2:
		dock_face = _polyline_from_array(foundation.get("spine", []) as Array)

	var seaward := _consensus_seaward(dock_face)
	var reserved_min := NAN
	var reserved_max := NAN
	if development:
		var along := Vector2(-seaward.y, seaward.x)
		if along.x < 0: along = -along
		reserved_min = INF
		reserved_max = -INF
		for point in dock_face:
			reserved_min = minf(reserved_min, point.dot(along))
			reserved_max = maxf(reserved_max, point.dot(along))
		# Preserve an unobstructed passenger terminal and reverse-out pocket.
		reserved_min += DevelopmentHarbour.PASSENGER_FRONTAGE_M
	## Quays take the full comb first; apron berths pack into free face arcs after.
	var quay_stations := _place_quays(
		quay_list,
		dock_face,
		n,
		site_seed,
		basin,
		layout,
		definition,
		reserved_min,
		reserved_max,
	)
	var asphalt_stations := _place_asphalt_on_face(
		asphalt_slots,
		dock_face,
		n,
		quay_stations,
	)
	var notes := _notes(asphalt_slots, quay_stations)
	var site_max := int(basin.get("site_max_size", PortSizing.MAX_SIZE))
	if site_max < PortSizing.MAX_SIZE:
		notes.append("site max size %d — harbour pocket limits growth" % site_max)
	if float(basin.get("tightness", 0.0)) > 0.35 and not bool(basin.get("probe_failed", false)):
		notes.append("basin tight — pier length shortened to open water")
	if not asphalt_stations.is_empty():
		notes.append("apron berths hug dock face with local edge orientation")

	var apron_arc_lo := INF
	var apron_arc_hi := -INF
	for raw in asphalt_stations:
		var arc := float((raw as Dictionary).get("arc_m", 0.0))
		var half := float((raw as Dictionary).get("length_m", 0.0)) * 0.5
		apron_arc_lo = minf(apron_arc_lo, arc - half)
		apron_arc_hi = maxf(apron_arc_hi, arc + half)
	if apron_arc_lo > apron_arc_hi:
		apron_arc_lo = 0.0
		apron_arc_hi = 0.0

	var quay_berth_faces := 0
	for raw in quay_stations:
		quay_berth_faces += int((raw as Dictionary).get("berth_faces", 1))
	return {
		"asphalt_stations": asphalt_stations,
		"quay_stations": quay_stations,
		"asphalt_slot_count": asphalt_stations.size(),
		"quay_count": quay_berth_faces,
		"seaward_dir": [seaward.x, seaward.y],
		"apron_district": {
			"arc_lo": apron_arc_lo,
			"arc_hi": apron_arc_hi,
		},
		"basin": basin,
		"notes": notes,
	}


static func _collect_slot(
		slots: Array,
		role: String,
		asphalt_slots: Array,
		quay_families: Dictionary,
) -> void:
	for raw in slots:
		var commodity_id := str(raw)
		if commodity_id.is_empty():
			continue
		if uses_asphalt_dock(commodity_id):
			asphalt_slots.append({
				"commodity_id": commodity_id,
				"role": role,
				"family": CommodityCatalog.commodity_terminal_family(commodity_id),
				"mode": MODE_ASPHALT,
			})
			continue
		var family := CommodityCatalog.commodity_terminal_family(commodity_id)
		## One pad per commodity direction — never iron+coal, never export+import on one apron.
		var group_id := CommodityCatalog.berth_group_id(commodity_id, role)
		if not quay_families.has(group_id):
			quay_families[group_id] = {
				"family": family,
				"group_id": group_id,
				"trade_slots": [],
				"mode": MODE_QUAY,
			}
		var entry: Dictionary = quay_families[group_id]
		var trade_slots: Array = entry["trade_slots"]
		var already := false
		for existing in trade_slots:
			if str(existing.get("commodity_id", "")) == commodity_id \
					and str(existing.get("role", "")) == role:
				already = true
				break
		if already:
			continue
		trade_slots.append({
			"commodity_id": commodity_id,
			"role": role,
			"family": family,
		})


static func _place_quays(
		quay_list: Array,
		dock_face: PackedVector2Array,
		size: int,
		site_seed: int,
		basin: Dictionary = {},
		layout: WorldLayout = null,
		definition: PortDefinition = null,
		proj_lo: float = NAN,
		proj_hi: float = NAN,
) -> Array:
	var out: Array = []
	if quay_list.is_empty() or dock_face.size() < 2:
		return out
	var count := quay_list.size()
	## Two ordinary trade pads may share one pier. A fish landing never does:
	## its approved pump/tank composition needs a dedicated full-width quay.
	if count == 2 and not _quay_list_contains_family(quay_list, "fishing"):
		var twin := _place_twin_quay(
			quay_list, dock_face, size, site_seed, basin, layout, definition, proj_lo, proj_hi
		)
		if not twin.is_empty():
			out.append(twin)
			return out
	var max_arm_m := float(basin.get("max_arm_m", INF))
	var lengths := PortSizing.arm_target_lengths_m(size, "solo_jetty", count)
	## One shared seaward heading — parallel fingers never converge on a bend.
	var seaward := _consensus_seaward(dock_face)
	var along := Vector2(-seaward.y, seaward.x)
	if along.dot(Vector2(1.0, 0.0)) < 0.0:
		along = -along
	var port_origin := definition.world_position if definition != null else Vector3.ZERO
	var port_yaw := definition.rotation_y if definition != null else 0.0
	var seaward_world := CoastTracer.port_local_dir_to_world(seaward, port_yaw)
	if seaward_world.length_squared() < 0.25:
		seaward_world = seaward
	var face_samples := _sample_face(dock_face, 6.0)
	if face_samples.is_empty():
		return out
	var soft_cap := layout != null and not bool(basin.get("probe_failed", false)) \
			and is_finite(max_arm_m)
	## Width follows runnable length — never fatten a pier the basin shortened.
	var width_size := size
	if soft_cap:
		width_size = mini(size, PortSizing.max_size_for_arm_budget_m(max_arm_m))
	var deck_w := PortSizing.quay_deck_width_m(width_size)
	if _quay_list_contains_family(quay_list, "fishing"):
		## Reserve enough comb spacing for the exact 72 m showcase arrangement,
		## even when neighbouring commodity quays are narrower.
		deck_w = maxf(deck_w, FishLandingLayout.REFERENCE_QUAY_WIDTH_M)
	var proj_min := INF
	var proj_max := -INF
	for sample in face_samples:
		var proj: float = sample["proj"]
		proj_min = minf(proj_min, proj)
		proj_max = maxf(proj_max, proj)
	## Optional apron-district reservation shrinks the quay comb span.
	if is_finite(proj_lo) and is_finite(proj_hi) and proj_hi > proj_lo + 1.0:
		proj_min = maxf(proj_min, proj_lo)
		proj_max = minf(proj_max, proj_hi)
	var margin := minf((proj_max - proj_min) * 0.08, 28.0)
	var span := maxf(proj_max - proj_min - margin * 2.0, deck_w)
	## Ideal fairway spacing; compress only enough to fit every family without overlap.
	var fairway := PortSizing.parallel_pier_center_spacing_m(width_size)
	var min_spacing := deck_w + maxf(PortSizing.design_hull_beam_m(width_size) * 0.35, 10.0)
	var spacing := fairway
	if count > 1:
		spacing = minf(fairway, span / float(count - 1))
		spacing = maxf(spacing, min_spacing)
	for index in range(count):
		var family_info: Dictionary = quay_list[index]
		var trade_slots: Array = (family_info.get("trade_slots", []) as Array).duplicate(true)
		if trade_slots.is_empty():
			## Legacy fallback from older family dicts.
			for commodity in family_info.get("commodities", []) as Array:
				trade_slots.append({
					"commodity_id": str(commodity),
					"role": "trade",
					"family": str(family_info.get("family", "general")),
				})
		var zones := _build_commodity_zones(trade_slots)
		var target_proj := (proj_min + proj_max) * 0.5
		if count > 1:
			var comb_span := spacing * float(count - 1)
			var start := (proj_min + proj_max) * 0.5 - comb_span * 0.5
			start = clampf(start, proj_min + margin * 0.25, proj_max - margin * 0.25 - comb_span)
			target_proj = start + spacing * float(index)
		var snap := _snap_to_face_proj(face_samples, target_proj)
		var origin: Vector2 = snap.get("position", Vector2.ZERO)
		## Length is the size signal: target grows with harbour size / zone count.
		var length_m := float(lengths[index]) if index < lengths.size() else float(lengths[0])
		length_m = maxf(length_m, PortSizing.min_quay_length_m(size, zones.size()))
		var local_clear := max_arm_m if soft_cap else length_m
		var arm_budget := length_m
		if soft_cap:
			var world_origin := CoastTracer.port_local_to_world(origin, port_origin, port_yaw)
			local_clear = CoastalPortPlacer.seaward_water_clearance_m(
				layout, world_origin, seaward_world, BASIN_PROBE_MAX_M
			)
			arm_budget = minf(max_arm_m, maxf(local_clear - ARM_WATER_TAIL_M, 0.0))
			if arm_budget > 0.0:
				length_m = minf(length_m, arm_budget)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(site_seed) ^ str(family_info.get("family", "")).hash() ^ (index * 7919)
		length_m *= rng.randf_range(0.98, 1.02)
		if soft_cap and arm_budget > 0.0:
			length_m = minf(length_m, arm_budget)
		length_m = maxf(length_m, 24.0)
		## Per-pier width from actual runnable length (not the uncapped size table).
		var pier_w := PortSizing.quay_deck_width_for_arm_m(length_m, size)
		if str(family_info.get("family", "")) == "fishing":
			pier_w = maxf(pier_w, FishLandingLayout.REFERENCE_QUAY_WIDTH_M)
		var tip := origin + seaward * length_m
		var yard := PortSizing.cargo_yard_size_m(mini(size, PortSizing.max_size_for_arm_budget_m(length_m)))
		var commodities: Array = []
		var roles: Array = []
		for slot in trade_slots:
			var cid := str(slot.get("commodity_id", ""))
			if not cid.is_empty() and not commodities.has(cid):
				commodities.append(cid)
			var role := str(slot.get("role", ""))
			if not role.is_empty() and not roles.has(role):
				roles.append(role)
		out.append({
			"id": "quay_%s" % str(family_info.get("group_id", family_info.get("family", index))).replace(":", "_"),
			"mode": MODE_QUAY,
			"layout": "single",
			"family": str(family_info.get("family", "general")),
			"group_id": str(family_info.get("group_id", "")),
			"commodities": commodities,
			"roles": roles,
			"trade_slots": trade_slots,
			"zones": zones,
			"origin": [origin.x, origin.y],
			"tip": [tip.x, tip.y],
			"direction": [seaward.x, seaward.y],
			"tangent": [along.x, along.y],
			"length_m": length_m,
			"min_length_m": PortSizing.min_quay_length_m(size, zones.size()),
			"ship_berth_m": PortSizing.min_ship_berth_m(size),
			"width_m": pier_w,
			"spacing_m": spacing,
			"equipment_kind": equipment_for_family(str(family_info.get("family", "general"))),
			"yard_width_m": yard.x,
			"yard_depth_m": yard.y,
			"berth_side": 1 if (index % 2) == 0 else -1,
			"berth_faces": 1,
			"lanes": ["dock", "crane", "cargo", "road"],
			"seaward_clear_m": local_clear,
		})
	_resolve_loading_faces(out, size)
	if definition != null and definition.development_facilities and layout != null:
		# A long development waterfront may bend around a headland. Keep the
		# actual working side in deep water as well as clear of the next quay.
		for station: Dictionary in out:
			for side in [float(station.berth_side), -float(station.berth_side)]:
				if _loading_face_gap(station, out, side) >= PortSizing.design_hull_beam_m(size) + 5.0 \
						and _loading_face_water_clear(station, side, layout, definition):
					station["berth_side"] = side
					break
	return out


static func _loading_face_water_clear(station: Dictionary, side: float,
		layout: WorldLayout, definition: PortDefinition) -> bool:
	var origin := Vector2(station.origin[0], station.origin[1])
	var sea := Vector2(station.direction[0], station.direction[1])
	var across := Vector2(sea.y, -sea.x) * side
	var frame := Transform3D(Basis(Vector3.UP, definition.rotation_y), definition.world_position)
	for depth in [40.0, 90.0, float(station.length_m) + ARM_WATER_TAIL_M]:
		var at: Vector2 = origin + sea * depth + across * (float(station.width_m) * .5 + 15.0)
		var point := frame * Vector3(at.x, 0, at.y)
		if layout.sample_height(Vector2(point.x, point.z)) > WaveSurface.WATER_LEVEL - 2.5:
			return false
	return true


## A curved/short waterfront can compress snapped roots below their requested
## comb spacing. Keep the existing piers and IDs, but put loading on the clear
## side when the alternating side would place a ship inside its neighbour.
static func _resolve_loading_faces(stations: Array, size: int) -> void:
	var required_gap := PortSizing.design_hull_beam_m(size) + 5.0
	for station: Dictionary in stations:
		var preferred := float(station.get("berth_side", 1.0))
		if _loading_face_gap(station, stations, preferred) >= required_gap:
			continue
		if _loading_face_gap(station, stations, -preferred) >= required_gap:
			station["berth_side"] = -preferred


static func _loading_face_gap(station: Dictionary, stations: Array, side: float) -> float:
	var raw: Array = station.direction
	var forward := Vector2(float(raw[0]),float(raw[1])).normalized()
	# Same local +X as the visualizer's yaw atan2(direction.x, direction.y).
	var across := Vector2(forward.y,-forward.x) * side
	var root := Vector2(float(station.origin[0]),float(station.origin[1]))
	var gap := INF
	for neighbour: Dictionary in stations:
		if str(neighbour.id) == str(station.id): continue
		var delta := Vector2(float(neighbour.origin[0]),float(neighbour.origin[1])) - root
		var lateral := delta.dot(across)
		if lateral <= 0.0: continue
		var start := delta.dot(forward)
		if start >= float(station.length_m) or start + float(neighbour.length_m) <= 0.0: continue
		gap = minf(gap, lateral - (float(station.width_m)+float(neighbour.width_m))*.5)
	return gap


static func _quay_list_contains_family(quay_list: Array, family: String) -> bool:
	for raw in quay_list:
		var family_info := raw as Dictionary
		if str(family_info.get("family", "")) == family:
			return true
	return false


## One shared pier for exactly two trade pads — outer docks, centre road.
static func _place_twin_quay(
		quay_list: Array,
		dock_face: PackedVector2Array,
		size: int,
		site_seed: int,
		basin: Dictionary = {},
		layout: WorldLayout = null,
		definition: PortDefinition = null,
		proj_lo: float = NAN,
		proj_hi: float = NAN,
) -> Dictionary:
	if quay_list.size() != 2 or dock_face.size() < 2:
		return {}
	var max_arm_m := float(basin.get("max_arm_m", INF))
	var lengths := PortSizing.arm_target_lengths_m(size, "solo_jetty", 2)
	var seaward := _consensus_seaward(dock_face)
	var along := Vector2(-seaward.y, seaward.x)
	if along.dot(Vector2(1.0, 0.0)) < 0.0:
		along = -along
	var port_origin := definition.world_position if definition != null else Vector3.ZERO
	var port_yaw := definition.rotation_y if definition != null else 0.0
	var seaward_world := CoastTracer.port_local_dir_to_world(seaward, port_yaw)
	if seaward_world.length_squared() < 0.25:
		seaward_world = seaward
	var face_samples := _sample_face(dock_face, 6.0)
	if face_samples.is_empty():
		return {}
	var soft_cap := layout != null and not bool(basin.get("probe_failed", false)) \
			and is_finite(max_arm_m)
	var proj_min := INF
	var proj_max := -INF
	for sample in face_samples:
		var proj: float = sample["proj"]
		proj_min = minf(proj_min, proj)
		proj_max = maxf(proj_max, proj)
	if is_finite(proj_lo) and is_finite(proj_hi) and proj_hi > proj_lo + 1.0:
		proj_min = maxf(proj_min, proj_lo)
		proj_max = minf(proj_max, proj_hi)
	var target_proj := (proj_min + proj_max) * 0.5
	var snap := _snap_to_face_proj(face_samples, target_proj)
	var origin: Vector2 = snap.get("position", Vector2.ZERO)

	var sides: Array = []
	var all_commodities: Array = []
	var all_roles: Array = []
	var zone_count := 0
	for index in range(2):
		var family_info: Dictionary = quay_list[index]
		var trade_slots: Array = (family_info.get("trade_slots", []) as Array).duplicate(true)
		if trade_slots.is_empty():
			for commodity in family_info.get("commodities", []) as Array:
				trade_slots.append({
					"commodity_id": str(commodity),
					"role": "trade",
					"family": str(family_info.get("family", "general")),
				})
		var zones := _build_commodity_zones(trade_slots)
		zone_count = maxi(zone_count, zones.size())
		var commodities: Array = []
		var roles: Array = []
		for slot in trade_slots:
			var cid := str(slot.get("commodity_id", ""))
			if not cid.is_empty() and not commodities.has(cid):
				commodities.append(cid)
				if not all_commodities.has(cid):
					all_commodities.append(cid)
			var role := str(slot.get("role", ""))
			if not role.is_empty() and not roles.has(role):
				roles.append(role)
				if not all_roles.has(role):
					all_roles.append(role)
		var berth_side := -1 if index == 0 else 1
		sides.append({
			"id": "side_%s" % str(family_info.get("group_id", family_info.get("family", index))).replace(":", "_"),
			"family": str(family_info.get("family", "general")),
			"group_id": str(family_info.get("group_id", "")),
			"commodities": commodities,
			"roles": roles,
			"trade_slots": trade_slots,
			"zones": zones,
			"berth_side": berth_side,
			"equipment_kind": equipment_for_family(str(family_info.get("family", "general"))),
		})

	var length_m := maxf(float(lengths[0]), float(lengths[1]))
	length_m = maxf(length_m, PortSizing.min_quay_length_m(size, maxi(zone_count, 1)))
	var local_clear := max_arm_m if soft_cap else length_m
	var arm_budget := length_m
	if soft_cap:
		var world_origin := CoastTracer.port_local_to_world(origin, port_origin, port_yaw)
		local_clear = CoastalPortPlacer.seaward_water_clearance_m(
			layout, world_origin, seaward_world, BASIN_PROBE_MAX_M
		)
		arm_budget = minf(max_arm_m, maxf(local_clear - ARM_WATER_TAIL_M, 0.0))
		if arm_budget > 0.0:
			length_m = minf(length_m, arm_budget)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site_seed) ^ 0x5457494E ^ size
	length_m *= rng.randf_range(0.98, 1.02)
	if soft_cap and arm_budget > 0.0:
		length_m = minf(length_m, arm_budget)
	length_m = maxf(length_m, 24.0)
	var pier_w := PortSizing.twin_quay_deck_width_for_arm_m(length_m, size)
	var tip := origin + seaward * length_m
	var yard := PortSizing.cargo_yard_size_m(mini(size, PortSizing.max_size_for_arm_budget_m(length_m)))
	var id_a := str((sides[0] as Dictionary).get("group_id", "a")).replace(":", "_")
	var id_b := str((sides[1] as Dictionary).get("group_id", "b")).replace(":", "_")
	return {
		"id": "quay_twin_%s_%s" % [id_a, id_b],
		"mode": MODE_QUAY,
		"layout": "twin_joined",
		"family": "twin",
		"group_id": "twin:%s:%s" % [id_a, id_b],
		"commodities": all_commodities,
		"roles": all_roles,
		"trade_slots": [],
		"zones": [],
		"sides": sides,
		"origin": [origin.x, origin.y],
		"tip": [tip.x, tip.y],
		"direction": [seaward.x, seaward.y],
		"tangent": [along.x, along.y],
		"length_m": length_m,
		"min_length_m": PortSizing.min_quay_length_m(size, maxi(zone_count, 1)),
		"ship_berth_m": PortSizing.min_ship_berth_m(size),
		"width_m": pier_w,
		"spacing_m": 0.0,
		"equipment_kind": "",
		"yard_width_m": yard.x,
		"yard_depth_m": yard.y,
		"berth_side": 0,
		"berth_faces": 2,
		"lanes": ["dock", "crane", "cargo", "road", "cargo", "crane", "dock"],
		"seaward_clear_m": local_clear,
	}


## Along-pier bands — one zone per commodity. Containers import+export merge into one.
static func _build_commodity_zones(trade_slots: Array) -> Array:
	var zones: Array = []
	if trade_slots.is_empty():
		return zones
	## Collapse bidirectional commodities (containers) to a single band.
	var merged: Array = []
	var seen_bi: Dictionary = {}
	for raw in trade_slots:
		var slot: Dictionary = raw
		var commodity_id := str(slot.get("commodity_id", ""))
		if PortTradeProfile.is_bidirectional_trade(commodity_id):
			if seen_bi.has(commodity_id):
				continue
			seen_bi[commodity_id] = true
			merged.append({
				"commodity_id": commodity_id,
				"role": "import_export",
				"family": str(slot.get("family", CommodityCatalog.commodity_terminal_family(commodity_id))),
				"bidirectional": true,
			})
			continue
		merged.append(slot)
	var n := merged.size()
	for index in range(n):
		var slot: Dictionary = merged[index]
		var commodity_id := str(slot.get("commodity_id", ""))
		var t0 := float(index) / float(n)
		var t1 := float(index + 1) / float(n)
		var role := str(slot.get("role", ""))
		var display := CommodityCatalog.commodity_display(commodity_id)
		var label := ""
		if bool(slot.get("bidirectional", false)):
			label = "IMPORT / EXPORT\n%s" % display
		elif role == "export":
			label = "EXPORT\n%s" % display
		elif role == "import":
			label = "IMPORT\n%s" % display
		else:
			label = display
		zones.append({
			"commodity_id": commodity_id,
			"role": role,
			"family": str(slot.get("family", CommodityCatalog.commodity_terminal_family(commodity_id))),
			"t0": t0,
			"t1": t1,
			"bidirectional": bool(slot.get("bidirectional", false)),
			"label": label,
			"color": [
				CommodityCatalog.commodity_color(commodity_id).r,
				CommodityCatalog.commodity_color(commodity_id).g,
				CommodityCatalog.commodity_color(commodity_id).b,
			],
		})
	return zones


static func equipment_for_family(family: String) -> String:
	match family:
		"fishing":
			return "equip_fish_derrick"
		"container":
			return "equip_sts_gantry"
		"general":
			return "equip_provision_crane"
		"bulk_ore":
			return "equip_grab_unloader"
		"bulk_grain":
			return "equip_grain_elevator"
		"liquid":
			return "equip_loading_arm"
		_:
			return "equip_jib_crane"


## Destiny already limits mature pads to ≤3. Never drop an unlocked pad here.
static func _cap_quay_families(quay_list: Array, _size: int) -> Array:
	var hard_max := PortSizing.max_dedicated_quays(PortSizing.MAX_SIZE)
	if quay_list.size() <= hard_max:
		return quay_list
	var ranked: Array = quay_list.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _quay_keep_priority(a) < _quay_keep_priority(b)
	)
	var kept: Array = []
	for index in range(mini(hard_max, ranked.size())):
		kept.append((ranked[index] as Dictionary).duplicate(true))
	return kept


static func _quay_keep_priority(entry: Dictionary) -> int:
	var slots: Array = entry.get("trade_slots", []) as Array
	var role := str(slots[0].get("role", "")) if not slots.is_empty() else ""
	var family := str(entry.get("family", ""))
	## Keep primary exports first, then imports; liquids / containers before general.
	var role_rank := 0 if role == "export" or role == "import_export" else 1
	var family_rank := 4
	match family:
		"liquid":
			family_rank = 0
		"container":
			family_rank = 1
		"bulk_grain", "bulk_ore":
			family_rank = 2
		_:
			family_rank = 3
	return role_rank * 10 + family_rank


static func _merge_asphalt_slots(asphalt_slots: Array) -> Array:
	## One apron berth per commodity — import+export share the same pad.
	var by_id: Dictionary = {}
	var order: Array[String] = []
	for raw in asphalt_slots:
		var slot: Dictionary = raw
		var commodity_id := str(slot.get("commodity_id", ""))
		if commodity_id.is_empty():
			continue
		if not by_id.has(commodity_id):
			by_id[commodity_id] = {
				"commodity_id": commodity_id,
				"role": str(slot.get("role", "")),
				"family": str(slot.get("family", CommodityCatalog.commodity_terminal_family(commodity_id))),
				"mode": MODE_ASPHALT,
				"roles": [str(slot.get("role", ""))],
			}
			order.append(commodity_id)
			continue
		var entry: Dictionary = by_id[commodity_id]
		var role := str(slot.get("role", ""))
		var roles: Array = entry["roles"]
		if not role.is_empty() and not roles.has(role):
			roles.append(role)
		if roles.has("import") and roles.has("export"):
			entry["role"] = "import_export"
		elif not role.is_empty():
			entry["role"] = role
	var out: Array = []
	## Fish first (working waterfront), then provisions / general.
	order.sort_custom(func(a: String, b: String) -> bool:
		var fa := CommodityCatalog.commodity_terminal_family(a)
		var fb := CommodityCatalog.commodity_terminal_family(b)
		if fa == "fishing" and fb != "fishing":
			return true
		if fb == "fishing" and fa != "fishing":
			return false
		return a < b
	)
	for commodity_id in order:
		out.append(by_id[commodity_id])
	return out


## Pack apron berths onto free dock-face arcs. Each pad inherits the local
## edge tangent/seaward so it hugs the curved waterline, and stays clear of
## quay roots + loading-side approach pockets.
static func _place_asphalt_on_face(
		asphalt_slots: Array,
		dock_face: PackedVector2Array,
		size: int,
		quay_stations: Array,
) -> Array:
	var out: Array = []
	if asphalt_slots.is_empty() or dock_face.size() < 2:
		return out
	var total_arc := _polyline_length_m(dock_face)
	if total_arc < 8.0:
		return out
	var gap_m := PortSizing.asphalt_berth_gap_m(size)
	var length_m := PortSizing.asphalt_berth_length_m(size)
	var depth_m := PortSizing.asphalt_apron_depth_m(size)
	var count := asphalt_slots.size()
	var need := length_m * float(count) + gap_m * float(maxi(count - 1, 0))
	var blocked := _quay_loading_exclusions_along_face(dock_face, quay_stations, size)
	var free_spans := _free_arc_spans(total_arc, blocked, gap_m)
	if free_spans.is_empty():
		## Soft fallback when exclusions cover the face — use the full usable run.
		free_spans = [{
			"lo": gap_m,
			"hi": maxf(total_arc - gap_m, gap_m + 1.0),
			"length": maxf(total_arc - gap_m * 2.0, 1.0),
		}]
	## Prefer the longest free waterfront run so pads share one edge neighbourhood.
	free_spans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("length", 0.0)) > float(b.get("length", 0.0))
	)
	var span: Dictionary = free_spans[0]
	var span_len := float(span.get("length", 0.0))
	if need > span_len and count > 0:
		var shrink := span_len / need
		length_m = maxf(length_m * shrink, PortSizing.design_hull_loa_m(size) * 0.75)
		need = length_m * float(count) + gap_m * float(maxi(count - 1, 0))
	need = minf(need, span_len)
	var span_lo := float(span.get("lo", 0.0))
	## Centre the pack inside the free span (not jammed against a pier exclusion).
	var pack_lo := span_lo + maxf((span_len - need) * 0.5, 0.0)
	var yard := PortSizing.cargo_yard_size_m(size)
	var cursor := pack_lo + length_m * 0.5
	for index in range(count):
		var slot: Dictionary = asphalt_slots[index]
		var sample := _point_at_arc(dock_face, cursor)
		var origin: Vector2 = sample.get("position", Vector2.ZERO)
		var tangent: Vector2 = sample.get("tangent", Vector2(1.0, 0.0))
		if tangent.length_squared() < 0.0001:
			tangent = Vector2(1.0, 0.0)
		else:
			tangent = tangent.normalized()
		var local_seaward := _seaward_normal(tangent)
		var inland := -local_seaward
		var family := str(slot.get("family", "general"))
		var role := str(slot.get("role", ""))
		var roles: Array = slot.get("roles", [role]) as Array
		out.append({
			"id": "asphalt_%s" % str(slot.get("commodity_id", index)),
			"mode": MODE_ASPHALT,
			"commodity_id": str(slot.get("commodity_id", "")),
			"role": role,
			"roles": roles,
			"family": family,
			## Root is the waterfront edge; the working pad belongs on the
			## harbour apron while the berth itself remains on the water side.
			"origin": [origin.x, origin.y],
			"direction": [local_seaward.x, local_seaward.y],
			"inland_dir": [inland.x, inland.y],
			"tangent": [tangent.x, tangent.y],
			"extends": "inland",
			"arc_m": cursor,
			"depth_m": depth_m,
			"length_m": length_m,
			"ship_berth_m": length_m,
			"equipment_kind": equipment_for_family(family),
			"yard_width_m": yard.x,
			"yard_depth_m": maxf(yard.y * 0.45, depth_m * 0.8),
			"lanes": ["storage", "road", "berth"],
			"district_index": index,
		})
		cursor += length_m + gap_m
	return out


## Arc-length exclusion around each pier root, widened on the loading/berth side.
static func _quay_loading_exclusions_along_face(
		dock_face: PackedVector2Array,
		quay_stations: Array,
		size: int,
) -> Array:
	var out: Array = []
	if quay_stations.is_empty() or dock_face.size() < 2:
		return out
	var loading_clear := PortSizing.asphalt_quay_loading_clearance_m(size)
	for raw in quay_stations:
		var station: Dictionary = raw
		var origin := Vector2(
			float((station.get("origin", [0.0, 0.0]) as Array)[0]),
			float((station.get("origin", [0.0, 0.0]) as Array)[1]),
		)
		var tip := Vector2(
			float((station.get("tip", [origin.x, origin.y]) as Array)[0]),
			float((station.get("tip", [origin.x, origin.y]) as Array)[1]),
		)
		var root_arc := _nearest_arc_on_polyline(dock_face, origin)
		var half_w := float(station.get("width_m", PortSizing.quay_deck_width_m(size))) * 0.5
		var lo := root_arc - half_w - loading_clear
		var hi := root_arc + half_w + loading_clear
		## Bias the keep-clear toward the pier's loading face along the dock edge.
		var berth_side := float(station.get("berth_side", 1.0))
		var pier_dir := (tip - origin)
		var face_sample := _point_at_arc(dock_face, root_arc)
		var face_tangent: Vector2 = face_sample.get("tangent", Vector2(1.0, 0.0))
		if face_tangent.length_squared() > 0.0001:
			face_tangent = face_tangent.normalized()
		## Local +X after seaward align ≈ UP×seaward; berth_side picks ship face.
		var local_seaward := _seaward_normal(face_tangent)
		var local_x := Vector2(-local_seaward.y, local_seaward.x)
		if local_x.dot(face_tangent) < 0.0:
			local_x = -local_x
		var loading_along := local_x * berth_side
		if loading_along.dot(face_tangent) >= 0.0:
			hi += loading_clear * 0.65
		else:
			lo -= loading_clear * 0.65
		## Also keep clear near the first stretch of the pier (approach pocket).
		if pier_dir.length_squared() > 1.0:
			var approach := minf(pier_dir.length() * 0.22, 48.0)
			lo -= approach * 0.15
			hi += approach * 0.15
		out.append({"lo": lo, "hi": hi})
	return _merge_arc_intervals(out)


static func _free_arc_spans(total_arc: float, blocked: Array, edge_pad_m: float) -> Array:
	var usable_lo := edge_pad_m
	var usable_hi := maxf(total_arc - edge_pad_m, usable_lo)
	var free: Array = []
	var cursor := usable_lo
	for raw in blocked:
		var lo := maxf(float((raw as Dictionary).get("lo", 0.0)), usable_lo)
		var hi := minf(float((raw as Dictionary).get("hi", 0.0)), usable_hi)
		if hi <= lo:
			continue
		if lo > cursor + 1.0:
			free.append({"lo": cursor, "hi": lo, "length": lo - cursor})
		cursor = maxf(cursor, hi)
	if usable_hi > cursor + 1.0:
		free.append({"lo": cursor, "hi": usable_hi, "length": usable_hi - cursor})
	return free


static func _merge_arc_intervals(intervals: Array) -> Array:
	if intervals.is_empty():
		return []
	var sorted: Array = intervals.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("lo", 0.0)) < float(b.get("lo", 0.0))
	)
	var merged: Array = []
	var cur: Dictionary = (sorted[0] as Dictionary).duplicate(true)
	for index in range(1, sorted.size()):
		var nxt: Dictionary = sorted[index]
		if float(nxt.get("lo", 0.0)) <= float(cur.get("hi", 0.0)) + 0.5:
			cur["hi"] = maxf(float(cur.get("hi", 0.0)), float(nxt.get("hi", 0.0)))
		else:
			merged.append(cur)
			cur = nxt.duplicate(true)
	merged.append(cur)
	return merged


static func _nearest_arc_on_polyline(path: PackedVector2Array, point: Vector2) -> float:
	if path.size() < 2:
		return 0.0
	var best_arc := 0.0
	var best_dist := INF
	var arc := 0.0
	for index in range(path.size() - 1):
		var a := path[index]
		var b := path[index + 1]
		var ab := b - a
		var len_sq := ab.length_squared()
		var t := 0.0 if len_sq < 0.0001 else clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
		var closest := a + ab * t
		var dist := closest.distance_squared_to(point)
		if dist < best_dist:
			best_dist = dist
			best_arc = arc + ab.length() * t
		arc += ab.length()
	return best_arc


static func _consensus_seaward(dock_face: PackedVector2Array) -> Vector2:
	var acc := Vector2.ZERO
	for index in range(dock_face.size() - 1):
		var step := dock_face[index + 1] - dock_face[index]
		if step.length_squared() < 0.01:
			continue
		acc += _seaward_normal(step.normalized())
	var local := acc.normalized() if acc.length_squared() > 0.001 else CoastTracer.PORT_LOCAL_SEAWARD_DIR
	## Blend toward port −Z so sharp bays don't yank the comb sideways.
	var blended := (local * 0.7 + CoastTracer.PORT_LOCAL_SEAWARD_DIR * 0.3).normalized()
	if blended.length_squared() < 0.001:
		return CoastTracer.PORT_LOCAL_SEAWARD_DIR
	return blended


static func _sample_face(dock_face: PackedVector2Array, step_m: float) -> Array:
	var seaward := _consensus_seaward(dock_face)
	var along := Vector2(-seaward.y, seaward.x)
	if along.dot(Vector2(1.0, 0.0)) < 0.0:
		along = -along
	var out: Array = []
	var total := _polyline_length_m(dock_face)
	if total <= 0.1:
		return out
	var arc := 0.0
	while arc <= total + 0.01:
		var sample := _point_at_arc(dock_face, arc)
		var pos: Vector2 = sample.get("position", Vector2.ZERO)
		out.append({
			"position": pos,
			"tangent": sample.get("tangent", along),
			"seaward": _seaward_normal((sample.get("tangent", along) as Vector2)),
			"proj": pos.dot(along),
			"arc": arc,
		})
		arc += step_m
	return out


static func _snap_to_face_proj(face_samples: Array, target_proj: float) -> Dictionary:
	var best: Dictionary = face_samples[0]
	var best_dist := INF
	for sample in face_samples:
		var dist := absf(float(sample["proj"]) - target_proj)
		if dist < best_dist:
			best_dist = dist
			best = sample
	return best


static func _notes(asphalt_slots: Array, quay_stations: Array) -> PackedStringArray:
	var notes: PackedStringArray = []
	if not asphalt_slots.is_empty():
		notes.append("%d apron berth(s) hugging dock face (local edge orientation)" % asphalt_slots.size())
	if not quay_stations.is_empty():
		var twin := false
		for raw in quay_stations:
			if str((raw as Dictionary).get("layout", "")) == "twin_joined":
				twin = true
				break
		if twin:
			notes.append(
				"joined twin quay · dock|crane|cargo|road|cargo|crane|dock"
			)
		else:
			notes.append(
				"%d quay(s) · dock|crane|cargo|road · ≥1 ship berth per commodity zone"
				% quay_stations.size()
			)
	elif not asphalt_slots.is_empty():
		notes.append("no dedicated quays yet — unlock timber/bulk/liquid/containers")
	if asphalt_slots.is_empty() and quay_stations.is_empty():
		notes.append("no trade slots to berth")
	return notes


static func _seaward_normal(tangent: Vector2) -> Vector2:
	## Port local: +Z inland, −Z seaward. Prefer the perpendicular that dots seaward.
	var left := Vector2(-tangent.y, tangent.x).normalized()
	var right := Vector2(tangent.y, -tangent.x).normalized()
	var seaward_ref := CoastTracer.PORT_LOCAL_SEAWARD_DIR
	if left.dot(seaward_ref) >= right.dot(seaward_ref):
		return left
	return right


static func _polyline_from_array(raw: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in raw:
		var arr := point as Array
		if arr.size() < 2:
			continue
		out.append(Vector2(float(arr[0]), float(arr[1])))
	return out


static func _polyline_length_m(path: PackedVector2Array) -> float:
	var total := 0.0
	for index in range(1, path.size()):
		total += path[index - 1].distance_to(path[index])
	return total


static func _point_at_arc(path: PackedVector2Array, arc_s: float) -> Dictionary:
	if path.is_empty():
		return {"position": Vector2.ZERO, "tangent": Vector2(1.0, 0.0)}
	if path.size() == 1:
		return {"position": path[0], "tangent": Vector2(1.0, 0.0)}
	var remaining := maxf(arc_s, 0.0)
	for index in range(path.size() - 1):
		var a := path[index]
		var b := path[index + 1]
		var seg := a.distance_to(b)
		if seg < 0.001:
			continue
		if remaining <= seg:
			var t := remaining / seg
			var tangent := (b - a) / seg
			return {"position": a.lerp(b, t), "tangent": tangent}
		remaining -= seg
	var last := path[path.size() - 1]
	var prev := path[path.size() - 2]
	var tangent := (last - prev).normalized()
	if tangent.length_squared() < 0.001:
		tangent = Vector2(1.0, 0.0)
	return {"position": last, "tangent": tangent}
