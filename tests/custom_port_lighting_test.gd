extends "res://tests/custom_harbour_asset_review.gd"

var count := 0
var port: CustomPortPresenter
var custom: Node3D
var existing: Node3D
var environment: Environment
var sun: DirectionalLight3D

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	_setup()
	for child in get_children():
		if child is WorldEnvironment: environment=child.environment
		elif child is DirectionalLight3D: sun=child
	WorldClock.set_process(false)
	WeatherLighting.set_process(false)
	_run.call_deferred()

func _run() -> void:
	var snapshot := {"id":"light-review","origin_m":[0,0,0],"placements":[
		CustomPortCatalog.placement("custom-light","quay_light",Vector3(-14,0,4))],"stores":[],"vessels":[]}
	port=CustomPortPresenter.new();port.simulate_vessels=false;add_child(port)
	port.load_record(snapshot)
	custom=port.placement_nodes["custom-light"]
	existing=HarbourEnvironmentKit.model(subject,"quay_light",Vector3(14,0,4))
	for x in [-14.0,14.0]:
		_block("Concrete apron",Vector3(24,.4,24),Vector3(x,-.2,1),"working_concrete",Color("92958b"))
		var pallets:=Library.instantiate("pallet_stack")
		pallets.position=Vector3(x+3,0,0);subject.add_child(pallets)
		var ring:=Library.instantiate("lifering_station")
		ring.position=Vector3(x-3,0,3);subject.add_child(ring)
		var sign:=Label3D.new();sign.text="CUSTOM PORT" if x<0 else "EXISTING PORT";sign.font_size=64;sign.pixel_size=.018
		sign.position=Vector3(x,1,-10);sign.billboard=BaseMaterial3D.BILLBOARD_ENABLED;subject.add_child(sign)
	camera.position=Vector3(0,21,37);camera.look_at(Vector3(0,1,0))
	_check(custom.find_children("*","Light3D",true,false).size()==1,"A placed custom quay light contains exactly one runtime light")
	_check(existing.find_children("*","Light3D",true,false).size()==1,"Existing generated-port light remains unchanged")
	var ghost:=CustomPortPresenter.asset_visual(CustomPortCatalog.definition("quay_light"),true,true)
	add_child(ghost)
	_check(ghost.find_children("*","Light3D",true,false).is_empty(),"A placement ghost emits no light and owns no updating light component")
	ghost.free()
	_set_time(false)
	for node in [custom,existing]:
		var lights: Array= node.find_children("*","Light3D",true,false)
		if not lights.is_empty():
			var lamp:SpotLight3D=lights[0]
			_check(lamp.visible and is_equal_approx(lamp.light_energy,20.0),"Night activates the existing full lamp energy")
			_check(lamp.shadow_enabled and lamp.distance_fade_enabled and is_equal_approx(lamp.distance_fade_begin,160.0),"Existing shadow and distance budget remains active")
			_check(not lamp.lenses.is_empty() and lamp.lenses[0].emission_energy_multiplier>2.9,"The actual authored diffuser glows at night")
	label.text="QUAY LIGHT REUSE · NIGHT\nLeft: custom placed asset · Right: existing generated-port asset · identical model and lighting conditions"
	if "--capture" in OS.get_cmdline_user_args(): await _capture("custom-port-light-night")
	_set_time(true)
	for node in [custom,existing]:
		for lamp in node.find_children("*","Light3D",true,false):
			_check(not lamp.visible and is_zero_approx(lamp.light_energy),"Daylight turns off the lamp")
			_check(lamp.lenses.is_empty() or is_zero_approx(lamp.lenses[0].emission_energy_multiplier),"Daylight turns off diffuser emission")
	label.text="QUAY LIGHT REUSE · DAY\nBoth use the same daylight dimming · the construction ghost never adds light"
	if "--capture" in OS.get_cmdline_user_args(): await _capture("custom-port-light-day")
	port.load_record(snapshot)
	_check(port.placement_nodes["custom-light"]==custom and custom.find_children("*","Light3D",true,false).size()==1,"Repeated snapshots neither rebuild nor duplicate the lamp")
	var old: WeakRef=weakref(custom)
	snapshot.placements[0].position_m=[-10,0,4]
	snapshot.placements[0].yaw_degrees=90
	port.load_record(snapshot)
	await get_tree().process_frame
	custom=port.placement_nodes["custom-light"]
	_check(old.get_ref()==null and custom.find_children("*","Light3D",true,false).size()==1,"Moving a light tears down the old component and creates exactly one replacement")
	var lamps:=custom.find_children("*","Light3D",true,false)
	if not lamps.is_empty():
		_check(lamps[0].global_position.distance_to(custom.to_global(Vector3(0,7.4,-1.2)))<.001,"Rotated light remains at its authored diffuser offset")
	old=weakref(custom)
	port.clear_record()
	await get_tree().process_frame
	_check(old.get_ref()==null and port.find_children("*","Light3D",true,false).is_empty(),"Unloading the streamed port removes all its light components")
	_check(is_instance_valid(existing) and existing.find_children("*","Light3D",true,false).size()==1,"Custom-port teardown leaves externally-owned lights alone")
	for failure in failures: push_error(failure)
	print("CUSTOM PORT LIGHTING ","PASS" if failures.is_empty() else "FAIL"," checks=",count," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _set_time(day: bool) -> void:
	WeatherLighting.time_of_day=.5 if day else .0
	environment.ambient_light_energy=.62 if day else .04
	sun.light_energy=1.3 if day else .025
	for node in [custom,existing]:
		for lamp in node.find_children("*","Light3D",true,false):lamp._update()

func _check(ok: bool,message: String) -> void:
	count+=1
	if not ok:failures.append(message)
