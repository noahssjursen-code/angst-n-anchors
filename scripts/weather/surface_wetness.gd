class_name SurfaceWetness
extends RefCounted

## Local presentation only, driven by the same supported rain as RainField.
## Opt-in ground materials; never infer exposure from a ship material's name.
## Weak registrations do not keep streamed terrain or edited finishes alive.
static var amount := 0.0
static var _materials: Dictionary = {}

static func target(rain: float) -> float:
	return smoothstep(0.02, 0.65, rain)

static func advance(rain: float, delta: float) -> void:
	var desired := target(rain)
	# Visible dampening over tens of seconds; clearing skies do not instantly
	# dry the quay. Wall time, independent of the accelerated world clock.
	var rate := (0.016 + 0.05 * rain) if desired > amount else 0.004
	set_amount(lerpf(amount, desired, 1.0 - exp(-maxf(delta, 0.0) * rate)))

static func register_material(material: ShaderMaterial) -> void:
	_materials[material.get_instance_id()] = weakref(material)
	material.set_shader_parameter("rain_wetness", amount)

static func set_amount(value: float) -> void:
	var next := clampf(value, 0.0, 1.0)
	if is_equal_approx(next, amount): return
	amount = next
	Palette.set_wetness(amount)
	for id in _materials.keys():
		var material := (_materials[id] as WeakRef).get_ref() as ShaderMaterial
		if material == null:
			_materials.erase(id)
		else:
			material.set_shader_parameter("rain_wetness", amount)
