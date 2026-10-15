extends Node
## Read-only playback of accepted catch movements. No fishing sale, local hold
## withdrawal, shore inventory mutation or network command is performed here.
signal transfer_started(summary: Dictionary)
signal transfer_finished(summary: Dictionary)
signal presentation_failed(reason: String)
signal phase_changed(label: String)

const LANDING = preload("res://scripts/port/building/custom_port_fish_landing.gd")

var presenter: CustomPortPresenter
var _jobs: Array[Dictionary] = []
var _current: Dictionary = {}
var _banks: Array[ShoreRswTankBank] = []
var _last_phase := ""
var total_mass_kg := 0.0
var completed_mass_kg := 0.0

func capture(before: Dictionary, after: Dictionary, events: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if before.get("id","") != after.get("id","") or int(after.get("revision",-1)) != int(before.get("revision",-2)) + 1: return result
	var seen: Dictionary = {}
	for event in events:
		if not event is Dictionary or str(event.get("kind","")) not in ["load_cargo","unload_cargo"]: continue
		if event.get("port_id","") != after.id or int(event.get("revision",-1)) != int(after.revision): continue
		var command_id := str(event.get("command_id",""))
		if command_id.is_empty() or seen.has(command_id): continue
		if event.get("receipt",{}) != after.get("receipts",{}).get(command_id,{}) or int(event.get("receipt",{}).get("applied_revision",-1)) != int(after.revision): continue
		seen[command_id] = true
		var issued: Dictionary = event.receipt.get("result",{})
		var old_store := _find(before.get("stores",[]),str(issued.get("store_id","")))
		var new_store := _find(after.get("stores",[]),str(issued.get("store_id","")))
		var old_ship := _find(before.get("vessels",[]),str(issued.get("vessel_id","")))
		var new_ship := _find(after.get("vessels",[]),str(issued.get("vessel_id","")))
		if old_store.is_empty() or new_store.is_empty() or old_ship.is_empty() or new_ship.is_empty(): continue
		var lot_id := str(issued.get("lot_id",""))
		var loading := str(event.kind) == "load_cargo"
		var lot := _find(old_store.lots if loading else old_ship.lots,lot_id)
		if lot.is_empty() or CustomPortState._handling_mode(lot) != "catch": continue
		var quantity := float(issued.get("quantity",0))
		var mass := quantity * float(lot.unit_mass_kg)
		var ship_delta := _lot_mass(new_ship,lot_id) - _lot_mass(old_ship,lot_id)
		var store_delta := _lot_mass(new_store,lot_id) - _lot_mass(old_store,lot_id)
		if mass <= 0 or absf(ship_delta - (mass if loading else -mass)) > .000001 or absf(store_delta + ship_delta) > .000001: continue
		var vessel: Dictionary = new_ship if loading else old_ship
		var catch_lots: Array = []
		for candidate in vessel.lots:
			if CustomPortState._handling_mode(candidate)=="catch": catch_lots.append(candidate)
		var packed := CustomPortVesselProjection.catch_hold_plan(vessel,catch_lots)
		if not packed.ok: continue
		# The ordered allocation stream is measured before CatchHoldState merges
		# compatible lots. It keeps exact input identity across multiple tanks.
		var offset := _lot_mass(old_ship,lot_id) if loading else _lot_mass(new_ship,lot_id)
		var allocations := _allocation_slice(packed.get("allocations",[]),lot_id,offset,mass)
		var assigned := 0.0
		for allocation in allocations: assigned += float(allocation.mass_kg)
		if absf(assigned - mass) > .000001: continue
		result.append({"pump_id":str(issued.get("crane_id","")),"store_id":str(old_store.id),
			"store_placement_id":str(new_store.placement_id),"vessel_id":str(vessel.id),"loading":loading,
			"mass_kg":mass,"lot_id":lot_id,"old_store_kg":_mass(old_store),"allocations":allocations})
	return result

func play(plans: Array[Dictionary]) -> void:
	total_mass_kg = 0
	completed_mass_kg = 0
	for plan in plans:
		var source: Node3D = presenter.placement_nodes.get(str(plan.pump_id))
		var storage: Node3D = presenter.placement_nodes.get(str(plan.store_placement_id))
		var ship: BoatBody = presenter.vessel_nodes.get(str(plan.vessel_id))
		var pump := source.find_child("FishLandingPump",true,false) as FishLandingPump if is_instance_valid(source) else null
		var bank := storage.find_child("ShoreRswTankBank",true,false) as ShoreRswTankBank if is_instance_valid(storage) else null
		if pump == null or bank == null or not is_instance_valid(ship):
			presentation_failed.emit("Catch is recorded, but its assigned pump, shore tank or vessel is unavailable.")
			continue
		if source != storage:
			presentation_failed.emit("Catch is recorded; this fixed-pipe plant is not connected to the selected shore bank.")
			continue
		var holds: Dictionary = {}
		for hold in ship.get_catch_holds(): holds[hold.hold_id] = hold
		var ready := true
		for allocation in plan.allocations:
			var hold: CatchHoldComponent = holds.get(str(allocation.hold_id))
			ready = ready and is_instance_valid(hold) and pump.can_project_to(hold,LANDING.HOSE_REACH_M)
		if not ready:
			presentation_failed.emit("Catch is recorded, but its exact installed tank is outside the hose's reach.")
			continue
		if bank not in _banks: _banks.append(bank)
		var shown_mass := float(plan.old_store_kg)
		bank.show_transfer_mass(shown_mass)
		for allocation in plan.allocations:
			_jobs.append({"pump":pump,"bank":bank,"ship":ship,"hold":holds[str(allocation.hold_id)],
				"loading":plan.loading,"mass_kg":float(allocation.mass_kg),"store_before_kg":shown_mass,"lot_id":plan.lot_id})
			shown_mass += float(allocation.mass_kg) * (-1 if plan.loading else 1)
			total_mass_kg += float(allocation.mass_kg)
	if not _jobs.is_empty():
		transfer_started.emit({"catch":true,"mass_kg":total_mass_kg})
		_start_next()

func is_busy() -> bool:
	return not _current.is_empty() or not _jobs.is_empty()

func status() -> String:
	if _current.is_empty(): return "Fish landing idle"
	var pump: FishLandingPump = _current.pump
	return "%s · %.1f / %.1f kg" % [pump.projection_label(),completed_mass_kg+pump.projection_progress()*float(_current.mass_kg),total_mass_kg]

func tick(delta: float) -> void:
	if _current.is_empty(): return
	if not is_instance_valid(_current.get("pump")) or not is_instance_valid(_current.get("bank")):
		_fail("The fish landing plant changed during playback.")
		return
	var pump: FishLandingPump = _current.pump
	var bank: ShoreRswTankBank = _current.bank
	if not is_instance_valid(pump) or not pump.is_inside_tree() or not is_instance_valid(bank) or not bank.is_inside_tree():
		_fail("The fish landing plant changed during playback.")
		return
	pump.step_projection(delta)
	var moved := pump.projection_progress()*float(_current.mass_kg)
	bank.show_transfer_mass(float(_current.store_before_kg)+moved*(-1 if _current.loading else 1))
	var phase := pump.projection_label()
	if phase != _last_phase:
		_last_phase = phase
		phase_changed.emit(phase)
	if not pump.is_projecting():
		if pump.state_label() != FishLandingPump.STATE_COMPLETE:
			_fail("The vessel or hose connection changed; committed catch remains in its saved location.")
			return
		completed_mass_kg += float(_current.mass_kg)
		_start_next()

func reset() -> void:
	for job in [_current] + _jobs:
		var pump: Variant = job.get("pump")
		if is_instance_valid(pump): pump.stop()
	for bank in _banks:
		if is_instance_valid(bank): bank.clear_transfer_projection()
	_banks.clear()
	_jobs.clear()
	_current.clear()
	_last_phase = ""

func _start_next() -> void:
	_current.clear()
	if _jobs.is_empty():
		var summary := {"catch":true,"mass_kg":completed_mass_kg}
		reset()
		phase_changed.emit("Fish landing idle")
		transfer_finished.emit(summary)
		return
	_current = _jobs.pop_front()
	if not is_instance_valid(_current.get("pump")):
		_fail("The fish landing plant changed during playback.")
		return
	var pump: FishLandingPump = _current.pump
	if not pump.start_projection(_current.ship,_current.hold,_current.mass_kg,_current.loading,LANDING.HOSE_REACH_M):
		_fail("The committed catch cannot be shown at the selected hose connection.")
		return
	_last_phase = ""

func _exit_tree() -> void:
	reset()

func _fail(message: String) -> void:
	reset()
	presentation_failed.emit(message)

static func _allocation_slice(allocations: Array, lot_id: String, offset: float, amount: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cursor := 0.0
	for row in allocations:
		if str(row.lot_id) != lot_id: continue
		var end := cursor + float(row.mass_kg)
		var overlap := minf(end,offset+amount)-maxf(cursor,offset)
		if overlap > .000001: result.append({"hold_id":str(row.hold_id),"mass_kg":overlap})
		cursor=end
	return result

static func _find(rows: Array,id: String) -> Dictionary:
	for row in rows:
		if str(row.get("id","")) == id: return row
	return {}

static func _lot_mass(owner: Dictionary,id: String) -> float:
	var lot := _find(owner.get("lots",[]),id)
	return float(lot.get("quantity",0))*float(lot.get("unit_mass_kg",0))

static func _mass(owner: Dictionary) -> float:
	var mass := 0.0
	for lot in owner.get("lots",[]): mass += float(lot.quantity)*float(lot.unit_mass_kg)
	return mass
