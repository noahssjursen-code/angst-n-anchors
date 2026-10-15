extends Node

const SOURCE = preload("res://scripts/port/building/custom_port_world_import.gd")
const WORLD := {"seed":424242,"generation_version":12,"checksum":"world-import-test"}
var checks := 0
var failures: Array[String] = []

func _ready() -> void:_run.call_deferred()

func _run() -> void:
	assert(ShipyardPlaytestMode.active())
	var context := {"seed":WORLD.seed,"generation_version":WORLD.generation_version,"layout_checksum":WORLD.checksum,"world_size_m":40000,"irrelevant":"not identity"}
	_check(SOURCE.world_identity(context)==WORLD,"Final layout checksum normalizes to exact three-field identity")
	_check(SOURCE.document_arguments(["--shipyard-playtest","--custom-port-document=C:/A port.json","--custom-port-document=user://b.json"])==PackedStringArray(["C:/A port.json","user://b.json"]),"Explicit repeatable paths preserve spaces")
	_check(SOURCE.preflight([],{},false,[],[]).code=="disabled","Default is disabled, with no world or filesystem required")
	_check(SOURCE.preflight(["Z:/missing/never-open.json"],{},true,[],[]).code=="remote_import_forbidden","Remote rejection precedes identity/path/file reads")
	var many := PackedStringArray()
	for index in 33:many.append("missing")
	_check(SOURCE.preflight(many,WORLD,false,[],[]).code=="too_many_documents","Document count is bounded before opening files")
	var a := fixture("port-a",Vector3(100,.5,100),WORLD)
	var b := fixture("port-b",Vector3(200,.5,100),WORLD)
	var path_a := write_fixture("a",a)
	var path_b := write_fixture("b",b)
	var checksum_a := FileAccess.get_sha256(path_a)
	var valid := SOURCE.preflight([path_a,path_b],WORLD,false,[],[])
	_check(valid.ok and valid.records.size()==2,"Two individually validated world-matched documents preflight")
	_check(valid.summaries.size()==2 and not valid.summaries[0].has("vessels") and not valid.summaries[0].has("stores"),"Only public construction is published")
	var wrong := WORLD.duplicate(true)
	wrong.checksum="same-seed-different-layout"
	_check(SOURCE.preflight([path_a],wrong,false,[],[]).code=="wrong_world","Seed alone cannot accept the wrong layout")
	_check(SOURCE.preflight([path_a,path_a],WORLD,false,[],[]).code=="invalid_collection","Duplicate document IDs reject the complete batch")
	var overlap := fixture("overlap",Vector3(101,.5,101),WORLD)
	_check(SOURCE.preflight([path_a,write_fixture("overlap",overlap)],WORLD,false,[],[]).code=="invalid_collection","Different ports cannot claim overlapping plots")
	_check(SOURCE.preflight([path_a],WORLD,false,["port-a"],[]).code=="generated_port_id_conflict","Generated identifier collision is rejected")
	var zones := [{"center":Vector2(100,100),"half_size":Vector2(3,20),"yaw":PI/4}]
	_check(SOURCE.preflight([path_a],WORLD,false,[],zones).code=="generated_footprint_conflict","Oriented generated pad conflicts reject")
	zones=[{"polygon":PackedVector2Array([Vector2(99,99),Vector2(101,99),Vector2(100,101)])}]
	_check(SOURCE.preflight([path_a],WORLD,false,[],zones).code=="generated_footprint_conflict","Nested bridge or settlement polygon conflicts reject")
	zones=[{"center":Vector2(110,100),"half_size":Vector2(2,8),"yaw":0}]
	_check(SOURCE.preflight([path_a],WORLD,false,[],zones).ok,"An exact plot boundary touching a reservation stays legal")
	var wrong_plane := fixture("wrong-plane",Vector3(300,2,100),WORLD)
	_check(SOURCE.preflight([write_fixture("wrong-plane",wrong_plane)],WORLD,false,[],[]).code=="incompatible_deck_plane","Imported ports obey the single sea-level deck plane")
	var bad_path := "user://port-import-test/broken.json"
	var file := FileAccess.open(bad_path,FileAccess.WRITE)
	file.store_string("{broken");file.close()
	var source := SOURCE.new()
	add_child(source)
	PortCatalog.clear()
	PortCatalog.register_port("legacy","Generated harbour",Vector3.ZERO)
	var before_revision := PortCatalog.revision
	var rejected: Dictionary=source.load_documents([path_a,bad_path],context,false,["legacy"],[],PortCatalog)
	_check(not rejected.ok and source.streamer==null and PortCatalog.get_custom_port_summaries().is_empty(),"Mixed bad batch installs no streamer or partial chart marker")
	_check(PortCatalog.revision==before_revision and PortCatalog.get_port_ids()==["legacy"],"Failed import leaves generated directory and revision unchanged")
	var imported: Dictionary=source.load_documents([path_a,path_b],context,false,["legacy"],[],PortCatalog)
	_check(imported.ok and source.streamer!=null,"Complete good batch installs one streamer")
	_check(PortCatalog.get_port_ids()==["legacy"] and PortCatalog.nearest_port_id(Vector2(100,100))=="legacy","Passive custom ports do not enter proximity/routing directory")
	var chart := ChartDataSnapshot.from_live_tree(get_tree())
	_check(chart.port_ids().has("port-a") and chart.port_ids().has("legacy"),"Live chart explicitly merges passive and generated entries")
	_check(chart.port_info("port-a").source=="custom" and not chart.port_info("port-a").services_ready,"Chart retains passive source and unavailable service flag")
	_check(ChartHarbourPlan.resolve_port_data("port-a",get_tree(),chart)==null,"Custom chart never invents a generated harbour")
	var summaries:=PortCatalog.get_custom_port_summaries()
	summaries[0].display_name="changed outside"
	_check(PortCatalog.get_custom_port_summaries()[0].display_name!="changed outside","Directory returns independent copies")
	var replacement := Node.new()
	add_child(replacement)
	_check(PortCatalog.register_custom_summary(valid.summaries[0],replacement),"Replacement source can own the same passive ID")
	source.queue_free()
	for frame in 3:await get_tree().process_frame
	_check(PortCatalog.get_custom_port_summaries().size()==1 and PortCatalog.get_custom_port_summaries()[0].id=="port-a","Old source teardown cannot erase replacement-owned entry")
	PortCatalog.unregister_custom_summary("port-a",replacement)
	_check(PortCatalog.get_custom_port_summaries().is_empty() and PortCatalog.get_port_ids()==["legacy"],"Owner cleanup removes only its own passive directory")
	replacement.queue_free()
	_check(FileAccess.get_sha256(path_a)==checksum_a,"Import/reject/teardown never rewrite source JSON")
	for frame in 3:await get_tree().process_frame
	for failure in failures:push_error(failure)
	print("CUSTOM PORT WORLD IMPORT ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	get_tree().quit(0 if failures.is_empty() else 1)

static func fixture(id: String, origin: Vector3, identity: Dictionary) -> Dictionary:
	return {"schema_version":1,"id":id,"name":id,"owner_company_id":"company-import",
		"world":identity.duplicate(true),"origin_m":[origin.x,origin.y,origin.z],"deck_height_above_sea_m":2.0,
		"plots":[{"id":id+"-plot","owner_company_id":"company-import","rect_m":[-8,-8,16,16]}],
		"placements":[{"id":"deck","asset_id":"foundation_8m","position_m":[0,0,0],"yaw_degrees":0}],
		"stores":[],"vessels":[],"water_regions":[],"reservations":[],"receipts":{},"revision":0}

static func write_fixture(name: String, record: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://port-import-test"))
	var path := "user://port-import-test/"+name+".json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(record,"\t",true,true));file.close()
	return path

func _check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message)
