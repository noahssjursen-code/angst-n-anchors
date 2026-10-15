extends Node
## Inspect the real workshop and save an occupied example through its real data.
const WORKSHOP=preload("res://scenes/showcases/plot_building_showcase.tscn")
var failures: Array[String]=[]
var checks:=0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var workshop=WORKSHOP.instantiate()
	add_child(workshop)
	var deadline:=Time.get_ticks_msec()+90000
	while not workshop.ready_for_review and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	_check(workshop.ready_for_review,"Original plot scene opens the shared port workshop")
	if not workshop.ready_for_review:_finish();return
	var state: CustomPortState=workshop.state
	var record:=state.to_dict()
	var decoded:Dictionary=JSON.parse_string(JSON.stringify(record,"",true,true))
	var rebuilt:=CustomPortState.from_dict(decoded,record.world,workshop.catalog)
	_check(rebuilt.validation_errors.is_empty(),"Full decorated port survives JSON reconstruction: "+str(rebuilt.validation_errors))
	_check(rebuilt.derived_berths()==state.derived_berths(),"Independent reconstruction derives identical berths")
	_check(state.derived_berths().size()==4,"Cargo quay, projecting bulk quay and sheltered pier yield four slots")
	for row in record.placements:
		_check(float(row.position_m[1])==0,"Shared sea-level datum: "+str(row.id))
		_check(workshop.presenter.placement_nodes.has(str(row.id)),"Saved placement has a real model: "+str(row.id))
		if str(row.asset_id) in ["warehouse_roof_8x4","office_roof_8x4"]:
			var at:=CustomPortCatalog.vector3(row.position_m)
			var snapped:Dictionary=workshop.editor._snap(workshop.catalog[str(row.asset_id)],at,float(row.yaw_degrees))
			_check(snapped.position.is_equal_approx(at),"Example roof uses the actual construction snap: "+str(row.id))
	for vessel_id in ["nordlys","trader"]:
		var vessel:Dictionary={}
		for row in state.to_dict().vessels:
			if str(row.id)==vessel_id:vessel=row
		var berth_id:=""
		for berth in state.derived_berths():
			var fishing:bool=str(berth.id).contains("fishing-bollard")
			if (vessel_id=="nordlys")!=fishing:continue
			if not CustomPortBerths.fit(berth,vessel,[]).ok:continue
			if vessel_id=="trader" and not "container-yard" in CustomPortBerths.services_for_vessel(berth,vessel).store_ids:continue
			berth_id=str(berth.id);break
		_check(not berth_id.is_empty(),"Suitable real surveyed berth for "+vessel_id)
		if berth_id.is_empty():continue
		var result:=state.apply({"command_id":"waterfront-arrival-"+vessel_id,"expected_revision":state.revision(),"actor_company_id":vessel.owner_company_id,"kind":"dock","payload":{"vessel_id":vessel_id,"berth_id":berth_id}})
		_check(result.ok,"Authority accepts visitor "+vessel_id+": "+str(result.get("code","")))
		if result.ok:workshop._on_state_changed(state.to_dict(),result)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(workshop.presenter.vessel_nodes.size()==2,"Both vessels reconstructed from their records")
	# Exterior buildings stay closed, including when older saves ask to open them.
	var site:Vector3=workshop.site
	var library=preload("res://scripts/port/building/custom_harbour_asset_library.gd")
	_check(not library.specification("workshop_door_4m").has("door"),"Decorative doors expose no opening interaction")
	var facade:Dictionary=library.specification("harbour_office_upper_floor")
	_check(facade.colliders.size()==4,"Upper facade has exterior walls only, without interior floors or stairs")
	while not workshop.library.thumbnail_renderer.completed and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	_check(workshop.library.thumbnail_renderer.completed,"Every library model thumbnail finished rendering")
	for id in workshop.library.thumbnails:
		_check(workshop.library.thumbnails[id].texture!=null,"Actual model thumbnail: "+str(id))
	workshop.library.hide();workshop.overlays.hide();workshop.ui.hide();workshop.hotbar.hide()
	if is_instance_valid(workshop.ghost):workshop.ghost.hide()
	for shot in [
		["finished-waterfront",Vector3(-145,70,-60),Vector3(-25,3,28)],
		["inlet-with-nordlys",Vector3(-77,13,-9),Vector3(-107,2,26)],
		["angled-quay-and-loft",Vector3(-128,7,-7),Vector3(-109,2,16)],
		["workshop-frontage",Vector3(-26,4,42),Vector3(-43,2.6,53)],
		["harbour-office",Vector3(-9,4,41),Vector3(-20,4,56)],
		["net-cages",Vector3(-117,1.8,20),Vector3(-115,1,26)]]:
		workshop.camera.position=site+shot[1]
		workshop.camera.look_at(site+shot[2])
		await get_tree().create_timer(.35).timeout
		await workshop._capture(str(shot[0]))
	workshop.save_port()
	print("WATERFRONT_SAVED_EXAMPLE ",ProjectSettings.globalize_path(workshop.save_path))
	workshop.ui.show();workshop.library.show()
	for index in workshop.library.category.item_count:
		if workshop.library.category.get_item_text(index)=="Waterfront buildings":
			workshop.library.category.select(index);workshop.library.category.item_selected.emit(index)
	workshop.camera.position=site+Vector3(-77,13,-9)
	workshop.camera.look_at(site+Vector3(-107,2,26))
	await get_tree().process_frame
	await workshop._capture("waterfront-model-library")
	_finish()

func _check(value:bool,why:String) -> void:
	checks+=1
	if not value:failures.append(why);push_error(why)

func _finish() -> void:
	print("CUSTOM PORT WATERFRONT ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
