extends Node3D

var _hold: CatchHoldComponent
var _label: Label
var _lot_serial := 0


func _ready() -> void:
	_build_environment()
	_hold = CatchHoldComponent.new()
	_hold.name = "CatchHold"
	_hold.configure("showcase_hold", 4000.0)
	add_child(_hold)
	_hold.fill_changed.connect(_refresh_label)
	_build_ui()
	_add_catch(1000.0)
	_refresh_label(_hold.state)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_SPACE:
		_add_catch(500.0)
	elif event.keycode in [KEY_BACKSPACE, KEY_DELETE]:
		_hold.withdraw_oldest(500.0)
	elif event.keycode == KEY_R:
		_hold.withdraw_oldest(_hold.state.total_mass_kg())


func _add_catch(mass_kg: float) -> void:
	_lot_serial += 1
	_hold.accept_lot(CatchLot.create({
		"lot_id": "showcase-%d" % _lot_serial,
		"mass_kg": mass_kg,
		"caught_game_hours": float(_lot_serial),
		"ground_tier": "rich",
		"price_multiplier": 1.75,
	}))


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.075, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.50, 0.58)
	env.ambient_light_energy = 0.75
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_energy = 1.3
	add_child(sun)
	var deck := MeshBuilder.box(Vector3(9.0, 0.22, 8.0), Color(0.18, 0.15, 0.11), 0.9)
	deck.position.y = -0.14
	add_child(deck)
	var camera := Camera3D.new()
	camera.position = Vector3(6.5, 5.4, 7.2)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.1, 0.0))
	add_child(camera)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(24.0, 24.0)
	_label.add_theme_font_size_override("font_size", 18)
	layer.add_child(_label)


func _refresh_label(_state: CatchHoldState) -> void:
	if _label == null or _hold == null:
		return
	var quote := FishingLandingService.quote([_hold.state])
	_label.text = (
		"INSULATED CATCH HOLD\n"
		+ "%.1f / %.1f t  |  %d%% full  |  market value %d marks\n"
		+ "SPACE add 500 kg  |  BACKSPACE unload 500 kg  |  R empty"
	) % [
		_hold.state.total_mass_kg() / 1000.0,
		_hold.state.capacity_kg / 1000.0,
		int(round(_hold.state.fill_ratio() * 100.0)),
		int(quote.get("value_marks", 0)),
	]
