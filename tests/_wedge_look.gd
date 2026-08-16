extends Node

## SCRATCH PROBE (leading underscore — not a gate unit).
##
##   xvfb-run -a --server-args="-screen 0 1600x900x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_wedge_look.tscn   (scene lane: it names BoatBody through
##                                       CaptureSubject, which lane A cannot compile)
##
## CAN A PERSON SEE THE WEDGE? `critic_ferry`'s saloon front rakes +4 and its
## roof stops on the wall's foot line, so 0.500 m of the head is open sky for the
## wall's whole 4.0 m run. Every render this project has ever taken of that boat
## shows the junction edge-on. This one puts the camera where the gap is largest
## and prints, beside the frame, how many pixels of SKY fall inside the
## deckhouse's own silhouette — so the answer is not "it looks fine".
##
## Frames go to `.probe/` and are NEVER committed: `.probe/` is gitignored and
## these are a look, not evidence anyone will diff.
##
## REPRODUCIBILITY. There is no `BoatBody` here — the plan is baked on its own
## and photographed against a flat sky — so nothing settles, no buoyancy runs and
## the physics-LOD class cannot reach it. `CaptureSubject.hold_still` is still
## called on the baked root for the same reason a seatbelt is worn in a parked
## car: the next person to copy this rig will stand a hull in it.
## `CaptureClock.pin` stops `WorldClock`, and every grab waits on
## `RenderingServer.frame_post_draw`.

const CaptureClock := preload("res://tests/support/capture_clock.gd")
const CaptureSubject := preload("res://tests/support/capture_subject.gd")
const OUT_DIR := "res://.probe/wedge"

var _camera: Camera3D
var _root: Node3D


func _ready() -> void:
	PieceKit.ensure_loaded()
	print("pinned hour: %s" % str(CaptureClock.pin(get_tree(), CaptureClock.NOON)))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_build()
	await _shoot("ferry_saloon_front__eye", Vector3(5.0, 1.7, -6.0), Vector3(5.0, 2.3, 6.0))
	await _shoot("ferry_saloon_front__low", Vector3(5.0, 0.6, -3.0), Vector3(5.0, 2.45, 5.8))
	await _shoot("ferry_saloon_front__above", Vector3(5.0, 6.0, 1.0), Vector3(5.0, 2.4, 6.2))
	## THE ONE VIEW THAT CAN SETTLE IT: standing INSIDE the saloon at eye height,
	## looking up at the junction. A wedge of open sky there is unambiguous, where
	## a view from above cannot tell a hole in the roof from the missing deck
	## under a plan baked on its own.
	await _shoot("ferry_saloon_inside__up", Vector3(5.0, 1.6, 9.5), Vector3(5.0, 2.5, 5.7))
	get_tree().quit(0)


func _build() -> void:
	var world := Node3D.new()
	add_child(world)

	var sky := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(400.0, 200.0)
	sky.mesh = quad
	var sky_material := StandardMaterial3D.new()
	sky_material.albedo_color = Color(0.86, 0.30, 0.20)
	sky_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sky.material_override = sky_material
	## A LOUD ground behind the boat, because the question is "does any of it show
	## through the junction" and a pale sky against pale plating answers nothing.
	sky.position = Vector3(5.0, 20.0, 60.0)
	sky.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	world.add_child(sky)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	light.shadow_enabled = true
	world.add_child(light)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.86, 0.30, 0.20)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.70, 0.78)
	environment.ambient_light_energy = 0.60
	env.environment = environment
	world.add_child(env)

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://resources/data/structures/critic_ferry.json"
	))
	var plan := StructurePlan.from_dict(parsed as Dictionary)
	_root = StructureBaker.bake(plan)
	CaptureSubject.hold_still(_root)
	world.add_child(_root)

	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 35.0
	world.add_child(_camera)


func _shoot(name: String, at: Vector3, look: Vector3) -> void:
	_camera.position = at
	_camera.look_at(look, Vector3.UP)
	await CaptureClock.settle(get_tree(), 4)
	var image := get_viewport().get_texture().get_image()
	var sky_px := 0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.r > 0.55 and c.g < 0.45 and c.b < 0.35:
				sky_px += 1
	print("%s: %d px of ground colour in frame (%d x %d)" % [
		name, sky_px, image.get_width(), image.get_height()
	])
	var err := image.save_png("%s/%s.png" % [OUT_DIR, name])
	print("  written: %s" % str(err == OK))
