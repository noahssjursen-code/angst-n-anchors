class_name BerthApproachLanes
extends RefCounted

## Island-owned quay approach lanes — three port-relative paths per target:
##   SPINE: straight seaward (approach from ahead)
##   FLANK_PORT / FLANK_STARBOARD: curve along island sides (behind / abeam)

enum LaneKind {
	SPINE = 0,
	FLANK_PORT = 1,
	FLANK_STARBOARD = 2,
}

const LANE_KIND_COUNT := 3

const PLOT_DEPTH_M := 140.0
const SPINE_REACH_M := 680.0
const FLANK_REACH_M := 820.0
const STEP_M := 24.0
const MAX_SPINE_STEPS := 36
const MAX_FLANK_STEPS := 48
const OPEN_WATER_END_M := 58.0
const OPEN_WATER_RUN_STEPS := 4
const LIVE_PORT_HANDOFF_M := 90.0
const LAND_PAD_M := IslandMeshBuilder.MARGIN + IslandMeshBuilder.AMPLITUDE
const QUAY_ZONE_M := 14.0
const NEAR_SHORE_ZONE_M := 55.0
const MID_SHORE_ZONE_M := 180.0
const ROUTE_CLEARANCE_M := 18.0
const FLANK_DEFLECT_DEG: Array[float] = [12.0, 24.0, 36.0, 48.0, 60.0, 75.0]

static var _initialized: bool = false
static var _lanes: Dictionary = {}  ## port_id -> target id -> lane kind -> Array[Vector3]
static var _berth_positions: Dictionary = {} # compatibility name: quay/call targets
static var _target_meta: Dictionary = {} ## port_id -> berth_id -> family/commodities
static var _islands: Dictionary = {}
static var _live_baked_ports: Dictionary = {}
static var debug_visible: bool = false


static func bake_all_ports(
		defs: Array,
		world_seed: int,
		world_layout: WorldLayout = null,
) -> void:
	if not LandField.is_initialized():
		push_warning("BerthApproachLanes: LandField not ready — skipping port bake")
		return
	_lanes.clear()
	_berth_positions.clear()
	_target_meta.clear()
	_islands.clear()
	_live_baked_ports.clear()
	var lane_count := 0
	for def_raw in defs:
		var def := def_raw as PortDefinition
		if def == null:
			continue
		var data := PortExpander.expand(def, world_seed, world_layout)
		lane_count += bake_from_port_data(data)
	_initialized = true
	print(
		"[BerthApproachLanes] Port bake: %d lane(s) across %d port(s), %d debug curves"
		% [lane_count, _lanes.size(), debug_polyline_count()]
	)


static func bake_from_port_data(data: PortData) -> int:
	if data == null or data.port_id.is_empty():
		return 0
	if not LandField.is_initialized():
		return 0
	if _live_baked_ports.has(data.port_id):
		return 0

	_islands[data.port_id] = _island_meta_from_data(data)
	var half_beam := ShipClass.beam(data.max_ship_class) * 0.5
	var port_lanes: Dictionary = {}
	var port_berths: Dictionary = {}
	var port_meta: Dictionary = {}
	var baked := 0
	var plan := data.layout_graph.initial_attributes.get("berth_plan", {}) as Dictionary \
		if data.layout_graph != null else {}
	for raw in plan.get("asphalt_stations", []) as Array:
		var station := raw as Dictionary
		var local_origin := _array_xz(station.get("origin", [0.0, 0.0]))
		var local_seaward := _array_xz(station.get("direction", [0.0, -1.0])).normalized()
		var seaward := PortCoastTracer.port_local_dir_to_world(local_seaward, data.rotation_y)
		var root_local := local_origin + local_seaward * float(station.get("depth_m", 36.0)) * 0.5
		var root_world := PortCoastTracer.port_local_to_world(root_local, data.world_position, data.rotation_y)
		var target_id := HarbourController.make_berth_id(data.port_id, str(station.get("id", "asphalt")))
		baked += _store_planned_lane(port_lanes, port_berths, port_meta, target_id,
			root_world, seaward, seaward, float(station.get("length_m", 40.0)),
			float(station.get("depth_m", 36.0)), half_beam,
			str(station.get("family", "general")),
			[str(station.get("commodity_id", ""))])
	for raw in plan.get("quay_stations", []) as Array:
		var station := raw as Dictionary
		var local_origin := _array_xz(station.get("origin", [0.0, 0.0]))
		var local_tip := _array_xz(station.get("tip", [local_origin.x, local_origin.y]))
		var local_seaward := _array_xz(station.get("direction", [0.0, -1.0])).normalized()
		var seaward := PortCoastTracer.port_local_dir_to_world(local_seaward, data.rotation_y)
		var mid_world := PortCoastTracer.port_local_to_world(
			local_origin.lerp(local_tip, 0.5), data.world_position, data.rotation_y)
		var right := Vector2(seaward.y, -seaward.x)
		var station_id := str(station.get("id", "quay"))
		var length_m := float(station.get("length_m", local_origin.distance_to(local_tip)))
		var width_m := float(station.get("width_m", 24.0))
		if str(station.get("layout", "single")) == "twin_joined":
			var sides := station.get("sides", []) as Array
			for side_index in range(mini(sides.size(), 2)):
				var side := sides[side_index] as Dictionary
				var sign := float(side.get("berth_side", -1.0 if side_index == 0 else 1.0))
				var target_id := HarbourController.make_berth_id(
					data.port_id, "%s/side_%d" % [station_id, side_index])
				baked += _store_planned_lane(port_lanes, port_berths, port_meta, target_id,
					mid_world, right * sign, seaward, length_m, width_m, half_beam,
					str(side.get("family", "general")), side.get("commodities", []) as Array)
		else:
			var sign := float(station.get("berth_side", 1.0))
			var target_id := HarbourController.make_berth_id(data.port_id, station_id)
			baked += _store_planned_lane(port_lanes, port_berths, port_meta, target_id,
				mid_world, right * sign, seaward, length_m, width_m, half_beam,
				str(station.get("family", "general")), station.get("commodities", []) as Array)

	_lanes[data.port_id] = port_lanes
	_berth_positions[data.port_id] = port_berths
	_target_meta[data.port_id] = port_meta
	return baked


static func _store_planned_lane(
	port_lanes: Dictionary, port_berths: Dictionary, port_meta: Dictionary,
	target_id: String, root_world: Vector2, water: Vector2, seaward: Vector2,
	length_m: float, face_width_m: float, half_beam_m: float,
	family: String, commodities_raw: Array,
) -> int:
	if target_id.is_empty() or water.length_squared() < 0.001 or seaward.length_squared() < 0.001:
		return 0
	water = water.normalized()
	seaward = seaward.normalized()
	var berth2 := root_world + water * (face_width_m * 0.5 + half_beam_m + 2.5)
	var berth := Vector3(berth2.x, WaveSurface.WATER_LEVEL, berth2.y)
	var crab := berth + Vector3(water.x, 0.0, water.y) * 16.0
	var sea3 := Vector3(seaward.x, 0.0, seaward.y)
	var canonical := _densify_chain([
		berth,
		crab,
		crab + sea3 * (length_m * 0.5 + 45.0),
		crab + sea3 * (length_m * 0.5 + 45.0 + LIVE_PORT_HANDOFF_M),
	])
	port_lanes[target_id] = {
		int(LaneKind.SPINE): canonical,
		int(LaneKind.FLANK_PORT): canonical,
		int(LaneKind.FLANK_STARBOARD): canonical,
	}
	port_berths[target_id] = berth
	var commodities := PackedStringArray()
	for raw in commodities_raw:
		var commodity := str(raw)
		if not commodity.is_empty():
			commodities.append(commodity)
	port_meta[target_id] = {"family": family, "commodities": commodities}
	return 3


## Runtime berth slots carry the exact station transform and water-side vector.
## Publishing them by real berth_id replaces the old primary-"quay" ambiguity
## and gives autonomous traffic stable network identifiers.
static func bake_live_berth(port_id: String, slot: QuayBerthSlot) -> int:
	if slot == null or not is_instance_valid(slot) or port_id.is_empty() or slot.berth_id.is_empty():
		return 0
	var water := slot.global_transform.basis * slot.water_dir_local
	water.y = 0.0
	if water.length_squared() <= 0.001:
		return 0
	water = water.normalized()
	## Runtime terminals are authored with local +Z pointing from shore toward
	## the pier tip. Deriving this from the berth-side normal is ambiguous: the
	## opposite face reverses that cross product and used to send its lane inland.
	var seaward := slot.global_transform.basis * Vector3(0.0, 0.0, 1.0)
	seaward.y = 0.0
	if seaward.length_squared() <= 0.001:
		return 0
	seaward = seaward.normalized()
	var berth := slot.to_global(slot.ship_dock_local(8.0).origin)
	berth.y = WaveSurface.WATER_LEVEL
	var crab_clear := berth + water * maxf(slot.berth_gap_m + 12.0, 16.0)
	var clear_tip := crab_clear + seaward * (slot.length_m * 0.5 + 45.0)
	## End port authority shortly after the hull clears the pier. The marine
	## passage planner owns everything beyond this compact handoff corridor.
	var outer := clear_tip + seaward * LIVE_PORT_HANDOFF_M
	var canonical := _densify_chain([
		berth,
		crab_clear,
		clear_tip,
		outer,
	])
	var by_port := _lanes.get(port_id, {}) as Dictionary
	by_port[slot.berth_id] = {
		## A live quay has one physically valid side-specific escape corridor.
		## Publish it under every approach selector so destination bearing cannot
		## choose a mirrored path through the terminal or neighbouring piers.
		int(LaneKind.SPINE): canonical,
		int(LaneKind.FLANK_PORT): canonical,
		int(LaneKind.FLANK_STARBOARD): canonical,
	}
	_lanes[port_id] = by_port
	var positions := _berth_positions.get(port_id, {}) as Dictionary
	positions[slot.berth_id] = berth
	_berth_positions[port_id] = positions
	var metadata := _target_meta.get(port_id, {}) as Dictionary
	metadata[slot.berth_id] = {
		"family": slot.family,
		"commodities": slot.commodities.duplicate(),
	}
	_target_meta[port_id] = metadata
	# From this point the runtime slot transform is the authority for which face
	# is water-side. Do not let a later planned-data bake replace this exact lane.
	_live_baked_ports[port_id] = true
	_initialized = true
	return 3


static func is_initialized() -> bool:
	return _initialized


static func is_live_baked(port_id: String) -> bool:
	return _live_baked_ports.has(port_id)


static func get_island_meta(port_id: String) -> Dictionary:
	return _islands.get(port_id, {}) as Dictionary


static func port_rotation_y(port_id: String) -> float:
	var island: Dictionary = _islands.get(port_id, {}) as Dictionary
	return float(island.get("rotation_y", 0.0))


static func toggle_debug() -> bool:
	debug_visible = not debug_visible
	return debug_visible


static func debug_label() -> String:
	return "on" if debug_visible else "off"


static func baked_port_count() -> int:
	return _lanes.size()


static func debug_polyline_count() -> int:
	return collect_debug_polylines().size()


static func berth_world_position(port_id: String, berth_index: int = 0) -> Vector3:
	return target_world_position(port_id, "quay" if berth_index == 0 else str(berth_index))


static func target_world_position(port_id: String, target_id: String = "quay") -> Vector3:
	var by_port: Variant = _berth_positions.get(port_id, {})
	if typeof(by_port) != TYPE_DICTIONARY:
		return Vector3.ZERO
	var pos: Variant = (by_port as Dictionary).get(target_id, Vector3.ZERO)
	return pos as Vector3 if pos is Vector3 else Vector3.ZERO


static func berth_count_for_port(port_id: String) -> int:
	var by_port: Variant = _berth_positions.get(port_id, {})
	if typeof(by_port) != TYPE_DICTIONARY:
		return 0
	return (by_port as Dictionary).size()


static func get_lane(port_id: String, berth_index: int, lane_kind: int) -> Array:
	return get_target_lane(port_id, "quay" if berth_index == 0 else str(berth_index), lane_kind)


static func get_target_lane(port_id: String, target_id: String, lane_kind: int) -> Array:
	var by_port: Variant = _lanes.get(port_id, {})
	if typeof(by_port) != TYPE_DICTIONARY:
		return []
	var by_berth: Variant = (by_port as Dictionary).get(target_id, {})
	if typeof(by_berth) != TYPE_DICTIONARY:
		return []
	var lane: Variant = (by_berth as Dictionary).get(lane_kind, [])
	return lane as Array if typeof(lane) == TYPE_ARRAY else []


static func best_target_id(port_id: String, family: String = "", commodity_id: String = "") -> String:
	var metadata := _target_meta.get(port_id, {}) as Dictionary
	var ids: Array = metadata.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	var best := ""
	var best_score := -1
	for raw_id in ids:
		var target_id := str(raw_id)
		var row := metadata.get(target_id, {}) as Dictionary
		var commodities := row.get("commodities", PackedStringArray()) as PackedStringArray
		var score := 0
		if not commodity_id.is_empty() and commodities.has(commodity_id):
			score += 100
		if not family.is_empty() and str(row.get("family", "")) == family:
			score += 20
		if score > best_score:
			best_score = score
			best = target_id
	return best


static func lane_outer_point(port_id: String, berth_index: int, lane_kind: int) -> Vector3:
	var lane := get_lane(port_id, berth_index, lane_kind)
	if lane.size() >= 2:
		return lane[lane.size() - 1] as Vector3
	return berth_world_position(port_id, berth_index)


static func call_lane_outer_point(port_id: String, call_id: String, lane_kind: int) -> Vector3:
	var lane := get_target_lane(port_id, call_id, lane_kind)
	if lane.size() >= 2:
		return lane[lane.size() - 1] as Vector3
	return target_world_position(port_id, call_id)


## Map travel direction (world XZ) to spine / port flank / starboard flank.
static func best_lane_kind_for_direction(travel_dir: Vector3, rotation_y: float) -> int:
	var dir := travel_dir
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return int(LaneKind.SPINE)
	dir = dir.normalized()
	var frame := _port_frame(rotation_y)
	var ahead := dir.dot(frame.seaward)
	var abeam := dir.dot(frame.port)

	if ahead >= 0.38:
		return int(LaneKind.SPINE)
	if abeam >= 0.22 and abeam >= absf(ahead) * 0.65:
		return int(LaneKind.FLANK_PORT)
	if abeam <= -0.22 and absf(abeam) >= absf(ahead) * 0.65:
		return int(LaneKind.FLANK_STARBOARD)
	if abeam >= 0.0:
		return int(LaneKind.FLANK_PORT)
	return int(LaneKind.FLANK_STARBOARD)


static func best_departure_lane_kind(berth_pos: Vector3, to_pos: Vector3, port_id: String) -> int:
	return best_lane_kind_for_direction(to_pos - berth_pos, port_rotation_y(port_id))


static func best_approach_lane_kind(berth_pos: Vector3, from_pos: Vector3, port_id: String) -> int:
	return best_lane_kind_for_direction(berth_pos - from_pos, port_rotation_y(port_id))


static func best_lane_kind(berth_pos: Vector3, from_pos: Vector3, port_id: String) -> int:
	return best_approach_lane_kind(berth_pos, from_pos, port_id)


static func collect_debug_polylines() -> Array:
	var out: Array = []
	if not _initialized:
		return out
	for port_id in _lanes.keys():
		var by_port: Dictionary = _lanes[port_id] as Dictionary
		for berth_key in by_port.keys():
			var by_berth: Dictionary = by_port[berth_key] as Dictionary
			for kind_key in by_berth.keys():
				var lane: Array = by_berth[kind_key] as Array
				if lane.size() < 2:
					continue
				out.append({
					"port_id": str(port_id),
					"berth_id": str(berth_key),
					"slice": int(kind_key),
					"points": lane.duplicate(),
				})
	return out


static func _port_frame(rotation_y: float) -> Dictionary:
	var seaward := _seaward_dir(rotation_y)
	var port := Vector3(-seaward.z, 0.0, seaward.x).normalized()
	return {
		"seaward": seaward,
		"landward": -seaward,
		"port": port,
		"starboard": -port,
	}


static func _island_meta_from_data(data: PortData) -> Dictionary:
	return {
		"port_id": data.port_id,
		"center": data.world_position,
		"half_x": data.island_width * 0.5 + LAND_PAD_M,
		"half_z": data.plot_depth * 0.5 + LAND_PAD_M,
		"rotation_y": data.rotation_y,
	}


static func _island_meta_from_plot(plot: PortPlot) -> Dictionary:
	return {
		"port_id": plot.port_id,
		"center": plot.global_position,
		"half_x": plot.plot_width * 0.5 + LAND_PAD_M,
		"half_z": plot.plot_depth * 0.5 + LAND_PAD_M,
		"rotation_y": plot.rotation.y,
	}


static func _seaward_dir(rotation_y: float) -> Vector3:
	var dir := Vector3(-sin(rotation_y), 0.0, -cos(rotation_y))
	if dir.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, -1.0)
	return dir.normalized()


static func _berth_world_from_plot_local(
	world_center: Vector3,
	rotation_y: float,
	dock_local: Vector3,
) -> Vector3:
	var basis := Basis.from_euler(Vector3(0.0, rotation_y, 0.0))
	var world := world_center + basis * dock_local
	world.y = WaveSurface.WATER_LEVEL
	return world


static func _world_to_port_local(world_pos: Vector3, island: Dictionary) -> Vector3:
	var center: Vector3 = island.get("center", Vector3.ZERO)
	var ry: float = island.get("rotation_y", 0.0)
	var offset := world_pos - center
	var basis := Basis.from_euler(Vector3(0.0, ry, 0.0)).inverse()
	var local := basis * offset
	local.y = WaveSurface.WATER_LEVEL
	return local


static func _port_local_to_world(local_pos: Vector3, island: Dictionary) -> Vector3:
	var center: Vector3 = island.get("center", Vector3.ZERO)
	var ry: float = island.get("rotation_y", 0.0)
	var basis := Basis.from_euler(Vector3(0.0, ry, 0.0))
	var world := center + basis * local_pos
	world.y = WaveSurface.WATER_LEVEL
	return world


static func _build_lane(berth: Vector3, kind: int, frame: Dictionary, island: Dictionary) -> Array:
	if island.is_empty():
		return [berth]
	match kind:
		int(LaneKind.SPINE):
			var local_berth := _world_to_port_local(berth, island)
			return _build_explicit_spine(local_berth, island)
		int(LaneKind.FLANK_PORT):
			var local_berth := _world_to_port_local(berth, island)
			return _build_explicit_flank(local_berth, island, true)
		int(LaneKind.FLANK_STARBOARD):
			var local_berth := _world_to_port_local(berth, island)
			return _build_explicit_flank(local_berth, island, false)
	return [berth]


static func _build_explicit_spine(berth_local: Vector3, island: Dictionary) -> Array:
	var half_z: float = island.get("half_z", 0.0)
	var local_pts: Array[Vector3] = [
		berth_local,
		Vector3(0.0, WaveSurface.WATER_LEVEL, -half_z - 70.0) # Node 0
	]
	var world_pts: Array = []
	for lp in local_pts:
		world_pts.append(_port_local_to_world(lp, island))
	return _densify_chain(world_pts)


static func _build_explicit_flank(berth_local: Vector3, island: Dictionary, is_port: bool) -> Array:
	var half_x: float = island.get("half_x", 0.0)
	var half_z: float = island.get("half_z", 0.0)
	
	var margin_x := 55.0
	var margin_z := 35.0
	
	var local_pts: Array[Vector3] = []
	local_pts.append(berth_local)
	
	if is_port:
		local_pts.append(Vector3(half_x + margin_x, WaveSurface.WATER_LEVEL, -half_z + 15.0)) # Node 1
		local_pts.append(Vector3(half_x + margin_x, WaveSurface.WATER_LEVEL, 50.0))                 # Node 2
		local_pts.append(Vector3(half_x + margin_x, WaveSurface.WATER_LEVEL, half_z + 85.0))  # Node 3
	else:
		local_pts.append(Vector3(-half_x - margin_x, WaveSurface.WATER_LEVEL, -half_z + 15.0)) # Node 7
		local_pts.append(Vector3(-half_x - margin_x, WaveSurface.WATER_LEVEL, 50.0))                 # Node 6
		local_pts.append(Vector3(-half_x - margin_x, WaveSurface.WATER_LEVEL, half_z + 85.0))  # Node 5
		
	var world_pts: Array = []
	for lp in local_pts:
		world_pts.append(_port_local_to_world(lp, island))
		
	return _densify_chain(world_pts)


static func _point_navigable(pos: Vector3) -> bool:
	if not LandField.is_initialized():
		return true
	var dist := LandField.distance_to_land(pos)
	if dist < 0.0:
		return false
	if dist < QUAY_ZONE_M:
		return dist >= 0.35
	if dist < NEAR_SHORE_ZONE_M:
		return dist >= 3.5
	if dist < MID_SHORE_ZONE_M:
		return dist >= 9.0
	return dist >= ROUTE_CLEARANCE_M


static func _densify_line(a: Vector3, b: Vector3) -> Array:
	return _densify_chain([a, b])


static func _densify_chain(points: Array) -> Array:
	if points.is_empty():
		return []
	var out: Array = [points[0]]
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var span := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
		var steps := maxi(1, int(ceil(span / STEP_M)))
		for s in range(1, steps + 1):
			var t := float(s) / float(steps)
			var p := a.lerp(b, t)
			p.y = WaveSurface.WATER_LEVEL
			if out.size() > 0:
				var last: Vector3 = out[out.size() - 1]
				if Vector2(last.x, last.z).distance_to(Vector2(p.x, p.z)) < 4.0:
					continue
			out.append(p)
	return out


static func _polyline_clear(a: Vector3, b: Vector3) -> bool:
	if not LandField.is_initialized():
		return true
	var span := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	var steps := maxi(6, int(ceil(span / 14.0)))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		if not _point_navigable(p):
			return false
	return true


static func _rotate_dir(dir: Vector3, rad: float) -> Vector3:
	var c := cos(rad)
	var s := sin(rad)
	return Vector3(dir.x * c - dir.z * s, 0.0, dir.x * s + dir.z * c).normalized()


static func _array_xz(raw: Variant) -> Vector2:
	var values := raw as Array
	if values.size() < 2:
		return Vector2.ZERO
	return Vector2(float(values[0]), float(values[1]))


static func _vec3_is_valid(v: Vector3) -> bool:
	return v.is_finite() and absf(v.x) < 1.0e8 and absf(v.z) < 1.0e8
