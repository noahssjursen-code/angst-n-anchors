extends Node3D

## One builder placement owns the existing harbour equipment and its cargo pad.
## No economy/harbour registration: this is the isolated construction showcase.
var spec: Dictionary
var preview := false
var valid := true
var ready_for_inspection := false
var passive_services := false
var crane: Node3D
var cargo_pad: Node3D
var _preview_material: StandardMaterial3D

func _ready() -> void:
	if preview:
		_preview_material = StandardMaterial3D.new()
		_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_preview_material.albedo_color = Color(.28,1,.57,.32) if valid else Color(1,.22,.16,.38)
		_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if str(spec.visual)=="bollard":
		var post := MooringPost.new()
		post.service_discovery_enabled=not passive_services
		post.name = "MooringBollard"
		add_child(post)
		_prepare_tree(self)
		ready_for_inspection = true
		return
	var crane_at := Vector3(float(spec.crane_offset_m[0]),0,float(spec.crane_offset_m[1]))
	var pad_at := Vector3(float(spec.pad_offset_m[0]),0,float(spec.pad_offset_m[1]))
	var pad_size := Vector2(float(spec.pad_size_m[0]),float(spec.pad_size_m[1]))
	# Plain asphalt working area, level with the shared deck; foundations below.
	var pad_yaw := deg_to_rad(float(spec.get("pad_yaw_degrees",0)))
	var yard := Node3D.new()
	yard.name = "CargoArea"
	yard.position = pad_at
	yard.rotation.y = pad_yaw
	add_child(yard)
	_box(yard, Vector3(pad_size.x,.025,pad_size.y), Vector3.UP*.0125, HarbourEnvironmentKit.paving())
	if str(spec.visual)=="container_crane":
		var pad := preload("res://scripts/port/port_cargo_yard.gd").container_pad(pad_size,not passive_services)
		pad.name = "CargoPad"
		pad.position = Vector3.UP*.035
		cargo_pad = pad
		yard.add_child(pad)
		# Slot occupancy is data only. The yard has an unmarked asphalt surface.
		crane = ProvisionCrane.new()
	else:
		cargo_pad = Node3D.new()
		cargo_pad.name = "CargoPad"
		cargo_pad.set_meta("bulk_pad_size_m", pad_size)
		yard.add_child(cargo_pad)
		var bulk := BulkCrane.new()
		bulk.show_operator = false
		bulk.simulate_bulk_material = false
		bulk.boom_angle_deg = 38.0
		crane = bulk
	crane.name = "Crane"
	crane.position = crane_at
	crane.model_loaded.connect(_on_crane_loaded)
	add_child(crane)
	# Keep the real colliders active; disabling the whole branch removes them.
	crane.set_process(false)
	crane.set_physics_process(false)
	cargo_pad.set_meta("paired_crane", crane)
	crane.set_meta("paired_cargo_pad", cargo_pad)
	# Clicking any part of the bay selects the same placement.
	_pick_surface(Vector3(float(spec.cells[0])*2,.04,float(spec.cells[1])*2))
	if preview: _orientation_marker()
	_prepare_tree(self)

func _on_crane_loaded(_path: String) -> void:
	_prepare_tree(self)
	ready_for_inspection = true

func _prepare_tree(node: Node) -> void:
	if node is CollisionObject3D:
		node.collision_layer = 0 if preview else 1
		node.collision_mask = 0
		node.set_meta("plot_build_visual",self)
	if preview:
		for group in node.get_groups(): node.remove_from_group(group)
		if node is GeometryInstance3D:
			node.material_override = _preview_material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children(): _prepare_tree(child)

func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material, collision := false) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	if collision:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var volume := BoxShape3D.new()
		volume.size = size
		shape.shape = volume
		body.position = at
		body.add_child(shape)
		parent.add_child(body)

func _pick_surface(size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = .025
	body.add_child(shape)
	add_child(body)

func _orientation_marker() -> void:
	var lines := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(.3,1,.6) if valid else Color(1,.25,.18)
	material.no_depth_test = true
	lines.surface_begin(Mesh.PRIMITIVE_LINES,material)
	var half := Vector2(float(spec.cells[0]),float(spec.cells[1]))
	var corners := [Vector3(-half.x,.08,-half.y),Vector3(half.x,.08,-half.y),Vector3(half.x,.08,half.y),Vector3(-half.x,.08,half.y)]
	for i in 4:
		lines.surface_add_vertex(corners[i]); lines.surface_add_vertex(corners[(i+1)%4])
	for segment in [[Vector3(0,.08,-half.y+4),Vector3(0,.08,-half.y-3)],
		[Vector3(-2,.08,-half.y-1),Vector3(0,.08,-half.y-3)],
		[Vector3(2,.08,-half.y-1),Vector3(0,.08,-half.y-3)]]:
		lines.surface_add_vertex(segment[0]); lines.surface_add_vertex(segment[1])
	var center := Vector3(float(spec.crane_offset_m[0]),.08,float(spec.crane_offset_m[1]))
	var reach := float(spec.get("reach_m",0))
	for i in 96:
		var a := TAU*float(i)/96.0
		var b := TAU*float(i+1)/96.0
		lines.surface_add_vertex(center+Vector3(cos(a),0,sin(a))*reach)
		lines.surface_add_vertex(center+Vector3(cos(b),0,sin(b))*reach)
	lines.surface_end()
	var marker := MeshInstance3D.new()
	marker.name = "WaterSideArrow"
	marker.mesh = lines
	add_child(marker)
