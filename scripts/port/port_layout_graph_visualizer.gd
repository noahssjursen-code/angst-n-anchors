@tool
class_name PortLayoutGraphVisualizer
extends Node3D

## Module footprints plus rough handling-gear silhouettes per cargo family.

const SLOT_COLORS := {
	"harbour_branch": Color(0.54, 0.30, 0.72, 0.58),
	"quay_branch": Color(0.38, 0.48, 0.62, 0.58),
	"quay_extension": Color(0.50, 0.34, 0.70, 0.58),
	"cargo_facility": Color(0.18, 0.66, 0.42, 0.58),
	"equipment_pad": Color(0.92, 0.74, 0.12, 0.58),
	"service_pad": Color(0.84, 0.24, 0.20, 0.58),
	"road_extension": Color(0.55, 0.58, 0.62, 0.58),
	"road_branch": Color(0.46, 0.50, 0.54, 0.58),
	"shore_chain": Color(0.42, 0.44, 0.46, 0.58),
	"coast_chain": Color(0.48, 0.50, 0.52, 0.58),
}

const STEEL := Color(0.45, 0.46, 0.48)
## Solid harbour pavement — flat #222222, no lighting variation.
const FOUNDATION_PAVEMENT_COLOR := Color(0.133, 0.133, 0.133)


static func _foundation_pavement_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = FOUNDATION_PAVEMENT_COLOR
	material.roughness = 1.0
	material.metallic = 0.0
	material.metallic_specular = 0.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	return material

## Shared materials across stamps — recreating StandardMaterial3D per box was a hitch.
static var _material_cache: Dictionary = {}

@export var show_module_labels := true
@export var show_open_slots := true
@export var show_equipment_shapes := true

var _graph: PortLayoutGraph


func configure(graph: PortLayoutGraph) -> void:
	_graph = graph
	if is_inside_tree():
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.free()
	if _graph == null:
		return
	_stamp_foundation()
	_stamp_berth_terminals()
	for instance_id in _graph.module_ids():
		_stamp_module(_graph.modules[instance_id] as PortPlacedModule)
	if show_open_slots:
		for slot in _graph.open_slots():
			if _should_stamp_open_slot(slot):
				_stamp_open_slot(slot)


func _stamp_module(placed: PortPlacedModule) -> void:
	var definition := _graph.module_definition(placed.module_id) if _graph != null \
			else PortModuleCatalog.definition(placed.module_id)
	if definition == null:
		return
	if definition.kind == "coast":
		return
	if show_equipment_shapes and definition.kind == "equipment":
		_stamp_equipment(placed, definition)
		return
	if show_equipment_shapes and definition.kind == "service" and definition.tags.has("fuel"):
		_stamp_fuel_tank(placed, definition)
		return
	var color := _module_color(definition, placed.assignment)
	var mesh_instance := _box(
		"Module_%s" % placed.instance_id,
		definition.footprint_m,
		placed.position_m + Vector3(0.0, definition.footprint_m.y * 0.5, 0.0),
		placed.yaw_degrees,
		color,
		false,
	)
	mesh_instance.set_meta("port_module_id", placed.instance_id)
	if not show_module_labels or definition.kind == "coast":
		return
	var text := definition.display_name
	var family := str(placed.assignment.get("family", ""))
	var role := str(placed.assignment.get("role", ""))
	var commodity := str(placed.assignment.get("commodity_id", ""))
	if not commodity.is_empty():
		text += "\n%s: %s" % [
			role.to_upper(),
			CommodityCatalog.commodity_display(commodity).to_upper(),
		]
	elif not family.is_empty() and definition.kind == "quay":
		text += "\n%s" % CommodityCatalog.terminal_family_display(family).to_upper()
	elif not role.is_empty() and role not in ["harbour_root", "terminal_arm", "inland_spine"]:
		text += "\n%s" % role.to_upper().replace("_", " ")
	_label(
		"Label_%s" % placed.instance_id,
		text,
		placed.position_m + Vector3(0.0, definition.footprint_m.y + 1.3, 0.0),
		Color(0.98, 0.97, 0.90),
		0.032,
	)


func _stamp_foundation() -> void:
	var plan := _graph.initial_attributes.get("foundation", {}) as Dictionary
	var spine := plan.get("spine", []) as Array
	if spine.size() < 2:
		return
	var inland_m := float(plan.get("town_inland_m", PortCoastTracer.FOUNDATION_TOWN_INLAND_M))
	var burial_extra := float(plan.get("burial_extra_m", PortCoastTracer.FOUNDATION_BURIAL_EXTRA_M))
	var sea_m := float(plan.get("dock_reach_m", PortCoastTracer.FOUNDATION_DOCK_REACH_M)) \
			+ float(plan.get("bay_lip_m", PortCoastTracer.FOUNDATION_BAY_LIP_M))
	var surface_y := float(plan.get("surface_y_m", PortCoastTracer.FOUNDATION_SURFACE_Y_M))
	var embed_depth := float(plan.get("embed_depth_m", PortCoastTracer.FOUNDATION_EMBED_DEPTH_M))
	var seaward_depth := float(plan.get("seaward_depth_m", PortCoastTracer.FOUNDATION_SEAWARD_DEPTH_M))
	var top_y := surface_y + PortCoastTracer.FOUNDATION_TERRAIN_CLEARANCE_M
	var land_bottom_y := surface_y - embed_depth
	var water_bottom_y := WaveSurface.WATER_LEVEL - seaward_depth
	var spine_pts := _foundation_spine_polyline(spine)
	var inland_top := PortCoastTracer.offset_spine_perpendicular(
		spine_pts, inland_m, PortCoastTracer.PORT_LOCAL_INLAND_DIR, true,
	)
	var sea_top := PortCoastTracer.offset_spine_perpendicular(
		spine_pts, sea_m, PortCoastTracer.PORT_LOCAL_INLAND_DIR, false,
	)
	var inland_bot := PortCoastTracer.offset_spine_perpendicular(
		spine_pts,
		inland_m + burial_extra,
		PortCoastTracer.PORT_LOCAL_INLAND_DIR,
		true,
	)
	var sea_bot := sea_top
	var shore_top := spine_pts
	var material := _foundation_pavement_material()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(spine.size() - 1):
		_add_ribbon_link(
			surface,
			sea_top,
			shore_top,
			inland_top,
			index,
			top_y,
			water_bottom_y,
			land_bottom_y,
		)
		_add_ribbon_side_wall(
			surface,
			sea_top,
			sea_bot,
			index,
			top_y,
			water_bottom_y,
			false,
		)
		_add_ribbon_side_wall(
			surface,
			inland_top,
			inland_bot,
			index,
			top_y,
			land_bottom_y,
			true,
		)
	_stamp_foundation_end_cap(
		surface,
		sea_top,
		shore_top,
		inland_top,
		sea_bot,
		inland_bot,
		0,
		top_y,
		water_bottom_y,
		land_bottom_y,
		false,
	)
	_stamp_foundation_end_cap(
		surface,
		sea_top,
		shore_top,
		inland_top,
		sea_bot,
		inland_bot,
		spine.size() - 1,
		top_y,
		water_bottom_y,
		land_bottom_y,
		true,
	)
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "HarbourFoundation"
	mesh.mesh = surface.commit()
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.extra_cull_margin = 24.0
	add_child(mesh)


## Trade berths planned on the asphalt dock face — wide decks with gear + yard.
func _stamp_berth_terminals() -> void:
	if not show_equipment_shapes:
		return
	var plan := _graph.initial_attributes.get("berth_plan", {}) as Dictionary
	if plan.is_empty():
		return
	var foundation := _graph.initial_attributes.get("foundation", {}) as Dictionary
	var surface_y := float(foundation.get("surface_y_m", PortCoastTracer.FOUNDATION_SURFACE_Y_M)) \
			+ PortCoastTracer.FOUNDATION_TERRAIN_CLEARANCE_M
	var root := Node3D.new()
	root.name = "BerthTerminals"
	add_child(root)
	for index in range((plan.get("quay_stations", []) as Array).size()):
		var station := (plan.get("quay_stations", []) as Array)[index] as Dictionary
		## Prefer plan berth_side when present (gameplay / docking later).
		var berth_sign := float(station.get("berth_side", 1 if (index % 2) == 0 else -1))
		if is_zero_approx(berth_sign):
			berth_sign = 1.0 if (index % 2) == 0 else -1.0
		_stamp_berth_quay(root, station, surface_y, berth_sign)
	for raw in plan.get("asphalt_stations", []) as Array:
		_stamp_berth_asphalt(root, raw as Dictionary, surface_y)


func _stamp_berth_quay(
		parent: Node3D,
		station: Dictionary,
		surface_y: float,
		berth_sign: float = 1.0,
) -> void:
	var origin := _xz2(station.get("origin", [0.0, 0.0]))
	var tip := _xz2(station.get("tip", [origin.x, origin.y]))
	var seaward := _xz2(station.get("direction", [0.0, -1.0])).normalized()
	if seaward.length_squared() < 0.001:
		seaward = PortCoastTracer.PORT_LOCAL_SEAWARD_DIR
	var length_m := float(station.get("length_m", origin.distance_to(tip)))
	var width_m := float(station.get("width_m", PortSizing.quay_deck_width_m(_size_class())))
	var family := str(station.get("family", "general"))
	var family_color := CommodityCatalog.terminal_family_color(family)
	var mid := origin.lerp(tip, 0.5)
	var terminal := Node3D.new()
	terminal.name = str(station.get("id", "quay"))
	terminal.position = Vector3(mid.x, surface_y, mid.y)
	_align_node_seaward(terminal, seaward)
	parent.add_child(terminal)
	terminal.set_meta("deck_half_w", width_m * 0.5)

	## Cross-section (local X): storage | road | crane.
	## berth_sign · +X = ship face; opposite flank = cargo/storage.
	var crane_lane_w := clampf(width_m * 0.34, 14.0, 36.0)
	var road_w := clampf(width_m * 0.22, 8.0, 16.0)
	var storage_w := maxf(width_m - crane_lane_w - road_w, width_m * 0.34)
	var lane_sum := storage_w + road_w + crane_lane_w
	if lane_sum > width_m:
		var scale := width_m / lane_sum
		storage_w *= scale
		road_w *= scale
		crane_lane_w *= scale
	var storage_x := -berth_sign * (width_m * 0.5 - storage_w * 0.5)
	var road_x := storage_x + berth_sign * (storage_w * 0.5 + road_w * 0.5)
	var crane_x := berth_sign * (width_m * 0.5 - crane_lane_w * 0.5)
	var usable_len := length_m * 0.90
	var z0 := -usable_len * 0.5

	var deck := MeshBuilder.box(
		Vector3(width_m, 0.55, length_m),
		FOUNDATION_PAVEMENT_COLOR.lightened(0.04),
		1.0,
		0.0,
	)
	deck.name = "Deck"
	deck.position = Vector3(0.0, 0.28, 0.0)
	terminal.add_child(deck)

	## Coping marks the ship berth edge
	var coping := MeshBuilder.box(
		Vector3(1.2, 0.7, length_m * 0.96),
		Color(0.55, 0.56, 0.58),
		0.9,
		0.05,
	)
	coping.name = "BerthEdge"
	coping.position = Vector3(berth_sign * (width_m * 0.5 - 0.6), 0.55, 0.0)
	terminal.add_child(coping)

	var road := MeshBuilder.box(
		Vector3(road_w, 0.22, usable_len),
		Color(0.07, 0.07, 0.08),
		1.0,
		0.0,
	)
	road.name = "Road"
	road.position = Vector3(road_x, 0.50, 0.0)
	terminal.add_child(road)

	_stamp_quay_storage_lane(
		terminal,
		station,
		storage_x,
		storage_w,
		usable_len,
		z0,
		berth_sign,
	)
	_stamp_quay_crane_lane(
		terminal,
		station,
		crane_x,
		crane_lane_w,
		usable_len,
		z0,
		berth_sign,
	)

	if show_module_labels:
		var zone_bits: PackedStringArray = []
		for zone in station.get("zones", []) as Array:
			var z := zone as Dictionary
			var role := str(z.get("role", "")).to_upper()
			var name := CommodityCatalog.commodity_display(str(z.get("commodity_id", "")))
			if bool(z.get("bidirectional", false)):
				zone_bits.append("IN/OUT %s" % name)
			elif not role.is_empty():
				zone_bits.append("%s %s" % [role, name])
			else:
				zone_bits.append(name)
		if zone_bits.is_empty():
			for commodity in station.get("commodities", []) as Array:
				zone_bits.append(CommodityCatalog.commodity_display(str(commodity)))
		_label(
			"BerthLabel_%s" % str(station.get("id", "quay")),
			"%s\n%.0f m quay" % ["\n".join(zone_bits), length_m],
			Vector3(mid.x, surface_y + 18.0, mid.y) + Vector3(seaward.x, 0.0, seaward.y) * (length_m * 0.15),
			CommodityCatalog.commodity_color(str((station.get("commodities", ["containers"]) as Array)[0])) \
					if not (station.get("commodities", []) as Array).is_empty() \
					else family_color.lightened(0.2),
			0.03,
		)


## Pack cargo along the storage flank, split into commodity zones when shared.
func _stamp_quay_storage_lane(
		terminal: Node3D,
		station: Dictionary,
		lane_x: float,
		lane_w: float,
		usable_len: float,
		z0: float,
		berth_sign: float,
) -> void:
	var lane := Node3D.new()
	lane.name = "StorageLane"
	terminal.add_child(lane)
	var zones: Array = station.get("zones", []) as Array
	if zones.is_empty():
		var family := str(station.get("family", "general"))
		zones = [{
			"commodity_id": "",
			"role": "",
			"family": family,
			"t0": 0.0,
			"t1": 1.0,
			"label": CommodityCatalog.terminal_family_display(family),
		}]
	for zone_index in range(zones.size()):
		var zone: Dictionary = zones[zone_index]
		var t0 := float(zone.get("t0", 0.0))
		var t1 := float(zone.get("t1", 1.0))
		var zone_len := usable_len * maxf(t1 - t0, 0.05)
		var zone_mid_z := z0 + usable_len * ((t0 + t1) * 0.5)
		var commodity_id := str(zone.get("commodity_id", ""))
		var zone_family := str(zone.get("family", station.get("family", "general")))
		var color := CommodityCatalog.commodity_color(commodity_id) if not commodity_id.is_empty() \
				else CommodityCatalog.terminal_family_color(zone_family)
		var color_arr := zone.get("color", []) as Array
		if color_arr.size() >= 3:
			color = Color(float(color_arr[0]), float(color_arr[1]), float(color_arr[2]))

		## Full commodity colour on the storage apron — readable from above.
		var apron := MeshBuilder.box(
			Vector3(lane_w * 0.96, 0.22, zone_len * 0.96),
			color,
			0.9,
			0.0,
		)
		apron.name = "ZoneApron_%d" % zone_index
		apron.position = Vector3(lane_x, 0.50, zone_mid_z)
		lane.add_child(apron)

		## Side stripe on the berth face matching this zone's product
		var half_w := float(terminal.get_meta("deck_half_w", absf(lane_x) + lane_w))
		var stripe := MeshBuilder.box(
			Vector3(1.1, 0.85, zone_len * 0.92),
			color.lightened(0.12),
			0.75,
			0.05,
		)
		stripe.name = "ZoneStripe_%d" % zone_index
		stripe.position = Vector3(berth_sign * (half_w - 0.55), 0.6, zone_mid_z)
		lane.add_child(stripe)

		## Divider stripe between commodity bands
		if zone_index > 0:
			var divider_z := z0 + usable_len * t0
			var divider := MeshBuilder.box(
				Vector3(lane_w * 1.05, 0.7, 1.8),
				Color(0.95, 0.95, 0.92),
				0.7,
				0.05,
			)
			divider.name = "ZoneDivide_%d" % zone_index
			divider.position = Vector3(lane_x, 0.75, divider_z)
			lane.add_child(divider)

		var pad_len := clampf(zone_len * 0.42, 14.0, 36.0)
		var gap := 3.5
		var count := maxi(1, int(floor((zone_len * 0.9 + gap) / (pad_len + gap))))
		var span := float(count) * pad_len + float(maxi(count - 1, 0)) * gap
		var start_z := zone_mid_z - span * 0.5 + pad_len * 0.5
		var stack_w := lane_w * 0.82
		for pad_i in range(count):
			var z := start_z + float(pad_i) * (pad_len + gap)
			var height := _storage_stack_height(zone_family, pad_i)
			var stack := _make_storage_stack(
				zone_family,
				color,
				Vector3(stack_w, height, pad_len * 0.88),
			)
			stack.name = "Cargo_%d_%d" % [zone_index, pad_i]
			stack.position = Vector3(lane_x, 0.55 + height * 0.5, z)
			lane.add_child(stack)

		if show_module_labels:
			var role := str(zone.get("role", ""))
			var role_color := Color(0.35, 0.9, 0.45) if role == "export" \
					else (Color(0.95, 0.7, 0.25) if role == "import" else color.lightened(0.2))
			if bool(zone.get("bidirectional", false)):
				role_color = Color(0.55, 0.82, 0.95)
			var label_x := lane_x - berth_sign * (lane_w * 0.2)
			_label(
				"ZoneLabel_%s_%d" % [str(station.get("id", "quay")), zone_index],
				str(zone.get("label", commodity_id)).to_upper(),
				terminal.to_global(Vector3(label_x, 10.0, zone_mid_z)),
				role_color,
				0.032,
			)


## Load/unload tools — one per commodity zone when shared, else spaced by length.
func _stamp_quay_crane_lane(
		terminal: Node3D,
		station: Dictionary,
		lane_x: float,
		lane_w: float,
		usable_len: float,
		z0: float,
		berth_sign: float,
) -> void:
	var lane := Node3D.new()
	lane.name = "CraneLane"
	terminal.add_child(lane)
	var rail := MeshBuilder.box(
		Vector3(lane_w * 0.9, 0.16, usable_len),
		STEEL.darkened(0.2),
		0.75,
		0.25,
	)
	rail.name = "CraneRail"
	rail.position = Vector3(lane_x, 0.48, 0.0)
	lane.add_child(rail)

	var zones: Array = station.get("zones", []) as Array
	var tool_positions: Array[float] = []
	if zones.size() >= 2:
		for zone in zones:
			var t0 := float(zone.get("t0", 0.0))
			var t1 := float(zone.get("t1", 1.0))
			tool_positions.append(z0 + usable_len * ((t0 + t1) * 0.5))
	else:
		var tool_count := 1
		if usable_len >= 160.0:
			tool_count = 3
		elif usable_len >= 90.0:
			tool_count = 2
		if tool_count == 1:
			tool_positions.append(0.0)
		else:
			var tool_span := usable_len * 0.72
			var step := tool_span / float(tool_count - 1)
			var start_z := z0 + (usable_len - tool_span) * 0.5
			for index in range(tool_count):
				tool_positions.append(start_z + float(index) * step)

	var family := str(station.get("family", "general"))
	var fp := Vector3(
		clampf(lane_w * 0.85, 10.0, 28.0),
		1.0,
		clampf(lane_w * 0.7, 10.0, 24.0),
	)
	for index in range(tool_positions.size()):
		var z := float(tool_positions[index])
		var equip_kind := str(station.get("equipment_kind", "equip_jib_crane"))
		if index < zones.size():
			var zone_family := str((zones[index] as Dictionary).get("family", family))
			equip_kind = PortBerthPlan.equipment_for_family(zone_family)
		var equip_root := Node3D.new()
		equip_root.name = "Tool_%d" % index
		equip_root.position = Vector3(lane_x, 0.55, z)
		if berth_sign < 0.0:
			equip_root.rotation_degrees.y = 180.0
		lane.add_child(equip_root)
		_stamp_equipment_kind(equip_root, equip_kind, fp, family)


func _storage_stack_height(family: String, index: int) -> float:
	match family:
		"container":
			return 4.4 + float(index % 3) * 2.6
		"bulk_ore", "bulk_grain":
			return 5.0 + float(index % 2) * 1.5
		"liquid":
			return 8.0
		"fishing":
			return 3.2
		_:
			return 3.6 + float(index % 2) * 1.2


func _make_storage_stack(family: String, family_color: Color, size: Vector3) -> Node3D:
	var root := Node3D.new()
	match family:
		"liquid":
			var tank := MeshBuilder.cylinder(
				minf(size.x, size.z) * 0.38,
				size.y,
				family_color.lightened(0.05),
				0.85,
				0.15,
			)
			root.add_child(tank)
		"bulk_ore", "bulk_grain":
			root.add_child(MeshBuilder.box(size, family_color.darkened(0.1), 0.95, 0.0))
		"container":
			var tiers := maxi(1, int(round(size.y / 2.6)))
			var tier_h := size.y / float(tiers)
			for tier in range(tiers):
				var box := MeshBuilder.box(
					Vector3(size.x * 0.92, tier_h * 0.88, size.z * 0.9),
					family_color.lightened(0.05 * float(tier % 2)),
					0.8,
					0.05,
				)
				box.position = Vector3(0.0, -size.y * 0.5 + tier_h * (float(tier) + 0.5), 0.0)
				root.add_child(box)
		_:
			root.add_child(MeshBuilder.box(size * Vector3(0.9, 1.0, 0.85), family_color.darkened(0.05), 0.9, 0.0))
	return root


func _stamp_berth_asphalt(parent: Node3D, station: Dictionary, surface_y: float) -> void:
	var origin := _xz2(station.get("origin", [0.0, 0.0]))
	var seaward := _xz2(station.get("direction", [0.0, -1.0])).normalized()
	if seaward.length_squared() < 0.001:
		seaward = PortCoastTracer.PORT_LOCAL_SEAWARD_DIR
	var depth := float(station.get("depth_m", 16.0))
	var length := float(station.get("length_m", 24.0))
	var family := str(station.get("family", "general"))
	var color := CommodityCatalog.terminal_family_color(family).lightened(0.2)
	var pad_center := origin + seaward * (depth * 0.5)
	var pad_root := Node3D.new()
	pad_root.name = str(station.get("id", "asphalt"))
	pad_root.position = Vector3(pad_center.x, surface_y, pad_center.y)
	_align_node_seaward(pad_root, seaward)
	parent.add_child(pad_root)
	var pad := MeshBuilder.box(Vector3(length, 0.45, depth), color.darkened(0.25), 0.9, 0.0)
	pad.position = Vector3(0.0, 0.25, 0.0)
	pad_root.add_child(pad)
	if show_module_labels:
		_label(
			"AsphaltLabel_%s" % str(station.get("id", "asphalt")),
			"%s\n%s · apron" % [
				CommodityCatalog.commodity_display(str(station.get("commodity_id", ""))).to_upper(),
				str(station.get("role", "")).to_upper(),
			],
			Vector3(origin.x, surface_y + 10.0, origin.y),
			color,
			0.026,
		)


func _stamp_equipment_kind(root: Node3D, kind: String, footprint: Vector3, family: String) -> void:
	match kind:
		"equip_sts_gantry":
			_stamp_sts_gantry_at(root, footprint)
		"equip_grab_unloader":
			_stamp_grab_unloader_at(root, footprint)
		"equip_grain_elevator":
			_stamp_grain_elevator_at(root, footprint)
		"equip_fish_derrick":
			_stamp_fish_derrick_at(root, footprint)
		"equip_loading_arm":
			_stamp_loading_arm_at(root, footprint)
		_:
			_stamp_jib_crane_at(root, footprint, family)


func _stamp_jib_crane_at(root: Node3D, footprint: Vector3, _family: String) -> void:
	var accent := Color(0.92, 0.72, 0.10)
	_pad(root, footprint, STEEL.darkened(0.15))
	var size := _size_class()
	var mast_h := clampf(14.0 + float(size) * 4.0, 14.0, 34.0)
	var mast := MeshBuilder.box(Vector3(1.6, mast_h, 1.6), accent, 0.75, 0.2)
	mast.position = Vector3(0.0, mast_h * 0.5, 0.0)
	root.add_child(mast)
	var jib_len := clampf(mast_h * 0.95 + float(size) * 2.0, 16.0, 44.0)
	var jib := MeshBuilder.box(Vector3(jib_len, 0.9, 1.1), accent.lightened(0.08), 0.7, 0.25)
	jib.position = Vector3(jib_len * 0.42, mast_h - 0.8, 0.0)
	root.add_child(jib)
	var counter := MeshBuilder.box(Vector3(jib_len * 0.28, 0.9, 1.1), STEEL, 0.8, 0.3)
	counter.position = Vector3(-jib_len * 0.18, mast_h - 0.8, 0.0)
	root.add_child(counter)


func _stamp_sts_gantry_at(root: Node3D, footprint: Vector3) -> void:
	var accent := Color(0.92, 0.72, 0.10)
	_pad(root, footprint, STEEL.darkened(0.15))
	var size := _size_class()
	var leg_h := clampf(18.0 + float(size) * 3.0, 18.0, 36.0)
	var leg_span := footprint.x * 0.38
	for side in [-1.0, 1.0]:
		var leg := MeshBuilder.box(Vector3(1.4, leg_h, 1.4), accent, 0.75, 0.2)
		leg.position = Vector3(side * leg_span, leg_h * 0.5, 0.0)
		root.add_child(leg)
	var beam := MeshBuilder.box(Vector3(footprint.x * 0.82, 1.2, 2.4), STEEL, 0.8, 0.3)
	beam.position = Vector3(0.0, leg_h - 0.6, 0.0)
	root.add_child(beam)


func _stamp_grab_unloader_at(root: Node3D, footprint: Vector3) -> void:
	var accent := Color(0.92, 0.72, 0.10)
	_pad(root, footprint, STEEL.darkened(0.15))
	var tower_h := clampf(20.0 + float(_size_class()) * 2.5, 20.0, 34.0)
	var tower := MeshBuilder.box(Vector3(3.0, tower_h, 3.0), accent, 0.75, 0.2)
	tower.position = Vector3(0.0, tower_h * 0.5, 0.0)
	root.add_child(tower)
	var boom := MeshBuilder.box(Vector3(footprint.x * 0.55, 0.8, 1.0), STEEL, 0.8, 0.3)
	boom.position = Vector3(0.0, tower_h - 1.0, footprint.z * 0.2)
	root.add_child(boom)


func _stamp_grain_elevator_at(root: Node3D, footprint: Vector3) -> void:
	var accent := Color(0.84, 0.62, 0.18)
	_pad(root, footprint, STEEL.darkened(0.15))
	var silo_h := clampf(24.0 + float(_size_class()) * 3.0, 24.0, 42.0)
	var silo := MeshBuilder.cylinder(2.8, silo_h, accent, 0.8, 0.2)
	silo.position = Vector3(0.0, silo_h * 0.5, 0.0)
	root.add_child(silo)


func _stamp_fish_derrick_at(root: Node3D, footprint: Vector3) -> void:
	var accent := Color(0.55, 0.72, 0.92)
	_pad(root, footprint, STEEL.darkened(0.15))
	var mast_h := clampf(12.0 + float(_size_class()) * 2.0, 12.0, 24.0)
	var mast := MeshBuilder.box(Vector3(1.2, mast_h, 1.2), accent, 0.75, 0.2)
	mast.position = Vector3(0.0, mast_h * 0.5, 0.0)
	root.add_child(mast)


func _stamp_loading_arm_at(root: Node3D, footprint: Vector3) -> void:
	var accent := Color(0.72, 0.78, 0.86)
	_pad(root, footprint, STEEL.darkened(0.15))
	var base_h := 4.0
	var base := MeshBuilder.cylinder(1.8, base_h, STEEL, 0.85, 0.2)
	base.position = Vector3(0.0, base_h * 0.5, 0.0)
	root.add_child(base)
	var arm := MeshBuilder.box(Vector3(10.0, 0.7, 0.7), accent, 0.75, 0.2)
	arm.position = Vector3(5.0, base_h + 1.0, 0.0)
	root.add_child(arm)


func _align_node_seaward(node: Node3D, seaward: Vector2) -> void:
	var z_axis := Vector3(seaward.x, 0.0, seaward.y)
	if z_axis.length_squared() < 0.001:
		z_axis = Vector3(0.0, 0.0, -1.0)
	else:
		z_axis = z_axis.normalized()
	var x_axis := Vector3.UP.cross(z_axis).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	node.basis = Basis(x_axis, y_axis, z_axis)


func _xz2(raw: Variant) -> Vector2:
	var arr := raw as Array
	if arr.size() < 2:
		return Vector2.ZERO
	return Vector2(float(arr[0]), float(arr[1]))


## Four planar triangles per link — hinge at the shore row so bends never bow-tie overlap.
func _add_ribbon_link(
		surface: SurfaceTool,
		sea: PackedVector2Array,
		shore: PackedVector2Array,
		inland: PackedVector2Array,
		index: int,
		top_y: float,
		sea_bottom_y: float,
		land_bottom_y: float,
) -> void:
	var s0 := _foundation_vertex(sea, index, top_y)
	var s1 := _foundation_vertex(sea, index + 1, top_y)
	var h0 := _foundation_vertex(shore, index, top_y)
	var h1 := _foundation_vertex(shore, index + 1, top_y)
	var l0 := _foundation_vertex(inland, index, top_y)
	var l1 := _foundation_vertex(inland, index + 1, top_y)
	_add_tri(surface, s0, s1, h1)
	_add_tri(surface, s0, h1, h0)
	_add_tri(surface, h0, h1, l1)
	_add_tri(surface, h0, l1, l0)
	var sb0 := _foundation_vertex(sea, index, sea_bottom_y)
	var sb1 := _foundation_vertex(sea, index + 1, sea_bottom_y)
	var hb0 := _foundation_vertex(shore, index, land_bottom_y)
	var hb1 := _foundation_vertex(shore, index + 1, land_bottom_y)
	var lb0 := _foundation_vertex(inland, index, land_bottom_y)
	var lb1 := _foundation_vertex(inland, index + 1, land_bottom_y)
	_add_tri(surface, sb0, hb0, hb1)
	_add_tri(surface, sb0, hb1, sb1)
	_add_tri(surface, hb0, lb0, lb1)
	_add_tri(surface, hb0, lb1, hb1)


func _add_ribbon_side_wall(
		surface: SurfaceTool,
		top_path: PackedVector2Array,
		bot_path: PackedVector2Array,
		index: int,
		top_y: float,
		bottom_y: float,
		is_inland_side: bool,
) -> void:
	var t0 := _foundation_vertex(top_path, index, top_y)
	var t1 := _foundation_vertex(top_path, index + 1, top_y)
	var b0 := _foundation_vertex(bot_path, index, bottom_y)
	var b1 := _foundation_vertex(bot_path, index + 1, bottom_y)
	if is_inland_side:
		_add_quad(surface, t0, t1, b1, b0)
	else:
		_add_quad(surface, t0, b0, b1, t1)


func _stamp_foundation_end_cap(
		surface: SurfaceTool,
		sea: PackedVector2Array,
		shore: PackedVector2Array,
		inland: PackedVector2Array,
		sea_bot: PackedVector2Array,
		inland_bot: PackedVector2Array,
		index: int,
		top_y: float,
		sea_bottom_y: float,
		land_bottom_y: float,
		is_far_end: bool,
) -> void:
	var sea_top_v := _foundation_vertex(sea, index, top_y)
	var shore_top_v := _foundation_vertex(shore, index, top_y)
	var inland_top_v := _foundation_vertex(inland, index, top_y)
	var sea_bot_v := _foundation_vertex(sea_bot, index, sea_bottom_y)
	var shore_bot_v := _foundation_vertex(shore, index, land_bottom_y)
	var inland_bot_v := _foundation_vertex(inland_bot, index, land_bottom_y)
	if is_far_end:
		_add_tri(surface, sea_top_v, shore_top_v, inland_top_v)
		_add_tri(surface, sea_bot_v, inland_bot_v, shore_bot_v)
		_add_quad(surface, sea_top_v, inland_top_v, inland_bot_v, sea_bot_v)
	else:
		_add_tri(surface, sea_top_v, inland_top_v, shore_top_v)
		_add_tri(surface, sea_bot_v, shore_bot_v, inland_bot_v)
		_add_quad(surface, sea_top_v, sea_bot_v, inland_bot_v, inland_top_v)


func _add_tri(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)


func _add_quad(
		surface: SurfaceTool,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		d: Vector3,
) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
	surface.add_vertex(a)
	surface.add_vertex(c)
	surface.add_vertex(d)


func _foundation_spine_polyline(spine: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for raw in spine:
		var pt := raw as Array
		out.append(Vector2(float(pt[0]), float(pt[1])))
	return out


func _foundation_vertex(path: PackedVector2Array, index: int, y: float) -> Vector3:
	var point := path[index]
	return Vector3(point.x, y, point.y)


func _foundation_point(raw: Variant, surface_y: float) -> Vector3:
	var point := raw as Array
	return Vector3(float(point[0]), surface_y, float(point[1]))


func _stamp_equipment(placed: PortPlacedModule, definition: PortModuleDefinition) -> void:
	var kind := str(placed.assignment.get("equipment_kind", placed.module_id))
	if kind.is_empty():
		kind = placed.module_id
	match kind:
		"equip_sts_gantry":
			_stamp_sts_gantry(placed, definition)
		"equip_grab_unloader":
			_stamp_grab_unloader(placed, definition)
		"equip_grain_elevator":
			_stamp_grain_elevator(placed, definition)
		"equip_fish_derrick":
			_stamp_fish_derrick(placed, definition)
		"equip_loading_arm":
			_stamp_loading_arm(placed, definition)
		_:
			_stamp_jib_crane(placed, definition)


func _stamp_jib_crane(placed: PortPlacedModule, definition: PortModuleDefinition) -> void:
	var root := _equip_root(placed, "JibCrane")
	var accent := Color(0.92, 0.72, 0.10)
	var fp := definition.footprint_m
	_pad(root, fp, STEEL.darkened(0.15))
	var size := _size_class()
	var mast_h := clampf(14.0 + float(size) * 4.0, 14.0, 34.0)
	var mast := MeshBuilder.box(Vector3(1.6, mast_h, 1.6), accent, 0.75, 0.2)
	mast.position = Vector3(0.0, mast_h * 0.5, 0.0)
	root.add_child(mast)
	var jib_side := _jib_side(placed)
	var jib_len := clampf(mast_h * 0.95 + float(size) * 2.0, 16.0, 44.0)
	var jib := MeshBuilder.box(Vector3(jib_len, 0.9, 1.1), accent.lightened(0.08), 0.7, 0.25)
	jib.position = Vector3(jib_side * jib_len * 0.42, mast_h - 0.8, 0.0)
	root.add_child(jib)
	var counter := MeshBuilder.box(Vector3(jib_len * 0.28, 0.9, 1.1), STEEL, 0.8, 0.3)
	counter.position = Vector3(-jib_side * jib_len * 0.18, mast_h - 0.8, 0.0)
	root.add_child(counter)
	_equip_label(placed, "JIB CRANE", mast_h + 1.5, accent)


func _stamp_sts_gantry(placed: PortPlacedModule, definition: PortModuleDefinition) -> void:
	var root := _equip_root(placed, "StsGantry")
	var accent := Color(0.92, 0.72, 0.10)
	var fp := definition.footprint_m
	_pad(root, fp, STEEL.darkened(0.15))
	var size := _size_class()
	var leg_h := clampf(18.0 + float(size) * 3.0, 18.0, 36.0)
	var leg_span := fp.x * 0.38
	for side in [-1.0, 1.0]:
		var leg := MeshBuilder.box(Vector3(1.4, leg_h, 1.4), accent, 0.75, 0.2)
		leg.position = Vector3(side * leg_span, leg_h * 0.5, 0.0)
		root.add_child(leg)
	var beam := MeshBuilder.box(Vector3(fp.x * 0.82, 1.2, 2.4), STEEL, 0.8, 0.3)
	beam.position = Vector3(0.0, leg_h - 0.6, 0.0)
	root.add_child(beam)
	_equip_label(placed, "STS GANTRY", leg_h + 2.0, accent)


func _stamp_grab_unloader(placed: PortPlacedModule, definition: PortModuleDefinition) -> void:
	var root := _equip_root(placed, "GrabUnloader")
	var accent := Color(0.92, 0.72, 0.10)
	var fp := definition.footprint_m
	_pad(root, fp, STEEL.darkened(0.15))
	var tower_h := clampf(20.0 + float(_size_class()) * 2.5, 20.0, 34.0)
	var tower := MeshBuilder.box(Vector3(3.0, tower_h, 3.0), accent, 0.75, 0.2)
	tower.position = Vector3(0.0, tower_h * 0.5, 0.0)
	root.add_child(tower)
	var boom := MeshBuilder.box(Vector3(fp.x * 0.55, 0.8, 1.0), STEEL, 0.8, 0.3)
	boom.position = Vector3(0.0, tower_h - 1.0, fp.z * 0.2)
	root.add_child(boom)
	_equip_label(placed, "GRAB UNLOADER", tower_h + 1.5, accent)


func _stamp_grain_elevator(placed: PortPlacedModule, definition: PortModuleDefinition) -> void:
	var root := _equip_root(placed, "GrainElevator")
	var accent := Color(0.84, 0.62, 0.18)
	var fp := definition.footprint_m
	_pad(root, fp, STEEL.darkened(0.15))
	var silo_h := clampf(24.0 + float(_size_class()) * 3.0, 24.0, 42.0)
	var silo := MeshBuilder.cylinder(2.8, silo_h, accent, 0.8, 0.2)
	silo.position = Vector3(0.0, silo_h * 0.5, 0.0)
	root.add_child(silo)
	_equip_label(placed, "GRAIN ELEVATOR", silo_h + 1.5, accent)


func _stamp_fish_derrick(placed: PortPlacedModule, definition: PortModuleDefinition) -> void:
	var root := _equip_root(placed, "FishDerrick")
	var accent := Color(0.55, 0.72, 0.92)
	var fp := definition.footprint_m
	_pad(root, fp, STEEL.darkened(0.15))
	var mast_h := clampf(12.0 + float(_size_class()) * 2.0, 12.0, 24.0)
	var mast := MeshBuilder.box(Vector3(1.2, mast_h, 1.2), accent, 0.75, 0.2)
	mast.position = Vector3(0.0, mast_h * 0.5, 0.0)
	root.add_child(mast)
	_equip_label(placed, "FISH DERRICK", mast_h + 1.5, accent)


func _stamp_loading_arm(placed: PortPlacedModule, definition: PortModuleDefinition) -> void:
	var root := _equip_root(placed, "LoadingArm")
	var accent := Color(0.72, 0.78, 0.86)
	var fp := definition.footprint_m
	_pad(root, fp, STEEL.darkened(0.15))
	var base_h := 4.0
	var base := MeshBuilder.cylinder(1.8, base_h, STEEL, 0.85, 0.2)
	base.position = Vector3(0.0, base_h * 0.5, 0.0)
	root.add_child(base)
	var arm := MeshBuilder.box(Vector3(10.0, 0.7, 0.7), accent, 0.75, 0.2)
	arm.position = Vector3(5.0, base_h + 1.0, 0.0)
	root.add_child(arm)
	_equip_label(placed, "LOADING ARM", base_h + 3.0, accent)


func _stamp_fuel_tank(placed: PortPlacedModule, definition: PortModuleDefinition) -> void:
	var root := _equip_root(placed, "FuelTank")
	var fp := definition.footprint_m
	_pad(root, fp, STEEL.darkened(0.15))
	var tank_h := clampf(6.0 + float(_size_class()), 6.0, 12.0)
	var tank := MeshBuilder.cylinder(minf(fp.x, fp.z) * 0.35, tank_h, Color(0.62, 0.64, 0.66), 0.85, 0.2)
	tank.position = Vector3(0.0, tank_h * 0.5, 0.0)
	root.add_child(tank)
	_label("FuelLabel_%s" % placed.instance_id, "FUEL", placed.position_m + Vector3(0.0, tank_h + 1.2, 0.0), Color(0.95, 0.9, 0.7), 0.028)


func _stamp_open_slot(slot: Dictionary) -> void:
	var slot_type := str(slot.get("type", ""))
	var color: Color = SLOT_COLORS.get(slot_type, Color(0.5, 0.5, 0.5, 0.5))
	var position := slot.get("position_m", Vector3.ZERO) as Vector3
	var yaw := float(slot.get("yaw_degrees", 0.0))
	_box(
		"OpenSlot_%s" % str(slot.get("slot_id", "slot")),
		Vector3(8.0, 0.4, 8.0),
		position + Vector3(0.0, 0.2, 0.0),
		yaw,
		color,
		true,
	)


func _should_stamp_open_slot(slot: Dictionary) -> bool:
	var slot_type := str(slot.get("type", ""))
	return slot_type not in ["coast_chain", "shore_chain"]


func _equip_root(placed: PortPlacedModule, name: String) -> Node3D:
	var root := Node3D.new()
	root.name = "%s_%s" % [name, placed.instance_id]
	root.position = placed.position_m
	root.rotation_degrees.y = placed.yaw_degrees
	add_child(root)
	return root


func _equip_label(placed: PortPlacedModule, text: String, height: float, color: Color) -> void:
	_label(
		"EquipLabel_%s" % placed.instance_id,
		text,
		placed.position_m + Vector3(0.0, height, 0.0),
		color,
		0.028,
	)


func _pad(root: Node3D, footprint: Vector3, color: Color) -> void:
	var pad := MeshBuilder.box(Vector3(footprint.x, 0.35, footprint.z), color.darkened(0.1), 0.9, 0.05)
	pad.position = Vector3(0.0, 0.175, 0.0)
	root.add_child(pad)


func _box(
		node_name: String,
		size: Vector3,
		position: Vector3,
		yaw_degrees: float,
		color: Color,
		transparent: bool,
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = _cached_material(color, transparent)
	mesh_instance.position = position
	mesh_instance.rotation_degrees.y = yaw_degrees
	add_child(mesh_instance)
	return mesh_instance


func _label(node_name: String, text: String, position: Vector3, color: Color, pixel_size: float) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.pixel_size = pixel_size
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = position
	add_child(label)


func _cached_material(color: Color, transparent: bool) -> StandardMaterial3D:
	var key := "%s_%s" % [color, transparent]
	if not _material_cache.has(key):
		_material_cache[key] = MeshBuilder.make_material(color, 0.9, 0.05, transparent)
	return _material_cache[key]


func _module_color(definition: PortModuleDefinition, assignment: Dictionary) -> Color:
	if definition.kind == "quay":
		var family := str(assignment.get("family", ""))
		if not family.is_empty():
			return CommodityCatalog.terminal_family_color(family)
	return Color(0.42, 0.44, 0.46, 0.72 if definition.kind != "coast" else 0.58)


func _jib_side(placed: PortPlacedModule) -> float:
	return -1.0 if str(placed.assignment.get("side", "port")) == "port" else 1.0


func _size_class() -> int:
	return _graph.size_class() if _graph != null else 2
