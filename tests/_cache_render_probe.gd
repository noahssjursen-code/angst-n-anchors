extends SceneTree

## SCRATCH PROBE (leading underscore). Renders what the two caches STAMP, so the
## "nothing a player can see changed" claim is a picture and an md5 rather than a
## node count. Runs unchanged on a `git archive HEAD` baseline: public API only.
##
## Orthographic, one fixed rig, 1.8 m figure in frame for absolute scale
## (CONVENTIONS.md §3a — a capture without one has no scale).

const OUT_DIR := "user://cache_probe"


func _initialize() -> void:
	var root := get_root()
	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.78, 0.84, 0.90)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.72)
	e.ambient_light_energy = 1.0
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	world.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.34, 0.38, 0.32)
	ground.material_override = gm
	world.add_child(ground)

	## 1.8 m figure, at the left of the row.
	var figure := MeshInstance3D.new()
	var caps := CapsuleMesh.new()
	caps.height = 1.8
	caps.radius = 0.28
	figure.mesh = caps
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.92, 0.24, 0.16)
	figure.material_override = fm
	figure.position = Vector3(-16.0, 0.9, 6.0)
	world.add_child(figure)

	var subjects: Array[Node3D] = []
	subjects.append(LandDecorCache.house_instance(3, 0.0, 0.0))
	subjects.append(ModelCache.instance("res://resources/data/models/buildings/lighthouse_building.json", 1.0))
	subjects.append(ModelCache.instance("res://resources/data/models/buildings/foghorn_building.json", 1.0))
	subjects.append(ModelCache.instance("res://resources/data/models/cargo/container_cube.json", 1.0))
	subjects.append(ModelCache.instance("res://resources/data/meshes/docks/docking_bollard.json", 1.0))

	var x := -10.0
	for node in subjects:
		node.position = Vector3(x, 0.0, 0.0)
		world.add_child(node)
		x += 11.0

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 62.0
	cam.position = Vector3(6.0, 14.0, 46.0)
	cam.rotation_degrees = Vector3(-9.0, 0.0, 0.0)
	cam.current = true
	world.add_child(cam)

	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var img := root.get_texture().get_image()
	var path := OUT_DIR.path_join("cache_row.png")
	img.save_png(path)
	print("WROTE %s  size=%dx%d" % [ProjectSettings.globalize_path(path), img.get_width(), img.get_height()])
	quit(0)
