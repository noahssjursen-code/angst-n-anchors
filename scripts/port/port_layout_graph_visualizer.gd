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
	var land_edge := plan.get("land_edge", []) as Array
	var water_edge := plan.get("water_edge", []) as Array
	if land_edge.size() < 2 or land_edge.size() != water_edge.size():
		return
	var surface_y := float(plan.get("surface_y_m", PortCoastTracer.FOUNDATION_SURFACE_Y_M))
	var material := MeshBuilder.make_material(Color(0.33, 0.35, 0.37), 0.96, 0.0, true)
	material.render_priority = 2
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	for index in range(land_edge.size() - 1):
		var land_a := _foundation_point(land_edge[index], surface_y)
		var land_b := _foundation_point(land_edge[index + 1], surface_y)
		var water_a := _foundation_point(water_edge[index], surface_y)
		var water_b := _foundation_point(water_edge[index + 1], surface_y)
		surface.add_vertex(land_a)
		surface.add_vertex(water_b)
		surface.add_vertex(water_a)
		surface.add_vertex(land_a)
		surface.add_vertex(land_b)
		surface.add_vertex(water_b)
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "TerrainFollowingFoundation"
	mesh.mesh = surface.commit()
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.extra_cull_margin = 8.0
	mesh.position.y = 0.04
	add_child(mesh)


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


func _stamp_fish_derrick(placed: PortPlacedModule, definition: PortModuleDefinition) -> void:
	var root := _equip_root(placed, "FishDerrick")
	var accent := Color(0.45, 0.78, 0.88)
	_pad(root, definition.footprint_m, STEEL.darkened(0.1))
	var mast_h := 12.0
	var mast := MeshBuilder.cylinder(0.35, mast_h, accent, 0.65, 0.25)
	mast.position.y = mast_h * 0.5
	root.add_child(mast)
	var boom_side := _jib_side(placed)
	var boom := MeshBuilder.box(Vector3(14.0, 0.5, 0.5), accent.lightened(0.1), 0.7, 0.15)
	boom.position = Vector3(boom_side * 6.0, mast_h - 1.5, 0.0)
	boom.rotation_degrees.z = boom_side * -18.0
	root.add_child(boom)
	_equip_label(placed, "FISH DERRICK", mast_h + 1.2, accent)


func _stamp_sts_gantry(placed: PortPlacedModule, definition: PortModuleDefinition) -> void:
	var root := _equip_root(placed, "StsGantry")
	var accent := Color(0.25, 0.55, 0.85)
	_pad(root, definition.footprint_m, STEEL.darkened(0.2))
	var size := _size_class()
	var height := clampf(22.0 + float(size) * 3.0, 22.0, 42.0)
	var span := clampf(28.0 + float(size) * 4.0, 28.0, 56.0)
	var side := _jib_side(placed)
	## Portal legs + crossbeam reaching over the berth (ship-to-shore silhouette).
	var leg_l := MeshBuilder.box(Vector3(1.4, height, 1.4), accent, 0.7, 0.2)
	leg_l.position = Vector3(-4.0, height * 0.5, 0.0)
	root.add_child(leg_l)
	var leg_r := MeshBuilder.box(Vector3(1.4, height, 1.4), accent, 0.7, 0.2)
	leg_r.position = Vector3(4.0, height * 0.5, 0.0)
	root.add_child(leg_r)
	var beam := MeshBuilder.box(Vector3(span, 1.2, 1.6), accent.lightened(0.08), 0.65, 0.25)
	beam.position = Vector3(side * span * 0.28, height - 0.8, 0.0)
	root.add_child(beam)
	var trolley := MeshBuilder.box(Vector3(3.0, 1.5, 2.4), STEEL.lightened(0.1), 0.6, 0.3)
	trolley.position = Vector3(side * span * 0.45, height - 2.2, 0.0)
	root.add_child(trolley)
	var spreader := MeshBuilder.box(Vector3(6.0, 0.6, 2.0), Color(0.85, 0.55, 0.12), 0.7, 0.1)
	spreader.position = Vector3(side * span * 0.45, height * 0.45, 0.0)
	root.add_child(spreader)
	_equip_label(placed, "STS GANTRY", height + 1.5, accent)


func _stamp_grab_unloader(placed: PortPlacedModule, definition: PortModuleDefinition) -> void:
	var root := _equip_root(placed, "GrabUnloader")
	var accent := Color(0.78, 0.48, 0.22)
	_pad(root, definition.footprint_m, STEEL.darkened(0.15))
	var mast_h := clampf(18.0 + float(_size_class()) * 3.0, 18.0, 36.0)
	var tower := MeshBuilder.box(Vector3(3.2, mast_h, 3.2), accent, 0.8, 0.15)
	tower.position.y = mast_h * 0.5
	root.add_child(tower)
	var side := _jib_side(placed)
	var boom := MeshBuilder.box(Vector3(22.0, 1.4, 1.8), accent.lightened(0.05), 0.75, 0.2)
	boom.position = Vector3(side * 10.0, mast_h - 2.0, 0.0)
	root.add_child(boom)
	var grab := MeshBuilder.box(Vector3(3.5, 2.2, 3.5), STEEL.darkened(0.25), 0.85, 0.4)
	grab.position = Vector3(side * 18.0, mast_h * 0.4, 0.0)
	root.add_child(grab)
	_equip_label(placed, "GRAB UNLOADER", mast_h + 1.4, accent)


func _stamp_grain_elevator(placed: PortPlacedModule, definition: PortModuleDefinition) -> void:
	var root := _equip_root(placed, "GrainElevator")
	var accent := Color(0.88, 0.78, 0.28)
	_pad(root, definition.footprint_m, STEEL.darkened(0.1))
	var tower_h := clampf(20.0 + float(_size_class()) * 3.5, 20.0, 40.0)
	var tower := MeshBuilder.box(Vector3(4.0, tower_h, 4.0), accent, 0.75, 0.05)
	tower.position.y = tower_h * 0.5
	root.add_child(tower)
	var silo := MeshBuilder.cylinder(2.4, tower_h * 0.7, accent.darkened(0.12), 0.7, 0.0)
	silo.position = Vector3(-5.0, tower_h * 0.35, 0.0)
	root.add_child(silo)
	var side := _jib_side(placed)
	var spout := MeshBuilder.box(Vector3(16.0, 0.9, 0.9), STEEL.lightened(0.15), 0.6, 0.35)
	spout.position = Vector3(side * 7.0, tower_h * 0.7, 0.0)
	spout.rotation_degrees.z = side * -12.0
	root.add_child(spout)
	_equip_label(placed, "GRAIN ELEVATOR", tower_h + 1.4, accent)


func _stamp_loading_arm(placed: PortPlacedModule, definition: PortModuleDefinition) -> void:
	var root := _equip_root(placed, "LoadingArm")
	var accent := Color(0.55, 0.62, 0.72)
	_pad(root, definition.footprint_m, STEEL.darkened(0.12))
	var pedestal_h := 4.5
	var pedestal := MeshBuilder.cylinder(0.45, pedestal_h, accent, 0.7, 0.25)
	pedestal.position.y = pedestal_h * 0.5
	root.add_child(pedestal)
	var side := _jib_side(placed)
	var knuckle := MeshBuilder.box(Vector3(1.2, 1.0, 1.2), accent.lightened(0.05), 0.65, 0.2)
	knuckle.position = Vector3(0.0, pedestal_h, 0.0)
	root.add_child(knuckle)
	var pipe := MeshBuilder.cylinder(0.22, 10.0, Color(0.72, 0.74, 0.78), 0.55, 0.45)
	pipe.position = Vector3(side * 4.5, pedestal_h - 1.0, -2.0)
	pipe.rotation_degrees.z = side * 28.0
	pipe.rotation_degrees.x = -18.0
	root.add_child(pipe)
	var hose := MeshBuilder.cylinder(0.14, 6.0, Color(0.35, 0.38, 0.42), 0.5, 0.35)
	hose.position = Vector3(side * 8.0, pedestal_h - 3.5, -5.0)
	hose.rotation_degrees.x = -55.0
	root.add_child(hose)
	_equip_label(placed, "LOADING ARM", pedestal_h + 2.0, accent)


func _stamp_fuel_tank(placed: PortPlacedModule, definition: PortModuleDefinition) -> void:
	var root := _equip_root(placed, "Fuel")
	var fp := definition.footprint_m
	var pad := MeshBuilder.box(Vector3(fp.x, 0.4, fp.z), Color(0.25, 0.25, 0.26), 0.9, 0.05)
	pad.position.y = 0.2
	root.add_child(pad)
	var radius := minf(fp.x, fp.z) * 0.35
	var tank := MeshBuilder.cylinder(radius, maxf(fp.y * 4.0, 6.0), Color(0.75, 0.16, 0.12), 0.55, 0.35)
	tank.position.y = maxf(fp.y * 2.0, 3.2)
	root.add_child(tank)
	_equip_label(placed, "FUEL", tank.position.y + radius + 1.2, Color(1.0, 0.55, 0.45))


func _should_stamp_open_slot(slot: Dictionary) -> bool:
	var parent := _graph.modules.get(str(slot.get("parent_instance_id", ""))) as PortPlacedModule
	var parent_definition := _graph.module_definition(parent.module_id) if parent != null else null
	if parent_definition != null and parent_definition.kind == "coast":
		return false
	var slot_key := str(slot.get("slot_id", ""))
	var parent_slot := slot_key.split(":")[-1] if slot_key.contains(":") else slot_key
	if PortSizing.is_inland_side_slot(parent_slot):
		return false
	## Unfilled pier roots on the asphalt apron read as "half built" in inspect scenes.
	if str(slot.get("type", "")) == "harbour_branch" \
			and str(slot.get("parent_instance_id", "")) == "root":
		return false
	if str(slot.get("type", "")) in ["quay_branch", "coast_chain"]:
		return false
	return true


func _stamp_open_slot(slot: Dictionary) -> void:
	var slot_type := str(slot.get("type", "slot"))
	var size := _slot_marker_size(slot_type)
	var position := slot.get("position_m", Vector3.ZERO) as Vector3
	_box(
		"Open_%s" % str(slot.get("slot_id", "")).replace(":", "_"),
		size,
		position + Vector3(0.0, size.y * 0.5 + 0.08, 0.0),
		float(slot.get("yaw_degrees", 0.0)),
		SLOT_COLORS.get(slot_type, Color(0.7, 0.3, 0.7, 0.58)) as Color,
		true,
	)
	_label(
		"OpenLabel_%s" % str(slot.get("slot_id", "")).replace(":", "_"),
		"OPEN: %s" % slot_type.to_upper().replace("_", " "),
		position + Vector3(0.0, size.y + 0.9, 0.0),
		Color(0.96, 0.84, 1.0),
		0.023,
	)


func _equip_root(placed: PortPlacedModule, prefix: String) -> Node3D:
	var root := Node3D.new()
	root.name = "%s_%s" % [prefix, placed.instance_id]
	root.position = placed.position_m
	root.rotation_degrees.y = placed.yaw_degrees
	add_child(root)
	return root


func _pad(root: Node3D, fp: Vector3, color: Color) -> void:
	var pad := MeshBuilder.box(
		Vector3(maxf(fp.x, 8.0), 1.0, maxf(fp.z, 8.0)),
		color,
		0.9,
		0.15,
	)
	pad.position.y = 0.5
	root.add_child(pad)


func _jib_side(placed: PortPlacedModule) -> float:
	return 1.0 if int(placed.assignment.get("berth_index", 0)) % 2 == 0 else -1.0


func _size_class() -> int:
	return _graph.size_class() if _graph != null else 1


func _equip_label(placed: PortPlacedModule, text: String, height: float, color: Color) -> void:
	if not show_module_labels:
		return
	_label(
		"Label_%s" % placed.instance_id,
		text,
		placed.position_m + Vector3(0.0, height, 0.0),
		color.lightened(0.25),
		0.026,
	)


func _box(
		node_name: String,
		size: Vector3,
		position: Vector3,
		yaw_degrees: float,
		color: Color,
		transparent: bool,
) -> MeshInstance3D:
	var out := MeshInstance3D.new()
	out.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	out.mesh = mesh
	out.material_override = _material_for(color, transparent)
	out.position = position
	out.rotation_degrees.y = yaw_degrees
	add_child(out)
	return out


func _material_for(color: Color, transparent: bool) -> StandardMaterial3D:
	var key := "%s|%d" % [color.to_html(true), 1 if transparent else 0]
	var cached: StandardMaterial3D = _material_cache.get(key) as StandardMaterial3D
	if cached != null:
		return cached
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	material.metallic = 0.02
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = 0.12
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material_cache[key] = material
	return material


func _label(
		node_name: String,
		text: String,
		position: Vector3,
		color: Color,
		pixel_size: float,
) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.pixel_size = pixel_size
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = position
	add_child(label)


static func _module_color(
		definition: PortModuleDefinition,
		assignment: Dictionary,
) -> Color:
	var commodity := str(assignment.get("commodity_id", ""))
	if not commodity.is_empty():
		var color := CommodityCatalog.commodity_color(commodity)
		return color.darkened(0.18) if str(assignment.get("role", "")) == "import" \
				else color.lightened(0.08)
	var family := str(assignment.get("family", ""))
	if definition.kind == "quay" and not family.is_empty():
		return CommodityCatalog.terminal_family_color(family)
	return definition.color


static func _slot_marker_size(slot_type: String) -> Vector3:
	match slot_type:
		"harbour_branch", "quay_extension":
			return Vector3(7.0, 0.35, 5.0)
		"quay_branch":
			return Vector3(5.5, 0.32, 4.5)
		"cargo_facility":
			return Vector3(6.0, 0.3, 5.0)
		"equipment_pad", "service_pad":
			return Vector3(4.5, 0.3, 4.0)
		"road_extension", "road_branch":
			return Vector3(4.0, 0.25, 4.0)
		_:
			return Vector3(4.0, 0.3, 4.0)
