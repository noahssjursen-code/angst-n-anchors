@tool
class_name PassengerCatamaran
extends BoatBody

## Bare high-speed catamaran hull. Players build the vessel on its deck grid.
## Bow −Z, stern +Z, port −X, starboard +X.

const VESSEL_ID := "passenger_catamaran"
const LOA_M := 45.0
const BEAM_M := 16.0
const DEMIHULL_BEAM_M := 3.6
const DEPTH_M := 5.5
const DRAFT_M := 2.2
const DISPLACEMENT_T := 520.0
const BOW_FRAC := 0.30
## ~38 kn design cruise — high-speed passenger cat.
const TARGET_CRUISE_MS := 19.5
const BOLLARD_THRUST_N := 2400000.0
const PROPULSIVE_EFFICIENCY := 0.72

var _pending_layout: Dictionary = {}


static func build() -> BoatBody:
	var boat := PassengerCatamaran.new()
	boat.name = "PassengerCatamaran"
	boat._assemble()
	return boat


static func make_grid() -> DeckGrid:
	return DeckGrid.from_hull(LOA_M, BEAM_M, DEPTH_M * 0.85 + 0.12)


static func make_physics_profile() -> HullPhysicsProfile:
	var profile := HullPhysicsProfile.new()
	profile.length_m = LOA_M
	profile.beam_m = BEAM_M
	profile.depth_m = DEPTH_M
	profile.design_draft_m = DRAFT_M
	profile.design_displacement_t = DISPLACEMENT_T
	profile.bow_taper_fraction = BOW_FRAC
	profile.station_count = 10
	profile.hull_center_of_mass = Vector3(0.0, 0.9, LOA_M * BOW_FRAC * 0.12)
	profile.engine_mass_kg = 28000.0
	profile.engine_position = Vector3(0.0, 1.0, LOA_M * 0.34)
	profile.ballast_mass_kg = 22000.0
	profile.ballast_position = Vector3(0.0, 0.25, LOA_M * 0.06)
	profile.full_stores_mass_kg = 5000.0
	profile.stores_position = Vector3(0.0, 1.1, LOA_M * 0.16)
	profile.roll_gyradius_fraction = 0.34
	profile.pitch_gyradius_fraction = 0.26
	profile.yaw_gyradius_fraction = 0.29
	profile.heave_damping_ratio = 0.78
	profile.max_heave_damping_accel = 5.5
	profile.bollard_thrust_n = BOLLARD_THRUST_N
	profile.propulsive_efficiency = PROPULSIVE_EFFICIENCY
	profile.shaft_power_kw = (
		BOLLARD_THRUST_N * TARGET_CRUISE_MS
		/ (PROPULSIVE_EFFICIENCY * 1000.0)
	)
	profile.propeller_position = Vector3(0.0, 1.0, LOA_M * 0.46)
	profile.fuel_burn_l_per_sec_full = 0.28
	profile.rudder_area_m2 = 6.5
	profile.rudder_position = Vector3(0.0, 1.2, LOA_M * 0.47)
	profile.max_rudder_angle_deg = 30.0
	profile.rudder_lift_slope = 2.8
	profile.rudder_stall_angle_deg = 22.0
	profile.prop_wash_speed_ms = 8.0
	## Semi-displacement / high-speed cat: weak hull-speed wall, low wave drag.
	profile.frictional_coeff = 0.0018
	profile.form_factor = 1.06
	profile.wave_making_peak_coeff = 0.0007
	profile.hull_speed_fn = 0.72
	profile.lateral_drag_coeff = 2.4
	profile.yaw_drag_coeff = 8.0
	profile.tunnel_thruster_force_n = 220000.0
	profile.bow_thruster_position = Vector3(0.0, 1.5, -LOA_M * 0.42)
	profile.stern_thruster_position = Vector3(0.0, 1.5, LOA_M * 0.42)
	profile.wind_frontal_area_m2 = BEAM_M * DEPTH_M * 0.30
	profile.wind_lateral_area_m2 = LOA_M * DEPTH_M * 0.35
	profile.wind_center_of_effort = Vector3(0.0, DEPTH_M * 0.8, 0.0)
	profile.calibrate_longitudinal_mass_center()
	return profile


func _ready() -> void:
	if get_node_or_null("HullVisual") == null:
		_assemble()
	model_data_path = ""
	mesh_data_path = ""
	linear_damp = linear_damp_coeff
	angular_damp = angular_damp_coeff
	collision_layer = LAYER_BOAT_HULL
	collision_mask = LAYER_WORLD
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.0
	physics_material_override = pm
	_refresh_mass()
	if not Engine.is_editor_hint():
		call_deferred("_ensure_walk_deck")
		if get_node_or_null("BoatAudio") == null:
			var audio: Node = load("res://scripts/ship/boat_audio_system.gd").new()
			audio.name = "BoatAudio"
			add_child(audio)
		call_deferred("_apply_pending_or_default_fitout")


func deck_grid() -> DeckGrid:
	return make_grid()


func apply_brick_layout(layout_dict: Dictionary) -> void:
	_pending_layout = layout_dict.duplicate(true)
	if get_node_or_null("HullVisual") != null:
		_apply_layout_dict(_pending_layout)
		_pending_layout.clear()


func _apply_pending_or_default_fitout() -> void:
	if has_meta("fitout_applied") and bool(get_meta("fitout_applied")):
		return
	if not _pending_layout.is_empty():
		_apply_layout_dict(_pending_layout)
		_pending_layout.clear()
	else:
		_apply_layout_dict({"hull_id": VESSEL_ID, "cells": {}})


func _apply_layout_dict(layout_dict: Dictionary) -> void:
	var layout := BrickLayout.from_dict(layout_dict)
	DeckFitout.apply(self, layout, make_grid())
	set_meta("fitout_applied", true)


func _assemble() -> void:
	var profile := make_physics_profile()
	physics_profile = profile
	length_m = profile.length_m
	beam_m = profile.beam_m
	depth_m = profile.depth_m
	draft_m = profile.design_draft_m
	displacement_t = profile.design_displacement_t
	design_draft_fraction = profile.design_draft_fraction()
	auto_mass_from_hull = true
	mass_scale = 1.0
	mesh_scale = 1.0
	fuel_capacity_l = 4200.0
	fuel_l = 4200.0
	engine_mass = profile.engine_mass_kg
	keel_ballast_mass = profile.ballast_mass_kg
	fuel_stores_mass = profile.full_stores_mass_kg
	bow_face = BoatBody.FaceAxis.MINUS_Z
	stern_face = BoatBody.FaceAxis.PLUS_Z
	port_face = BoatBody.FaceAxis.MINUS_X
	starboard_face = BoatBody.FaceAxis.PLUS_X
	collision_layer = LAYER_BOAT_HULL
	collision_mask = LAYER_WORLD
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	linear_damp = linear_damp_coeff
	angular_damp = angular_damp_coeff

	var stations := profile.make_stations()
	hull_stations = stations
	hull_size = Vector3(BEAM_M, DEPTH_M, LOA_M)
	hull_center = Vector3(0.0, DEPTH_M * 0.5, 0.0)
	center_of_mass_longitudinal_m = LOA_M * BOW_FRAC * 0.18

	angular_damp_coeff = 0.30
	angular_damp = angular_damp_coeff
	linear_damp_coeff = 0.04
	linear_damp = linear_damp_coeff

	_clear_generated()
	_build_hull_visual()
	_build_hull_collision()
	_add_systems(profile, stations)
	_refresh_mass()


func _clear_generated() -> void:
	for child_name in [
		"HullVisual",
		"HullCollisionPort", "HullCollisionStarboard",
		"BowCollisionPort", "BowCollisionStarboard",
		"StripBuoyancyComponent", "HydrodynamicsComponent",
		"PropulsionComponent", "RudderComponent", "BowThrusterComponent", "BoatController",
		"BoatCamera", "ShipLighting", "ShipGameplay", "Sockets", "DeckFitout", "AutoUtilities",
	]:
		var n := get_node_or_null(child_name)
		if n != null:
			remove_child(n)
			n.free()
	DeckFitout.clear(self)
	if has_meta("fitout_applied"):
		remove_meta("fitout_applied")
	if has_meta("loadout_applied"):
		remove_meta("loadout_applied")


func _build_hull_visual() -> void:
	var root := Node3D.new()
	root.name = "HullVisual"
	add_child(root)

	var shell_h := DEPTH_M * 0.85
	var hull_offset := (BEAM_M - DEMIHULL_BEAM_M) * 0.5
	for side in [-1.0, 1.0]:
		## Double-sided: bow tip tops are thin fans — single-sided cull reads as hollow.
		var hull := MeshBuilder.pointed_hull_shell(
			LOA_M,
			DEMIHULL_BEAM_M,
			shell_h,
			BOW_FRAC,
			Color(0.14, 0.16, 0.18),
			0.9,
			0.05,
			true
		)
		hull.name = "HullPort" if side < 0.0 else "HullStarboard"
		hull.position.x = hull_offset * side
		root.add_child(hull)

	## Full rectangular deck across both hulls — not a pointed planform.
	var deck := MeshBuilder.box(
		Vector3(BEAM_M, 0.12, LOA_M),
		Color(0.38, 0.34, 0.28),
		0.95,
		0.0
	)
	deck.name = "Deck"
	deck.position = Vector3(0.0, shell_h + 0.06, 0.0)
	root.add_child(deck)


func _build_hull_collision() -> void:
	var shell_h := DEPTH_M * 0.85
	var bow_len := LOA_M * BOW_FRAC
	var body_len := LOA_M - bow_len
	var hull_offset := (BEAM_M - DEMIHULL_BEAM_M) * 0.5
	for side in [-1.0, 1.0]:
		var suffix := "Port" if side < 0.0 else "Starboard"
		var body_col := CollisionShape3D.new()
		body_col.name = "HullCollision" + suffix
		var box := BoxShape3D.new()
		box.size = Vector3(DEMIHULL_BEAM_M, shell_h, body_len)
		body_col.shape = box
		body_col.position = Vector3(
			hull_offset * side,
			shell_h * 0.5,
			bow_len * 0.5
		)
		add_child(body_col)

		var bow_col := CollisionShape3D.new()
		bow_col.name = "BowCollision" + suffix
		var convex := ConvexPolygonShape3D.new()
		var points := MeshBuilder.pointed_bow_collision_points(
			LOA_M,
			DEMIHULL_BEAM_M,
			shell_h,
			BOW_FRAC
		)
		for i in range(points.size()):
			points[i].x += hull_offset * side
		convex.points = points
		bow_col.shape = convex
		add_child(bow_col)


func _add_systems(profile: HullPhysicsProfile, stations: HullStations) -> void:
	var buoy := StripBuoyancyComponent.new()
	buoy.name = "StripBuoyancyComponent"
	buoy.hull_stations = stations
	buoy.mesh_scale = 1.0
	buoy.heave_damping_per_m2 = 42000.0
	add_child(buoy)

	var hydro := HydrodynamicsComponent.new()
	hydro.name = "HydrodynamicsComponent"
	hydro.hull_stations = stations
	hydro.mesh_scale = 1.0
	hydro.frictional_coeff = profile.frictional_coeff
	hydro.form_factor = profile.form_factor
	hydro.wave_making_peak_coeff = profile.wave_making_peak_coeff
	hydro.hull_speed_fn = profile.hull_speed_fn
	hydro.lateral_drag_coeff = profile.lateral_drag_coeff
	hydro.yaw_drag_coeff = profile.yaw_drag_coeff
	hydro.wind_frontal_area = profile.wind_frontal_area_m2
	hydro.wind_lateral_area = profile.wind_lateral_area_m2
	hydro.wind_drag_coeff = profile.wind_drag_coeff
	hydro.wind_center_of_effort = profile.wind_center_of_effort
	add_child(hydro)

	var prop := PropulsionComponent.new()
	prop.name = "PropulsionComponent"
	prop.max_thrust = profile.bollard_thrust_n
	prop.shaft_power_kw = profile.shaft_power_kw
	prop.propulsive_efficiency = profile.propulsive_efficiency
	prop.reverse_multiplier = profile.reverse_multiplier
	prop.stern_offset = profile.propeller_position
	prop.fuel_burn_l_per_sec_full = profile.fuel_burn_l_per_sec_full
	add_child(prop)

	var rudder := RudderComponent.new()
	rudder.name = "RudderComponent"
	rudder.max_torque = 9000000.0
	rudder.speed_factor = 0.22
	rudder.min_effectiveness_floor = 0.1
	rudder.rudder_flow_gate = 0.4
	rudder.sideslip_rudder_weight = 0.18
	rudder.max_effectiveness = 0.75
	add_child(rudder)

	var thruster := BowThrusterComponent.new()
	thruster.name = "BowThrusterComponent"
	thruster.max_thrust = profile.tunnel_thruster_force_n
	thruster.bow_offset = profile.bow_thruster_position
	thruster.stern_offset = profile.stern_thruster_position
	thruster.position = Vector3(0.0, 1.8, -LOA_M * 0.42)
	add_child(thruster)

	var controller := BoatController.new()
	controller.name = "BoatController"
	add_child(controller)

	var cam := BoatCamera.new()
	cam.name = "BoatCamera"
	cam.follow_distance = 32.0
	cam.follow_height = 12.0
	cam.min_distance = 10.0
	add_child(cam)

	var lights := ShipLighting.new()
	lights.name = "ShipLighting"
	add_child(lights)

	var gameplay := Node3D.new()
	gameplay.name = "ShipGameplay"
	add_child(gameplay)

	var mooring := MooringComponent.new()
	mooring.name = "MooringComponent"
	gameplay.add_child(mooring)


func _deck_y() -> float:
	return DEPTH_M * 0.85 + 0.12
