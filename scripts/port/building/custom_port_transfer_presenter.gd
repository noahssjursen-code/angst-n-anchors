class_name CustomPortTransferPresenter
extends Node

## Animates already committed container, bulk and catch transfers. The snapshot remains
## the cargo authority: visual playback never modifies a pad or manifest.
## Call present() instead of presenter.load_record() for subscribed snapshots.
signal transfer_started(summary: Dictionary)
signal transfer_finished(summary: Dictionary)
signal presentation_failed(reason: String)
signal phase_changed(label: String)

const NEAR_M := .16
const OVER_M := .22
const PHASE_TIMEOUT_S := 75.0
const BULK_PRESENTER = preload("res://scripts/port/building/custom_port_bulk_transfer_presenter.gd")
const CATCH_PRESENTER = preload("res://scripts/port/building/custom_port_catch_transfer_presenter.gd")
var playback_speed := 1.0
var presenter: CustomPortPresenter
var completed_units := 0
var total_units := 0
var _jobs: Array[Dictionary] = []
var _current: Dictionary = {}
var _phase := ""
var _timer := 0.0
var _serial := 0
var bulk: Node
var catch_transfer: Node
var _continuity_roots: Array[Dictionary] = []
var _continuity_anchors: Array[Dictionary] = []
var _handling_bounds := AABB()
var _has_handling_bounds := false

func bind(value: CustomPortPresenter) -> void:
	reset()
	presenter=value
	if not is_instance_valid(bulk):
		bulk=BULK_PRESENTER.new()
		add_child(bulk)
		bulk.transfer_started.connect(func(summary: Dictionary)->void: transfer_started.emit(summary))
		bulk.transfer_finished.connect(func(summary: Dictionary)->void: transfer_finished.emit(summary))
		bulk.phase_changed.connect(func(label: String)->void: phase_changed.emit(label))
		bulk.presentation_failed.connect(func(reason: String)->void: presentation_failed.emit(reason))
	bulk.presenter=presenter
	if not is_instance_valid(catch_transfer):
		catch_transfer=CATCH_PRESENTER.new()
		add_child(catch_transfer)
		catch_transfer.transfer_started.connect(func(summary: Dictionary)->void: transfer_started.emit(summary))
		catch_transfer.transfer_finished.connect(func(summary: Dictionary)->void: transfer_finished.emit(summary))
		catch_transfer.phase_changed.connect(func(label: String)->void: phase_changed.emit(label))
		catch_transfer.presentation_failed.connect(func(reason: String)->void: presentation_failed.emit(reason))
	catch_transfer.presenter=presenter

func present(snapshot: Dictionary, berths: Array = [], events: Array = []) -> void:
	if not is_instance_valid(presenter):
		presentation_failed.emit("The port projection is unavailable.")
		return
	# UI refreshes and duplicate event deliveries must not restart a lift.
	if snapshot.get("id","")==presenter.record.get("id","") and int(snapshot.get("revision",-1))==int(presenter.record.get("revision",-2)):
		var recorded:=presenter.record.duplicate(true)
		recorded.erase("_presented_berths")
		if snapshot==recorded:return
	if _can_preserve_playback(snapshot,berths,events):
		# Loading only the unrelated decoration delta leaves the same stock,
		# vessel and rig nodes in place. Do not restart a hose or reveal a box
		# which is still suspended merely because someone opens their office.
		presenter.load_record(snapshot,berths)
		return
	var plan: Array[Dictionary] = []
	var bulk_plan: Array[Dictionary] = []
	var catch_plan: Array[Dictionary] = []
	if _is_transfer_commit(snapshot,events):
		plan=_capture_moves(presenter.record,snapshot,events)
		bulk_plan=bulk.capture(presenter.record,snapshot,events)
		catch_plan=catch_transfer.capture(presenter.record,snapshot,events)
	# Unknown edits, cancel, undock or replacement snapshots interrupt safely.
	# Revealing the committed destinations before rebuilding also handles a
	# mid-lift save/load without keeping an unregistered box under the hook.
	reset()
	presenter.load_record(snapshot,berths)
	bulk.play(bulk_plan)
	catch_transfer.play(catch_plan)
	for move in plan:
		var crane:=_crane_by_id(str(move.crane_id))
		var destination:=_destination_node(move)
		if crane==null or destination==null:
			presentation_failed.emit("Cargo is recorded, but its crane or destination is not visible.")
			continue
		if not crane.can_reach_point(move.source_transform.origin,.2) or not crane.can_reach_point(destination.global_position,.2):
			presentation_failed.emit("Cargo is recorded, but this crane cannot reach both loading points.")
			continue
		var proxy:=ContainerNode.new()
		proxy.name="PresentedTransfer_"+str(_serial)
		_serial+=1
		presenter.add_child(proxy)
		proxy.setup(destination.unit.duplicate(true) as ContainerUnit,true)
		proxy.remove_from_group(ContainerNode.GROUP)
		proxy.set_meta("custom_port_transfer_visual",true)
		proxy.global_transform=move.source_transform
		destination.hide()
		destination.set_collision_enabled(false)
		move.crane=crane
		move.destination=destination
		move.proxy=proxy
		_jobs.append(move)
	total_units=_jobs.size()
	completed_units=0
	if total_units>0:
		transfer_started.emit({"port_id":snapshot.id,"units":total_units,"revision":snapshot.revision})
		_start_next()
	if is_busy():_remember_continuity(plan+bulk_plan+catch_plan)

func _can_preserve_playback(snapshot: Dictionary,berths: Array,events: Array) -> bool:
	if not is_busy() or _continuity_roots.is_empty() or events.size()!=1:return false
	var before: Dictionary=presenter.record
	if snapshot.get("id","")!=before.get("id","") or int(snapshot.get("revision",-1))!=int(before.get("revision",-2))+1:return false
	if berths!=before.get("_presented_berths",[]):return false
	var event: Variant=events[0]
	if not event is Dictionary or event.get("kind","") not in ["edit_assets","rename_port"] or event.get("port_id","")!=snapshot.id or int(event.get("revision",-1))!=int(snapshot.revision):return false
	var renaming: bool=event.kind=="rename_port"
	var command_id:=str(event.get("command_id",""))
	if command_id.is_empty() or before.get("receipts",{}).has(command_id):return false
	if event.get("receipt",{})!=snapshot.get("receipts",{}).get(command_id,{}) or int(event.get("receipt",{}).get("applied_revision",-1))!=int(snapshot.revision):return false
	var changed_field: String="name" if renaming else "placements"
	if event.get("changes",{}).keys()!=[changed_field] or event.changes[changed_field]!=snapshot.get(changed_field):return false
	var receipts: Dictionary=before.get("receipts",{}).duplicate(true)
	receipts[command_id]=event.receipt
	if receipts!=snapshot.get("receipts",{}):return false
	var old_data:=before.duplicate(true)
	var new_data:=snapshot.duplicate(true)
	for key in ["revision","receipts","placements","_presented_berths"]:
		old_data.erase(key);new_data.erase(key)
	if renaming:old_data.erase("name");new_data.erase("name")
	# This also rejects changed stock, reservations, boats, water, origin, owner,
	# plot boundaries and future unknown document fields without guessing safety.
	if old_data!=new_data:return false
	var prior: Dictionary={}
	for row in before.get("placements",[]):prior[str(row.id)]=row
	if prior.size()!=snapshot.get("placements",[]).size():return false
	var changed:=false
	for row in snapshot.get("placements",[]):
		var id:=str(row.id)
		if not prior.has(id):return false
		var old: Dictionary=prior[id]
		if old==row:continue
		if renaming:return false
		changed=true
		var spec:=CustomPortCatalog.definition(str(row.asset_id))
		if str(spec.get("kind",""))!="decoration" or bool(spec.get("mooring",false)) or bool(spec.get("berth_edge",false)):return false
		for root in _continuity_roots:
			if root.collection=="placement_nodes" and root.id==id:return false
		var old_row:=old.duplicate(true)
		var new_row: Dictionary=row.duplicate(true)
		for key in ["door_open","wall_colour"]:
			old_row.get("attributes",{}).erase(key);new_row.get("attributes",{}).erase(key)
		if old_row!=new_row:return false
		if old.get("attributes",{}).get("door_open")!=row.get("attributes",{}).get("door_open"):
			if not spec.has("door") or not _door_clear_of_handling(id,spec):return false
	if not changed and not renaming:return false
	for root in _continuity_roots:
		var node: Variant=root.node
		if not is_instance_valid(node) or presenter.get(root.collection).get(root.id)!=node:return false
	for anchor in _continuity_anchors:
		var node: Variant=anchor.node
		if not is_instance_valid(node) or not node.is_inside_tree() or node.is_queued_for_deletion() or not presenter.is_ancestor_of(node):return false
		if not node.global_transform.is_equal_approx(anchor.transform):return false
	return true

func _remember_continuity(plans: Array) -> void:
	_continuity_roots.clear();_continuity_anchors.clear();_has_handling_bounds=false
	var seen: Dictionary={}
	for plan in plans:
		for pair in [["placement_nodes",str(plan.get("crane_id",plan.get("pump_id","")))],
				["placement_nodes",str(plan.get("store_placement_id",""))],["vessel_nodes",str(plan.get("vessel_id",""))]]:
			var key: String=pair[0]+":"+pair[1]
			if seen.has(key):continue
			seen[key]=true
			var node: Node3D=presenter.get(pair[0]).get(pair[1])
			if not is_instance_valid(node):continue
			_continuity_roots.append({"collection":pair[0],"id":pair[1],"node":node})
			_continuity_anchors.append({"node":node,"transform":node.global_transform})
			for child in node.find_children("*","Node3D",true,false):
				if child is ProvisionCrane or child is BulkCrane or child is FishLandingPump or child is ShoreRswTankBank or child is CargoSlotPadComponent or child is BulkHoldComponent or child is CatchHoldComponent:
					_continuity_anchors.append({"node":child,"transform":child.global_transform})
				if child is MeshInstance3D and child.mesh!=null:
					var bounds: AABB=child.global_transform*child.get_aabb()
					_handling_bounds=bounds if not _has_handling_bounds else _handling_bounds.merge(bounds)
					_has_handling_bounds=true
	for job in [_current]+_jobs:
		var destination: Node3D=job.get("destination")
		if is_instance_valid(destination):_continuity_anchors.append({"node":destination,"transform":destination.global_transform})

func _door_clear_of_handling(id: String,spec: Dictionary) -> bool:
	var node: Node3D=presenter.placement_nodes.get(id)
	if not is_instance_valid(node) or not _has_handling_bounds:return false
	var pivot:=node.find_child(str(spec.door.pivot_node),true,false) as Node3D
	if not is_instance_valid(pivot):return false
	var found:=false
	for collider in spec.get("colliders",[]):
		if str(collider.get("moving_node",""))!=str(spec.door.pivot_node):continue
		found=true
		var at:=CustomPortCatalog.vector3(collider.position_m)
		var half:=CustomPortCatalog.vector3(collider.size_m)*.5
		# A full horizontal rotation envelope covers both opening and closing,
		# including intermediate angles, without changing the actual door node.
		var radius:=Vector2(absf(at.x)+half.x,absf(at.z)+half.z).length()
		var sweep:=pivot.global_transform*AABB(Vector3(-radius,at.y-half.y,-radius),Vector3(radius*2,half.y*2,radius*2))
		if sweep.grow(.25).intersects(_handling_bounds):return false
	return found

func is_busy() -> bool:
	return not _current.is_empty() or not _jobs.is_empty() or (is_instance_valid(bulk) and bulk.is_busy()) or (is_instance_valid(catch_transfer) and catch_transfer.is_busy())

func status() -> String:
	if is_instance_valid(catch_transfer) and catch_transfer.is_busy(): return catch_transfer.status()
	if is_instance_valid(bulk) and bulk.is_busy(): return bulk.status()
	if not is_busy():return "Crane idle"
	return "%s · %d / %d" % [_phase_label(),completed_units+1,total_units]

func reset() -> void:
	var was_busy:=is_busy()
	if is_instance_valid(bulk): bulk.reset()
	if is_instance_valid(catch_transfer): catch_transfer.reset()
	_clear_job(_current)
	for job in _jobs:_clear_job(job)
	_jobs.clear()
	_current.clear()
	_phase=""
	_timer=0
	_continuity_roots.clear();_continuity_anchors.clear();_has_handling_bounds=false
	if was_busy:phase_changed.emit("Crane idle")

func _exit_tree() -> void:
	reset()

func _is_transfer_commit(snapshot: Dictionary,events: Array) -> bool:
	if presenter.record.is_empty() or snapshot.get("id","")!=presenter.record.get("id",""):return false
	# A snapshot gap is reconstructed directly; it is not a request to replay
	# hours of old crane movements when a client comes back into range.
	if int(snapshot.get("revision",-1))!=int(presenter.record.get("revision",-2))+1:return false
	for event in events:
		if not event is Dictionary:continue
		if str(event.get("kind","")) in ["load_cargo","unload_cargo"] and str(event.get("port_id",""))==str(snapshot.id) and int(event.get("revision",-1))==int(snapshot.revision):return true
	return false

func _capture_moves(before: Dictionary,after: Dictionary,events: Array) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for old_store in before.get("stores",[]):
		var new_store:=_find(after.get("stores",[]),str(old_store.id))
		if new_store.is_empty():continue
		var lot_ids: Dictionary={}
		for lot in old_store.get("lots",[]):lot_ids[str(lot.id)]=true
		for lot in new_store.get("lots",[]):lot_ids[str(lot.id)]=true
		for lot_id in lot_ids:
			var old_lot:=_find(old_store.get("lots",[]),str(lot_id))
			var new_lot:=_find(new_store.get("lots",[]),str(lot_id))
			var lot: Dictionary=old_lot if not old_lot.is_empty() else new_lot
			if not lot.get("attributes",{}).has("container_type"):continue
			var store_delta:=int(new_lot.get("quantity",0))-int(old_lot.get("quantity",0))
			if store_delta==0:continue
			for old_vessel in before.get("vessels",[]):
				var new_vessel:=_find(after.get("vessels",[]),str(old_vessel.id))
				if new_vessel.is_empty():continue
				var old_cargo:=_find(old_vessel.get("lots",[]),str(lot_id))
				var new_cargo:=_find(new_vessel.get("lots",[]),str(lot_id))
				var vessel_delta:=int(new_cargo.get("quantity",0))-int(old_cargo.get("quantity",0))
				if store_delta+vessel_delta!=0 or vessel_delta==0:continue
				var loading:=vessel_delta>0
				var selection:=_issued_crane(events,after,str(old_store.id),str(old_vessel.id),str(lot_id),loading,absi(vessel_delta))
				if selection.is_empty():
					presentation_failed.emit("Cargo is recorded, but the accepted transfer has no matching crane assignment.")
					continue
				var source_root: Node3D=presenter.placement_nodes.get(str(old_store.placement_id)) if loading else presenter.vessel_nodes.get(str(old_vessel.id))
				var source_start:=int(new_lot.get("quantity",0)) if loading else int(new_cargo.get("quantity",0))
				var target_start:=int(old_cargo.get("quantity",0)) if loading else int(old_lot.get("quantity",0))
				for index in absi(vessel_delta):
					var source_id:="%s-%d"%[lot_id,source_start+index] if loading else "%s-%s-%d"%[old_vessel.id,lot_id,source_start+index]
					var source:=_container(source_root,source_id)
					if source==null:
						presentation_failed.emit("Cargo is recorded, but its previous loading position is not visible.")
						continue
					result.append({"crane_id":selection,"store_id":str(old_store.id),"store_placement_id":str(old_store.placement_id),"vessel_id":str(old_vessel.id),
						"loading":loading,"source_transform":source.global_transform,"source_unit_id":source_id,
						"destination_unit_id":"%s-%s-%d"%[old_vessel.id,lot_id,target_start+index] if loading else "%s-%d"%[lot_id,target_start+index]})
	return result

func _destination_node(move: Dictionary) -> ContainerNode:
	var root: Node3D=presenter.vessel_nodes.get(str(move.vessel_id)) if move.loading else presenter.placement_nodes.get(str(move.store_placement_id))
	return _container(root,str(move.destination_unit_id))

static func _issued_crane(events: Array,snapshot: Dictionary,store_id: String,vessel_id: String,lot_id: String,loading: bool,quantity: int) -> String:
	# The authority selects a crane for this cargo type and the actual berth.
	# A store may live on another placement, including a yard without a crane.
	# Never substitute that placement's machine or guess a nearby alternative.
	for event in events:
		if not event is Dictionary or str(event.get("kind",""))!=("load_cargo" if loading else "unload_cargo"):continue
		if str(event.get("port_id",""))!=str(snapshot.id) or int(event.get("revision",-1))!=int(snapshot.revision):continue
		var result: Dictionary=event.get("receipt",{}).get("result",{})
		if str(result.get("store_id",""))!=store_id or str(result.get("vessel_id",""))!=vessel_id or str(result.get("lot_id",""))!=lot_id:continue
		if float(result.get("quantity",0))!=quantity:continue
		return str(result.get("crane_id",""))
	return ""

func _crane_by_id(crane_id: String) -> ProvisionCrane:
	var root: Node3D=presenter.placement_nodes.get(crane_id)
	if not is_instance_valid(root):return null
	return root.find_child("Crane",true,false) as ProvisionCrane

static func _container(root: Node3D,id: String) -> ContainerNode:
	if not is_instance_valid(root):return null
	for node in root.find_children("*","Node3D",true,false):
		if node is ContainerNode and node.unit!=null and node.unit.id==id:return node
	return null

static func _find(rows: Array,id: String) -> Dictionary:
	for row in rows:
		if str(row.get("id",""))==id:return row
	return {}

func _start_next() -> void:
	if _jobs.is_empty():
		_phase=""
		phase_changed.emit("Crane idle")
		transfer_finished.emit({"units":completed_units,"total_units":total_units})
		return
	_current=_jobs.pop_front()
	if not is_instance_valid(_current.get("crane")) or not is_instance_valid(_current.proxy) or not is_instance_valid(_current.destination):
		_fail("The port changed while loading.")
		return
	var crane: ProvisionCrane=_current.crane
	if crane.get_attached_container()!=null:
		_fail("The crane hook is already occupied.")
		return
	_current.was_processing=crane.is_processing()
	crane.set_process(true)
	_set_phase("clear_hook")

func _process(delta: float) -> void:
	if is_instance_valid(bulk): bulk.tick(delta*maxf(.01,playback_speed))
	if is_instance_valid(catch_transfer): catch_transfer.tick(delta*maxf(.01,playback_speed))
	if _current.is_empty():return
	if not is_instance_valid(_current.get("crane")) or not is_instance_valid(_current.get("proxy")) or not is_instance_valid(_current.get("destination")):
		_fail("The vessel or loading equipment is no longer available.")
		return
	var crane: ProvisionCrane=_current.crane
	var proxy: ContainerNode=_current.proxy
	var destination: ContainerNode=_current.destination
	var dt:=delta*maxf(.01,playback_speed)
	_timer+=dt
	if _timer>PHASE_TIMEOUT_S:
		_fail("Crane alignment timed out. Cargo remains in its committed location.")
		return
	var source_frame: Transform3D=_current.source_transform
	var source_aim:=source_frame.origin+source_frame.basis.y.normalized()*proxy.lift_height_m()
	var destination_aim:=destination.global_position+destination.global_basis.y.normalized()*proxy.lift_height_m()
	match _phase:
		"clear_hook":
			crane.ik_hook_to(dt,crane.get_hook_global(),"raise")
			if _raised(crane):_set_phase("travel_pickup")
		"travel_pickup":
			crane.ik_hook_to(dt,source_aim,"raise")
			if crane.is_hook_over(source_aim,OVER_M):_set_phase("lower_pickup")
		"lower_pickup":
			crane.ik_hook_to(dt,source_aim,"track")
			if crane.is_hook_near(source_aim,NEAR_M):_set_phase("secure")
		"secure":
			if _timer>=.3:
				if not crane.attach_container(proxy):_fail("The presentation could not secure its container.");return
				_set_phase("raise_load")
		"raise_load":
			crane.ik_hook_to(dt,crane.get_hook_global(),"raise")
			crane.align_attached_container(source_frame.basis.orthonormalized(),dt)
			if _raised(crane):_set_phase("travel_drop")
		"travel_drop":
			crane.ik_hook_to(dt,destination_aim,"raise")
			crane.align_attached_container(destination.global_basis.orthonormalized(),dt)
			if crane.is_hook_over(destination_aim,OVER_M):_set_phase("lower_drop")
		"lower_drop":
			crane.ik_hook_to(dt,destination_aim,"track")
			crane.align_attached_container(destination.global_basis.orthonormalized(),dt)
			if crane.is_hook_near(destination_aim,NEAR_M):_set_phase("release")
		"release":
			if _timer>=.3:
				crane.release_container_to_world(destination.global_position,presenter)
				proxy.hide()
				destination.show()
				destination.set_collision_enabled(true)
				WorldSound.play("res://resources/audio/world/cargo/container_land_1.wav",destination.global_position,-4)
				_set_phase("raise_empty")
		"raise_empty":
			crane.ik_hook_to(dt,destination_aim,"raise")
			if _raised(crane):
				completed_units+=1
				_clear_job(_current)
				_current.clear()
				_start_next()

static func _raised(crane: ProvisionCrane) -> bool:
	return crane.hoist_length_m<=crane.hoist_min_m+2.05

func _set_phase(value: String) -> void:
	_phase=value
	_timer=0
	phase_changed.emit(_phase_label())

func _phase_label() -> String:
	return {"clear_hook":"Raising hook","travel_pickup":"Moving to cargo","lower_pickup":"Lowering hook",
		"secure":"Securing cargo","raise_load":"Lifting cargo","travel_drop":"Moving cargo",
		"lower_drop":"Lowering cargo","release":"Landing cargo","raise_empty":"Clearing hook"}.get(_phase,"Crane idle")

func _clear_job(job: Dictionary) -> void:
	if job.is_empty():return
	var crane: Variant=job.get("crane")
	var proxy: Variant=job.get("proxy")
	var destination: Variant=job.get("destination")
	if is_instance_valid(crane) and is_instance_valid(proxy) and crane.get_attached_container()==proxy:
		crane.release_container_to_world(proxy.global_position,presenter if is_instance_valid(presenter) else self)
	if is_instance_valid(proxy):
		if proxy.get_parent()!=null:proxy.get_parent().remove_child(proxy)
		proxy.queue_free()
	if is_instance_valid(destination):
		destination.show()
		destination.set_collision_enabled(true)
	if is_instance_valid(crane) and job.has("was_processing"):
		crane.set_process(bool(job.was_processing))
		if not job.was_processing:
			for sound in crane.find_children("*","AudioStreamPlayer3D",true,false):sound.stop()

func _fail(reason: String) -> void:
	reset()
	presentation_failed.emit(reason)
