class_name GullFlock
extends Node3D
## Bounded flock renderer. Each bird has a profile and steering state.
@export_range(1, 64) var bird_count := 16
@export var flock_seed := 761
@export_range(0.5, 12.0) var mean_age := 4.0
@export_range(0.75, 1.25) var mean_size := 1.0
@export_range(0.0, 1.0) var variation := 0.65
@export_range(0.3, 2.0) var flap_rate_scale := 1.0
var simulation := GullFlockSimulation.new()
var paused := false
## Water breaks are opt-in until the habitat provider has selected open water.
@export var water_rest_enabled := false
@export_range(60.0, 1800.0) var rest_duration_seconds := 240.0
@export_range(60.0, 1800.0) var flight_duration_seconds := 180.0
var water_sample_provider: Callable
var can_land_provider: Callable
var calls_enabled := true:
	set(value):
		calls_enabled = value
		for bird in _birds: bird.calls.enabled = value
var _next_water_break := 2.0
var _water_bird_index := 0
var _birds: Array[CoastalGull] = []

func _ready() -> void:
	rebuild()

func rebuild() -> void:
	for bird in _birds:
		remove_child(bird)
		bird.queue_free()
	_birds.clear()
	simulation.configure(bird_count, flock_seed, mean_age, mean_size, variation)
	_next_water_break = 2.0
	_water_bird_index = 0
	for profile in simulation.profiles:
		profile.flap_hz *= flap_rate_scale
		var bird := CoastalGull.new()
		bird.profile = profile
		add_child(bird)
		bird.calls.enabled = calls_enabled
		_birds.append(bird)
	_refresh(0.0)

func update_appearance() -> void:
	for i in _birds.size():
		var profile := GullProfile.seeded(flock_seed, i, mean_age, mean_size, variation)
		profile.flap_hz *= flap_rate_scale
		simulation.profiles[i] = profile
		_birds[i].apply_profile(profile)

func _process(delta: float) -> void:
	if not visible or paused:
		return
	simulation.advance(delta)
	if water_rest_enabled and simulation.time_seconds >= _next_water_break:
		_request_next_water_break()
		_next_water_break = simulation.time_seconds + 3.0
	_refresh(delta)

func _request_next_water_break() -> void:
	if _birds.is_empty():
		return
	var i := _water_bird_index % _birds.size()
	_water_bird_index += 1
	var water := simulation.water_behaviours[i]
	if water.stage != GullWaterBehaviour.Stage.FLYING or water.elapsed < flight_duration_seconds * (0.8 + float(i % 5) * 0.1):
		return
	var p := simulation.positions[i]
	var v := simulation.velocities[i]
	var target := p + Vector3(v.x, 0, v.z).normalized() * 14.0
	var world_target := to_global(target)
	world_target.y = WaveSurface.WATER_LEVEL
	if can_land_provider.is_valid() and not bool(can_land_provider.call(world_target)):
		return
	simulation.request_water_rest(i, to_local(world_target), rest_duration_seconds * (0.8 + 0.4 * float(i % 5) / 4.0))

## Call from local authority, or apply a server-approved disturbance/checkpoint.
## Replicated clients must not independently choose different scare outcomes.
func react_to_vessel(world_position: Vector3, world_velocity: Vector3, hull_radius: float = 0.0, clearance: float = 12.0) -> Array[int]:
	return simulation.react_to_vessel(to_local(world_position), global_basis.inverse() * world_velocity, hull_radius, clearance)

func water_sample(at: Vector3) -> WaterSample:
	if water_sample_provider.is_valid():
		return water_sample_provider.call(at.x, at.z) as WaterSample
	return WaveSurface.sample_at(at.x, at.z)

func _refresh(delta: float) -> void:
	for i in _birds.size():
		var bird := _birds[i]
		bird.position = simulation.previous_positions[i].lerp(simulation.positions[i], simulation.interpolation())
		var v := simulation.velocities[i]
		var water := simulation.water_behaviours[i]
		bird.update_audio(simulation.time_seconds, water)
		if water.stage != GullWaterBehaviour.Stage.FLYING:
			_apply_water_pose(bird, water, v, delta)
			continue
		if v.length_squared() > 0.01:
			var current_forward := -bird.basis.z
			var turn := current_forward.cross(v.normalized()).y
			var desired := Basis.looking_at(v.normalized(), Vector3.UP).rotated(v.normalized(), clampf(-turn * 2.0, -0.45, 0.45))
			bird.quaternion = bird.quaternion.slerp(desired.get_rotation_quaternion(), 1.0 - exp(-delta * 5.0)) if delta > 0 else desired.get_rotation_quaternion()
		var glide := smoothstep(0.3, 0.8, sin(simulation.time_seconds * 0.55 + bird.profile.phase_offset))
		bird.pose(simulation.time_seconds, glide)

func _apply_water_pose(bird: CoastalGull, water: GullWaterBehaviour, v: Vector3, delta: float) -> void:
	var at := bird.global_position
	var weight := water.water_weight()
	var sample := water_sample(at)
	# Follow height directly: smoothing wave height would make a small bird sink
	# into a rising crest. Only roll/pitch is damped.
	at.y += (sample.height - WaveSurface.WATER_LEVEL) * weight
	at.y += 0.012 * bird.profile.size_scale * weight
	bird.global_position = at
	var forward := global_basis * (v.normalized() if v.length_squared() > 0.01 else water.heading)
	var flight_basis := Basis.looking_at(forward, Vector3.UP)
	var floating_basis := CoastalGull.water_basis(global_basis * water.heading, sample.normal)
	var desired := flight_basis.get_rotation_quaternion().slerp(floating_basis.get_rotation_quaternion(), weight)
	var current := bird.global_basis.get_rotation_quaternion()
	bird.global_basis = Basis(current.slerp(desired, 1.0 - exp(-delta * 8.0)) if delta > 0.0 else desired)
	bird.pose_water(simulation.time_seconds, water)
