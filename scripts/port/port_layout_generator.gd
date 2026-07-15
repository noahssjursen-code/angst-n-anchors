class_name PortLayoutGenerator
extends RefCounted

const CoastTracer := preload("res://scripts/port/port_coast_tracer.gd")

## Terrain-traced port layout:
##   1) square port area
##   2) trace coast edge inside it
##   3) pick harbour span on the natural shoreline
##   4) grow mainland seaward + reclaim terrain for dock pavement


static func generate(
		definition: PortDefinition,
		profile: PortTradeProfile,
		site_seed: int,
		attributes: Dictionary = {},
) -> PortLayoutGraph:
	var graph := PortLayoutGraph.new()
	graph.port_id = definition.port_id
	graph.site_id = definition.site_id
	graph.site_seed = site_seed
	graph.generation_version = definition.port_generation_version
	graph.initial_attributes = attributes.duplicate(true)
	graph.initial_attributes.erase("world_layout")
	var size := PortSizing.normalized_size(definition.size)
	graph.initial_attributes["size"] = size
	graph.initial_attributes["region_kind"] = int(definition.region_kind)
	graph.initial_attributes["exports"] = profile.export_slots.duplicate()
	graph.initial_attributes["imports"] = profile.import_slots.duplicate()

	var layout := attributes.get("world_layout") as WorldLayout
	var half_width := CoastTracer.port_area_half_width_m(size)
	var half_depth := CoastTracer.port_area_half_depth_m(size)
	var traced_coast := _trace_coast(
		layout,
		definition,
		site_seed,
		half_width,
		half_depth,
	)
	traced_coast = CoastTracer.orient_seaward(
		layout,
		definition.world_position,
		definition.rotation_y,
		traced_coast,
	)
	var fit := CoastTracer.fit_port_shoreline(
		layout,
		definition.world_position,
		definition.rotation_y,
		traced_coast,
		size,
		site_seed,
		0.0,
		str(attributes.get("length_profile_override", "")),
	)
	var coast_path: PackedVector2Array = fit.get("harbour_coast", PackedVector2Array()) as PackedVector2Array
	var natural_shore: PackedVector2Array = fit.get("natural_shore", PackedVector2Array()) as PackedVector2Array
	graph.initial_attributes["port_area"] = {
		"half_width_m": half_width,
		"half_depth_m": half_depth,
		"half_extent_m": maxf(half_width, half_depth),
		"coast_polyline": _polyline_to_array(coast_path),
		"natural_shore_polyline": _polyline_to_array(natural_shore),
		"terrain_coast_polyline": _polyline_to_array(traced_coast),
		"harbour_style": str(fit.get("style", "")),
		"length_profile": str(fit.get("length_profile", "")),
		"span_coast_polyline": _polyline_to_array(fit.get("span_coast", PackedVector2Array()) as PackedVector2Array),
	}
	var center := coast_path[int(float(coast_path.size()) * 0.5)] if not coast_path.is_empty() else Vector2.ZERO
	graph.add_root("coast_vertex", "root", Vector3(center.x, 0.0, center.y), 0.0, {"role": "foundation_anchor"})
	var foundation: Dictionary = fit.get("foundation", {}) as Dictionary
	foundation["dock_reach_m"] = fit.get("dock_reach_m", foundation.get("dock_reach_m", 0.0))
	foundation["shore_length_m"] = fit.get("shore_length_m", 0.0)
	foundation["length_profile"] = fit.get("length_profile", foundation.get("length_profile", ""))
	foundation["design_hull_loa_m"] = fit.get("design_hull_loa_m", PortSizing.design_hull_loa_m(size))
	graph.initial_attributes["foundation"] = foundation
	return graph


static func _trace_coast(
		layout: WorldLayout,
		definition: PortDefinition,
		site_seed: int,
		half_width: float,
		half_depth: float,
) -> PackedVector2Array:
	if layout != null:
		var traced := CoastTracer.trace_in_port_area(
			layout,
			definition.world_position,
			definition.rotation_y,
			half_width,
			half_depth,
		)
		if traced.size() >= 2:
			return traced
	return CoastTracer.synthetic_coast(site_seed, half_width, half_depth)


static func _polyline_to_array(path: PackedVector2Array) -> Array:
	var out: Array = []
	for point in path:
		out.append([point.x, point.y])
	return out


static func _build_coast_chain(
		graph: PortLayoutGraph,
		coast_path: PackedVector2Array,
		size: int,
) -> Array[String]:
	var vertex_ids: Array[String] = []
	if coast_path.size() < 2:
		graph.add_root(
			"coast_vertex",
			"root",
			Vector3(0.0, 0.0, PortSizing.COASTAL_GRAPH_ROOT_Z_M),
			0.0,
			{"role": "coast_root"},
		)
		return ["root"]

	var yaws: Array[float] = []
	for i in range(coast_path.size()):
		var next_i := mini(i + 1, coast_path.size() - 1)
		var prev_i := maxi(i - 1, 0)
		var dir := coast_path[next_i] - coast_path[prev_i]
		if dir.length_squared() < 0.01:
			dir = Vector2(1.0, 0.0)
		yaws.append(rad_to_deg(atan2(-dir.y, dir.x)))

	graph.add_root(
		"coast_vertex",
		"root",
		Vector3(coast_path[0].x, 0.0, coast_path[0].y),
		yaws[0],
		{"role": "coast_root", "vertex_index": 0},
	)
	vertex_ids.append("root")

	var parent_id := "root"
	for index in range(1, coast_path.size()):
		var prev_yaw := float(yaws[index - 1])
		var yaw := float(yaws[index])
		var extra_yaw := wrapf(yaw - prev_yaw, -180.0, 180.0)
		var vertex_id := "coast_%d" % index
		if not _attach_coast_link(
			graph,
			parent_id,
			"along_next",
			vertex_id,
			coast_path[index],
			yaw,
			extra_yaw,
			{"role": "coast_vertex", "vertex_index": index},
		):
			break
		vertex_ids.append(vertex_id)
		parent_id = vertex_id
	return vertex_ids


static func _build_foundation_harbour(
		graph: PortLayoutGraph,
		vertex_ids: Array[String],
		size: int,
		site_seed: int,
) -> Dictionary:
	var foundation_count := mini(clampi(1 + size / 2, 1, 4), vertex_ids.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = site_seed ^ 0x464F554E
	var land_pavements: Array[String] = []
	var docks: Array[Dictionary] = []
	for foundation_index in range(foundation_count):
		var vertex_index := int(round(
			float(foundation_index + 1) * float(vertex_ids.size() - 1)
			/ float(foundation_count + 1)
		))
		vertex_index = clampi(vertex_index, 0, vertex_ids.size() - 1)
		var vertex_id := vertex_ids[vertex_index]
		var land_id := "mainland_pavement_%d" % foundation_index
		if graph.attach_module(
			vertex_id,
			"backland",
			"land_pavement",
			land_id,
			{"role": "mainland_ground", "foundation_index": foundation_index},
		):
			land_pavements.append(land_id)
		var angle := 90 if rng.randf() < 0.62 else 45
		var side := -1 if rng.randf() < 0.5 else 1
		var yaw_offset := 0.0 if angle == 90 else 45.0 * float(side)
		var dock_id := "dock_pavement_%d" % foundation_index
		if _attach_extruded_quay(
			graph,
			vertex_id,
			"extrude",
			"dock_pavement",
			dock_id,
			yaw_offset,
			{
				"role": "dock_foundation",
				"foundation_index": foundation_index,
				"extrude_angle_deg": angle,
				"yaw_offset_deg": yaw_offset,
			},
		):
			docks.append({
				"dock_id": dock_id,
				"coast_vertex_id": vertex_id,
				"extrude_angle_deg": angle,
			})
	_build_inland_road_from_pavements(graph, land_pavements, size)
	return {
		"foundation_count": foundation_count,
		"dock_length_m": 20.0,
		"land_pavements": land_pavements,
		"docks": docks,
	}


static func _attach_coast_link(
		graph: PortLayoutGraph,
		parent_instance_id: String,
		parent_slot_id: String,
		instance_id: String,
		target_position: Vector2,
		target_yaw: float,
		extra_yaw_deg: float,
		assignment: Dictionary,
) -> bool:
	if graph.modules.has(instance_id):
		return false
	var parent := graph.modules.get(parent_instance_id) as PortPlacedModule
	var parent_def := graph.module_definition(parent.module_id) if parent != null else null
	var child_def := graph.module_definition("coast_vertex")
	if parent == null or parent_def == null or child_def == null:
		return false
	if parent.consumes(parent_slot_id):
		return false
	var output := parent_def.output_slot(parent_slot_id)
	if output.is_empty():
		return false
	var input := child_def.input_for(str(output.get("type", "")))
	if input.is_empty():
		return false

	var parent_basis := Basis(Vector3.UP, deg_to_rad(parent.yaw_degrees))
	var output_position := parent.position_m + parent_basis * (output.get("position_m", Vector3.ZERO) as Vector3)
	var output_yaw := parent.yaw_degrees + float(output.get("yaw_degrees", 0.0))
	var child_yaw := wrapf(
		output_yaw + 180.0 - float(input.get("yaw_degrees", 0.0)) + extra_yaw_deg,
		-180.0,
		180.0,
	)
	var child_basis := Basis(Vector3.UP, deg_to_rad(child_yaw))
	var child_position := output_position - child_basis * (input.get("position_m", Vector3.ZERO) as Vector3)
	child_position.x = target_position.x
	child_position.z = target_position.y

	var child := PortPlacedModule.new()
	child.instance_id = instance_id
	child.module_id = "coast_vertex"
	child.parent_instance_id = parent_instance_id
	child.parent_slot_id = parent_slot_id
	child.input_slot_id = str(input.get("id", ""))
	child.position_m = child_position
	child.yaw_degrees = target_yaw
	child.assignment = assignment.duplicate(true)
	if graph._overlaps_existing(child, child_def):
		return false

	parent.consume(parent_slot_id)
	graph.modules[instance_id] = child
	graph.edges.append({
		"parent_instance_id": parent_instance_id,
		"parent_slot_id": parent_slot_id,
		"child_instance_id": instance_id,
		"child_input_slot_id": child.input_slot_id,
		"link_kind": "coast_chain",
	})
	return true


static func _attach_extruded_quay(
		graph: PortLayoutGraph,
		parent_instance_id: String,
		parent_slot_id: String,
		module_id: String,
		instance_id: String,
		extra_yaw_deg: float,
		assignment: Dictionary,
) -> bool:
	if graph.modules.has(instance_id):
		return false
	var parent := graph.modules.get(parent_instance_id) as PortPlacedModule
	var parent_def := graph.module_definition(parent.module_id) if parent != null else null
	var child_def := graph.module_definition(module_id)
	if parent == null or parent_def == null or child_def == null:
		return false
	if parent.consumes(parent_slot_id):
		return false
	var output := parent_def.output_slot(parent_slot_id)
	if output.is_empty():
		return false
	var input := child_def.input_for(str(output.get("type", "")))
	if input.is_empty():
		return false

	var parent_basis := Basis(Vector3.UP, deg_to_rad(parent.yaw_degrees))
	var output_position := parent.position_m + parent_basis * (output.get("position_m", Vector3.ZERO) as Vector3)
	var output_yaw := parent.yaw_degrees + float(output.get("yaw_degrees", 0.0))
	var child_yaw := wrapf(
		output_yaw + 180.0 - float(input.get("yaw_degrees", 0.0)) + extra_yaw_deg,
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
	if graph._overlaps_existing(child, child_def):
		return false

	parent.consume(parent_slot_id)
	graph.modules[instance_id] = child
	graph.edges.append({
		"parent_instance_id": parent_instance_id,
		"parent_slot_id": parent_slot_id,
		"child_instance_id": instance_id,
		"child_input_slot_id": child.input_slot_id,
		"link_kind": "terrain_extrusion",
	})
	return true


static func _group_trade(profile: PortTradeProfile) -> Dictionary:
	var grouped: Dictionary = {}
	for commodity in profile.export_slots:
		var family := _family_for(commodity)
		if not grouped.has(family):
			grouped[family] = []
		(grouped[family] as Array).append({
			"commodity_id": commodity,
			"role": "export",
			"family": family,
		})
	for commodity in profile.import_slots:
		var family := _family_for(commodity)
		if not grouped.has(family):
			grouped[family] = []
		(grouped[family] as Array).append({
			"commodity_id": commodity,
			"role": "import",
			"family": family,
		})
	return grouped


static func _family_for(commodity_id: String) -> String:
	return CommodityCatalog.commodity_terminal_family(commodity_id)


static func _quay_for_family(family: String) -> String:
	match family:
		"fishing":
			return "quay_fishing"
		"container":
			return "quay_container"
		"bulk_ore":
			return "quay_bulk"
		"bulk_grain":
			return "quay_grain"
		"liquid":
			return "quay_liquid"
		_:
			return "quay_general"


static func _equipment_for_family(family: String) -> String:
	match family:
		"fishing":
			return "equip_fish_derrick"
		"container":
			return "equip_sts_gantry"
		"bulk_ore":
			return "equip_grab_unloader"
		"bulk_grain":
			return "equip_grain_elevator"
		"liquid":
			return "equip_loading_arm"
		_:
			return "equip_jib_crane"


static func _yard_for_family(family: String) -> String:
	match family:
		"fishing":
			return "yard_fish"
		"container":
			return "yard_container"
		"bulk_ore":
			return "yard_ore"
		"bulk_grain":
			return "yard_grain"
		"liquid":
			return "yard_tank"
		_:
			return "yard_general"


static func _extend_arm_to_length(
		graph: PortLayoutGraph,
		arm_id: String,
		family: String,
		target_length_m: float,
) -> void:
	var tip_id := arm_id
	var placed := graph.modules.get(tip_id) as PortPlacedModule
	if placed == null:
		return
	var size := PortSizing.normalized_size(int(graph.initial_attributes.get("size", 2)))
	var definition := PortModuleCatalog.definition_for_size(placed.module_id, size)
	var length := definition.footprint_m.z if definition != null else 0.0
	var extension_index := 0
	var max_extensions := PortSizing.max_quay_segments_per_arm(size) - 1
	while length + 0.5 < target_length_m:
		if extension_index >= max_extensions:
			break
		var extension_id := "%s_extension_%d" % [arm_id, extension_index]
		if not graph.attach_module(
			tip_id,
			"extend",
			"quay_extension",
			extension_id,
			{"role": "terminal_extension", "family": family},
		):
			break
		tip_id = extension_id
		var ext := PortModuleCatalog.definition_for_size("quay_extension", size)
		length += ext.footprint_m.z if ext != null else PortSizing.slot_width_m(size)
		extension_index += 1


static func _place_trade_yards_on_land(
		graph: PortLayoutGraph,
		family: String,
		assignments: Array,
		preferred_vertices: Array[String] = [],
) -> void:
	var yard_module := _yard_for_family(family)
	for index in range(assignments.size()):
		var assignment := (assignments[index] as Dictionary).duplicate(true)
		assignment["serves_berth_family"] = family
		var yard_id := "yard_%s_%d" % [family, index]
		if _attach_coast_backland_yard(
			graph, yard_module, yard_id, assignment, preferred_vertices
		) != "":
			continue
		if _attach_named_open(graph, "cargo_facility", yard_module, yard_id, assignment) != "":
			continue
		if _attach_named_open(graph, "cargo_facility", "cargo_yard", yard_id, assignment) != "":
			continue
		push_warning("PortLayoutGenerator: no land cargo socket left for %s" % yard_id)


static func _attach_coast_backland_yard(
		graph: PortLayoutGraph,
		yard_module: String,
		instance_id: String,
		assignment: Dictionary,
		preferred_vertices: Array[String] = [],
) -> String:
	var candidates := preferred_vertices.duplicate()
	for vid in graph.module_ids():
		if not candidates.has(vid):
			candidates.append(vid)
	for vid in candidates:
		var placed := graph.modules[vid] as PortPlacedModule
		var definition := graph.module_definition(placed.module_id)
		if definition == null or definition.kind != "coast":
			continue
		if placed.consumes("backland"):
			continue
		if graph.attach_module(vid, "backland", yard_module, instance_id, assignment):
			return instance_id
	return ""


static func _build_inland_road(
		graph: PortLayoutGraph,
		vertex_ids: Array[String],
		size: int,
) -> void:
	if vertex_ids.is_empty():
		return
	var center_index := int(float(vertex_ids.size()) * 0.5)
	var road_parent := ""
	for offset in range(vertex_ids.size()):
		for index in [center_index - offset, center_index + offset]:
			if index < 0 or index >= vertex_ids.size():
				continue
			var candidate := vertex_ids[index]
			var placed := graph.modules.get(candidate) as PortPlacedModule
			if placed != null and not placed.consumes("backland"):
				road_parent = candidate
				break
		if not road_parent.is_empty():
			break
	if road_parent.is_empty():
		return
	var road_slot := "backland"
	for index in range(PortSizing.inland_road_segments(size)):
		var road_id := "road_%d" % index
		if not graph.attach_module(road_parent, road_slot, "road_spine", road_id, {"role": "inland_spine"}):
			break
		road_parent = road_id
		road_slot = "extend"


static func _build_inland_road_from_pavements(
		graph: PortLayoutGraph,
		land_pavements: Array[String],
		size: int,
) -> void:
	if land_pavements.is_empty():
		return
	var road_parent := land_pavements[int(float(land_pavements.size()) * 0.5)]
	var road_slot := "extend"
	for index in range(PortSizing.inland_road_segments(size)):
		var road_id := "road_%d" % index
		if not graph.attach_module(road_parent, road_slot, "road_spine", road_id, {"role": "inland_spine"}):
			break
		road_parent = road_id
		road_slot = "extend"


static func _arm_chain_ids(graph: PortLayoutGraph, root_arm_id: String) -> Array[String]:
	var ids: Array[String] = [root_arm_id]
	var current := root_arm_id
	while true:
		var next_id := ""
		for edge in graph.edges:
			if str(edge.get("parent_instance_id", "")) != current:
				continue
			if str(edge.get("parent_slot_id", "")) != "extend":
				continue
			next_id = str(edge.get("child_instance_id", ""))
			break
		if next_id.is_empty():
			break
		ids.append(next_id)
		current = next_id
	return ids


static func _attach_equipment_along_arm(
		graph: PortLayoutGraph,
		arm_id: String,
		family: String,
) -> void:
	var equip_module := _equipment_for_family(family)
	var equip_index := 0
	for chain_id in _arm_chain_ids(graph, arm_id):
		for slot in graph.open_slots("equipment_pad"):
			if str(slot.get("parent_instance_id", "")) != chain_id:
				continue
			var equip_id := "equip_%s_%d" % [family, equip_index]
			if graph.attach_module(
				chain_id,
				str(slot.get("parent_slot_id", "")),
				equip_module,
				equip_id,
				{
					"role": "handling_gear",
					"family": family,
					"equipment_kind": equip_module,
					"berth_index": equip_index,
				},
			):
				equip_index += 1


static func _attach_named_open(
		graph: PortLayoutGraph,
		slot_type: String,
		module_id: String,
		instance_id: String,
		assignment: Dictionary,
) -> String:
	var slots := graph.open_slots(slot_type)
	slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var az := (a.get("position_m", Vector3.ZERO) as Vector3).z
		var bz := (b.get("position_m", Vector3.ZERO) as Vector3).z
		if not is_equal_approx(az, bz):
			return az > bz
		return str(a.get("slot_id", "")) < str(b.get("slot_id", ""))
	)
	for slot in slots:
		if graph.attach_module(
			str(slot.get("parent_instance_id", "")),
			str(slot.get("parent_slot_id", "")),
			module_id,
			instance_id,
			assignment,
		):
			return instance_id
	return ""
