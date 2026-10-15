class_name CustomPortStreamer
extends Node3D

## Read-only client projection of already-authorized port snapshots. Distance
## only controls scene residency; it never removes stock or an authority record.
## The normal vessel replication system remains responsible for every ship.
signal port_loaded(port_id: String, presenter: CustomPortPresenter)
signal port_unloaded(port_id: String)
signal operator_selected(port_id: String, placement_id: String)

const EARTHWORKS = preload("res://scripts/port/state/custom_port_earthworks.gd")
const WORLD_POLICY = preload("res://scripts/port/building/custom_port_world_policy.gd")
const PLAYER_DECK_MARGIN_M := 4.0
@export var load_radius_m := 1400.0
## Local file previews are not live service providers. A future authorized
## projection source may deliberately use the normal presentation contract.
var passive_services := false
var live_services := false
var retained_ids:Dictionary={}
var loader: ProximityLoader
var _world: Dictionary = {}
var _catalog: Dictionary = {}
var _records: Dictionary = {}
var _entries: Dictionary = {}
var _removed_revisions: Dictionary = {}
var _terrain: WorldTerrainStreamer
var _forest: WorldForestStreamer
var _configured := false


func _ready() -> void:
	loader = ProximityLoader.new()
	loader.name = "CustomPortProximity"
	loader.telemetry_key = &"world.custom_ports"
	loader.retain_loaded = _retain_for_walking_player
	loader.entry_loaded.connect(_on_loaded)
	loader.entry_unloaded.connect(_on_unloaded)
	add_child(loader)
	loader.set_process(_configured)


func configure(expected_world: Dictionary, catalog: Dictionary = {}) -> Dictionary:
	var cleared := clear()
	if not cleared.ok: return cleared
	_world = expected_world.duplicate(true)
	_catalog = CustomPortCatalog.definitions() if catalog.is_empty() else catalog.duplicate(true)
	_configured = not _world.is_empty()
	if is_instance_valid(loader): loader.set_process(_configured)
	return {"ok":true,"code":"configured"}


func bind_environment(terrain: WorldTerrainStreamer, forest: WorldForestStreamer = null) -> void:
	if is_instance_valid(_forest) and _forest != forest:
		for id in _records: _forest.set_custom_port_exclusions(_forest_key(id),[])
	if is_instance_valid(_terrain) and _terrain != terrain: _terrain.set_custom_port_earthworks([])
	_terrain = terrain
	_forest = forest
	_publish_environment()
	if is_instance_valid(_forest):
		for id in _records: _publish_forest(id)


func upsert_record(snapshot: Dictionary) -> Dictionary:
	if not _configured or not is_instance_valid(loader): return {"ok":false,"code":"not_configured"}
	# Delayed or repeated traffic must not revalidate all construction polygons
	# and derive every berth on the main thread. Only rejection may bypass JSON
	# validation; a successful duplicate must still be a complete safe document.
	var source_fingerprint := ""
	var raw_id: Variant = snapshot.get("id")
	var raw_revision: Variant = snapshot.get("revision",0)
	if raw_id is String and CustomPortState._integer(raw_revision) and int(raw_revision)>=0:
		if _removed_revisions.has(raw_id) and int(raw_revision)<=int(_removed_revisions[raw_id]):
			return {"ok":false,"code":"stale_snapshot"}
		var known: Dictionary = _records.get(raw_id,{})
		if not known.is_empty():
			if int(raw_revision)<int(known.snapshot.revision): return {"ok":false,"code":"stale_snapshot"}
			if int(raw_revision)==int(known.snapshot.revision):
				if not CustomPortState._json_safe(snapshot): return {"ok":false,"code":"invalid_snapshot","errors":["Port data must contain only finite JSON values."]}
				source_fingerprint=JSON.stringify(snapshot,"",true,true).sha256_text()
				if source_fingerprint==str(known.get("source_fingerprint","")):
					return {"ok":true,"code":"unchanged"}
				# Wire numbers and omitted optional collections normalize exactly as
				# the authority does, without accepting changed or invalid content.
				var canonical: Dictionary = CustomPortState._canonical(snapshot)
				for key in CustomPortState.MUTABLE_FIELDS:
					if not canonical.has(key): canonical[key]=[]
				if not canonical.has("receipts"): canonical.receipts={}
				if not canonical.has("revision"): canonical.revision=0
				if JSON.stringify(canonical,"",true,true).sha256_text()==str(known.fingerprint):
					return {"ok":true,"code":"unchanged"}
	var state := CustomPortState.from_dict(snapshot,_world,_catalog)
	if not state.validation_errors.is_empty():
		return {"ok":false,"code":"invalid_snapshot","errors":state.validation_errors.duplicate()}
	var data := state.to_dict()
	var plane: Dictionary=WORLD_POLICY.validate_deck_plane(data)
	if not plane.ok:return plane
	var vessels:=CustomPortVesselProjection.validate_snapshot(data)
	if not vessels.ok:return vessels
	var id := str(data.id)
	var revision := state.revision()
	if _removed_revisions.has(id) and revision <= int(_removed_revisions[id]):
		return {"ok":false,"code":"stale_snapshot"}
	var fingerprint := JSON.stringify(data,"",true,true).sha256_text()
	var previous: Dictionary = _records.get(id,{})
	if not previous.is_empty():
		if revision < int(previous.snapshot.revision): return {"ok":false,"code":"stale_snapshot"}
		if revision == int(previous.snapshot.revision):
			return {"ok":fingerprint==str(previous.fingerprint),"code":"unchanged" if fingerprint==str(previous.fingerprint) else "revision_conflict"}
	var projection: Dictionary = EARTHWORKS.project(data,_catalog,state.construction_edges())
	var geometry_changed: bool = previous.is_empty() or str(previous.earthworks.geometry_signature)!=str(projection.geometry_signature)
	if source_fingerprint.is_empty(): source_fingerprint=JSON.stringify(snapshot,"",true,true).sha256_text()
	_records[id] = {"snapshot":data,"berths":state.derived_berths(),"earthworks":projection,"fingerprint":fingerprint,"source_fingerprint":source_fingerprint}
	_removed_revisions.erase(id)
	var interest := _interest(data,projection)
	if _entries.has(id):
		loader.update_entry(_entries[id],interest.position,interest.radius)
		var presenter := get_presenter(id)
		if presenter != null: _present(id,presenter)
	else:
		_entries[id] = loader.register(interest.position,_create_presenter.bind(id),interest.radius,id)
	if geometry_changed:
		_publish_environment()
		_publish_forest(id)
	return {"ok":true,"code":"updated","revision":revision}


## An explicit authority deletion has a revision. Merely leaving render range
## never calls this, and an older delayed packet cannot recreate deleted cargo.
func remove_record(id: String, revision: int) -> Dictionary:
	var last := int(_records.get(id,{}).get("snapshot",{}).get("revision",-1))
	last = maxi(last,int(_removed_revisions.get(id,-1)))
	if revision < last or revision < 0: return {"ok":false,"code":"stale_snapshot"}
	if _records.has(id) and revision == last: return {"ok":false,"code":"revision_conflict"}
	if _entries.has(id):
		if not loader.unregister(_entries[id]): return {"ok":false,"code":"occupied_presentation"}
		_entries.erase(id)
	_records.erase(id)
	_removed_revisions[id] = revision
	if is_instance_valid(_forest): _forest.set_custom_port_exclusions(_forest_key(id),[])
	_publish_environment()
	return {"ok":true,"code":"removed"}


func record(id: String) -> Dictionary:
	return _records.get(id,{}).get("snapshot",{}).duplicate(true)


func get_presenter(id: String) -> CustomPortPresenter:
	var instance: Variant = _entries.get(id,{}).get("instance")
	return instance as CustomPortPresenter if is_instance_valid(instance) else null


func load_now(id:String)->CustomPortPresenter:
	if _entries.has(id):loader._load(_entries[id])
	return get_presenter(id)

func loaded_port_ids() -> Array[String]:
	var result: Array[String] = []
	for id in _entries:
		if get_presenter(id) != null: result.append(id)
	result.sort()
	return result


## A protected child prevents the entire reset. Keep its record, environment
## and loader handle together so a later retry can finish safely.
func clear() -> Dictionary:
	for id in _entries:
		if is_instance_valid(loader) and not loader.can_unregister(_entries[id]):
			return {"ok":false,"code":"occupied_presentation"}
	for id in _entries:
		if is_instance_valid(loader): loader.unregister(_entries[id])
	for id in _records:
		if is_instance_valid(_forest): _forest.set_custom_port_exclusions(_forest_key(id),[])
	_entries.clear()
	_records.clear()
	_removed_revisions.clear()
	_publish_environment()
	return {"ok":true,"code":"cleared"}


func _create_presenter(_id: String) -> Node3D:
	var presenter := CustomPortPresenter.new()
	presenter.simulate_vessels = false
	presenter.passive_services = passive_services
	presenter.name = "CustomPort_"+_id.validate_node_name()
	presenter.operator_selected.connect(func(placement_id: String)->void:operator_selected.emit(_id,placement_id))
	return presenter


func _on_loaded(entry: Dictionary, instance: Node3D) -> void:
	var id := str(entry.debug_name)
	if not _records.has(id): return
	var presenter := instance as CustomPortPresenter
	_present(id,presenter)
	port_loaded.emit(id,presenter)


func _on_unloaded(entry: Dictionary) -> void:
	port_unloaded.emit(str(entry.debug_name))


func _present(id: String, presenter: CustomPortPresenter) -> void:
	var cached: Dictionary = _records[id]
	presenter.load_record(cached.snapshot,cached.berths)
	# Records are world anchored even if a review scene transforms this parent.
	presenter.global_position = CustomPortCatalog.vector3(cached.snapshot.origin_m)
	if live_services and presenter.get_node_or_null("Services")==null:
		var services:=PlayerPortPlot.new()
		services.name="Services"
		presenter.add_child(services)
		services.attach(presenter)


func _interest(snapshot: Dictionary, earthworks: Dictionary) -> Dictionary:
	var origin := CustomPortCatalog.vector3(snapshot.origin_m)
	var bounds: Rect2 = earthworks.bounds
	var center := bounds.get_center() if bounds.has_area() else Vector2(origin.x,origin.z)
	return {"position":Vector3(center.x,origin.y,center.y),"radius":maxf(1,load_radius_m)+bounds.size.length()*.5}


func _retain_for_walking_player(entry: Dictionary) -> bool:
	if retained_ids.has(str(entry.get("debug_name",""))):return true
	var cached: Dictionary = _records.get(str(entry.get("debug_name","")),{})
	if cached.is_empty(): return false
	var bounds: Rect2 = cached.earthworks.bounds
	if not bounds.has_area(): return false
	bounds=bounds.grow(PLAYER_DECK_MARGIN_M)
	# The free camera may fly away while the real character is still standing
	# on this floor. Keep only already-loaded ports; do not load distant ships.
	# Explicit authority deletion bypasses this camera-residency safety rule.
	for player in get_tree().get_nodes_in_group("player"):
		if player is Node3D and bounds.has_point(Vector2(player.global_position.x,player.global_position.z)):
			return true
	return false


func _publish_environment() -> void:
	if not is_instance_valid(_terrain): return
	var projections: Array = []
	for id in _records: projections.append(_records[id].earthworks)
	_terrain.set_custom_port_earthworks(projections)


func _publish_forest(id: String) -> void:
	if not is_instance_valid(_forest): return
	_forest.set_custom_port_exclusions(_forest_key(id),EARTHWORKS.forest_exclusions(_records[id].earthworks))


func _forest_key(id: String) -> String:
	return "custom-port:"+id


func _exit_tree() -> void:
	# Environment projections outlive distance residency, but not their owning
	# world consumer. No saved authority data is changed by this cleanup.
	for id in _records:
		if is_instance_valid(_forest): _forest.set_custom_port_exclusions(_forest_key(id),[])
	if is_instance_valid(_terrain): _terrain.set_custom_port_earthworks([])
