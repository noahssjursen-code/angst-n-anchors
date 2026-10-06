extends Node3D

var crane: BulkCrane
var camera: Camera3D
var label: Label

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("263943")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.65;add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-35,0);sun.shadow_enabled=true;add_child(sun)
	crane=BulkCrane.new();crane.model_scale=1;crane.bucket_scale=1;add_child(crane)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=39;add_child(camera)
	camera.position=Vector3(35,25,-38);camera.look_at(Vector3(0,10,-12));camera.make_current()
	var canvas:=CanvasLayer.new();add_child(canvas);label=Label.new();label.position=Vector2(24,70)
	label.add_theme_font_size_override("font_size",20);canvas.add_child(label)
	label.text="BLENDER BULK CRANE / eleven independent models\nExisting slew, luff, hoist and grab controls / imported seated operator"
	for i in 12:await get_tree().process_frame
	assert(crane._assembler is BlenderBulkCraneRig)
	assert(is_equal_approx(crane.get_boom_length_m(),30))
	assert(crane._operator.animator.current_state()==&"seated")
	var right:=crane._shell_right.find_child("CuttingLip",true,false) as Node3D
	var left:=crane._shell_left.find_child("CuttingLip",true,false) as Node3D
	assert(right != null and left != null)
	for scale_value in [.7,1.0,1.5]:
		crane.bucket_scale=scale_value;crane.bucket_open=0
		await get_tree().process_frame
		assert(right.global_position.distance_to(left.global_position)<.001,"Closed jaw cutting lips must meet")
		assert(right.global_position.distance_to(crane.get_bucket_mouth_global())<.001,"Gameplay mouth must match authored lips")
		for opening in [0.0,.25,.5,.75,1.0]:
			crane.bucket_open=opening
			var articulated := crane._assembler as BlenderBulkCraneRig
			for actuator in articulated.grab_actuators:
				assert((actuator.rod as Node3D).to_global(Vector3(0,.5,0)).distance_to((actuator.end as Node3D).global_position)<.001,"Grab piston must stay attached through the full opening")
				assert((actuator.barrel as Node3D).global_position.distance_to((actuator.base as Node3D).global_position)<.001)
		crane.bucket_open=1
		assert(right.global_position.distance_to(left.global_position)>.65*scale_value,"Jaws must open apart")
		assert(crane._bucket.to_local(right.global_position).z>0 and crane._bucket.to_local(left.global_position).z<0,"Jaws must open outward, not pass through each other")
	crane.bucket_scale=1;crane.bucket_open=0
	var start:=crane.get_boom_tip_global()
	crane.slew_degrees=35;crane.boom_angle_deg=48;crane.hoist_length_m=8
	assert(crane.get_boom_tip_global().distance_to(start)>5)
	assert(crane._bucket.global_basis.y.dot(Vector3.UP)>.999,"Grab must stay upright while luffing")
	assert(crane.get_bucket_global().distance_to(crane.get_boom_tip_global()+Vector3.DOWN*crane.hoist_length_m)<.001)
	var mesh:=crane._wire_mesh
	var lower:=mesh.to_global(Vector3(0,-10,0))
	assert(lower.distance_to(crane.get_bucket_global())<.001,"Cable must terminate at hook after length changes")
	var rig:=crane._assembler as BlenderBulkCraneRig
	for angle in [8,32,72]:
		crane.boom_angle_deg=angle
		var feed_end := rig.feed_wire.to_global(Vector3(0,-10,0))
		assert(feed_end.distance_to(crane._boom.to_global(Vector3(0,.75,0)))<.001,"Feed wire must follow boom heel")
		assert(rig.luff_rod.to_global(Vector3(0,4,0)).distance_to(crane._boom.to_global(Vector3(0,-.58,-6)))<.001)
	print("CRANE RIG PASS: eleven imports, seated operator, 30 m boom, scaled jaw seam/mouth, outward jaws, slew/luff/cylinder, feed wires, both grab cylinders across five poses, vertical cable endpoint")
	crane.slew_degrees=0;crane.boom_angle_deg=32;crane.hoist_length_m=10
	var args:=OS.get_cmdline_user_args();var index:=args.find("--capture")
	if index>=0:
		var path:=args[index+1]
		await _capture(path)
		camera.size=5;camera.position=crane.get_bucket_global()+Vector3(4,2,4);camera.look_at(crane.get_bucket_global()+Vector3(0,-.9,0))
		label.text="CLAMSHELL / closed cutting lips meet at the gameplay mouth"
		await _capture(path.get_basename()+"-closed.png")
		crane.bucket_open=1;label.text="CLAMSHELL / independent jaws open around their hinge"
		await _capture(path.get_basename()+"-open.png")
		camera.size=9;camera.position=Vector3(7,6,-8);camera.look_at(Vector3(-.7,3,0));label.text="SLEWING CABIN / separate machinery, service deck and seated operator"
		await _capture(path.get_basename()+"-cabin.png")
		camera.size=9;camera.position=Vector3(-7,7,7);camera.look_at(Vector3(-.7,3.4,0))
		label.text="MACHINERY / hoist drum, feed wires, bearing blocks and boarding ladder"
		await _capture(path.get_basename()+"-service.png")
		crane.queue_free()
		for i in 4:await get_tree().process_frame
		get_tree().quit()

func _capture(path: String) -> void:
	for i in 8:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):get_tree().quit()
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_SPACE:crane.bucket_open=1-crane.bucket_open
		if event.keycode==KEY_LEFT:crane.slew_degrees-=5
		if event.keycode==KEY_RIGHT:crane.slew_degrees+=5
		if event.keycode==KEY_UP:crane.boom_angle_deg+=5
		if event.keycode==KEY_DOWN:crane.boom_angle_deg-=5
		if event.keycode==KEY_PAGEUP:crane.hoist_length_m-=1
		if event.keycode==KEY_PAGEDOWN:crane.hoist_length_m+=1
