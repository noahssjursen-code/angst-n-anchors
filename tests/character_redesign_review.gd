extends Node3D

var actor: CharacterVisual
var camera: Camera3D
var stamp := str(int(Time.get_unix_time_from_system()))
func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	GameMenu.set_gameplay_hud_visible(false)
	var env := WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(.105,.145,.17)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color(.76,.84,.94)
	env.environment.ambient_light_energy=.6
	env.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-32,-30,0)
	sun.light_energy=1.3
	sun.shadow_enabled=true
	add_child(sun)
	var fill:=OmniLight3D.new()
	fill.position=Vector3(-2,2,-2)
	fill.light_color=Color(.73,.85,1)
	fill.light_energy=1.5
	fill.omni_range=8
	add_child(fill)
	var floor:=MeshInstance3D.new()
	floor.mesh=PlaneMesh.new()
	floor.mesh.size=Vector2(200,200)
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=Color(.16,.20,.22)
	mat.roughness=.9
	floor.material_override=mat
	add_child(floor)
	actor=CharacterVisual.new()
	add_child(actor)
	camera=Camera3D.new()
	add_child(camera)
	camera.current=true
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=2.15
	camera.position=Vector3(2.1,1.8,-4.5)
	camera.look_at(Vector3(0,.95,0))
	await get_tree().create_timer(.7).timeout
	await capture("full")
	camera.size=.54
	camera.position=Vector3(.48,1.71,-1.4)
	camera.look_at(Vector3(0,1.665,0))
	await capture("portrait")
	camera.size=.34
	var hand_target: Vector3 = actor.get_hand_anchor("right").global_position + Vector3(0,-.065,0)
	camera.position=hand_target+Vector3(-.4,.04,-.5)
	camera.look_at(hand_target)
	await capture("hand")
	camera.size=2.15
	camera.position=Vector3(2.1,1.8,4.5)
	camera.look_at(Vector3(0,.95,0))
	await capture("back")
	var look:=CharacterCatalog.appearance_preset("dock_worker")
	look.build=1;look.belly=1;look.frame=1;look.age=80
	actor.apply_appearance(look)
	camera.position=Vector3(2.1,1.8,-4.5)
	camera.look_at(Vector3(0,.95,0))
	await capture("crew-heavy")
	actor.apply_appearance(CharacterAppearance.default_appearance())
	var thigh := actor.skeleton.find_bone("thigh.L")
	actor.animation_player.play("idle",0.0)
	actor.animation_player.seek(0,true)
	actor.animation_player.advance(0)
	var idle_pose := actor.skeleton.get_bone_pose_rotation(thigh)
	for motion in ["walk","run","seated"]:
		actor.animation_player.play(motion,0.0)
		actor.animation_player.speed_scale=0
		actor.animation_player.seek(.17,true)
		actor.animation_player.advance(0)
		actor.skeleton.force_update_all_bone_transforms()
		assert(actor.skeleton.get_bone_pose_rotation(thigh).angle_to(idle_pose)>.05,"Review pose must actually differ from idle: "+motion)
		await capture(motion)
	print("CHARACTER REDESIGN REVIEW complete "+stamp)
	get_tree().quit()
func capture(label:String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path:="C:/Users/noahs/Pictures/machinescreenshots/mariner-rebuild-"+stamp+"-"+label+".png"
	get_viewport().get_texture().get_image().save_png(path)
	print(path)
