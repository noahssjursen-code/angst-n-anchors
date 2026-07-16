class_name VesselSpawn
extends RefCounted

## Instantiates hand-authored vessels and applies brick fit-out layouts.

const TRAWLER_SMALL_ID := "hull_28x10"
const TRAWLER_SMALL_SCENE := "res://scenes/vessels/fishing_trawler_small.tscn"
const TRAWLER_SMALL_SCRIPT := "res://scripts/ship/vessels/fishing_trawler_small.gd"
const PASSENGER_CATAMARAN_ID := "hull_45x16_cat"
const PASSENGER_CATAMARAN_SCENE := "res://scenes/vessels/passenger_catamaran.tscn"
const PASSENGER_CATAMARAN_SCRIPT := "res://scripts/ship/vessels/passenger_catamaran.gd"


static func instantiate(
	vessel_id: String = TRAWLER_SMALL_ID,
	brick_layout: Dictionary = {},
	registration_id: String = "",
) -> BoatBody:
	var id := HullRegistry.resolve_network_hull_id(vessel_id)
	var boat := _instantiate_hull(id)
	if boat != null:
		_apply_fitout(
			boat,
			brick_layout if not brick_layout.is_empty() else default_brick_layout(id),
			registration_id,
		)
	return boat


static func instantiate_from_path(
	path: String,
	brick_layout: Dictionary = {},
	registration_id: String = "",
) -> BoatBody:
	var p := path.strip_edges()
	if p.is_empty():
		return instantiate(TRAWLER_SMALL_ID, brick_layout, registration_id)
	if p.ends_with(".tscn") or p.ends_with(".scn"):
		if not ResourceLoader.exists(p):
			push_error("VesselSpawn: scene missing: " + p)
			return instantiate(TRAWLER_SMALL_ID, brick_layout, registration_id)
		var packed := load(p) as PackedScene
		if packed == null:
			push_error("VesselSpawn: not a PackedScene: " + p)
			return instantiate(TRAWLER_SMALL_ID, brick_layout, registration_id)
		var node := packed.instantiate()
		if node is BoatBody:
			var boat := node as BoatBody
			_ensure_assembled(boat)
			var hull_id := HullRegistry.resolve_id_from_template(p, TRAWLER_SMALL_ID)
			_apply_fitout(
				boat,
				brick_layout if not brick_layout.is_empty() else default_brick_layout(hull_id),
				registration_id,
			)
			return boat
		push_error("VesselSpawn: scene root must be BoatBody: " + p)
		if node != null:
			node.queue_free()
		return instantiate(TRAWLER_SMALL_ID, brick_layout, registration_id)
	return instantiate(TRAWLER_SMALL_ID, brick_layout, registration_id)


static func instantiate_from_record(record: Dictionary) -> BoatBody:
	var normalized := resolve_deployable_record(record)
	if normalized.is_empty():
		push_error("VesselSpawn: refused unregistered or noncompliant vessel record")
		return null
	var path := resolve_template_path(normalized)
	var layout: Dictionary = brick_layout_of(normalized)
	var registration_id := str(normalized.get("registration_id", ""))
	var boat: BoatBody = null
	if not path.is_empty():
		boat = instantiate_from_path(path, layout, registration_id)
	else:
		boat = instantiate(
			str(normalized.get("hull_id", TRAWLER_SMALL_ID)), layout, registration_id
		)
	apply_propulsion_override(boat, normalized)
	apply_identity(boat, normalized)
	return boat


static func scene_path_for(vessel_id: String) -> String:
	return HullRegistry.scene_path_for(vessel_id)


static func default_brick_layout(vessel_id: String = TRAWLER_SMALL_ID) -> Dictionary:
	## Bare deck — humans place every brick.
	return {"hull_id": HullRegistry.resolve_network_hull_id(vessel_id), "cells": {}}


static func default_owned_record() -> Dictionary:
	## Free starter — small coastal trawler.
	var uid := new_vessel_uid(TRAWLER_SMALL_ID)
	var layout := default_brick_layout(TRAWLER_SMALL_ID)
	for entry in PrebuiltVesselCatalog.catalog_entries():
		if str(entry.get("prebuilt_id", "")) == "fishing_trawler":
			layout = (entry.get("prebuilt_layout", {}) as Dictionary).duplicate(true)
			break
	return normalize_record({
		"uid": uid,
		"hull_id": TRAWLER_SMALL_ID,
		"name": "Day Trawler",
		"display": "Day Trawler",
		"shaft_power_kw": 1871.0,
		"registration_id": "fishing_vessel",
		"brick_layout": layout,
	})


## Persistent identity is random, not second-resolution time. Two commissions
## (or server rows hydrated in one frame) must never alias the same ledger row.
static func new_vessel_uid(hull_id: String) -> String:
	var id := HullRegistry.resolve_network_hull_id(hull_id)
	var random_bytes := Crypto.new().generate_random_bytes(16)
	if not random_bytes.is_empty():
		return "%s_%s" % [id, random_bytes.hex_encode()]
	return "%s_%d_%d" % [
		id,
		int(Time.get_unix_time_from_system() * 1000.0),
		Time.get_ticks_usec(),
	]


static func brick_layout_of(record: Dictionary) -> Dictionary:
	var raw: Variant = record.get("brick_layout", {})
	if typeof(raw) == TYPE_DICTIONARY and not (raw as Dictionary).is_empty():
		return (raw as Dictionary).duplicate(true)
	return default_brick_layout(str(record.get("hull_id", TRAWLER_SMALL_ID)))


## Captain-chosen name, falling back to hull catalog label.
static func vessel_name_of(record: Dictionary) -> String:
	var custom := str(record.get("name", "")).strip_edges()
	if not custom.is_empty():
		return custom
	var display := str(record.get("display", "")).strip_edges()
	if "  •  " in display:
		return display.split("  •  ")[0].strip_edges()
	if not display.is_empty():
		return display
	return "Vessel"


static func apply_identity(boat: BoatBody, record: Dictionary) -> void:
	if boat == null:
		return
	var vessel_name := vessel_name_of(record)
	var ctrl := boat.get_node_or_null("BoatController") as BoatController
	if ctrl != null:
		ctrl.ship_name = vessel_name
	boat.set_meta("vessel_display_name", vessel_name)
	boat.set_meta("registration_id", str(record.get("registration_id", "")))
	boat.set_meta("vessel_uid", str(record.get("uid", "")))


## Power belongs to the finished store ship, not the reusable hull component.
## Scale bollard thrust with power so each hull keeps its authored cruise/thrust ratio.
static func apply_propulsion_override(boat: BoatBody, record: Dictionary) -> void:
	if boat == null or not record.has("shaft_power_kw"):
		return
	var requested_kw := maxf(float(record.get("shaft_power_kw", 0.0)), 1.0)
	var profile := boat.physics_profile
	var original_kw := requested_kw
	var original_bollard := 0.0
	if profile != null:
		original_kw = maxf(profile.shaft_power_kw, 1.0)
		original_bollard = maxf(profile.bollard_thrust_n, 1.0)
		profile.shaft_power_kw = requested_kw
		profile.bollard_thrust_n = original_bollard * requested_kw / original_kw
	var prop := boat.get_node_or_null("PropulsionComponent") as PropulsionComponent
	if prop != null:
		prop.shaft_power_kw = requested_kw
		if original_bollard > 0.0:
			prop.max_thrust = original_bollard * requested_kw / original_kw


static func normalize_record(record: Dictionary) -> Dictionary:
	var out := record.duplicate(true)
	var hull_id := HullRegistry.resolve_network_hull_id(str(out.get("hull_id", TRAWLER_SMALL_ID)))
	out["hull_id"] = hull_id
	if not out.has("brick_layout") or typeof(out.get("brick_layout", null)) != TYPE_DICTIONARY \
			or (out.get("brick_layout", {}) as Dictionary).is_empty():
		out["brick_layout"] = default_brick_layout(hull_id)
	var custom_name := str(out.get("name", "")).strip_edges()
	if custom_name.is_empty():
		out["name"] = vessel_name_of(out)
	else:
		out["name"] = custom_name
	if out.has("shaft_power_kw"):
		out["shaft_power_kw"] = maxf(float(out.get("shaft_power_kw", 0.0)), 1.0)
	else:
		var hull := HullRegistry.get_by_id(hull_id)
		out["shaft_power_kw"] = maxf(float(hull.get("default_shaft_power_kw", 1.0)), 1.0)
	var registration_id := str(out.get("registration_id", "")).strip_edges()
	out["registration_id"] = registration_id if not registration_id.is_empty() else "review_required"
	return out


static func resolve_template_path(record: Dictionary) -> String:
	var path := str(record.get("scene_path", record.get("template_path", "")))
	if path.ends_with(".tscn") or path.ends_with(".scn"):
		if ResourceLoader.exists(path):
			return path
	var hull_id := str(record.get("hull_id", ""))
	if hull_id.is_empty():
		return TRAWLER_SMALL_SCENE
	return HullRegistry.scene_path_for(hull_id)


static func resolve_deployable_record(record: Dictionary) -> Dictionary:
	if record.is_empty():
		return {}
	var out := normalize_record(record)
	var hull_id := str(out.get("hull_id", "")).strip_edges()
	var path := resolve_template_path(out)
	## Catalog hulls have no .tscn — still deployable via hull_id.
	if path.is_empty() and not HullRegistry.is_known_hull(hull_id):
		return {}
	var registration_id := str(out.get("registration_id", ""))
	if not VesselRegistrationCatalog.has(registration_id):
		return {}
	var layout := BrickLayout.from_dict(brick_layout_of(out))
	var compliance := VesselCompliance.validate(
		layout, hull_id, registration_id, HullRegistry.make_grid(hull_id)
	)
	if not bool(compliance.get("ok", false)):
		return {}
	out["hull_id"] = hull_id
	out["scene_path"] = path
	return out


static func _apply_fitout(
	boat: BoatBody,
	layout: Dictionary,
	registration_id: String = "",
) -> void:
	if boat == null:
		return
	boat.set_meta("registration_id", registration_id)
	if boat.has_method("apply_brick_layout"):
		boat.call("apply_brick_layout", layout)
	else:
		var bl := BrickLayout.from_dict(layout)
		DeckFitout.apply(boat, bl)


static func _instantiate_hull(hull_id: String) -> BoatBody:
	var id := HullRegistry.resolve_network_hull_id(hull_id)
	if HullCatalog.has_id(id):
		return HullRegistry.build_hull(id)
	var scene_path := HullRegistry.scene_path_for(id)
	if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
		var packed := load(scene_path) as PackedScene
		if packed != null:
			var node := packed.instantiate()
			if node is BoatBody:
				var boat := node as BoatBody
				_ensure_assembled(boat)
				return boat
			if node != null:
				node.queue_free()
	return HullRegistry.build_hull(id)


static func _ensure_assembled(boat: BoatBody) -> void:
	if boat == null:
		return
	if boat.get_node_or_null("HullVisual") != null:
		return
	if boat.has_method("_assemble"):
		boat.call("_assemble")
