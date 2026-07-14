extends Node

var _failures := PackedStringArray()


func _ready() -> void:
	_test_registered_hulls()
	_test_catamaran_twin_hulls()
	_test_prebuilt_catalog_workflow()
	if _failures.is_empty():
		print("Hull form geometry: all loft, collision, physics, and yard checks passed")
		get_tree().quit()
	else:
		for failure in _failures:
			push_error("Hull form geometry: " + failure)
		get_tree().quit(1)


func _test_registered_hulls() -> void:
	var entries := HullRegistry.catalog()
	_check(entries.size() >= 9, "all hand-authored and catalog hulls are registered")
	for entry in entries:
		var hull_id := str(entry.get("id", ""))
		var boat := HullRegistry.build_hull(hull_id)
		_check(boat != null, "%s builds" % hull_id)
		if boat == null:
			continue
		var stations := boat.hull_stations
		_check(stations != null and not stations.stations.is_empty(), "%s has stations" % hull_id)
		if stations != null and not stations.stations.is_empty():
			_check(not stations.form_id.is_empty(), "%s uses a hull-form preset" % hull_id)
			var target := boat.displacement_t * 1000.0 / 1025.0
			var actual := stations.volume_below(boat.draft_m)
			var error := absf(actual - target) / maxf(target, 0.001)
			_check(error < 0.015, "%s displacement-at-draft error %.3f" % [hull_id, error])
			var mid := stations.stations.size() / 2
			var bottom := stations.half_beam_at(mid, stations.keel_y)
			var waterline := stations.half_beam_at(mid, stations.design_draft_m)
			var deck := stations.half_beam_at(mid, stations.deck_y)
			_check(bottom < waterline, "%s bottom tapers into bilge" % hull_id)
			_check(waterline < deck, "%s waterline flares outward to deck" % hull_id)
		var grid := HullRegistry.make_grid(hull_id)
		_check(
			grid.bow_taper_cells == int(grid.width / 2),
			"%s deck bow is an exact half-beam 45-degree taper" % hull_id
		)
		_check(_mesh_faces_are_valid(boat), "%s loft mesh has valid triangles" % hull_id)
		var collision_count := _collision_shape_count(boat)
		_check(collision_count >= 4, "%s has convex collision slices" % hull_id)
		_check(collision_count <= 20, "%s collision slice count is bounded" % hull_id)
		boat.free()


func _test_catamaran_twin_hulls() -> void:
	var boat := HullRegistry.build_hull("passenger_catamaran")
	if boat == null:
		_check(false, "catamaran builds for twin-hull checks")
		return
	var port := boat.get_node_or_null("StripBuoyancyComponent") as StripBuoyancyComponent
	var starboard := boat.get_node_or_null("StripBuoyancyStarboard") as StripBuoyancyComponent
	_check(port != null and starboard != null, "catamaran has two buoyancy components")
	if port != null and starboard != null:
		_check(port.hull_center_x_m < 0.0, "port demihull buoyancy is offset to port")
		_check(starboard.hull_center_x_m > 0.0, "starboard demihull buoyancy is offset to starboard")
		_check(
			is_equal_approx(port.damping_mass_fraction + starboard.damping_mass_fraction, 1.0),
			"catamaran damping mass is split across demihulls"
		)
	var hydro := boat.get_node_or_null("HydrodynamicsComponent") as HydrodynamicsComponent
	_check(
		hydro != null and is_equal_approx(hydro.wetted_area_multiplier, 2.0),
		"catamaran drag accounts for both demihulls"
	)
	var visual := boat.get_node_or_null("HullVisual")
	_check(
		visual != null
			and visual.get_node_or_null("HullPort") != null
			and visual.get_node_or_null("HullStarboard") != null,
		"catamaran renders two lofted demihulls"
	)
	boat.free()


func _test_prebuilt_catalog_workflow() -> void:
	var found := false
	for entry in PrebuiltVesselCatalog.catalog_entries():
		if str(entry.get("prebuilt_id", "")) != "short_sea_container_150":
			continue
		found = true
		_check(int(entry.get("price_marks", -1)) == 0, "saved zero shipwright price is preserved")
		_check(str(entry.get("scene_path", "")).is_empty(), "catalog hull needs no scene path")
		var record := VesselSpawn.normalize_record({
			"uid": "hull_form_catalog_test",
			"hull_id": str(entry.get("hull_id", "")),
			"name": "Loft Test",
			"scene_path": "",
			"brick_layout": entry.get("prebuilt_layout", {}),
		})
		_check(
			not VesselSpawn.resolve_deployable_record(record).is_empty(),
			"catalog hull remains Harbour Master deployable without a scene"
		)
		break
	_check(found, "saved container appears in shipwright prebuilt catalog")
	var payload := ShipyardBrickEditor.make_prebuilt_payload(
		"price_test",
		"Price Test",
		HullRegistry.get_by_id("container_feeder_small"),
		{"hull_id": "container_feeder_small", "cells": {}},
		4321
	)
	_check(int(payload.get("price_marks", 0)) == 4321, "editor payload preserves explicit price")


func _mesh_faces_are_valid(boat: BoatBody) -> bool:
	var visual := boat.get_node_or_null("HullVisual")
	if visual == null:
		return false
	var triangle_count := 0
	for child in visual.get_children():
		if not child is MeshInstance3D:
			continue
		var mesh := (child as MeshInstance3D).mesh
		if mesh == null or not str(child.name).begins_with("Hull"):
			continue
		var faces := mesh.get_faces()
		if faces.size() % 3 != 0:
			return false
		for i in range(0, faces.size(), 3):
			var area := ((faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i])).length() * 0.5
			if area <= 0.000001:
				continue
			triangle_count += 1
	return triangle_count > 8


func _collision_shape_count(boat: BoatBody) -> int:
	var count := 0
	for child in boat.get_children():
		if child is CollisionShape3D and str(child.name).begins_with("HullCollision"):
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
