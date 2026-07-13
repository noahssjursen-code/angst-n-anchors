@tool
class_name Workboat
extends BoatBody

## Hand-authored workboat. Metres only — see WorldUnits (1 unit = 1 m).
## Hull: 30 m LOA × 24 m beam (a big beamy workboat — these are its real dims).
## Deck: 1.0 m cells → 30 × 24 grid. Player 1.8 m ≈ almost 2 cells tall.
## Bow −Z, stern +Z, port −X, starboard +X.

const VESSEL_ID := "workboat"
const LOA_M := 30.0
const BEAM_M := 24.0
const DEPTH_M := 6.0
const DRAFT_M := 3.0
const DISPLACEMENT_T := 960.0
const TARGET_CRUISE_MS := 5.0
const BOLLARD_THRUST_N := 720000.0
const PROPULSIVE_EFFICIENCY := 0.62

var _pending_layout: Dictionary = {}


static func build() -> BoatBody:
	var boat := Workboat.new()
	boat.name = "Workboat"
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
	profile.bow_taper_fraction = 0.0
	profile.station_count = 10
	profile.hull_center_of_mass = Vector3(0.0, 0.85, 0.0)
	profile.engine_mass_kg = 8000.0
	profile.engine_position = Vector3(0.0, 1.0, LOA_M * 0.32)
	profile.ballast_mass_kg = 16000.0
	profile.ballast_position = Vector3(0.0, 0.25, 0.0)
	profile.full_stores_mass_kg = 4000.0
	profile.stores_position = Vector3(0.0, 1.0, LOA_M * 0.18)
	profile.roll_gyradius_fraction = 0.31
	profile.pitch_gyradius_fraction = 0.26
	profile.yaw_gyradius_fraction = 0.28
	profile.heave_damping_ratio = 0.82
	profile.max_heave_damping_accel = 5.0
	profile.bollard_thrust_n = BOLLARD_THRUST_N
	profile.propulsive_efficiency = PROPULSIVE_EFFICIENCY
	profile.shaft_power_kw = (
		BOLLARD_THRUST_N * TARGET_CRUISE_MS
		/ (PROPULSIVE_EFFICIENCY * 1000.0)
	)
	profile.propeller_position = Vector3(0.0, 1.2, LOA_M * 0.45)
	profile.fuel_burn_l_per_sec_full = 0.11
	profile.rudder_area_m2 = 6.0
	profile.rudder_position = Vector3(0.0, 1.5, LOA_M * 0.46)
	profile.max_rudder_angle_deg = 28.0
	profile.rudder_lift_slope = 2.6
	profile.rudder_stall_angle_deg = 20.0
	profile.prop_wash_speed_ms = 3.2
	profile.lateral_drag_coeff = 3.6
	profile.yaw_drag_coeff = 11.0
	profile.tunnel_thruster_force_n = 240000.0
	profile.bow_thruster_position = Vector3(0.0, 1.5, -LOA_M * 0.42)
	profile.stern_thruster_position = Vector3(0.0, 1.5, LOA_M * 0.42)
	profile.wind_frontal_area_m2 = BEAM_M * DEPTH_M * 0.4
	profile.wind_lateral_area_m2 = LOA_M * DEPTH_M * 0.5
	profile.wind_center_of_effort = Vector3(0.0, DEPTH_M * 1.15, 0.0)
	profile.calibrate_longitudinal_mass_center()
	return profile


func _ready() -> void:
	if get_node_or_null("HullVisual") == null:
		_assemble()
	model_data_path = ""
	mesh_data_path = ""
	linear_damp  = linear_damp_coeff
	angular_damp = angular_damp_coeff
	collision_layer = LAYER_BOAT_HULL
	collision_mask  = LAYER_WORLD
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
		# Bare deck — no starter cabin / fishing / utilities.
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
	fuel_capacity_l = 1600.0
	fuel_l = 1600.0
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

	# Let hydro yaw drag own rotational damping — stock 0.7 kills helm on a 960 t hull.
	angular_damp_coeff = 0.32
	angular_damp = angular_damp_coeff
	linear_damp_coeff = 0.05
	linear_damp = linear_damp_coeff

	_clear_generated()
	_build_hull_visual()
	_build_hull_collision()
	_add_systems(profile, stations)
	_refresh_mass()


func _clear_generated() -> void:
	for child_name in [
		"HullVisual", "HullCollision", "StripBuoyancyComponent", "HydrodynamicsComponent",
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

	var hull := MeshBuilder.box(
		Vector3(BEAM_M, DEPTH_M * 0.85, LOA_M),
		Color(0.12, 0.14, 0.16),
		0.9,
		0.05,
	)
	hull.name = "HullShell"
	hull.position = Vector3(0.0, DEPTH_M * 0.85 * 0.5, 0.0)
	root.add_child(hull)
	# Sanity: BoxMesh.size is full extents — LOA/beam must match WorldUnits metres.
	assert(is_equal_approx((hull.mesh as BoxMesh).size.z, LOA_M))
	assert(is_equal_approx((hull.mesh as BoxMesh).size.x, BEAM_M))

	var deck := MeshBuilder.box(
		Vector3(BEAM_M, 0.12, LOA_M),
		Color(0.35, 0.32, 0.28),
		0.95,
		0.0,
	)
	deck.name = "Deck"
	deck.position = Vector3(0.0, DEPTH_M * 0.85 + 0.06, 0.0)
	root.add_child(deck)


func _build_hull_collision() -> void:
	var body_col := CollisionShape3D.new()
	body_col.name = "HullCollision"
	var box := BoxShape3D.new()
	box.size = Vector3(BEAM_M, DEPTH_M * 0.85, LOA_M)
	body_col.shape = box
	body_col.position = Vector3(0.0, DEPTH_M * 0.85 * 0.5, 0.0)
	add_child(body_col)


func _add_systems(profile: HullPhysicsProfile, stations: HullStations) -> void:
	var buoy := StripBuoyancyComponent.new()
	buoy.name = "StripBuoyancyComponent"
	buoy.hull_stations = stations
	buoy.mesh_scale = 1.0
	buoy.heave_damping_per_m2 = 28000.0
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
	## ~0.75 m/s² at full ahead on 960 t — coastal workboat feel, not a barge.
	prop.max_thrust = profile.bollard_thrust_n
	prop.shaft_power_kw = profile.shaft_power_kw
	prop.propulsive_efficiency = profile.propulsive_efficiency
	prop.reverse_multiplier = profile.reverse_multiplier
	prop.stern_offset = profile.propeller_position
	prop.fuel_burn_l_per_sec_full = profile.fuel_burn_l_per_sec_full
	add_child(prop)

	var rudder := RudderComponent.new()
	rudder.name = "RudderComponent"
	## Displacement-hull helm — slow throw, no arcade snap yaw.
	rudder.max_torque = 12000000.0
	rudder.speed_factor = 0.18
	rudder.min_effectiveness_floor = 0.08
	rudder.rudder_flow_gate = 0.45
	rudder.sideslip_rudder_weight = 0.2
	rudder.max_effectiveness = 0.7
	add_child(rudder)

	var thruster := BowThrusterComponent.new()
	thruster.name = "BowThrusterComponent"
	## Lateral ~0.25 m/s²; force must sit at the bow (−Z), not the default midships offset.
	thruster.max_thrust = profile.tunnel_thruster_force_n
	thruster.bow_offset = profile.bow_thruster_position
	thruster.stern_offset = profile.stern_thruster_position
	thruster.position = Vector3(0.0, 1.6, -LOA_M * 0.42)
	add_child(thruster)

	var controller := BoatController.new()
	controller.name = "BoatController"
	add_child(controller)

	var cam := BoatCamera.new()
	cam.name = "BoatCamera"
	cam.follow_distance = 24.0
	cam.follow_height = 10.0
	cam.min_distance = 8.0
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
