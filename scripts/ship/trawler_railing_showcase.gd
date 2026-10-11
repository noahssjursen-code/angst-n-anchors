extends Node3D

const ROOT := "res://resources/models/parts/trawler_rails/"
const VARIANTS := ["rail_flat", "halfwall_flat", "rail_rising", "halfwall_rising"]
var _parts: Node3D
var _camera: Camera3D
var _label: Label
var _assets: Dictionary = {}
var _yaw := 35.0
var _pitch := -30.0
var _distance := 19.0
var _verified_variants := 0


func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.035, 0.05, 0.065)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.86, 0.95)
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.8
	add_child(light)
	add_child(TrawlerHullAsset.instantiate())
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_camera.current = true
	add_child(_camera)
	_update_camera()
	var ui := CanvasLayer.new()
	add_child(ui)
	_label = Label.new()
	_label.position = Vector2(24, 20)
	_label.add_theme_font_size_override("font_size", 22)
	ui.add_child(_label)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
	for item in manifest["assets"]:
		_assets[item["id"]] = item
	show_variant(0)
	if "--verify-rails" in OS.get_cmdline_user_args():
		for index in range(4):
			show_variant(index)
			for frame in range(8):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("C:/Users/noahs/Documents/Codex/2026-10-05/referenced-chatgpt-conversation-this-is-an/outputs/trawler-rails/godot-" + VARIANTS[index] + ".png")
		assert(_verified_variants == 5, "One or more assembly checks failed")
		print("PASS: all imported panel endpoints and heights match; halfwalls have no joint posts")
		get_tree().quit()


func show_variant(index: int) -> void:
	if is_instance_valid(_parts):
		remove_child(_parts)
		_parts.queue_free()
	_parts = Node3D.new()
	add_child(_parts)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + VARIANTS[index] + "_assembly.json"))
	var endpoints: Dictionary = {}
	var joints: Dictionary = {}
	var panel_count := 0
	for placement in data["placements"]:
		var spec: Dictionary = _assets[placement["asset_id"]]
		var model := (load(spec["model"]) as PackedScene).instantiate() as Node3D
		_parts.add_child(model)
		var p: Array = placement["position"]
		model.position = Vector3(p[0], p[1], p[2])
		model.rotation_degrees.y = float(placement["yaw_degrees"])
		if spec["kind"] == "joint":
			joints[_key(model.position)] = float(spec["height_start_m"])
			continue
		panel_count += 1
		# Inspect sockets from the imported GLBs, not only the placement recipe.
		for socket_name in ["SocketStart", "SocketEnd"]:
			var socket := model.find_child(socket_name + "*", true, false) as Node3D
			assert(socket != null, "Missing exported connection socket")
			var point := socket.global_position
			var key := _key(point)
			var height := float(spec["height_start_m"] if socket_name == "SocketStart" else spec["height_end_m"])
			if not endpoints.has(key):
				endpoints[key] = []
			endpoints[key].append(height)
	assert(panel_count == 37 and joints.size() == int(data["joint_count"]) and endpoints.size() == 37)
	for key in endpoints:
		assert(endpoints[key].size() == 2, "Unmatched panel end: " + key)
		assert(is_equal_approx(endpoints[key][0], endpoints[key][1]), "Top height discontinuity")
		if int(data["joint_count"]) > 0:
			assert(joints.has(key), "Missing corner joint: " + key)
			assert(is_equal_approx(endpoints[key][0], joints[key]), "Joint height mismatch")
	_label.text = VARIANTS[index].replace("_", " ").capitalize() + "\n1–4: variants · RMB: orbit · Wheel: zoom\n37 separate panels · " + ("mitered seamless joins" if joints.is_empty() else "shared rail posts")
	_verified_variants += 1


func _key(point: Vector3) -> String:
	return "%d,%d,%d" % [roundi(point.x * 10000), roundi(point.y * 10000), roundi(point.z * 10000)]


func _update_camera() -> void:
	var target := Vector3(0, 2.8, 0)
	_camera.position = target + Vector3(sin(deg_to_rad(_yaw)) * cos(deg_to_rad(_pitch)), -sin(deg_to_rad(_pitch)), cos(deg_to_rad(_yaw)) * cos(deg_to_rad(_pitch))) * _distance
	_camera.look_at(target)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode >= KEY_1 and event.keycode <= KEY_4:
		show_variant(event.keycode - KEY_1)
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		_yaw -= event.relative.x * 0.3
		_pitch = clampf(_pitch + event.relative.y * 0.3, -80, -5)
		_update_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(7, _distance - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(40, _distance + 1)
		_update_camera()
