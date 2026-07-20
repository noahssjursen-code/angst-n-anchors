class_name WorldTrafficService
extends Node3D

## Local single-player authority and multiplayer-ready client interest seam.
## The simulator owns all outcomes. This node only materializes nearby records;
## changing presentation tiers can never change routes, signals or berth order.

signal fleet_changed(vessel_count: int)
signal presentation_changed(summary: Dictionary)

const PRESENTATION_POLICY := preload(
	"res://scripts/traffic/traffic_vessel_presentation_policy.gd")
const PROXY_CACHE := preload("res://scripts/traffic/traffic_vessel_proxy_cache.gd")
const PREBUILT_CATALOG_PATH := "res://scripts/ship/prebuilt_vessel_catalog.gd"
const HULL_REGISTRY_PATH := "res://scripts/ship/hull_registry.gd"
const VESSEL_SPAWN_PATH := "res://scripts/ship/vessel_spawn.gd"

const AUTHORITY_TICK_S := 0.50
const INTEREST_REFRESH_S := 0.50
const PHYSICS_RADIUS_M := 240.0
const FULL_RADIUS_M := 1100.0
const PROXY_RADIUS_M := 7200.0
const MAX_PHYSICS_VESSELS := 4
const MAX_FULL_VESSELS := 8
const MAX_PROXY_VESSELS := 192
const COMPANY_NAMES := [
	"Nordhavn Frakt", "Skarv Line", "Vestfjord Bulk", "Anchor Coastal",
]

var network: ShippingLaneNetwork
var world_layout: WorldLayout
var world_seed := 0

var _simulator: ShippingLaneTrafficSimulator
var _records: Dictionary = {}
var _presentation: Dictionary = {}
var _metadata: Dictionary = {}
var _map_contacts_cache: Array[Dictionary] = []
var _prebuilt_entries: Array[Dictionary] = []
var _authority_elapsed := 0.0
var _interest_elapsed := 0.0
var _presentation_summary: Dictionary = {}
var _fleet_serial := 0
var _last_authority_ms := 0.0
var _peak_authority_ms := 0.0
var _last_interest_ms := 0.0


func _ready() -> void:
	add_to_group("world_traffic_service")
	set_process(false)
	set_physics_process(false)
	# Dedicated/headless authorities retain all vessel data and never load a
	# visual vessel dependency graph.
	if DisplayServer.get_name() == "headless":
		return
	var catalog := load(PREBUILT_CATALOG_PATH)
	var hull_registry := load(HULL_REGISTRY_PATH)
	# Traffic presentation may use all official editor templates, including
	# drafts. These are visual sources, not ships being sold or deployed into the
	# player's registry; shop certification must not make a traffic model vanish.
	for entry in catalog.call("catalog_entries", true):
		var id := str(entry.get("prebuilt_id", ""))
		if id in ["28_10_m", "bulk_small"] and bool(hull_registry.call("is_known_hull",
				str(entry.get("hull_id", "")))):
			_prebuilt_entries.append(entry)


func configure(
		value: ShippingLaneNetwork,
		layout: WorldLayout,
		seed: int,
) -> void:
	network = value
	world_layout = layout
	world_seed = seed


func spawn_debug_fleet(count: int) -> Dictionary:
	if network == null:
		return {"ok": false, "error": "shipping lane network is not ready"}
	clear_debug_fleet()
	_fleet_serial += 1
	var started := Time.get_ticks_usec()
	_simulator = ShippingLaneTrafficSimulator.new()
	_simulator.configure(network, maxi(count, 1), world_seed + _fleet_serial * 7919,
		world_layout)
	_build_metadata(_simulator.presentation_records())
	_pull_authority_snapshot()
	_refresh_interest(true)
	set_process(true)
	set_physics_process(true)
	fleet_changed.emit(_records.size())
	return {
		"ok": true,
		"vessel_count": _records.size(),
		"configure_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"presentation": _presentation_summary.duplicate(true),
	}


func clear_debug_fleet() -> void:
	for state_value in _presentation.values():
		var state := state_value as Dictionary
		var node := state.get("node") as Node
		if node != null and is_instance_valid(node):
			node.queue_free()
	_presentation.clear()
	_records.clear()
	_metadata.clear()
	_map_contacts_cache.clear()
	_simulator = null
	_authority_elapsed = 0.0
	_interest_elapsed = 0.0
	_presentation_summary.clear()
	set_process(false)
	set_physics_process(false)
	fleet_changed.emit(0)


func vessel_count() -> int:
	return _records.size()


func presentation_summary() -> Dictionary:
	return _presentation_summary.duplicate(true)


func get_debug_stats() -> Dictionary:
	var summary := _simulator.summary() if _simulator != null else {}
	return {
		"records": _records.size(),
		"materialized": _presentation.size(),
		"physics": (_presentation_summary.get("physics_ids", PackedStringArray()) as PackedStringArray).size(),
		"full": (_presentation_summary.get("full_ids", PackedStringArray()) as PackedStringArray).size(),
		"proxy": (_presentation_summary.get("proxy_ids", PackedStringArray()) as PackedStringArray).size(),
		"data_only": int(_presentation_summary.get("data_only_count", _records.size())),
		"authority_ms": _last_authority_ms,
		"authority_peak_ms": _peak_authority_ms,
		"interest_ms": _last_interest_ms,
		"states": summary.get("states", {}),
		"collisions": int(summary.get("collisions", 0)),
		"route_failures": int(summary.get("route_failures", 0)),
	}


func traffic_report() -> String:
	return _simulator.generate_report() if _simulator != null else "No debug traffic fleet"


## Compact AIS-style view. It deliberately contains every authoritative record,
## including vessels that have no 3D node on this client.
func map_contacts() -> Array[Dictionary]:
	return _map_contacts_cache


func _process(delta: float) -> void:
	if _simulator == null:
		return
	_authority_elapsed += delta
	if _authority_elapsed >= AUTHORITY_TICK_S:
		var authority_started := Time.get_ticks_usec()
		_simulator.advance(_authority_elapsed)
		_authority_elapsed = 0.0
		_pull_authority_snapshot()
		_last_authority_ms = float(Time.get_ticks_usec() - authority_started) / 1000.0
		_peak_authority_ms = maxf(_peak_authority_ms, _last_authority_ms)
	_interest_elapsed += delta
	if _interest_elapsed >= INTEREST_REFRESH_S:
		_interest_elapsed = 0.0
		var interest_started := Time.get_ticks_usec()
		_refresh_interest(false)
		_last_interest_ms = float(Time.get_ticks_usec() - interest_started) / 1000.0
	_interpolate_non_physics(delta)


func _physics_process(_delta: float) -> void:
	for vessel_id in _presentation.keys():
		var state := _presentation[vessel_id] as Dictionary
		if not bool(state.get("physics", false)):
			continue
		var ship := state.get("node") as RigidBody3D
		if ship == null or not is_instance_valid(ship):
			continue
		var target := state.get("target_position", ship.global_position) as Vector3
		var heading := state.get("target_heading", Vector2(0.0, -1.0)) as Vector2
		var error := Vector2(target.x - ship.global_position.x,
			target.z - ship.global_position.z)
		var state_name := str((_records.get(vessel_id, {}) as Dictionary).get("state", ""))
		var commanded_speed := 0.0 if state_name.begins_with("waiting") \
			or state_name == "docked" else 7.0
		var desired := heading.normalized() * commanded_speed + error.limit_length(18.0) * 1.2
		ship.linear_velocity.x = desired.x
		ship.linear_velocity.z = desired.y
		var wanted_yaw := atan2(-heading.x, -heading.y)
		var yaw_error := wrapf(wanted_yaw - ship.global_rotation.y, -PI, PI)
		ship.angular_velocity.y = clampf(yaw_error * 1.8, -0.8, 0.8)


func _pull_authority_snapshot() -> void:
	_records.clear()
	_map_contacts_cache.clear()
	for record in _simulator.presentation_records():
		var vessel_id := str(record.get("id", ""))
		_records[vessel_id] = record
		var contact := record.duplicate(false)
		contact.merge(_metadata.get(vessel_id, {}) as Dictionary, true)
		_map_contacts_cache.append(contact)
	for vessel_id in _presentation.keys():
		if not _records.has(vessel_id):
			_remove_presentation(str(vessel_id))
			continue
		var record := _records[vessel_id] as Dictionary
		var point := record.get("position", Vector2.ZERO) as Vector2
		var state := _presentation[vessel_id] as Dictionary
		state["target_position"] = Vector3(
			point.x, float(state.get("presentation_y", 0.0)), point.y)
		state["target_heading"] = record.get("heading", Vector2(0.0, -1.0))
		_update_label(state, record)


func _refresh_interest(force: bool) -> void:
	if _records.is_empty():
		return
	var records: Array[Dictionary] = []
	for record in _records.values():
		records.append(record as Dictionary)
	var observer3 := WorldReference.stream_position(get_viewport())
	var selected := PRESENTATION_POLICY.select(
		records,
		Vector2(observer3.x, observer3.z),
		FULL_RADIUS_M,
		PROXY_RADIUS_M,
		MAX_FULL_VESSELS,
		PHYSICS_RADIUS_M,
		MAX_PHYSICS_VESSELS,
		MAX_PROXY_VESSELS,
	)
	var full := _id_set(selected.get("full_ids", PackedStringArray()))
	var physics := _id_set(selected.get("physics_ids", PackedStringArray()))
	var proxies := _id_set(selected.get("proxy_ids", PackedStringArray()))
	for vessel_id in _presentation.keys():
		if not full.has(vessel_id) and not proxies.has(vessel_id):
			_remove_presentation(str(vessel_id))
	for vessel_id in full:
		_ensure_presentation(str(vessel_id), "full", physics.has(vessel_id), force)
	for vessel_id in proxies:
		_ensure_presentation(str(vessel_id), "proxy", false, force)
	_presentation_summary = selected
	_presentation_summary["materialized"] = _presentation.size()
	presentation_changed.emit(_presentation_summary.duplicate(true))


func _ensure_presentation(
		vessel_id: String, kind: String, physics: bool, force: bool,
) -> void:
	var old := _presentation.get(vessel_id, {}) as Dictionary
	var needs_replacement := old.is_empty() or str(old.get("kind", "")) != kind
	if needs_replacement:
		var record := _records.get(vessel_id, {}) as Dictionary
		var node := _make_full_ship(vessel_id) if kind == "full" \
			else _make_proxy(vessel_id, record)
		# Never punch a hole in the world while a higher-detail representation
		# is unavailable. Keep the existing proxy until its replacement exists.
		if node == null:
			return
		add_child(node)
		var point := record.get("position", Vector2.ZERO) as Vector2
		var heading := record.get("heading", Vector2(0.0, -1.0)) as Vector2
		node.global_position = Vector3(point.x, 0.0, point.y)
		if kind == "full" and node.has_method("place_at_waterline"):
			# The real hull's origin is not its waterline. Place after assigning X/Z
			# so the vessel samples the correct local wave and keeps its design draft.
			node.call("place_at_waterline", WaveSurface.WATER_LEVEL)
		node.global_rotation.y = atan2(-heading.x, -heading.y)
		var presentation_y := node.global_position.y
		var replacement := {
			"node": node,
			"kind": kind,
			"physics": false,
			"target_position": node.global_position,
			"target_heading": heading,
			"presentation_y": presentation_y,
			"label": _make_label(node),
		}
		var old_node := old.get("node") as Node
		_presentation[vessel_id] = replacement
		old = replacement
		_update_label(replacement, record)
		if old_node != null and is_instance_valid(old_node):
			old_node.queue_free()
	if kind == "full" and (force or bool(old.get("physics", false)) != physics):
		_configure_full_physics(old.get("node") as Node3D, physics)
		old["physics"] = physics


func _make_full_ship(vessel_id: String) -> Node3D:
	if _prebuilt_entries.is_empty():
		return null
	var metadata := _metadata.get(vessel_id, {}) as Dictionary
	var wanted_kind := str(metadata.get("vessel_kind", "general_cargo"))
	var entry := _prebuilt_entries[0]
	for candidate in _prebuilt_entries:
		if (wanted_kind == "bulk") == (str(candidate.get("prebuilt_id", "")) == "bulk_small"):
			entry = candidate
			break
	var record := {
		"uid": vessel_id,
		"hull_id": str(entry.get("hull_id", "")),
		"name": str(metadata.get("name", vessel_id)),
		"shaft_power_kw": float(entry.get("shaft_power_kw", 1.0)),
		"registration_id": str(entry.get("registration_id", "")),
		"brick_layout": (entry.get("prebuilt_layout", {}) as Dictionary).duplicate(true),
	}
	var spawn_script := load(VESSEL_SPAWN_PATH)
	var ship := spawn_script.call("instantiate_from_record", record) as Node3D
	if ship == null:
		return null
	ship.name = vessel_id
	ship.set("automatic_physics_lod", false)
	call_deferred("_populate_full_cargo", vessel_id, ship)
	return ship


func _populate_full_cargo(vessel_id: String, ship: Node3D) -> void:
	if ship == null or not is_instance_valid(ship) or not ship.has_method("get_cargo_pads"):
		return
	var metadata := _metadata.get(vessel_id, {}) as Dictionary
	if str(metadata.get("vessel_kind", "")) != "general_cargo":
		return
	var record := _records.get(vessel_id, {}) as Dictionary
	var origin_id := _port_id_for_token(str(record.get("source_token_id", "")))
	for pad_value in ship.call("get_cargo_pads") as Array:
		var pad := pad_value as Node
		if pad != null and pad.has_method("prefill_general_cargo"):
			pad.call("prefill_general_cargo", -1, origin_id, 0.72)


func _make_proxy(vessel_id: String, record: Dictionary) -> Node3D:
	var metadata := _metadata.get(vessel_id, {}) as Dictionary
	var proxy := PROXY_CACHE.instance(str(metadata.get("vessel_kind", "general_cargo")),
		float(record.get("length_m", 42.0)), float(record.get("beam_m", 10.0)))
	proxy.name = vessel_id
	return proxy


func _make_label(parent: Node3D) -> Label3D:
	var label := Label3D.new()
	label.name = "TrafficState"
	label.position = Vector3(0.0, 15.0, 0.0)
	label.font_size = 22
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	parent.add_child(label)
	WorldGizmos.register(label, WorldGizmos.LAYER_NAVIGATION)
	return label


func _configure_full_physics(ship: Node3D, enabled: bool) -> void:
	if ship == null:
		return
	var body := ship as RigidBody3D
	if body == null:
		return
	if enabled:
		body.collision_layer = 2
		body.collision_mask = 3
		ship.call("set_physics_quality", 0)
	else:
		ship.call("set_physics_quality", 2)
		body.collision_layer = 0
		body.collision_mask = 0


func _interpolate_non_physics(delta: float) -> void:
	var alpha := 1.0 - exp(-8.0 * delta)
	for state_value in _presentation.values():
		var state := state_value as Dictionary
		if bool(state.get("physics", false)):
			continue
		var node := state.get("node") as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var target := state.get("target_position", node.global_position) as Vector3
		node.global_position = node.global_position.lerp(target, alpha)
		var heading := state.get("target_heading", Vector2(0.0, -1.0)) as Vector2
		var yaw := atan2(-heading.x, -heading.y)
		node.global_rotation.y = lerp_angle(node.global_rotation.y, yaw, alpha)


func _update_label(state: Dictionary, record: Dictionary) -> void:
	var label := state.get("label") as Label3D
	if label == null:
		return
	var vessel_id := str(record.get("id", ""))
	var meta := _metadata.get(vessel_id, {}) as Dictionary
	var destination := _port_name_for_token(str(record.get("destination_token_id", "")))
	var status := str(record.get("state", "unknown")).replace("_", " ")
	if status.begins_with("traveling"):
		status = "traveling to %s" % destination
	elif status == "waiting berth":
		status = "waiting for berth at %s" % destination
	elif status == "waiting signal":
		status = "waiting for signal"
	label.text = "%s · %s\n%s" % [
		str(meta.get("name", vessel_id)), str(meta.get("company_name", "Independent")), status,
	]


func _build_metadata(records: Array[Dictionary]) -> void:
	_metadata.clear()
	for record in records:
		var index := int(record.get("index", 0))
		var vessel_id := str(record.get("id", ""))
		var kind := "bulk" if index % 3 == 1 else "general_cargo"
		_metadata[vessel_id] = {
			"name": "%s %02d" % ["Bulk" if kind == "bulk" else "Coaster", index + 1],
			"company_id": "company-%02d" % (index % COMPANY_NAMES.size()),
			"company_name": COMPANY_NAMES[index % COMPANY_NAMES.size()],
			"contract_id": "debug-contract-%04d" % (index + 1),
			"vessel_kind": kind,
		}


func _port_name_for_token(token_id: String) -> String:
	var port_id := _port_id_for_token(token_id)
	var catalog := get_node_or_null("/root/PortCatalog")
	if catalog != null:
		var info := catalog.call("get_port_info", port_id) as Dictionary
		return str(info.get("display_name", port_id))
	return port_id


func _port_id_for_token(token_id: String) -> String:
	if network == null:
		return ""
	var token := network.berth_tokens.get(token_id, {}) as Dictionary
	return str(token.get("port_id", ""))


func _remove_presentation(vessel_id: String) -> void:
	var state := _presentation.get(vessel_id, {}) as Dictionary
	var node := state.get("node") as Node
	if node != null and is_instance_valid(node):
		node.queue_free()
	_presentation.erase(vessel_id)


static func _id_set(ids: PackedStringArray) -> Dictionary:
	var result := {}
	for id in ids:
		result[id] = true
	return result
