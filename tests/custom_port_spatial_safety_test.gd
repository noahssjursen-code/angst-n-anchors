extends Node
## Numeric ingress regression: JSON's finite64 values must not enter Godot
## geometry as infinities or collapsed asset edges. No renderer or save access.
const FIXTURE = preload("res://tests/custom_port_world_import_test.gd")
const SOURCE = preload("res://scripts/port/building/custom_port_world_import.gd")
const WORLD := {"seed":424242,"generation_version":12,"checksum":"world-import-test"}
var checks := 0
var failures: Array[String] = []

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	assert(ShipyardPlaytestMode.active())
	var base := FIXTURE.fixture("numeric-port", Vector3(100,.5,100), WORLD)
	var catalog := CustomPortCatalog.definitions()
	var cases: Dictionary = {}
	var value := base.duplicate(true)
	value.origin_m[0]=1e40; value.placements=[]; cases.origin=value
	value=base.duplicate(true)
	value.deck_height_above_sea_m=1e40; cases.deck=value
	value=base.duplicate(true)
	value.plots[0].rect_m=[-8,-8,1e40,16]; value.placements=[]; cases.plot_size=value
	value=base.duplicate(true)
	value.plots[0].rect_m=[3e38,-8,1e38,16]; value.placements=[]; cases.plot_endpoint=value
	value=base.duplicate(true)
	value.plots[0].rect_m=[1e20,-8,16,16]; value.placements=[]; cases.plot_precision=value
	value=base.duplicate(true)
	value.origin_m[0]=3e38; value.plots[0].rect_m=[0,-8,1e38,16]; value.placements=[]; cases.world_plot_endpoint=value
	value=base.duplicate(true)
	value.placements[0].position_m[0]=1e40; cases.placement=value
	value=base.duplicate(true)
	value.origin_m[0]=3e38; value.plots=[]; value.placements[0].position_m[0]=1e38; cases.world_placement_sum=value
	value=base.duplicate(true)
	value.placements[0].yaw_degrees=90.0*pow(2.0,200.0); cases.yaw=value
	value=base.duplicate(true)
	value.origin_m[0]=1e10; value.plots[0].rect_m=[-2048,-8,4096,16]; cases.world_asset_precision=value
	value=base.duplicate(true)
	value.water_regions=[{"rect_m":[-8,-8,1e40,16],"depth_m":10}]; cases.survey=value
	var streamer := CustomPortStreamer.new()
	add_child(streamer)
	streamer.configure(WORLD)
	streamer.loader.set_process(false)
	var zones := [{"center":Vector2(100,100),"half_size":Vector2(3,20),"yaw":0}]
	for key: String in cases:
		var record: Dictionary = cases[key]
		_check(CustomPortState._json_safe(record),key+": source remains finite64 JSON")
		var state := CustomPortState.from_dict(record,WORLD,catalog)
		_check(not state.validation_errors.is_empty() and str(state.validation_errors).contains("Unrepresentable"),key+": rejected by common State before geometry")
		var path := FIXTURE.write_fixture("spatial-"+key,record)
		var before := FileAccess.get_sha256(path)
		var loaded := CustomPortRepository.load_state(path,WORLD,catalog)
		_check(not loaded.ok and loaded.code=="invalid_document",key+": repository rejects")
		var updated := streamer.upsert_record(record)
		_check(not updated.ok and streamer.record("numeric-port").is_empty() and streamer.get("_entries").is_empty(),key+": streamer publishes no proximity entry")
		var imported := SOURCE.preflight([path],WORLD,false,[],zones)
		_check(not imported.ok and imported.code=="invalid_document",key+": import rejects before reserved clipping/chart publication")
		_check(FileAccess.get_sha256(path)==before,key+": rejected input file unchanged")
	streamer.free()
	var normal := FIXTURE.fixture("normal-port",Vector3(20000,.5,-20000),WORLD)
	normal.metadata={"valuation_nok":1e100}
	normal.placements[0].yaw_degrees=36000.0
	var accepted := CustomPortState.from_dict(normal,WORLD,catalog)
	_check(accepted.validation_errors.is_empty(),"Normal world dimensions and finite64 financial metadata remain valid")
	_check(CustomPortState._number(1e100),"Generic scalar/financial number semantics unchanged")
	var normal_path := FIXTURE.write_fixture("spatial-normal",normal)
	_check(SOURCE.preflight([normal_path],WORLD,false,[],[]).ok,"Normal world import remains valid")
	for failure in failures: push_error(failure)
	print("CUSTOM PORT SPATIAL SAFETY ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message)
