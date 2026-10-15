class_name CustomHarbourAssetLibrary
extends RefCounted

## Presentation of authored harbour pieces. The manifest contains real dimensions;
## placing a visual does not create stock, production, a berth or ownership.
const MANIFEST := "res://resources/data/ports/custom_harbour_assets.json"
static var _definitions: Dictionary = {}

static func definitions() -> Dictionary:
	if _definitions.is_empty():
		var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		for row in document.get("assets", []):
			_definitions[str(row.id)] = row
	return _definitions

static func specification(id: String) -> Dictionary:
	return definitions().get(id, {}).duplicate(true)

static func instantiate(id: String, collision: bool = true, runtime_lighting: bool = true) -> Node3D:
	if id == "fish_landing_plant":
		var plant := preload("res://scripts/port/building/custom_port_fish_landing.gd").new()
		plant.collision_enabled = collision
		return plant
	var spec := specification(id)
	if spec.is_empty():
		push_error("Unknown harbour asset: " + id)
		return null
	var packed := load(str(spec.model_path)) as PackedScene
	if packed == null:
		return null
	var root := Node3D.new()
	root.name = id.to_pascal_case()
	root.set_meta("harbour_asset_id", id)
	var model := packed.instantiate() as Node3D
	model.name = "Model"
	root.add_child(model)
	SurfaceMaterialLibrary.apply(model, "custom_harbour")
	_finish_softwood(model)
	if spec.has("foundation"):
		# Diagonal and square pads are the same concrete, including grain scale.
		# A different imported finish made every angled tile look like a patch.
		for mesh in SurfaceMaterialLibrary.meshes(model):
			for surface in mesh.mesh.get_surface_count():
				var original: Material=mesh.mesh.surface_get_material(surface)
				if original!=null and original.resource_name.get_slice(".",0)=="Concrete":
					mesh.set_surface_override_material(surface,SurfaceMaterialLibrary.material("concrete_cast",Color("9eaba7"),"Concrete"))
	if id == "quay_light" and runtime_lighting:
		HarbourEnvironmentKit.attach_area_light(model)
	# Imported mesh LODs handle the near reductions. Small fittings do not keep
	# drawing fine chains/fasteners across a whole harbour, while their collision
	# and authoritative placement survive independently of visual distance.
	var visibility_distance := 0.0
	if spec.category == "Quay fittings":
		visibility_distance = 900.0 if id == "quay_light" else 220.0
	elif spec.category == "Cargo details":
		visibility_distance = 360.0
	if visibility_distance > 0.0:
		for mesh in SurfaceMaterialLibrary.meshes(model):
			mesh.visibility_range_end = visibility_distance
			mesh.visibility_range_end_margin = 16.0
	if collision:
		if spec.has("foundation"):
			var foundation_body := StaticBody3D.new()
			foundation_body.name = "FoundationBody"
			foundation_body.collision_layer = 1
			foundation_body.collision_mask = 0
			foundation_body.set_meta("harbour_asset_root", root)
			root.add_child(foundation_body)
			var foundation_shape := CollisionShape3D.new()
			foundation_shape.name = "FoundationShape"
			foundation_shape.shape = ConvexPolygonShape3D.new()
			foundation_body.add_child(foundation_shape)
		for index in spec.get("colliders", []).size():
			var bounds: Dictionary = spec.colliders[index]
			var parent: Node3D = root
			if bounds.has("moving_node"):
				parent = model.find_child(str(bounds.moving_node), true, false) as Node3D
				if parent == null:
					push_error("Missing authored collider pivot for " + id)
					continue
			var body := StaticBody3D.new()
			body.name = "Body" + str(index)
			body.collision_layer = 1
			body.collision_mask = 0
			body.set_meta("harbour_asset_root", root)
			if bounds.has("moving_node"):
				body.set_meta("harbour_door", true)
			parent.add_child(body)
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = _vector(bounds.size_m)
			shape.shape = box
			shape.position = _vector(bounds.position_m)
			if bounds.has("rotation_degrees"): shape.rotation_degrees = _vector(bounds.rotation_degrees)
			body.add_child(shape)
	if spec.has("foundation"):
		set_foundation_depth(root,float(spec.foundation.default_depth_m))
	return root

static func set_foundation_depth(root: Node3D, depth_m: float) -> bool:
	var spec := specification(str(root.get_meta("harbour_asset_id","")))
	if not spec.has("foundation") or not is_finite(depth_m):
		return false
	var support := root.find_child(str(spec.foundation.support_node),true,false) as Node3D
	if support == null:return false
	var cap := float(spec.foundation.cap_thickness_m)
	var depth := maxf(cap+.05,depth_m)
	support.scale.y = (depth-cap)/float(spec.foundation.authored_support_depth_m)
	root.set_meta("foundation_depth_m",depth)
	var model := root.get_node("Model") as Node3D
	# Concrete retains metre-scale grain when a shallow cap grows deep supports.
	SurfaceMaterialLibrary.map_frame(model)
	var collision := root.get_node_or_null("FoundationBody/FoundationShape") as CollisionShape3D
	if collision != null:
		var points := PackedVector3Array()
		for y in [0.0,-depth]:
			for point in spec.footprint_polygon_m:
				points.append(Vector3(float(point[0]),y,float(point[1])))
		var shape := collision.shape as ConvexPolygonShape3D
		shape.points = points
	return true

static func set_door_open(root: Node3D, open: bool) -> bool:
	var spec := specification(str(root.get_meta("harbour_asset_id", "")))
	if not spec.has("door"):
		return false
	var pivot := root.find_child(str(spec.door.pivot_node), true, false) as Node3D
	if pivot == null:
		return false
	pivot.rotation.y = deg_to_rad(float(spec.door.open_degrees)) if open else 0.0
	root.set_meta("door_open", open)
	return true

static func set_wall_colour(root: Node3D, colour: Color) -> void:
	for mesh in SurfaceMaterialLibrary.meshes(root):
		for surface in mesh.mesh.get_surface_count():
			var original: Material = mesh.mesh.surface_get_material(surface)
			if original != null and original.resource_name.get_slice(".", 0) == "Office cladding":
				mesh.set_surface_override_material(surface, SurfaceMaterialLibrary.material("painted_timber", colour, "Office cladding"))

static func _finish_softwood(root: Node3D) -> void:
	# Sawn harbour timber and vertical red boarding use the approved softwood
	# grain. The old pallet finish is a coarse, horizontal hardwood veneer.
	for mesh in SurfaceMaterialLibrary.meshes(root):
		for surface in mesh.mesh.get_surface_count():
			var original: Material = mesh.mesh.surface_get_material(surface)
			if original == null:continue
			var material_name := original.resource_name.get_slice(".",0)
			if material_name == "Pallet timber":
				mesh.set_surface_override_material(surface,SurfaceMaterialLibrary.material("timber_clean",Color(.92,.87,.77),material_name))
			elif material_name == "Office cladding":
				mesh.set_surface_override_material(surface,SurfaceMaterialLibrary.material("painted_timber",SurfaceMaterialLibrary.colour_of(original),material_name))

static func _vector(raw: Array) -> Vector3:
	return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
