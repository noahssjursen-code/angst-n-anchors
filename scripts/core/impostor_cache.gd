class_name ImpostorCache
extends RefCounted

## Bake six orthographic face textures from a live Node3D once, then stamp a
## cheap textured AABB box at the same local pose. Runtime ImageTextures only —
## no imported atlas files.

const DEFAULT_RESOLUTION := 256
const IMPOSTOR_INSTANCE := preload("res://scripts/core/impostor_instance.gd")

static var _entries: Dictionary = {}  ## key -> {size, center, textures}


static func clear() -> void:
	_entries.clear()


static func has_key(key: String) -> bool:
	return _entries.has(key)


static func has_geometry(key: String) -> bool:
	return _entries.has(key) and _entries[key].has("mesh")


static func entry_count() -> int:
	return _entries.size()


## Capture one orthographic view per AABB axis face of `source`.
## Faces are derived from bounds only — no object-specific front/back roles.
## `host` must be inside the scene tree (used for frame waits / viewport parent).
static func bake_from_node(
		host: Node,
		key: String,
		source: Node3D,
		resolution: int = DEFAULT_RESOLUTION,
) -> void:
	if host == null or not host.is_inside_tree() or source == null:
		push_warning("ImpostorCache.bake_from_node: host/source not ready")
		return
	if key.is_empty():
		return

	var source_aabb := compute_local_aabb(source)
	if source_aabb.size.length() < 0.001:
		push_warning("ImpostorCache: empty AABB for %s" % key)
		return

	var vp := SubViewport.new()
	vp.name = "ImpostorBake"
	vp.own_world_3d = true
	# Clear alpha so empty AABB face space is see-through (lattice cranes, etc.).
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.disable_3d = false
	# Bake albedo only; the runtime proxy receives current sun/ambient light.
	vp.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	vp.size = Vector2i(resolution, resolution)
	host.add_child(vp)

	var world_root := Node3D.new()
	world_root.name = "BakeRoot"
	vp.add_child(world_root)

	var clone := source.duplicate() as Node3D
	clone.name = "Source"
	# Prevent ProvisionCrane/_ready etc. from rebuilding while we capture.
	_strip_scripts_recursive(clone)
	_strip_physics_recursive(clone)
	_strip_lights_and_cameras(clone)
	world_root.add_child(clone)
	# Center geometry at origin so every face camera shares a simple framing.
	clone.position = -source_aabb.get_center()

	var light := DirectionalLight3D.new()
	light.name = "BakeLight"
	light.light_energy = 1.25
	light.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	world_root.add_child(light)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.68)
	env_node.environment = env
	world_root.add_child(env_node)

	var cam := Camera3D.new()
	cam.name = "BakeCam"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.current = true
	cam.near = 0.05
	cam.far = 10000.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	world_root.add_child(cam)

	await host.get_tree().process_frame
	await host.get_tree().process_frame

	var size := source_aabb.size
	var center := source_aabb.get_center()
	var textures: Dictionary = {}
	for face in IMPOSTOR_INSTANCE.aabb_faces(size):
		var dir: Vector3 = face["normal"]
		var up: Vector3 = face["up"]
		var face_w: float = maxf(float(face["face_w"]), 0.05)
		var face_h: float = maxf(float(face["face_h"]), 0.05)
		var res_h := maxi(resolution, 32)
		var res_w := clampi(int(round(float(res_h) * (face_w / face_h))), 32, 1024)
		vp.size = Vector2i(res_w, res_h)
		cam.size = face_h
		var dist := maxf(size.length(), maxf(face_w, face_h)) * 1.25
		cam.position = dir * dist
		cam.look_at(Vector3.ZERO, up)
		await host.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		if img == null:
			continue
		img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		textures[str(face["key"])] = ImageTexture.create_from_image(img)

	vp.queue_free()
	_entries[key] = {
		"size": size,
		"center": center,
		"textures": textures,
	}


## Store an already cheap visual mesh without baking six image panels.
static func register_geometry(key: String, mesh: ArrayMesh) -> void:
	if key.is_empty() or mesh==null: return
	_entries[key]={"mesh":mesh}


## Stamp the footprint box: quads on each AABB face, same local pose as source.
static func instance(key: String, show_ghost: bool = false) -> Node3D:
	var root = IMPOSTOR_INSTANCE.new()
	root.show_footprint_ghost = show_ghost
	if not _entries.has(key):
		return root as Node3D
	var entry: Dictionary = _entries[key]
	if entry.has("mesh"):
		var visual:=MeshInstance3D.new()
		visual.mesh=entry.mesh
		visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(visual)
		if show_ghost:
			var bounds: AABB = visual.mesh.get_aabb()
			root._add_footprint_ghost(bounds.size,bounds.get_center())
		return root
	root.setup(
		entry.get("size", Vector3.ONE) as Vector3,
		entry.get("center", Vector3.ZERO) as Vector3,
		entry.get("textures", {}) as Dictionary,
	)
	return root as Node3D


static func compute_local_aabb(root: Node3D) -> AABB:
	return _accumulate_aabb_result(root, Transform3D.IDENTITY)


static func _accumulate_aabb_result(node: Node, parent_xform: Transform3D) -> AABB:
	var merged := AABB()
	var found := false
	if node is Node3D:
		var xform := parent_xform * (node as Node3D).transform
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh != null and mi.visible:
				var local := _transform_aabb(xform, mi.get_aabb())
				if not found:
					merged = local
					found = true
				else:
					merged = merged.merge(local)
		for child in node.get_children():
			var child_aabb := _accumulate_aabb_result(child, xform)
			if child_aabb.size.length() > 0.0:
				if not found:
					merged = child_aabb
					found = true
				else:
					merged = merged.merge(child_aabb)
	return merged if found else AABB()


static func _transform_aabb(xform: Transform3D, aabb: AABB) -> AABB:
	var out := AABB(xform * aabb.position, Vector3.ZERO)
	for i in range(8):
		out = out.expand(xform * aabb.get_endpoint(i))
	return out


static func _strip_scripts_recursive(node: Node) -> void:
	node.set_script(null)
	for child in node.get_children():
		_strip_scripts_recursive(child)


static func _strip_physics_recursive(node: Node) -> void:
	var children := node.get_children()
	for child in children:
		if child is StaticBody3D or child is RigidBody3D or child is CollisionObject3D:
			child.free()
		elif child is CollisionShape3D:
			child.free()
		else:
			_strip_physics_recursive(child)


static func _strip_lights_and_cameras(node: Node) -> void:
	var children := node.get_children()
	for child in children:
		if child is Camera3D or child is Light3D or child is WorldEnvironment:
			child.free()
		else:
			_strip_lights_and_cameras(child)
