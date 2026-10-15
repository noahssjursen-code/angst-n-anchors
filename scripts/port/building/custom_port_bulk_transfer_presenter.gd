extends Node

## Visual playback of a committed bulk transfer. Uses the production grab rig,
## but never calls its inventory operator, BulkMaterialDrop, or FreightService.
signal transfer_started(summary: Dictionary)
signal transfer_finished(summary: Dictionary)
signal presentation_failed(reason: String)
signal phase_changed(label: String)

const TIMEOUT_S := 75.0
const BULK_STOCK = preload("res://scripts/port/building/custom_port_bulk_stock_layout.gd")
var presenter: CustomPortPresenter
var completed_grabs := 0
var total_grabs := 0
var presented_kg := 0.0
var _jobs: Array[Dictionary] = []
var _current: Dictionary = {}
var _phase := ""
var _timer := 0.0
var _visuals: Array[Node3D] = []
var _hidden: Array[Node3D] = []
var _grains: Array[Dictionary] = []

func capture(before: Dictionary, after: Dictionary, events: Array) -> Array[Dictionary]:
	var plans: Array[Dictionary] = []
	for event in events:
		if not event is Dictionary or str(event.get("kind","")) not in ["load_cargo","unload_cargo"]: continue
		if str(event.get("port_id",""))!=str(after.id) or int(event.get("revision",-1))!=int(after.revision): continue
		var issued: Dictionary=event.get("receipt",{}).get("result",{})
		var store_before:=_find(before.get("stores",[]),str(issued.get("store_id","")))
		var store_after:=_find(after.get("stores",[]),str(issued.get("store_id","")))
		var ship_before:=_find(before.get("vessels",[]),str(issued.get("vessel_id","")))
		var ship_after:=_find(after.get("vessels",[]),str(issued.get("vessel_id","")))
		if store_before.is_empty() or store_after.is_empty() or ship_before.is_empty() or ship_after.is_empty(): continue
		var lot_id:=str(issued.get("lot_id",""))
		var old_lot:=_find(store_before.get("lots",[]),lot_id)
		var new_lot:=_find(store_after.get("lots",[]),lot_id)
		var lot: Dictionary=old_lot if not old_lot.is_empty() else new_lot
		if CustomPortState._handling_mode(lot)!="bulk": continue
		var loading:=str(event.kind)=="load_cargo"
		var quantity:=float(issued.get("quantity",0))
		var store_delta:=float(new_lot.get("quantity",0))-float(old_lot.get("quantity",0))
		var ship_delta:=_lot_mass(ship_after,lot_id)-_lot_mass(ship_before,lot_id)
		var mass:=quantity*float(lot.get("unit_mass_kg",0))
		if mass<=0 or not is_equal_approx(absf(store_delta),quantity) or not is_equal_approx(ship_delta,mass if loading else -mass): continue
		var old_holds: Dictionary={}
		var ship: BoatBody=presenter.vessel_nodes.get(str(ship_before.id))
		if is_instance_valid(ship):
			for hold in ship.get_bulk_holds(): old_holds[hold.hold_id]=hold.state.filled_tonnes_t*1000.0
		plans.append({"crane_id":str(issued.get("crane_id","")),"store_id":str(store_before.id),"store_placement_id":str(store_before.placement_id),
			"vessel_id":str(ship_before.id),"lot_id":lot_id,"commodity_id":str(lot.commodity_id),"loading":loading,"mass_kg":mass,
			"old_store_kg":_commodity_mass(store_before,str(lot.commodity_id)),"new_store_kg":_commodity_mass(store_after,str(lot.commodity_id)),
			"store_capacity_kg":float(store_after.capacity_kg),"old_holds":old_holds})
	return plans

func play(plans: Array[Dictionary]) -> void:
	completed_grabs=0
	total_grabs=0
	presented_kg=0
	for plan in plans:
		var owner: Node3D=presenter.placement_nodes.get(str(plan.crane_id))
		var crane:=owner.find_child("Crane",true,false) as BulkCrane if is_instance_valid(owner) else null
		var store: Node3D=presenter.placement_nodes.get(str(plan.store_placement_id))
		var pad:=store.find_child("CargoPad",true,false) as Node3D if is_instance_valid(store) else null
		var ship: BoatBody=presenter.vessel_nodes.get(str(plan.vessel_id))
		if crane==null or pad==null or not pad.has_meta("bulk_pad_size_m") or not is_instance_valid(ship):
			presentation_failed.emit("Bulk cargo is recorded, but its assigned crane, stockpile or ship is unavailable.")
			continue
		if crane.simulate_bulk_material or crane.is_auto_active() or not crane.get_bucket_lot().is_empty():
			presentation_failed.emit("Bulk cargo is recorded; the assigned grab is occupied by another operation.")
			continue
		var changes: Array[Dictionary]=[]
		var found_mass:=0.0
		for hold in ship.get_bulk_holds():
			var old_mass:=float(plan.old_holds.get(hold.hold_id,0))
			var new_mass:=hold.state.filled_tonnes_t*1000.0
			var delta:=new_mass-old_mass
			if absf(delta)<.001 or (delta>0)!=bool(plan.loading): continue
			changes.append({"hold":hold,"old_kg":old_mass,"new_kg":new_mass,"mass_kg":absf(delta)})
			found_mass+=absf(delta)
		var store_record:=_find(presenter.record.get("stores",[]),str(plan.store_id))
		var layout:=presenter.bulk_stock_layout(store_record,pad.get_meta("bulk_pad_size_m"))
		if not layout.has(str(plan.commodity_id)):
			presentation_failed.emit("Bulk cargo is recorded, but its receiving bay is unavailable.")
			continue
		var pile_spec: Dictionary=layout[str(plan.commodity_id)]
		var pile_aim:=pad.to_global(pile_spec.position_m)+Vector3.UP*_pile_height(plan.old_store_kg if plan.loading else plan.new_store_kg,plan.store_capacity_kg)
		var reachable:=is_equal_approx(found_mass,float(plan.mass_kg)) and crane.can_reach_point(pile_aim)
		for change in changes:
			reachable=reachable and change.hold.cargo_accessible and crane.can_reach_point(change.hold.get_crane_aim_toward(crane.get_boom_hinge_global()))
		if not reachable:
			presentation_failed.emit("Bulk cargo is recorded, but the assigned grab cannot reach its exact stockpile and hold.")
			continue
		var pile:=_visual(plan.commodity_id,pile_spec.size_m,hash(str(plan.commodity_id)),pad)
		pile.position=pile_spec.position_m
		# Several consignments of this commodity share one visible heap. The
		# transferred lot may have disappeared from the committed shore record.
		for lot_id in pile_spec.lot_ids:_hide(presenter.cargo_nodes.get(str(lot_id)))
		_hide(presenter.cargo_nodes.get(str(plan.lot_id)))
		var shown_store:=float(plan.old_store_kg)
		_pile_fill(pile,shown_store,plan.store_capacity_kg)
		for change in changes:
			var hold: BulkHoldComponent=change.hold
			_hide(hold._fill_layer)
			var fill:=_visual(plan.commodity_id,hold._inner_fill_size(),hash(hold.hold_id),hold)
			fill.position.y=-hold.hold_depth_m+.025 if hold is ImportedBulkHold else 0.0
			_hold_fill(fill,change.old_kg,hold.state.capacity_tonnes_t*1000.0)
			var remaining:=float(change.mass_kg)
			var capacity:=crane.bucket_capacity_tonnes_t()*1000.0
			var shown_hold:=float(change.old_kg)
			while remaining>.001:
				var amount:=minf(capacity,remaining)
				_jobs.append({"crane":crane,"hold":hold,"pad":pad,"pile":pile,"fill":fill,"commodity_id":plan.commodity_id,
					"loading":plan.loading,"mass_kg":amount,"store_before_kg":shown_store,"hold_before_kg":shown_hold,
					"store_capacity_kg":plan.store_capacity_kg,"hold_capacity_kg":hold.state.capacity_tonnes_t*1000.0,
					"vessel_id":plan.vessel_id,"was_processing":crane.is_processing()})
				shown_store+=-amount if plan.loading else amount
				shown_hold+=amount if plan.loading else -amount
				remaining-=amount
	total_grabs=_jobs.size()
	if total_grabs>0:
		transfer_started.emit({"bulk":true,"grabs":total_grabs})
		_start_next()

func is_busy() -> bool:
	return not _current.is_empty() or not _jobs.is_empty()

func status() -> String:
	return "%s · grab %d / %d"%[_label(),completed_grabs+1,total_grabs] if is_busy() else "Crane idle"

func reset() -> void:
	var cranes: Array=[]
	for job in [_current]+_jobs:
		var crane: Variant=job.get("crane")
		if is_instance_valid(crane) and not crane in cranes:
			crane.set_bucket_jaws_target(1)
			crane.set_process(bool(job.get("was_processing",false)))
			for sound in crane.find_children("*","AudioStreamPlayer3D",true,false): sound.stop()
			cranes.append(crane)
	for node in _hidden:
		if is_instance_valid(node): node.show()
	_hidden.clear()
	for node in _visuals:
		if is_instance_valid(node):
			if node.get_parent()!=null:node.get_parent().remove_child(node)
			node.queue_free()
	_visuals.clear()
	_grains.clear()
	_jobs.clear()
	_current.clear()
	_phase=""
	_timer=0

func _exit_tree() -> void:
	reset()

func tick(delta: float) -> void:
	if _current.is_empty(): return
	for key in ["crane","hold","pad","pile","fill"]:
		if not is_instance_valid(_current.get(key)):
			_fail("The vessel or bulk equipment changed during loading.");return
	var crane: BulkCrane=_current.crane
	var hold: BulkHoldComponent=_current.hold
	if not is_instance_valid(crane) or not is_instance_valid(hold) or not hold.is_inside_tree() or not is_instance_valid(_current.pad):
		_fail("The vessel or bulk equipment changed during loading.");return
	_timer+=delta
	if _timer>TIMEOUT_S:
		_fail("The bulk grab could not align; committed stock is shown at its destination.");return
	var store_kg:=float(_current.store_before_kg)
	var pile_aim: Vector3=_current.pile.global_position+Vector3.UP*_pile_height(store_kg,_current.store_capacity_kg)
	var hold_aim:=hold.get_crane_aim_toward(crane.get_boom_hinge_global())
	var source: Vector3=pile_aim if _current.loading else hold_aim
	var destination: Vector3=hold_aim if _current.loading else pile_aim
	match _phase:
		"raise_empty","raise_load","clear_drop":
			crane.ik_mouth_to(delta,crane.get_bucket_mouth_global(),"raise")
			if _raised(crane):
				if _phase=="raise_empty":_set_phase("travel_pickup")
				elif _phase=="raise_load":_set_phase("travel_drop")
				else:
					completed_grabs+=1
					presented_kg+=float(_current.mass_kg)
					_start_next()
		"travel_pickup","travel_drop":
			var aim:=source if _phase=="travel_pickup" else destination
			crane.ik_mouth_to(delta,aim,"raise")
			if _over(crane,aim):_set_phase("lower_pickup" if _phase=="travel_pickup" else "lower_drop")
		"lower_pickup","lower_drop":
			var aim:=source if _phase=="lower_pickup" else destination
			crane.ik_mouth_to(delta,aim,"track")
			if crane.get_bucket_mouth_global().distance_to(aim)<.55:
				_set_phase("close_grab" if _phase=="lower_pickup" else "dump")
		"close_grab":
			crane.set_bucket_jaws_target(0)
			crane.step_jaws(delta)
			if crane.is_bucket_at_target(.04):
				_current.grab.show()
				if _current.loading:_pile_fill(_current.pile,store_kg-_current.mass_kg,_current.store_capacity_kg)
				else:_hold_fill(_current.fill,_current.hold_before_kg-_current.mass_kg,_current.hold_capacity_kg)
				_set_phase("raise_load")
		"dump":
			crane.set_bucket_jaws_target(1)
			crane.step_jaws(delta)
			if crane.bucket_open>=.45 and _grains.is_empty():_start_dump(crane,destination)
			_tick_grains(delta)
			if _timer>=1.5 and crane.is_bucket_at_target(.04):
				_pile_fill(_current.pile,store_kg+(-_current.mass_kg if _current.loading else _current.mass_kg),_current.store_capacity_kg)
				_hold_fill(_current.fill,_current.hold_before_kg+(_current.mass_kg if _current.loading else -_current.mass_kg),_current.hold_capacity_kg)
				_clear_grains()
				_set_phase("clear_drop")
	if not _current.is_empty() and is_instance_valid(_current.grab):
		_current.grab.global_position=crane.get_bucket_mouth_global()+Vector3.UP*.22

func _start_next() -> void:
	if not _current.is_empty():
		var prior: Variant=_current.crane
		if is_instance_valid(prior):
			prior.set_process(bool(_current.was_processing))
			if not _current.was_processing:
				for sound in prior.find_children("*","AudioStreamPlayer3D",true,false): sound.stop()
		var grab: Variant=_current.grab
		if is_instance_valid(grab):grab.hide()
	_current.clear()
	if _jobs.is_empty():
		var summary: Dictionary={"bulk":true,"grabs":completed_grabs,"mass_kg":presented_kg}
		reset()
		phase_changed.emit("Crane idle")
		transfer_finished.emit(summary)
		return
	_current=_jobs.pop_front()
	if not is_instance_valid(_current.get("crane")):
		_fail("The vessel or bulk equipment changed during loading.");return
	var crane: BulkCrane=_current.crane
	crane.set_process(true)
	crane.set_bucket_jaws_target(1)
	crane.bucket_open=1
	var grab:=_visual(_current.commodity_id,Vector3(2.4,.8,1.9),completed_grabs,presenter)
	grab.scale=Vector3.ONE*pow(float(_current.mass_kg)/(crane.bucket_capacity_tonnes_t()*1000.0),1.0/3.0)
	grab.hide()
	_current.grab=grab
	_set_phase("raise_empty")

func _start_dump(crane: BulkCrane,destination: Vector3) -> void:
	_current.grab.hide()
	for index in 8:
		var grain:=_visual(_current.commodity_id,Vector3(1,.6,1),index,presenter)
		grain.scale=Vector3(.22,.3,.22)
		grain.global_position=crane.get_bucket_mouth_global()+Vector3((index%3-1)*.3,.15+floorf(float(index)/3.0)*.22,(index%2-.5)*.4)
		_grains.append({"node":grain,"velocity":Vector3((index%3-1)*.16,-.8,0),"floor":destination.y-1.4})

func _tick_grains(delta: float) -> void:
	for grain in _grains:
		grain.velocity+=Vector3.DOWN*9.8*delta
		grain.node.global_position+=grain.velocity*delta
		if grain.node.global_position.y<=float(grain.floor): grain.node.hide()

func _clear_grains() -> void:
	for grain in _grains:
		if is_instance_valid(grain.node):grain.node.hide()
	_grains.clear()

func _visual(commodity: String,size: Vector3,seed: int,parent: Node3D) -> Node3D:
	var visual:=OreMoundBuilder.build_mound(commodity,size,seed)
	visual.set_meta("custom_port_bulk_visual",true)
	parent.add_child(visual)
	_visuals.append(visual)
	return visual

func _hide(node: Node3D) -> void:
	if is_instance_valid(node) and node.visible:
		node.hide()
		_hidden.append(node)

static func _pile_fill(node: Node3D,mass: float,capacity: float) -> void:
	var ratio:=clampf(mass/maxf(capacity,1),0,1)
	node.visible=ratio>.000001
	node.scale=BULK_STOCK.fill_scale(maxf(mass,.000001),capacity)

static func _hold_fill(node: Node3D,mass: float,capacity: float) -> void:
	var ratio:=clampf(mass/maxf(capacity,1),0,1)
	node.visible=ratio>.000001
	node.scale=Vector3(1,maxf(ratio,.000001),1)

static func _pile_height(mass: float,capacity: float) -> float:
	return .1+3.5*pow(clampf(mass/maxf(capacity,1),0,1),2.0/3.0)

static func _raised(crane: BulkCrane) -> bool:
	return crane.hoist_length_m<=crane.hoist_min_m+1.35

static func _over(crane: BulkCrane,at: Vector3) -> bool:
	var delta:=crane.get_bucket_mouth_global()-at
	return Vector2(delta.x,delta.z).length()<.45

static func _find(rows: Array,id: String) -> Dictionary:
	for row in rows:
		if str(row.get("id",""))==id:return row
	return {}

static func _lot_mass(owner: Dictionary,id: String) -> float:
	var lot:=_find(owner.get("lots",[]),id)
	return float(lot.get("quantity",0))*float(lot.get("unit_mass_kg",0))

static func _commodity_mass(owner: Dictionary,commodity: String) -> float:
	var mass:=0.0
	for lot in owner.get("lots",[]):
		if str(lot.commodity_id)==commodity and CustomPortState._handling_mode(lot)=="bulk":
			mass+=float(lot.quantity)*float(lot.unit_mass_kg)
	return mass

func _set_phase(value: String) -> void:
	_phase=value
	_timer=0
	phase_changed.emit(_label())

func _label() -> String:
	return {"raise_empty":"Raising grab","travel_pickup":"Moving to stock","lower_pickup":"Lowering grab","close_grab":"Taking a grab",
		"raise_load":"Lifting bulk","travel_drop":"Moving bulk","lower_drop":"Lowering bulk","dump":"Emptying grab","clear_drop":"Clearing hold"}.get(_phase,"Crane idle")

func _fail(reason: String) -> void:
	reset()
	presentation_failed.emit(reason)
