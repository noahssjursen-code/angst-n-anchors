class_name ForestTreeMesh
extends RefCounted
## Shared Blender foliage geometry and two-triangle distant silhouettes.
## Alpha scissor keeps depth writes; all foliage is lit by the live environment.
const SPECIES := ["pine", "birch", "spruce", "juniper"]
const CANOPY_HEIGHT := [7.0, 6.0, 8.0, 1.5]
const TREE_HEIGHT := [11.0, 10.0, 14.0, 2.6]
const FOLIAGE := preload("res://scripts/world/forest_foliage.gdshader")
static var _meshes: Dictionary = {}
static var _requested := false
static func request_assets() -> void:
	if _requested: return
	_requested = true
	for species in SPECIES:
		for suffix in ["_near", "_mid"]:
			if _meshes.has(species+suffix): continue
			ResourceLoader.load_threaded_request("res://resources/models/scenery/coastal_vegetation/"+species+suffix+".glb")

static func assets_ready() -> bool:
	if not _requested: return true
	for species in SPECIES:
		for suffix in ["_near", "_mid"]:
			if _meshes.has(species+suffix): continue
			var status := ResourceLoader.load_threaded_get_status("res://resources/models/scenery/coastal_vegetation/"+species+suffix+".glb")
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return false
	# Consume every request, including species absent from the current coast.
	# Prepare one mesh per frame rather than retaining unused loader requests
	# or assembling all eight imported scenes during a single patch build.
	for i in SPECIES.size():
		for near in [true, false]:
			var key: String = SPECIES[i]+("_near" if near else "_mid")
			if not _meshes.has(key):
				species_mesh(i, near)
				return false
	return true

static func finish_pending_requests() -> void:
	if not _requested: return
	# World teardown can happen before the first camera frame. Godot's loader
	# requests must still be consumed so unused imported scenes aren't retained.
	for species in SPECIES:
		for suffix in ["_near", "_mid"]:
			if not _meshes.has(species+suffix):
				ResourceLoader.load_threaded_get("res://resources/models/scenery/coastal_vegetation/"+species+suffix+".glb")
	_requested = false

static func species_mesh(species: int, near: bool) -> ArrayMesh:
	var key: String = SPECIES[clampi(species,0,3)]+("_near" if near else "_mid")
	if not _meshes.has(key):
		var path := "res://resources/models/scenery/coastal_vegetation/"+key+".glb"
		var scene := (ResourceLoader.load_threaded_get(path) if _requested else load(path)) as PackedScene
		var root := scene.instantiate()
		var mesh := root.find_child("*",true,false) as MeshInstance3D
		if mesh == null:
			mesh = root.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D
		var asset := mesh.mesh as ArrayMesh
		if not near:
			# The shader rotates the card toward the camera. Its CPU bounds
			# must cover every yaw, including when the stored plane is edge-on.
			var bounds := asset.get_aabb()
			var radius := bounds.size.x * 0.5
			asset.custom_aabb = AABB(Vector3(-radius, bounds.position.y, -radius),
				Vector3(radius * 2.0, bounds.size.y, radius * 2.0))
		for surface in asset.get_surface_count():
			var mat := asset.surface_get_material(surface) as StandardMaterial3D
			if mat != null and mat.albedo_texture != null:
				var foliage := ShaderMaterial.new()
				foliage.shader = FOLIAGE
				foliage.set_shader_parameter("foliage_texture", mat.albedo_texture)
				foliage.set_shader_parameter("canopy_height", CANOPY_HEIGHT[species])
				foliage.set_shader_parameter("tree_height", TREE_HEIGHT[species])
				foliage.set_shader_parameter("distant", not near)
				asset.surface_set_material(surface, foliage)
		_meshes[key] = asset
		root.free()
	return _meshes[key] as ArrayMesh
static func near_mesh() -> ArrayMesh: return species_mesh(2,true)
static func mid_mesh() -> ArrayMesh: return species_mesh(2,false)
static func build_near_spruce() -> ArrayMesh: return near_mesh()
static func build_mid_card() -> ArrayMesh: return mid_mesh()
static func near_material() -> Material: return near_mesh().surface_get_material(0)
static func mid_material() -> Material: return mid_mesh().surface_get_material(0)
