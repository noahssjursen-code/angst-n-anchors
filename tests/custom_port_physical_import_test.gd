extends Node

## Real-model boundary regression. Generic CustomPortState deliberately remains
## useful for abstract data simulations; rendered imports require actual fitout.
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := {"seed":73119,"generation_version":1,"checksum":"physical-import"}
	var plots: Array = [{"id":"plot","rect_m":[-124,-108,200,200],"owner_company_id":CustomPortExample.OWNER}]
	var snapshot := CustomPortExample.build(Vector3(0,.5,0), plots, world)
	snapshot.erase("_site_yaw")
	snapshot.water_regions = [{"rect_m":[-128,-104,232,168],"depth_m":12}]
	_check(CustomPortVesselProjection.validate_snapshot(snapshot).ok, "Existing Nordvik fleet has canonical installed equipment")
	var bulk := CustomPortVesselProjection.from_prebuilt("coastal_coaster", "working-bulk", "new-owner", "Renamed vessel")
	bulk.capacity_kg = 100000 # Valid scenario ceiling below the actual 120t hold.
	bulk.lots = [_lot("ore", "iron_ore", 75000)]
	_check(CustomPortVesselProjection.validate_vessel(bulk).ok, "Owner, name, identity and lower overall mass ceiling may vary")
	var trader := CustomPortVesselProjection.from_prebuilt("28_10_m", "working-cargo", "new-owner", "", 48000)
	trader.lots = [_lot("boxes", "containers", 2, 12000, {"container_type":"20ft"})]
	var fishing := CustomPortVesselProjection.from_prebuilt("fishing_hook_line", "working-fishing", "new-owner")
	fishing.lots = [_lot("catch", "fresh_groundfish", 200)]
	var legacy:=fishing.duplicate(true)
	var installed_id: String=legacy.cargo_holds[0].id
	legacy.cargo_holds[0].id=installed_id.replace("tank_","catch:")
	var preserved:=legacy.duplicate(true)
	_check(CustomPortVesselProjection.validate_vessel(legacy).ok,"Earlier catch:N documents retain their exact valid installed fitout")
	_check(legacy==preserved,"Legacy identity validation does not rewrite saved data")
	var old_plan:=CustomPortVesselProjection.catch_hold_plan(legacy,legacy.lots)
	_check(old_plan.ok and old_plan.allocations[0].hold_id==installed_id,"Legacy saved tank resolves to the real runtime hose connection")
	legacy.cargo_holds[0].capacity_kg=900
	_reject(legacy,"Legacy aliases cannot enlarge installed tank capacity")
	var operating := {"vessels":[bulk,trader,fishing],"stores":[],"reservations":[]}
	_check(CustomPortVesselProjection.validate_snapshot(operating).ok, "Operating fleet carries visible bulk, two ISO boxes and catch within real fitout")
	_check(CustomPortVesselProjection.validate_snapshot(JSON.parse_string(JSON.stringify(operating,"",true,true))).ok, "Full precision JSON roundtrip preserves physical validity")
	var bad := bulk.duplicate(true)
	bad.capacity_kg = 200000
	bad.handling_capacity_kg.bulk = 200000
	bad.cargo_holds[0].capacity_kg = 200000
	bad.lots[0].quantity = 150000
	_reject(bad, "Forged 200t declaration cannot hide 30t beyond the actual 120t hold")
	bad = bulk.duplicate(true)
	bad.erase("cargo_holds")
	_reject(bad, "Known prebuilt cannot opt into abstract fallback by deleting installed holds")
	bad = bulk.duplicate(true)
	bad.cargo_holds = []
	_reject(bad, "Empty installed holds cannot replace the real construction")
	bad = bulk.duplicate(true)
	bad.cargo_holds[0].position_m[0] = 2
	_reject(bad, "Moved compartment evidence must match the authored fitout")
	bad = bulk.duplicate(true)
	bad.length_m = 12
	_reject(bad, "Physical berth dimensions cannot be forged independently of the hull")
	bad = trader.duplicate(true)
	bad.container_beds.append(bad.container_beds[0].duplicate(true))
	bad.capacity_units = 3
	bad.lots[0].quantity = 3
	_reject(bad, "Claiming a third securing bed does not enlarge the real ship")
	bad = trader.duplicate(true)
	bad.erase("container_beds")
	_reject(bad, "Known cargo ship must include installed bed evidence")
	bad = trader.duplicate(true)
	bad.lots[0].attributes.container_type = "40ft"
	bad.lots[0].quantity = 1
	_reject(bad, "One 40ft box cannot occupy two independent 20ft beds")
	bad = trader.duplicate(true)
	bad.lots[0].quantity = 3
	_reject(bad, "Valid installed evidence still rejects physically excessive payload")
	bad = bulk.duplicate(true)
	bad.lots[0].quantity = 110000
	_reject(bad, "Lower scenario mass ceiling remains binding")
	bad = fishing.duplicate(true)
	bad.lots[0].quantity = 601
	_reject(bad, "Catch above the actual 600kg tank limit rejects")
	bad = fishing.duplicate(true)
	bad.lots = [_lot("box", "containers", 1, 10, {"container_type":"20ft"})]
	_reject(bad, "Fishing tank cannot be used as an ISO cargo bed")
	bad = bulk.duplicate(true)
	bad.prebuilt_id = "unknown_custom_model"
	_reject(bad, "Unknown prebuilt cannot silently fall back to a different model")
	bad.prebuilt_id = "../coastal_coaster"
	_reject(bad, "Prebuilt ids cannot escape the canonical catalog")
	bad = bulk.duplicate(true)
	bad.erase("prebuilt_id")
	bad.erase("cargo_holds")
	bad.capacity_kg = 200000
	_check(CustomPortVesselProjection.validate_vessel(bad).ok, "Abstract simulation records remain independent of rendered models")
	var small := CustomPortVesselProjection.from_prebuilt("bulk_small", "small", "new-owner")
	small.lots = [_lot("coal", "coal", 1000), _lot("iron", "iron_ore", 2000)]
	_check(CustomPortVesselProjection.validate_vessel(small).ok, "Two separate commodities fit the actual two-hold ship")
	small.lots.append(_lot("grain", "grain", 1000))
	_reject(small, "Three incompatible shipments cannot share two installed compartments")
	var reserved := {"vessels":[bulk],"stores":[{"id":"yard","lots":[_lot("ore", "iron_ore", 100000)]}],
		"reservations":[{"id":"r","store_id":"yard","vessel_id":bulk.id,"lot_id":"ore","quantity":20000}]}
	var original := reserved.duplicate(true)
	_check(CustomPortVesselProjection.validate_snapshot(reserved).ok, "Carried 75t plus reserved 20t fits the lower 100t scenario limit")
	_check(reserved == original, "Physical validation never changes source stock, manifest or reservation")
	reserved.reservations[0].quantity = 30000
	_check(not CustomPortVesselProjection.validate_snapshot(reserved).ok, "Combined carried and reserved mass cannot exceed the scenario ceiling")
	reserved.reservations[0].lot_id = "missing"
	_check(not CustomPortVesselProjection.validate_snapshot(reserved).ok, "Unresolved reservation source cannot be treated as empty cargo")
	reserved = {"vessels":[trader],"stores":[{"id":"yard","lots":[trader.lots[0].duplicate(true)]}],
		"reservations":[{"id":"r","store_id":"yard","vessel_id":trader.id,"lot_id":"boxes","quantity":1}]}
	_check(not CustomPortVesselProjection.validate_snapshot(reserved).ok, "Reservations cannot allocate a third box to two physical beds")
	bad = bulk.duplicate(true)
	bad.lots = [_lot("dust", "iron_ore", 0.0001)]
	_reject(bad, "Sub-component bulk epsilon cannot accept a lot that vanishes on reconstruction")
	bad = fishing.duplicate(true)
	bad.lots[0].quantity = 0.05
	_reject(bad, "Sub-component catch epsilon cannot accept fish mass that vanishes on reconstruction")
	bad = fishing.duplicate(true)
	bad.lots[0].attributes.container_type = ""
	_reject(bad, "Empty container tag cannot change catch into an unrenderable box")
	bad = fishing.duplicate(true)
	bad.lots[0].attributes.quality = [1,2]
	_reject(bad, "Malformed catch attributes reject before the physical data constructor runs")
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--legacy-port-document="):continue
		var path:=arg.trim_prefix("--legacy-port-document=")
		var before:=FileAccess.get_sha256(path)
		var loaded:=CustomPortRepository.load_state(path,{},CustomPortCatalog.definitions())
		_check(loaded.ok,"Earlier complete harbour file still passes repository checks")
		if loaded.ok:_check(CustomPortVesselProjection.validate_snapshot(loaded.snapshot).ok,"Earlier complete harbour still passes physical reconstruction boundary")
		_check(FileAccess.get_sha256(path)==before,"Read-only compatibility check preserves source file bytes")
	for failure in failures: push_error(failure)
	print("CUSTOM PORT PHYSICAL IMPORT ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	get_tree().quit(0 if failures.is_empty() else 1)

func _lot(id: String, commodity: String, quantity: float, unit_mass := 1.0, attributes: Dictionary = {}) -> Dictionary:
	return {"id":id,"commodity_id":commodity,"quantity":quantity,"unit_mass_kg":unit_mass,"attributes":attributes}

func _reject(vessel: Dictionary, message: String) -> void:
	var result := CustomPortVesselProjection.validate_vessel(vessel)
	_check(not result.ok and result.code == "invalid_vessel_projection" and not result.errors.is_empty(), message)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
