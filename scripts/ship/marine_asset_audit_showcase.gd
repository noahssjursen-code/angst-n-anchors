extends Node3D

## Inspection only: candidate legacy hardware at current physics coordinates.
## This deliberately does not install rejected hardware on gameplay vessels.
var camera: Camera3D
var propeller: Node3D
var rudder: Node3D
var hull: Node3D
var elapsed := 0.0

func _ready() -> void:
	assert(ShipyardPlaytestMode.active(), "Asset inspection must isolate captain saves and networking")
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("26343f")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .65
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, -35, 0)
	sun.light_energy = 1.8
	add_child(sun)
	hull = TrawlerHullAsset.instantiate(false)
	ModelPaint.apply(hull, {})
	add_child(hull)
	propeller = load("res://resources/models/parts/marine_kit/bronze_propeller/bronze_propeller.glb").instantiate()
	propeller.position = Vector3(0, 2.92 * .20, 14 * .45)
	add_child(propeller)
	rudder = load("res://resources/models/parts/marine_kit/rudder/rudder.glb").instantiate()
	rudder.position = Vector3(0, 2.92 * .24, 14 * .46)
	add_child(rudder)
	for item in [propeller, rudder]:
		var bounds := AABB()
		var first := true
		for mesh: MeshInstance3D in item.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		print("AUDIT ", item.name, " world bounds: ", bounds)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.5
	add_child(camera)
	camera.position = Vector3(8, 3.7, 12)
	camera.look_at(Vector3(0, 1.35, 5))
	var label := Label.new()
	label.text = "ASSET AUDIT — existing hardware at physics mounts (NOT approved)\n1: stern exterior   2: hull hidden / pivot inspection\nLegacy propeller spins around shaft; rudder sweeps ±28°"
	label.position = Vector2(24, 70)
	label.add_theme_font_size_override("font_size", 20)
	var ui := CanvasLayer.new()
	add_child(ui)
	ui.add_child(label)
	var args := OS.get_cmdline_user_args()
	var index := args.find("--capture")
	if index >= 0 and index + 1 < args.size():
		var initial_spin := propeller.rotation.z
		for i in 12: await get_tree().process_frame
		assert(not is_equal_approx(initial_spin, propeller.rotation.z))
		assert(absf(rudder.rotation.y) <= deg_to_rad(28))
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png(args[index + 1]) == OK)
		hull.hide()
		for i in 12: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png(args[index + 1].get_basename() + "-hardware.png") == OK)
		print("MARINE ASSET AUDIT CAPTURED")
		get_tree().quit()

func _process(delta: float) -> void:
	elapsed += delta
	propeller.rotation.z += delta * 2
	rudder.rotation.y = sin(elapsed) * deg_to_rad(28)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1: hull.show()
		if event.keycode == KEY_2: hull.hide()
