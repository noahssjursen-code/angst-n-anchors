class_name VesselSpawn
extends RefCounted

## Instantiates hand-authored vessels and applies brick fit-out layouts.

const WORKBOAT_ID := "workboat"
const WORKBOAT_SCENE := "res://scenes/vessels/workboat.tscn"
const WORKBOAT_SCRIPT := "res://scripts/ship/vessels/workboat.gd"


static func instantiate(vessel_id: String = WORKBOAT_ID, brick_layout: Dictionary = {}) -> BoatBody:
	var id := vessel_id.strip_edges()
	if id.is_empty():
		id = WORKBOAT_ID
	var boat := _instantiate_workboat()
	if boat != null:
		_apply_fitout(boat, brick_layout if not brick_layout.is_empty() else default_brick_layout(id))
	return boat


static func instantiate_from_path(path: String, brick_layout: Dictionary = {}) -> BoatBody:
	var p := path.strip_edges()
	if p.is_empty():
		return instantiate(WORKBOAT_ID, brick_layout)
	if p.ends_with(".tscn") or p.ends_with(".scn"):
		if not ResourceLoader.exists(p):
			push_error("VesselSpawn: scene missing: " + p)
			return instantiate(WORKBOAT_ID, brick_layout)
		var packed := load(p) as PackedScene
		if packed == null:
			push_error("VesselSpawn: not a PackedScene: " + p)
			return instantiate(WORKBOAT_ID, brick_layout)
		var node := packed.instantiate()
		if node is BoatBody:
			var boat := node as BoatBody
			_ensure_assembled(boat)
			_apply_fitout(boat, brick_layout if not brick_layout.is_empty() else default_brick_layout(WORKBOAT_ID))
			return boat
		push_error("VesselSpawn: scene root must be BoatBody: " + p)
		if node != null:
			node.queue_free()
		return instantiate(WORKBOAT_ID, brick_layout)
	return instantiate(WORKBOAT_ID, brick_layout)


static func instantiate_from_record(record: Dictionary) -> BoatBody:
	var normalized := normalize_record(record)
	var path := resolve_template_path(normalized)
	var layout: Dictionary = brick_layout_of(normalized)
	var boat: BoatBody = null
	if not path.is_empty():
		boat = instantiate_from_path(path, layout)
	else:
		boat = instantiate(str(normalized.get("hull_id", WORKBOAT_ID)), layout)
	apply_identity(boat, normalized)
	return boat


static func scene_path_for(_vessel_id: String) -> String:
	return WORKBOAT_SCENE


static func default_brick_layout(vessel_id: String = WORKBOAT_ID) -> Dictionary:
	## Bare deck — humans place every brick.
	return {"hull_id": vessel_id, "cells": {}}


static func default_owned_record() -> Dictionary:
	var uid := "workboat_%d" % Time.get_unix_time_from_system()
	return normalize_record({
		"uid": uid,
		"hull_id": WORKBOAT_ID,
		"name": "Workboat",
		"display": "Workboat  •  30 × 24 m",
		"template_path": WORKBOAT_SCENE,
		"scene_path": WORKBOAT_SCENE,
		"brick_layout": default_brick_layout(WORKBOAT_ID),
	})


static func brick_layout_of(record: Dictionary) -> Dictionary:
	var raw: Variant = record.get("brick_layout", {})
	if typeof(raw) == TYPE_DICTIONARY and not (raw as Dictionary).is_empty():
		return (raw as Dictionary).duplicate(true)
	# Migrate legacy attachments[] → starter layout
	return default_brick_layout(str(record.get("hull_id", WORKBOAT_ID)))


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


static func normalize_record(record: Dictionary) -> Dictionary:
	var out := record.duplicate(true)
	if not out.has("brick_layout") or typeof(out.get("brick_layout", null)) != TYPE_DICTIONARY \
			or (out.get("brick_layout", {}) as Dictionary).is_empty():
		out["brick_layout"] = default_brick_layout(str(out.get("hull_id", WORKBOAT_ID)))
	var custom_name := str(out.get("name", "")).strip_edges()
	if custom_name.is_empty():
		out["name"] = vessel_name_of(out)
	else:
		out["name"] = custom_name
	# Drop retired kit fields gently (leave attachments if present for old saves, unused).
	return out


static func resolve_template_path(record: Dictionary) -> String:
	var path := str(record.get("scene_path", record.get("template_path", "")))
	if path.ends_with(".tscn") or path.ends_with(".scn"):
		if ResourceLoader.exists(path):
			return path
	elif not path.is_empty():
		return WORKBOAT_SCENE
	var hull_id := str(record.get("hull_id", ""))
	if hull_id.is_empty():
		return WORKBOAT_SCENE
	return HullRegistry.scene_path_for(hull_id)


static func resolve_deployable_record(record: Dictionary) -> Dictionary:
	if record.is_empty():
		return {}
	var out := normalize_record(record)
	var path := resolve_template_path(out)
	if path.is_empty():
		return {}
	out["template_path"] = path
	out["scene_path"] = path
	return out


static func _apply_fitout(boat: BoatBody, layout: Dictionary) -> void:
	if boat == null:
		return
	if boat.has_method("apply_brick_layout"):
		boat.call("apply_brick_layout", layout)
	else:
		var bl := BrickLayout.from_dict(layout)
		DeckFitout.apply(boat, bl)


static func _instantiate_workboat() -> BoatBody:
	if ResourceLoader.exists(WORKBOAT_SCENE):
		var packed := load(WORKBOAT_SCENE) as PackedScene
		if packed != null:
			var node := packed.instantiate()
			if node is BoatBody:
				var boat := node as BoatBody
				_ensure_assembled(boat)
				return boat
			if node != null:
				node.queue_free()
	var script := load(WORKBOAT_SCRIPT) as GDScript
	if script != null and script.has_method("build"):
		return script.call("build") as BoatBody
	push_error("VesselSpawn: workboat scene/script missing")
	return null


static func _ensure_assembled(boat: BoatBody) -> void:
	if boat == null:
		return
	if boat.get_node_or_null("HullVisual") != null:
		return
	if boat.has_method("_assemble"):
		boat.call("_assemble")
