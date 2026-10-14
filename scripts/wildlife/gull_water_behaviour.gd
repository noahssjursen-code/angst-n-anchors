class_name GullWaterBehaviour
extends RefCounted
## Mean-water flight path and behaviour state. Wave displacement is presentation
## only, sampled by GullFlock, so the record does not persist ocean physics.
enum Stage { FLYING, LANDING, RESTING, TAKING_OFF }
var stage := Stage.FLYING
var elapsed := 0.0
var duration := 5.0
var rest_seconds := 240.0
var rest_indefinitely := false
var idle_seed: int = 1
var startled := false
var departure_water_weight := 1.0
var departure_fold := 1.0
var start := Vector3.ZERO
var target := Vector3.ZERO
var start_velocity := Vector3.ZERO
var heading := Vector3.FORWARD
var position := Vector3.ZERO
var velocity := Vector3.ZERO
var cruise_speed := 9.0

func land(from: Vector3, speed: Vector3, water_target: Vector3, rest: float, cruise: float) -> void:
	stage = Stage.LANDING
	elapsed = 0.0
	start = from
	position = from
	start_velocity = speed
	velocity = speed
	target = water_target
	rest_seconds = clampf(rest, 2.0, 1800.0)
	rest_indefinitely = false
	startled = false
	cruise_speed = cruise
	duration = clampf((from.y - water_target.y) / 1.7, 3.5, 9.0)
	heading = Vector3(speed.x, 0, speed.z).normalized()
	if heading.length_squared() < 0.1:
		heading = Vector3.FORWARD

func rest_at(at: Vector3, forward: Vector3, rest: float = 240.0, indefinite: bool = false) -> void:
	stage = Stage.RESTING
	elapsed = 0.0
	position = at
	target = at
	heading = Vector3(forward.x, 0, forward.z).normalized()
	if heading.length_squared() < 0.1:
		heading = Vector3.FORWARD
	velocity = Vector3.ZERO
	rest_seconds = clampf(rest, 2.0, 1800.0)
	rest_indefinitely = indefinite
	startled = false

func take_off(escape_direction: Vector3 = Vector3.ZERO) -> void:
	if stage != Stage.RESTING and stage != Stage.LANDING:
		return
	departure_water_weight = water_weight()
	departure_fold = fold_amount()
	startled = escape_direction.length_squared() > 0.01
	if startled:
		heading = Vector3(escape_direction.x, 0, escape_direction.z).normalized()
	stage = Stage.TAKING_OFF
	elapsed = 0.0
	duration = 2.8 if startled else 4.5
	start = position
	start_velocity = heading * (1.0 if startled else 0.3)
	target = start + heading * 21.0 + Vector3.UP * 8.0

func advance(delta: float) -> void:
	elapsed += delta
	if stage == Stage.FLYING:
		return
	if stage == Stage.RESTING:
		# Stay near the resting patch, rather than swim 24 m during a long rest.
		velocity = (heading * 0.02 + (target - position) * 0.08).limit_length(0.04)
		position += velocity * delta
		if not rest_indefinitely and elapsed >= rest_seconds:
			take_off()
		return
	var t := clampf(elapsed / duration, 0.0, 1.0)
	var a := start_velocity.limit_length(cruise_speed) * duration * 0.55
	var b := heading * 0.25 * duration
	if stage == Stage.LANDING:
		# A long descent must not overshoot its short water approach and reverse.
		var approach := Vector3(target.x - start.x, 0, target.z - start.z)
		var horizontal := Vector3(a.x, 0, a.z).limit_length(approach.length() * 2.0)
		a.x = horizontal.x
		a.z = horizontal.z
	if stage == Stage.TAKING_OFF:
		a = start_velocity * duration
		b = (heading * cruise_speed + Vector3.UP * 1.5) * duration
	position = _hermite(start, target, a, b, t)
	velocity = _derivative(start, target, a, b, t) / duration
	if stage == Stage.LANDING:
		position.y = maxf(position.y, target.y)
	if t >= 1.0:
		if stage == Stage.LANDING:
			rest_at(target, heading, rest_seconds)
		else:
			stage = Stage.FLYING
			elapsed = 0.0

func water_weight() -> float:
	match stage:
		Stage.RESTING: return 1.0
		Stage.LANDING: return 1.0 - smoothstep(0.0, 1.5, position.y - target.y)
		Stage.TAKING_OFF: return departure_water_weight * (1.0 - smoothstep(0.0, 1.5, position.y - start.y))
	return 0.0

func fold_amount() -> float:
	match stage:
		Stage.RESTING: return smoothstep(0.0, 0.65, elapsed) * (1.0 - float(rest_activity().wing_stretch))
		Stage.TAKING_OFF: return departure_fold * (1.0 - smoothstep(0.0, 0.45, elapsed))
	return 0.0

## Pure pose schedule: seed + elapsed time, never rendering-frame random calls.
## Quiet intervals separate each short action; each bird has its own schedule.
func rest_activity() -> Dictionary:
	var pose := {"name": "Resting", "wing_stretch": 0.0, "neck_lift": 0.0, "look": 0.0}
	if stage != Stage.RESTING:
		return pose
	var block := int(floor(elapsed / 28.0))
	var code := posmod((idle_seed + block * 104729) * 48271, 2147483647)
	code = posmod(code * 48271 + 1, 2147483647)
	var begins := 6.0 + float(code % 1200) / 100.0
	var activity := int(code / 1200) % 3
	var length := 5.5 if activity == 0 else 4.5
	var t := (fposmod(elapsed, 28.0) - begins) / length
	if t <= 0.0 or t >= 1.0:
		return pose
	var envelope := smoothstep(0.0, 0.30, t) * (1.0 - smoothstep(0.65, 1.0, t))
	match activity:
		0:
			pose.name = "Stretching wings"
			pose.wing_stretch = envelope
			pose.neck_lift = envelope * 0.35
		1:
			pose.name = "Lifting neck"
			pose.neck_lift = envelope
		2:
			pose.name = "Looking around"
			pose.neck_lift = envelope * 0.25
			pose.look = sin(t * TAU) * envelope * (1.0 if code % 2 == 0 else -1.0)
	return pose

## Authority-side proximity decision, also usable by the isolated workshop.
## Inputs share the behaviour's coordinate frame; no scene/physics dependency.
func react_to_vessel(at: Vector3, vessel_velocity: Vector3, hull_radius: float = 0.0, clearance: float = 12.0) -> bool:
	if stage != Stage.RESTING and stage != Stage.LANDING:
		return false
	if not at.is_finite() or not vessel_velocity.is_finite() or not is_finite(hull_radius) or not is_finite(clearance):
		return false
	var offset := Vector3(position.x - at.x, 0, position.z - at.z)
	var travel := Vector3(vessel_velocity.x, 0, vessel_velocity.z)
	var closest_time := clampf(offset.dot(travel) / travel.length_squared(), 0.0, 2.0) if travel.length_squared() > 0.01 else 0.0
	var miss := offset - travel * closest_time
	var radius := maxf(hull_radius, 0.0) + maxf(clearance, 0.0)
	if offset.length() > radius and miss.length() > radius:
		return false
	# Escape sideways from an oncoming bow, not farther along its path.
	var away := offset.slide(travel.normalized()) if closest_time > 0.0 else offset
	if away.length_squared() < 1.0:
		away = Vector3(-travel.z, 0, travel.x) if travel.length_squared() > 0.01 else heading
	take_off(away.normalized())
	return true

func flare_amount() -> float:
	return water_weight() if stage == Stage.LANDING else 0.0

func to_record() -> Dictionary:
	return {"stage": stage, "elapsed": elapsed, "duration": duration, "rest_seconds": rest_seconds,
		"rest_indefinitely": rest_indefinitely, "idle_seed": idle_seed, "startled": startled,
		"departure_water_weight": departure_water_weight, "departure_fold": departure_fold,
		"start": _array(start), "target": _array(target), "start_velocity": _array(start_velocity),
		"heading": _array(heading), "position": _array(position), "velocity": _array(velocity), "cruise_speed": cruise_speed}

static func from_record(record: Dictionary) -> GullWaterBehaviour:
	var result := GullWaterBehaviour.new()
	var state: Variant = record.get("stage", -1)
	if not (state is int or state is float) or not is_finite(float(state)):
		return null
	if float(state) != floorf(float(state)) or int(state) < 0 or int(state) > Stage.TAKING_OFF:
		return null
	for key in ["elapsed", "duration", "rest_seconds", "cruise_speed"]:
		var value: Variant = record.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0:
			return null
	for key in ["start", "target", "start_velocity", "heading", "position", "velocity"]:
		var value: Variant = record.get(key)
		if not value is Array or value.size() != 3:
			return null
		for component in value:
			if not (component is int or component is float) or not is_finite(float(component)):
				return null
		result.set(key, Vector3(value[0], value[1], value[2]))
	result.stage = int(state) as Stage
	result.elapsed = float(record.elapsed)
	result.duration = maxf(float(record.duration), 0.1)
	result.rest_seconds = float(record.rest_seconds)
	result.cruise_speed = float(record.cruise_speed)
	for key in ["rest_indefinitely", "startled"]:
		if record.has(key) and not record[key] is bool:
			return null
		result.set(key, record.get(key, false))
	var seed_value: Variant = record.get("idle_seed", 1)
	if not (seed_value is int or seed_value is float) or not is_finite(float(seed_value)) or float(seed_value) != floorf(float(seed_value)):
		return null
	result.idle_seed = posmod(int(seed_value), 2147483647)
	for key in ["departure_water_weight", "departure_fold"]:
		var value: Variant = record.get(key, 1.0)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0 or float(value) > 1.0:
			return null
		result.set(key, float(value))
	return result

static func _array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

static func _hermite(a: Vector3, b: Vector3, da: Vector3, db: Vector3, t: float) -> Vector3:
	return (2*t*t*t-3*t*t+1)*a + (t*t*t-2*t*t+t)*da + (-2*t*t*t+3*t*t)*b + (t*t*t-t*t)*db

static func _derivative(a: Vector3, b: Vector3, da: Vector3, db: Vector3, t: float) -> Vector3:
	return (6*t*t-6*t)*a + (3*t*t-4*t+1)*da + (-6*t*t+6*t)*b + (3*t*t-2*t)*db
