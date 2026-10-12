extends Node3D
## F6 inspect scene: real boat, player, deck interactions and catch UI, bounded water.
class Ground extends WorldLayout:
	func sample_height(p:Vector2)->float:return -35+sin(p.x/120)*7+WorldTerrainStreamer.TERRAIN_SINK_M
	func sample_signed_distance(_p:Vector2)->float:return 500
@export var harpe_preview:=false
var boat:ImportedDraftVessel
var station:RodFishingStation
var player:CharacterBody3D
var camera:Camera3D
var school:Dictionary
var _hand_check:RefCounted
func _ready()->void:
	assert(ShipyardPlaytestMode.active())
	var layout:=Ground.new();layout.seed=717
	WorldClock.set_game_hours_elapsed(0)
	FishingField.initialize(717);FishingField.configure_habitat(layout)
	for z in range(-1200,1200,160):
		for x in range(-1200,1200,160):
			for candidate:Dictionary in FishingField.habitat.schools_near(Vector2(x,z),0,100):
				if candidate.species=="cod":school=candidate;break
			if not school.is_empty():break
		if not school.is_empty():break
	assert(not school.is_empty())
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("7997a6")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.55;add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-35,0);sun.light_energy=1.3;add_child(sun)
	boat=ImportedDraftVessel.new();boat.configure(JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/vessels/prebuilt/fishing_hook_line.json")).brick_layout)
	boat.freeze=true;boat.position=Vector3(school.position.x-25,0,school.position.y+2.5);add_child(boat)
	boat.place_at_waterline(WaveSurface.WATER_LEVEL);boat.freeze=true;boat.get_node("BoatCamera").set_process(false)
	PlayerVessel.mark_player_ship(boat)
	var water:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(2000,2000);water.mesh=plane
	var material:=StandardMaterial3D.new();material.albedo_color=Color("225969");material.roughness=.28;water.material_override=material
	water.position=Vector3(school.position.x,WaveSurface.WATER_LEVEL-.1,school.position.y);add_child(water)
	if OS.get_cmdline_user_args().has("--ocean-line-review"):
		# Real near-water transmission/depth shader, with deterministic calm FFT inputs.
		var maps:=Texture2DArray.new()
		var layers:Array[Image]=[]
		for i in 4:
			var image:=Image.create(4,4,false,Image.FORMAT_RGBAF)
			image.fill(Color(0,0,0,0));layers.append(image)
		assert(maps.create_from_images(layers)==OK)
		var ocean:=ShaderMaterial.new()
		ocean.shader=preload("res://resources/shaders/ocean_waves.gdshader")
		ocean.set_shader_parameter("displacement_map",maps)
		ocean.set_shader_parameter("slope_map",maps)
		ocean.set_shader_parameter("wave_intensity",0.0)
		ocean.set_shader_parameter("water_level",WaveSurface.WATER_LEVEL)
		water.material_override=ocean

	player=preload("res://scenes/shared/player.tscn").instantiate();add_child(player)
	if OS.get_cmdline_user_args().has("--hands-heavy"):
		var appearance:=CharacterAppearance.default_appearance()
		appearance.build=1;appearance.belly=1;appearance.frame=1;appearance.age=80
		player.get_node("BodyMesh").visual.apply_appearance(appearance)
	station=boat.get_node("RodFishingStation")
	player.global_position=station.authored_station.global_position+Vector3(-1.1,.1,0)
	camera=player.get_node("Camera3D");camera.current=true
	GameMenu.set_gameplay_hud_visible(true);GameMenu.hide_loading()
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	if harpe_preview and not OS.get_cmdline_user_args().has("--harpe-review"):_prepare_harpe.call_deferred()
	elif OS.get_cmdline_user_args().has("--harpe-review"):_harpe_review.call_deferred(water)
	elif OS.get_cmdline_user_args().has("--hands-test"):
		_hand_check=preload("res://tests/rod_hand_contact_check.gd").new();_hand_check.run.call_deferred(self)
	elif OS.get_cmdline_user_args().has("--schools-review"):_school_review.call_deferred(water)
	elif OS.get_cmdline_user_args().has("--school-gizmos-review"):_school_gizmos_review.call_deferred(water)
	elif OS.get_cmdline_user_args().has("--hands-close-review"):_hands_close_review.call_deferred()
	elif OS.get_cmdline_user_args().has("--hands-review"):_hand_review.call_deferred()
	elif OS.get_cmdline_user_args().has("--capture"):review.call_deferred()

func aim_at(target:Vector3)->void:
	var controls:=player.get_node("PlayerCamera") as PlayerCamera
	controls._look_yaw=atan2(-(target.x-player.global_position.x),-(target.z-player.global_position.z))
	player.rotation.y=controls._look_yaw
	camera.global_position=player.global_position+Vector3(0,1.6,0)
	camera.look_at(target)
	controls._fp_pitch=camera.rotation.x

func press_f()->void:
	var event:=InputEventAction.new();event.action="interact";event.pressed=true;get_viewport().push_input(event,true)
	event=InputEventAction.new();event.action="interact";event.pressed=false;get_viewport().push_input(event,true)

func capture(label:String)->void:
	if OS.get_cmdline_user_args().has("--hands-heavy"):label="heavy-"+label
	for i in 8:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var directory:="C:/Users/noahs/Pictures/machinescreenshots";DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("fishing-%s-%d-%d.png"%[label,Time.get_unix_time_from_system(),Time.get_ticks_usec()])
	get_viewport().get_texture().get_image().save_png(path);print("CAPTURE ",path)

func review()->void:
	for i in 90:await get_tree().physics_frame
	assert(player.is_on_floor(),"Must start on real deck")
	var before:=player.global_position
	Input.action_press("move_back")
	for i in 20:await get_tree().physics_frame
	Input.action_release("move_back")
	assert(player.global_position.distance_to(before)>.15,"Exercise actual deck movement")
	player.global_position=station.authored_station.global_position+Vector3(-1.1,.1,0)
	for i in 12:await get_tree().physics_frame
	aim_at(station._interaction.global_position)
	assert(station.can_interact(),"Rod holder must be reachable")
	press_f();assert(station.working and is_instance_valid(station._carried))
	aim_at(camera.global_position+Vector3(20,-2,0))
	await capture("rod-ready")
	Input.action_press("fishing_rod")
	for i in 45:await get_tree().physics_frame
	assert(station.session.phase=="charging" and station.session.charge>.4,"Charge state: %s %.2f working=%s"%[station.session.phase,station.session.charge,station.working])
	Input.action_release("fishing_rod")
	for i in 3:await get_tree().physics_frame
	assert(station.session.phase=="casting","Releasing mouse casts")
	var target:=station._cast_at
	print("CAST offset ",target-school.position," radius ",school.radius_m)
	camera.rotate_y(.4)
	Input.action_press("move_back")
	for i in 12:await get_tree().physics_frame
	Input.action_release("move_back")
	assert(station._cast_at==target,"Moving/looking must not drag cast point around")
	aim_at(Vector3(target.x,WaveSurface.WATER_LEVEL,target.y))
	while station.session.phase=="casting":await get_tree().physics_frame
	for i in 30:await get_tree().physics_frame
	assert(station.session.depth_m==0,"No input must hold tackle at surface")
	Input.action_press("fishing_lower")
	var deadline:=Time.get_ticks_msec()+20000
	var started:=Time.get_ticks_msec()
	var ui_steps:=0
	var rendered_frames:=0
	var last_depth:=-1.0
	while station.session.depth_m<12 and Time.get_ticks_msec()<deadline:
		await RenderingServer.frame_post_draw
		rendered_frames+=1
		var shown:=float(GameMenu._hud._fishing.data.get("line_m",-1))
		if shown!=last_depth:ui_steps+=1;last_depth=shown
	var refresh_rate:=float(ui_steps)*1000/maxf(1,Time.get_ticks_msec()-started)
	print("FISHING HUD distinct depth updates/sec: ",refresh_rate)
	var frame_rate:=float(rendered_frames)*1000/maxf(1,Time.get_ticks_msec()-started)
	assert(refresh_rate>minf(float(Engine.physics_ticks_per_second),frame_rate)*.75,"Fishing HUD must follow physics/render cadence, not a 10 Hz timer")
	Input.action_release("fishing_lower")
	var held_depth:=station.session.depth_m
	for i in 30:await get_tree().physics_frame
	assert(absf(station.session.depth_m-held_depth)<.1,"Release RMB holds depth")
	await capture("line-depth")
	var camera_control:=player.get_node("PlayerCamera") as PlayerCamera
	camera_control._toggle_mode()
	for i in 15:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(station._carried.global_position.distance_to(player.global_position)<2,"Third-person rod belongs to player, not orbit camera")
	var vertices:PackedVector3Array=station._line.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert(((vertices[0]+vertices[1])*.5).distance_to(station._tip.global_position)<.002,"Line starts at current rendered rod tip")
	await capture("third-person-line")
	camera_control._orbit_yaw+=.5
	for i in 15:await get_tree().process_frame
	assert(station._carried.global_position.distance_to(player.global_position)<2,"Orbit must not pull rod away from person")
	camera_control._toggle_mode()
	aim_at(Vector3(target.x,WaveSurface.WATER_LEVEL,target.y))

	# The wider attraction radius can bring a midwater fish during the camera
	# checks. Give line to decline that bite before testing manual retrieval.
	if station.session.phase=="bite":
		Input.action_press("fishing_lower")
		for i in 2:await get_tree().physics_frame
		Input.action_release("fishing_lower")
	held_depth=station.session.depth_m
	Input.action_press("fishing_reel")
	for i in 12:await get_tree().physics_frame
	Input.action_release("fishing_reel")
	assert(station.session.depth_m<held_depth-.8,"LMB manually retrieves")
	var actual:Dictionary={}
	for candidate:Dictionary in FishingField.habitat.schools_near(station._cast_at,WorldClock.get_game_hours_elapsed(),0):
		if candidate.species=="cod":actual=candidate;break
	assert(not actual.is_empty(),"Cast must reach the physical cod ground")
	Input.action_press("fishing_lower")
	deadline=Time.get_ticks_msec()+20000
	while station.session.depth_m<float(actual.depth_m) and Time.get_ticks_msec()<deadline:await get_tree().physics_frame
	Input.action_release("fishing_lower")
	deadline=Time.get_ticks_msec()+15000
	while station.session.phase!="bite" and Time.get_ticks_msec()<deadline:await get_tree().physics_frame
	assert(station.session.phase=="bite","Manual payout must discover fish at this depth")
	await capture("bite")
	Input.action_press("fishing_rod")
	for i in 2:await get_tree().physics_frame
	Input.action_release("fishing_rod")
	assert(station.session.phase=="fighting")
	deadline=Time.get_ticks_msec()+13000
	var photographed:=false
	var close_photographed:=false
	while station.session.phase=="fighting" and Time.get_ticks_msec()<deadline:
		if station.session.control<station.session.fish_position:
			Input.action_press("fishing_reel");Input.action_release("fishing_lower")
		else:
			Input.action_release("fishing_reel");Input.action_press("fishing_lower")
		if is_instance_valid(station._fish) and station._fish.visible:
			var mouth:=station._fish.find_child("MouthHook",true,false) as Node3D
			var line_vertices:PackedVector3Array=station._line.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var endpoint:=station._line.to_global((line_vertices[-1]+line_vertices[-2])*.5)
			assert(mouth.global_position.distance_to(endpoint)<.002,"Rendered line must end at the fish's mouth")
			assert(station._fish.global_basis.x.normalized().dot((station._tip.global_position-mouth.global_position).normalized())>.999,"Fish must face the rod while reeled")
		if station.session.progress>.65 and not photographed:
			photographed=true;await capture("fish-on")
		if station.session.progress>.94 and not close_photographed:
			close_photographed=true
			aim_at(station._fish.global_position)
			await capture("mouth-attachment")
		await get_tree().physics_frame
	Input.action_release("fishing_reel");Input.action_release("fishing_lower")
	assert(station.session.phase=="landed","Successful fight must show landed fish")
	assert(is_instance_valid(station._fish) and station._fish.visible,"Landed fish must have a visible model")
	var hold:=boat.get_catch_holds()[0] as CatchHoldComponent
	assert(hold.state.lots.size()==1 and hold.state.lots[0].specimen)
	await capture("landed")
	# Recover/stow with real controls, then inspect the authored crate using F.
	player.global_position=station.authored_station.global_position+Vector3(-1.1,.1,0);aim_at(station._interaction.global_position)
	press_f();assert(not station.working)
	var reachable:=false
	for i in 16:
		var a:=TAU*float(i)/16
		player.global_position=hold._inspect_area.global_position+Vector3(cos(a)*1.8,-.5,sin(a)*1.8)
		aim_at(hold._inspect_area.global_position)
		if hold.can_inspect():reachable=true;break
	assert(reachable,"Deck crate must be physically inspectable")
	press_f();await get_tree().process_frame
	assert(GameMenu._screen==GameMenu.Screen.CATCH and GameMenu._catch_library.visible)
	assert(GameMenu._catch_library.data.items.size()==1 and GameMenu._catch_library._preview.fish!=null)
	assert(GameMenu._catch_library._summary.text.contains("NOK"))
	await capture("crate")
	GameMenu._set_screen(GameMenu.Screen.NONE)
	assert(not GameMenu.is_modal_open() and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED)
	var saved:=CatchHoldState.from_dict(hold.state.to_dict());assert(saved.lots[0].lot_id==hold.state.lots[0].lot_id)
	var mass:=hold.state.total_mass_kg();var price:int=FishingLandingService.quote([hold.state]).value_marks
	var bank:=ShoreRswTankBank.new();add_child(bank);bank.hide()
	var pump:=FishLandingPump.new();add_child(pump);pump.hide();pump.bind_receiver(bank);pump.connect_seconds=.01;pump.flush_seconds=.01;pump.pump_rate_kg_s=.5
	# A whole fish cannot be cut to fit the receiver. The pump must finish, not stall.
	bank._inventory.capacity_kg=mass*.8
	assert(pump.start_unload(boat));pump.set_process(false)
	for i in 5:
		pump._process(.1)
		if pump.state_label()==FishLandingPump.STATE_COMPLETE:break
	assert(pump.state_label()==FishLandingPump.STATE_COMPLETE and bank.total_mass_kg()==0 and is_equal_approx(hold.state.total_mass_kg(),mass))
	bank._inventory.capacity_kg=1000
	assert(pump.start_unload(boat));pump.set_process(false)
	for i in 2000:
		pump._process(.1)
		if pump.state_label()==FishLandingPump.STATE_COMPLETE:break
	assert(absf(bank.total_mass_kg()-mass)<.001 and hold.state.is_empty())
	assert(pump.landed_value_marks()==price)
	print("ROD LIVE PASS: real deck movement/look, F pickup, hold/release cast, world-anchored line, RMB payout/LMB reel/release hold, bite, fight, fish model/reveal, indivisible crate record, F library/3D/NOK, save roundtrip, slow pump transfer/value")
	get_tree().quit()

func _school_review(water:Node3D)->void:
	for i in 60:await get_tree().process_frame
	water.hide();player.set_process(false);player.set_physics_process(false)
	GameMenu.set_gameplay_hud_visible(false)
	var p:Vector3=FishingField.habitat.members(school,WorldClock.get_game_hours_elapsed())[0].position
	camera.global_position=p+Vector3(6,4,9);camera.look_at(p)
	for i in 60:await get_tree().process_frame
	await capture("school-ocean-disabled")
	var rendered:=0
	for node in boat.get_children():
		if node.get_script()==preload("res://scripts/ship/ship_sounder.gd"):
			assert(is_instance_valid(node._schools))
			rendered=node._schools._tracks.size()
	assert(rendered>0 and rendered<=192,"Shared population must actually be rendered within budget")
	print("SCHOOL VISUAL PASS: production habitat individuals with water hidden")
	get_tree().quit()

func _school_gizmos_review(water:Node3D)->void:
	for i in 60:await get_tree().process_frame
	player.set_process(false);player.set_physics_process(false)
	player.get_node("PlayerCamera").set_process(false)
	GameMenu.set_gameplay_hud_visible(false)
	DebugHud.set_gizmo_layer_enabled(WorldGizmos.LAYER_FISHING,true)
	var center:=Vector3(school.position.x,WaveSurface.WATER_LEVEL-float(school.depth_m),school.position.y)
	camera.global_position=center+Vector3(130,160,180);camera.look_at(center)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=260
	var panel:=CanvasLayer.new();add_child(panel)
	var instrument:=FishingInstrument.new();panel.add_child(instrument);instrument.position=Vector2(18,18)
	var history:Array=[]
	for i in 60:history.append(FishingField.habitat.ping(school.position+Vector2(60-i,0),WorldClock.get_game_hours_elapsed()))
	instrument.present({"sonar_view":true,"sounder":true,"history":history})
	for i in 60:await get_tree().process_frame
	await capture("school-catch-area-water-on")
	water.hide()
	await capture("school-catch-area-water-off")
	DebugHud.set_gizmo_layer_enabled(WorldGizmos.LAYER_FISHING,false)
	print("SCHOOL GIZMO REVIEW PASS: production volumes and sonar with water on / off")
	get_tree().quit()

func _hand_review()->void:
	for i in 90:await get_tree().physics_frame
	aim_at(station._interaction.global_position)
	press_f();assert(station.working)
	aim_at(camera.global_position+Vector3(20,-2,0))
	await capture("hand-grip-first-person")
	var controller:=player.get_node("PlayerCamera") as PlayerCamera
	controller._toggle_mode();player.set_process(false);player.set_physics_process(false)
	controller._orbit_yaw+=2.2;controller.tp_distance=1.7;controller._update_third_person()
	for i in 60:await get_tree().process_frame
	await capture("hand-grip-third-person")
	station.session.recover();station.working=false;station._carry(false)
	player.set_process(true);player.set_physics_process(true)
	controller._toggle_mode();controller._fp_pitch=-1.15
	for i in 30:await get_tree().process_frame
	await capture("hands-neutral-first-person")
	print("HAND VISUAL REVIEW COMPLETE")
	get_tree().quit()

var _review_hand_poses:Dictionary={}
func _record_review_hands(skeleton:Skeleton3D)->void:
	for side in ["L","R"]:
		_review_hand_poses[side]=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("hand."+side))

func _hands_close_review()->void:
	for i in 90:await get_tree().physics_frame
	GameMenu.set_gameplay_hud_visible(false)
	var controller:=player.get_node("PlayerCamera") as PlayerCamera
	controller._toggle_mode()
	player.set_process(false);player.set_physics_process(false)
	# Isolate the actual skinned hands and equipment from occluding trousers/sleeves.
	# This changes only the review camera's layer, not the production character.
	var review_light:=OmniLight3D.new()
	add_child(review_light);review_light.light_cull_mask=2;review_light.layers=2
	review_light.omni_range=3;review_light.light_energy=.20
	var fill_light:=OmniLight3D.new()
	add_child(fill_light);fill_light.light_cull_mask=2;fill_light.layers=2
	fill_light.omni_range=3;fill_light.light_energy=.015
	var visual:CharacterVisual=player.get_node("BodyMesh").visual
	var hands:=visual.get_part("Hands") as MeshInstance3D
	var isolated:Dictionary={"L":_review_hand_only(hands,true),"R":_review_hand_only(hands,false)}
	for env:WorldEnvironment in find_children("*","WorldEnvironment",false,false):
		env.environment.background_color=Color("263842");env.environment.ambient_light_energy=.35
	for mesh:MeshInstance3D in station._rod_root.find_children("*","MeshInstance3D",true,false):mesh.layers=mesh.layers|2
	var skeleton:=visual.skeleton
	skeleton.skeleton_updated.connect(_record_review_hands.bind(skeleton))
	for holding in [false,true]:
		if holding:
			station.working=true;station._carry(true)
		for i in 30:await get_tree().process_frame
		for side in ["L","R"]:
			isolated.L.visible=side=="L";isolated.R.visible=side=="R"
			await RenderingServer.frame_post_draw
			assert(_review_hand_poses.has(side))
			var pose:Transform3D=_review_hand_poses[side]
			var center:=pose.origin+pose.basis.y*.075
			for view_sign in [-1,1]:
				var review_camera:=Camera3D.new();review_camera.name="HandCamera_%s_%s_%s"%[side,holding,view_sign]
				add_child(review_camera);review_camera.current=true;review_camera.near=.01;review_camera.cull_mask=2
				review_camera.projection=Camera3D.PROJECTION_ORTHOGONAL;review_camera.size=.27
				review_camera.global_position=center+pose.basis.z*view_sign*.45+pose.basis.x*.18
				if holding and side=="L" and view_sign<0:
					review_camera.global_position=center-pose.basis.z*.35-pose.basis.y*.5+pose.basis.x*.12
				review_camera.look_at(center,pose.basis.y*-1)
				review_light.global_position=center+pose.basis.z*view_sign*.25-pose.basis.x*.20-pose.basis.y*.15
				fill_light.global_position=center+pose.basis.x*.20
				await capture("close-%s-%s-%s"%["grip" if holding else "neutral",side,"palm" if view_sign<0 else "back"])
	print("INDEPENDENT HAND CAMERAS COMPLETE")
	get_tree().quit()

func _review_hand_only(source:MeshInstance3D,positive_x:bool)->MeshInstance3D:
	# Keep the production vertices, skin, weights, materials and morphs verbatim;
	# only omit the other hand's triangles from this camera's diagnostic layer.
	var mesh:=ArrayMesh.new();mesh.blend_shape_mode=source.mesh.blend_shape_mode
	for key in source.mesh.get_blend_shape_count():mesh.add_blend_shape(source.mesh.get_blend_shape_name(key))
	for surface in source.mesh.get_surface_count():
		var arrays:=source.mesh.surface_get_arrays(surface)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var selected:=PackedInt32Array()
		for i in range(0,indices.size(),3):
			if (vertices[indices[i]].x>0)==positive_x:selected.append_array(indices.slice(i,i+3))
		arrays[Mesh.ARRAY_INDEX]=selected
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,source.mesh.surface_get_blend_shape_arrays(surface))
		mesh.surface_set_material(surface,source.get_active_material(surface))
	var result:=MeshInstance3D.new();source.get_parent().add_child(result)
	result.mesh=mesh;result.skin=source.skin;result.skeleton=source.skeleton;result.transform=source.transform;result.layers=2
	for key in mesh.get_blend_shape_count():result.set_blend_shape_value(key,source.get_blend_shape_value(key))
	return result


func _harpe_review(water:Node3D)->void:
	for i in 90:await get_tree().physics_frame
	_prepare_harpe()
	var record:=PlayerSession.data.get_active_vessel_record()
	aim_at(station._interaction.global_position)
	await capture("harpe-mounted")
	press_f();assert(station.working)
	assert(not PlayerSession.equip_ship_fishing_item({"vessel_id":record.uid,"item_id":"fishing_rod"}).ok,"Cannot swap held gear")
	aim_at(camera.global_position+Vector3(20,-2,0))
	await capture("harpe-held")
	# Move to the starboard rail, then lower vertically using the production input.
	player.global_position.x=boat.global_position.x+2.15
	aim_at(camera.global_position+Vector3(20,-2,0))
	for i in 12:await get_tree().physics_frame
	Input.action_press("fishing_lower")
	for i in 12:await get_tree().physics_frame
	assert(station.session.phase=="fishing","Hooks drop vertically over the rail")
	var deadline:=Time.get_ticks_msec()+25000
	while station.session.depth_m<float(school.depth_m)+2 and Time.get_ticks_msec()<deadline:await get_tree().physics_frame
	Input.action_release("fishing_lower")
	deadline=Time.get_ticks_msec()+14000
	while station.session.catches.size()<6 and Time.get_ticks_msec()<deadline:await get_tree().physics_frame
	assert(station.session.catches.size()==6,"Live harpe fills six different hooks")
	await capture("harpe-six-hooks-ui")
	# Separate underwater camera shows the six actual specimens and their snoods.
	station.set_physics_process(false)
	var review:=Camera3D.new();add_child(review)
	var at:=Vector3(station._cast_at.x,WaveSurface.WATER_LEVEL-station.session.depth_m+2,station._cast_at.y)
	review.position=at+Vector3(2.4,.4,3.2);review.look_at(at);review.current=true;water.hide()
	await capture("harpe-six-fish-underwater")
	camera.current=true;review.queue_free();water.show();station.set_physics_process(true)
	Input.action_press("fishing_reel")
	for i in 2:await get_tree().physics_frame
	Input.action_release("fishing_reel")
	assert(station.session.phase=="fighting")
	deadline=Time.get_ticks_msec()+14000
	while station.session.phase=="fighting" and Time.get_ticks_msec()<deadline:
		if station.session.control<station.session.fish_position:
			Input.action_press("fishing_reel");Input.action_release("fishing_lower")
		else:
			Input.action_release("fishing_reel");Input.action_press("fishing_lower")
		await get_tree().physics_frame
	Input.action_release("fishing_reel");Input.action_release("fishing_lower")
	assert(station.session.phase=="landed")
	var hold:=boat.get_catch_holds()[0] as CatchHoldComponent
	assert(hold.state.lots.size()==6,"Six independent fish stored in crate")
	await capture("harpe-six-landed")
	station.session.recover();station.working=false;station._carry(false)
	assert(PlayerSession.equip_ship_fishing_item({"vessel_id":record.uid,"item_id":"fishing_rod"}).ok)
	assert(station._stored_rod.visible and not station._harpe_model.visible)
	station.working=true;station._carry(true)
	for i in 12:await get_tree().physics_frame
	await capture("heavy-sea-rod-held")
	Input.action_press("fishing_lower")
	for i in 45:await get_tree().physics_frame
	Input.action_release("fishing_lower")
	assert(station.session.phase=="fishing" and station.session.depth_m>2,"Heavy pilk lowers directly")
	station.set_physics_process(false);station.set_process(false)
	var detail:=Camera3D.new();add_child(detail)
	detail.global_position=station._tackle.global_position+Vector3(.22,.04,.35)
	detail.look_at(station._tackle.global_position-Vector3.UP*.12);detail.current=true
	water.hide();await capture("heavy-pilk-detail");water.show()
	camera.current=true;detail.queue_free()
	station.set_physics_process(true);station.set_process(true)
	station.session.recover();station.working=false;station._carry(false)
	assert(PlayerSession.equip_ship_fishing_item({"vessel_id":record.uid,"item_id":"harpe"}).ok)
	var loaded:=PlayerData.from_dict(JSON.parse_string(JSON.stringify(PlayerSession.data.to_dict())))
	assert(loaded.get_active_vessel_record().equipped_fishing_item=="harpe")
	print("HARPE LIVE PASS: purchased, equipped, mount changes, held swap blocked, vertical drop, six unique fish, haul, six crate lots, rod swap and saved selection")
	get_tree().quit()


func _prepare_harpe()->void:
	PlayerSession.begin_new_captain("Harpe Review",CharacterAppearance.default_appearance(),"test-port","harpe-review",717,"Review Fishing",Color.WHITE,"")
	var record:=CompanyService.build_starter_vessel_record("fishing")
	record.uid="harpe-review-boat";record.brick_layout=boat.draft.duplicate(true)
	PlayerSession.data.upsert_owned_vessel(record);PlayerSession.data.set_active_vessel(record)
	boat.set_meta("vessel_uid",record.uid)
	assert(PlayerSession.purchase_ship_equipment({"request_id":"review-harpe","vessel_id":record.uid,"item_id":"harpe"}).ok)
	assert(PlayerSession.equip_ship_fishing_item({"vessel_id":record.uid,"item_id":"harpe"}).ok)
	assert(station.equipment_id=="harpe" and not station._stored_rod.visible)
