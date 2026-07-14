@tool
class_name CatalogHullVessel
extends BoatBody

## Parameterized hull from HullCatalog JSON. Default shape is pointed (45° bow).

const TARGET_CRUISE_MS := 5.0
const PROPULSIVE_EFFICIENCY := 0.62

var _hull_id: String = ""
var _config: Dictionary = {}
var _pending_layout: Dictionary = {}


static func build(hull_id: String) -> BoatBody:
	var config := HullCatalog.get_by_id(hull_id)
	if config.is_empty():
		push_error("CatalogHullVessel: unknown hull id %s" % hull_id)
		return null
	var boat := CatalogHullVessel.new()
	boat._hull_id = hull_id
	boat._config = config
	boat.name = hull_id
	boat._assemble()
	return boat


static func make_grid(hull_id: String) -> DeckGrid:
	var config := HullCatalog.get_by_id(hull_id)
	if config.is_empty():
		return DeckGrid.from_hull(28.0, 10.0, 5.0)
	var loa_m := float(config.get("loa_m", 28.0))
	var beam_m := float(config.get("beam_m", 10.0))
	var depth_m := float(config.get("depth_m", 5.0))
	## 45° bow cells: taper length = half beam.
	var bow_taper_m := 0.0
	if str(config.get("shape", "pointed")) != "box":
		bow_taper_m = beam_m * 0.5
	var deck_y := depth_m + 0.12
	return DeckGrid.from_hull(loa_m, beam_m, deck_y, bow_taper_m)


static func make_physics_profile(config: Dictionary) -> HullPhysicsProfile:
	var loa_m := float(config.get("loa_m", 28.0))
	var beam_m := float(config.get("beam_m", 10.0))
	var depth_m := float(config.get("depth_m", 5.0))
	var draft_m := float(config.get("draft_m", depth_m * 0.5))
	var displacement_t := float(config.get("displacement_t", loa_m * beam_m * draft_m * 0.52))
	## 45° plan bow: run = half beam.
	var bow_taper_m := beam_m * 0.5 if str(config.get("shape", "pointed")) != "box" else 0.0
	var bow_frac := clampf(bow_taper_m / maxf(loa_m, 0.1), 0.0, 0.5)
	var bollard := displacement_t * 750.0
	var profile := HullPhysicsProfile.new()
	profile.length_m = loa_m
	profile.beam_m = beam_m
	profile.depth_m = depth_m
	profile.design_draft_m = draft_m
	profile.design_displacement_t = displacement_t
	profile.bow_taper_fraction = bow_frac
	profile.station_count = clampi(int(round(loa_m / 8.0)), 8, 16)
	var raw_form = config.get("hull_form", {})
	profile.hull_form = (
		(raw_form as Dictionary).duplicate(true)
		if raw_form is Dictionary
		else HullFormProfile.resolve(str(config.get("form", "container")))
	)
	profile.hull_center_of_mass = Vector3(0.0, depth_m * 0.14, loa_m * bow_frac * 0.12)
	profile.engine_mass_kg = displacement_t * 8.5
	profile.engine_position = Vector3(0.0, depth_m * 0.16, loa_m * 0.30)
	profile.ballast_mass_kg = displacement_t * 16.0
	profile.ballast_position = Vector3(0.0, depth_m * 0.04, loa_m * 0.06)
	profile.full_stores_mass_kg = displacement_t * 4.0
	profile.stores_position = Vector3(0.0, depth_m * 0.16, loa_m * 0.16)
	profile.roll_gyradius_fraction = 0.30
	profile.pitch_gyradius_fraction = 0.26
	profile.yaw_gyradius_fraction = 0.28
	profile.heave_damping_ratio = 0.80
	profile.max_heave_damping_accel = 5.0
	profile.bollard_thrust_n = bollard
	profile.propulsive_efficiency = PROPULSIVE_EFFICIENCY
	profile.shaft_power_kw = bollard * TARGET_CRUISE_MS / (PROPULSIVE_EFFICIENCY * 1000.0)
	profile.propeller_position = Vector3(0.0, depth_m * 0.20, loa_m * 0.45)
	profile.fuel_burn_l_per_sec_full = clampf(displacement_t * 0.000115, 0.05, 0.28)
	profile.rudder_area_m2 = beam_m * depth_m * 0.04
	profile.rudder_position = Vector3(0.0, depth_m * 0.24, loa_m * 0.46)
	profile.max_rudder_angle_deg = 28.0
	profile.rudder_lift_slope = 2.6
	profile.rudder_stall_angle_deg = 20.0
	profile.prop_wash_speed_ms = 3.0
	profile.lateral_drag_coeff = 3.6
	profile.yaw_drag_coeff = 11.0
	profile.tunnel_thruster_force_n = displacement_t * 250.0
	profile.bow_thruster_position = Vector3(0.0, depth_m * 0.24, -loa_m * 0.42)
	profile.stern_thruster_position = Vector3(0.0, depth_m * 0.24, loa_m * 0.42)
	profile.wind_frontal_area_m2 = beam_m * depth_m * 0.38
	profile.wind_lateral_area_m2 = loa_m * depth_m * 0.48
	profile.wind_center_of_effort = Vector3(0.0, depth_m * 1.12, 0.0)
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
	return make_grid(_hull_id)


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
		_apply_layout_dict({"hull_id": _hull_id, "cells": {}})


func _apply_layout_dict(layout_dict: Dictionary) -> void:
	var layout := BrickLayout.from_dict(layout_dict)
	DeckFitout.apply(self, layout, make_grid(_hull_id))
	set_meta("fitout_applied", true)


func _assemble() -> void:
	if _config.is_empty() and not _hull_id.is_empty():
		_config = HullCatalog.get_by_id(_hull_id)
	var cfg_loa := float(_config.get("loa_m", 28.0))
	var cfg_beam := float(_config.get("beam_m", 10.0))
	var cfg_depth := float(_config.get("depth_m", 5.0))
	var cfg_draft := float(_config.get("draft_m", cfg_depth * 0.5))
	var cfg_displacement := float(_config.get(
		"displacement_t",
		cfg_loa * cfg_beam * cfg_draft * 0.52,
	))
	var profile := make_physics_profile(_config)
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
	fuel_capacity_l = cfg_displacement * 1.67
	fuel_l = fuel_capacity_l
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
	angular_damp_coeff = lerpf(0.38, 0.28, clampf(cfg_displacement / 4000.0, 0.0, 1.0))
	angular_damp = angular_damp_coeff
	linear_damp_coeff = 0.05
	linear_damp = linear_damp_coeff

	var stations := profile.make_stations()
	hull_stations = stations
	hull_size = Vector3(cfg_beam, cfg_depth, cfg_loa)
	hull_center = Vector3(0.0, cfg_depth * 0.5, 0.0)
	center_of_mass_longitudinal_m = cfg_loa * profile.bow_taper_fraction * 0.22

	_clear_generated()
	_build_lofted_hull_visual(stations, cfg_loa, cfg_beam, profile.bow_taper_fraction)
	_build_lofted_hull_collision(stations, cfg_loa)
	_add_systems(profile, stations, cfg_loa, cfg_depth, cfg_displacement)
	_refresh_mass()


func _clear_generated() -> void:
	for child_name in [
		"HullVisual", "HullCollision", "BowCollision", "StripBuoyancyComponent",
		"HydrodynamicsComponent", "PropulsionComponent", "RudderComponent",
		"BowThrusterComponent", "BoatController", "BoatCamera", "ShipLighting",
		"ShipGameplay", "Sockets", "DeckFitout", "AutoUtilities",
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


func _build_lofted_hull_visual(
	stations: HullStations,
	loa_m: float,
	beam_m: float,
	bow_frac: float,
) -> void:
	var root := Node3D.new()
	root.name = "HullVisual"
	add_child(root)
	var hull := MeshBuilder.lofted_hull_shell(
		stations, Color(0.14, 0.16, 0.18), 0.9, 0.05
	)
	hull.name = "HullShell"
	root.add_child(hull)
	var deck := MeshBuilder.pointed_deck_plate(
		loa_m,
		beam_m,
		stations.deck_y + 0.1,
		0.1,
		bow_frac,
		Color(0.38, 0.34, 0.28),
		0.95
	)
	deck.name = "Deck"
	root.add_child(deck)


func _build_lofted_hull_collision(stations: HullStations, loa_m: float) -> void:
	var max_slices := clampi(int(ceil(loa_m / 20.0)), 4, 10)
	var slices := MeshBuilder.lofted_collision_slices(stations, max_slices)
	for i in range(slices.size()):
		var body_col := CollisionShape3D.new()
		body_col.name = "HullCollisionSlice%02d" % i
		var convex := ConvexPolygonShape3D.new()
		convex.points = slices[i]
		body_col.shape = convex
		add_child(body_col)


func _add_systems(
		profile: HullPhysicsProfile,
		stations: HullStations,
		loa_m: float,
		depth_m: float,
		displacement_t: float,
) -> void:
	var buoy := StripBuoyancyComponent.new()
	buoy.name = "StripBuoyancyComponent"
	buoy.hull_stations = stations
	buoy.mesh_scale = 1.0
	buoy.heave_damping_per_m2 = lerpf(18000.0, 36000.0, clampf(displacement_t / 4000.0, 0.0, 1.0))
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
	rudder.max_torque = displacement_t * 12500.0
	rudder.speed_factor = 0.18
	rudder.min_effectiveness_floor = 0.08
	rudder.rudder_flow_gate = 0.45
	rudder.sideslip_rudder_weight = 0.2
	rudder.max_effectiveness = 0.7
	add_child(rudder)

	var thruster := BowThrusterComponent.new()
	thruster.name = "BowThrusterComponent"
	thruster.max_thrust = profile.tunnel_thruster_force_n
	thruster.bow_offset = profile.bow_thruster_position
	thruster.stern_offset = profile.stern_thruster_position
	thruster.position = Vector3(0.0, depth_m * 0.26, -loa_m * 0.42)
	add_child(thruster)

	var controller := BoatController.new()
	controller.name = "BoatController"
	add_child(controller)

	var cam := BoatCamera.new()
	cam.name = "BoatCamera"
	cam.follow_distance = clampf(loa_m * 0.75, 28.0, 90.0)
	cam.follow_height = clampf(loa_m * 0.28, 12.0, 28.0)
	cam.min_distance = clampf(loa_m * 0.22, 10.0, 24.0)
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
