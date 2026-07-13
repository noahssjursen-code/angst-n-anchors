@tool
class_name FishingTrawlerSmall
extends BoatBody

## Free starter fishing hull. Metres only — WorldUnits (1 unit = 1 m).
## Real reference ~14 × 5 m; in-world size uses WORLD_FEEL_SCALE (same as workboat).
## Deck: 1.0 m cells → 28 × 10 grid. Bow −Z, stern +Z, port −X, starboard +X.

const VESSEL_ID := "fishing_trawler_small"
const WORLD_FEEL_SCALE := 2.0
const LOA_M := 14.0 * WORLD_FEEL_SCALE
const BEAM_M := 5.0 * WORLD_FEEL_SCALE
const DEPTH_M := 2.8 * WORLD_FEEL_SCALE
const DRAFT_M := 1.4 * WORLD_FEEL_SCALE
## Volume scales ~L³.
const DISPLACEMENT_T := 32.0 * WORLD_FEEL_SCALE * WORLD_FEEL_SCALE * WORLD_FEEL_SCALE
const BOW_FRAC := 0.30

var _pending_layout: Dictionary = {}


static func build() -> BoatBody:
	var boat := FishingTrawlerSmall.new()
	boat.name = "FishingTrawlerSmall"
	boat._assemble()
	return boat


static func make_grid() -> DeckGrid:
	return DeckGrid.from_hull(LOA_M, BEAM_M, DEPTH_M * 0.85 + 0.12)


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
	length_m = LOA_M
	beam_m = BEAM_M
	depth_m = DEPTH_M
	draft_m = DRAFT_M
	displacement_t = DISPLACEMENT_T
	design_draft_fraction = DRAFT_M / DEPTH_M
	auto_mass_from_hull = true
	mass_scale = 1.0
	mesh_scale = 1.0
	fuel_capacity_l = 840.0
	fuel_l = 840.0
	engine_mass = 11200.0
	keel_ballast_mass = 33600.0
	fuel_stores_mass = 2800.0
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

	var stations: HullStations = HullStations.from_pointed(LOA_M, BEAM_M, DEPTH_M, BOW_FRAC, 8)
	hull_stations = stations
	hull_size = Vector3(BEAM_M, DEPTH_M, LOA_M)
	hull_center = Vector3(0.0, DEPTH_M * 0.5, 0.0)
	## Pointed bow shifts buoyancy aft — bias CoM toward stern so she sits level.
	center_of_mass_longitudinal_m = LOA_M * BOW_FRAC * 0.22

	angular_damp_coeff = 0.22
	angular_damp = angular_damp_coeff
	linear_damp_coeff = 0.05
	linear_damp = linear_damp_coeff

	_clear_generated()
	_build_hull_visual()
	_build_hull_collision()
	_add_systems(stations)
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
	var hull := MeshBuilder.pointed_hull_shell(
		LOA_M, BEAM_M, shell_h, BOW_FRAC, Color(0.14, 0.16, 0.18), 0.9, 0.05
	)
	hull.name = "HullShell"
	root.add_child(hull)

	var deck := MeshBuilder.pointed_deck_plate(
		LOA_M, BEAM_M, shell_h + 0.1, 0.1, BOW_FRAC, Color(0.38, 0.34, 0.28), 0.95
	)
	deck.name = "Deck"
	root.add_child(deck)


func _build_hull_collision() -> void:
	var shell_h := DEPTH_M * 0.85
	var bow_len := LOA_M * BOW_FRAC
	var body_col := CollisionShape3D.new()
	body_col.name = "HullCollision"
	var box := BoxShape3D.new()
	var body_len := LOA_M - bow_len
	box.size = Vector3(BEAM_M, shell_h, body_len)
	body_col.shape = box
	body_col.position = Vector3(0.0, shell_h * 0.5, bow_len * 0.5)
	add_child(body_col)
	var bow_col := CollisionShape3D.new()
	bow_col.name = "BowCollision"
	var convex := ConvexPolygonShape3D.new()
	convex.points = MeshBuilder.pointed_bow_collision_points(LOA_M, BEAM_M, shell_h, BOW_FRAC)
	bow_col.shape = convex
	add_child(bow_col)


func _add_systems(stations: HullStations) -> void:
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
	hydro.wind_frontal_area = BEAM_M * DEPTH_M * 0.35
	hydro.wind_lateral_area = LOA_M * DEPTH_M * 0.45
	add_child(hydro)

	var prop := PropulsionComponent.new()
	prop.name = "PropulsionComponent"
	## ~0.9 m/s² at full ahead on ~256 t — lively day trawler.
	prop.max_thrust = 232000.0
	prop.stern_offset = Vector3(0.0, 1.4, LOA_M * 0.45)
	prop.fuel_burn_l_per_sec_full = 0.07
	add_child(prop)

	var rudder := RudderComponent.new()
	rudder.name = "RudderComponent"
	rudder.max_torque = 2240000.0
	rudder.speed_factor = 0.28
	rudder.min_effectiveness_floor = 0.16
	rudder.rudder_flow_gate = 0.3
	rudder.max_effectiveness = 0.9
	add_child(rudder)

	var thruster := BowThrusterComponent.new()
	thruster.name = "BowThrusterComponent"
	thruster.max_thrust = 72000.0
	thruster.bow_offset = Vector3(0.0, 1.8, -LOA_M * 0.42)
	thruster.stern_offset = Vector3(0.0, 1.8, LOA_M * 0.42)
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
	return DEPTH_M * 0.85 + 0.1
