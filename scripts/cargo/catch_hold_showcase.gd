extends Node3D

var _hold: CatchHoldComponent
var _label: Label
var _lot_serial := 0


func _ready() -> void:
	_hold = CatchHoldComponent.new()
	_hold.name = "CatchHold"
	_hold.configure("showcase_hold", 4000.0)
	add_child(_hold)
	## AFTER the hold, because the deck around it is cut to the hold's own
	## aperture. It used to be one 9 x 8 m slab spanning everything, which is
	## the same defect the hull's deck plate had: with the hatch open the slab
	## stood between the camera and the catch at every fill below brimful.
	_build_environment()
	## THE HATCH STARTS OPEN HERE, and that is the whole point of this scene.
	## This showcase exists to display fill stages; from `bd548bc` until the
	## hatch could be worked it displayed a closed lid and nothing else. A hold
	## on a vessel starts closed, as a hold at sea would.
	_hold.set_hatch_open(true)
	_hold.fill_changed.connect(_refresh_label)
	_hold.hatch_changed.connect(_on_hatch_changed)
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
	elif event.keycode == KEY_H:
		_hold.toggle_hatch()


func _on_hatch_changed(_open: bool) -> void:
	_refresh_label(_hold.state)


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
	var hole := _hold.hatch_aperture_m()
	var deck_c := Color(0.18, 0.15, 0.11)
	for panel in [
		[Vector3(9.0, 0.22, 4.0 - hole.end.y), Vector3(0.0, -0.14, (4.0 + hole.end.y) * 0.5)],
		[Vector3(9.0, 0.22, 4.0 + hole.position.y), Vector3(0.0, -0.14, (-4.0 + hole.position.y) * 0.5)],
		[Vector3(4.5 + hole.position.x, 0.22, hole.size.y),
			Vector3((-4.5 + hole.position.x) * 0.5, -0.14, hole.get_center().y)],
		[Vector3(4.5 - hole.end.x, 0.22, hole.size.y),
			Vector3((4.5 + hole.end.x) * 0.5, -0.14, hole.get_center().y)],
	]:
		var deck := MeshBuilder.box(panel[0] as Vector3, deck_c, 0.9)
		deck.position = panel[1] as Vector3
		add_child(deck)
	## STEEPER THAN IT WAS, and the angle is derived rather than composed. This
	## scene's job is showing fill stages, and the hatch opens into slots one
	## board wide (0.54 m on the default footprint) because a slot wider than
	## that is a slot a 0.70 m player capsule falls through. You can only see a
	## surface `d` metres down a `w` metre slot from above atan(d/w): the chilled
	## water sits 1.08 m below the boards when the hold is empty, so anything
	## shallower than ~63 degrees photographs the liner and calls it a fill stage.
	## The old pose was 28.6 degrees and would have shown a white box at every
	## stage below brimful.
	var camera := Camera3D.new()
	camera.fov = 45.0
	camera.position = Vector3(1.6, 4.4, 1.8)
	camera.look_at_from_position(camera.position, Vector3(0.0, -0.35, 0.0))
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
		+ "%.1f / %.1f t  |  %d%% full  |  market value %d marks  |  hatch %s\n"
		+ "SPACE add 500 kg  |  BACKSPACE unload 500 kg  |  R empty  |  H work the hatch"
	) % [
		_hold.state.total_mass_kg() / 1000.0,
		_hold.state.capacity_kg / 1000.0,
		int(round(_hold.state.fill_ratio() * 100.0)),
		int(quote.get("value_marks", 0)),
		"OPEN" if _hold.is_hatch_open() else "CLOSED",
	]
