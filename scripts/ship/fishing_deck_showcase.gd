extends Node3D

## Production stock and fittings, isolated from captain saves. Left/right cycles cameras.
var camera: Camera3D
var label: Label
var view_index := 0
var views := [
	["Fishing boat / completed stern",Vector3(10,10,14),Vector3(0,2,1)],
	["Insulated catch box",Vector3(-3.2,3.5,4.0),Vector3(-1.15,1.92,1.5)],
	["Stainless preparation bench",Vector3(-3.2,3.1,4.3),Vector3(-1.5,2.05,2.6)],
	["Mooring bitts and roller fairlead",Vector3(.6,2.7,8),Vector3(2.15,1.95,6)],
	["Continuous stern bulwark",Vector3(5,4.7,11),Vector3(0,1.7,6.8)],
	["Gangway / close quay clearance",Vector3(-.8,3.4,8),Vector3(-3.0,1.9,4.5)],
]

func _ready() -> void:
	assert(ShipyardPlaytestMode.active(),"Run isolated: -- --shipyard-playtest")
	GameMenu.set_gameplay_hud_visible(false)
	var environment := WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(.40,.52,.62)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color(.82,.88,1)
	environment.environment.ambient_light_energy=.7
	environment.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	add_child(environment)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-40,0)
	sun.light_energy=1.5
	sun.shadow_enabled=true
	add_child(sun)
	var record:Dictionary={}
	for entry in PrebuiltVesselCatalog.for_sale_entries():
		if entry.prebuilt_id=="fishing_hook_line":
			record=VesselSpawn.normalize_record({"uid":"deck-review","name":entry.display,"hull_id":entry.hull_id,"brick_layout":entry.prebuilt_layout})
	assert(not record.is_empty())
	var boat:=VesselSpawn.instantiate_from_record(record) as ImportedDraftVessel
	boat.freeze=true
	boat.position.y=-boat.draft_m
	add_child(boat)
	if OS.get_cmdline_user_args().has("--crew"):
		var actor:=CharacterVisual.new()
		boat.add_child(actor)
		actor.position=Vector3(.3,boat.depth_m,3.7)
		actor.rotation.y=PI
		views.append(["Captain on the working deck",Vector3(3.0,3.1,8),Vector3(.3,2.25,3.7)])
	var quay:=StaticBody3D.new()
	quay.collision_layer=BoatBody.LAYER_WORLD
	add_child(quay)
	var slab:=BoxMesh.new();slab.size=Vector3(5,2,18)
	var slab_visual:=MeshInstance3D.new();slab_visual.mesh=slab;slab_visual.position=Vector3(-5.75,.7,1)
	var concrete:=StandardMaterial3D.new();concrete.resource_name="Concrete";concrete.albedo_color=Color(.35,.38,.39)
	slab_visual.material_override=concrete;quay.add_child(slab_visual)
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=slab.size
	collider.shape=shape;collider.position=slab_visual.position;quay.add_child(collider)
	var water:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(200,200)
	water.mesh=plane;var paint:=StandardMaterial3D.new();paint.albedo_color=Color(.045,.14,.19);paint.roughness=.3
	water.material_override=paint;add_child(water)
	var berth:=QuayBerthSlot.new()
	berth.setup("review","Review quay","general",[],50,12,1,Vector3.RIGHT,0)
	berth.position=Vector3(-3.25,0,0);add_child(berth)
	boat.gangway.apply_berth_projection(berth,true)
	camera=Camera3D.new();camera.fov=48;camera.far=300;add_child(camera);camera.current=true
	var canvas:=CanvasLayer.new();add_child(canvas)
	label=Label.new();label.position=Vector2(25,22);label.add_theme_font_size_override("font_size",21);canvas.add_child(label)
	show_view()
	if OS.get_cmdline_user_args().has("--capture"):call_deferred("capture_views")

func _unhandled_key_input(event:InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_RIGHT:view_index=(view_index+1)%views.size();show_view()
		if event.keycode==KEY_LEFT:view_index=posmod(view_index-1,views.size());show_view()

func show_view() -> void:
	var view:Array=views[view_index]
	camera.position=view[1];camera.look_at(view[2])
	label.text="%s\nLeft / right: inspect actual boat fittings" % view[0]

func capture_views() -> void:
	var folder:="C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	var stamp:=str(int(Time.get_unix_time_from_system()))
	for index in views.size():
		view_index=index;show_view()
		for frame in 15:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path:="%s/fishing-deck-%s-%s.png" % [folder,stamp,index]
		get_viewport().get_texture().get_image().save_png(path)
		print("CAPTURE ",path)
	get_tree().quit()
