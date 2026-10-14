class_name GullFlockSimulation
extends RefCounted
## Data-only, fixed-step boids. Positions are local to the flock anchor.
## Scene instances are presentation only; goals can later come from an authority.

const STEP := 1.0 / 30.0
const MAX_BIRDS := 64
var positions := PackedVector3Array()
var previous_positions := PackedVector3Array()
var velocities := PackedVector3Array()
var profiles: Array[GullProfile] = []
var water_behaviours: Array[GullWaterBehaviour] = []
var goals: Dictionary = {}
var separation_m := 2.0
var cohesion := 0.8
var alignment := 1.0
var radius_m := 25.0
var time_seconds := 0.0
var _accumulator := 0.0

func configure(count: int, seed_value: int, age: float, size: float, variation: float) -> void:
	positions.clear()
	velocities.clear()
	profiles.clear()
	water_behaviours.clear()
	goals.clear()
	time_seconds = 0.0
	_accumulator = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(clampi(count, 1, MAX_BIRDS)):
		profiles.append(GullProfile.seeded(seed_value, i, age, size, variation))
		var water := GullWaterBehaviour.new()
		water.idle_seed = posmod(seed_value + i * 104729, 2147483647)
		water_behaviours.append(water)
		var theta := TAU * float(i) / float(count) + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(radius_m * 0.35, radius_m * 0.65)
		positions.append(Vector3(cos(theta) * r, rng.randf_range(8.0, 15.0), sin(theta) * r))
		velocities.append(Vector3(-sin(theta), 0, cos(theta)) * profiles[i].cruise_speed_mps)
	previous_positions = positions.duplicate()

func advance(delta: float) -> void:
	_accumulator += clampf(delta, 0.0, STEP * 8.0)
	while _accumulator >= STEP:
		_step()
		_accumulator -= STEP

func interpolation() -> float:
	return clampf(_accumulator / STEP, 0.0, 1.0)

func set_goal(bird_id: int, local_target: Vector3) -> void:
	goals[bird_id] = local_target

func clear_goal(bird_id: int) -> void:
	goals.erase(bird_id)

func request_water_rest(index: int, water_target: Vector3, rest: float = 240.0) -> bool:
	if index < 0 or index >= profiles.size() or not water_target.is_finite():
		return false
	if water_behaviours[index].stage != GullWaterBehaviour.Stage.FLYING:
		return false
	water_behaviours[index].land(positions[index], velocities[index], water_target, rest, profiles[index].cruise_speed_mps)
	return true

func react_to_vessel(at: Vector3, vessel_velocity: Vector3, hull_radius: float = 0.0, clearance: float = 12.0) -> Array[int]:
	var disturbed: Array[int] = []
	for i in water_behaviours.size():
		if water_behaviours[i].react_to_vessel(at, vessel_velocity, hull_radius, clearance):
			disturbed.append(profiles[i].bird_id)
	return disturbed

func _step() -> void:
	previous_positions = positions.duplicate()
	var next_velocities := velocities.duplicate()
	var water_updated := PackedByteArray()
	water_updated.resize(positions.size())
	var cells: Dictionary = {}
	const CELL := 8.0
	for i in positions.size():
		if water_behaviours[i].stage != GullWaterBehaviour.Stage.FLYING:
			continue
		var key := Vector3i((positions[i] / CELL).floor())
		if not cells.has(key):
			cells[key] = []
		cells[key].append(i)
	for i in positions.size():
		var water := water_behaviours[i]
		if water.stage != GullWaterBehaviour.Stage.FLYING:
			water_updated[i] = 1
			water.advance(STEP)
			positions[i] = water.position
			next_velocities[i] = water.velocity
			continue
		water.advance(STEP)
		var p := positions[i]
		var v := velocities[i]
		var separation := Vector3.ZERO
		var neighbours_position := Vector3.ZERO
		var neighbours_velocity := Vector3.ZERO
		var count := 0
		var cell := Vector3i((p / CELL).floor())
		for x in range(-1, 2):
			for y in range(-1, 2):
				for z in range(-1, 2):
					for j in cells.get(cell + Vector3i(x, y, z), []):
						if i == j:
							continue
						var offset := p - positions[j]
						var d2 := offset.length_squared()
						if d2 > CELL * CELL:
							continue
						if d2 < separation_m * separation_m:
							separation += offset / maxf(d2, 0.05)
						neighbours_position += positions[j]
						neighbours_velocity += velocities[j]
						count += 1
		var acceleration := separation * 12.0
		if count > 0:
			acceleration += (neighbours_position / count - p) * cohesion * 0.25
			acceleration += (neighbours_velocity / count - v) * alignment * 0.55
		# A broad orbit encourages natural circling without fixing birds to rails.
		var radial := Vector3(p.x, 0, p.z)
		var tangent := Vector3(-radial.z, 0, radial.x).normalized()
		var desired := tangent * profiles[i].cruise_speed_mps
		acceleration += (desired - v) * 0.35
		acceleration -= radial.normalized() * (radial.length() - radius_m * 0.55) * 0.5
		acceleration.y += (12.0 + sin(time_seconds * 0.25 + profiles[i].phase_offset) * 3.0 - p.y) * 0.7
		if goals.has(profiles[i].bird_id):
			var target: Vector3 = goals[profiles[i].bird_id]
			acceleration += (target - p).normalized() * 7.0
		var next_v := v + acceleration.limit_length(8.0) * STEP
		var speed := clampf(next_v.length(), profiles[i].cruise_speed_mps * 0.65, profiles[i].cruise_speed_mps * 1.3)
		next_velocities[i] = next_v.normalized() * speed
	velocities = next_velocities
	for i in positions.size():
		if water_updated[i] != 0:
			continue
		positions[i] += velocities[i] * STEP
		if positions[i].y < 3.0:
			positions[i].y = 3.0
			velocities[i].y = maxf(velocities[i].y, 0.0)
	time_seconds += STEP

func snapshot() -> Dictionary:
	var birds: Array[Dictionary] = []
	for i in profiles.size():
		var p := positions[i]
		var v := velocities[i]
		var row := profiles[i].to_record()
		row["position"] = [p.x, p.y, p.z]
		row["velocity"] = [v.x, v.y, v.z]
		row["behaviour"] = "seeking" if goals.has(profiles[i].bird_id) else "flocking"
		# Flying elapsed time is the next landing cooldown; preserve it too.
		row["water_behaviour"] = water_behaviours[i].to_record()
		if water_behaviours[i].stage != GullWaterBehaviour.Stage.FLYING:
			row["behaviour"] = ["flocking", "water_landing", "water_resting", "water_takeoff"][water_behaviours[i].stage]
		if goals.has(profiles[i].bird_id):
			var goal: Vector3 = goals[profiles[i].bird_id]
			row["goal"] = [goal.x, goal.y, goal.z]
		birds.append(row)
	return {"version": 1, "time_seconds": time_seconds, "birds": birds,
		"separation_m": separation_m, "cohesion": cohesion, "alignment": alignment, "radius_m": radius_m}

func restore(record: Dictionary) -> bool:
	if int(record.get("version", 0)) != 1 or not record.get("birds") is Array:
		return false
	var rows: Array = record.birds
	if rows.is_empty() or rows.size() > MAX_BIRDS:
		return false
	for key in ["time_seconds", "separation_m", "cohesion", "alignment", "radius_m"]:
		var value: Variant = record.get(key, 0.0)
		if not (value is int or value is float) or not is_finite(float(value)):
			return false
	var restored_positions := PackedVector3Array()
	var restored_velocities := PackedVector3Array()
	var restored_profiles: Array[GullProfile] = []
	var restored_water: Array[GullWaterBehaviour] = []
	var restored_goals: Dictionary = {}
	var ids: Dictionary = {}
	for row in rows:
		if not row is Dictionary:
			return false
		for key in ["position", "velocity"]:
			if not row.get(key) is Array or row[key].size() != 3:
				return false
			for value in row[key]:
				if not (value is int or value is float) or not is_finite(float(value)):
					return false
		var profile := GullProfile.from_record(row)
		var water := GullWaterBehaviour.new()
		if row.has("water_behaviour"):
			if not row.water_behaviour is Dictionary:
				return false
			water = GullWaterBehaviour.from_record(row.water_behaviour)
			if water == null:
				return false
		restored_water.append(water)
		if ids.has(profile.bird_id):
			return false
		ids[profile.bird_id] = true
		restored_profiles.append(profile)
		restored_positions.append(Vector3(row.position[0], row.position[1], row.position[2]))
		restored_velocities.append(Vector3(row.velocity[0], row.velocity[1], row.velocity[2]))
		if row.has("goal"):
			if not row.goal is Array or row.goal.size() != 3:
				return false
			for value in row.goal:
				if not (value is int or value is float) or not is_finite(float(value)):
					return false
			restored_goals[profile.bird_id] = Vector3(row.goal[0], row.goal[1], row.goal[2])
	positions = restored_positions
	previous_positions = positions.duplicate()
	velocities = restored_velocities
	profiles = restored_profiles
	water_behaviours = restored_water
	goals = restored_goals
	time_seconds = float(record.get("time_seconds", 0.0))
	separation_m = clampf(float(record.get("separation_m", 2.0)), 0.8, 6.0)
	cohesion = clampf(float(record.get("cohesion", 0.8)), 0.0, 2.0)
	alignment = clampf(float(record.get("alignment", 1.0)), 0.0, 2.0)
	radius_m = clampf(float(record.get("radius_m", 25.0)), 5.0, 100.0)
	_accumulator = 0.0
	return true
