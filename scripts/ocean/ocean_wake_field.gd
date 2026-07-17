class_name OceanWakeField
extends Node

## Client-local persistent visual wake atlas. It never participates in
## WaveSurface physics queries.

const WAKE_SHADER := preload("res://resources/shaders/ocean_wake_update.glsl")
const RESOLUTION := 1024
const WORLD_EXTENT_M := 2048.0
const UPDATE_HZ := 30.0
const UPDATE_STEP := 1.0 / UPDATE_HZ
const MAX_EMITTERS := 8
const EMITTER_FLOATS := 16
const EMITTER_BYTES := EMITTER_FLOATS * 4
const STALE_SECONDS := 0.25
## Remap only after the camera has moved this many wake texels. Frequent
## 1-texel origin crawls make the trail jitter against the clipmap ocean.
const ORIGIN_SNAP_TEXELS := 48

var rd: RenderingDevice
var wake_texture_rd: Texture2DRD

var _textures: Array[RID] = []
var _uniform_sets: Array[RID] = []
var _shader: RID
var _pipeline: RID
var _emitter_buffer: RID
var _push := PackedByteArray()
var _emitters: Dictionary = {}
var _timer := 0.0
var _current_index := 0
var _focus_xz := Vector2.ZERO
var _current_origin := Vector2.ZERO
var _previous_origin := Vector2.ZERO
var _origin_initialized := false
var _active_emitters := 0
var _stamped_segments := 0
var _cpu_update_ms := 0.0
var _gpu_update_ms := -1.0
var _last_local_strength := 0.0


func _ready() -> void:
	add_to_group("ocean_wake_field")
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null and telemetry.has_method("register_provider"):
		telemetry.register_provider(&"ocean.wake", self, &"get_debug_stats", &"ocean", {
			"memory_mb": {"unit": "MB"},
			"cpu_update_ms": {"unit": "ms"},
			"gpu_update_ms": {"unit": "ms"},
		})
	_push.resize(32)
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		return
	_create_pipeline()
	_create_resources()
	set_process(true)


func _exit_tree() -> void:
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null and telemetry.has_method("unregister_provider"):
		telemetry.unregister_provider(&"ocean.wake", self)
	if rd == null:
		return
	if wake_texture_rd != null:
		wake_texture_rd.texture_rd_rid = RID()
	for uniform_set in _uniform_sets:
		_free_rid(uniform_set)
	_free_rid(_pipeline)
	_free_rid(_emitter_buffer)
	for texture in _textures:
		_free_rid(texture)
	_free_rid(_shader)
	_uniform_sets.clear()
	_textures.clear()


func set_focus(world_xz: Vector2) -> void:
	_focus_xz = world_xz


static func world_to_uv(
	world_xz: Vector2, origin: Vector2, extent_m: float
) -> Vector2:
	return (world_xz - origin) / maxf(extent_m, 0.001)


static func is_teleport_segment(
	previous: Vector2, current: Vector2, half_beam_m: float
) -> bool:
	return previous.distance_to(current) > maxf(80.0, half_beam_m * 10.0)


static func decayed_channel(value: float, delta: float, time_constant: float) -> float:
	return value * exp(-maxf(delta, 0.0) / maxf(time_constant, 0.001))


static func calculate_strength(
	thrust_n: float,
	vessel_mass_kg: float,
	speed_ms: float,
	throttle_value: float,
	propeller_immersion: float,
) -> Vector2:
	var thrust_to_weight := absf(thrust_n) / maxf(vessel_mass_kg * 9.81, 1.0)
	# Authored propeller Y is often above the true screw depth. Fully dry
	# (well above water) still kills wash; slightly high markers still emit.
	var immersion := smoothstep(-0.55, 0.25, propeller_immersion)
	var foam := clampf(
		thrust_to_weight * 8.0
		+ absf(throttle_value) * 0.28
		+ speed_ms * 0.03,
		0.0,
		1.0
	) * immersion
	var churn := clampf(
		thrust_to_weight * 10.0
		+ absf(throttle_value) * 0.35
		+ speed_ms * 0.04,
		0.0,
		1.0
	) * immersion
	return Vector2(foam, churn)


static func calculate_trailing_axis(
	body_stern_axis: Vector2, throttle_value: float
) -> Vector2:
	var stern := body_stern_axis.normalized()
	if stern.length_squared() < 0.5:
		stern = Vector2.DOWN
	return stern * -signf(throttle_value)


## Generic seam used by local propulsion and remote interpolated vessels.
func submit_emitter(
	emitter_id: String,
	world_position: Vector2,
	trailing_axis: Vector2,
	half_beam_m: float,
	speed_ms: float,
	foam_strength: float,
	churn_strength: float,
	priority: float = 10.0,
) -> void:
	if emitter_id.is_empty():
		return
	var now_usec := Time.get_ticks_usec()
	var axis := trailing_axis.normalized()
	if axis.length_squared() < 0.5:
		axis = Vector2.DOWN
	var record: Dictionary = _emitters.get(emitter_id, {})
	if record.is_empty():
		record = {
			"position": world_position,
			"consumed_position": world_position,
			"teleport": false,
		}
	var consumed: Vector2 = record.get("consumed_position", world_position)
	var teleported := is_teleport_segment(consumed, world_position, half_beam_m)
	if teleported:
		consumed = world_position
	record["position"] = world_position
	record["consumed_position"] = consumed
	record["axis"] = axis
	record["half_beam"] = maxf(half_beam_m, 0.5)
	record["speed"] = maxf(speed_ms, 0.0)
	record["foam"] = clampf(foam_strength, 0.0, 1.0)
	record["churn"] = clampf(churn_strength, 0.0, 1.0)
	record["priority"] = priority
	record["last_usec"] = now_usec
	record["teleport"] = teleported
	_emitters[emitter_id] = record


func remove_emitter(emitter_id: String) -> void:
	_emitters.erase(emitter_id)


func get_wake_texture() -> Texture2DRD:
	return wake_texture_rd


func get_world_origin() -> Vector2:
	return _current_origin


func get_world_extent() -> float:
	return WORLD_EXTENT_M


static func compute_locked_origin(
	focus_xz: Vector2,
	current_origin: Vector2,
	origin_initialized: bool,
) -> Vector2:
	var texel_m := WORLD_EXTENT_M / float(RESOLUTION)
	var snap_m := texel_m * float(ORIGIN_SNAP_TEXELS)
	var desired := focus_xz - Vector2.ONE * WORLD_EXTENT_M * 0.5
	desired.x = snappedf(desired.x, snap_m)
	desired.y = snappedf(desired.y, snap_m)
	if not origin_initialized:
		return desired
	if (
		absf(desired.x - current_origin.x) >= snap_m * 0.5
		or absf(desired.y - current_origin.y) >= snap_m * 0.5
	):
		return desired
	return current_origin


func get_debug_stats() -> Dictionary:
	return {
		"resolution": RESOLUTION,
		"extent_m": WORLD_EXTENT_M,
		"update_hz": UPDATE_HZ,
		"active_emitters": _active_emitters,
		"stamped_segments": _stamped_segments,
		"memory_mb": float(RESOLUTION * RESOLUTION * 4 * 2) / (1024.0 * 1024.0),
		"cpu_update_ms": _cpu_update_ms,
		"gpu_update_ms": _gpu_update_ms,
		"local_strength": _last_local_strength,
	}


func _process(delta: float) -> void:
	if rd == null or _pipeline.is_valid() == false:
		return
	_collect_gpu_profile()
	_timer += delta
	if _timer < UPDATE_STEP:
		return
	var step := minf(_timer, 0.1)
	_timer = 0.0
	_update_wake(step)


func _create_pipeline() -> void:
	var versions := WAKE_SHADER.get_version_list()
	var version := &""
	if not versions.is_empty():
		version = versions[0]
	var spirv := WAKE_SHADER.get_spirv(version)
	_shader = rd.shader_create_from_spirv(spirv)
	_pipeline = rd.compute_pipeline_create(_shader)


func _create_resources() -> void:
	var format := RDTextureFormat.new()
	format.width = RESOLUTION
	format.height = RESOLUTION
	format.depth = 1
	format.array_layers = 1
	format.mipmaps = 1
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.format = RenderingDevice.DATA_FORMAT_R16G16_SFLOAT
	format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	var zeroes := PackedByteArray()
	zeroes.resize(RESOLUTION * RESOLUTION * 4)
	zeroes.fill(0)
	for _i in range(2):
		_textures.append(rd.texture_create(format, RDTextureView.new(), [zeroes]))

	var emitter_bytes := PackedByteArray()
	emitter_bytes.resize(MAX_EMITTERS * EMITTER_BYTES)
	emitter_bytes.fill(0)
	_emitter_buffer = rd.storage_buffer_create(emitter_bytes.size(), emitter_bytes)

	_uniform_sets.append(_make_uniform_set(_textures[0], _textures[1]))
	_uniform_sets.append(_make_uniform_set(_textures[1], _textures[0]))
	wake_texture_rd = Texture2DRD.new()
	wake_texture_rd.texture_rd_rid = _textures[0]


func _make_uniform_set(input_texture: RID, output_texture: RID) -> RID:
	var uniforms: Array[RDUniform] = []
	var input := RDUniform.new()
	input.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	input.binding = 0
	input.add_id(input_texture)
	uniforms.append(input)
	var output := RDUniform.new()
	output.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output.binding = 1
	output.add_id(output_texture)
	uniforms.append(output)
	var emitters := RDUniform.new()
	emitters.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	emitters.binding = 2
	emitters.add_id(_emitter_buffer)
	uniforms.append(emitters)
	return rd.uniform_set_create(uniforms, _shader, 0)


func _update_wake(delta: float) -> void:
	var cpu_begin := Time.get_ticks_usec()
	var desired_origin := compute_locked_origin(
		_focus_xz, _current_origin, _origin_initialized
	)
	if not _origin_initialized:
		_current_origin = desired_origin
		_previous_origin = desired_origin
		_origin_initialized = true
	else:
		_previous_origin = _current_origin
		_current_origin = desired_origin

	var packed := _pack_emitters()
	rd.buffer_update(_emitter_buffer, 0, packed.size(), packed)
	_push.encode_float(0, _current_origin.x)
	_push.encode_float(4, _current_origin.y)
	_push.encode_float(8, _previous_origin.x)
	_push.encode_float(12, _previous_origin.y)
	_push.encode_float(16, WORLD_EXTENT_M)
	_push.encode_float(20, delta)
	_push.encode_u32(24, RESOLUTION)
	_push.encode_u32(28, _active_emitters)

	var profile := _profile_enabled()
	if profile:
		rd.capture_timestamp("OceanWake.Begin")
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
	rd.compute_list_bind_uniform_set(compute_list, _uniform_sets[_current_index], 0)
	rd.compute_list_set_push_constant(compute_list, _push, _push.size())
	rd.compute_list_dispatch(compute_list, RESOLUTION / 8, RESOLUTION / 8, 1)
	rd.compute_list_end()
	if profile:
		rd.capture_timestamp("OceanWake.End")

	_current_index = 1 - _current_index
	wake_texture_rd.texture_rd_rid = _textures[_current_index]
	_cpu_update_ms = lerpf(
		_cpu_update_ms,
		float(Time.get_ticks_usec() - cpu_begin) / 1000.0,
		0.2
	)


func _pack_emitters() -> PackedByteArray:
	var now_usec := Time.get_ticks_usec()
	var candidates: Array[Dictionary] = []
	for emitter_id in _emitters.keys().duplicate():
		var record := _emitters[emitter_id] as Dictionary
		var age := float(now_usec - int(record.get("last_usec", 0))) / 1_000_000.0
		if age > 2.0:
			_emitters.erase(emitter_id)
			continue
		var emitter_position: Vector2 = record.get("position", Vector2.INF)
		if (
			age <= STALE_SECONDS
			and emitter_position.distance_to(_focus_xz) <= WORLD_EXTENT_M * 0.72
		):
			record["id"] = str(emitter_id)
			candidates.append(record)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("priority", 0.0)) > float(b.get("priority", 0.0))
	)

	var bytes := PackedByteArray()
	bytes.resize(MAX_EMITTERS * EMITTER_BYTES)
	bytes.fill(0)
	_active_emitters = mini(candidates.size(), MAX_EMITTERS)
	_stamped_segments = 0
	_last_local_strength = 0.0
	for i in range(_active_emitters):
		var record := candidates[i]
		var previous: Vector2 = record["consumed_position"]
		var current: Vector2 = record["position"]
		var axis: Vector2 = record["axis"]
		var half_beam := float(record["half_beam"])
		var speed := float(record["speed"])
		var foam := float(record["foam"])
		var churn := float(record["churn"])
		var teleported := bool(record["teleport"])
		var base := i * EMITTER_BYTES
		var values := PackedFloat32Array([
			previous.x, previous.y, current.x, current.y,
			axis.x, axis.y, half_beam, speed,
			foam, churn, 1.0, float(record["priority"]),
			maxf(half_beam * 8.0, 30.0 + speed * 10.0),
			1.0 if teleported else 0.0, 0.0, 0.0,
		])
		for j in range(EMITTER_FLOATS):
			bytes.encode_float(base + j * 4, values[j])
		record["consumed_position"] = current
		record["teleport"] = false
		_emitters[str(record["id"])] = record
		if not teleported and maxf(foam, churn) > 0.001:
			_stamped_segments += 1
		if float(record["priority"]) >= 100.0:
			_last_local_strength = maxf(_last_local_strength, maxf(foam, churn))
	return bytes


func _collect_gpu_profile() -> void:
	if not _profile_enabled():
		return
	for i in range(rd.get_captured_timestamps_count()):
		if rd.get_captured_timestamp_name(i) != "OceanWake.Begin":
			continue
		if i + 1 >= rd.get_captured_timestamps_count():
			continue
		if rd.get_captured_timestamp_name(i + 1) != "OceanWake.End":
			continue
		var begin := int(rd.get_captured_timestamp_gpu_time(i))
		var finish := int(rd.get_captured_timestamp_gpu_time(i + 1))
		var sample_ms := float(finish - begin) / 1_000_000.0
		if sample_ms >= 0.0 and sample_ms < 20.0:
			_gpu_update_ms = (
				sample_ms if _gpu_update_ms < 0.0
				else lerpf(_gpu_update_ms, sample_ms, 0.2)
			)


func _profile_enabled() -> bool:
	var hud := get_node_or_null("/root/DebugHud")
	return (
		hud != null
		and hud.has_method("is_open")
		and bool(hud.call("is_open"))
	)


func _free_rid(rid: RID) -> void:
	if rid.is_valid():
		rd.free_rid(rid)
