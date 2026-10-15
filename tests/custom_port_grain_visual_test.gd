extends "res://tests/custom_port_bulk_transfer_test.gd"

var grain_checks := 0

func _run() -> void:
	_check(OreMoundBuilder.resolve_commodity("grain")=="grain","Grain preserves its actual commodity identity")
	for enabled in [true,false]:
		SurfaceMaterialLibrary.enabled=enabled
		var material:=OreMoundBuilder.material_for("grain") as ShaderMaterial
		_check(material.shader==OreMoundBuilder.ORE_PILE_SHADER and int(material.get_shader_parameter("pile_kind"))==2,"Grain uses the cereal material with the material library enabled or disabled")
		var coal:=OreMoundBuilder.material_for("coal") as ShaderMaterial
		var ore:=OreMoundBuilder.material_for("iron_ore") as ShaderMaterial
		if enabled:
			_check(coal.get_meta("marine_profile")=="coal_aggregate" and ore.get_meta("marine_profile")=="crushed_aggregate","Existing textured coal and ore profiles are preserved")
		else:
			_check(int(coal.get_shader_parameter("pile_kind"))==1 and int(ore.get_shader_parameter("pile_kind"))==0,"Existing procedural coal and ore variants are preserved")
	SurfaceMaterialLibrary.enabled=true
	var world: Dictionary={"seed":73119,"generation_version":1,"checksum":"grain-visual-fixture"}
	var plots: Array=[{"id":"plot-west","rect_m":[-124,-108,200,200],"owner_company_id":CustomPortExample.OWNER}]
	var snapshot:=CustomPortExample.build(Vector3(0,.5,0),plots,world)
	snapshot.erase("_site_yaw")
	snapshot.water_regions=[{"rect_m":[-128,-104,232,168],"depth_m":12.0}]
	var shore:=Transfer._find(snapshot.stores,"bulk-yard")
	shore.accepted_commodities=["coal","grain","iron_ore"]
	shore.lots=[]
	for commodity in shore.accepted_commodities:
		shore.lots.append({"id":commodity+"-stock","commodity_id":commodity,"quantity":80000,"unit_mass_kg":1,"attributes":{"slots_per_unit":0}})
	state=CustomPortState.from_dict(snapshot,world,CustomPortCatalog.definitions())
	_check(state.validation_errors.is_empty(),"Three-commodity fixture is valid: "+str(state.validation_errors))
	if not state.validation_errors.is_empty():get_tree().quit(1);return
	port=CustomPortPresenter.new()
	add_child(port)
	transfer=Transfer.new()
	add_child(transfer)
	transfer.bind(port)
	transfer.set_process(false)
	transfer.presentation_failed.connect(func(reason: String):animation_errors.append(reason))
	transfer.present(state.to_dict(),state.derived_berths())
	var grain: Node3D=port.cargo_nodes["grain-stock"]
	var ore: Node3D=port.cargo_nodes["iron_ore-stock"]
	var coal: Node3D=port.cargo_nodes["coal-stock"]
	_check(grain!=ore and grain!=coal and grain.global_position.distance_to(ore.global_position)>3,"Three commodities occupy separate actual yard bays")
	_check(_is_grain(grain),"Permanent grain pile uses cereal on every lobe")
	var unchanged: Dictionary={"coal":coal.scale,"ore":ore.scale}
	if native_capture:
		for commodity in shore.accepted_commodities:
			var nameplate:=Label3D.new()
			nameplate.text=CommodityCatalog.commodity_display(commodity)+" · 80 t"
			nameplate.position=port.cargo_nodes[commodity+"-stock"].global_position+Vector3.UP*2.5
			nameplate.billboard=BaseMaterial3D.BILLBOARD_ENABLED
			nameplate.pixel_size=.012
			nameplate.font_size=40
			add_child(nameplate)
		target=(coal.global_position+grain.global_position+ore.global_position)/3
		camera.position=target+Vector3(22,25,30)
		camera.look_at(target)
		label.text="THREE SUPPORTED BULK COMMODITIES\nCoal, cereal grain and iron ore occupy their own finite stock bays"
		await _capture("grain-three-stockpiles")
		target=grain.global_position+Vector3.UP*.7
		camera.position=target+Vector3(5,4,5)
		camera.look_at(target)
		label.text="CEREAL GRAIN · Close surface review\nDry, non-metallic kernels and small settled surface variation"
		await _capture("grain-material-close")
	var trader:=Transfer._find(state.to_dict().vessels,"bulk-trader")
	var berth_id:=""
	for berth in state.derived_berths():
		if CustomPortBerths.fit(berth,trader,[]).ok and "bulk-yard" in CustomPortBerths.services_for_vessel(berth,trader,"bulk").store_ids:
			berth_id=str(berth.id);break
	_check(not berth_id.is_empty(),"Actual bulk vessel has a reachable berth")
	if berth_id.is_empty():get_tree().quit(1);return
	_apply("dock",{"vessel_id":"bulk-trader","berth_id":berth_id})
	await get_tree().process_frame
	var ship: BoatBody=port.vessel_nodes["bulk-trader"]
	var hold: BulkHoldComponent=ship.get_bulk_holds()[0]
	var crane:=port.placement_nodes["bulk-terminal"].find_child("Crane",true,false) as BulkCrane
	slew_before=crane.slew_degrees
	_apply("reserve_cargo",{"store_id":"bulk-yard","vessel_id":"bulk-trader","lot_id":"grain-stock","quantity":20000,"reservation_id":"grain-load"})
	_apply("load_cargo",{"reservation_id":"grain-load"})
	_check(transfer.bulk.is_busy() and transfer.bulk.total_grabs==1,"Accepted grain load runs through the actual grab")
	_check(hold.state.commodity_id=="grain" and is_equal_approx(hold.state.filled_tonnes_t,20) and _is_grain(hold._fill_layer),"Committed real hold shows 20 tonnes of grain, not ore")
	_check(_all_grain_proxies(),"Loading pile, hold and grab proxy all carry the grain material")
	var committed:=JSON.stringify(state.to_dict())
	label.text="GRAIN LOADING · Existing crane, finite stock and actual vessel hold\nCereal material follows shore pile → grab → falling cargo → ship"
	await _finish_bulk("grain-load")
	_check(JSON.stringify(state.to_dict())==committed,"Loading animation does not alter accepted authority data")
	_check(_bulk_proxy_count()==0 and hold._fill_layer.visible,"Completed loading removes temporary visuals and restores real grain")
	_check(port.cargo_nodes["coal-stock"].scale==unchanged.coal and port.cargo_nodes["iron_ore-stock"].scale==unchanged.ore,"Coal and iron ore piles do not change during grain loading")
	_apply("unload_cargo",{"store_id":"bulk-yard","vessel_id":"bulk-trader","lot_id":"grain-stock","quantity":20000})
	_check(transfer.bulk.is_busy() and _all_grain_proxies(),"Unloading creates cereal proxies even when the committed hold becomes empty")
	committed=JSON.stringify(state.to_dict())
	label.text="GRAIN UNLOADING · Same commodity in the opposite direction\nThe empty committed hold is restored when the visual transfer finishes"
	await _finish_bulk("grain-unload")
	_check(JSON.stringify(state.to_dict())==committed and hold.state.is_empty(),"Unloading preserves the accepted empty hold")
	_check(_is_grain(port.cargo_nodes["grain-stock"]) and _bulk_proxy_count()==0,"Final shore grain is correct and no temporary cargo remains")
	_check(float(Transfer._find(Transfer._find(state.to_dict().stores,"bulk-yard").lots,"grain-stock").quantity)==80000,"Finite grain stock returns to its exact 80-tonne fixture balance")
	_check(animation_errors.is_empty(),"No grain transfer presentation failure: "+str(animation_errors))
	await _settle_audio_before_exit()
	print("CUSTOM PORT GRAIN VISUAL ","PASS" if failures.is_empty() else "FAIL"," checks=",grain_checks," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _finish_bulk(direction: String) -> void:
	var steps:=0
	var checked_falling:=false
	while transfer.is_busy() and steps<12000:
		transfer._process(.05)
		steps+=1
		if steps%40==0:await get_tree().process_frame
		if not checked_falling and not transfer.bulk._grains.is_empty():
			checked_falling=true
			_check(_all_grain_proxies(),"Every falling cargo piece keeps cereal material during "+direction)
		if native_capture and (transfer.bulk._phase=="travel_drop" or (transfer.bulk._phase=="dump" and transfer.bulk._timer>.4)):
			var key:=direction+"-"+str(transfer.bulk._phase)
			if not bulk_captures.has(key):
				bulk_captures[key]=true
				var crane:=port.placement_nodes["bulk-terminal"].find_child("Crane",true,false) as BulkCrane
				target=crane.get_bucket_mouth_global()+Vector3.DOWN*.5
				camera.position=target+Vector3(10,9,-12)
				camera.look_at(target)
				await _capture(key)
	_check(not transfer.is_busy() and checked_falling,"Grain transfer completes with a real visible dump: "+direction)
	await get_tree().process_frame

func _is_grain(node: Node3D) -> bool:
	if not is_instance_valid(node):return false
	var meshes:=SurfaceMaterialLibrary.meshes(node)
	if meshes.is_empty():return false
	for mesh in meshes:
		var material: ShaderMaterial=mesh.material_override
		if material==null or material.shader!=OreMoundBuilder.ORE_PILE_SHADER or int(material.get_shader_parameter("pile_kind"))!=2:return false
	return true

func _all_grain_proxies() -> bool:
	if transfer.bulk._visuals.is_empty():return false
	for visual in transfer.bulk._visuals:
		if not _is_grain(visual):return false
	return true

func _check(ok: bool,message: String) -> void:
	grain_checks+=1
	super._check(ok,message)
