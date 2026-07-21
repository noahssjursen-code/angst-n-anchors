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
## Quay pier mass (underwater face) — slightly lighter so depth reads in clear water.
const QUAY_PIER_MASS_COLOR := Color(0.18, 0.19, 0.20)
## Deck top above the berth terminal origin (foundation apron crown).
## Keep nearly flush — a raised pad reads as a step out of the apron.
const QUAY_DECK_TOP_LOCAL_Y := 0.02
const QUAY_DECK_SLAB_H := 0.55
## Asphalt berth pad crown / thickness (same flush rule as quay decks).
const ASPHALT_PAD_TOP_LOCAL_Y := 0.02
const ASPHALT_PAD_H := 0.40
## Small apron props sit on the same flat crown as berth decks.
const APRON_PROP_TOP_Y := 0.02
## Convex footing slab — CharacterBody3D needs a thick box crown, not a thin mesh.
const DECK_WALK_THICKNESS_M := 0.55
const BULK_CRANE_SCRIPT := preload("res://scripts/port/bulk_crane.gd")
const BULK_CRANE_AUTO_SCRIPT := preload("res://scripts/port/bulk_crane_auto_operator.gd")
const BULK_EQUIP_JOB_SCRIPT := preload("res://scripts/port/bulk_crane_equipment_job.gd")
const PROVISION_CRANE_SCRIPT := preload("res://scripts/port/provision_crane.gd")
const PROVISION_CRANE_AUTO_SCRIPT := preload("res://scripts/port/provision_crane_auto_operator.gd")
const PROVISION_EQUIP_JOB_SCRIPT := preload("res://scripts/port/provision_crane_equipment_job.gd")
const CRANE_OPERATOR_SCRIPT := preload("res://scripts/port/crane_operator_npc.gd")
const MOORING_POST_SCRIPT := preload("res://scripts/port/mooring_post.gd")
const PORT_STRUCTURE_LOD := preload("res://scripts/core/port_structure_lod.gd")
const IMPOSTOR_SERVICE := preload("res://scripts/core/impostor_service.gd")


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

@export var show_module_labels := false
@export var show_open_slots := true
@export var show_equipment_shapes := true

var _graph: PortLayoutGraph
var _harbour: HarbourController


func configure(graph: PortLayoutGraph, harbour: HarbourController = null) -> void:
	_graph = graph
	_harbour = harbour
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
	## Apron props deferred — layout first via asphalt/apron gizmos, then decorate.
	_stamp_berth_terminals()
	_stamp_apron_pads()
	_stamp_land_structures()
	for instance_id in _graph.module_ids():
		_stamp_module(_graph.modules[instance_id] as PortPlacedModule)
	if show_open_slots:
		for slot in _graph.open_slots():
			if _should_stamp_open_slot(slot):
				_stamp_open_slot(slot)


func _port_id() -> String:
	if _harbour != null:
		return _harbour.port_id()
	return "port"


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
	## Walk slabs only — trimesh cook was a first-frame hitch with little gameplay gain.
	_stamp_foundation_walk_boxes(spine_pts, sea_top, inland_top, top_y)


func _stamp_foundation_walk_boxes(
		spine_pts: PackedVector2Array,
		sea_top: PackedVector2Array,
		inland_top: PackedVector2Array,
		top_y: float,
) -> void:
	if spine_pts.size() < 2:
		return
	var root := Node3D.new()
	root.name = "FoundationWalkCollision"
	add_child(root)
	var slab_h := 0.55
	for index in range(spine_pts.size() - 1):
		var a_sea := sea_top[index]
		var b_sea := sea_top[index + 1]
		var a_in := inland_top[index]
		var b_in := inland_top[index + 1]
		var center := (a_sea + b_sea + a_in + b_in) * 0.25
		var along := (b_sea - a_sea + b_in - a_in) * 0.5
		var across := (a_in - a_sea + b_in - b_sea) * 0.5
		var length := maxf(along.length(), 1.0)
		var width := maxf(across.length(), 1.0)
		var yaw := atan2(along.x, along.y)
		_add_box_collision(
			root,
			"WalkSlab_%d" % index,
			Vector3(width, slab_h, length),
			Vector3(center.x, top_y - slab_h * 0.5, center.y),
			yaw,
		)


func _foundation_surface_y() -> float:
	var foundation := _graph.initial_attributes.get("foundation", {}) as Dictionary
	return float(foundation.get("surface_y_m", PortCoastTracer.FOUNDATION_SURFACE_Y_M)) \
			+ PortCoastTracer.FOUNDATION_TERRAIN_CLEARANCE_M


## Trade berths planned on the asphalt dock face — wide decks with gear + yard.
func _stamp_berth_terminals() -> void:
	if not show_equipment_shapes:
		return
	var plan := _graph.initial_attributes.get("berth_plan", {}) as Dictionary
	if plan.is_empty():
		return
	var surface_y := _foundation_surface_y()
	var root := Node3D.new()
	root.name = "BerthTerminals"
	add_child(root)
	for index in range((plan.get("quay_stations", []) as Array).size()):
		var station := (plan.get("quay_stations", []) as Array)[index] as Dictionary
		if str(station.get("layout", "")) == "twin_joined":
			_stamp_berth_quay_twin(root, station, surface_y)
			continue
		## Prefer plan berth_side when present (gameplay / docking later).
		var berth_sign := float(station.get("berth_side", 1 if (index % 2) == 0 else -1))
		if is_zero_approx(berth_sign):
			berth_sign = 1.0 if (index % 2) == 0 else -1.0
		_stamp_berth_quay(root, station, surface_y, berth_sign)
	for raw in plan.get("asphalt_stations", []) as Array:
		_stamp_berth_asphalt(root, raw as Dictionary, surface_y)


func _commodities_from_station(station: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for commodity in station.get("commodities", []) as Array:
		var cid := str(commodity)
		if not cid.is_empty() and cid not in out:
			out.append(cid)
	for zone in station.get("zones", []) as Array:
		var cid := str((zone as Dictionary).get("commodity_id", ""))
		if not cid.is_empty() and cid not in out:
			out.append(cid)
	return out


func _make_berth_slot(
		terminal: Node3D,
		station_id: String,
		family: String,
		commodities: PackedStringArray,
		length_m: float,
		width_m: float,
		berth_sign: float,
		water_dir_local: Vector3 = Vector3(0.0, 0.0, 1.0),
		face_offset_m: float = -1.0,
) -> QuayBerthSlot:
	var berth_id := HarbourController.make_berth_id(_port_id(), station_id)
	var slot := QuayBerthSlot.new()
	slot.setup(
		berth_id,
		station_id,
		family,
		commodities,
		length_m,
		width_m,
		berth_sign,
		water_dir_local,
		face_offset_m,
	)
	terminal.add_child(slot)
	terminal.set_meta("berth_id", berth_id)
	if _harbour != null:
		_harbour.register_berth(slot)
	_stamp_ship_berth_pocket(slot)
	return slot


## Water-side legal ship pocket — visual only (no collision). Ships dock into this volume.
func _stamp_ship_berth_pocket(slot: QuayBerthSlot) -> void:
	if slot == null:
		return
	var design_beam := PortSizing.design_hull_beam_m(_size_class())
	var design_loa := PortSizing.design_hull_loa_m(_size_class())
	var water := slot.water_dir_local.normalized()
	if water.length_squared() < 0.0001:
		water = Vector3(0.0, 0.0, 1.0)
	var along := Vector3(-water.z, 0.0, water.x)
	if along.length_squared() < 0.0001:
		along = Vector3(0.0, 0.0, -1.0)
	else:
		along = along.normalized()
	var loa := clampf(design_loa * 1.05, 16.0, maxf(slot.length_m * 0.9, 16.0))
	var pocket_out := design_beam + slot.berth_gap_m * 2.0
	var centre := water * (slot.face_offset_m + slot.berth_gap_m + design_beam * 0.5)
	## Parent terminal sits on the apron surface; waterline is below that in local Y.
	var surface_y := 0.0
	var parent_n := slot.get_parent() as Node3D
	if parent_n != null:
		surface_y = parent_n.position.y
	var water_local_y := WaveSurface.WATER_LEVEL - surface_y
	## Size: along quay × thin slab × out into basin.
	var size := Vector3(
		absf(along.x) * loa + absf(water.x) * pocket_out,
		0.4,
		absf(along.z) * loa + absf(water.z) * pocket_out,
	)
	var family_color := CommodityCatalog.terminal_family_color(slot.family)
	var fill := Color(family_color.r, family_color.g, family_color.b, 0.32)
	var pocket := MeshBuilder.box(size, fill, 1.0, 0.0)
	pocket.name = "ShipBerthPocket"
	pocket.position = centre + Vector3(0.0, water_local_y + 0.15, 0.0)
	pocket.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	slot.add_child(pocket)
	WorldGizmos.register(pocket, WorldGizmos.LAYER_PORT_LAYOUT)

	## Bright face line — land ends here; ships stay outside.
	var edge_size := Vector3(
		absf(along.x) * loa * 0.98 + absf(water.x) * 0.85,
		0.55,
		absf(along.z) * loa * 0.98 + absf(water.z) * 0.85,
	)
	var edge := MeshBuilder.box(
		edge_size,
		Color(0.95, 0.72, 0.22, 0.9),
		0.7,
		0.1,
	)
	edge.name = "ShipBerthFace"
	edge.position = water * (slot.face_offset_m + 0.4) + Vector3(0.0, QUAY_DECK_TOP_LOCAL_Y + 0.15, 0.0)
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	slot.add_child(edge)
	WorldGizmos.register(edge, WorldGizmos.LAYER_PORT_LAYOUT)

	var label := Label3D.new()
	label.name = "ShipBerthLabel"
	label.text = "SHIP BERTH\n%s" % CommodityCatalog.terminal_family_display(slot.family).to_upper()
	label.pixel_size = 0.018
	label.modulate = Color(0.98, 0.90, 0.55)
	label.outline_modulate = Color(0.05, 0.06, 0.08, 0.85)
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = centre + Vector3(0.0, water_local_y + 5.0, 0.0)
	slot.add_child(label)
	WorldGizmos.register(label, WorldGizmos.LAYER_PORT_LAYOUT)


func _stamp_berth_bollards(
		terminal: Node3D,
		slot: QuayBerthSlot,
		length_m: float,
		width_m: float,
		berth_sign: float,
) -> void:
	if slot == null:
		return
	var edge_x := berth_sign * (width_m * 0.5 - 0.85)
	var usable := length_m * 0.88
	var count := clampi(int(floor(usable / 18.0)) + 1, 2, 8)
	var span := usable * 0.92
	var start_z := -span * 0.5
	var step := span / float(maxi(count - 1, 1))
	for i in range(count):
		var post: MooringPost = MOORING_POST_SCRIPT.new() as MooringPost
		post.name = "Bollard_%d" % i
		post.mooring_visual = MooringPost.MooringVisual.DOCKING_BOLLARD
		post.bollard_scale = 1.15
		post.position = Vector3(edge_x, QUAY_DECK_TOP_LOCAL_Y, start_z + float(i) * step)
		terminal.add_child(post)
		slot.add_bollard(post)


func _stamp_asphalt_bollards(
		pad_root: Node3D,
		slot: QuayBerthSlot,
		length_m: float,
		depth_m: float,
) -> void:
	if slot == null:
		return
	var count := clampi(int(floor(length_m / 16.0)) + 1, 2, 6)
	var span := length_m * 0.82
	var start_x := -span * 0.5
	var step := span / float(maxi(count - 1, 1))
	var edge_z := depth_m * 0.5 - 1.1
	for i in range(count):
		var post: MooringPost = MOORING_POST_SCRIPT.new() as MooringPost
		post.name = "Bollard_%d" % i
		post.mooring_visual = MooringPost.MooringVisual.DOCKING_BOLLARD
		post.bollard_scale = 1.1
		post.position = Vector3(start_x + float(i) * step, ASPHALT_PAD_TOP_LOCAL_Y, edge_z)
		pad_root.add_child(post)
		slot.add_bollard(post)


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
	var station_id := str(station.get("id", "quay"))
	var terminal := Node3D.new()
	terminal.name = station_id
	terminal.position = Vector3(mid.x, surface_y, mid.y)
	_align_node_seaward(terminal, seaward)
	parent.add_child(terminal)
	terminal.set_meta("deck_half_w", width_m * 0.5)
	var slot := _make_berth_slot(
		terminal,
		station_id,
		family,
		_commodities_from_station(station),
		length_m,
		width_m,
		berth_sign,
		Vector3(berth_sign, 0.0, 0.0),
	)
	_stamp_berth_bollards(terminal, slot, length_m, width_m, berth_sign)

	## Cross-section (local X): cargo | road | crane · berth_sign · +X = ship face.
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

	_stamp_quay_pier_model(terminal, length_m, width_m, surface_y)

	var road := MeshBuilder.box(
		Vector3(road_w, 0.14, usable_len),
		Color(0.07, 0.07, 0.08),
		1.0,
		0.0,
	)
	road.name = "Road"
	road.position = Vector3(road_x, QUAY_DECK_TOP_LOCAL_Y + 0.08, 0.0)
	terminal.add_child(road)

	_stamp_quay_storage_lane(
		terminal,
		station,
		storage_x,
		storage_w,
		usable_len,
		z0,
		berth_sign,
		slot,
	)
	_stamp_quay_crane_lane(
		terminal,
		station,
		crane_x,
		crane_lane_w,
		usable_len,
		z0,
		berth_sign,
		slot,
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
			CommodityCatalog.commodity_color(str((station.get("commodities", ["provisions"]) as Array)[0])) \
					if not (station.get("commodities", []) as Array).is_empty() \
					else family_color.lightened(0.2),
			0.03,
		)


## Twin pier: dock|crane|cargo|road|cargo|crane|dock — one deck, two outer berths.
func _stamp_berth_quay_twin(parent: Node3D, station: Dictionary, surface_y: float) -> void:
	var origin := _xz2(station.get("origin", [0.0, 0.0]))
	var tip := _xz2(station.get("tip", [origin.x, origin.y]))
	var seaward := _xz2(station.get("direction", [0.0, -1.0])).normalized()
	if seaward.length_squared() < 0.001:
		seaward = PortCoastTracer.PORT_LOCAL_SEAWARD_DIR
	var length_m := float(station.get("length_m", origin.distance_to(tip)))
	var width_m := float(station.get("width_m", PortSizing.twin_quay_deck_width_m(_size_class())))
	var mid := origin.lerp(tip, 0.5)
	var terminal := Node3D.new()
	terminal.name = str(station.get("id", "quay_twin"))
	terminal.position = Vector3(mid.x, surface_y, mid.y)
	_align_node_seaward(terminal, seaward)
	parent.add_child(terminal)
	terminal.set_meta("deck_half_w", width_m * 0.5)

	var unit := PortSizing.quay_deck_width_for_arm_m(length_m, _size_class())
	var crane_lane_w := clampf(unit * 0.34, 14.0, 36.0)
	var storage_w := clampf(unit * 0.34, 14.0, 36.0)
	var road_w := clampf(unit * 0.22, 8.0, 16.0)
	var lane_sum := crane_lane_w * 2.0 + storage_w * 2.0 + road_w
	if lane_sum > width_m and lane_sum > 0.01:
		var scale := width_m / lane_sum
		crane_lane_w *= scale
		storage_w *= scale
		road_w *= scale
	var usable_len := length_m * 0.90
	var z0 := -usable_len * 0.5

	_stamp_quay_pier_model(terminal, length_m, width_m, surface_y)

	var road := MeshBuilder.box(
		Vector3(road_w, 0.14, usable_len),
		Color(0.07, 0.07, 0.08),
		1.0,
		0.0,
	)
	road.name = "CentreRoad"
	road.position = Vector3(0.0, QUAY_DECK_TOP_LOCAL_Y + 0.08, 0.0)
	terminal.add_child(road)

	var base_station_id := str(station.get("id", "quay_twin"))
	var sides: Array = station.get("sides", []) as Array
	for side_index in range(mini(sides.size(), 2)):
		var side: Dictionary = sides[side_index]
		var berth_sign := float(side.get("berth_side", -1.0 if side_index == 0 else 1.0))
		if is_zero_approx(berth_sign):
			berth_sign = -1.0 if side_index == 0 else 1.0
		var crane_x := berth_sign * (width_m * 0.5 - crane_lane_w * 0.5)
		var storage_x := berth_sign * (
			width_m * 0.5 - crane_lane_w - storage_w * 0.5
		)
		var side_id := "%s/side_%d" % [base_station_id, side_index]
		var side_family := str(side.get("family", station.get("family", "general")))
		var slot := _make_berth_slot(
			terminal,
			side_id,
			side_family,
			_commodities_from_station(side),
			length_m,
			width_m,
			berth_sign,
			Vector3(berth_sign, 0.0, 0.0),
		)
		_stamp_berth_bollards(terminal, slot, length_m, width_m, berth_sign)
		_stamp_quay_storage_lane(
			terminal, side, storage_x, storage_w, usable_len, z0, berth_sign, slot
		)
		_stamp_quay_crane_lane(
			terminal, side, crane_x, crane_lane_w, usable_len, z0, berth_sign, slot
		)

	if show_module_labels:
		var zone_bits: PackedStringArray = []
		for side in sides:
			for commodity in (side as Dictionary).get("commodities", []) as Array:
				zone_bits.append(CommodityCatalog.commodity_display(str(commodity)))
		_label(
			"BerthLabel_%s" % str(station.get("id", "quay_twin")),
			"TWIN QUAY\n%s\n%.0f m" % [" · ".join(zone_bits), length_m],
			Vector3(mid.x, surface_y + 18.0, mid.y) + Vector3(seaward.x, 0.0, seaward.y) * (length_m * 0.15),
			Color(0.85, 0.85, 0.7),
			0.03,
		)


## Solid quay arm: pavement deck + underwater pier mass + collision.
## Extends from the asphalt apron into the basin; depth matches foundation seaward embed
## so boat cameras cannot slip under the pier.
func _stamp_quay_pier_model(
		terminal: Node3D,
		length_m: float,
		width_m: float,
		surface_y: float,
) -> void:
	var foundation := _graph.initial_attributes.get("foundation", {}) as Dictionary
	var seaward_depth := float(foundation.get(
		"seaward_depth_m",
		PortCoastTracer.FOUNDATION_SEAWARD_DEPTH_M,
	))
	var deck_top := QUAY_DECK_TOP_LOCAL_Y
	var deck_bottom := deck_top - QUAY_DECK_SLAB_H
	var water_bottom_world := WaveSurface.WATER_LEVEL - seaward_depth
	var bottom_local := water_bottom_world - surface_y
	## One column from basin floor through the deck crown — boats cannot slip
	## under the arm and the player walks on the same surface as the mesh.
	var pier_h := maxf(deck_top - bottom_local, 2.0)
	var pier_center_y := bottom_local + pier_h * 0.5

	var root := Node3D.new()
	root.name = "QuayPier"
	terminal.add_child(root)

	## Underwater / freeboard mass — opaque so the camera cannot see “through” the pier.
	var mass_top := deck_bottom - 0.02
	var mass_h := maxf(mass_top - bottom_local, 2.0)
	var mass_center_y := bottom_local + mass_h * 0.5
	var mass := MeshBuilder.box(
		Vector3(width_m, mass_h, length_m),
		QUAY_PIER_MASS_COLOR,
		0.95,
		0.0,
	)
	mass.name = "PierMass"
	mass.position = Vector3(0.0, mass_center_y, 0.0)
	mass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mass)

	## Deck slab on the pier crown (same pavement language as the asphalt apron).
	var deck := MeshBuilder.box(
		Vector3(width_m, QUAY_DECK_SLAB_H, length_m),
		FOUNDATION_PAVEMENT_COLOR.lightened(0.04),
		1.0,
		0.0,
	)
	deck.name = "Deck"
	deck.position = Vector3(0.0, deck_bottom + QUAY_DECK_SLAB_H * 0.5, 0.0)
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(deck)

	var body := StaticBody3D.new()
	body.name = "PierCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = Vector3(width_m, pier_h, length_m)
	var col := CollisionShape3D.new()
	col.name = "Shape"
	col.shape = shape
	col.position = Vector3(0.0, pier_center_y, 0.0)
	body.add_child(col)
	## Belt-and-suspenders footing slab on the deck crown for CB3D floor snaps.
	_add_deck_walk_collision(
		root,
		"DeckWalkCollision",
		Vector2(width_m, length_m),
		deck_top,
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
		slot: QuayBerthSlot = null,
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
	## General cargo: one live yard pad per crane bay (same plan as crane lane).
	var general_tools := _plan_quay_tools(station, usable_len, z0)
	for tool_index in range(general_tools.size()):
		var tool := general_tools[tool_index] as Dictionary
		if str(tool.get("family", "")) != "general":
			continue
		_stamp_general_cargo_quay_yard(
			lane,
			lane_x,
			lane_w,
			float(tool.get("bay_len", usable_len * 0.85)),
			float(tool.get("z", 0.0)),
			slot,
			tool_index,
			str(tool.get("role", "")),
		)

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

		## Non-general families keep decorative storage stacks / mounds.
		if zone_family != "general":
			## Full commodity colour on the storage apron — readable from above.
			## Bulk ore skips the pad: stockpile mounds already mark the zone.
			if zone_family != "bulk_ore":
				var apron := MeshBuilder.box(
					Vector3(lane_w * 0.96, 0.22, zone_len * 0.96),
					color,
					0.9,
					0.0,
				)
				apron.name = "ZoneApron_%d" % zone_index
				apron.position = Vector3(lane_x, QUAY_DECK_TOP_LOCAL_Y + 0.12, zone_mid_z)
				lane.add_child(apron)

			var pad_len := clampf(zone_len * 0.42, 14.0, 36.0)
			var gap := 3.5
			var count := maxi(1, int(floor((zone_len * 0.9 + gap) / (pad_len + gap))))
			var span := float(count) * pad_len + float(maxi(count - 1, 0)) * gap
			var start_z := zone_mid_z - span * 0.5 + pad_len * 0.5
			var stack_w := lane_w * 0.82
			for pad_i in range(count):
				var z := start_z + float(pad_i) * (pad_len + gap)
				var height := _storage_stack_height(zone_family, pad_i)
				var stack_size := Vector3(stack_w, height, pad_len * 0.88)
				var stack: Node3D
				if zone_family == "bulk_ore":
					var cid := commodity_id if not commodity_id.is_empty() else "iron_ore"
					var mound := OreMound.create(
						cid,
						stack_size,
						cid.hash() + pad_i * 17 + zone_index * 31,
					)
					mound.name = "Cargo_%d_%d" % [zone_index, pad_i]
					mound.position = Vector3(lane_x, QUAY_DECK_TOP_LOCAL_Y, z)
					lane.add_child(mound)
					if slot != null and _harbour != null:
						_harbour.register_yard(mound, slot.berth_id)
					continue
				stack = _make_storage_stack(zone_family, color, stack_size, commodity_id)
				stack.name = "Cargo_%d_%d" % [zone_index, pad_i]
				stack.position = Vector3(lane_x, QUAY_DECK_TOP_LOCAL_Y, z)
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


## Shared crane/yard bay plan — one entry per tool along the quay.
## Each: { z, family, role, bay_len }.
func _plan_quay_tools(station: Dictionary, usable_len: float, z0: float) -> Array[Dictionary]:
	var tools: Array[Dictionary] = []
	var zones: Array = station.get("zones", []) as Array
	var family_for_spacing := str(station.get("family", "general"))
	var station_role := str(station.get("role", ""))
	## Bulk grab unloaders need denser coverage — short boats only sit under one bay.
	var bulk_spacing_m := 32.0
	if zones.size() >= 2:
		for zone in zones:
			var zd := zone as Dictionary
			var t0 := float(zd.get("t0", 0.0))
			var t1 := float(zd.get("t1", 1.0))
			var zone_mid := z0 + usable_len * ((t0 + t1) * 0.5)
			var zone_len := usable_len * maxf(t1 - t0, 0.05)
			var zone_family := str(zd.get("family", family_for_spacing))
			var zone_role := str(zd.get("role", station_role))
			if zone_family.begins_with("bulk") and zone_len >= bulk_spacing_m * 1.5:
				var count := maxi(1, int(ceil(zone_len / bulk_spacing_m)))
				var span := minf(zone_len * 0.9, float(maxi(count - 1, 0)) * bulk_spacing_m)
				var start := zone_mid - span * 0.5
				var step := span / float(maxi(count - 1, 1)) if count > 1 else 0.0
				var bay_len := zone_len / float(count)
				for i in range(count):
					tools.append({
						"z": start + float(i) * step,
						"family": zone_family,
						"role": zone_role,
						"bay_len": bay_len,
					})
			else:
				tools.append({
					"z": zone_mid,
					"family": zone_family,
					"role": zone_role,
					"bay_len": zone_len,
				})
		return tools

	## Prefer the sole zone's role when present (station dict uses "roles" array).
	var spaced_role := station_role
	var spaced_family := family_for_spacing
	if zones.size() == 1:
		var sole := zones[0] as Dictionary
		spaced_role = str(sole.get("role", spaced_role))
		spaced_family = str(sole.get("family", spaced_family))
	elif spaced_role.is_empty():
		var roles: Array = station.get("roles", []) as Array
		if roles.size() == 1:
			spaced_role = str(roles[0])
		elif roles.has("import") and roles.has("export"):
			spaced_role = "import_export"

	var tool_count := 1
	if spaced_family.begins_with("bulk"):
		tool_count = maxi(1, int(ceil(usable_len / bulk_spacing_m)))
	elif usable_len >= 160.0:
		tool_count = 3
	elif usable_len >= 90.0:
		tool_count = 2
	var bay_len := usable_len / float(tool_count)
	if tool_count == 1:
		tools.append({
			"z": 0.0,
			"family": spaced_family,
			"role": spaced_role,
			"bay_len": usable_len * 0.85,
		})
		return tools
	var tool_span := usable_len * (0.88 if spaced_family.begins_with("bulk") else 0.72)
	var step := tool_span / float(tool_count - 1)
	var start_z := z0 + (usable_len - tool_span) * 0.5
	for index in range(tool_count):
		tools.append({
			"z": start_z + float(index) * step,
			"family": spaced_family,
			"role": spaced_role,
			"bay_len": bay_len * 0.92,
		})
	return tools


## Load/unload tools — one per commodity zone when shared, else spaced by length.
func _stamp_quay_crane_lane(
		terminal: Node3D,
		station: Dictionary,
		lane_x: float,
		lane_w: float,
		usable_len: float,
		z0: float,
		berth_sign: float,
		slot: QuayBerthSlot = null,
) -> void:
	var lane := Node3D.new()
	lane.name = "CraneLane"
	terminal.add_child(lane)

	var tools := _plan_quay_tools(station, usable_len, z0)
	var family := str(station.get("family", "general"))
	var fp := Vector3(
		clampf(lane_w * 0.85, 10.0, 28.0),
		1.0,
		clampf(lane_w * 0.7, 10.0, 24.0),
	)
	var berth_id := slot.berth_id if slot != null else ""
	for index in range(tools.size()):
		var tool: Dictionary = tools[index]
		var z := float(tool.get("z", 0.0))
		var tool_family := str(tool.get("family", family))
		var equip_kind := PortBerthPlan.equipment_for_family(tool_family)
		if equip_kind.is_empty():
			equip_kind = str(station.get("equipment_kind", "equip_jib_crane"))
		var equip_root := Node3D.new()
		equip_root.name = "Tool_%d" % index
		equip_root.position = Vector3(lane_x, QUAY_DECK_TOP_LOCAL_Y, z)
		if berth_sign < 0.0:
			equip_root.rotation_degrees.y = 180.0
		lane.add_child(equip_root)
		_stamp_equipment_kind(equip_root, equip_kind, fp, tool_family, berth_sign, berth_id, index)


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


func _make_storage_stack(
		family: String,
		family_color: Color,
		size: Vector3,
		commodity_id: String = "",
) -> Node3D:
	if family == "bulk_ore":
		var cid := commodity_id if not commodity_id.is_empty() else "iron_ore"
		return OreMoundBuilder.build_mound(cid, size, cid.hash() + int(size.length() * 100.0))
	var root := Node3D.new()
	match family:
		"liquid":
			var tank_h := size.y
			var tank := MeshBuilder.cylinder(
				minf(size.x, size.z) * 0.38,
				tank_h,
				family_color.lightened(0.05),
				0.85,
				0.15,
			)
			tank.position.y = tank_h * 0.5
			root.add_child(tank)
		"bulk_grain":
			var grain_h := size.y * 0.88
			var grain := MeshBuilder.box(
				Vector3(size.x * 0.9, grain_h, size.z * 0.85),
				family_color.darkened(0.1),
				0.95,
				0.0,
			)
			grain.position.y = grain_h * 0.5
			root.add_child(grain)
		"container", "general":
			var tiers := maxi(1, int(round(size.y / 2.6)))
			var tier_h := size.y / float(tiers)
			for tier in range(tiers):
				var box_h := tier_h * 0.88
				var box := MeshBuilder.box(
					Vector3(size.x * 0.92, box_h, size.z * 0.9),
					family_color.lightened(0.05 * float(tier % 2)),
					0.8,
					0.05,
				)
				box.position = Vector3(0.0, box_h * 0.5 + tier_h * float(tier), 0.0)
				root.add_child(box)
		_:
			var lump_h := size.y * 0.85
			var lump := MeshBuilder.box(
				size * Vector3(0.9, 0.85, 0.85),
				family_color.darkened(0.05),
				0.9,
				0.0,
			)
			lump.position.y = lump_h * 0.5
			root.add_child(lump)
	return root


func _stamp_apron_pads() -> void:
	## Always stamp a pad marker on every placed site; swap in BuildingFitout when designed.
	var land_plan := _graph.initial_attributes.get("land_plan", {}) as Dictionary
	if land_plan.is_empty():
		return
	var apron_pads: Dictionary = land_plan.get("apron_pads", {}) as Dictionary
	var pads: Array = apron_pads.get("pads", []) as Array
	if pads.is_empty():
		return
	var foundation := _graph.initial_attributes.get("foundation", {}) as Dictionary
	var surface_y := float(foundation.get("surface_y_m", PortCoastTracer.FOUNDATION_SURFACE_Y_M)) \
			+ PortCoastTracer.FOUNDATION_TERRAIN_CLEARANCE_M
	var root := Node3D.new()
	root.name = "ApronPads"
	add_child(root)
	for raw in pads:
		var pad: Dictionary = raw
		var role_id := str(pad.get("role", ""))
		var template_id := str(pad.get("pad_template_id", ""))
		if role_id.is_empty():
			continue
		var origin := _xz2(pad.get("origin", [0.0, 0.0]))
		var along := _xz2(pad.get("along_dir", [1.0, 0.0])).normalized()
		var inland := _xz2(pad.get("inland_dir", [0.0, 1.0])).normalized()
		if along.length_squared() < 0.01:
			along = Vector2(1.0, 0.0)
		if inland.length_squared() < 0.01:
			inland = PortCoastTracer.PORT_LOCAL_INLAND_DIR
		var size_arr: Array = pad.get("size_m", [
			PortApronPadCatalog.CELL_M, PortApronPadCatalog.CELL_M,
		]) as Array
		var size_x := float(size_arr[0]) if size_arr.size() > 0 else PortApronPadCatalog.CELL_M
		var size_z := float(size_arr[1]) if size_arr.size() > 1 else PortApronPadCatalog.CELL_M
		var site := Node3D.new()
		site.name = str(pad.get("id", role_id))
		site.position = Vector3(origin.x, surface_y, origin.y)
		var z_axis := Vector3(inland.x, 0.0, inland.y).normalized()
		var x_axis := Vector3.UP.cross(z_axis).normalized()
		if x_axis.dot(Vector3(along.x, 0.0, along.y)) < 0.0:
			x_axis = -x_axis
		var y_axis := z_axis.cross(x_axis).normalized()
		site.basis = Basis(x_axis, y_axis, z_axis)
		root.add_child(site)
		site.set_meta("apron_pad_role", role_id)
		site.set_meta("apron_pad_template", template_id)

		var layout := BuildingBlueprintCatalog.find_for_pad(role_id, template_id)
		if layout != null:
			var blueprint_id := layout.blueprint_id.strip_edges()
			var lod = PORT_STRUCTURE_LOD.new()
			lod.name = "BuildingLod"
			site.add_child(lod)
			var captured := layout
			lod.setup(
				IMPOSTOR_SERVICE.building_key(blueprint_id),
				func() -> Node3D:
					var building := BuildingCache.instance(captured, true)
					if building != null:
						building.name = "Building"
					return building if building != null else Node3D.new(),
			)
			continue
		## Placeholder so every pad site always reads in-world (until you save a blueprint).
		_stamp_apron_pad_placeholder(site, size_x, size_z, role_id)


func _stamp_apron_pad_placeholder(
		parent: Node3D,
		size_x: float,
		size_z: float,
		role_id: String,
) -> void:
	var pad_col := Color(0.22, 0.62, 0.88, 1.0)
	if role_id.begins_with("fish") or role_id.begins_with("provisions"):
		pad_col = Color(0.92, 0.48, 0.22, 1.0)
	var slab := MeshBuilder.box(Vector3(size_x * 0.92, 0.45, size_z * 0.92), pad_col, 0.9, 0.0)
	slab.name = "PadSlab"
	slab.position = Vector3(0.0, 0.22, 0.0)
	parent.add_child(slab)
	## Simple massing so the site reads as a building lot, not an empty plate.
	var body_h := clampf(minf(size_x, size_z) * 0.28, 4.0, 10.0)
	var body := MeshBuilder.box(
		Vector3(size_x * 0.55, body_h, size_z * 0.45),
		pad_col.lightened(0.12),
		0.88,
		0.0,
	)
	body.name = "PadMass"
	body.position = Vector3(0.0, 0.45 + body_h * 0.5, 0.0)
	parent.add_child(body)


func _stamp_apron_decor() -> void:
	var land_plan := _graph.initial_attributes.get("land_plan", {}) as Dictionary
	if land_plan.is_empty():
		return
	var apron: Dictionary = land_plan.get("apron_decor", {}) as Dictionary
	var points: Array = apron.get("points", []) as Array
	if points.is_empty():
		return
	var foundation := _graph.initial_attributes.get("foundation", {}) as Dictionary
	var surface_y := float(foundation.get("surface_y_m", PortCoastTracer.FOUNDATION_SURFACE_Y_M)) \
			+ PortCoastTracer.FOUNDATION_TERRAIN_CLEARANCE_M
	var root := Node3D.new()
	root.name = "ApronDecor"
	add_child(root)
	for index in range(points.size()):
		var entry: Dictionary = points[index]
		var local_arr: Array = entry.get("local", [0.0, 0.0]) as Array
		if local_arr.size() < 2:
			continue
		var lx := float(local_arr[0])
		var lz := float(local_arr[1])
		var yaw_deg := float(entry.get("yaw_deg", 0.0))
		var family := str(entry.get("family", "general"))
		var color := CommodityCatalog.terminal_family_color(family)
		var prop := Node3D.new()
		prop.name = "Apron_%s_%d" % [str(entry.get("kind", "prop")), index]
		prop.position = Vector3(lx, surface_y, lz)
		prop.rotation.y = deg_to_rad(yaw_deg)
		root.add_child(prop)
		match str(entry.get("kind", "")):
			PortLandPlan.APRON_KIND_LAMP:
				_stamp_apron_lamp(prop)
			PortLandPlan.APRON_KIND_CRATES:
				_stamp_apron_crates(prop, color)
			PortLandPlan.APRON_KIND_PALLETS:
				_stamp_apron_pallets(prop, color)
			PortLandPlan.APRON_KIND_DRUMS:
				_stamp_apron_drums(prop, color)
			PortLandPlan.APRON_KIND_HOSE:
				_stamp_apron_hose_reel(prop, color)
			PortLandPlan.APRON_KIND_BOLLARD:
				_stamp_apron_bollard(prop)
			PortLandPlan.APRON_KIND_SIGN:
				_stamp_apron_sign(prop, family)
			PortLandPlan.APRON_KIND_HATCH:
				_stamp_apron_hatch(prop)
			_:
				_stamp_apron_crates(prop, color)


func _stamp_apron_lamp(parent: Node3D) -> void:
	var pole := MeshBuilder.cylinder(0.14, 5.6, Color(0.42, 0.43, 0.45), 0.88, 0.05)
	pole.position = Vector3(0.0, APRON_PROP_TOP_Y + 2.8, 0.0)
	parent.add_child(pole)
	var head := MeshBuilder.box(Vector3(0.55, 0.35, 0.55), Color(0.92, 0.88, 0.72), 0.75, 0.0)
	head.position = Vector3(0.0, APRON_PROP_TOP_Y + 5.75, 0.0)
	parent.add_child(head)
	var base := MeshBuilder.cylinder(0.28, 0.18, Color(0.30, 0.31, 0.33), 0.92, 0.0)
	base.position = Vector3(0.0, APRON_PROP_TOP_Y + 0.09, 0.0)
	parent.add_child(base)


func _stamp_apron_crates(parent: Node3D, color: Color) -> void:
	var crate_col := color.darkened(0.12).lerp(Color(0.48, 0.40, 0.32), 0.35)
	for i in range(3):
		var w := lerpf(1.1, 1.5, float(i) * 0.35)
		var h := lerpf(1.0, 1.35, float(i) * 0.25)
		var crate := MeshBuilder.box(Vector3(w, h, w * 0.92), crate_col, 0.9, 0.0)
		crate.position = Vector3(
			float(i - 1) * 1.15,
			APRON_PROP_TOP_Y + h * 0.5,
			float(i % 2) * 0.55 - 0.25,
		)
		parent.add_child(crate)


func _stamp_apron_pallets(parent: Node3D, color: Color) -> void:
	var plank := color.darkened(0.18).lerp(Color(0.55, 0.42, 0.30), 0.4)
	for tier in range(2):
		var pallet := MeshBuilder.box(Vector3(1.8, 0.22, 1.2), plank, 0.92, 0.0)
		pallet.position = Vector3(0.0, APRON_PROP_TOP_Y + 0.11 + float(tier) * 0.24, 0.0)
		parent.add_child(pallet)
		var load := MeshBuilder.box(Vector3(1.5, 0.85, 1.0), color.darkened(0.05), 0.88, 0.0)
		load.position = Vector3(0.15, APRON_PROP_TOP_Y + 0.55 + float(tier) * 0.24, -0.1)
		parent.add_child(load)


func _stamp_apron_drums(parent: Node3D, color: Color) -> void:
	var drum_col := color.darkened(0.08).lerp(Color(0.42, 0.44, 0.48), 0.45)
	for i in range(2):
		var drum := MeshBuilder.cylinder(0.42, 1.05, drum_col, 0.82, 0.12)
		drum.position = Vector3(float(i) * 1.05 - 0.52, APRON_PROP_TOP_Y + 0.52, 0.0)
		parent.add_child(drum)
		var band := MeshBuilder.torus(0.38, 0.44, Color(0.28, 0.28, 0.30), 0.7, 0.35)
		band.rotation.x = deg_to_rad(90.0)
		band.position = Vector3(float(i) * 1.05 - 0.52, APRON_PROP_TOP_Y + 0.52, 0.0)
		parent.add_child(band)


func _stamp_apron_hose_reel(parent: Node3D, color: Color) -> void:
	var stand := MeshBuilder.box(Vector3(0.9, 0.65, 0.7), Color(0.38, 0.39, 0.41), 0.9, 0.05)
	stand.position = Vector3(0.0, APRON_PROP_TOP_Y + 0.32, 0.0)
	parent.add_child(stand)
	var reel := MeshBuilder.cylinder(0.55, 0.45, color.darkened(0.1), 0.85, 0.1)
	reel.rotation.z = deg_to_rad(90.0)
	reel.position = Vector3(0.0, APRON_PROP_TOP_Y + 0.95, 0.0)
	parent.add_child(reel)


func _stamp_apron_bollard(parent: Node3D) -> void:
	var post: MooringPost = MOORING_POST_SCRIPT.new() as MooringPost
	post.name = "ApronBollard"
	post.mooring_visual = MooringPost.MooringVisual.DOCKING_BOLLARD
	post.bollard_scale = 1.0
	post.position = Vector3(0.0, APRON_PROP_TOP_Y, 0.0)
	parent.add_child(post)


func _stamp_apron_sign(parent: Node3D, family: String) -> void:
	var pole := MeshBuilder.cylinder(0.08, 2.8, Color(0.40, 0.41, 0.43), 0.9, 0.0)
	pole.position = Vector3(0.0, APRON_PROP_TOP_Y + 1.4, 0.0)
	parent.add_child(pole)
	var board := MeshBuilder.box(Vector3(1.4, 0.9, 0.08), CommodityCatalog.terminal_family_color(family), 0.82, 0.0)
	board.position = Vector3(0.0, APRON_PROP_TOP_Y + 2.95, 0.0)
	parent.add_child(board)


func _stamp_apron_hatch(parent: Node3D) -> void:
	var frame := MeshBuilder.box(Vector3(1.6, 0.06, 1.1), Color(0.22, 0.22, 0.24), 0.95, 0.0)
	frame.position = Vector3(0.0, APRON_PROP_TOP_Y + 0.03, 0.0)
	parent.add_child(frame)
	var grate := MeshBuilder.box(Vector3(1.35, 0.04, 0.85), Color(0.48, 0.50, 0.52), 0.88, 0.15)
	grate.position = Vector3(0.0, APRON_PROP_TOP_Y + 0.08, 0.0)
	parent.add_child(grate)


func _stamp_land_structures() -> void:
	## Cheap primitive village from land_plan.terrain_grid — houses + trade yards
	## on sampled terrain. Always stamped with the port (not a gizmo / equipment toggle).
	var plan := _graph.initial_attributes.get("land_plan", {}) as Dictionary
	if plan.is_empty():
		return
	var grid: Dictionary = plan.get("terrain_grid", {}) as Dictionary
	var points: Array = grid.get("points", []) as Array
	if points.is_empty():
		return
	var root := Node3D.new()
	root.name = "LandDecor"
	add_child(root)
	var apron_y := _foundation_surface_y()
	for index in range(points.size()):
		var entry: Dictionary = points[index]
		var local_arr: Array = entry.get("local", [0.0, 0.0]) as Array
		if local_arr.size() < 2:
			continue
		var lx := float(local_arr[0])
		var lz := float(local_arr[1])
		var terrain_y := float(entry.get("y", 0.0))
		## Apron pavement is flattened — never let decor sample below the crown.
		var place_y := maxf(terrain_y, apron_y)
		var kind := str(entry.get("kind", PortLandPlan.KIND_HOUSE))
		if kind == PortLandPlan.KIND_TRADE:
			_stamp_land_trade_point(root, entry, index, lx, place_y, lz)
		else:
			_stamp_land_house_point(root, entry, index, lx, place_y, lz)


func _stamp_land_house_point(
		parent: Node3D,
		entry: Dictionary,
		index: int,
		lx: float,
		terrain_y: float,
		lz: float,
) -> void:
	var u := float(entry.get("u", 0.0))
	var v := float(entry.get("v", 0.0))
	var variant := LandDecorCache.variant_index(index, u, v)
	var lod = PORT_STRUCTURE_LOD.new()
	lod.name = "House_%d" % index
	lod.position = Vector3(lx, terrain_y, lz)
	lod.rotation.y = deg_to_rad(180.0 + float(index % 5) * 12.0 - 24.0)
	parent.add_child(lod)
	lod.setup(
		IMPOSTOR_SERVICE.land_house_key(variant),
		func() -> Node3D:
			var house := LandDecorCache.house_instance(index, u, v)
			house.name = "House"
			return house,
	)


func _stamp_land_trade_point(
		parent: Node3D,
		entry: Dictionary,
		index: int,
		lx: float,
		terrain_y: float,
		lz: float,
) -> void:
	var commodity_id := str(entry.get("commodity_id", ""))
	var role := str(entry.get("role", "trade"))
	var family := str(entry.get("family", ""))
	if family.is_empty():
		family = CommodityCatalog.commodity_terminal_family(commodity_id)
	var decor_kind := _trade_decor_kind(commodity_id, role, family)
	var radius := float(entry.get("radius_m", PortLandPlan.TRADE_RADIUS_M))
	var size := Vector3(radius * 2.0, maxf(radius * 0.85, 8.0), radius * 2.0)
	var color := CommodityCatalog.terminal_family_color(family)
	var cluster := Node3D.new()
	cluster.name = "Trade_%s_%d" % [commodity_id, index]
	cluster.position = Vector3(lx, terrain_y, lz)
	cluster.rotation.y = deg_to_rad(float(index % 7) * 18.0)
	parent.add_child(cluster)
	match decor_kind:
		"fish_market":
			_stamp_land_market(cluster, size, color)
		"warehouse":
			_stamp_land_warehouse(cluster, size, color)
		"silos":
			_stamp_land_silos(cluster, size, color)
		"farm":
			_stamp_land_farm(cluster, size, color)
		"sawmill":
			_stamp_land_sawmill(cluster, size, color)
		"tree_stand":
			_stamp_land_trees(cluster, size, color)
		"ore_mound":
			_stamp_land_ore_mound(cluster, size, commodity_id)
		"minehead":
			_stamp_land_minehead(cluster, size, color)
		"yard_blocks":
			_stamp_land_yard_blocks(cluster, size, color)
		"tank_farm":
			_stamp_land_tank_farm(cluster, size, color)
		_:
			_stamp_land_warehouse(cluster, size, color)
	if show_module_labels:
		_label(
			"TradeLabel_%d" % index,
			"%s\n%s" % [
				CommodityCatalog.commodity_display(commodity_id).to_upper(),
				role.to_upper(),
			],
			Vector3(lx, terrain_y + size.y + 6.0, lz),
			color.lightened(0.2),
			0.02,
		)


func _trade_decor_kind(commodity_id: String, role: String, family: String) -> String:
	match str(commodity_id):
		"fish":
			return "fish_market"
		"grain":
			return "silos" if role == "export" else "farm"
		"timber":
			return "sawmill" if role == "export" else "tree_stand"
		"coal", "iron_ore":
			return "minehead" if role == "export" else "ore_mound"
		"diesel", "crude_oil", "lng":
			return "tank_farm"
		"containers":
			return "yard_blocks"
		"provisions":
			return "warehouse"
		_:
			match family:
				"fishing":
					return "fish_market"
				"bulk_grain":
					return "silos"
				"bulk_ore":
					return "ore_mound"
				"liquid":
					return "tank_farm"
				"container":
					return "yard_blocks"
				_:
					return "warehouse"


## Cheap village house: walls + pitched roof + door/window/chimney (~8×7 m).
func _make_village_house(index: int, u: float, v: float) -> Node3D:
	var root := Node3D.new()
	var tint := fmod(float(index) * 0.17 + u * 0.4 + v * 0.25, 1.0)
	var wall := Color(0.72, 0.28, 0.22).lerp(Color(0.55, 0.42, 0.32), tint)
	var roof_col := Color(0.28, 0.22, 0.20).lerp(Color(0.38, 0.18, 0.14), 1.0 - tint)
	var w := lerpf(7.2, 9.0, fmod(tint * 3.1, 1.0))
	var d := lerpf(6.0, 7.6, fmod(tint * 5.7, 1.0))
	var wall_h := lerpf(3.4, 4.2, fmod(tint * 2.3, 1.0))
	var roof_h := lerpf(2.2, 2.8, fmod(tint * 4.1, 1.0))

	var body := MeshBuilder.box(Vector3(w, wall_h, d), wall, 0.92, 0.0)
	body.position = Vector3(0.0, wall_h * 0.5, 0.0)
	root.add_child(body)
	var roof := MeshBuilder.prism(Vector3(w * 1.08, roof_h, d * 1.04), roof_col, 0.88, 0.0)
	roof.position = Vector3(0.0, wall_h + roof_h * 0.5, 0.0)
	root.add_child(roof)
	var door := MeshBuilder.box(Vector3(w * 0.22, wall_h * 0.55, 0.35), Color(0.22, 0.16, 0.12), 0.9, 0.05)
	door.position = Vector3(0.0, wall_h * 0.28, d * 0.5)
	root.add_child(door)
	var window := MeshBuilder.box(Vector3(w * 0.18, wall_h * 0.28, 0.25), Color(0.55, 0.72, 0.82), 0.35, 0.1)
	window.position = Vector3(w * 0.28, wall_h * 0.55, d * 0.5)
	root.add_child(window)
	var chimney := MeshBuilder.box(Vector3(0.7, roof_h * 0.85, 0.7), Color(0.35, 0.28, 0.26), 0.95, 0.0)
	chimney.position = Vector3(-w * 0.28, wall_h + roof_h * 0.55, -d * 0.15)
	root.add_child(chimney)
	return root


func _stamp_land_structure(parent: Node3D, entry: Dictionary, surface_y: float) -> void:
	var origin := _xz2(entry.get("origin", [0.0, 0.0]))
	var size_arr: Array = entry.get("size_m", [10.0, 5.0, 8.0]) as Array
	var size := Vector3(
		float(size_arr[0]) if size_arr.size() > 0 else 10.0,
		float(size_arr[1]) if size_arr.size() > 1 else 5.0,
		float(size_arr[2]) if size_arr.size() > 2 else 8.0,
	)
	var color_arr: Array = entry.get("color", [0.5, 0.5, 0.45]) as Array
	var color := Color(
		float(color_arr[0]) if color_arr.size() > 0 else 0.5,
		float(color_arr[1]) if color_arr.size() > 1 else 0.5,
		float(color_arr[2]) if color_arr.size() > 2 else 0.45,
	)
	var kind := str(entry.get("kind", "housing"))
	var cluster := Node3D.new()
	cluster.name = str(entry.get("id", kind))
	cluster.position = Vector3(origin.x, surface_y, origin.y)
	cluster.rotation.y = deg_to_rad(float(entry.get("yaw_degrees", 0.0)))
	parent.add_child(cluster)
	match kind:
		"housing":
			_stamp_land_housing(cluster, size, color)
		"fish_market":
			_stamp_land_market(cluster, size, color)
		"warehouse":
			_stamp_land_warehouse(cluster, size, color)
		"silos":
			_stamp_land_silos(cluster, size, color)
		"farm":
			_stamp_land_farm(cluster, size, color)
		"sawmill":
			_stamp_land_sawmill(cluster, size, color)
		"tree_stand":
			_stamp_land_trees(cluster, size, color)
		"ore_mound":
			_stamp_land_ore_mound(
				cluster,
				size,
				str(entry.get("commodity_id", "iron_ore")),
			)
		"minehead":
			_stamp_land_minehead(cluster, size, color)
		"yard_blocks":
			_stamp_land_yard_blocks(cluster, size, color)
		"tank_farm":
			_stamp_land_tank_farm(cluster, size, color)
		_:
			var box := MeshBuilder.box(size, color.darkened(0.1), 0.9, 0.0)
			box.position = Vector3(0.0, size.y * 0.5, 0.0)
			cluster.add_child(box)
	if show_module_labels:
		_label(
			"LandLabel_%s" % str(entry.get("id", kind)),
			str(entry.get("label", kind)).to_upper(),
			Vector3(origin.x, surface_y + size.y + 8.0, origin.y),
			color.lightened(0.2),
			0.022,
		)


func _stamp_land_housing(root: Node3D, size: Vector3, color: Color) -> void:
	var body := MeshBuilder.box(size * Vector3(1.0, 0.7, 1.0), color.darkened(0.15), 0.95, 0.0)
	body.position = Vector3(0.0, size.y * 0.35, 0.0)
	root.add_child(body)
	var roof := MeshBuilder.box(size * Vector3(1.08, 0.22, 1.08), color.lightened(0.1), 0.9, 0.0)
	roof.position = Vector3(0.0, size.y * 0.75, 0.0)
	root.add_child(roof)


func _stamp_land_market(root: Node3D, size: Vector3, color: Color) -> void:
	var hall := MeshBuilder.box(size, color.darkened(0.2), 0.9, 0.0)
	hall.position = Vector3(0.0, size.y * 0.5, 0.0)
	root.add_child(hall)
	var awning := MeshBuilder.box(Vector3(size.x * 1.15, 0.4, size.z * 0.35), color.lightened(0.15), 0.85, 0.0)
	awning.position = Vector3(0.0, size.y * 0.85, size.z * 0.4)
	root.add_child(awning)


func _stamp_land_warehouse(root: Node3D, size: Vector3, color: Color) -> void:
	var body := MeshBuilder.box(size, color.darkened(0.25), 0.95, 0.0)
	body.position = Vector3(0.0, size.y * 0.5, 0.0)
	root.add_child(body)
	var door := MeshBuilder.box(Vector3(size.x * 0.28, size.y * 0.55, 0.6), Color(0.2, 0.2, 0.22), 0.9, 0.05)
	door.position = Vector3(0.0, size.y * 0.28, size.z * 0.5)
	root.add_child(door)


func _stamp_land_silos(root: Node3D, size: Vector3, color: Color) -> void:
	var radius := minf(size.x, size.z) * 0.22
	for i in range(3):
		var silo := MeshBuilder.cylinder(radius, size.y, color.darkened(0.05), 0.85, 0.05)
		silo.position = Vector3((float(i) - 1.0) * radius * 2.4, size.y * 0.5, 0.0)
		root.add_child(silo)


func _stamp_land_farm(root: Node3D, size: Vector3, color: Color) -> void:
	var field := MeshBuilder.box(Vector3(size.x, 0.35, size.z), color.darkened(0.1), 1.0, 0.0)
	field.position = Vector3(0.0, 0.2, 0.0)
	root.add_child(field)
	var shed := MeshBuilder.box(Vector3(size.x * 0.28, size.y * 1.4, size.z * 0.22), Color(0.45, 0.38, 0.28), 0.9, 0.0)
	shed.position = Vector3(-size.x * 0.28, size.y * 0.7, -size.z * 0.28)
	root.add_child(shed)


func _stamp_land_sawmill(root: Node3D, size: Vector3, color: Color) -> void:
	var mill := MeshBuilder.box(size * Vector3(0.85, 0.8, 0.7), color.darkened(0.2), 0.9, 0.0)
	mill.position = Vector3(0.0, size.y * 0.4, 0.0)
	root.add_child(mill)
	var ramp := MeshBuilder.box(Vector3(size.x * 0.35, 0.5, size.z * 0.9), color.lightened(0.05), 0.95, 0.0)
	ramp.position = Vector3(size.x * 0.35, 0.4, 0.0)
	root.add_child(ramp)


func _stamp_land_trees(root: Node3D, size: Vector3, color: Color) -> void:
	var trunk_c := Color(0.35, 0.22, 0.12)
	var leaf_c := color.darkened(0.05) if color.g > 0.3 else Color(0.22, 0.42, 0.18)
	for i in range(5):
		var ox := (float(i % 3) - 1.0) * size.x * 0.28
		var oz := (float(int(i / 3)) - 0.5) * size.z * 0.35
		var trunk := MeshBuilder.cylinder(0.45, size.y * 0.45, trunk_c, 0.95, 0.0)
		trunk.position = Vector3(ox, size.y * 0.22, oz)
		root.add_child(trunk)
		var canopy := MeshBuilder.sphere(size.y * 0.22, leaf_c, 0.9, 0.0)
		canopy.position = Vector3(ox, size.y * 0.55, oz)
		root.add_child(canopy)


func _stamp_land_ore_mound(root: Node3D, size: Vector3, commodity_id: String) -> void:
	var mound := OreMoundBuilder.build_mound(commodity_id, size, commodity_id.hash())
	root.add_child(mound)


func _stamp_land_minehead(root: Node3D, size: Vector3, color: Color) -> void:
	var headframe := MeshBuilder.box(Vector3(size.x * 0.25, size.y, size.z * 0.25), STEEL, 0.75, 0.2)
	headframe.position = Vector3(0.0, size.y * 0.5, 0.0)
	root.add_child(headframe)
	var shed := MeshBuilder.box(Vector3(size.x * 0.7, size.y * 0.45, size.z * 0.55), color.darkened(0.25), 0.9, 0.0)
	shed.position = Vector3(size.x * 0.2, size.y * 0.22, 0.0)
	root.add_child(shed)
	var tip := MeshBuilder.box(Vector3(size.x * 0.9, 0.5, 0.6), Color(0.55, 0.55, 0.5), 0.8, 0.1)
	tip.position = Vector3(0.0, size.y * 0.95, 0.0)
	root.add_child(tip)


func _stamp_land_yard_blocks(root: Node3D, size: Vector3, color: Color) -> void:
	for row in range(2):
		for col in range(3):
			var h := size.y * (0.55 + float(row) * 0.2)
			var block := MeshBuilder.box(
				Vector3(size.x * 0.22, h, size.z * 0.28),
				color.darkened(0.05 * float(col)),
				0.85,
				0.05,
			)
			block.position = Vector3(
				(float(col) - 1.0) * size.x * 0.28,
				h * 0.5,
				(float(row) - 0.5) * size.z * 0.35,
			)
			root.add_child(block)


func _stamp_land_tank_farm(root: Node3D, size: Vector3, color: Color) -> void:
	var radius := minf(size.x, size.z) * 0.2
	for i in range(4):
		var tank := MeshBuilder.cylinder(radius, size.y * 0.7, color.darkened(0.2), 0.8, 0.15)
		var ox := (float(i % 2) - 0.5) * radius * 2.6
		var oz := (float(int(i / 2)) - 0.5) * radius * 2.6
		tank.position = Vector3(ox, size.y * 0.35, oz)
		root.add_child(tank)


func _stamp_berth_asphalt(parent: Node3D, station: Dictionary, surface_y: float) -> void:
	var origin := _xz2(station.get("origin", [0.0, 0.0]))
	var seaward := _xz2(station.get("direction", [0.0, -1.0])).normalized()
	if seaward.length_squared() < 0.001:
		seaward = PortCoastTracer.PORT_LOCAL_SEAWARD_DIR
	var depth := float(station.get("depth_m", 36.0))
	var length := float(station.get("length_m", 40.0))
	var family := str(station.get("family", "general"))
	var color := CommodityCatalog.terminal_family_color(family).lightened(0.2)
	## Berth deck protrudes seaward of the dock face (outside the apron).
	var pad_center := origin + seaward * (depth * 0.5)
	var station_id := str(station.get("id", "asphalt"))
	var pad_root := Node3D.new()
	pad_root.name = station_id
	pad_root.position = Vector3(pad_center.x, surface_y, pad_center.y)
	_align_node_seaward(pad_root, seaward)
	parent.add_child(pad_root)
	var commodities := PackedStringArray()
	var cid := str(station.get("commodity_id", ""))
	if not cid.is_empty():
		commodities.append(cid)
	var slot := _make_berth_slot(
		pad_root,
		station_id,
		family,
		commodities,
		length,
		depth,
		1.0,
		Vector3(0.0, 0.0, 1.0),
	)
	## Pad hangs below the apron crown so the walking surface stays flush.
	var pad_center_y := ASPHALT_PAD_TOP_LOCAL_Y - ASPHALT_PAD_H * 0.5
	var pad := MeshBuilder.box(
		Vector3(length, ASPHALT_PAD_H, depth),
		color.darkened(0.25),
		0.9,
		0.0,
	)
	pad.position = Vector3(0.0, pad_center_y, 0.0)
	pad_root.add_child(pad)
	_add_deck_walk_collision(
		pad_root,
		"PadWalkCollision",
		Vector2(length, depth),
		ASPHALT_PAD_TOP_LOCAL_Y,
	)
	## Bollards on the seaward face — player/ship mooring interaction.
	_stamp_asphalt_bollards(pad_root, slot, length, depth)
	## Thin seam where the pad meets the harbour face (local −Z).
	var junction_h := 0.08
	var junction := MeshBuilder.box(
		Vector3(length * 0.98, junction_h, 1.4),
		FOUNDATION_PAVEMENT_COLOR.lightened(0.08),
		1.0,
		0.0,
	)
	junction.name = "ApronJunction"
	junction.position = Vector3(
		0.0,
		ASPHALT_PAD_TOP_LOCAL_Y + junction_h * 0.5,
		-depth * 0.5 + 0.7,
	)
	pad_root.add_child(junction)
	var road_w := clampf(length * 0.18, 6.0, 12.0)
	var road_h := 0.08
	var road := MeshBuilder.box(
		Vector3(road_w, road_h, depth * 0.82),
		Color(0.07, 0.07, 0.08),
		1.0,
		0.0,
	)
	road.name = "Road"
	## Sit just above pad crown to avoid coplanar flicker.
	road.position = Vector3(0.0, ASPHALT_PAD_TOP_LOCAL_Y + road_h * 0.5 + 0.01, 0.0)
	pad_root.add_child(road)
	var kind := str(station.get("equipment_kind", ""))
	if not kind.is_empty():
		var gear_root := Node3D.new()
		gear_root.name = "Equipment"
		## Keep gear near the apron junction, not the outer tip.
		gear_root.position = Vector3(length * 0.28, 0.0, -depth * 0.22)
		pad_root.add_child(gear_root)
		_stamp_equipment_kind(
			gear_root,
			kind,
			Vector3(length * 0.35, 1.0, depth * 0.35),
			family,
			1.0,
			slot.berth_id if slot != null else "",
			0,
		)
	if show_module_labels:
		var role := str(station.get("role", "")).to_upper()
		_label(
			"AsphaltLabel_%s" % str(station.get("id", "asphalt")),
			"%s\n%s · apron  %.0f×%.0f m" % [
				CommodityCatalog.commodity_display(str(station.get("commodity_id", ""))).to_upper(),
				role,
				length,
				depth,
			],
			Vector3(origin.x, surface_y + 10.0, origin.y) + Vector3(seaward.x, 0.0, seaward.y) * (depth * 0.45),
			color,
			0.026,
		)


func _stamp_equipment_kind(
		root: Node3D,
		kind: String,
		footprint: Vector3,
		family: String,
		berth_sign: float = 1.0,
		berth_id: String = "",
		tool_index: int = 0,
) -> void:
	match kind:
		"equip_sts_gantry":
			_stamp_sts_gantry_at(root, footprint)
		"equip_provision_crane":
			_stamp_provision_crane_at(root, footprint, berth_sign, berth_id, tool_index)
		"equip_grab_unloader":
			_stamp_bulk_crane_at(root, footprint, berth_sign, berth_id, tool_index)
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


## Live general-cargo yard on a dedicated quay finger deck (pier crown Y).
## Yards start empty. FreightService stages accepted contract cargo here; a
## future warehouse/forklift system can replace that immediate staging step.
func _stamp_general_cargo_quay_yard(
		lane: Node3D,
		lane_x: float,
		lane_w: float,
		zone_len: float,
		zone_mid_z: float,
		slot: QuayBerthSlot,
		zone_index: int,
		role: String = "",
) -> void:
	var yard_w := clampf(lane_w * 0.88, 8.0, 28.0)
	var yard_len := clampf(zone_len * 0.88, 12.0, 80.0)
	## Snap length to whole container footprints so slots pack cleanly.
	var fp := ContainerUnit.DEFAULT_FOOTPRINT
	var cell := 1.0
	yard_w = maxf(float(fp.x) * cell, floor(yard_w / (float(fp.x) * cell)) * float(fp.x) * cell)
	yard_len = maxf(float(fp.y) * cell, floor(yard_len / (float(fp.y) * cell)) * float(fp.y) * cell)

	var yard_pad := CargoSlotPadComponent.new()
	yard_pad.name = "GeneralCargoYard_%d" % zone_index
	yard_pad.is_quay_yard_pad = true
	yard_pad.affects_boat_cargo_mass = false
	yard_pad.deck_width_m = yard_w
	yard_pad.deck_length_m = yard_len
	yard_pad.cell_size_m = cell
	yard_pad.container_footprint = fp
	yard_pad.pad_color = Color(0.28, 0.22, 0.18, 0.92)
	yard_pad.slot_line_color = Color(0.82, 0.55, 0.32, 0.55)
	## Sit on the pier crown — same reference as bulk mounds / quay decks.
	yard_pad.position = Vector3(lane_x, QUAY_DECK_TOP_LOCAL_Y + 0.06, zone_mid_z)
	lane.add_child(yard_pad)

	var drop := Node3D.new()
	drop.name = "YardDrop"
	drop.add_to_group("container_yard_drop")
	yard_pad.add_child(drop)

	if slot != null and _harbour != null:
		## One long berth may contain several independent crane bays. Preserve
		## the exact yard ↔ crane pairing instead of collapsing to berth only.
		yard_pad.set_meta(
			"equipment_id",
			HarbourController.make_equip_id(
				slot.berth_id,
				"equip_provision_crane",
				zone_index,
			),
		)
		_harbour.register_yard(yard_pad, slot.berth_id)


func _stamp_provision_crane_at(
		root: Node3D,
		_footprint: Vector3,
		_berth_sign: float,
		berth_id: String = "",
		tool_index: int = 0,
) -> void:
	var equip_id := ""
	if not berth_id.is_empty():
		equip_id = HarbourController.make_equip_id(berth_id, "equip_provision_crane", tool_index)
	var harbour := _harbour
	var lod = PORT_STRUCTURE_LOD.new()
	lod.name = "ProvisionCraneLod"
	root.add_child(lod)
	lod.setup(
		IMPOSTOR_SERVICE.crane_key("provision"),
		func() -> Node3D:
			return _build_provision_crane_full(berth_id, equip_id, harbour),
		PORT_STRUCTURE_LOD.PROFILE_TALL,
		func() -> void:
			if harbour != null and not equip_id.is_empty():
				harbour.unregister_equipment(equip_id),
	)


func _build_provision_crane_full(
		berth_id: String,
		equip_id: String,
		harbour: HarbourController,
) -> Node3D:
	var holder := Node3D.new()
	holder.name = "ProvisionCraneFull"
	var crane := PROVISION_CRANE_SCRIPT.new() as ProvisionCrane
	crane.name = "ProvisionCrane"
	crane.rotation_degrees.y = -90.0
	var auto := PROVISION_CRANE_AUTO_SCRIPT.new() as ProvisionCraneAutoOperator
	auto.name = "AutoOperator"
	crane.add_child(auto)
	holder.add_child(crane)
	if berth_id.is_empty() or harbour == null or equip_id.is_empty():
		return holder
	var job := PROVISION_EQUIP_JOB_SCRIPT.new() as ProvisionCraneEquipmentJob
	job.setup(equip_id, "equip_provision_crane", berth_id)
	job.bind_crane(crane)
	crane.add_child(job)
	harbour.register_equipment(job, berth_id)
	var operator := CRANE_OPERATOR_SCRIPT.new() as CraneOperatorNpc
	operator.name = "CraneOperator"
	operator.position = Vector3(-2.2, 0.0, 3.5)
	operator.configure(harbour, berth_id, equip_id)
	holder.add_child(operator)
	return holder


func _stamp_bulk_crane_at(
		root: Node3D,
		_footprint: Vector3,
		_berth_sign: float,
		berth_id: String = "",
		tool_index: int = 0,
) -> void:
	var equip_id := ""
	if not berth_id.is_empty():
		equip_id = HarbourController.make_equip_id(berth_id, "equip_grab_unloader", tool_index)
	var harbour := _harbour
	var lod = PORT_STRUCTURE_LOD.new()
	lod.name = "BulkCraneLod"
	root.add_child(lod)
	lod.setup(
		IMPOSTOR_SERVICE.crane_key("bulk"),
		func() -> Node3D:
			return _build_bulk_crane_full(berth_id, equip_id, harbour),
		PORT_STRUCTURE_LOD.PROFILE_TALL,
		func() -> void:
			if harbour != null and not equip_id.is_empty():
				harbour.unregister_equipment(equip_id),
	)


func _build_bulk_crane_full(
		berth_id: String,
		equip_id: String,
		harbour: HarbourController,
) -> Node3D:
	var holder := Node3D.new()
	holder.name = "BulkCraneFull"
	var crane := BULK_CRANE_SCRIPT.new() as BulkCrane
	crane.name = "BulkCrane"
	## Authored boom is −Z; berth face is local ±X (equip_root yaw handles sign).
	crane.rotation_degrees.y = -90.0
	crane.boom_angle_deg = 38.0
	crane.hoist_length_m = 10.0
	crane.bucket_open = 0.0
	crane.set_bucket_jaws_target(0.0)
	var auto := BULK_CRANE_AUTO_SCRIPT.new() as BulkCraneAutoOperator
	auto.name = "AutoOperator"
	crane.add_child(auto)
	holder.add_child(crane)
	if berth_id.is_empty() or harbour == null or equip_id.is_empty():
		return holder
	var job := BULK_EQUIP_JOB_SCRIPT.new() as BulkCraneEquipmentJob
	job.setup(equip_id, "equip_grab_unloader", berth_id)
	job.bind_crane(crane)
	crane.add_child(job)
	harbour.register_equipment(job, berth_id)
	var operator := CRANE_OPERATOR_SCRIPT.new() as CraneOperatorNpc
	operator.name = "CraneOperator"
	operator.position = Vector3(-2.2, 0.0, 3.5)
	operator.configure(harbour, berth_id, equip_id)
	holder.add_child(operator)
	return holder


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
	## Yaw only — never rebuild a full basis. Some headings used to flip local +Y
	## (east-facing pads), which broke CharacterBody floor normals so players
	## fell through asphalt/quay decks.
	var dir := Vector2(seaward.x, seaward.y)
	if dir.length_squared() < 0.001:
		dir = Vector2(0.0, -1.0)
	else:
		dir = dir.normalized()
	node.rotation = Vector3(0.0, atan2(dir.x, dir.y), 0.0)


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


func _add_trimesh_collision(mesh_instance: MeshInstance3D, body_name: String) -> void:
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	var shape := mesh_instance.mesh.create_trimesh_shape()
	if shape == null:
		return
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.name = "Shape"
	col.shape = shape
	body.add_child(col)
	mesh_instance.add_child(body)


func _add_deck_walk_collision(
		parent: Node3D,
		body_name: String,
		footprint: Vector2,
		deck_top_local_y: float,
) -> void:
	if parent == null:
		return
	var walk_h := DECK_WALK_THICKNESS_M
	_add_box_collision(
		parent,
		body_name,
		Vector3(footprint.x, walk_h, footprint.y),
		Vector3(0.0, deck_top_local_y - walk_h * 0.5, 0.0),
	)


func _add_box_collision(
		parent: Node3D,
		body_name: String,
		size: Vector3,
		local_position: Vector3,
		yaw_radians: float = 0.0,
) -> void:
	if parent == null:
		return
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = local_position
	body.rotation.y = yaw_radians
	var col := CollisionShape3D.new()
	col.name = "Shape"
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)


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
	WorldGizmos.register(label, WorldGizmos.LAYER_PORT_LAYOUT)


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
