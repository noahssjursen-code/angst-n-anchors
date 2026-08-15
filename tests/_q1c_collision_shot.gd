extends Node3D

## SCRATCH CAPTURE (leading underscore — not a gate unit, the gate must not
## discover it). Owner question 1c: what a stamped building COLLIDES as, drawn
## against what it DRAWS.
##
##   Q1C_VARIANT=after xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_q1c_collision_shot.tscn
##
## The rig is `_q1_cell_shot.gd`'s, unchanged where it can be: shadows ON, a pale
## sky so the silhouette has a boundary, a 1.8 m figure in the SAME PLANE as the
## wall it measures, and an ORTHOGRAPHIC lens on every frame — a perspective
## frame of this exact warehouse was once misread by 2.4x (REALITY.md §8).
##
## THE CAMERA IS HARDCODED AND IDENTICAL IN BOTH VARIANTS. `before` is shot by
## running this same file against a `git archive HEAD` copy of the tree, so the
## only thing that differs between the two sets of frames is the code under test.
##
## WHAT IS DRAWN. Pale grey is the building's own meshes, exactly as
## `BuildingCache.instance` stamps them. Translucent red is every shape on every
## `PhysicsBody3D` under that same stamp, drawn at the transform and size
## `PhysicsServer3D` reports for it — not at the transform the `CollisionShape3D`
## node claims, because the node is the input and the server is the subject
## (REALITY.md §3).

const OUT_DIR := "res://screenshots/decisions"

const ELEV_ORTHO_SIZE := 15.0
const ELEV_CENTRE := Vector3(0.0, 4.2, 0.0)
const ELEV_DISTANCE := 80.0
const QUARTER_ORTHO_SIZE := 27.0
const DOOR_ORTHO_SIZE := 6.0
## World x of the left-hand cargo door, read off the blueprint at run time.
const DOOR_CENTRE := Vector3(-5.0, 2.0, 0.0)

var _camera: Camera3D
var _figure: Node3D
var _building: Node3D
var _collider_root: Node3D
var _variant := "after"


func _ready() -> void:
	_variant = OS.get_environment("Q1C_VARIANT")
	if _variant.is_empty():
		_variant = "after"

	var layout := BuildingBlueprintCatalog.by_id("warehouse")
	if layout == null:
		printerr("[q1c] warehouse blueprint did not load")
		get_tree().quit(1)
		return

	BuildingCache.clear()
	_building = BuildingCache.instance(layout, true)
	add_child(_building)
	## Two physics frames so every body is in the space and every `BrickDoor`
	## has built its leaf collider before the census is taken.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var ground := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(64.0, 0.6, 64.0)
	ground.mesh = slab
	ground.position = Vector3(0.0, -0.3, 0.0)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.44, 0.45, 0.42)
	ground.material_override = ground_mat
	add_child(ground)

	_hide_autoload_ui()
	_light()
	_pale(_building)

	_collider_root = Node3D.new()
	_collider_root.name = "ColliderOverlay"
	add_child(_collider_root)
	var census := _draw_colliders(_building, _collider_root)
	print("[q1c] variant=%s: %d shapes on %d bodies, union pos %s size %s"
		% [_variant, int(census["shapes"]), int(census["bodies"]),
			str((census["union"] as AABB).position), str((census["union"] as AABB).size)])
	var drawn := _bounds(_building)
	print("[q1c] variant=%s: DRAWN pos %s size %s (y %.3f..%.3f)"
		% [_variant, str(drawn.position), str(drawn.size),
			drawn.position.y, drawn.position.y + drawn.size.y])
	var union := census["union"] as AABB
	print("[q1c] variant=%s: COLLISION y %.3f..%.3f — floor is %.3f m off the drawn floor"
		% [_variant, union.position.y, union.position.y + union.size.y,
			union.position.y - drawn.position.y])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_figure = _make_figure()
	_figure.position = Vector3(-6.9, 0.0, -7.6)
	add_child(_figure)

	await _shot("elevation", Camera3D.PROJECTION_ORTHOGONAL, ELEV_ORTHO_SIZE,
		ELEV_CENTRE + Vector3(0.0, 0.0, -ELEV_DISTANCE), ELEV_CENTRE)

	## Raking: a wall with holes in it reads far better off square.
	var dir := Vector3(sin(deg_to_rad(-35.0)) * cos(deg_to_rad(16.0)),
		sin(deg_to_rad(16.0)), cos(deg_to_rad(-35.0)) * cos(deg_to_rad(16.0)))
	_figure.position = Vector3(-9.0, 0.0, 7.6)
	await _shot("quarter", Camera3D.PROJECTION_ORTHOGONAL, QUARTER_ORTHO_SIZE,
		ELEV_CENTRE + dir * 80.0, ELEV_CENTRE)

	## The doorway, close, with the figure standing in it — the frame that
	## answers "can he walk through" without anyone typing a number.
	_figure.position = Vector3(DOOR_CENTRE.x, 0.0, -7.6)
	await _shot("door", Camera3D.PROJECTION_ORTHOGONAL, DOOR_ORTHO_SIZE,
		DOOR_CENTRE + Vector3(0.0, 0.0, -ELEV_DISTANCE), DOOR_CENTRE)

	## And the collision ON ITS OWN. With the building hidden there is nothing
	## for a missing collider to hide behind.
	_pale_hide(_building)
	await _shot("collidersonly", Camera3D.PROJECTION_ORTHOGONAL, QUARTER_ORTHO_SIZE,
		ELEV_CENTRE + dir * 80.0, ELEV_CENTRE)

	get_tree().quit(0)


## Every shape on every `PhysicsBody3D` under `root`, as the SERVER holds it.
func _draw_colliders(root: Node, overlay: Node3D) -> Dictionary:
	var bodies: Array = []
	_collision_objects(root, bodies)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.13, 0.08, 0.34)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var shapes := 0
	var solid_bodies := 0
	var union := AABB()
	var first := true
	for body_variant in bodies:
		var body := body_variant as CollisionObject3D
		if not (body is PhysicsBody3D):
			## An Area3D is a trigger, not a wall.
			continue
		solid_bodies += 1
		var rid := body.get_rid()
		for i in PhysicsServer3D.body_get_shape_count(rid):
			var data: Variant = PhysicsServer3D.shape_get_data(PhysicsServer3D.body_get_shape(rid, i))
			var extent := Vector3.ONE
			if data is Vector3:
				extent = (data as Vector3) * 2.0
			elif data is Dictionary and (data as Dictionary).has("points"):
				var pts: PackedVector3Array = (data as Dictionary)["points"]
				var box := AABB(pts[0], Vector3.ZERO)
				for p in pts:
					box = box.expand(p)
				extent = box.size
			var xf: Transform3D = body.global_transform \
				* PhysicsServer3D.body_get_shape_transform(rid, i)
			var mi := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = extent
			mi.mesh = mesh
			mi.material_override = mat
			mi.transform = xf
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			overlay.add_child(mi)
			var world := AABB(xf.origin - extent * 0.5, extent)
			union = world if first else union.merge(world)
			first = false
			shapes += 1
	return {"shapes": shapes, "bodies": solid_bodies, "union": union}


func _collision_objects(node: Node, out: Array) -> void:
	if node is CollisionObject3D:
		out.append(node)
	for child in node.get_children():
		_collision_objects(child, out)


## The building goes pale and flat so the red reads on top of it. This is the
## RIG, not the subject — the colour of a warehouse is not what is being asked.
func _pale(node: Node) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.80, 0.79, 0.75)
	mat.roughness = 0.95
	for mi in _meshes(node):
		mi.material_override = mat


func _pale_hide(node: Node) -> void:
	for mi in _meshes(node):
		mi.visible = false


func _shot(tag: String, projection: int, size: float, at: Vector3, look: Vector3) -> void:
	_camera.projection = projection as Camera3D.ProjectionType
	_camera.size = size
	_camera.position = at
	_camera.look_at(look, Vector3.UP)
	var image := await _frame()
	var path := "%s/q1c_building_collision__%s__%s.png" % [OUT_DIR, _variant, tag]
	print("[q1c] %s (%d)" % [path, image.save_png(path)])


func _frame() -> Image:
	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _hide_autoload_ui() -> void:
	for child in get_tree().root.get_children():
		if child == self:
			continue
		_hide_canvas_items(child)


func _hide_canvas_items(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
		return
	if node is CanvasItem:
		(node as CanvasItem).visible = false
		return
	for child in node.get_children():
		_hide_canvas_items(child)


func _make_figure() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = 1.8
	capsule.radius = 0.28
	body.mesh = capsule
	body.position = Vector3(0.0, 0.9, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.32, 0.85)
	body.material_override = mat
	root.add_child(body)
	return root


func _light() -> void:
	RenderingServer.directional_shadow_atlas_set_size(1024, true)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 220.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.4
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, -125.0, 0.0)
	fill.light_energy = 0.35
	add_child(fill)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.74, 0.80, 0.85)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.70, 0.78)
	environment.ambient_light_energy = 0.60
	env.environment = environment
	add_child(env)
	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)


func _bounds(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(node):
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		out = aabb if first else out.merge(aabb)
		first = false
	return out


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out
