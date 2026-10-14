extends Node3D
## F6: live model and boids inspector. No world, network, or captain save required.
var _gull: CoastalGull
var _flock: GullFlock
var _camera: Camera3D
var _profile := GullProfile.new()
var _angle := 2.5
var _elevation := 0.28
var _clock := 0.0
var _paused := false
var _mode := 0
var _zoom := 1.8
var _status: Label
var _dragging := false
var _sliders: Dictionary = {}
var _modes: OptionButton
var _studio_env: WorldEnvironment
var _studio_settings: Environment
var _studio_sun: DirectionalLight3D
var _ocean: WorldRenderer
var _ocean_env: WorldEnvironment
var _ocean_settings: Environment
var _water := GullWaterBehaviour.new()
var _rest_seconds := 240.0
var _waves := 0.45
var _water_status: Label
var _calls_on := true
var _call_index := 0
var _call_button: Button

func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var env := WorldEnvironment.new()
	_studio_env = env
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("243b49")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c6dbe6")
	settings.ambient_light_energy = 0.65
	env.environment = settings
	_studio_settings = settings
	add_child(env)
	var sun := DirectionalLight3D.new()
	_studio_sun = sun
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.6
	add_child(sun)
	_gull = CoastalGull.new()
	_gull.profile = _profile
	add_child(_gull)
	_flock = GullFlock.new()
	_flock.visible = false
	add_child(_flock)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.far = 500.0
	add_child(_camera)
	_build_panel()
	if OS.get_cmdline_user_args().has("--capture-gull-rest"):
		call_deferred("_capture_rest")
	elif OS.get_cmdline_user_args().has("--capture-gull-water"):
		call_deferred("_capture_water")
	elif OS.get_cmdline_user_args().has("--capture-gulls"):
		call_deferred("_capture")
	elif OS.get_cmdline_user_args().has("--gull-water"):
		call_deferred("_set_mode", 4)
		await get_tree().create_timer(1.0).timeout
		_play_next_call()

func _build_panel() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(310, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.075, 0.095, 0.96)
	style.set_corner_radius_all(10)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "COASTAL GULLS"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	var desc := Label.new()
	desc.text = "Herring gull · live asset workshop"
	box.add_child(desc)
	var modes := OptionButton.new()
	_modes = modes
	for label in ["Flight cycle", "Gliding", "Folded wings", "Boids flock", "Floating on water", "Land, rest, take off", "Flock water breaks"]:
		modes.add_item(label)
	modes.item_selected.connect(_set_mode)
	box.add_child(modes)
	_slider(box, "Age (years)", 0.5, 8.0, 0.1, 4.0, func(v: float):
		_profile.age_years = v
		_flock.mean_age = v
		_update_appearance())
	_slider(box, "Size", 0.75, 1.25, 0.01, 1.0, func(v: float):
		_profile.size_scale = v
		_flock.mean_size = v
		_update_appearance())
	_slider(box, "Wingbeats / second", 0.5, 3.0, 0.05, 1.65, func(v: float):
		_profile.flap_hz = v
		_flock.flap_rate_scale = v / 1.65
		_flock.update_appearance())
	_slider(box, "Flock count", 1.0, 64.0, 1.0, 16.0, func(v: float):
		_flock.bird_count = int(v)
		_flock.rebuild())
	_slider(box, "Individual variation", 0.0, 1.0, 0.01, 0.65, func(v: float):
		_flock.variation = v
		_flock.update_appearance())
	_slider(box, "Separation (m)", 0.8, 6.0, 0.1, 2.0, func(v: float):
		_flock.simulation.separation_m = v)
	_slider(box, "Cohesion", 0.0, 2.0, 0.05, 0.8, func(v: float):
		_flock.simulation.cohesion = v)
	_slider(box, "Alignment", 0.0, 2.0, 0.05, 1.0, func(v: float):
		_flock.simulation.alignment = v)
	_slider(box, "Water rest (minutes)", 1.0, 10.0, 0.5, 4.0, func(v: float):
		_rest_seconds = v * 60.0
		_water.rest_seconds = _rest_seconds
		_flock.rest_duration_seconds = _rest_seconds)
	_slider(box, "Wave strength", 0.0, 2.0, 0.05, 0.45, func(v: float):
		_waves = v
		if _ocean != null:
			WaveSurface.set_wave_intensity(v))
	var restart := Button.new()
	restart.text = "Land again / take off"
	restart.pressed.connect(func():
		if _mode == 4 or _mode == 5:
			if _water.stage == GullWaterBehaviour.Stage.RESTING:
				_water.take_off()
			else:
				_begin_landing())
	box.add_child(restart)
	var scare := Button.new()
	scare.text = "Startle resting birds"
	scare.pressed.connect(_startle)
	box.add_child(scare)
	_water_status = Label.new()
	box.add_child(_water_status)
	var pause := Button.new()
	pause.text = "Pause / resume · Space"
	pause.pressed.connect(_toggle_pause)
	box.add_child(pause)
	var shuffle := Button.new()
	shuffle.text = "New flock seed"
	shuffle.pressed.connect(func():
		_flock.flock_seed += 1
		_flock.rebuild())
	box.add_child(shuffle)
	_status = Label.new()
	_status.text = "Drag to orbit · wheel to zoom\nAge begins at fledging, not hatchlings."
	box.add_child(_status)
	var calls_toggle := CheckButton.new()
	calls_toggle.text = "Bird calls · spatial audio"
	calls_toggle.button_pressed = true
	calls_toggle.toggled.connect(func(value: bool):
		_calls_on = value
		_sync_audio_enabled())
	box.add_child(calls_toggle)
	_call_button = Button.new()
	_call_button.text = "Hear next call · 12 variations"
	_call_button.pressed.connect(_play_next_call)
	box.add_child(_call_button)

func _sync_audio_enabled() -> void:
	_gull.calls.enabled = _calls_on and not _paused
	_flock.calls_enabled = _calls_on and not _paused

func _play_next_call() -> void:
	var bird := _gull
	if _mode == 3 or _mode == 6:
		bird = _flock.get_child(_call_index % _flock.bird_count) as CoastalGull
	var choices := ["contact", "contact", "contact", "contact", "long", "long", "long", "quiet", "quiet", "quiet", "alarm", "alarm"]
	var variants := [1, 2, 3, 4, 1, 2, 3, 1, 2, 3, 1, 2]
	var index := _call_index % choices.size()
	if bird.calls.play_call(choices[index], variants[index], 1.0, true):
		_call_index += 1
		_call_button.text = "Hear next · played %s %d (%d/12)" % [choices[index], variants[index], index + 1]

func _slider(box: VBoxContainer, label: String, lo: float, hi: float, step: float, value: float, callback: Callable) -> void:
	var caption := Label.new()
	caption.text = "%s   %.2f" % [label, value]
	box.add_child(caption)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.value_changed.connect(func(v: float):
		caption.text = "%s   %.2f" % [label, v]
		callback.call(v))
	box.add_child(slider)
	_sliders[label] = slider

func _update_appearance() -> void:
	_gull.apply_profile(_profile)
	_flock.update_appearance()

func _set_mode(value: int) -> void:
	_mode = value
	_modes.select(value)
	var flock_mode := value == 3 or value == 6
	_gull.visible = not flock_mode
	_flock.visible = flock_mode
	_flock.water_rest_enabled = value == 6
	_zoom = 42.0 if flock_mode else (1.2 if value == 2 else 1.8)
	_gull.transform = Transform3D.IDENTITY
	if value >= 4:
		_ensure_ocean()
		_studio_env.environment = null
		_studio_sun.visible = false
		_ocean_env.environment = _ocean_settings
		_ocean.visible = true
		_ocean.process_mode = Node.PROCESS_MODE_INHERIT
		_ocean.set_ocean_hidden(false)
		_elevation = 0.4
		if value == 4:
			_water.rest_at(Vector3(0, WaveSurface.WATER_LEVEL, 0), Vector3.FORWARD, _rest_seconds, true)
			_water.elapsed = 1.0
		elif value == 5:
			_begin_landing()
		else:
			_flock.rebuild()
			# Show both stable lifestyles immediately without waiting several minutes.
			for i in range(0, _flock.bird_count, 2):
				var at := _flock.simulation.positions[i]
				at.y = WaveSurface.WATER_LEVEL
				var motion := _flock.simulation.water_behaviours[i]
				motion.rest_at(at, _flock.simulation.velocities[i], _rest_seconds * (0.8 + i % 5 * 0.1))
				motion.elapsed = 1.0
				_flock.simulation.positions[i] = at
				_flock.simulation.previous_positions[i] = at
			_flock._refresh(0.0)
	else:
		if _ocean != null:
			_ocean.visible = false
			_ocean.set_ocean_hidden(true)
			_ocean.process_mode = Node.PROCESS_MODE_DISABLED
			_ocean_env.environment = null
		_studio_env.environment = _studio_settings
		_studio_sun.visible = true

func _ensure_ocean() -> void:
	if _ocean != null:
		return
	WorldClock.snap_time_of_day(0.48)
	WaveSurface.set_wave_intensity(_waves)
	_ocean = WorldRenderer.new()
	_ocean.enable_weather_post_fx = false
	_ocean.enable_volumetric_fog = false
	_studio_env.environment = null
	add_child(_ocean)
	for node in _ocean.get_children():
		if node is WorldEnvironment:
			_ocean_env = node
			_ocean_settings = node.environment
			break

func _begin_landing() -> void:
	if _water.stage == GullWaterBehaviour.Stage.FLYING and _water.position.y > 3.0:
		var target := _water.position + _water.heading * 18.0
		target.y = WaveSurface.WATER_LEVEL
		_water.land(_water.position, _water.velocity, target, _rest_seconds, 7.0)
	else:
		_water.land(Vector3(0, 5.5, 12), Vector3(0, -0.5, -5), Vector3(0, WaveSurface.WATER_LEVEL, 0), _rest_seconds, 7.0)

func _startle() -> void:
	if _mode == 6:
		for motion in _flock.simulation.water_behaviours:
			motion.react_to_vessel(motion.position + Vector3(6, 0, 0), Vector3(-3, 0, 0), 2.0)
	elif _mode == 4 or _mode == 5:
		_water.react_to_vessel(_water.position + Vector3(6, 0, 0), Vector3(-3, 0, 0), 2.0)

func _present_water(delta: float) -> void:
	if not _paused:
		_water.advance(delta)
		if _water.stage == GullWaterBehaviour.Stage.FLYING:
			_water.heading = _water.heading.rotated(Vector3.UP, delta * 0.20)
			_water.velocity = _water.heading * 7.0
			_water.position += _water.velocity * delta
			if _mode == 5 and _water.elapsed >= 180.0:
				_begin_landing()
	var sample := WaveSurface.sample_at(_water.position.x, _water.position.z)
	var weight := _water.water_weight()
	_gull.position = _water.position + Vector3.UP * ((sample.height - WaveSurface.WATER_LEVEL) + 0.012 * _profile.size_scale) * weight
	var direction := _water.velocity.normalized() if _water.velocity.length_squared() > 0.01 else _water.heading
	var flight := Basis.looking_at(direction, Vector3.UP).get_rotation_quaternion()
	var afloat := CoastalGull.water_basis(_water.heading, sample.normal).get_rotation_quaternion()
	var desired := flight.slerp(afloat, weight)
	_gull.quaternion = _gull.quaternion.slerp(desired, 1.0 - exp(-delta * 8.0))
	_gull.pose_water(_clock, _water)
	_water_status.text = ["Flying", "Descending · flare at touchdown", "Resting · follows ocean waves", "Taking off"][_water.stage]
	if _water.stage == GullWaterBehaviour.Stage.RESTING:
		_water_status.text = str(_water.rest_activity().name) + " · afloat"
	elif _water.startled and _water.stage == GullWaterBehaviour.Stage.TAKING_OFF:
		_water_status.text = "Startled · escaping approaching vessel"

func _toggle_pause() -> void:
	_paused = not _paused
	_flock.paused = _paused
	_sync_audio_enabled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_toggle_pause()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(_zoom * 0.9, 0.5)
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(_zoom * 1.1, 90.0)
	if event is InputEventMouseMotion and _dragging:
		_angle -= event.relative.x * 0.007
		_elevation = clampf(_elevation + event.relative.y * 0.007, -1.2, 1.4)

func _process(delta: float) -> void:
	if not _paused:
		_clock += delta
	if _mode == 4 or _mode == 5:
		_present_water(delta)
	else:
		_gull.pose(_clock, 1.0 if _mode == 1 else 0.0, _mode == 2)
		_water_status.text = ""
	if not _paused and _gull.visible:
		_gull.update_audio(_clock, _water if _mode == 4 or _mode == 5 else null)
	_angle += (float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))) * delta
	var target := Vector3(0, 11, 0) if _mode == 3 or _mode == 6 else Vector3.ZERO
	if _mode == 4 or _mode == 5:
		target = _gull.position
	_camera.size = _zoom
	_camera.position = target + Vector3(sin(_angle) * cos(_elevation), sin(_elevation), cos(_angle) * cos(_elevation)) * (_zoom * 2.0)
	_camera.look_at(target)
	# Leave the model clear of the control panel at common window aspect ratios.
	_camera.h_offset = -_zoom * 0.20

func _capture() -> void:
	var archive := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(archive)
	var stamp := str(Time.get_unix_time_from_system()).replace(".", "-")
	for mode in [1, 2, 3, 4]:
		_set_mode(mode if mode < 4 else 2)
		if mode == 4:
			_sliders["Age (years)"].value = 0.5
			_sliders["Size"].value = 0.85
		for frame in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := archive.path_join("gull-workshop-%s-mode%d.png" % [stamp, mode])
		get_viewport().get_texture().get_image().save_png(path)
		print("GULL_CAPTURE ", path)
	_set_mode(0)
	_sliders["Age (years)"].value = 4.0
	_sliders["Size"].value = 1.0
	_paused = true
	for i in 24:
		_clock = float(i) / (24.0 * _profile.flap_hz)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(archive.path_join("gull-animation-%s-%02d.png" % [stamp, i]))
	print("GULL_ANIMATION_STAMP ", stamp)
	get_tree().quit()

func _capture_water() -> void:
	var archive := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(archive)
	var stamp := str(Time.get_unix_time_from_system()).replace(".", "-")
	_set_mode(5)
	_zoom = 2.0
	for stage in 3:
		if stage == 1:
			_water.rest_at(Vector3(0, WaveSurface.WATER_LEVEL, 0), Vector3.FORWARD, 60.0)
			_water.elapsed = 1.0
		if stage == 2:
			_water.take_off()
		for frame in 90:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := archive.path_join("gull-water-%s-stage%d.png" % [stamp, stage])
		get_viewport().get_texture().get_image().save_png(path)
		print("GULL_WATER_CAPTURE ", path)
	_set_mode(6)
	var end := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var flock_path := archive.path_join("gull-water-%s-flock.png" % stamp)
	get_viewport().get_texture().get_image().save_png(flock_path)
	print("GULL_WATER_CAPTURE ", flock_path)
	get_tree().quit()

func _capture_rest() -> void:
	var archive := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(archive)
	var stamp := str(Time.get_unix_time_from_system()).replace(".", "-")
	_set_mode(4)
	_zoom = 1.1
	_paused = true
	for frame in 90:
		await get_tree().process_frame
	for action in ["Resting", "Stretching wings", "Lifting neck", "Looking around"]:
		var best := 0.0
		var best_time := 2.0
		for step in 1800:
			_water.elapsed = float(step) * 0.1
			var activity := _water.rest_activity()
			if activity.name != action:
				continue
			var weight := float(activity.wing_stretch) + float(activity.neck_lift) + absf(float(activity.look))
			if weight > best:
				best = weight
				best_time = _water.elapsed
		_water.elapsed = best_time
		_zoom = 1.9 if action == "Stretching wings" else 1.1
		for frame in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := archive.path_join("gull-rest-%s-%s.png" % [stamp, action.to_snake_case()])
		get_viewport().get_texture().get_image().save_png(path)
		print("GULL_REST_CAPTURE ", path)
	get_tree().quit()
