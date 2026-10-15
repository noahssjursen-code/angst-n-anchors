extends Node
## Recovery must preserve the latest usable cargo/receipt record, even when the
## primary is unavailable. This runs only in an isolated test profile.
const State = preload("res://scripts/port/state/custom_port_state.gd")
const Repository = preload("res://scripts/port/state/custom_port_repository.gd")
const Fixture = preload("res://tests/custom_port_data_test.gd")
var failures: Array[String] = []
var checks := 0
var directory := ""
var catalog: Dictionary
var world: Dictionary
var current: CustomPortState
var stale: CustomPortState

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ShipyardPlaytestMode.active():
		push_error("Recovery tests require --shipyard-playtest isolation.")
		get_tree().quit(1); return
	directory = "user://custom-port-recovery-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	var fixture := Fixture.new()
	var record: Dictionary = fixture.call("_fixture")
	catalog = fixture.call("_catalog")
	fixture.free()
	world = record.world
	current = State.from_dict(record,world,catalog)
	_check(current.validation_errors.is_empty(),"Fixture validates")
	_check(_command("dock",{"vessel_id":"ship-a","berth_id":current.derived_berths()[0].id}).ok,"Vessel docks")
	_check(_command("reserve_cargo",{"store_id":"yard","vessel_id":"ship-a","lot_id":"coal-lot","quantity":1250,"reservation_id":"cargo-r"}).ok,"Finite cargo reserved")
	stale = State.from_dict(current.to_dict(),world,catalog)
	_check(_command("load_cargo",{"reservation_id":"cargo-r"}).ok,"Cargo and receipt commit before the damaged save")
	for mode in ["missing","truncated","checksum","raw-backup"]:
		_recovery_case(mode)
	_future_backup()
	for failure in failures: push_error(failure)
	print("CUSTOM PORT REPOSITORY RECOVERY ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _command(kind: String,payload: Dictionary) -> Dictionary:
	return current.apply({"command_id":kind,"expected_revision":current.revision(),"actor_company_id":"company-a","kind":kind,"payload":payload})

func _recovery_case(mode: String) -> void:
	var path := directory.path_join(mode+".json")
	_check(Repository.save(path,current).ok and Repository.save(path,current).ok,mode+": current and backup established")
	if mode=="missing":
		_check(DirAccess.remove_absolute(path)==OK,"Remove only the isolated primary")
	elif mode=="checksum":
		var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		document.snapshot.name="Damaged name without checksum"
		_write(path,JSON.stringify(document,"",true,true))
	else:
		_write(path,"{truncated")
	if mode=="raw-backup": _write(path+".bak",JSON.stringify(current.to_dict(),"",true,true))
	var original_primary := _bytes(path)
	var original_backup := _bytes(path+".bak")
	var recovery := Repository.load_state(path,world,catalog)
	_check(recovery.ok and recovery.recovered_from_backup and recovery.snapshot==current.to_dict(),mode+": last usable cargo document recovers")
	_reject(path,stale,"stale_snapshot",original_primary,original_backup)
	var divergent := current.to_dict()
	divergent.name="A different branch at the same revision"
	_reject(path,State.from_dict(divergent,world,catalog),"snapshot_revision_conflict",original_primary,original_backup)
	var foreign := current.to_dict()
	foreign.id="other-port"
	# Berth IDs are namespaced by port ID; a different valid document cannot
	# retain the source port's occupied berth reference.
	foreign.vessels[0].berth_id=""
	_reject(path,State.from_dict(foreign,world,catalog),"port_identity_conflict",original_primary,original_backup)
	foreign=current.to_dict()
	foreign.world.checksum="other-world"
	_reject(path,State.from_dict(foreign,foreign.world,catalog),"port_identity_conflict",original_primary,original_backup)
	var recovered_again := Repository.load_state(path,world,catalog)
	_check(recovered_again.ok and recovered_again.snapshot.vessels[0].lots[0].quantity==1250 and recovered_again.snapshot.receipts.has("load_cargo"),mode+": refused writes retain all loaded cargo and its receipt")
	_check(Repository.save(path,recovery.state).ok,mode+": identical recovered revision explicitly repairs the primary")
	_check(_bytes(path+".bak")==original_backup,mode+": repair preserves exact recovery bytes")
	var repaired := Repository.load_state(path,world,catalog)
	_check(repaired.ok and not repaired.recovered_from_backup and repaired.snapshot==current.to_dict(),mode+": repaired primary matches durable data")
	var retry: Dictionary = repaired.state.apply({"command_id":"load_cargo","expected_revision":2,"actor_company_id":"company-a","kind":"load_cargo","payload":{"reservation_id":"cargo-r"}})
	_check(retry.ok and retry.code=="already_applied" and retry.events.is_empty() and repaired.state.to_dict()==current.to_dict(),mode+": retry cannot reapply the recovered cargo movement")
	var changed: Dictionary = repaired.state.apply({"command_id":"after-recovery","expected_revision":3,"actor_company_id":"company-a","kind":"rename_port","payload":{"name":"Recovered harbour"}})
	_check(changed.ok and Repository.save(path,repaired.state).ok,mode+": newer accepted revision still saves normally")
	_check(Repository.load_state(path,world,catalog).snapshot.revision==4,mode+": newer revision reopens")
	_check(Repository.load_state(path+".bak",world,catalog).snapshot==current.to_dict(),mode+": ordinary save keeps the prior good snapshot")
	_check(Array(DirAccess.open(ProjectSettings.globalize_path(directory)).get_files()).filter(func(file: String) -> bool:return file.contains(".tmp-")).is_empty(),mode+": failed writes leave no temporary files")

func _future_backup() -> void:
	var path := directory.path_join("future.json")
	var encoded := JSON.stringify({"file_format":Repository.FILE_FORMAT,"file_version":999,"snapshot":current.to_dict()},"",true,true)
	_write(path+".bak",encoded)
	var original := _bytes(path+".bak")
	var result := Repository.save(path,current)
	_check(not result.ok and result.code=="existing_file_incompatible","Missing primary cannot downgrade an unknown newer recovery format")
	_check(not FileAccess.file_exists(path) and _bytes(path+".bak")==original,"Unknown recovery document is preserved byte for byte")

func _reject(path: String,state: CustomPortState,code: String,primary: Dictionary,backup: Dictionary) -> void:
	var before := state.to_dict()
	_check(state.validation_errors.is_empty(),"Candidate is individually valid before the recovery conflict check")
	var result := Repository.save(path,state)
	_check(not result.ok and result.code==code,path.get_file()+": rejects "+code+"; got "+str(result))
	_check(state.to_dict()==before and _bytes(path)==primary and _bytes(path+".bak")==backup,"Rejected save changes neither data nor primary/recovery bytes")

func _write(path: String,text: String) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _bytes(path: String) -> Dictionary:
	var exists := FileAccess.file_exists(path)
	return {"exists":exists,"bytes":FileAccess.get_file_as_bytes(path) if exists else PackedByteArray()}

func _check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures.append(message)
