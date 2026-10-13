class_name CargoManifestReplication
extends Node3D

## Reliable cargo identity/location snapshots. The current captain simulates the
## crane; observers only animate the accepted state, never run another cargo job.
## This presentation stream does not authorize payments or generate inventory.
var gateway: Node
var view: Node
var drawing: Node
var _elapsed := 0.0
var _pending := ""
var _sent: Dictionary = {}
var _acknowledged: Dictionary = {}
var _manifests: Dictionary = {}
var _nodes: Dictionary = {}
var _interests: Dictionary = {}
var _own_id := ""
var _session := ""
var _crane_targets: Dictionary = {}
var last_error := ""
var port_lookup: Callable = HarbourRegistry.controller
var _pending_since := 0
var _pending_revision := 0

func setup(world_gateway: Node, local_view: Node, remote_drawing: Node = null) -> void:
	gateway = world_gateway
	view = local_view
	drawing = remote_drawing
	gateway.projection_changed.connect(_on_projection)
	gateway.command_completed.connect(_on_result)
	gateway.session_closed.connect(clear)

func clear() -> void:
	for scope in _interests: gateway.release_interest(scope, self)
	_interests.clear()
	for node in _nodes.values():
		if is_instance_valid(node): node.queue_free()
	_nodes.clear()
	_manifests.clear()
	_crane_targets.clear()
	_pending = ""
	_sent.clear()
	_acknowledged.clear()
	_own_id = ""

func _process(delta: float) -> void:
	if gateway == null or not gateway.is_remote() or not gateway.is_ready(): return
	if drawing == null: drawing = NetworkManager.drawing_service
	if not _pending.is_empty() and Time.get_ticks_msec() - _pending_since > 10000:
		# Retry the SAME receipt after an unknown outcome; never double-apply.
		_pending_since = Time.get_ticks_msec()
		gateway.send_command("cargo.manifest.publish", _sent, _pending, _pending_revision)
	_animate_cranes(delta)
	_elapsed += delta
	if _elapsed < .15: return
	_elapsed = 0.0
	var current_session: String = gateway.session_token()
	if _session != current_session:
		clear()
		_session = current_session
	var ship := view.get_active_ship() as BoatBody
	var wanted := {}
	if is_instance_valid(ship):
		_own_id = str(ship.get_meta("server_vessel_id", ""))
		if not _own_id.is_empty(): wanted["vessel:" + _own_id] = true
	if is_instance_valid(drawing):
		for state: Dictionary in drawing.get_visible_entities().values():
			var id := str(state.get("server_vessel_id", ""))
			if not id.is_empty(): wanted["vessel:" + id] = true
	for scope in wanted:
		if not _interests.has(scope):
			_interests[scope] = true
			gateway.retain_interest(scope, self)
			gateway.query_projections("cargo_manifest", str(scope).trim_prefix("vessel:"))
	for scope in _interests.keys():
		if not wanted.has(scope):
			gateway.release_interest(scope, self)
			_interests.erase(scope)
	# Rebuild from accessible projections so released scopes cannot leave ghosts.
	_manifests.clear()
	# Cached projections also cover ports/ships that finish assembling after data.
	for kind in ["cargo_manifest", "port_cargo_manifest"]:
		for projection: Dictionary in gateway.projections(kind):
			_on_projection(kind, str(projection.get("id", "")), projection)
	_reconcile()
	if is_instance_valid(ship) and not _own_id.is_empty() and _pending.is_empty():
		var snapshot := collect_manifest(ship, FreightService.active_contracts(), _manifests.get(_own_id, {}))
		if snapshot == _acknowledged: return
		_sent = snapshot
		_pending = gateway.next_request_id("cargo-manifest")
		var revision := int(gateway.projection("cargo_manifest", _own_id).get("revision", 0))
		_pending_revision = revision
		_pending_since = Time.get_ticks_msec()
		gateway.send_command("cargo.manifest.publish", snapshot, _pending, revision)

func _on_result(request_id: String, result: Dictionary) -> void:
	if request_id != _pending: return
	if str(result.get("error_code", result.get("code", ""))) == "transport_failed": return
	_pending = ""
	if result.get("ok", false):
		_acknowledged = _sent.duplicate(true)
		last_error = ""
	else:
		last_error = str(result.get("error", result))
		gateway.query_projections("cargo_manifest", _own_id)
		_elapsed = -1.0 # Back off on failures; do not hammer the authority.

func _on_projection(kind: String, _id: String, projection: Dictionary) -> void:
	if kind not in ["cargo_manifest", "port_cargo_manifest"]: return
	var state: Dictionary = projection.get("state", {})
	var id := str(state.get("vessel_id", ""))
	if id.is_empty(): return
	var previous: Dictionary = _manifests.get(id, {})
	if state.get("retired", false):
		if previous.get("port_id", "") == state.get("port_id", "") and int(previous.get("sequence", 0)) <= int(state.get("sequence", 0)):
			_manifests.erase(id)
		return
	if int(state.get("sequence", 0)) >= int(previous.get("sequence", 0)):
		_clear_removed_staging(state)
		_manifests[id] = state.duplicate(true)

static func vector(value: Vector3) -> Array:
	return [snappedf(value.x, .001), snappedf(value.y, .001), snappedf(value.z, .001)]

static func decode(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func collect_manifest(ship: BoatBody, contracts: Array, previous: Dictionary = {}) -> Dictionary:
	var vid := str(ship.get_meta("server_vessel_id", ""))
	var owned_contracts := {}
	var uid := str(ship.get_meta("vessel_uid", ""))
	for contract: Dictionary in contracts:
		if str(contract.get("vessel_uid", "")) == uid:
			owned_contracts[str(contract.id)] = true
	var result := {"vessel_id":vid, "port_id":ship.get_harbour_port_id(),
		"berth_id":ship.get_moored_berth_id(), "items":[], "cranes":[]}
	# Cargo left ashore still belongs to its last berth after the vessel casts off.
	if str(result.port_id).is_empty():
		result.port_id = str(previous.get("port_id", ""))
		result.berth_id = str(previous.get("berth_id", ""))
	var harbour := HarbourRegistry.controller(str(result.port_id))
	var hooks := {}
	if harbour != null:
		for equipment in harbour.all_equipment():
			if equipment is not ProvisionCraneEquipmentJob: continue
			var job := equipment as ProvisionCraneEquipmentJob
			if str(job.replication_context.get("vessel_id", "")) != vid: continue
			var crane := job._crane
			if not is_instance_valid(crane): continue
			if not job.is_job_active() and not is_instance_valid(crane.get_attached_container()): continue
			result.cranes.append({"equipment_id":job.equipment_id(), "operation_id":str(job.replication_context.get("operation_id", "")),
				"slew":snappedf(crane.slew_degrees,.01), "trolley":snappedf(crane.trolley_z_m,.01), "hoist":snappedf(crane.hoist_length_m,.01)})
			if is_instance_valid(crane._attached_container): hooks[crane._attached_container.get_instance_id()] = job
	for item in ship.get_tree().get_nodes_in_group(ContainerNode.GROUP):
		var node := item as ContainerNode
		if node == null or node.unit == null or node.get_meta("cargo_replica", false): continue
		var aboard := ship.is_ancestor_of(node)
		if not aboard and not owned_contracts.has(node.unit.freight_contract_id): continue
		var pad := CargoSlotPadComponent.find_pad_for_node(node)
		var hook: ProvisionCraneEquipmentJob = hooks.get(node.get_instance_id())
		var location := "vessel" if aboard else ("hook" if hook != null else "quay")
		var pose := ship.global_transform.affine_inverse() * node.global_transform if aboard else node.global_transform
		if hook != null: pose = hook._crane._hook.global_transform.affine_inverse() * node.global_transform
		var slot := str(pad.get_meta("authority_slot_id", "")) if pad != null else ""
		result.items.append({"id":node.unit.id,"unit":node.unit.to_dict(),"location":location,
			"slot_id":slot,"equipment_id":hook.equipment_id() if hook != null else "",
			"position":vector(pose.origin),"rotation":vector(pose.basis.get_euler())})
	if ship.get_harbour_port_id().is_empty() and result.items.all(func(item: Dictionary): return item.location == "vessel"):
		result.port_id = ""
		result.berth_id = ""
		result.cranes = []
	result.items.sort_custom(func(a: Dictionary,b: Dictionary):return str(a.id)<str(b.id))
	result.cranes.sort_custom(func(a: Dictionary,b: Dictionary):return str(a.equipment_id)<str(b.equipment_id))
	return result

func _ship(id: String) -> BoatBody:
	if is_instance_valid(drawing): return drawing.find_remote_ship_by_vessel_id(id)
	return null

func _reconcile() -> void:
	var wanted := {}
	_crane_targets.clear()
	for vid in _manifests:
		var manifest: Dictionary = _manifests[vid]
		var ship := _ship(vid)
		var port: HarbourController = port_lookup.call(str(manifest.get("port_id", "")))
		for pose: Dictionary in manifest.get("cranes", []):
			if port == null: continue
			var job := port.get_equipment(str(pose.equipment_id)) as ProvisionCraneEquipmentJob
			if job == null or not is_instance_valid(job._crane): continue
			var crane_key := str(manifest.get("port_id", "")) + "/" + str(pose.equipment_id)
			var stamp := int(manifest.get("updated_at_ms", 0))
			if int(_crane_targets.get(crane_key, {}).get("stamp", -1)) <= stamp:
				_crane_targets[crane_key] = {"crane":job._crane,"pose":pose,"stamp":stamp,"job":job,"owner":vid}
		if vid == _own_id: continue
		if ship != null: ship.set_meta("cargo_manifest", manifest.duplicate(true))
		for item: Dictionary in manifest.get("items", []):
			var location := str(item.location)
			var parent: Node3D = self
			if location == "vessel":
				if ship == null: continue
				parent = ship
			else:
				if port == null: continue
				if location == "hook":
					var job := port.get_equipment(str(item.equipment_id)) as ProvisionCraneEquipmentJob
					if job == null or not is_instance_valid(job._crane) or not is_instance_valid(job._crane._hook): continue
					parent = job._crane._hook
			var key := str(vid) + "/" + str(item.id)
			wanted[key] = true
			var existing: Variant = _nodes.get(key)
			var node: ContainerNode = existing if is_instance_valid(existing) else null
			if not is_instance_valid(node):
				node = ContainerNode.new()
				node.set_meta("cargo_replica", true)
				parent.add_child(node)
				node.remove_from_group(ContainerNode.GROUP)
				_nodes[key] = node
			if node.get_meta("replicated_unit", {}) != item.unit:
				node.setup(ContainerUnit.from_dict(item.unit), true)
				node.set_meta("replicated_unit", item.unit.duplicate(true))
			if node.get_parent() != parent: node.reparent(parent, false)
			var old_location := str(node.get_meta("cargo_location", ""))
			if old_location != location:
				if location == "hook": node.notify_grabbed()
				elif old_location == "hook": node.notify_released()
				node.set_meta("cargo_location", location)
			node.position = decode(item.position)
			node.rotation = decode(item.rotation)
	for key in _nodes.keys():
		if wanted.has(key): continue
		if is_instance_valid(_nodes[key]): _nodes[key].queue_free()
		_nodes.erase(key)

func _animate_cranes(delta: float) -> void:
	var alpha := 1.0-exp(-18.0*delta)
	for target: Dictionary in _crane_targets.values():
		if str(target.get("owner", "")) == _own_id: continue
		var job: Variant = target.get("job")
		if is_instance_valid(job): job.replication_context.clear()
		var crane: Variant = target.crane
		if not is_instance_valid(crane): continue
		var pose: Dictionary = target.pose
		crane.slew_degrees = rad_to_deg(lerp_angle(deg_to_rad(crane.slew_degrees),deg_to_rad(float(pose.slew)),alpha))
		crane.trolley_z_m = lerpf(crane.trolley_z_m,float(pose.trolley),alpha)
		crane.hoist_length_m = lerpf(crane.hoist_length_m,float(pose.hoist),alpha)

# Cleanup also reaches the owning client's native cargo, not just observer replicas.
func _clear_removed_staging(state: Dictionary) -> void:
	var removed: Array = state.get("cleared_item_ids", [])
	if removed.is_empty() or not is_inside_tree(): return
	var port: HarbourController = port_lookup.call(str(state.get("port_id", "")))
	if port != null:
		for equipment in port.all_equipment():
			if equipment is not ProvisionCraneEquipmentJob: continue
			var job := equipment as ProvisionCraneEquipmentJob
			if not is_instance_valid(job._crane): continue
			var held := job._crane.get_attached_container()
			if is_instance_valid(held) and held.unit != null and removed.has(held.unit.id):
				job.stop_job()
				job._crane.release_container_to_world(held.global_position, self)
				job.replication_context.clear()
	for candidate in get_tree().get_nodes_in_group(ContainerNode.GROUP):
		var node := candidate as ContainerNode
		if node == null or node.unit == null or node.is_queued_for_deletion() or not removed.has(node.unit.id): continue
		# Never destroy cargo which has since legitimately reached a vessel.
		var parent := node.get_parent()
		var aboard := false
		while parent != null:
			if parent is BoatBody: aboard = true; break
			parent = parent.get_parent()
		if aboard: continue
		var pad := CargoSlotPadComponent.find_pad_for_node(node)
		if pad != null: pad.take_container_node(node)
		node.remove_from_group(ContainerNode.GROUP)
		node.queue_free()
