class_name PortLayoutGraph
extends RefCounted

## Authoritative port layout container. Live generation stores a foundation
## anchor plus `initial_attributes["berth_plan"]` (asphalt / quay stations).
## Module attach/open-slot APIs remain for future growth; they are not how
## trade berths are placed today.

const FORMAT_VERSION := 1
const OVERLAP_EPS_M := 0.05

var port_id := ""
var site_id := ""
var site_seed := 0
var generation_version := 1
var initial_attributes: Dictionary = {}
var modules: Dictionary = {} ## instance_id -> PortPlacedModule
var edges: Array[Dictionary] = []


func size_class() -> int:
	return PortSizing.normalized_size(int(initial_attributes.get(
		"size",
		PortSizing.CATALOG_REFERENCE_SIZE,
	)))


func module_definition(module_id: String) -> PortModuleDefinition:
	return PortModuleCatalog.definition_for_size(module_id, size_class())


func add_root(
		module_id: String,
		instance_id: String = "root",
		position_m: Vector3 = Vector3.ZERO,
		yaw_degrees: float = 0.0,
		assignment: Dictionary = {},
) -> bool:
	if not modules.is_empty() or modules.has(instance_id):
		return false
	var definition := module_definition(module_id)
	if definition == null or not definition.tags.has("root"):
		return false
	var placed := PortPlacedModule.new()
	placed.instance_id = instance_id
	placed.module_id = module_id
	placed.position_m = position_m
	placed.yaw_degrees = yaw_degrees
	placed.assignment = assignment.duplicate(true)
	modules[instance_id] = placed
	return true


func attach_module(
		parent_instance_id: String,
		parent_slot_id: String,
		module_id: String,
		instance_id: String,
		assignment: Dictionary = {},
) -> bool:
	if modules.has(instance_id):
		return false
	var parent := modules.get(parent_instance_id) as PortPlacedModule
	var parent_def := module_definition(parent.module_id) if parent != null else null
	var child_def := module_definition(module_id)
	if parent == null or parent_def == null or child_def == null:
		return false
	if parent.consumes(parent_slot_id):
		return false
	var output := parent_def.output_slot(parent_slot_id)
	if output.is_empty():
		return false
	var output_type := str(output.get("type", ""))
	var input := child_def.input_for(output_type)
	if input.is_empty():
		return false

	var parent_basis := Basis(Vector3.UP, deg_to_rad(parent.yaw_degrees))
	var output_position := parent.position_m + parent_basis * (output.get("position_m", Vector3.ZERO) as Vector3)
	var output_yaw := parent.yaw_degrees + float(output.get("yaw_degrees", 0.0))
	var child_yaw := wrapf(
		output_yaw + 180.0 - float(input.get("yaw_degrees", 0.0)),
		-180.0,
		180.0,
	)
	var child_basis := Basis(Vector3.UP, deg_to_rad(child_yaw))
	var child_position := output_position - child_basis * (input.get("position_m", Vector3.ZERO) as Vector3)

	var child := PortPlacedModule.new()
	child.instance_id = instance_id
	child.module_id = module_id
	child.parent_instance_id = parent_instance_id
	child.parent_slot_id = parent_slot_id
	child.input_slot_id = str(input.get("id", ""))
	child.position_m = child_position
	child.yaw_degrees = child_yaw
	child.assignment = assignment.duplicate(true)
	if _overlaps_existing(child, child_def):
		return false

	parent.consume(parent_slot_id)
	modules[instance_id] = child
	edges.append({
		"parent_instance_id": parent_instance_id,
		"parent_slot_id": parent_slot_id,
		"child_instance_id": instance_id,
		"child_input_slot_id": child.input_slot_id,
	})
	return true


func open_slots(slot_type: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for instance_id in module_ids():
		var placed := modules[instance_id] as PortPlacedModule
		var definition := module_definition(placed.module_id)
		if definition == null:
			continue
		var basis := Basis(Vector3.UP, deg_to_rad(placed.yaw_degrees))
		for slot in definition.output_slots():
			var current_type := str(slot.get("type", ""))
			if placed.consumes(str(slot.get("id", ""))):
				continue
			if not slot_type.is_empty() and current_type != slot_type:
				continue
			out.append({
				"slot_id": "%s:%s" % [instance_id, str(slot.get("id", ""))],
				"parent_instance_id": instance_id,
				"parent_slot_id": str(slot.get("id", "")),
				"type": current_type,
				"position_m": placed.position_m + basis * (slot.get("position_m", Vector3.ZERO) as Vector3),
				"yaw_degrees": wrapf(
					placed.yaw_degrees + float(slot.get("yaw_degrees", 0.0)),
					-180.0,
					180.0,
				),
			})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("slot_id", "")) < str(b.get("slot_id", ""))
	)
	return out


func module_ids() -> Array[String]:
	var out: Array[String] = []
	for key in modules.keys():
		out.append(str(key))
	out.sort()
	return out


func bounds() -> AABB:
	if modules.is_empty():
		return AABB(Vector3.ZERO, Vector3.ZERO)
	var min_point := Vector3(INF, 0.0, INF)
	var max_point := Vector3(-INF, 0.0, -INF)
	var max_height := 0.0
	for instance_id in module_ids():
		var placed := modules[instance_id] as PortPlacedModule
		var definition := module_definition(placed.module_id)
		if definition == null:
			continue
		for corner in _corners(placed, definition):
			min_point.x = minf(min_point.x, corner.x)
			min_point.z = minf(min_point.z, corner.y)
			max_point.x = maxf(max_point.x, corner.x)
			max_point.z = maxf(max_point.z, corner.y)
		max_height = maxf(max_height, definition.footprint_m.y)
	var foundation := initial_attributes.get("foundation", {}) as Dictionary
	var spine := foundation.get("spine", []) as Array
	var inland_m := float(foundation.get("town_inland_m", PortCoastTracer.FOUNDATION_TOWN_INLAND_M))
	var sea_m := float(foundation.get("dock_reach_m", PortCoastTracer.FOUNDATION_DOCK_REACH_M)) \
			+ float(foundation.get("bay_lip_m", PortCoastTracer.FOUNDATION_BAY_LIP_M))
	var spine_pts := PackedVector2Array()
	for raw_point in spine:
		var point := raw_point as Array
		if point.size() < 2:
			continue
		spine_pts.append(Vector2(float(point[0]), float(point[1])))
	if spine_pts.size() >= 2:
		var inland_pts := PortCoastTracer.offset_spine_perpendicular(
			spine_pts, inland_m, PortCoastTracer.PORT_LOCAL_INLAND_DIR, true,
		)
		var sea_pts := PortCoastTracer.offset_spine_perpendicular(
			spine_pts, sea_m, PortCoastTracer.PORT_LOCAL_INLAND_DIR, false,
		)
		for corner_set in [spine_pts, inland_pts, sea_pts]:
			for corner in corner_set:
				min_point.x = minf(min_point.x, corner.x)
				min_point.z = minf(min_point.z, corner.y)
				max_point.x = maxf(max_point.x, corner.x)
				max_point.z = maxf(max_point.z, corner.y)
				max_height = maxf(max_height, 0.9)
	if not min_point.is_finite() or not max_point.is_finite():
		return AABB(Vector3.ZERO, Vector3.ZERO)
	return AABB(
		Vector3(min_point.x, 0.0, min_point.z),
		Vector3(max_point.x - min_point.x, max_height, max_point.z - min_point.z),
	)


func spawn_local_position() -> Vector3:
	## Prefer foundation apron (landward of the dock spine) — berth_plan ports
	## no longer stamp road modules, so the old road search always missed.
	var foundation := initial_attributes.get("foundation", {}) as Dictionary
	var surface_y := float(foundation.get("surface_y_m", PortCoastTracer.FOUNDATION_SURFACE_Y_M))
	var top_y := surface_y + PortCoastTracer.FOUNDATION_TERRAIN_CLEARANCE_M
	var spine := foundation.get("spine", []) as Array
	if spine.size() >= 2:
		var mid_i := int(spine.size() / 2)
		var mid_raw: Array = spine[mid_i] as Array
		if mid_raw.size() >= 2:
			var inland := PortCoastTracer.PORT_LOCAL_INLAND_DIR
			var inland_m := clampf(
				float(foundation.get("town_inland_m", PortCoastTracer.FOUNDATION_TOWN_INLAND_M)) * 0.35,
				8.0,
				18.0,
			)
			return Vector3(
				float(mid_raw[0]) + inland.x * inland_m,
				top_y + 1.0,
				float(mid_raw[1]) + inland.y * inland_m,
			)
	var berth_plan := initial_attributes.get("berth_plan", {}) as Dictionary
	var asphalt: Array = berth_plan.get("asphalt_stations", []) as Array
	if not asphalt.is_empty():
		var station: Dictionary = asphalt[0] as Dictionary
		var origin: Array = station.get("origin", [0.0, 0.0]) as Array
		if origin.size() >= 2:
			var inland2 := PortCoastTracer.PORT_LOCAL_INLAND_DIR
			return Vector3(
				float(origin[0]) + inland2.x * 10.0,
				top_y + 1.0,
				float(origin[1]) + inland2.y * 10.0,
			)
	var best := Vector3(0.0, top_y + 1.0, 18.0)
	var best_landward := -INF
	for instance_id in module_ids():
		var placed := modules[instance_id] as PortPlacedModule
		var definition := module_definition(placed.module_id)
		if definition != null and definition.kind == "road" and placed.position_m.z > best_landward:
			best_landward = placed.position_m.z
			best = placed.position_m + Vector3(0.0, 1.2, 0.0)
	return best


func primary_quay_pose() -> Dictionary:
	var from_plan := _primary_quay_pose_from_berth_plan()
	if not from_plan.is_empty():
		return from_plan
	var best := {
		"position_m": Vector3(0.0, 0.0, -15.0),
		"yaw_degrees": 0.0,
		"length_m": 20.0,
		"width_m": 8.0,
	}
	var best_length := 0.0
	for instance_id in module_ids():
		var placed := modules[instance_id] as PortPlacedModule
		var definition := module_definition(placed.module_id)
		if definition == null or definition.kind != "quay":
			continue
		var chain_length := definition.footprint_m.z
		## Walk seaward extensions belonging to this arm.
		var tip := instance_id
		while true:
			var next_id := ""
			for edge in edges:
				if str(edge.get("parent_instance_id", "")) != tip:
					continue
				if str(edge.get("parent_slot_id", "")) != "extend":
					continue
				next_id = str(edge.get("child_instance_id", ""))
				break
			if next_id.is_empty():
				break
			var ext := modules.get(next_id) as PortPlacedModule
			var ext_def := module_definition(ext.module_id) if ext != null else null
			if ext_def == null:
				break
			chain_length += ext_def.footprint_m.z
			tip = next_id
		if chain_length > best_length:
			best_length = chain_length
			best = {
				"position_m": placed.position_m,
				"yaw_degrees": placed.yaw_degrees,
				"length_m": chain_length,
				"width_m": definition.footprint_m.x,
			}
	return best


func total_quay_length_m() -> float:
	var plan := initial_attributes.get("berth_plan", {}) as Dictionary
	var stations: Array = plan.get("quay_stations", []) as Array
	var total := 0.0
	if not stations.is_empty():
		for raw in stations:
			total += float((raw as Dictionary).get("length_m", 0.0))
		return total
	for instance_id in module_ids():
		var placed := modules[instance_id] as PortPlacedModule
		var definition := module_definition(placed.module_id)
		if definition != null and definition.kind == "quay":
			total += definition.footprint_m.z
	return total


## Centers of seaward-pointing quay roots (yaw near 0 in port space), sorted by X.
func parallel_seaward_pier_centers() -> Array[Vector2]:
	var plan := initial_attributes.get("berth_plan", {}) as Dictionary
	var stations: Array = plan.get("quay_stations", []) as Array
	if not stations.is_empty():
		var from_plan: Array[Vector2] = []
		for raw in stations:
			var station := raw as Dictionary
			var origin: Array = station.get("origin", []) as Array
			if origin.size() < 2:
				continue
			from_plan.append(Vector2(float(origin[0]), float(origin[1])))
		from_plan.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		return from_plan
	var centers: Array[Vector2] = []
	for instance_id in module_ids():
		var placed := modules[instance_id] as PortPlacedModule
		var definition := module_definition(placed.module_id)
		if definition == null or definition.kind != "quay":
			continue
		## Only root pier stubs / arms — skip mid-chain extensions for spacing.
		if placed.parent_slot_id == "extend":
			continue
		var yaw := wrapf(placed.yaw_degrees, -180.0, 180.0)
		if absf(yaw) > 1.0 and absf(absf(yaw) - 180.0) > 1.0:
			continue
		centers.append(Vector2(placed.position_m.x, placed.position_m.z))
	centers.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.x < b.x
	)
	return centers


func flatten_zone_records(
		world_position: Vector3,
		rotation_y: float,
		height_m := -1.0,
) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var port_basis := Basis(Vector3.UP, rotation_y)
	var foundation := initial_attributes.get("foundation", {}) as Dictionary
	var pad_height := height_m
	if pad_height < 0.0:
		pad_height = float(foundation.get("surface_y_m", PortCoastTracer.FOUNDATION_SURFACE_Y_M)) - 0.12
	var foundation_segments := foundation.get("segments", []) as Array
	var spine := foundation.get("spine", []) as Array
	var graph_bounds := bounds()
	if not spine.is_empty():
		## Harbour foundations are extruded meshes — natural terrain is untouched.
		pass
	elif graph_bounds.size.length_squared() > 0.01 and foundation_segments.is_empty():
		var size_class := PortSizing.normalized_size(int(initial_attributes.get("size", 1)))
		var seaward := Vector2(-sin(rotation_y), -cos(rotation_y))
		var center_world := world_position + port_basis * graph_bounds.get_center()
		var envelope_center := Vector2(center_world.x, center_world.z) \
				+ seaward * PortSizing.PAD_SEAWARD_SHIFT_M
		records.append({
			"center": envelope_center,
			"yaw": rotation_y,
			"half_size": Vector2(
				maxf(graph_bounds.size.x * 0.5 + 24.0, PortSizing.terrain_pad_width_m(size_class) * 0.5),
				maxf(graph_bounds.size.z * 0.5 + 24.0, PortSizing.PAD_DEPTH_M * 0.5),
			),
			"falloff": 70.0 + float(size_class) * 15.0,
			"height": height_m,
			"shape": "rectangle",
			"carve": false,
			"facility_id": "%s:site_envelope" % port_id,
		})
	for instance_id in module_ids():
		var placed := modules[instance_id] as PortPlacedModule
		var definition := module_definition(placed.module_id)
		if definition == null:
			continue
		var carve := definition.tags.has("water") or definition.tags.has("waterfront")
		var center := world_position + port_basis * placed.position_m
		records.append({
			"center": Vector2(center.x, center.z),
			"yaw": rotation_y + deg_to_rad(placed.yaw_degrees),
			"half_size": Vector2(definition.footprint_m.x, definition.footprint_m.z) * 0.5,
			"falloff": 12.0 if carve else 18.0,
			"height": height_m,
			"shape": "rectangle",
			"carve": carve,
			"facility_id": "%s:%s" % [port_id, instance_id],
		})
	## Town trapezoid clears forest only — does not flatten hinterland hills.
	var town_clear := forest_clear_polygon(world_position, rotation_y)
	if town_clear.size() >= 3:
		records.append({
			"forest_clear_only": true,
			"polygon": town_clear,
			"facility_id": "%s:town_forest_clear" % port_id,
		})
	return records


## World-space buildable land polygon (apron + hinterland), padded for tree clear.
func forest_clear_polygon(
		world_position: Vector3,
		rotation_y: float,
		pad_m: float = PortLandPlan.FOREST_CLEAR_PAD_M,
) -> PackedVector2Array:
	var land: Dictionary = initial_attributes.get("land_plan", {}) as Dictionary
	var zone: Dictionary = land.get("buildable_zone", {}) as Dictionary
	if zone.is_empty():
		return PackedVector2Array()
	return PortLandPlan.world_buildable_polygon(zone, world_position, rotation_y, pad_m)


func local_footprints() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var foundation := initial_attributes.get("foundation", {}) as Dictionary
	var foundation_segments := foundation.get("segments", []) as Array
	if not foundation_segments.is_empty():
		for index in range(foundation_segments.size()):
			var segment := foundation_segments[index] as Dictionary
			var center := segment.get("center", [0.0, 0.0]) as Array
			if center.size() < 2:
				continue
			out.append({
				"id": "foundation_%d" % index,
				"facility_id": "%s:foundation_%d" % [port_id, index],
				"center_m": Vector2(float(center[0]), float(center[1])),
				"size_m": Vector2(
					float(segment.get("length_m", 1.0)),
					float(segment.get("width_m", 1.0)),
				),
				"yaw_degrees": float(segment.get("yaw_degrees", 0.0)),
				"shape": "rectangle",
				"requires_land": false,
			})
		return out
	for instance_id in module_ids():
		var placed := modules[instance_id] as PortPlacedModule
		var definition := module_definition(placed.module_id)
		if definition == null:
			continue
		out.append({
			"id": instance_id,
			"facility_id": "%s:%s" % [port_id, instance_id],
			"center_m": Vector2(placed.position_m.x, placed.position_m.z),
			"size_m": Vector2(definition.footprint_m.x, definition.footprint_m.z),
			"yaw_degrees": placed.yaw_degrees,
			"shape": "rectangle",
			"requires_land": not (
				definition.tags.has("water") or definition.tags.has("waterfront")
			),
		})
	return out


func to_dict() -> Dictionary:
	var serialized_modules: Array = []
	for instance_id in module_ids():
		serialized_modules.append((modules[instance_id] as PortPlacedModule).to_dict())
	var serialized_edges := edges.duplicate(true)
	serialized_edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("child_instance_id", "")) < str(b.get("child_instance_id", ""))
	)
	return {
		"format_version": FORMAT_VERSION,
		"generation_version": generation_version,
		"port_id": port_id,
		"site_id": site_id,
		"site_seed": site_seed,
		"initial_attributes": initial_attributes.duplicate(true),
		"modules": serialized_modules,
		"edges": serialized_edges,
	}


static func from_dict(raw: Dictionary) -> PortLayoutGraph:
	if int(raw.get("format_version", -1)) != FORMAT_VERSION:
		return null
	var out := PortLayoutGraph.new()
	out.generation_version = int(raw.get("generation_version", 1))
	out.port_id = str(raw.get("port_id", ""))
	out.site_id = str(raw.get("site_id", ""))
	out.site_seed = int(raw.get("site_seed", 0))
	out.initial_attributes = (raw.get("initial_attributes", {}) as Dictionary).duplicate(true)
	for module_raw in raw.get("modules", []) as Array:
		if typeof(module_raw) != TYPE_DICTIONARY:
			continue
		var placed := PortPlacedModule.from_dict(module_raw as Dictionary)
		if placed.instance_id.is_empty() or out.modules.has(placed.instance_id):
			return null
		out.modules[placed.instance_id] = placed
	for edge_raw in raw.get("edges", []) as Array:
		if typeof(edge_raw) == TYPE_DICTIONARY:
			out.edges.append((edge_raw as Dictionary).duplicate(true))
	return out


func is_graph_connected() -> bool:
	if modules.is_empty():
		return false
	if modules.size() == 1:
		return true
	var children: Dictionary = {}
	for edge in edges:
		children[str(edge.get("child_instance_id", ""))] = true
	for instance_id in module_ids():
		if instance_id == "root":
			continue
		if not children.has(instance_id):
			return false
	return children.size() == modules.size() - 1


func _primary_quay_pose_from_berth_plan() -> Dictionary:
	var plan := initial_attributes.get("berth_plan", {}) as Dictionary
	var stations: Array = plan.get("quay_stations", []) as Array
	if stations.is_empty():
		stations = plan.get("asphalt_stations", []) as Array
	if stations.is_empty():
		return {}
	var best: Dictionary = {}
	var best_length := -1.0
	for raw in stations:
		var station := raw as Dictionary
		var length_m := float(station.get("length_m", 0.0))
		if length_m <= best_length:
			continue
		var origin: Array = station.get("origin", []) as Array
		var direction: Array = station.get("direction", []) as Array
		if origin.size() < 2:
			continue
		var dir := Vector2(
			float(direction[0]) if direction.size() > 0 else 0.0,
			float(direction[1]) if direction.size() > 1 else -1.0,
		)
		if dir.length_squared() < 0.0001:
			dir = Vector2(0.0, -1.0)
		else:
			dir = dir.normalized()
		## Port-local: X across, Z along seaward. Yaw 0 faces −Z.
		var yaw_degrees := rad_to_deg(atan2(dir.x, -dir.y))
		best_length = length_m
		best = {
			"position_m": Vector3(float(origin[0]), 0.0, float(origin[1])),
			"yaw_degrees": yaw_degrees,
			"length_m": length_m,
			"width_m": float(station.get("width_m", station.get("depth_m", 8.0))),
		}
	return best


func _overlaps_existing(candidate: PortPlacedModule, definition: PortModuleDefinition) -> bool:
	var candidate_corners := _corners(candidate, definition)
	for instance_id in module_ids():
		## Apron cargo / crane pads intentionally sit on their parent quay deck.
		if instance_id == candidate.parent_instance_id:
			continue
		var existing := modules[instance_id] as PortPlacedModule
		var existing_def := module_definition(existing.module_id)
		if existing_def == null:
			continue
		if _rectangles_overlap(candidate_corners, _corners(existing, existing_def)):
			return true
	return false


static func _corners(placed: PortPlacedModule, definition: PortModuleDefinition) -> Array[Vector2]:
	var half := Vector2(definition.footprint_m.x, definition.footprint_m.z) * 0.5
	var basis := Basis(Vector3.UP, deg_to_rad(placed.yaw_degrees))
	var out: Array[Vector2] = []
	for local_raw in [
		Vector3(-half.x, 0.0, -half.y),
		Vector3(half.x, 0.0, -half.y),
		Vector3(half.x, 0.0, half.y),
		Vector3(-half.x, 0.0, half.y),
	]:
		var local := local_raw as Vector3
		var point := placed.position_m + basis * local
		out.append(Vector2(point.x, point.z))
	return out


static func _world_zone_yaw(port_basis: Basis, zone: Dictionary) -> float:
	var dir_local := zone.get("direction_local", []) as Array
	var local_dir := Vector3(1.0, 0.0, 0.0)
	if dir_local.size() >= 2:
		local_dir = Vector3(float(dir_local[0]), 0.0, float(dir_local[1]))
	else:
		var yaw_rad := deg_to_rad(float(zone.get("yaw_degrees", 0.0)))
		local_dir = Vector3(cos(yaw_rad), 0.0, -sin(yaw_rad))
	var world_dir := port_basis * local_dir
	return atan2(world_dir.z, world_dir.x)


static func _rectangles_overlap(a: Array[Vector2], b: Array[Vector2]) -> bool:
	for polygon in [a, b]:
		for i in range(polygon.size()):
			var edge: Vector2 = polygon[(i + 1) % polygon.size()] - polygon[i]
			var axis := Vector2(-edge.y, edge.x).normalized()
			var a_range := _project(a, axis)
			var b_range := _project(b, axis)
			if a_range.y <= b_range.x + OVERLAP_EPS_M \
					or b_range.y <= a_range.x + OVERLAP_EPS_M:
				return false
	return true


static func _project(points: Array[Vector2], axis: Vector2) -> Vector2:
	var min_value := INF
	var max_value := -INF
	for point in points:
		var value := point.dot(axis)
		min_value = minf(min_value, value)
		max_value = maxf(max_value, value)
	return Vector2(min_value, max_value)
