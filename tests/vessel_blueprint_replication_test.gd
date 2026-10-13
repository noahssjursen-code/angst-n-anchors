extends Node

const DrawingScript = preload("res://scripts/network/replication_drawing_service.gd")

class RecordingDrawing extends DrawingScript:
	var applied: Dictionary = {}
	func _apply_remote_ship_layout(ship: BoatBody, layout: Dictionary) -> void:
		applied[ship.get_instance_id()] = layout.duplicate(true)

var failed := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	call_deferred("_run")

func _run() -> void:
	var builds: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/showcases/authority_builds.json"))
	var construction: Dictionary = builds.values()[0]
	check(VesselSync.construction_matches(str(construction.id), construction), "Accepts matching construction and catalog")
	check(not VesselSync.construction_matches("other-version", construction), "Rejects a response for another construction")
	var invalid := construction.duplicate(true)
	invalid.catalog_hash = "different-installed-assets"
	check(not VesselSync.construction_matches(str(invalid.id), invalid), "Rejects incompatible installed catalog")
	invalid = construction.duplicate(true)
	invalid.layout = {}
	check(not VesselSync.construction_matches(str(invalid.id), invalid), "Rejects missing accepted layout")
	var configured := {"hull_id": construction.layout.hull, "brick_layout": construction.layout.duplicate(true), "uid": "keep-me"}
	configured.brick_layout.hull_colors = {"HullUpper": "#ee2211"}
	var row := {"id": "server-stable", "hull_id": construction.layout.hull, "construction_id": construction.id, "catalog_hash": construction.catalog_hash, "layout_hash": "accepted", "brick_layout": construction.layout}
	var patch := VesselSync._layout_patch_from_row(row, configured)
	check(patch.get("brick_layout", {}) == construction.layout, "Accepted server construction replaces stale owned ledger layout")
	check(str(patch.get("construction_id", "")) == str(construction.id), "Accepted construction identity remains paired with layout")
	var data := PlayerData.new()
	configured.server_vessel_id = "server-stable"
	data.upsert_owned_vessel(configured)
	var merged := VesselSync._merge_server_row(data, row)
	check(str(merged.get("uid", "")) == "keep-me", "Fleet refresh preserves vessel UID when no local template file exists")

	var drawing := RecordingDrawing.new()
	add_child(drawing)
	var first := BoatBody.new()
	var second := BoatBody.new()
	drawing.add_child(first)
	drawing.add_child(second)
	first.freeze = true
	second.freeze = true
	first.visible = false
	second.visible = false
	var announcements: Array = []
	drawing.remote_ship_available.connect(func(id: String, _ship: BoatBody) -> void: announcements.append(id))
	drawing._visible_entities = {
		"entity": state_for(first, "vessel-b", "construction:b"),
		"shared": state_for(second, "vessel-c", "construction:b"),
	}
	var accepted_b := {"layout": {"test_version": "b"}, "hash": "b"}
	drawing._finish_layout_request("construction:b", drawing._layout_epoch, accepted_b)
	check(drawing.applied.size() == 2, "A single immutable fetch hydrates all current consumers")
	check(first.visible and second.visible, "Accepted construction is revealed after assembly")
	check(announcements.size() == 2, "Announce remote availability only after accepted assembly")
	drawing._finish_layout_request("construction:a", drawing._layout_epoch, {"layout": {"test_version": "a"}, "hash": "a"})
	check(drawing.applied[first.get_instance_id()].test_version == "b", "Late response cannot overwrite newer requested refit")
	check(announcements.size() == 2, "Late and duplicate deliveries do not reannounce vessels")

	# Reuse the network id while a request for its previous occupant completes.
	drawing._visible_entities["entity"] = state_for(first, "replacement-vessel", "construction:c")
	drawing._finish_layout_request("construction:b", drawing._layout_epoch, accepted_b)
	check(not drawing._visible_entities.entity.has("applied_layout_key"), "Old vessel response cannot hydrate a reused entity id")
	var before_epoch := drawing._layout_epoch
	drawing._reset_layout_requests(true)
	drawing._finish_layout_request("construction:c", before_epoch, {"layout": {"test_version": "c"}})
	check(drawing._layout_cache.is_empty(), "Previous server/session callbacks cannot repopulate a new cache")
	check(not drawing._visible_entities.entity.has("applied_layout_key"), "Previous session cannot mutate current scene")
	for index in range(drawing.MAX_CACHED_LAYOUTS + 7):
		drawing._finish_layout_request("construction:cache-%d" % index, drawing._layout_epoch, accepted_b)
	check(drawing._layout_cache.size() == drawing.MAX_CACHED_LAYOUTS, "Exploration keeps immutable blueprint cache bounded")
	drawing.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await verify_live_owner_refit(builds)
	if not failed: print("VESSEL BLUEPRINT REPLICATION PASS: catalog/version rejection, server-accepted ledger, stable UID, shared fetch, stale/refit/reused entity safety, session invalidation and bounded cache")
	get_tree().quit(1 if failed else 0)

func verify_live_owner_refit(builds: Dictionary) -> void:
	var construction: Dictionary = {}
	for candidate: Dictionary in builds.values():
		if candidate.get("cargo_slots", []).size() > 0 and candidate.layout.parts.size() < 150:
			construction = candidate
			break
	check(not construction.is_empty(), "Live refit fixture has real container storage")
	if construction.is_empty(): return
	var record := {"uid": "owner-live-test", "server_vessel_id": "owner-server-vessel",
		"name": "Before", "hull_id": construction.layout.hull, "construction_id": construction.id,
		"catalog_hash": construction.catalog_hash, "brick_layout": construction.layout.duplicate(true)}
	var boat := VesselSpawn.instantiate_from_record(record) as ImportedDraftVessel
	check(boat != null, "Owner refit test constructs the real imported vessel")
	if boat == null: return
	boat.freeze = true
	boat.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(boat)
	PlayerVessel.mark_player_ship(boat)
	boat.position = Vector3(7, 3, -10)
	var original_instance := boat.get_instance_id()
	var accepted := record.duplicate(true)
	accepted.name = "Accepted refit"
	accepted.construction_id = "new-accepted-version"
	accepted.layout_hash = "new-hash"
	accepted.brick_layout.parts[0].position[0] += 0.5
	check(VesselSync.apply_accepted_live_vessel(self, accepted), "Accepted empty owner ship refit applies")
	check(boat.get_instance_id() == original_instance and boat.position == Vector3(7, 3, -10), "Refit preserves owner vessel instance and world pose")
	check(boat.draft == accepted.brick_layout, "Owner geometry uses exactly the accepted layout")
	check(str(boat.get_meta("construction_id")) == "new-accepted-version" and str(boat.get_meta("layout_hash")) == "new-hash", "Owner live metadata updates together with geometry")
	check(is_equal_approx(boat.part_roots[0].position.x, float(accepted.brick_layout.parts[0].position[0])), "Changed physical part placement reaches the owner model")
	var other := accepted.duplicate(true)
	other.server_vessel_id = "someone-else"
	other.brick_layout.parts[0].position[0] += 1.0
	VesselSync.apply_accepted_live_vessel(self, other)
	check(boat.draft == accepted.brick_layout, "An accepted record for another vessel cannot refit the active ship")
	var pads := boat.get_cargo_pads()
	check(not pads.is_empty(), "Owner fixture still has usable installed storage")
	if not pads.is_empty():
		var unit := ContainerUnit.create("do-not-delete", "provisions", 7000.0, str(construction.cargo_slots[0].container_type))
		check(pads[0].add_container(unit) >= 0, "Loads real container before unsafe refit attempt")
		var unsafe := accepted.duplicate(true)
		unsafe.brick_layout.parts[0].position[0] += 0.5
		check(not VesselSync.live_refit_block_reason(self, unsafe).is_empty(), "Occupied storage blocks destructive refit before publication")
		check(VesselSync.live_refit_block_reason(self, accepted).is_empty(), "Unchanged accepted build remains safe with cargo onboard")
		check(pads[0].get_containers()[0].id == "do-not-delete", "Refit preflight leaves container identity and contents intact")
	PlayerVessel.unmark_player_ship(boat)
	boat.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func state_for(boat: BoatBody, vessel_id: String, key: String) -> Dictionary:
	return {"node": boat, "type": "ship_test", "server_vessel_id": vessel_id,
		"requested_layout_key": key, "requested_construction_id": key.trim_prefix("construction:")}
