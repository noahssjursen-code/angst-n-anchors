extends Node3D

const Library := preload("res://scripts/port/building/custom_harbour_asset_library.gd")
var camera: Camera3D
var label: Label
var subject: Node3D
var door: Node3D
var target := Vector3(0, 1, 0)
var orbiting := false
var failures: Array[String] = []

func _ready() -> void:
	assert(ShipyardPlaytestMode.active(), "Run with --shipyard-playtest; no captain state is needed.")
	_setup()
	_build_assembly()
	_view(1)
	if OS.get_cmdline_user_args().has("--verify") or OS.get_cmdline_user_args().has("--capture"):
		call_deferred("_verify")

func _setup() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_4X
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var material := ProceduralSkyMaterial.new()
	material.sky_top_color = Color("6992b5")
	material.sky_horizon_color = Color("bbc8cc")
	material.ground_bottom_color = Color("344653")
	material.ground_horizon_color = Color("a9bcc8")
	sky.sky_material = material
	world.environment.sky = sky
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world.environment.ambient_light_energy = .62
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 48
	camera.far = 1000
	add_child(camera)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(24, 20)
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", Color("f3ede0"))
	label.add_theme_color_override("font_shadow_color", Color("14232d"))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(label)
	subject = Node3D.new()
	add_child(subject)

func _block(name_text: String, size: Vector3, position_at: Vector3, profile: String, tint: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = name_text
	var geometry := BoxMesh.new()
	geometry.size = size
	mesh.mesh = geometry
	mesh.position = position_at
	mesh.material_override = SurfaceMaterialLibrary.material(profile, tint)
	subject.add_child(mesh)
	SurfaceMaterialLibrary.map_frame(mesh)

func _asset(id: String, at: Vector3, yaw: float = 0.0) -> Node3D:
	var asset := Library.instantiate(id)
	assert(asset != null)
	asset.position = at
	asset.rotation_degrees.y = yaw
	subject.add_child(asset)
	return asset

func _build_assembly() -> void:
	_block("Foundation", Vector3(28, 3, 20), Vector3(0, -1.535, 3), "working_concrete", Color("777970"))
	_block("Asphalt", Vector3(27, .035, 19), Vector3(0, -.0175, 3), "asphalt", Color("454a47"))
	_block("Still water backdrop", Vector3(400, .05, 400), Vector3(0, -2.02, 0), "roof_sheet", Color("274958"))
	for index in 7:
		_asset("quay_edge_4m", Vector3(-12+index*4,0,-7))
	for x in [-12,-7,1,7,12]:
		_asset("tractor_tire_fender", Vector3(x,0,-7))
	for x in [-10,4,11]:
		_asset("quay_bollard", Vector3(x,0,-6))
	_asset("quay_ladder", Vector3(-2,0,-7))
	_asset("lifering_station", Vector3(-3.2,0,-5.8), 180)
	_asset("quay_light", Vector3(11,0,9))
	_asset("quay_light", Vector3(-11,0,9))
	_asset("timber_bundle", Vector3(6.8,0,3.5))
	_asset("timber_bundle", Vector3(8.4,0,3.5))
	_asset("pallet_stack", Vector3(8,0,-.5), 90)
	_asset("pallet_stack", Vector3(9,0,-.5), 90)
	# An exterior-only 8x8m building assembled from the same player library.
	door = _asset("workshop_door_4m", Vector3(-6,0,1))
	_asset("workshop_open_bay_4m", Vector3(-2,0,1))
	for z in [3,7]:
		_asset("workshop_window_4m", Vector3(-8,0,z), 90)
		_asset("workshop_wall_4m", Vector3(0,0,z), -90)
	for x in [-6,-2]:
		_asset("workshop_wall_4m", Vector3(x,0,9), 180)
		for z in [3,7]:
			_asset("workshop_roof_4m", Vector3(x,0,z))
		_asset("workshop_roof_edge_4m", Vector3(x,0,1))
		_asset("workshop_roof_edge_4m", Vector3(x,0,9),180)
	for row in [[-8,1,90],[0,1,0],[-8,9,180],[0,9,-90]]:
		_asset("workshop_corner_trim", Vector3(row[0],0,row[1]),row[2])

func _view(page: int) -> void:
	var title := ""
	match page:
		1:
			target=Vector3(-1,.7,1);camera.position=Vector3(25,19,-30);title="CUSTOM HARBOUR · 4 m construction kit"
		2:
			target=Vector3(-6,1.2,.7);camera.position=Vector3(-11,4,-8);title="WORKSHOP EXTERIOR · Modular walls, sealed windows and closed doors"
		3:
			target=Vector3(1,-.8,-7);camera.position=Vector3(3,1,-11);title="TRACTOR TYRE · Open sidewall, tread, chain and raised anchors"
		4:
			target=Vector3(-3,.8,-6.4);camera.position=Vector3(-6,2.8,-11);title="QUAY SAFETY · Existing ladder, new throw line and life ring"
		5:
			target=Vector3(8,.6,3);camera.position=Vector3(12,3.5,-3);title="STOCK DETAILS · Strapped timber and empty pallets"
		6:
			target=Vector3(-3,1.2,1);camera.position=Vector3(-9,2,-5);title="DECORATIVE ENTRANCES · Closed door and roller shutter"
	camera.look_at(target)
	label.text=title+"\n1–6 views · Right-drag orbit · Wheel zoom · P photograph"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode>=KEY_1 and event.keycode<=KEY_6:
			_view(int(event.keycode-KEY_1)+1)
		elif event.keycode==KEY_P:
			_capture("manual")
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT:orbiting=event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			camera.position=target+(camera.position-target)*(.9 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.1)
	if event is InputEventMouseMotion and orbiting:
		var offset:=camera.position-target
		offset=offset.rotated(Vector3.UP,-event.relative.x*.005)
		offset=offset.rotated(camera.global_basis.x,-event.relative.y*.005)
		camera.position=target+offset
		camera.look_at(target)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _verify() -> void:
	var ids := Library.definitions().keys()
	for id in ids:
		var spec := Library.specification(id)
		var prop := Library.instantiate(id)
		_check(prop!=null,"Model instantiates: "+id)
		if prop==null:continue
		_check(not SurfaceMaterialLibrary.meshes(prop).is_empty(),"Model has imported geometry: "+id)
		for bounds in spec.get("colliders",[]):
			for value in bounds.size_m:_check(float(value)>0,"Positive collider size: "+id)
		if not spec.get("existing_asset",false):
			_check(FileAccess.file_exists(spec.source_path),"Editable Blender source: "+id)
			var actual := _bounds(prop)
			var expected_min := Library._vector(spec.bounds_m.min)
			var expected_max := Library._vector(spec.bounds_m.max)
			_check(actual.position.distance_to(expected_min)<.012 and actual.end.distance_to(expected_max)<.012,"Imported bounds match metre manifest: "+id)
			if id=="tractor_tire_fender":
				_check(int(spec.triangles)<=5500,"Repeated tyre has a bounded close mesh cost")
		_check(spec.footprint_m.size()==2 and float(spec.snap_m)>0,"Physical units: "+id)
		prop.free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	Library.set_door_open(door,false)
	await get_tree().physics_frame
	var query:=PhysicsRayQueryParameters3D.create(Vector3(-6,1,0),Vector3(-6,1,2),1)
	_check(not get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"Closed door has actual collision")
	_check(not Library.set_door_open(door,true),"Decorative entrance rejects opening, including old save state")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"Decorative door remains solid")
	var bay_query:=PhysicsRayQueryParameters3D.create(Vector3(-2,1,0),Vector3(-2,1,2),1)
	_check(not get_world_3d().direct_space_state.intersect_ray(bay_query).is_empty(),"Workshop shutter blocks entry")
	if OS.get_cmdline_user_args().has("--capture"):
		for page in range(1,7):
			_view(page)
			await _capture("view-"+str(page))
		camera.position=Vector3(1.9,1.1,-7.8)
		camera.look_at(Vector3(1,.04,-7))
		label.text="TYRE ANCHORS · Separate mounting plate, coping and foundation surfaces"
		await _capture("tyre-anchor-close")
	print("CUSTOM HARBOUR ASSET REVIEW ","PASS" if failures.is_empty() else "FAIL"," assets=",ids.size()," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh in SurfaceMaterialLibrary.meshes(root):
		var frame: Transform3D = mesh.transform
		var ancestor := mesh.get_parent()
		while ancestor != root and ancestor != null:
			if ancestor is Node3D:frame=ancestor.transform*frame
			ancestor=ancestor.get_parent()
		var part: AABB = frame*mesh.get_aabb()
		bounds=part if first else bounds.merge(part)
		first=false
	return bounds

func _capture(description: String) -> void:
	for frame in 30:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var folder:="C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("custom-harbour-assets-"+str(Time.get_unix_time_from_system()).replace(".","-")+"-"+description+".png")
	_check(get_viewport().get_texture().get_image().save_png(path)==OK,"Screenshot saved to required archive")
	print("CAPTURE ",path)
