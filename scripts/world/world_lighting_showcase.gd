class_name WorldLightingShowcase
extends Node3D

## F6 presentation lab for the shipping world's shared lighting seam.
## Uses WorldRenderer + WeatherLighting, not a showcase-only environment.

const FOGHORN_MODEL := "res://resources/data/models/buildings/foghorn_building.json"

const TIMES: Array[Dictionary] = [
	{"label": "MORNING", "clock": "06:20", "fraction": 6.333 / 24.0},
	{"label": "DAY", "clock": "13:10", "fraction": 13.166 / 24.0},
	{"label": "EVENING", "clock": "20:45", "fraction": 20.75 / 24.0},
	{"label": "NIGHT", "clock": "01:10", "fraction": 1.166 / 24.0},
]

const WEATHER: Array[Dictionary] = [
	{
		"label": "CRISP COAST",
		"precipitation": 0.0, "wind": 0.16, "visibility": 0.98,
		"cloud": 0.16, "sea": 0.14, "wave_height": 0.55,
	},
	{
		"label": "BROKEN CLOUD",
		"precipitation": 0.0, "wind": 0.28, "visibility": 0.90,
		"cloud": 0.48, "sea": 0.25, "wave_height": 1.15,
	},
	{
		"label": "COASTAL RAIN",
		"precipitation": 0.58, "wind": 0.46, "visibility": 0.74,
		"cloud": 0.74, "sea": 0.41, "wave_height": 2.25,
	},
	{
		"label": "HARBOUR FOG",
		"precipitation": 0.04, "wind": 0.08, "visibility": 0.32,
		"cloud": 0.68, "sea": 0.10, "wave_height": 0.42,
	},
	{
		"label": "NORTH SEA GALE",
		"precipitation": 0.86, "wind": 0.82, "visibility": 0.50,
		"cloud": 0.95, "sea": 0.76, "wave_height": 6.1,
	},
]

const CAMERAS: Array[Dictionary] = [
	{
		"label": "HARBOUR WIDE",
		"position": Vector3(82.0, 34.0, 72.0),
		"target": Vector3(-5.0, 5.0, 0.0),
		"fov": 52.0,
	},
	{
		"label": "QUAYSIDE",
		"position": Vector3(52.0, 12.5, 27.0),
		"target": Vector3(-8.0, 6.0, -8.0),
		"fov": 57.0,
	},
	{
		"label": "VESSEL",
		"position": Vector3(54.0, 8.5, 43.0),
		"target": Vector3(18.0, 4.0, 6.0),
		"fov": 50.0,
	},
	{
		"label": "PORT OVERVIEW",
		"position": Vector3(74.0, 48.0, -82.0),
		"target": Vector3(-24.0, 4.0, 0.0),
		"fov": 48.0,
	},
	{
		"label": "WORK CREW",
		"position": Vector3(25.0, 7.2, -24.0),
		"target": Vector3(-1.0, 3.25, -11.0),
		"fov": 48.0,
	},
]

const CANONICAL_REVIEW: Array[Dictionary] = [
	{"time": 0, "weather": 3, "camera": 0, "slug": "morning_mist"},
	{"time": 1, "weather": 1, "camera": 0, "slug": "day_broken_cloud"},
	{"time": 2, "weather": 2, "camera": 1, "slug": "evening_rain"},
	{"time": 3, "weather": 0, "camera": 2, "slug": "night_clear"},
	{"time": 1, "weather": 4, "camera": 0, "slug": "day_gale"},
	{"time": 1, "weather": 1, "camera": 4, "slug": "day_work_crew"},
]

const DECK_Y := 2.4
const SHORE_X := -10.0

var time_index := 2
var weather_index := 1
var camera_index := 0

var _camera: Camera3D
var _hud_title: Label
var _hud_detail: Label
var _practical_lights: Array[Light3D] = []
var _capture_running := false


func _ready() -> void:
	WorldWeather.set_blend_to_lighting_paused(true)
	_build_renderer()
	_build_landscape()
	_build_harbour()
	_build_camera()
	_build_hud()
	_apply_review_state()
	if "--capture-world-lighting" in OS.get_cmdline_user_args():
		_capture_running = true
		call_deferred("_capture_review_series")


func _process(_delta: float) -> void:
	var weather := get_node_or_null("/root/WeatherLighting")
	var light_scale := 1.0
	var volume_scale := 1.0
	if weather != null:
		if weather.has_method("artificial_light_scale"):
			light_scale = float(weather.call("artificial_light_scale"))
		if weather.has_method("artificial_volumetric_scale"):
			volume_scale = float(weather.call("artificial_volumetric_scale"))
	for light in _practical_lights:
		if not is_instance_valid(light):
			continue
		light.light_energy = float(light.get_meta("base_energy", 3.0)) * light_scale
		light.light_volumetric_fog_energy = (
			float(light.get_meta("base_volume", 0.7)) * volume_scale
		)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo or _capture_running:
		return
	match event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4:
			time_index = int(event.keycode - KEY_1)
			_apply_review_state()
		KEY_Q:
			weather_index = wrapi(weather_index - 1, 0, WEATHER.size())
			_apply_review_state()
		KEY_E:
			weather_index = wrapi(weather_index + 1, 0, WEATHER.size())
			_apply_review_state()
		KEY_C:
			camera_index = wrapi(camera_index + 1, 0, CAMERAS.size())
			_apply_camera()
		KEY_ESCAPE:
			get_tree().quit()
	get_viewport().set_input_as_handled()


func _build_renderer() -> void:
	var renderer := WorldRenderer.new()
	renderer.name = "WorldRenderer"
	renderer.force_runtime_build = true
	renderer.enable_ocean_system = true
	renderer.enable_ssao = true
	renderer.enable_glow = true
	renderer.enable_volumetric_fog = true
	renderer.enable_weather_post_fx = true
	add_child(renderer)

	var rain := RainField.new()
	rain.name = "RainField"
	add_child(rain)


func _build_landscape() -> void:
	var terrain := MeshInstance3D.new()
	terrain.name = "TerrainHeadland"
	terrain.mesh = _terrain_mesh()
	terrain.material_override = MeshBuilder.make_material(Color(0.12, 0.18, 0.13), 0.98)
	add_child(terrain)

	# A compact, level industrial shelf cut into the authored headland.
	_add_box(
		self, "PortApron", Vector3(62.0, 1.7, 108.0),
		Vector3(-41.0, DECK_Y - 0.85, 0.0), Color(0.105, 0.112, 0.12), 0.96
	)
	_add_box(
		self, "QuayMass", Vector3(24.0, 5.3, 112.0),
		Vector3(-2.0, DECK_Y - 2.65, 0.0), Color(0.062, 0.068, 0.074), 0.98
	)
	_add_box(
		self, "QuayDeck", Vector3(24.0, 0.28, 112.0),
		Vector3(-2.0, DECK_Y - 0.14, 0.0), Color(0.13, 0.136, 0.142), 0.93
	)
	_add_box(
		self, "QuayEdge", Vector3(0.38, 1.2, 112.0),
		Vector3(10.15, DECK_Y - 0.46, 0.0), Color(0.62, 0.64, 0.62), 0.78
	)


func _terrain_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const ROWS := 14
	const COLS := 12
	var grid: Array[Array] = []
	for z_i in range(ROWS):
		var row: Array[Vector3] = []
		var z := lerpf(-145.0, 145.0, float(z_i) / float(ROWS - 1))
		var coast := SHORE_X + sin(z * 0.036) * 6.5 + sin(z * 0.083) * 2.2
		for x_i in range(COLS):
			var inland := float(x_i) / float(COLS - 1)
			var x := lerpf(coast, -172.0, inland)
			var height := 1.3 + pow(inland, 1.28) * 17.0
			height += sin(z * 0.031 + inland * 3.8) * 2.3 * inland
			height += sin(x * 0.055 - z * 0.018) * 1.2 * inland
			if absf(z) < 66.0 and x > -76.0:
				height = lerpf(height, DECK_Y - 0.95, smoothstep(-76.0, -24.0, x))
			row.append(Vector3(x, height, z))
		grid.append(row)
	for z_i in range(ROWS - 1):
		for x_i in range(COLS - 1):
			var a: Vector3 = grid[z_i][x_i]
			var b: Vector3 = grid[z_i][x_i + 1]
			var c: Vector3 = grid[z_i + 1][x_i + 1]
			var d: Vector3 = grid[z_i + 1][x_i]
			for vertex in [a, c, b, a, d, c]:
				surface.set_uv(Vector2(vertex.x * 0.02, vertex.z * 0.02))
				surface.add_vertex(vertex)
	surface.generate_normals()
	return surface.commit()


func _build_harbour() -> void:
	_build_buildings()
	_build_cranes()
	_build_ship()
	_build_characters()
	_build_port_lights()
	_build_quay_details()


func _build_buildings() -> void:
	var warehouse := Node3D.new()
	warehouse.name = "Warehouse"
	warehouse.position = Vector3(-45.0, DECK_Y, -24.0)
	add_child(warehouse)
	_add_box(
		warehouse, "WarehouseBody", Vector3(25.0, 9.5, 30.0),
		Vector3(0.0, 4.75, 0.0), Color(0.36, 0.39, 0.40), 0.88
	)
	_add_prism_roof(warehouse, Vector3(26.4, 5.0, 31.4), Vector3(0.0, 11.0, 0.0))
	for z in [-10.5, 0.0, 10.5]:
		_add_box(
			warehouse, "LoadingDoor", Vector3(0.18, 5.8, 7.2),
			Vector3(12.58, 2.9, z), Color(0.055, 0.065, 0.075), 0.72
		)
		_build_wall_light(warehouse, Vector3(12.78, 6.7, z))

	var office := ModelCache.instance(FOGHORN_MODEL, 0.85)
	office.name = "HarbourOffice"
	office.position = Vector3(-50.0, DECK_Y, 27.0)
	office.rotation_degrees.y = 90.0
	add_child(office)

	var lighthouse := LighthouseBuilding.new()
	lighthouse.name = "HeadlandLighthouse"
	lighthouse.position = Vector3(-88.0, 12.4, 82.0)
	lighthouse.scale = Vector3.ONE * 0.82
	add_child(lighthouse)


func _build_cranes() -> void:
	var bulk := BulkCrane.new()
	bulk.name = "BulkCrane"
	bulk.position = Vector3(-4.0, DECK_Y, -18.0)
	bulk.rotation_degrees.y = -90.0
	bulk.show_operator = true
	bulk.boom_angle_deg = 38.0
	bulk.hoist_length_m = 8.0
	add_child(bulk)

	var provision := ProvisionCrane.new()
	provision.name = "ProvisionCrane"
	provision.position = Vector3(-4.0, DECK_Y, 31.0)
	provision.rotation_degrees.y = -90.0
	provision.trolley_z_m = -22.0
	provision.hoist_length_m = 7.0
	add_child(provision)


func _build_ship() -> void:
	var preset := _prebuilt("fishing_trawler")
	if preset.is_empty():
		return
	var ship := VesselSpawn.instantiate(
		str(preset.get("hull_id", "hull_28x10")),
		(preset.get("prebuilt_layout", {}) as Dictionary).duplicate(true),
		str(preset.get("registration_id", "fishing_vessel")),
	)
	if ship == null:
		return
	ship.name = "ShowcaseVessel"
	ship.freeze = true
	ship.position = Vector3(22.0, WaveSurface.WATER_LEVEL, 7.0)
	ship.rotation_degrees.y = 180.0
	VesselSpawn.apply_propulsion_override(ship, preset)
	VesselSpawn.apply_identity(ship, preset)
	add_child(ship)
	call_deferred("_place_showcase_ship", ship)


func _place_showcase_ship(ship: BoatBody) -> void:
	if not is_instance_valid(ship):
		return
	ship.place_at_waterline(WaveSurface.WATER_LEVEL)
	ship.freeze = true
	ship.sleeping = true


func _prebuilt(id: String) -> Dictionary:
	for entry in PrebuiltVesselCatalog.catalog_entries():
		if str(entry.get("prebuilt_id", "")) == id:
			return entry
	return {}


func _build_characters() -> void:
	var workers := [
		{"preset": "orange_oilskin", "position": Vector3(3.0, DECK_Y, -12.0), "yaw": -70.0},
		{"preset": "trawler_deckhand", "position": Vector3(1.0, DECK_Y, 8.0), "yaw": 65.0},
		{"preset": "dock_safety_officer", "position": Vector3(-18.0, DECK_Y, 19.0), "yaw": 120.0},
		{"preset": "harbour_master", "position": Vector3(-35.0, DECK_Y, 29.0), "yaw": 86.0},
		{"preset": "harbour_mechanic", "position": Vector3(-19.0, DECK_Y, -32.0), "yaw": 40.0},
	]
	for spec in workers:
		var npc := NpcBase.new()
		npc.name = str(spec["preset"]).to_pascal_case()
		npc.appearance = CharacterCatalog.appearance_preset(str(spec["preset"]))
		npc.position = spec["position"] as Vector3
		npc.rotation_degrees.y = float(spec["yaw"])
		add_child(npc)


func _build_port_lights() -> void:
	for spec in [
		{"position": Vector3(4.0, DECK_Y, -43.0), "yaw": 90.0},
		{"position": Vector3(4.0, DECK_Y, 0.0), "yaw": 90.0},
		{"position": Vector3(4.0, DECK_Y, 43.0), "yaw": 90.0},
		{"position": Vector3(-27.0, DECK_Y, -42.0), "yaw": 0.0},
		{"position": Vector3(-27.0, DECK_Y, 42.0), "yaw": 180.0},
	]:
		_build_lamp_post(spec["position"] as Vector3, float(spec["yaw"]))


func _build_lamp_post(position: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "QuayLamp"
	root.position = position
	root.rotation_degrees.y = yaw
	add_child(root)
	_add_box(root, "Pole", Vector3(0.18, 7.2, 0.18), Vector3(0.0, 3.6, 0.0), Color(0.13, 0.15, 0.16), 0.55, 0.38)
	_add_box(root, "Arm", Vector3(2.0, 0.14, 0.14), Vector3(0.9, 7.0, 0.0), Color(0.13, 0.15, 0.16), 0.55, 0.38)
	_add_box(root, "LampHousing", Vector3(0.72, 0.28, 0.52), Vector3(1.8, 6.86, 0.0), Color(0.18, 0.19, 0.19), 0.48, 0.44)
	var lens := _add_box(root, "LampLens", Vector3(0.56, 0.035, 0.4), Vector3(1.8, 6.7, 0.0), Color(1.0, 0.78, 0.44), 0.2)
	lens.material_override = _emissive_material(Color(1.0, 0.72, 0.36), 4.4)
	var light := OmniLight3D.new()
	light.name = "WarmQuayLight"
	light.position = Vector3(1.8, 6.62, 0.0)
	light.light_color = Color(1.0, 0.72, 0.43)
	light.omni_range = 26.0
	light.shadow_enabled = true
	light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	light.set_meta("base_energy", 7.2)
	light.set_meta("base_volume", 1.1)
	root.add_child(light)
	_practical_lights.append(light)


func _build_wall_light(parent: Node3D, position: Vector3) -> void:
	var housing := _add_box(
		parent, "WallLightHousing", Vector3(0.24, 0.62, 1.25),
		position, Color(0.10, 0.11, 0.12), 0.54, 0.25
	)
	housing.position.x += 0.02
	var lens := _add_box(
		parent, "WallLightLens", Vector3(0.06, 0.38, 0.84),
		position + Vector3(0.15, -0.03, 0.0), Color(1.0, 0.76, 0.42), 0.18
	)
	lens.material_override = _emissive_material(Color(1.0, 0.68, 0.32), 5.2)
	var light := OmniLight3D.new()
	light.name = "WarehouseWorkLight"
	light.position = position + Vector3(0.65, -0.4, 0.0)
	light.light_color = Color(1.0, 0.67, 0.36)
	light.omni_range = 15.0
	light.shadow_enabled = false
	light.set_meta("base_energy", 5.8)
	light.set_meta("base_volume", 0.72)
	parent.add_child(light)
	_practical_lights.append(light)


func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.26
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _build_quay_details() -> void:
	for z in range(-48, 49, 12):
		var bollard := MeshBuilder.cylinder(0.24, 0.75, Color(0.12, 0.13, 0.13), 0.56, 0.58)
		bollard.name = "Bollard"
		bollard.position = Vector3(8.8, DECK_Y + 0.38, float(z))
		add_child(bollard)
	for z in [-40.0, -32.0, 20.0, 28.0, 36.0]:
		var container := Node3D.new()
		container.name = "CargoUnit"
		container.position = Vector3(-22.0, DECK_Y, z)
		add_child(container)
		_add_box(container, "Body", Vector3(2.45, 2.55, 6.05), Vector3.ZERO + Vector3.UP * 1.275, Color(0.12, 0.26, 0.38), 0.82)
		for rib in [-2.4, -1.2, 0.0, 1.2, 2.4]:
			_add_box(container, "Rib", Vector3(2.52, 2.62, 0.065), Vector3(0.0, 1.31, rib), Color(0.08, 0.17, 0.24), 0.76)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "ReviewCamera"
	_camera.current = true
	_camera.near = 0.25
	_camera.far = 6000.0
	add_child(_camera)
	_apply_camera()


func _apply_camera() -> void:
	if _camera == null:
		return
	var preset := CAMERAS[camera_index]
	_camera.position = preset["position"] as Vector3
	_camera.fov = float(preset["fov"])
	_camera.look_at(preset["target"] as Vector3, Vector3.UP)
	_update_hud()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ReviewHUD"
	layer.layer = 20
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(22.0, 22.0)
	panel.custom_minimum_size = Vector2(366.0, 0.0)
	layer.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.027, 0.036, 0.91)
	style.border_color = Color(0.76, 0.42, 0.19, 0.88)
	style.set_border_width_all(1)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	_hud_title = Label.new()
	_hud_title.add_theme_font_size_override("font_size", 24)
	_hud_title.add_theme_color_override("font_color", Color(0.96, 0.91, 0.82))
	column.add_child(_hud_title)
	_hud_detail = Label.new()
	_hud_detail.add_theme_font_size_override("font_size", 13)
	_hud_detail.add_theme_color_override("font_color", Color(0.68, 0.74, 0.78))
	column.add_child(_hud_detail)
	var controls := Label.new()
	controls.text = "1-4 time of day   Q / E weather   C camera   Esc quit"
	controls.add_theme_font_size_override("font_size", 12)
	controls.add_theme_color_override("font_color", Color(0.88, 0.48, 0.24))
	column.add_child(controls)
	_update_hud()


func _apply_review_state() -> void:
	var clock := get_node_or_null("/root/WorldClock")
	if clock != null and clock.has_method("snap_time_of_day"):
		clock.call("snap_time_of_day", float(TIMES[time_index]["fraction"]))
	var weather := get_node_or_null("/root/WeatherLighting") as WeatherLightingState
	if weather != null:
		weather.apply_weather_state(_weather_state(WEATHER[weather_index]))
	_apply_camera()
	_update_hud()


func _weather_state(spec: Dictionary) -> WeatherState:
	var state := WeatherState.new()
	state.precipitation = float(spec["precipitation"])
	state.wind_force = float(spec["wind"])
	state.wind_speed_ms = state.wind_force * 22.0
	state.visibility = float(spec["visibility"])
	state.cloud_cover = float(spec["cloud"])
	state.sea_state = float(spec["sea"])
	state.significant_wave_height_m = float(spec["wave_height"])
	state.wind_direction = Vector3(-0.72, 0.0, 0.69).normalized()
	state.exposure = 1.0
	state.humidity = clampf(0.36 + state.precipitation * 0.58 + (1.0 - state.visibility) * 0.45, 0.0, 1.0)
	state.zone_label = str(spec["label"])
	state.weather_cell_id = "showcase:%s" % str(spec["label"]).to_lower().replace(" ", "_")
	return state


func _update_hud() -> void:
	if _hud_title == null or _hud_detail == null:
		return
	var time := TIMES[time_index]
	var weather := WEATHER[weather_index]
	var camera := CAMERAS[camera_index]
	_hud_title.text = "%s  ·  %s" % [str(time["label"]), str(time["clock"])]
	_hud_detail.text = "%s  ·  %s\nReal WorldRenderer / WeatherLighting presentation" % [
		str(weather["label"]), str(camera["label"])
	]


func _capture_review_series() -> void:
	var output_dir := ProjectSettings.globalize_path("user://world_lighting_review")
	DirAccess.make_dir_recursive_absolute(output_dir)
	await get_tree().create_timer(1.5).timeout
	for spec in CANONICAL_REVIEW:
		time_index = int(spec["time"])
		weather_index = int(spec["weather"])
		camera_index = int(spec["camera"])
		_apply_review_state()
		# Let temporal VFX finish their previous state before documenting the
		# next one. In particular, stopped rain particles remain alive for their
		# 1.2 second lifetime even though no new particles are emitted.
		await get_tree().create_timer(1.35).timeout
		for frame in range(3):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := "%s/%s.png" % [output_dir, str(spec["slug"])]
		var error := image.save_png(path)
		if error != OK:
			push_error("WorldLightingShowcase: could not save %s (%s)" % [path, error])
		else:
			print("WORLD_LIGHTING_CAPTURE ", path)
	get_tree().quit()


func _add_box(
		parent: Node3D,
		label: String,
		size: Vector3,
		position: Vector3,
		color: Color,
		roughness := 0.85,
		metallic := 0.0,
) -> MeshInstance3D:
	var mesh := MeshBuilder.box(size, color, roughness, metallic)
	mesh.name = label
	mesh.position = position
	parent.add_child(mesh)
	return mesh


func _add_prism_roof(parent: Node3D, size: Vector3, position: Vector3) -> void:
	var roof := MeshBuilder.prism(size, Color(0.13, 0.14, 0.15), 0.87, 0.06)
	roof.name = "WarehouseRoof"
	roof.position = position
	roof.rotation_degrees.y = 90.0
	parent.add_child(roof)
