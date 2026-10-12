extends Node3D

var _camera: Camera3D
var _bridges: Array
var _selected := 0
var _angle := .65
var _distance := 1200.0
var _label: Label
var _seed := 1850239324

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): _seed=int(arg.trim_prefix("--seed="))
	var layout := WorldLayoutGenerator.generate(_seed)
	var ports := CoastalPortPlacer.place_ports(layout)
	var zones := WorldTerrainStreamer.make_flatten_zones(ports,0.0,_seed,layout)
	var settlements := CoastalSettlementPlan.build(layout,ports,zones)
	var plan := CoastalBridgePlan.build(layout,ports,settlements.buildings)
	_bridges=[]
	for crossing: Dictionary in plan.bridges:
		var structure := BridgeStructurePlan.design(crossing,layout,"",zones,settlements.roads)
		if not structure.accepted: continue
		add_child(BridgeAssembler.build(structure))
		var record := crossing.duplicate()
		record.deck_y=structure.deck_y
		record.family=structure.family
		_bridges.append(record)
	print("BRIDGE SHOWCASE seed=",_seed," bridges=",_bridges.size()," ms=",plan.build_ms)
	var towns := CoastalSettlements.new()
	add_child(towns)
	towns.configure(layout,settlements,zones)
	for port: PortDefinition in ports:
		var marker := Label3D.new()
		marker.text=port.display_name+" (port)"
		marker.position=port.world_position+Vector3.UP*60
		marker.font_size=42;marker.pixel_size=.4
		marker.modulate=Color(1,.8,.3)
		marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		add_child(marker)
	_camera=Camera3D.new()
	_camera.far=16000
	add_child(_camera)
	_camera.current=true
	var light := DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-55,-30,0)
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(.38,.53,.65)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color(.65,.72,.8)
	environment.environment.ambient_light_energy=.6
	add_child(environment)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size=Vector2.ONE*layout.world_size_m
	water.mesh=plane
	var material := StandardMaterial3D.new()
	material.albedo_color=Color(.055,.18,.24)
	water.material_override=material
	water.position.y=WaveSurface.WATER_LEVEL
	add_child(water)
	var terrain := WorldTerrainStreamer.new()
	terrain.visual_radius_m=5500
	terrain.collision_radius_m=0
	add_child(terrain)
	terrain.configure(layout,ports)
	var ui := CanvasLayer.new()
	add_child(ui)
	_label=Label.new()
	_label.position=Vector2(18,18)
	ui.add_child(_label)
	if _bridges.is_empty():
		_label.text="No bridge candidates for seed %d" % _seed
		if OS.get_cmdline_user_args().has("--capture"): get_tree().quit(1)
		return
	_select(0)
	if OS.get_cmdline_user_args().has("--capture"):
		for index in mini(2,_bridges.size()):
			_select(index)
			for frame in 300: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var directory := "C:/Users/noahs/Pictures/machinescreenshots"
			DirAccess.make_dir_recursive_absolute(directory)
			var path := directory+"/bridge-preview-%d-%d-%d.png" % [_seed,index,Time.get_ticks_usec()]
			get_viewport().get_texture().get_image().save_png(path)
			print("CAPTURE ",path)
		get_tree().quit()

func _select(index: int) -> void:
	_selected=wrapi(index,0,_bridges.size())
	_distance=maxf(750,_bridges[_selected].span_m*1.5)
	_label.text="PROCEDURAL MODULAR BRIDGES | seed %d | %d / %d | %s\nSpace: next crossing | arrows: orbit / zoom\nTerrain-fitted approaches, physical decks and supports" % [_seed,_selected+1,_bridges.size(),_bridges[_selected].family]
	_update_camera()

func _update_camera() -> void:
	var bridge: Dictionary = _bridges[_selected]
	var target := Vector3(bridge.center.x,bridge.deck_y,bridge.center.y)
	_camera.position=target+Vector3(cos(_angle)*_distance,_distance*.65,sin(_angle)*_distance)
	_camera.look_at(target)

func _process(delta: float) -> void:
	if _bridges.is_empty(): return
	_angle+=Input.get_axis("ui_left","ui_right")*delta
	_distance=clampf(_distance+Input.get_axis("ui_up","ui_down")*delta*500,150,5000)
	_update_camera()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_SPACE and not _bridges.is_empty():
		_select(_selected+1)
