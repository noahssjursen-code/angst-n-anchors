extends Node3D

var boat: ImportedDraftVessel
var gear: ShipDriveVisual
var camera: Camera3D
var label: Label
var elapsed := 0.0
var coaster := false

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	coaster = OS.get_cmdline_user_args().has("--coaster")
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("243540")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = .65
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25,-40,0)
	light.light_energy = 2.0
	add_child(light)
	boat = ImportedDraftVessel.new()
	boat.configure({"hull":"hull_32x10" if coaster else "trawler_hull_14m","parts":[],"hull_colors":{"upper":[.075,.25,.29],"lower":[.36,.075,.043]}})
	boat.freeze = true
	boat.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(boat)
	gear = boat.get_node("HullVisual/DriveGear")
	gear.process_mode = Node.PROCESS_MODE_ALWAYS
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.3
	add_child(camera)
	camera.position = Vector3(5,2.6,11)
	camera.look_at(Vector3(0,1.1,7.3))
	if coaster:
		camera.size=6.2;camera.position=Vector3(6,2.5,20);camera.look_at(Vector3(0,1.7,14.7))
	camera.make_current()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(24,70)
	label.add_theme_font_size_override("font_size",20)
	canvas.add_child(label)
	for i in 3: await get_tree().physics_frame
	_verify()
	var args := OS.get_cmdline_user_args()
	var index := args.find("--capture")
	if index >= 0:
		set_process(false)
		var path := args[index+1]
		var drive := boat.get_node("PropulsionComponent") as PropulsionComponent
		var steering := boat.get_node("RudderComponent") as RudderComponent
		drive.throttle = -.25
		steering.rudder_input = .8
		label.text = "BLENDER STERN GEAR / installed on imported draft\nSeparate shaft support, bronze propeller and balanced rudder\nAhead / starboard helm — prototype external transom mounting"
		if coaster:label.text="32 M COASTER / RAISED COUNTER\n1.8 m screw / 2.1 m spade / real shaft and stock pivots\nAhead / starboard helm"
		for i in 20: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png(path) == OK)
		var angle := gear.propeller.rotation.z
		drive.throttle = .25
		steering.rudder_input = -1
		label.text = "ASTERN / PORT HELM\nSame models, driven by propulsion and rudder component state"
		for i in 20: await get_tree().process_frame
		assert(not is_equal_approx(angle, gear.propeller.rotation.z))
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png(path.get_basename()+"-reverse.png") == OK)
		if coaster:
			camera.size=5;camera.position=Vector3(6,1.7,15.2);camera.look_at(Vector3(0,1.7,14.3))
			label.visible=false
			for i in 12: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(path.get_basename()+"-side.png")
		print("STERN GEAR PASS: local/remote state, dry fuel, reload, clearance and renders")
		boat.queue_free()
		for i in 4:await get_tree().process_frame
		get_tree().quit()

func _verify() -> void:
	var drive := boat.get_node("PropulsionComponent") as PropulsionComponent
	var steering := boat.get_node("RudderComponent") as RudderComponent
	var original_force_point := drive.stern_offset
	var original_rudder_point := steering.rudder_position
	drive.throttle = -.5
	steering.rudder_input = 1
	gear._process(.01)
	assert(gear.signed_rpm == gear.max_rpm*.5 and is_equal_approx(gear.rudder.rotation.y, deg_to_rad(28)))
	drive.throttle = .5
	gear._process(.01)
	assert(gear.signed_rpm == -gear.max_rpm*.5)
	drive.throttle = 0
	gear._process(.01)
	assert(gear.signed_rpm == 0)
	boat.fuel_l = 0
	drive.throttle = -1
	drive.delivered_thrust_n = 1234
	drive._physics_process(.01)
	gear._process(.01)
	assert(drive.delivered_thrust_n == 0 and gear.signed_rpm == 0)
	boat.fuel_l = 600
	gear.local_boat = null
	var sequence := gear.revision+1
	assert(gear.apply_snapshot({"throttle":.5,"steering":-1,"powered":true},sequence))
	assert(not gear.apply_snapshot({"throttle":1,"steering":0,"powered":true},sequence))
	assert(not gear.apply_snapshot({"throttle":NAN,"steering":0,"powered":true},sequence+1))
	assert(not gear.apply_snapshot({"throttle":0,"steering":0,"powered":1},sequence+1))
	gear._process(.01)
	assert(gear.signed_rpm == gear.max_rpm*.5 and is_equal_approx(gear.rudder.rotation.y,deg_to_rad(-28)))
	# Actual imported vertices, swept through one full prop revolution and both
	# steering locks. All moving surfaces must stay aft of the closed transom.
	var prop_max := -INF
	for angle in range(0,360,15):
		gear.propeller.rotation.z = deg_to_rad(angle)
		var points:=_points(gear.propeller)
		for point in points:
			if not coaster:assert(point.z > 7.2, "Propeller intersects closed stern")
			prop_max = maxf(prop_max,point.z)
		if coaster:_verify_below_counter(points)
	for angle in range(-28,29,2):
		gear.rudder.rotation.y = deg_to_rad(angle)
		for point in _points(gear.rudder):
			assert(point.z > prop_max+.10, "Rudder enters propeller swept envelope")
		if coaster:_verify_below_counter(_points(gear.rudder,"Tapered balanced spade"))
	assert(drive.stern_offset == original_force_point and steering.rudder_position == original_rudder_point)
	var restored := ImportedDraftVessel.new()
	restored.configure(JSON.parse_string(JSON.stringify(boat.draft)))
	assert(restored.find_children("DriveGear","",true,false).size() == 1)
	assert(restored.draft == boat.draft)
	# configure() creates this helper off-tree; _exit_tree does not run here.
	restored.assembler.free()
	restored.free()
	gear.bind_local(boat)
	print("Stern gear geometry/state verification passed; propeller aft extent ",prop_max)

func _verify_below_counter(points:Array[Vector3]) -> void:
	# Sample actual imported vertices against player-facing hull triangles.
	assert(not points.is_empty(),"Clearance probes require actual imported mesh vertices")
	for i in range(0,points.size(),64):
		var point:=points[i]
		var ray:=PhysicsRayQueryParameters3D.create(Vector3(point.x,-1,point.z),Vector3(point.x,5,point.z),BoatBody.LAYER_BOAT_WALK)
		var hit:=get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			assert(point.y+.06<hit.position.y,"Moving blade intersects raised counter: %s / hull %s"%[point,hit.position])

func _points(root: Node3D, only_name:String="") -> Array[Vector3]:
	var points: Array[Vector3] = []
	for mesh: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		if not only_name.is_empty() and not str(mesh.name).begins_with(only_name):continue
		for surface in mesh.mesh.get_surface_count():
			for vertex in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				points.append(boat.global_transform.affine_inverse()*mesh.global_transform*vertex)
	return points

func _process(delta: float) -> void:
	elapsed += delta
	var drive := boat.get_node("PropulsionComponent") as PropulsionComponent
	var steering := boat.get_node("RudderComponent") as RudderComponent
	drive.throttle = -.25 if fmod(elapsed,12) < 6 else .25
	steering.rudder_input = sin(elapsed*.6)
	label.text = "STERN GEAR / live component-driven inspection\nShaft %.0f RPM | Rudder %.1f° | reverses every six seconds\nEsc: close" % [gear.signed_rpm,gear.steering_degrees]

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): get_tree().quit()
