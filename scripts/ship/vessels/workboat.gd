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

var _pending_layout: Dictionary = {}


static func build() -> BoatBody:
	var boat := Workboat.new()
	boat.name = "Workboat"
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
		# Bare deck — no starter cabin / fishing / utilities.
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
	fuel_capacity_l = 1600.0
	fuel_l = 1600.0
	engine_mass = 8000.0
	keel_ballast_mass = 16000.0
	fuel_stores_mass = 4000.0
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

	var stations: HullStations = HullStations.from_box(LOA_M, BEAM_M, DEPTH_M, 10)
	hull_stations = stations
	hull_size = Vector3(BEAM_M, DEPTH_M, LOA_M)
	hull_center = Vector3(0.0, DEPTH_M * 0.5, 0.0)

	# Let hydro yaw drag own rotational damping — stock 0.7 kills helm on a 960 t hull.
	angular_damp_coeff = 0.18
	angular_damp = angular_damp_coeff
	linear_damp_coeff = 0.04
	linear_damp = linear_damp_coeff

	_clear_generated()
	_build_hull_visual()
	_build_hull_collision()
	_add_systems(stations)
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


func _add_systems(stations: HullStations) -> void:
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
	hydro.wind_frontal_area = BEAM_M * DEPTH_M * 0.4
	hydro.wind_lateral_area = LOA_M * DEPTH_M * 0.5
	add_child(hydro)

	var prop := PropulsionComponent.new()
	prop.name = "PropulsionComponent"
	## ~0.75 m/s² at full ahead on 960 t — coastal workboat feel, not a barge.
	prop.max_thrust = 720000.0
	prop.stern_offset = Vector3(0.0, 1.2, LOA_M * 0.45)
	prop.fuel_burn_l_per_sec_full = 0.11
	add_child(prop)

	var rudder := RudderComponent.new()
	rudder.name = "RudderComponent"
	## Enough to turn 960 t at speed without snappy arcade yaw.
	rudder.max_torque = 12000000.0
	rudder.speed_factor = 0.22
	rudder.min_effectiveness_floor = 0.14
	rudder.rudder_flow_gate = 0.35
	rudder.max_effectiveness = 0.85
	add_child(rudder)

	var thruster := BowThrusterComponent.new()
	thruster.name = "BowThrusterComponent"
	## Lateral ~0.25 m/s²; force must sit at the bow (−Z), not the default midships offset.
	thruster.max_thrust = 240000.0
	thruster.bow_offset = Vector3(0.0, 1.5, -LOA_M * 0.42)
	thruster.stern_offset = Vector3(0.0, 1.5, LOA_M * 0.42)
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
