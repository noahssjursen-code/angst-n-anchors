class_name AmbientPopulation
extends RefCounted

## Deterministic walker positions for ambient port life.
##
## Given (port_seed, npc_index, time, port_radius), returns the walker's
## current local transform along a procedurally-generated patrol loop.
##
## The whole point: **two clients computing this with the same seed + time
## get bit-identical transforms**. No replication needed for ambient walkers
## — they're "weather for the dock" in network terms. Add 20 of them per
## port for free.
##
## Loops are simple star-polygons around the port centre: a circle with each
## vertex perturbed by ±25 % in radius and ±15° in angle. Keeps walkers in
## the "ring" between the building rows and the water (most ports place
## buildings around radius 0..0.5; the dock is at radius 0..0.2 toward the
## water side; we keep walkers between 0.45 and 0.85 of port_radius).

const MIN_LOOP_RADIUS_FACTOR : float = 0.45
const MAX_LOOP_RADIUS_FACTOR : float = 0.85
const WAYPOINT_COUNT_MIN     : int   = 4
const WAYPOINT_COUNT_MAX     : int   = 8
const WALK_SPEED_MIN_M_S     : float = 0.65
const WALK_SPEED_MAX_M_S     : float = 1.25

## How many walkers per port, by port_size (0..4). Mirrors the ISLAND_WIDTH /
## DOCK_LENGTH tables in PortExpander.
const WALKERS_BY_SIZE : Array[int] = [2, 3, 5, 8, 14]


## How many ambient walkers a port of the given size should host.
static func walker_count_for_size(size: int) -> int:
	return WALKERS_BY_SIZE[clampi(size, 0, WALKERS_BY_SIZE.size() - 1)]


## Returns the local-space Transform3D for walker `npc_index` at the given
## port (identified by `port_seed` + `port_radius`) at the given time.
##
## The transform is purely procedural — no allocation, no caching. Repeated
## calls with the same inputs return identical results across all clients.
static func local_transform_at(port_seed: int, npc_index: int,
								time_s: float, port_radius: float) -> Transform3D:
	var loop      := _loop_waypoints(port_seed, npc_index, port_radius)
	var speed     := _walk_speed(port_seed, npc_index)
	var segments  := _segment_lengths(loop)
	var perimeter : float = 0.0
	for s in segments:
		perimeter += s
	if perimeter <= 0.001:
		return Transform3D(Basis(), loop[0])

	# Distance along the loop, wrapped.
	var dist := fposmod(time_s * speed, perimeter)

	# Walk segments until we land in the right one.
	var pos    := loop[0]
	var facing := Vector3.FORWARD
	var n      := loop.size()
	var accum  := 0.0
	for i in range(n):
		var seg_len := segments[i]
		if dist <= accum + seg_len:
			var t := (dist - accum) / maxf(seg_len, 0.0001)
			var a := loop[i]
			var b := loop[(i + 1) % n]
			pos    = a.lerp(b, t)
			facing = (b - a).normalized()
			break
		accum += seg_len

	return _transform_facing(pos, facing)


## The raw closed-polygon waypoints for a walker's loop. Useful for debug
## drawing or for placement-aware spawners that want to check a path. Pure
## function — first waypoint is also the conceptual "home" position.
static func loop_waypoints(port_seed: int, npc_index: int, port_radius: float) -> PackedVector3Array:
	return _loop_waypoints(port_seed, npc_index, port_radius)


## Walking speed (m/s) for this walker. Exposed so visual systems (step bob,
## potential future animation) can sync their cadence to the actual gait.
static func walk_speed_for(port_seed: int, npc_index: int) -> float:
	return _walk_speed(port_seed, npc_index)


# ── Internals ─────────────────────────────────────────────────────────────────

static func _loop_waypoints(port_seed: int, npc_index: int, port_radius: float) -> PackedVector3Array:
	var rng := _rng_for(port_seed, npc_index, 0xA9D17A12)  # 'WALK'
	var n   := rng.randi_range(WAYPOINT_COUNT_MIN, WAYPOINT_COUNT_MAX)
	var base_r       := rng.randf_range(MIN_LOOP_RADIUS_FACTOR,
										 MAX_LOOP_RADIUS_FACTOR) * port_radius
	var base_offset  := rng.randf() * TAU
	var out := PackedVector3Array()
	out.resize(n)
	for i in range(n):
		var angle := base_offset + (TAU * float(i) / float(n))
		angle    += deg_to_rad(rng.randf_range(-15.0, 15.0))
		var radius := base_r * rng.randf_range(0.75, 1.25)
		out[i] = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	return out


static func _segment_lengths(loop: PackedVector3Array) -> PackedFloat32Array:
	var n := loop.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		out[i] = loop[i].distance_to(loop[(i + 1) % n])
	return out


static func _walk_speed(port_seed: int, npc_index: int) -> float:
	var rng := _rng_for(port_seed, npc_index, 0x5DEED5DD)  # 'SPED'
	return rng.randf_range(WALK_SPEED_MIN_M_S, WALK_SPEED_MAX_M_S)


static func _rng_for(port_seed: int, npc_index: int, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	# Hash all three together so different salts give independent streams
	# (loop shape vs. walk speed vs. future per-walker colour, etc.).
	rng.seed = port_seed ^ ((npc_index + 1) * 0x9E3779B1) ^ salt
	return rng


## Build a transform that places the walker at `pos` looking along `facing`
## (XZ plane). Up is always +Y. Uses Basis.looking_at so the model's local
## -Z (Godot's "front" convention) aligns with the walking direction —
## otherwise the walker moonwalks along its loop.
static func _transform_facing(pos: Vector3, facing: Vector3) -> Transform3D:
	var f := facing
	f.y = 0.0
	if f.length_squared() < 0.0001:
		return Transform3D(Basis(), pos)
	f = f.normalized()
	return Transform3D(Basis.looking_at(f, Vector3.UP), pos)
