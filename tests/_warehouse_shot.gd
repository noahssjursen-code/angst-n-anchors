extends Node3D

## SCRATCH CAPTURE (leading underscore — not a gate unit). Photographs the
## warehouse blueprint as `BuildingCache` stamps it, so a person can look at it
## instead of reading a brick count (REALITY.md §1).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_warehouse_shot.tscn
##
## Rig settings are lifted from `vessel_render_capture.gd` for the reasons it
## documents: shadows ON (the default is off, and a whole day of captures shipped
## flat because of it), a PALE sky so the silhouette has a boundary against its
## ground, and a 1.8 m figure standing in the open where it can be SEEN.

const OUT_DIR := "res://screenshots/buildings"
const VIEWS := [
	{"name": "quarter", "azimuth": -35.0, "elevation": 18.0},
	{"name": "door", "azimuth": 0.0, "elevation": 6.0},
]

var _camera: Camera3D


func _ready() -> void:
	var layout := BuildingBlueprintCatalog.by_id("warehouse")
	if layout == null:
		print("warehouse blueprint did not load")
		get_tree().quit(1)
		return
	## printerr, not print: stdout is block-buffered when it is a pipe, so a
	## progress marker written with print() is invisible while the run is stuck.
	printerr("[shot] blueprint loaded")
	var building := BuildingCache.instance(layout, false)
	add_child(building)
	printerr("[shot] stamped")

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160.0, 160.0)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.44, 0.45, 0.42)
	ground.material_override = ground_mat
	add_child(ground)

	var figure := _figure()
	## Standing off the quay-facing corner, in the open, with sky behind it.
	figure.position = Vector3(-12.0, 0.0, -9.0)
	add_child(figure)

	_light()
	var bounds := _bounds(building)
	print("visual meshes %d, bounds %s" % [_mesh_count(building), str(bounds)])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for view in VIEWS:
		await _shoot(bounds, view as Dictionary)
	get_tree().quit(0)


func _figure() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = 1.8
	capsule.radius = 0.28
	body.mesh = capsule
	body.position = Vector3(0.0, 0.9, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.55, 0.10)
	body.material_override = mat
	root.add_child(body)
	return root


func _light() -> void:
	## llvmpipe rasterises the shadow map in software, and a 645-mesh building at
	## the 4096 default never finished a frame in 10 minutes of CPU. 1024 is a
	## legible shadow at this framing and it is the difference between a capture
	## and a hang — the rig, not the subject (REALITY.md §8).
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
	_camera.fov = 35.0
	_camera.current = true
	add_child(_camera)


func _bounds(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(node):
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		if first:
			out = aabb
			first = false
		else:
			out = out.merge(aabb)
	return out


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


func _mesh_count(node: Node) -> int:
	return _meshes(node).size()


func _shoot(bounds: AABB, view: Dictionary) -> void:
	var centre := bounds.get_center()
	var azimuth := deg_to_rad(float(view["azimuth"]))
	var elevation := deg_to_rad(float(view["elevation"]))
	var dir := Vector3(
		cos(elevation) * sin(azimuth), sin(elevation), cos(elevation) * cos(azimuth)
	)
	var radius := bounds.size.length() * 0.5
	var distance := radius / tan(deg_to_rad(_camera.fov * 0.5)) * 1.15
	_camera.position = centre + dir * distance
	_camera.look_at(centre, Vector3.UP)
	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out := "%s/warehouse__%s.png" % [OUT_DIR, str(view["name"])]
	var error := get_viewport().get_texture().get_image().save_png(out)
	print("%s (%d)" % [out, error])
