class_name ImpostorInstance
extends Node3D

## Object-footprint impostor: AABB-sized box, one ortho texture per axis face.
## All six faces stay visible — no view culling.

@export var show_footprint_ghost := false


## Six AABB sides derived only from `size`. Texture keys: px/nx/py/ny/pz/nz.
static func aabb_faces(size: Vector3) -> Array[Dictionary]:
	var half := size * 0.5
	return [
		_face("px", Vector3(1, 0, 0), Vector3.UP, Vector2(size.z, size.y), Vector3(half.x, 0, 0), Vector3(0, -PI * 0.5, 0)),
		_face("nx", Vector3(-1, 0, 0), Vector3.UP, Vector2(size.z, size.y), Vector3(-half.x, 0, 0), Vector3(0, PI * 0.5, 0)),
		_face("py", Vector3(0, 1, 0), Vector3(0, 0, -1), Vector2(size.x, size.z), Vector3(0, half.y, 0), Vector3(-PI * 0.5, 0, 0)),
		_face("ny", Vector3(0, -1, 0), Vector3(0, 0, 1), Vector2(size.x, size.z), Vector3(0, -half.y, 0), Vector3(PI * 0.5, 0, 0)),
		_face("pz", Vector3(0, 0, 1), Vector3.UP, Vector2(size.x, size.y), Vector3(0, 0, half.z), Vector3.ZERO),
		_face("nz", Vector3(0, 0, -1), Vector3.UP, Vector2(size.x, size.y), Vector3(0, 0, -half.z), Vector3(0, PI, 0)),
	]


static func _face(
		key: String,
		normal: Vector3,
		up: Vector3,
		quad_size: Vector2,
		offset: Vector3,
		rotation: Vector3,
) -> Dictionary:
	return {
		"key": key,
		"normal": normal,
		"up": up,
		"quad_size": quad_size,
		"offset": offset,
		"rotation": rotation,
		"face_w": quad_size.x,
		"face_h": quad_size.y,
	}


func setup(size: Vector3, center: Vector3, textures: Dictionary) -> void:
	name = "Impostor"
	for face in aabb_faces(size):
		_add_face(
			textures.get(str(face["key"])) as Texture2D,
			face["quad_size"] as Vector2,
			center + (face["offset"] as Vector3),
			face["rotation"] as Vector3,
		)
	if show_footprint_ghost:
		_add_footprint_ghost(size, center)


func _add_face(
		texture: Texture2D,
		face_size: Vector2,
		position: Vector3,
		rotation: Vector3,
) -> void:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(maxf(face_size.x, 0.01), maxf(face_size.y, 0.01))
	mi.mesh = quad
	mi.position = position
	mi.rotation = rotation
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Scissor keeps six-face sorting cheap while punching out clear bake pixels.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.08
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color.WHITE
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if texture != null:
		mat.albedo_texture = texture
	else:
		mat.albedo_color = Color(0.35, 0.35, 0.38)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mi.material_override = mat
	add_child(mi)


func _add_footprint_ghost(size: Vector3, center: Vector3) -> void:
	var ghost := MeshInstance3D.new()
	ghost.name = "FootprintGhost"
	var box := BoxMesh.new()
	box.size = size
	ghost.mesh = box
	ghost.position = center
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.15, 0.95, 0.35, 0.07)
	ghost.material_override = mat
	add_child(ghost)
