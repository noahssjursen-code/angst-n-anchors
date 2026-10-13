extends Node3D

const Lod = preload("res://scripts/network/remote_vessel_lod.gd")
var failures := 0
var boat: ImportedDraftVessel
var lod: Node3D
var caption: Label

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures += 1

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	GameMenu.set_gameplay_hud_visible(false)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.1, .18, .23)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .65
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	add_child(light)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(32, 22, 35)
	camera.look_at(Vector3(0, 3, 0))
	camera.current = true
	var canvas := CanvasLayer.new()
	add_child(canvas)
	caption = Label.new()
	caption.position = Vector2(25, 25)
	canvas.add_child(caption)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/vessels/prebuilt/28_10_m.json"))
	boat = ImportedDraftVessel.new()
	boat.configure(layout.brick_layout)
	add_child(boat)
	boat.freeze = true
	boat.process_mode = Node.PROCESS_MODE_DISABLED
	lod = Lod.new()
	boat.add_child(lod)
	call_deferred("run")

func run() -> void:
	await get_tree().process_frame
	await lod.refresh(501.0)
	check(lod.distant, "beyond 500m uses constructed proxy")
	check(lod.proxy_surfaces > 0 and lod.proxy_surfaces < lod.source_surfaces, "draw surfaces reduced %d -> %d" % [lod.source_surfaces, lod.proxy_surfaces])
	await lod.refresh(450.0)
	check(lod.distant, "hysteresis keeps proxy at 450m")
	await lod.refresh(399.0)
	check(not lod.distant, "returns full ship below 400m")
	for mesh in boat.find_children("*", "MeshInstance3D", true, false):
		check(not mesh.has_meta("remote_lod_range"), "range restored: " + str(mesh.name))
	await lod.refresh(600.0)
	await lod.refresh(600.0, true)
	check(not lod.distant, "passenger protects full ship during freecam")
	await lod.refresh(600.0)
	var before: int = lod.source_surfaces
	var cargo := MeshInstance3D.new()
	cargo.name = "ManifestArrival"
	var box := BoxMesh.new()
	box.size = Vector3(2, 2, 6)
	cargo.mesh = box
	cargo.position = Vector3(0, 5, 0)
	boat.add_child(cargo)
	await lod.refresh(600.0)
	check(lod.source_surfaces > before, "cargo arriving while distant rebuilds proxy")
	cargo.free()
	await lod.refresh(600.0)
	check(lod.source_surfaces == before, "removed cargo disappears from proxy")
	var original := boat.draft.duplicate(true)
	var custom := original.duplicate(true)
	var new_part: Dictionary = custom.parts[0].duplicate(true)
	new_part.position = [0, 14, 0]
	custom.parts.append(new_part)
	await lod.refresh(0.0)
	boat.apply_brick_layout(custom)
	await lod.refresh(600.0)
	check(lod._proxy.mesh.get_aabb().end.y > 14.0, "runtime UGC addition is present in baked geometry")
	await lod.refresh(0.0)
	boat.apply_brick_layout(original)
	# Enter and leave while a multi-frame bake is still running.
	lod.refresh(600.0)
	await lod.refresh(0.0)
	await get_tree().process_frame
	check(not lod.distant, "approaching during bake cancels distant switch")
	await lod.refresh(600.0)
	var gizmo := preload("res://scripts/network/network_range_gizmo.gd").new()
	add_child(gizmo)
	gizmo.set_process(false)
	gizmo._policy = {"ship_bands_m": [100, 500, 2000, 4000], "player_range_m": 1000, "ship_range_m": 4000}
	gizmo._rebuild()
	gizmo.position_rings(Vector3.ZERO, Vector3(20, 60, 0))
	check(gizmo._rings.size() == 7, "boat LOD and server network bands built without duplicate outer ring")
	check(is_equal_approx(gizmo._rings[2].node.scale.x, 80.0), "3D network radius accounts for camera height")
	check(gizmo._rings[2].node.position.x == 20.0 and gizmo._rings[0].node.position.x == 0.0, "network follows observer; boat guides stay on boat")
	gizmo.free()
	caption.text = "Actual construction: %d surfaces -> distant replacement: %d\nSpace: switch full / distant model (close-up for inspection)" % [lod.source_surfaces, lod.proxy_surfaces]
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var folder := "C:/Users/noahs/Pictures/machinescreenshots"
		DirAccess.make_dir_recursive_absolute(folder)
		get_viewport().get_texture().get_image().save_png(folder + "/vessel-lod-%d.png" % Time.get_unix_time_from_system())
		if not "--inspect" in OS.get_cmdline_user_args():
			var camera := get_viewport().get_camera_3d()
			camera.position = Vector3(0, 1050, 250)
			camera.look_at(Vector3.ZERO)
			DebugHud.set_gizmo_layer_enabled(WorldGizmos.LAYER_NETWORK, true)
			await get_tree().create_timer(0.2).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(folder + "/network-range-rings-%d.png" % Time.get_unix_time_from_system())
	print("LOD RESULT failures=", failures)
	if not "--inspect" in OS.get_cmdline_user_args(): get_tree().quit(1 if failures else 0)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		await lod.refresh(0.0 if lod.distant else 600.0)
