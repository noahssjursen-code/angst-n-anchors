extends Node

var _failures := PackedStringArray()


func _ready() -> void:
	_test_registered_hulls()
	_test_catamaran_twin_hulls()
	_test_livery_material_slots()
	_test_prebuilt_catalog_workflow()
	_test_shared_hull_power_variants()
	if _failures.is_empty():
		print("Hull form geometry: all loft, collision, physics, and yard checks passed")
		get_tree().quit()
	else:
		for failure in _failures:
			push_error("Hull form geometry: " + failure)
		get_tree().quit(1)


func _test_registered_hulls() -> void:
	var entries := HullRegistry.catalog()
	_check(entries.size() >= 8, "all hand-authored and catalog hulls are registered")
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
		if hull_id == "hull_45x16_cat":
			_check(grid.bow_taper_cells == 0, "catamaran bridge deck is rectangular")
		else:
			_check(
				grid.bow_taper_cells == int(grid.width / 2),
				"%s deck bow uses its declared 45-degree taper" % hull_id
			)
		_check(_mesh_faces_are_valid(boat), "%s loft mesh has valid triangles" % hull_id)
		var collision_count := _collision_shape_count(boat)
		_check(collision_count >= 4, "%s has convex collision slices" % hull_id)
		_check(collision_count <= 20, "%s collision slice count is bounded" % hull_id)
		boat.free()


func _test_catamaran_twin_hulls() -> void:
	var boat := HullRegistry.build_hull("hull_45x16_cat")
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


func _test_livery_material_slots() -> void:
	var boat := HullRegistry.build_hull("hull_28x10")
	if boat == null:
		_check(false, "trawler builds for livery checks")
		return
	var hull := boat.get_node_or_null("HullVisual/HullShell") as MeshInstance3D
	_check(hull != null and hull.mesh.get_surface_count() == 2, "hull exposes topside and keel paint slots")
	if hull != null and hull.mesh.get_surface_count() == 2:
		var default_keel := hull.get_active_material(1) as StandardMaterial3D
		_check(
			default_keel != null and default_keel.albedo_color.r > default_keel.albedo_color.g * 3.0,
			"default anti-fouling keel is red"
		)
		var custom_top := Color(0.08, 0.24, 0.52)
		var custom_keel := Color(0.08, 0.12, 0.10)
		var custom_deck := Color(0.62, 0.58, 0.44)
		boat.apply_hull_livery({
			"topsides_color": custom_top,
			"keel_color": custom_keel,
			"deck_color": custom_deck,
		})
		var top_material := hull.get_active_material(0) as StandardMaterial3D
		var keel_material := hull.get_active_material(1) as StandardMaterial3D
		var deck := boat.get_node_or_null("HullVisual/Deck") as MeshInstance3D
		var deck_material := deck.get_active_material(0) as StandardMaterial3D
		_check(top_material.albedo_color.is_equal_approx(custom_top), "runtime livery recolors topsides")
		_check(keel_material.albedo_color.is_equal_approx(custom_keel), "runtime livery recolors keel")
		_check(deck_material.albedo_color.is_equal_approx(custom_deck), "runtime livery recolors deck")
		var saved := boat.get_meta("hull_livery", {}) as Dictionary
		_check(saved.get("topsides_color", []) is Array, "livery colors serialize as JSON-safe arrays")
	boat.free()


func _test_prebuilt_catalog_workflow() -> void:
	var found := false
	for entry in PrebuiltVesselCatalog.catalog_entries():
		if str(entry.get("prebuilt_id", "")) != "fishing_trawler":
			continue
		found = true
		_check(int(entry.get("price_marks", -1)) >= 0, "ship SKU owns its shipwright price")
		_check(float(entry.get("shaft_power_kw", 0.0)) > 0.0, "ship SKU owns shaft power")
		_check(
			str(entry.get("registration_id", "")) == "fishing_vessel",
			"ship SKU owns its legal registration",
		)
		var record := VesselSpawn.normalize_record({
			"uid": "hull_form_catalog_test",
			"hull_id": str(entry.get("hull_id", "")),
			"name": "Loft Test",
			"scene_path": "",
			"registration_id": entry.get("registration_id", ""),
			"brick_layout": entry.get("prebuilt_layout", {}),
		})
		_check(
			not VesselSpawn.resolve_deployable_record(record).is_empty(),
			"catalog hull remains Harbour Master deployable without a scene"
		)
		break
	_check(found, "certified fishing trawler appears in shipwright prebuilt catalog")
	var payload := ShipyardBrickEditor.make_prebuilt_payload(
		"price_test",
		"Price Test",
		HullRegistry.get_by_id("hull_90x24"),
		{"hull_id": "hull_90x24", "cells": {}},
		4321,
		9876.0
	)
	_check(int(payload.get("price_marks", 0)) == 4321, "editor payload preserves explicit price")
	_check(float(payload.get("shaft_power_kw", 0.0)) == 9876.0, "editor payload preserves ship power")
	_check(not payload.has("scene_path"), "store SKU spawns by hull_id without a scene key")


func _test_shared_hull_power_variants() -> void:
	var layout: Dictionary = {}
	for entry in PrebuiltVesselCatalog.catalog_entries():
		if str(entry.get("prebuilt_id", "")) == "fishing_trawler":
			layout = (entry.get("prebuilt_layout", {}) as Dictionary).duplicate(true)
			break
	if layout.is_empty():
		_check(false, "certified layout exists for shared-hull power variants")
		return
	var slow := VesselSpawn.instantiate_from_record({
		"hull_id": "hull_28x10",
		"name": "Slow fishing workboat",
		"registration_id": "fishing_vessel",
		"shaft_power_kw": 2500.0,
		"brick_layout": layout,
	})
	var fast := VesselSpawn.instantiate_from_record({
		"hull_id": "hull_28x10",
		"name": "Fast fishing workboat",
		"registration_id": "fishing_vessel",
		"shaft_power_kw": 12000.0,
		"brick_layout": layout,
	})
	_check(slow != null and fast != null, "two store ships build from one hull component")
	if slow != null and fast != null:
		_check(is_equal_approx(slow.length_m, fast.length_m), "shared hull keeps identical geometry")
		_check(
			is_equal_approx(slow.physics_profile.shaft_power_kw, 2500.0)
				and is_equal_approx(fast.physics_profile.shaft_power_kw, 12000.0),
			"shared hull accepts different per-ship power",
		)
		slow.free()
		fast.free()


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
				return false
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
