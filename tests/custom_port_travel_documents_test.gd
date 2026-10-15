extends Node

const REVIEW = preload("res://scripts/port/building/custom_port_streaming_showcase.gd")
class RecordDirectory extends Node3D:
	var records: Dictionary={}
	func record(id: String) -> Dictionary:return records.get(id,{}).duplicate(true)
var checks := 0
var failures: Array[String] = []
var directory := ""
var written: Array[String] = []
var world := {"seed":73119,"generation_version":1,"checksum":"travel-documents"}
var catalog: Dictionary

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(ShipyardPlaytestMode.active())
	catalog=CustomPortCatalog.definitions()
	directory="user://travel-documents-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var paths: Array[String] = []
	var hashes: Dictionary = {}
	for index in 3:
		var record:=_record("port-%d"%index,Vector3(100+index*350,.5,200))
		record.name="Owner's harbour %d"%index
		var path:=_save("port %d.json"%index,record)
		paths.append(path)
		hashes[path]=FileAccess.get_sha256(path)
	var loaded:=REVIEW.load_documents(paths,world,catalog)
	_check(loaded.ok and loaded.snapshots.size()==3,"Arbitrary batches preserve all three saved documents")
	if loaded.ok:
		for index in 3:
			_check(loaded.snapshots[index].id=="port-%d"%index and loaded.snapshots[index].name=="Owner's harbour %d"%index,"Document identity/name/order survive loading")
			_check(CustomPortCatalog.vector3(loaded.snapshots[index].origin_m).is_equal_approx(Vector3(100+index*350,.5,200)),"Saved world origin is retained, including neighbouring ports")
			_check(loaded.sources[index].source_sha256==hashes[paths[index]],"Original source checksum is retained for native verification")
	var one: Array[String]=[paths[0]]
	_check(REVIEW.load_documents(one,world,catalog).ok,"Single-port travel works without a second example")
	var empty: Array[String]=[]
	_check(REVIEW.load_documents(empty,world,catalog).code=="no_port_documents","Empty explicit import selection rejects")
	var duplicate: Array[String]=[paths[0],paths[0]]
	var rejected:=REVIEW.load_documents(duplicate,world,catalog)
	_check(not rejected.ok and rejected.code=="duplicate_port_id" and not rejected.has("snapshots"),"Duplicate identity rejects the whole batch before installation")
	var changed:=_record("port-0",Vector3(100,.5,200))
	changed.revision=4
	changed.name="Newer conflicting selection"
	duplicate=[paths[0],_save("newer.json",changed)]
	_check(REVIEW.load_documents(duplicate,world,catalog).code=="duplicate_port_id","Two revisions of one port require an explicit file choice")
	changed=_record("wrong-world",Vector3(0,.5,0))
	changed.world.seed=999
	_expect_rejection(paths[0],_save("wrong-world.json",changed),"wrong_world","World mismatch rejects without leaking a partial batch")
	changed=_record("wrong-plane",Vector3(0,5.5,0))
	changed.deck_height_above_sea_m=7
	_expect_rejection(paths[0],_save("wrong-plane.json",changed),"incompatible_deck_plane","Rendering policy rejects a second construction plane")
	changed=_record("forged-fitout",Vector3(0,.5,0))
	var bulk:=CustomPortVesselProjection.from_prebuilt("coastal_coaster","bulk","owner")
	bulk.erase("cargo_holds")
	changed.vessels=[bulk]
	_expect_rejection(paths[0],_save("forged-fitout.json",changed),"invalid_vessel_projection","Missing installed evidence rejects before any projection")
	changed=_record("overlapping",Vector3(110,.5,200))
	_expect_rejection(paths[0],_save("overlapping.json",changed),"invalid_collection","Distinct port ids cannot claim overlapping world plots")
	changed=_record("touching",Vector3(140,.5,200))
	var touching_paths: Array[String]=[paths[0],_save("touching.json",changed)]
	_check(REVIEW.load_documents(touching_paths,world,catalog).ok,"Exact neighbouring plot edges may touch without conflicting")
	changed=_record("unnamed",Vector3(800,.5,200))
	changed.erase("name")
	var unnamed_paths: Array[String]=[_save("unnamed.json",changed)]
	_check(REVIEW.load_documents(unnamed_paths,world,catalog).ok,"Optional display name does not invalidate an otherwise compatible document")
	var damaged:=directory.path_join("damaged.json")
	_write(damaged,"{unfinished")
	_write(damaged+".bak",FileAccess.get_file_as_string(paths[1]))
	var recover_paths: Array[String]=[damaged]
	var recovered:=REVIEW.load_documents(recover_paths,world,catalog)
	_check(recovered.ok and recovered.sources[0].loaded_path.ends_with(".bak") and not recovered.sources[0].warnings.is_empty(),"Explicit backup recovery is reported and tracks the actual loaded source")
	_check(FileAccess.get_file_as_string(damaged)=="{unfinished","Read-only recovery does not repair or overwrite the primary")
	for path in paths:
		_check(FileAccess.get_sha256(path)==hashes[path],"Import and rejection leave source bytes unchanged")
		_check(not FileAccess.file_exists(path+".bak"),"Read-only review does not create save backups")
	var review:=REVIEW.new()
	review.imported_mode=true
	review.snapshots.assign(loaded.snapshots)
	var before:=review.snapshots.duplicate(true)
	review.edit_nordvik()
	_check(review.snapshots==before and review.ports==null,"Imported mode disables the builtin pallet-edit action")
	# The chart reads retained authority data, not loaded models or original files.
	var directory_view:=RecordDirectory.new()
	for document in loaded.snapshots:directory_view.records[str(document.id)]=document.duplicate(true)
	directory_view.records["port-0"].revision=17
	review.ports=directory_view
	review.map=MapOverlay.new()
	review.map.preview_mode=true
	add_child(review.map)
	review.camera.set_flying(true)
	review.open_chart()
	_check(review.map.visible and not review.camera.flying,"Travel chart pauses free-camera movement")
	_check(review.map.data.ports.size()==3 and int(review.map.data.port_info("port-0").revision)==17,"Travel chart uses latest retained documents without resident port nodes")
	_check(not review.map.plot_panel.visible and not review.map.layers.is_visible("plots"),"Hidden plot layer does not leave a misleading plot panel")
	review.close_chart()
	_check(not review.map.visible and review.camera.flying,"Closing chart restores the prior fly mode")
	directory_view.records["port-0"].revision=18
	directory_view.records.erase("port-1")
	review.open_chart()
	_check(review.map.data.ports.size()==2 and int(review.map.data.port_info("port-0").revision)==18,"Reopening chart reflects edits and removals made while away")
	review.close_chart()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	review.map.free()
	directory_view.free()
	review.camera.free()
	review.free()
	for path in written:DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	for failure in failures:push_error(failure)
	print("CUSTOM PORT TRAVEL DOCUMENTS ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	get_tree().quit(0 if failures.is_empty() else 1)

func _record(id: String, origin: Vector3) -> Dictionary:
	return {"schema_version":1,"id":id,"name":id,"owner_company_id":"owner","world":world.duplicate(true),
		"origin_m":[origin.x,origin.y,origin.z],"deck_height_above_sea_m":2,"revision":0,
		"plots":[{"id":id+"-plot","rect_m":[-20,-20,40,40],"owner_company_id":"owner"}],
		"placements":[{"id":"slab","asset_id":"foundation","position_m":[0,0,0],"yaw_degrees":0,"attributes":{}}],
		"stores":[],"vessels":[],"reservations":[],"receipts":{},"water_regions":[]}

func _save(name: String, record: Dictionary) -> String:
	var state:=CustomPortState.from_dict(record,record.world,catalog)
	var path:=directory.path_join(name)
	var result:=CustomPortRepository.save(path,state)
	_check(result.ok,"Repository fixture saved: "+name+" "+str(result.get("errors",[])))
	written.append(path)
	return path

func _write(path: String, text: String) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(text)
	file.close()
	written.append(path)

func _expect_rejection(first: String, second: String, code: String, message: String) -> void:
	var paths: Array[String]=[first,second]
	var result:=REVIEW.load_documents(paths,world,catalog)
	_check(not result.ok and result.code==code and not result.has("snapshots"),message)

func _check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message)
