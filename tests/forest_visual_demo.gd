extends "res://tests/provision_hoist_review.gd"
## F6: Space switches geometry tier; N switches night; 1/2/3 views.
## --capture-forest runs and archives comparison captures then exits.
var trees: Array[MultiMeshInstance3D] = []
var near := true
var night := false
var sun: DirectionalLight3D
var environment: Environment
var label: Label
func review() -> void:
	assert(ShipyardPlaytestMode.active())
	ForestTreeMesh.request_assets()
	while not ForestTreeMesh.assets_ready(): await get_tree().process_frame
	output="C:/Users/noahs/Pictures/machinescreenshots/forest-stand-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	var env:=WorldEnvironment.new();environment=Environment.new();env.environment=environment
	environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.36,.43,.5)
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color(.72,.8,.9);environment.ambient_light_energy=.4;add_child(env)
	sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.light_energy=1.2;sun.shadow_enabled=true;add_child(sun)
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(300,300);ground.mesh=plane
	var earth:=StandardMaterial3D.new();earth.albedo_color=Color(.12,.15,.085);earth.roughness=1;ground.material_override=earth;add_child(ground)
	camera=Camera3D.new();camera.fov=55;camera.far=2000;add_child(camera);camera.current=true
	var rng:=RandomNumberGenerator.new();rng.seed=7711
	for species in 4:
		var mmi:=MultiMeshInstance3D.new();var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D
		mm.mesh=ForestTreeMesh.species_mesh(species,true);mm.instance_count=100
		for i in 100:
			var p:=Vector3((i%10)*7-35+rng.randf_range(-2,2),0,(i/10)*7-35+rng.randf_range(-2,2))
			p.x+=float(species%2)*75-37.5;p.z+=float(species/2)*75-37.5
			var basis:=Basis(Vector3.UP,rng.randf_range(0,TAU)).scaled(Vector3.ONE*rng.randf_range(.8,1.3))
			mm.set_instance_transform(i,Transform3D(basis,p))
		mmi.multimesh=mm;add_child(mmi);trees.append(mmi)
	label=Label.new();label.position=Vector2(16,80);add_child(label)
	set_view(0);update_label()
	if OS.get_cmdline_user_args().has("--capture-forest"):
		for detail in [true,false]:
			set_detail(detail)
			for v in 3:
				set_view(v)
				await shot(("near" if near else "far")+"-"+str(v),camera.position,Vector3(-35,6,-35))
		sun.light_energy=.04;environment.ambient_light_energy=.03
		await shot("night-far",camera.position,Vector3(-35,6,-35))
		set_detail(true)
		await shot("night-near",camera.position,Vector3(-35,6,-35))
		get_tree().quit()
func set_view(view:int) -> void:
	camera.position=[Vector3(-15,3,-5),Vector3(40,40,60),Vector3(160,90,260)][view]
	camera.look_at(Vector3(-35,6,-35))
func set_detail(value:bool) -> void:
	near=value
	for i in trees.size():trees[i].multimesh.mesh=ForestTreeMesh.species_mesh(i,near)
	update_label()
func update_label() -> void:
	if label:label.text="Forest review | Space: near/far | N: day/night | 1/2/3: camera\n"+("Branch geometry" if near else "Two-triangle silhouettes")
func _unhandled_key_input(event:InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():return
	if event.keycode==KEY_SPACE:set_detail(not near)
	if event.keycode==KEY_N:
		night=not night;sun.light_energy=.04 if night else 1.2;environment.ambient_light_energy=.03 if night else .4
	if event.keycode>=KEY_1 and event.keycode<=KEY_3:set_view(event.keycode-KEY_1)
