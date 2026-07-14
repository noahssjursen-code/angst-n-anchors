extends Node

const OUTPUT_DIR := "/opt/cursor/artifacts/hull-forms"
const HULL_IDS := [
	"fishing_trawler_small",
	"workboat",
	"passenger_catamaran",
	"container_short_sea",
	"tanker_product",
	"tanker_lng",
]


func _ready() -> void:
	call_deferred("_capture_all")


func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	get_tree().root.add_child(viewport)

	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055, 0.075, 0.095)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.70)
	env.ambient_light_energy = 0.85
	environment.environment = env
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	sun.light_energy = 1.4
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
	fill.light_energy = 0.55
	world.add_child(fill)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 48.0
	world.add_child(camera)

	for hull_id in HULL_IDS:
		var boat := HullRegistry.build_hull(hull_id)
		if boat == null:
			push_error("Hull visual capture: cannot build %s" % hull_id)
			continue
		boat.freeze = true
		boat.rotation_degrees.y = -18.0
		world.add_child(boat)
		var length := maxf(boat.length_m, 10.0)
		var beam := maxf(boat.beam_m, 5.0)
		var height := maxf(boat.depth_m, 3.0)
		for view in ["front", "side", "three_quarter"]:
			match view:
				"front":
					camera.position = Vector3(
						0.0,
						height * 0.82,
						-maxf(beam * 1.9, height * 5.0)
					)
				"side":
					camera.position = Vector3(
						maxf(length * 0.76, height * 5.0),
						height * 0.68,
						0.0
					)
				_:
					var distance := maxf(length * 0.64, beam * 1.45)
					camera.position = Vector3(
						distance * 0.55,
						height * 1.35,
						-distance
					)
			camera.look_at_from_position(
				camera.position,
				Vector3(0.0, height * 0.48, 0.0),
				Vector3.UP
			)
			for _frame in range(3):
				await get_tree().process_frame
			var image := viewport.get_texture().get_image()
			var path := "%s/%s_%s.png" % [OUTPUT_DIR, hull_id, view]
			var error := image.save_png(path)
			if error != OK:
				push_error("Hull visual capture: failed %s (error %d)" % [path, error])
			else:
				print("Hull visual capture: " + path)
		world.remove_child(boat)
		boat.free()

	viewport.queue_free()
	get_tree().quit()
