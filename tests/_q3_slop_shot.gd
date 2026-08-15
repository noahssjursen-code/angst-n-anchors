extends Node3D

## SCRATCH CAPTURE (leading underscore — not a gate unit). Owner decision on
## `StructureBaker.PLATE_COLLIDER_SLOP`, where 0.08 ("the knee") is on record and
## was not taken.
##
##   Q3_LABEL=slop0.05-today xvfb-run -a --server-args="-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_q3_slop_shot.tscn
##
## This is a COLLISION question, so a beauty shot is the wrong picture. The frame
## is the thing you WALK ON drawn against the thing you SEE: the plate as
## `StructureBaker.bake` draws it, plus every box `collect_colliders` emits for
## it, in translucent red, in the same world position, through one orthographic
## camera looking straight down the plate's own run so the rake is edge-on.
##
## Subject: item 100 of `probe_plate_deckhouse.json` — shipped data, not authored
## here. Its own `__is` calls it "lower tier, raked front — top overhangs 0.45 m
## forward of its foot", and it is tapered in plan as well, so it is warped in
## both parameters, which is the case the dicing exists for.
##
## ONLY the subject plate is baked. Baking the whole deckhouse for "context" put
## the port side plate between the lens and the subject and hid the very thing
## the frame exists to show — the instrument obscuring the subject, again
## (REALITY.md §8).

const OUT_DIR := "res://screenshots/decisions"
const FIXTURE := "res://resources/data/structures/probe_plate_deckhouse.json"
const SUBJECT_ID := 100

## Fixed for every value of the constant.
const EDGE_ORTHO := 3.4
const FACE_ORTHO := 3.6
## The top edge, where the rake makes the boxes stand furthest proud.
const DETAIL_ORTHO := 1.30

var _camera: Camera3D
var _label := "slop"


func _ready() -> void:
	_label = OS.get_environment("Q3_LABEL")
	if _label.is_empty():
		_label = "slop%.2f" % StructureBaker.PLATE_COLLIDER_SLOP

	var doc := JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)) as Dictionary
	if doc == null:
		printerr("[q3] fixture did not parse")
		get_tree().quit(1)
		return
	var plan := StructurePlan.from_dict(doc)

	## The subject alone, in its own plan, so `collect_colliders` returns exactly
	## its boxes through the PRODUCTION path rather than my re-deriving them
	## (REALITY.md §3b — a second derivation is how the drawn thing and the
	## collided thing drift apart in the first place).
	var subject_doc := doc.duplicate(true)
	var kept: Array = []
	for raw in subject_doc.get("items", []) as Array:
		if int((raw as Dictionary).get("id", -1)) == SUBJECT_ID:
			kept.append(raw)
	subject_doc["items"] = kept
	subject_doc["walls"] = []
	subject_doc["decks"] = []
	subject_doc["stairs"] = []
	subject_doc["edges"] = []
	var subject_plan := StructurePlan.from_dict(subject_doc)
	if kept.is_empty():
		printerr("[q3] item %d not found in the fixture" % SUBJECT_ID)
		get_tree().quit(1)
		return

	var props := StructurePlan.item_props(kept[0] as Dictionary)
	var at := _at_of(kept[0] as Dictionary)
	var corners := StructureBaker.plate_corners(props)
	var thickness := float(props.get("thickness", 0.05))
	var world_corners := PackedVector3Array()
	for c in corners:
		world_corners.append(c + at)

	var boxes := StructureBaker.collect_colliders(subject_plan)
	print("[q3] label=%s  PLATE_COLLIDER_SLOP=%.4f  boxes for item %d = %d"
		% [_label, StructureBaker.PLATE_COLLIDER_SLOP, SUBJECT_ID, boxes.size()])
	print("[q3] %s: subject is %s" % [_label, str(props.get("__is", ""))])
	_report_proud(world_corners, thickness, boxes)

	var baked := StructureBaker.bake(subject_plan)
	add_child(baked)
	var overlay := Node3D.new()
	overlay.name = "Colliders"
	add_child(overlay)
	for raw in boxes:
		overlay.add_child(_collider_ghost(raw as Dictionary))

	_light()
	_hide_autoload_ui()

	## Edge-on: look along the plate's own u run (its width), so the 2.4 m rise
	## and the 0.45 m overhang are a straight diagonal and any box standing proud
	## of it is a red step sticking out into the air.
	var centre := (world_corners[0] + world_corners[1] + world_corners[2] + world_corners[3]) * 0.25
	var u_run := ((world_corners[1] + world_corners[2]) - (world_corners[0] + world_corners[3])) * 0.5
	var along := Vector3(u_run.x, 0.0, u_run.z).normalized()
	var normal := StructureBaker.plate_normal(world_corners)
	var facing := Vector3(normal.x, 0.0, normal.z).normalized()
	print("[q3] %s: plate centre %s, u run %s, normal %s"
		% [_label, str(centre), str(along), str(normal)])

	## Foot on the plate's own base plane (y = 0), not on the plate's centre
	## height — the first placement floated it 1.2 m and it read as a 3 m man.
	var figure_at := centre - facing * 1.6 - along * 2.1
	add_child(_figure(Vector3(figure_at.x, 0.0, figure_at.z)))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await _shoot("edge", EDGE_ORTHO, centre, along * 40.0)
	## Dropped half a metre below the very top edge so the plate fills the frame
	## instead of hanging from the middle of it. Same point at every value.
	var top := (world_corners[2] + world_corners[3]) * 0.5 - Vector3(0.0, 0.5, 0.0)
	await _shoot("edgedetail", DETAIL_ORTHO, top, along * 40.0)
	await _shoot("face", FACE_ORTHO, centre, -facing * 40.0 + Vector3(0.0, 6.0, 0.0))
	get_tree().quit(0)


func _at_of(item: Dictionary) -> Vector3:
	var raw: Variant = item.get("at", [0.0, 0.0, 0.0])
	if raw is Array:
		var a: Array = raw
		if a.size() >= 3:
			return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


## The number the picture is showing, so the frame is not the only evidence.
## Worst distance from any collider corner to the drawn slab, measured by
## nearest point on the plate's own bilinear patch thickened by its thickness —
## the same instrument `_plate_phantom_probe` uses, so the numbers compare.
func _report_proud(quad: PackedVector3Array, thickness: float, boxes: Array) -> void:
	var worst := 0.0
	for raw in boxes:
		var box: Dictionary = raw
		var basis := Basis(Vector3.UP, deg_to_rad(float(box.get("yaw_deg", 0.0))))
		var half := (box["size"] as Vector3) * 0.5
		var centre := box["center"] as Vector3
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var corner := centre + basis * Vector3(
						half.x * float(sx), half.y * float(sy), half.z * float(sz))
					worst = maxf(worst, _phantom(quad, thickness, corner))
	print("[q3] %s: worst PHANTOM (collider corner to drawn plate) = %.4f m" % [_label, worst])


func _phantom(quad: PackedVector3Array, thickness: float, p: Vector3) -> float:
	var u := 0.5
	var v := 0.5
	for _pass in 8:
		u = clampf(_project(StructureBaker.plate_point(quad, 0.0, v),
			StructureBaker.plate_point(quad, 1.0, v), p), 0.0, 1.0)
		v = clampf(_project(StructureBaker.plate_point(quad, u, 0.0),
			StructureBaker.plate_point(quad, u, 1.0), p), 0.0, 1.0)
	var near := StructureBaker.plate_point(quad, u, v)
	var n := StructureBaker.plate_normal(quad)
	var d := p - near
	var along := d.dot(n)
	var across := (d - n * along).length()
	var out := maxf(absf(along) - thickness * 0.5, 0.0)
	return sqrt(out * out + across * across)


func _project(a: Vector3, b: Vector3, p: Vector3) -> float:
	var run := b - a
	var len2 := run.length_squared()
	return 0.5 if len2 < 1e-12 else (p - a).dot(run) / len2


## One collider box, drawn where the physics body puts it: translucent red skin
## plus opaque red edge rails, because a translucent box alone loses its
## silhouette against a white plate and the silhouette is the whole point.
func _collider_ghost(box: Dictionary) -> Node3D:
	var root := Node3D.new()
	var size := box["size"] as Vector3
	var skin := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	skin.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.13, 0.09, 0.13)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	skin.material_override = mat
	root.add_child(skin)

	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.85, 0.05, 0.03)
	rail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var t := 0.006
	for sy in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var rail := MeshInstance3D.new()
			var rail_mesh := BoxMesh.new()
			rail_mesh.size = Vector3(size.x, t, t)
			rail.mesh = rail_mesh
			rail.material_override = rail_mat
			rail.position = Vector3(0.0, size.y * 0.5 * float(sy), size.z * 0.5 * float(sz))
			root.add_child(rail)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var rail := MeshInstance3D.new()
			var rail_mesh := BoxMesh.new()
			rail_mesh.size = Vector3(t, size.y, t)
			rail.mesh = rail_mesh
			rail.material_override = rail_mat
			rail.position = Vector3(size.x * 0.5 * float(sx), 0.0, size.z * 0.5 * float(sz))
			root.add_child(rail)

	root.position = box["center"] as Vector3
	root.rotation_degrees.y = float(box.get("yaw_deg", 0.0))
	return root


func _shoot(view: String, ortho: float, centre: Vector3, offset: Vector3) -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = ortho
	_camera.position = centre + offset
	_camera.look_at(centre, Vector3.UP)
	for _i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/q3_plate_slop__%s__%s.png" % [OUT_DIR, _label, view]
	print("[q3] %s (%d)" % [path, get_viewport().get_texture().get_image().save_png(path)])


func _figure(at: Vector3) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = 1.8
	capsule.radius = 0.28
	body.mesh = capsule
	body.position = Vector3(0.0, 0.9, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.42, 0.92)
	body.material_override = mat
	root.add_child(body)
	root.position = at
	return root


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


func _light() -> void:
	RenderingServer.directional_shadow_atlas_set_size(1024, true)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 34.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-16.0, -128.0, 0.0)
	fill.light_energy = 0.40
	add_child(fill)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.26, 0.31, 0.36)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.60, 0.68, 0.76)
	environment.ambient_light_energy = 0.55
	env.environment = environment
	add_child(env)
	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)
