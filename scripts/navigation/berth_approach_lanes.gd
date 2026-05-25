class_name BerthApproachLanes
extends RefCounted

## Island-owned berth lanes — three port-relative paths per berth:
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
const LAND_PAD_M := IslandMeshBuilder.MARGIN + IslandMeshBuilder.AMPLITUDE
const QUAY_ZONE_M := 14.0
const NEAR_SHORE_ZONE_M := 55.0
const MID_SHORE_ZONE_M := 180.0
const ROUTE_CLEARANCE_M := 18.0
const FLANK_DEFLECT_DEG: Array[float] = [12.0, 24.0, 36.0, 48.0, 60.0, 75.0]

static var _initialized: bool = false
static var _lanes: Dictionary = {}  ## port_id -> berth_index -> lane_kind -> Array[Vector3]
static var _berth_positions: Dictionary = {}
static var _islands: Dictionary = {}
static var _live_baked_ports: Dictionary = {}
static var debug_visible: bool = false


static func bake_all_ports(defs: Array, world_seed: int) -> void:
	if not LandField.is_initialized():
		push_warning("BerthApproachLanes: LandField not ready — skipping port bake")
		return
	var lane_count := 0
	for def_raw in defs:
		var def := def_raw as PortDefinition
		if def == null:
			continue
		var data := PortExpander.expand(def, world_seed)
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

	var island := _island_meta_from_data(data)
	_islands[data.port_id] = island
	var frame := _port_frame(data.rotation_y)

	var berth_n := data.berth_types.size()
	if berth_n <= 0:
		berth_n = maxi(data.berth_count, 1)
	var half_beam := ShipClass.beam(data.max_ship_class) * 0.5
	var slot_w := data.dock_length / float(berth_n)
	var port_lanes: Dictionary = {}
	var port_berths: Dictionary = {}
	var baked := 0

	for berth_index in range(berth_n):
		var cx := -data.dock_length * 0.5 + slot_w * (float(berth_index) + 0.5)
		var berth_pos := _berth_world_from_plot_local(
			data.world_position,
			data.rotation_y,
			Vector3(cx, WaveSurface.WATER_LEVEL, -(half_beam + PortDock.BERTH_QUAY_GAP_M)),
		)
		if not _vec3_is_valid(berth_pos):
			continue
		port_berths[berth_index] = berth_pos
		var kind_lanes: Dictionary = {}
		for kind in range(LANE_KIND_COUNT):
			var lane := _build_lane(berth_pos, kind, frame, island)
			kind_lanes[kind] = lane
			if lane.size() >= 2:
				baked += 1
		port_lanes[berth_index] = kind_lanes

	_lanes[data.port_id] = port_lanes
	_berth_positions[data.port_id] = port_berths
	return baked


static func bake_from_dock(port_id: String, dock: PortDock) -> int:
	if port_id.is_empty() or dock == null or not is_instance_valid(dock):
		return 0
	if not LandField.is_initialized():
		return 0

	var plot := dock.get_parent() as PortPlot
	var island := _islands.get(port_id, {}) as Dictionary
	if island.is_empty() and plot != null:
		island = _island_meta_from_plot(plot)
	_islands[port_id] = island
	var ry := plot.rotation.y if plot != null else float(island.get("rotation_y", 0.0))
	var frame := _port_frame(ry)

	var count := dock.berth_count()
	var port_lanes: Dictionary = {}
	var port_berths: Dictionary = {}
	var baked := 0

	for berth_index in range(count):
		var local := dock.berth_reference_local_midship(berth_index)
		var berth_pos := dock.to_global(local) as Vector3
		berth_pos.y = WaveSurface.WATER_LEVEL
		if not _vec3_is_valid(berth_pos):
			continue
		port_berths[berth_index] = berth_pos
		var kind_lanes: Dictionary = {}
		for kind in range(LANE_KIND_COUNT):
			var lane := _build_lane(berth_pos, kind, frame, island)
			kind_lanes[kind] = lane
			if lane.size() >= 2:
				baked += 1
		port_lanes[berth_index] = kind_lanes

	_lanes[port_id] = port_lanes
	_berth_positions[port_id] = port_berths
	_live_baked_ports[port_id] = true
	_initialized = true
	print("[BerthApproachLanes] Dock bake %s: %d berth(s), %d lane(s)" % [port_id, count, baked])
	return baked


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
	var by_port: Variant = _berth_positions.get(port_id, {})
	if typeof(by_port) != TYPE_DICTIONARY:
		return Vector3.ZERO
	var pos: Variant = (by_port as Dictionary).get(berth_index, Vector3.ZERO)
	return pos as Vector3 if pos is Vector3 else Vector3.ZERO


static func berth_count_for_port(port_id: String) -> int:
	var by_port: Variant = _berth_positions.get(port_id, {})
	if typeof(by_port) != TYPE_DICTIONARY:
		return 0
	return (by_port as Dictionary).size()


static func get_lane(port_id: String, berth_index: int, lane_kind: int) -> Array:
	var by_port: Variant = _lanes.get(port_id, {})
	if typeof(by_port) != TYPE_DICTIONARY:
		return []
	var by_berth: Variant = (by_port as Dictionary).get(berth_index, {})
	if typeof(by_berth) != TYPE_DICTIONARY:
		return []
	var lane: Variant = (by_berth as Dictionary).get(lane_kind, [])
	return lane as Array if typeof(lane) == TYPE_ARRAY else []


static func lane_outer_point(port_id: String, berth_index: int, lane_kind: int) -> Vector3:
	var lane := get_lane(port_id, berth_index, lane_kind)
	if lane.size() >= 2:
		return lane[lane.size() - 1] as Vector3
	return berth_world_position(port_id, berth_index)


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
					"berth": int(berth_key),
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
		"half_z": PLOT_DEPTH_M * 0.5 + LAND_PAD_M,
		"rotation_y": data.rotation_y,
	}


static func _island_meta_from_plot(plot: PortPlot) -> Dictionary:
	var facilities := plot.get_node_or_null("PortFacilities") as PortFacilities
	var island_w := facilities.plot_width if facilities != null else plot.plot_width
	return {
		"port_id": plot.port_id,
		"center": plot.global_position,
		"half_x": island_w * 0.5 + LAND_PAD_M,
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
	var hd := PLOT_DEPTH_M * 0.5
	var plot_local := Vector3(0.0, 0.0, -hd) + dock_local
	var basis := Basis.from_euler(Vector3(0.0, rotation_y, 0.0))
	var world := world_center + basis * plot_local
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


static func _vec3_is_valid(v: Vector3) -> bool:
	return v.is_finite() and absf(v.x) < 1.0e8 and absf(v.z) < 1.0e8
