@tool
class_name StripBuoyancyComponent
extends Node3D

## Strip-theory buoyancy: the hull is sliced into N stations along its length.
## Each physics tick, every station samples water at port + starboard half-centroids,
## computes submerged half-section area at the local waterline, and applies lift
## up at the sample world position. Heave, pitch and roll all emerge from this —
## no fudge factors, no fall_gravity_multiplier, no pseudo-depth assist.
##
## ShipBuilder constructs `hull_stations` from the hull JSON (HullStations.from_hull_json)
## and assigns it before this component enters the tree. `mesh_scale` is the parent
## BoatBody.mesh_scale and scales all geometry from scale-1.0 station data.

## Per-hull station table (scale 1.0). Required — built by ShipBuilder.
@export var hull_stations: HullStations
## Uniform scale applied to station geometry to match the rendered hull. Set by ShipBuilder.
@export var mesh_scale: float = 1.0
## Salt water density.
@export var water_density: float = 1025.0
@export var gravity: float = 9.81
## Multiplier on lift forces. Should normally stay at 1.0 — strip theory produces correct
## Archimedes lift directly. Only deviate if a hull is consistently sitting wrong.
@export_range(0.5, 2.0, 0.01) var buoyancy_multiplier: float = 1.0
## Vertical damping coefficient per unit waterplane area (N·s/m per m²).
## Damps the ship's vertical velocity relative to the local water surface velocity.
## Real wave-radiation damping scales with frequency — this is a constant approximation
## that's been tuned for "feels right" without killing wave following.
@export var heave_damping_per_m2: float = 8000.0

var _body: RigidBody3D


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		push_error("StripBuoyancyComponent must be a child of a RigidBody3D")
		return
	if not Engine.is_editor_hint():
		WaveSurface.set_coupled_vessel(_body)


func _exit_tree() -> void:
	if _body != null and not Engine.is_editor_hint():
		WaveSurface.clear_coupled_vessel_if(_body)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _body == null or hull_stations == null:
		return
	if hull_stations.stations.is_empty():
		return

	var s: float = mesh_scale
	var rho_g: float = water_density * gravity * buoyancy_multiplier

	# Iterate stations. For each, apply lift on port and starboard halves independently.
	# This gives roll dynamics for free — when the ship heels, the deeper side gets more
	# area, more lift, and the resulting moment opposes the heel (righting moment).
	for i in range(hull_stations.stations.size()):
		var station: Dictionary = hull_stations.stations[i]
		var z_local: float = float(station["z"]) * s
		var st_len: float = hull_stations.station_length(i) * s
		if st_len <= 0.0:
			continue

		# Half-beam at design draft for sample point placement. Use the deck-level half-beam
		# as a proxy (this is just where the sample is taken; the submerged area is computed
		# from the full section profile at the local waterline).
		var hb_max: float = hull_stations.half_beam_at(i, hull_stations.deck_y) * s
		if hb_max <= 0.001:
			# Station is at a hull endpoint (bow tip / stern tip) with zero beam — skip.
			continue

		_apply_station_side(i, z_local, hb_max * 0.5, st_len, rho_g)
		_apply_station_side(i, z_local, -hb_max * 0.5, st_len, rho_g)


## Apply lift + damping at one side (port or starboard) of one station.
## `x_local_side` is the X offset for the sample point (positive = starboard, negative = port).
func _apply_station_side(
	station_idx: int,
	z_local: float,
	x_local_side: float,
	station_length_world: float,
	rho_g: float
) -> void:
	var s: float = mesh_scale
	# Sample point at the ship-local design-waterline (y=0). Y is unimportant for water
	# sampling — only X/Z determine where to query the wave surface.
	var sample_local := Vector3(x_local_side, 0.0, z_local)
	var sample_world: Vector3 = _body.to_global(sample_local)

	var water_y_world: float = WaveSurface.get_buoyancy_surface_height_at(
		sample_world.x, sample_world.z
	)
	# Convert the water surface intersection point into ship-local frame to get the
	# waterline as seen by the section profile. Approximation: treat the local water
	# patch as flat at this XZ — accurate for ship-scale << wave-length.
	var water_world_pt := Vector3(sample_world.x, water_y_world, sample_world.z)
	var water_local: Vector3 = _body.to_local(water_world_pt)
	var waterline_y_local: float = water_local.y / s  # back to scale-1.0 frame for HS query

	# Submerged half-section area at this station + waterline, in scale-1.0 m².
	# Multiply by s² to get area in world units. Multiply by station_length_world to get volume.
	var half_area_s1: float = hull_stations.half_section_area_below(station_idx, waterline_y_local)
	if half_area_s1 <= 0.0:
		return  # this side of this station is dry
	var half_area_world: float = half_area_s1 * s * s
	var half_volume_world: float = half_area_world * station_length_world

	# Archimedes lift, world UP direction.
	var lift_N: float = rho_g * half_volume_world

	# Damping: relative vertical velocity at the sample point vs local water vertical velocity.
	var offset_from_com: Vector3 = sample_world - _body.global_position
	var angular_vel_at_pt: Vector3 = _body.angular_velocity.cross(offset_from_com)
	var point_vy: float = _body.linear_velocity.y + angular_vel_at_pt.y
	# Clamp water Vy reads — FFT shader can briefly spike during cascade restarts.
	var water_vy: float = clampf(
		WaveSurface.get_vertical_velocity_at(sample_world.x, sample_world.z),
		-8.0, 8.0
	)
	var rel_vy: float = point_vy - water_vy

	# Damping force scaled by waterplane area on this side (half_beam_at_waterline × station_length).
	# This is the area presenting "drag" to vertical motion through the water surface.
	var hb_at_wl: float = hull_stations.half_beam_at(station_idx, waterline_y_local) * s
	var damp_area: float = hb_at_wl * station_length_world
	var damp_N: float = -rel_vy * heave_damping_per_m2 * damp_area

	# Combined vertical force, applied at the sample world position.
	# Offset from COM creates a torque automatically — pitch and roll moments emerge.
	var total_y_force: float = lift_N + damp_N
	_body.apply_force(Vector3(0.0, total_y_force, 0.0), offset_from_com)
