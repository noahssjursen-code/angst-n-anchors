extends Camera3D

## Detached construction camera. Its height never enters a placement record.
@export var move_speed := 18.0
@export var fast_multiplier := 3.0
@export var slow_multiplier := .25
@export var mouse_sensitivity := .0015
var flying := false
var minimum_y := 1.0
var _held: Dictionary = {}

func reset_from(source: Camera3D, deck_y: float) -> void:
	global_transform = source.global_transform
	minimum_y = deck_y + 1.0
	global_position.y = maxf(source.global_position.y + 8.0, deck_y + 10.0)
	rotation = Vector3(deg_to_rad(-35.0), source.global_rotation.y, 0.0)
	fov = source.fov
	far = source.far
	near = .08
	reset_physics_interpolation()

func set_flying(enabled: bool) -> void:
	flying = enabled
	_held.clear()

func handle_input(event: InputEvent) -> bool:
	if not flying: return false
	if event is InputEventKey:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key in [KEY_W, KEY_S, KEY_A, KEY_D, KEY_Q, KEY_E, KEY_SHIFT, KEY_CTRL]:
			if event.pressed: _held[key] = true
			else: _held.erase(key)
			return true
	if event is InputEventMouseMotion:
		var sensitivity := mouse_sensitivity * float(GameSettings.mouse_sensitivity)
		var invert := -1.0 if GameSettings.invert_mouse_y else 1.0
		rotation.y = wrapf(rotation.y - event.relative.x * sensitivity, -PI, PI)
		rotation.x = clampf(rotation.x - event.relative.y * sensitivity * invert, deg_to_rad(-89), deg_to_rad(89))
		return true
	return false

func fly(delta: float) -> void:
	if not flying: return
	var motion := global_basis.x * (float(_held.has(KEY_D)) - float(_held.has(KEY_A)))
	motion += global_basis.z * (float(_held.has(KEY_S)) - float(_held.has(KEY_W)))
	# Q/E always change world height, even while looking straight down.
	motion += Vector3.UP * (float(_held.has(KEY_E)) - float(_held.has(KEY_Q)))
	var speed := move_speed
	if _held.has(KEY_SHIFT): speed *= fast_multiplier
	if _held.has(KEY_CTRL): speed *= slow_multiplier
	global_position += motion.limit_length() * speed * delta
	global_position.y = maxf(global_position.y, minimum_y)
