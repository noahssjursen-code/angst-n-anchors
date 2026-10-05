@tool
class_name FishingTrawlerSmall
extends BoatBody

## Free starter fishing hull. Metres only — WorldUnits (1 unit = 1 m).
## Real reference ~14 × 5 m; dimensions are authored directly in world metres.
## Deck: 1.0 m cells → 28 × 10 grid. Bow −Z, stern +Z, port −X, starboard +X.

const VESSEL_ID := "fishing_trawler_small"
const WORLD_FEEL_SCALE := 2.0
const LOA_M := 14.0 * WORLD_FEEL_SCALE
const BEAM_M := 5.0 * WORLD_FEEL_SCALE
const DEPTH_M := 2.8 * WORLD_FEEL_SCALE
const DRAFT_M := 1.4 * WORLD_FEEL_SCALE
## Volume scales ~L³.
const DISPLACEMENT_T := 32.0 * WORLD_FEEL_SCALE * WORLD_FEEL_SCALE * WORLD_FEEL_SCALE
## Half-beam run makes each bow side exactly 45 degrees in plan view.
const BOW_LENGTH_M := BEAM_M * 0.5
const BOW_FRAC := BOW_LENGTH_M / LOA_M
const TARGET_CRUISE_MS := 5.0
const BOLLARD_THRUST_N := 232000.0
const PROPULSIVE_EFFICIENCY := 0.62

var _pending_layout: Dictionary = {}


static func build() -> BoatBody:
	var boat := FishingTrawlerSmall.new()
	boat.name = "FishingTrawlerSmall"
	boat._assemble()
	return boat


static func make_grid() -> DeckGrid:
	return DeckGrid.from_hull(LOA_M, BEAM_M, DEPTH_M + 0.12, BOW_LENGTH_M)


static func make_physics_profile() -> HullPhysicsProfile:
	var profile := HullPhysicsProfile.new()
	profile.length_m = LOA_M
	profile.beam_m = BEAM_M
	profile.depth_m = DEPTH_M
	profile.design_draft_m = DRAFT_M
	profile.design_displacement_t = DISPLACEMENT_T
	profile.bow_taper_fraction = BOW_FRAC
	profile.station_count = 8
	profile.hull_form = HullFormProfile.resolve("fine_entry")
	profile.hull_center_of_mass = Vector3(0.0, 0.72, LOA_M * BOW_FRAC * 0.16)
	profile.engine_mass_kg = 11200.0
	profile.engine_position = Vector3(0.0, 0.9, LOA_M * 0.30)
	profile.ballast_mass_kg = 33600.0
	profile.ballast_position = Vector3(0.0, 0.22, LOA_M * 0.08)
	profile.full_stores_mass_kg = 2800.0
	profile.stores_position = Vector3(0.0, 1.0, LOA_M * 0.16)
	profile.roll_gyradius_fraction = 0.29
	profile.pitch_gyradius_fraction = 0.25
	profile.yaw_gyradius_fraction = 0.27
	profile.heave_damping_ratio = 0.78
	profile.max_heave_damping_accel = 5.5
	profile.bollard_thrust_n = BOLLARD_THRUST_N
	profile.propulsive_efficiency = PROPULSIVE_EFFICIENCY
	# WORLD_FEEL_SCALE already scales displacement and bollard thrust. Size the
	# engine so the new power limiter preserves that thrust through the existing
	# 5 m/s cruise target, then tapers naturally above it.
	profile.shaft_power_kw = (
		BOLLARD_THRUST_N * TARGET_CRUISE_MS
		/ (PROPULSIVE_EFFICIENCY * 1000.0)
	)
	profile.propeller_position = Vector3(0.0, 1.4, LOA_M * 0.45)
	profile.fuel_burn_l_per_sec_full = 0.07
	profile.rudder_area_m2 = 2.6
	profile.rudder_position = Vector3(0.0, 1.35, LOA_M * 0.46)
	profile.max_rudder_angle_deg = 28.0
	profile.rudder_lift_slope = 2.6
	profile.rudder_stall_angle_deg = 20.0
	profile.prop_wash_speed_ms = 2.8
	profile.lateral_drag_coeff = 3.5
	profile.yaw_drag_coeff = 10.5
	profile.tunnel_thruster_force_n = 72000.0
	profile.bow_thruster_position = Vector3(0.0, 1.8, -LOA_M * 0.42)
	profile.stern_thruster_position = Vector3(0.0, 1.8, LOA_M * 0.42)
	profile.wind_frontal_area_m2 = BEAM_M * DEPTH_M * 0.35
	profile.wind_lateral_area_m2 = LOA_M * DEPTH_M * 0.45
	profile.wind_center_of_effort = Vector3(0.0, DEPTH_M * 1.2, LOA_M * 0.05)
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
	fuel_capacity_l = 840.0
	fuel_l = 840.0
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
	## Pointed bow shifts buoyancy aft — bias CoM toward stern so she sits level.
	center_of_mass_longitudinal_m = LOA_M * BOW_FRAC * 0.22

	angular_damp_coeff = 0.36
	angular_damp = angular_damp_coeff
	linear_damp_coeff = 0.06
	linear_damp = linear_damp_coeff

	_clear_generated()
	_build_hull_visual(stations)
	apply_hull_livery(hull_livery)
	_build_hull_collision(stations)
	_add_systems(profile, stations)
	_refresh_mass()


func _clear_generated() -> void:
	for child_name in [
		"HullVisual", "HullCollision", "BowCollision", "StripBuoyancyComponent", "HydrodynamicsComponent",
		"PropulsionComponent", "RudderComponent", "BowThrusterComponent", "BoatController",
		"BoatCamera", "ShipLighting", "ShipGameplay", "Sockets", "DeckFitout", "AutoUtilities",
	]:
		var n := get_node_or_null(child_name)
		if n != null:
			remove_child(n)
			n.free()
	for child in get_children():
		if str(child.name).begins_with("HullCollisionSlice"):
			remove_child(child)
			child.free()
	DeckFitout.clear(self)
	if has_meta("fitout_applied"):
		remove_meta("fitout_applied")
	if has_meta("loadout_applied"):
		remove_meta("loadout_applied")


func _build_hull_visual(_stations: HullStations) -> void:
	# Empty anchor retained for assembly lifecycle; old mesh generation is deleted.
	var root := Node3D.new()
	root.name = "HullVisual"
	add_child(root)


func _build_hull_collision(stations: HullStations) -> void:
	var slices := MeshBuilder.lofted_collision_slices(stations, 5)
	for i in range(slices.size()):
		var body_col := CollisionShape3D.new()
		body_col.name = "HullCollisionSlice%02d" % i
		var convex := ConvexPolygonShape3D.new()
		convex.points = slices[i]
		body_col.shape = convex
		add_child(body_col)


func _add_systems(profile: HullPhysicsProfile, stations: HullStations) -> void:
	var buoy := StripBuoyancyComponent.new()
	buoy.name = "StripBuoyancyComponent"
	buoy.hull_stations = stations
	buoy.mesh_scale = 1.0
	buoy.heave_damping_per_m2 = 56000.0
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
	## ~0.9 m/s² at full ahead on ~256 t — lively day trawler.
	prop.max_thrust = profile.bollard_thrust_n
	prop.shaft_power_kw = profile.shaft_power_kw
	prop.propulsive_efficiency = profile.propulsive_efficiency
	prop.reverse_multiplier = profile.reverse_multiplier
	prop.stern_offset = profile.propeller_position
	prop.fuel_burn_l_per_sec_full = profile.fuel_burn_l_per_sec_full
	add_child(prop)

	var rudder := RudderComponent.new()
	rudder.name = "RudderComponent"
	rudder.max_torque = 2240000.0
	rudder.speed_factor = 0.2
	rudder.min_effectiveness_floor = 0.1
	rudder.rudder_flow_gate = 0.42
	rudder.sideslip_rudder_weight = 0.22
	rudder.max_effectiveness = 0.75
	add_child(rudder)

	var thruster := BowThrusterComponent.new()
	thruster.name = "BowThrusterComponent"
	thruster.max_thrust = profile.tunnel_thruster_force_n
	thruster.bow_offset = profile.bow_thruster_position
	thruster.stern_offset = profile.stern_thruster_position
	thruster.position = Vector3(0.0, 2.0, -LOA_M * 0.42)
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
	return DEPTH_M + 0.1
