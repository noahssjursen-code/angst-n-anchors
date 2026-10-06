extends Node3D
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	for option in CompanyContracts.starter_options():
		var record := CompanyService.build_starter_vessel_record(option.id)
		check(not record.is_empty(), "Starter missing: " + option.id)
		if record.is_empty(): continue
		var layout := VesselSpawn.brick_layout_of(record)
		var data := PlayerData.new()
		data.upsert_owned_vessel(record)
		data.set_active_vessel(record)
		var restored := PlayerData.from_dict(JSON.parse_string(JSON.stringify(data.to_dict())))
		var saved: Dictionary = restored.active_vessel
		check(PlayerData.json_equivalent(VesselSpawn.brick_layout_of(saved), layout), "Full model fitout must survive captain JSON")
		check(PlayerData.json_equivalent(PlayerData.ledger_vessel_record(saved).brick_layout, layout), "Ledger must preserve models")
		check(not VesselSync._layout_patch_from_row({"brick_layout": {"hull_id":record.hull_id,"cells":{}}}, saved).has("brick_layout"), "Stale server response must not erase models")
		var bare := {"hull_id":record.hull_id,"brick_layout":ImportedVesselLayout.empty(record.hull_id)}
		check(VesselSync._layout_patch_from_row({"brick_layout":JSON.stringify(layout)}, bare).has("brick_layout"), "Server JSON can hydrate an empty model record")
		var boat := VesselSpawn.instantiate_from_record(saved) as ImportedDraftVessel
		check(boat != null, "Owned imported starter must spawn")
		if boat == null: continue
		boat.freeze = true
		add_child(boat)
		for component in ["StripBuoyancyComponent","HydrodynamicsComponent","PropulsionComponent","RudderComponent","BowThrusterComponent"]:
			boat.get_node(component).set_physics_process(false)
		for i in 4: await get_tree().physics_frame
		check(boat.part_roots.size() == layout.parts.size(), "No lost or duplicated model records")
		check(boat.get_meta("vessel_uid") == record.uid, "Ownership identity must survive spawn")
		check(is_equal_approx(boat.length_m, ImportedHullCatalog.ENTRIES[record.hull_id].loa_m), "Actual metric hull dimensions")
		check(boat.find_children("SeatInteraction", "Node", true, false).size() >= 2, "F helm and crew seats")
		var drive := boat.get_node("HullVisual/DriveGear") as ShipDriveVisual
		drive.local_boat = null
		drive.apply_snapshot({"throttle":.6,"steering":.5,"powered":true},1)
		var rotation := drive.propeller.rotation.z
		drive._process(.1)
		check(not is_equal_approx(rotation, drive.propeller.rotation.z), "Starter propeller responds")
		check(absf(drive.rudder.rotation.y) > .1, "Starter rudder responds")
		match option.id:
			"fishing":
				var fishing := boat.get_fishing_systems()[0]
				for i in 5: fishing._complete_one_haul_crate()
				check(is_equal_approx(fishing.catch_totals().mass_kg,1200), "Catch fills both 600 kg tanks including split haul")
				check(fishing.get_activity_status()=="HOLD FULL", "Full vessel catch status")
			"general_cargo":
				var pads := boat.get_cargo_pads()
				check(pads.size()==2, "Two working cargo beds")
				for pad in pads:
					check(pad.get_max_slots()==1, "One 20-foot container per bed")
					check(pad.global_position.y >= 3.6,"Cargo sits above the main deck")
					var unit := ContainerUnit.new()
					unit.id = "starter-test-" + str(pad.get_instance_id())
					check(pad.add_container(unit) >= 0, "Existing cargo inventory accepts freight")
					check(pad.iter_container_nodes().size()==1, "Cargo is visible through crane API")
					check(pad.add_container(ContainerUnit.new()) < 0, "Occupied bed rejects another unit")
			"bulk":
				check(boat.get_bulk_holds().size()==2, "Two bulk compartments")
				for hold in boat.get_bulk_holds(): check(hold.cargo_accessible, "Bulk holds must be open")
			"coaster":
				check(boat.get_bulk_holds().size()==1, "One continuous coaster hold")
				check(boat.get_bulk_holds()[0].cargo_accessible, "Coaster must load without removing covers")
		boat.queue_free()
		for i in 4: await get_tree().process_frame
		# Same path used for streamed remote replicas, with no owner controller.
		var replica := VesselSpawn.instantiate(record.hull_id) as ImportedDraftVessel
		replica.freeze = true
		replica.get_node("BoatController").free()
		add_child(replica)
		replica.apply_brick_layout(layout)
		replica.apply_brick_layout(layout)
		for i in 3: await get_tree().physics_frame
		check(replica.part_roots.size()==layout.parts.size(), "Remote hydration is complete and idempotent")
		var changed := layout.duplicate(true)
		changed.hull_colors.upper = [.4,.3,.2]
		changed.engine_preset = MarineEngineCatalog.options(record.hull_id).back().id
		replica.apply_brick_layout(changed)
		for i in 3: await get_tree().physics_frame
		check(replica.part_roots.size()==layout.parts.size(), "Replica refit does not duplicate parts")
		check(replica.physics_profile.shaft_power_kw == float(MarineEngineCatalog.resolve(record.hull_id,changed.engine_preset).power_kw),"Replica refit installs selected engine")
		replica.queue_free()
		for i in 4: await get_tree().process_frame
		var invalid := record.duplicate(true)
		invalid.brick_layout.parts[0].asset_id = "missing-model"
		check(VesselSpawn.resolve_deployable_record(invalid).is_empty(), "Unknown model is rejected")
		invalid = record.duplicate(true)
		invalid.brick_layout.hull = "hull_999"
		check(VesselSpawn.resolve_deployable_record(invalid).is_empty(), "Hull/layout mismatch rejected")
		print("STARTER VERIFIED ", option.id, " parts=", layout.parts.size())
	var cargo_record := CompanyService.build_starter_vessel_record("general_cargo")
	var unsupported: Dictionary = cargo_record.brick_layout.duplicate(true)
	unsupported.parts = unsupported.parts.filter(func(part: Dictionary) -> bool: return part.asset_id != "cargo_deck_5x8")
	var unsafe_boat := VesselSpawn.instantiate(cargo_record.hull_id,unsupported) as ImportedDraftVessel
	unsafe_boat.freeze = true;add_child(unsafe_boat)
	check(unsafe_boat.get_cargo_pads().is_empty(),"Container beds need the supporting cargo deck")
	unsafe_boat.queue_free()
	var sealed: Dictionary = CompanyService.build_starter_vessel_record("bulk").brick_layout.duplicate(true)
	sealed.parts = sealed.parts.filter(func(part: Dictionary) -> bool: return part.asset_id != "hold_coaming_5x8")
	sealed.parts.append({"asset_id":"cargo_deck_5x8","position":[0,3.6,0],"yaw_degrees":0})
	unsafe_boat = VesselSpawn.instantiate(cargo_record.hull_id,sealed) as ImportedDraftVessel
	unsafe_boat.freeze = true;add_child(unsafe_boat)
	check(unsafe_boat.get_bulk_holds().is_empty(),"Solid cargo deck blocks access to underlying bulk space")
	unsafe_boat.queue_free()
	for frame in 4: await get_tree().process_frame
	if not failed: print("IMPORTED STARTER FLEET PASS: grants, save/ledger, stale-server protection, spawning, equipment, remote hydration, invalid records")
	ModelCache.clear()
	get_tree().quit(1 if failed else 0)
