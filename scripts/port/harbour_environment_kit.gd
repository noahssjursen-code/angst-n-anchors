@tool
class_name HarbourEnvironmentKit
extends RefCounted

const ROOT := "res://resources/models/parts/harbour_kit/"
static var _scenes: Dictionary = {}
static var _paving: ShaderMaterial
static var _paint: ShaderMaterial
static var _paint_widths: Dictionary = {}

static func paving() -> ShaderMaterial:
	if _paving == null:
		_paving = ShaderMaterial.new()
		_paving.shader = preload("res://resources/shaders/harbour_pavement.gdshader")
		_paving.set_shader_parameter("colour_map", load(SurfaceMaterialLibrary.DIRECTORY + "Asphalt033/Asphalt033_1K-PNG_Color.png"))
		_paving.set_shader_parameter("normal_map", load(SurfaceMaterialLibrary.DIRECTORY + "Asphalt033/Asphalt033_1K-PNG_NormalGL.png"))
		_paving.set_shader_parameter("roughness_map", load(SurfaceMaterialLibrary.DIRECTORY + "Asphalt033/Asphalt033_1K-PNG_Roughness.png"))
	_paving.set_shader_parameter("use_scan", SurfaceMaterialLibrary.enabled)
	return _paving

static func model(parent: Node3D, id: String, position: Vector3, yaw: float = 0.0, use_lod: bool = true) -> Node3D:
	if not _scenes.has(id): _scenes[id] = load(id if id.begins_with("res://") else ROOT + id + ".glb")
	var node := (_scenes[id] as PackedScene).instantiate() as Node3D
	parent.add_child(node)
	node.position = position
	node.rotation.y = yaw
	if use_lod:
		PortModelLod.attach(node, id if id.begins_with("res://") else ROOT + id + ".glb")
	SurfaceMaterialLibrary.apply(node, id.get_file().get_basename())
	if id == "quay_light" and not Engine.is_editor_hint():
		var lamp := preload("res://scripts/port/harbour_area_light.gd").new()
		node.add_child(lamp)
		lamp.position = Vector3(0,7.4,-1.2)
	return node

static func repeated(parent: Node3D, id: String, poses: Array[Transform3D]) -> void:
	if poses.is_empty(): return
	var prototype := model(parent, id, Vector3.ZERO, 0.0, false)
	var meshes := prototype.find_children("*", "MeshInstance3D", true, false)
	for raw in meshes:
		var source := raw as MeshInstance3D
		var batch := MultiMeshInstance3D.new()
		batch.name = id.get_file().get_basename() + "_batch"
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		# MultiMesh does not inherit a prototype's surface overrides. Duplicate
		# the small mesh resource once per batch; all instances still share it.
		multi.mesh = SurfaceMaterialLibrary.finished_mesh(source)
		multi.instance_count = poses.size()
		var local := prototype.global_transform.affine_inverse() * source.global_transform
		for i in poses.size(): multi.set_instance_transform(i, poses[i] * local)
		batch.multimesh = multi
		for parameter in ["finish_x", "finish_y", "finish_z"]:
			batch.set_instance_shader_parameter(parameter, source.get_instance_shader_parameter(parameter))
		batch.visibility_range_end = 900.0
		parent.add_child(batch)
	prototype.free()

static func solid(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	body.position = center

static func quay(parent: Node3D, length: float, width: float, top: float) -> void:
	var root := Node3D.new()
	root.name = "WaterfrontKit"
	parent.add_child(root)
	root.position.y = top+.012
	var coping: Array[Transform3D] = []
	var fenders: Array[Transform3D] = []
	for side in [-1.0, 1.0]:
		var yaw: float = -side * PI*.5
		var count := maxi(1, int(ceil(length/2.0)))
		var pitch := length/count
		for i in count:
			coping.append(Transform3D(Basis(Vector3.UP,yaw).scaled_local(Vector3(pitch/2.0,1,1)),Vector3(side*(width*.5+.015),0,-length*.5+pitch*(i+.5))))
		var fender_count := maxi(1,int(length/12.0))
		for i in fender_count:
			var z := -length*.5+(i+.5)*length/fender_count
			fenders.append(Transform3D(Basis(Vector3.UP,yaw),Vector3(side*width*.5,0,z)))
		# Ladders between fenders; no handrail across a mooring point.
		var ladder_z := -length*.5+length/fender_count
		model(root,"quay_ladder",Vector3(side*width*.5,0,ladder_z),yaw)
		for i in range(1,maxi(2,int(length/32.0))):
			var z: float = -length*.5+i*32.0
			if z > length*.5-8: continue
			var pole := model(root,"quay_light",Vector3(side*(width*.5-2.0),0,z),-yaw)
			solid(pole,Vector3(0,3.75,0),Vector3(.24,7.5,.24))
	# Close the seaward end, leaving the landward road connection open.
	var count := maxi(1,int(ceil(width/2.0)))
	for i in count:
		coping.append(Transform3D(Basis(Vector3.UP,PI).scaled_local(Vector3(width/count/2.0,1,1)),Vector3(-width*.5+(i+.5)*width/count,0,length*.5+.015)))
	repeated(root,"quay_coping_2m",coping)
	repeated(root,"arch_fender",fenders)

static func line(parent: Node3D, a: Vector3, b: Vector3, width: float = .12) -> void:
	if a.distance_to(b) < .01: return
	if _paint == null:
		_paint = ShaderMaterial.new()
		_paint.shader = preload("res://resources/shaders/harbour_road_paint.gdshader")
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(width,a.distance_to(b))
	var node := MeshInstance3D.new()
	node.mesh = mesh
	if not _paint_widths.has(width):
		var paint := _paint.duplicate() as ShaderMaterial
		paint.set_shader_parameter("paint_width",width)
		_paint_widths[width]=paint
	node.material_override = _paint_widths[width]
	parent.add_child(node)
	node.position = (a+b)*.5
	node.rotation.y = atan2(b.x-a.x,b.z-a.z)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func lane(parent: Node3D, a: Vector3, b: Vector3, width: float) -> void:
	var direction := (b-a).normalized()
	var lateral := direction.cross(Vector3.UP)*width*.5
	line(parent,a+lateral,b+lateral)
	line(parent,a-lateral,b-lateral)
	var distance := a.distance_to(b)
	for i in range(int(distance/6.0)):
		var start := a+direction*(i*6.0+1)
		line(parent,start,start+direction*minf(2.5,distance-i*6.0-1))

static func warehouse(parent: Node3D, size_x: float, size_z: float) -> bool:
	# Leave a loading forecourt; never scale doors to fit arbitrary plot sizes.
	if size_x < 16 or size_z < 22: return false
	var root := model(parent,"warehouse_12x18",Vector3(0,0,1),PI)
	root.set_meta("warehouse_shell",true)
	solid(root,Vector3(0,2.7,0),Vector3(12,5.4,18))
	for x in [-5.5,5.5]:
		line(parent,Vector3(x,.009,-8.5),Vector3(x,.009,-minf(size_z*.46,18)))
	return true
