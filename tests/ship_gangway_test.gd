extends Node3D

## Real imported stock, berth/mooring state and gameplay capsule. Quay is test
## apparatus; the ramp and hinged opening are the production Blender parts.
class TestPort extends PortPlot:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

var failures: Array[String] = []
var port: PortPlot
var harbour: HarbourController
var player: CharacterBody3D
var camera: Camera3D
var label: Label
var boat: ImportedDraftVessel
var completed := 0
var capture_prefix := ""

func _ready() -> void:
	assert(ShipyardPlaytestMode.active(), "Use --shipyard-playtest; never load captain saves")
	if DisplayServer.get_name() == "headless":
		push_error("Gangway traversal uses real captured input; run with the renderer enabled")
		get_tree().quit(1)
		return
	GameMenu.set_gameplay_hud_visible(false)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.31,.41,.5)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.8,.85,1)
	env.environment.ambient_light_energy = .65
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45,-35,0)
	sun.shadow_enabled = true
	add_child(sun)
	port = TestPort.new()
	port.port_id = "gangway-review"
	add_child(port)
	harbour = HarbourController.new()
	harbour.setup(port.port_id)
	port.add_child(harbour)
	HarbourRegistry.register(harbour)
	var quay := StaticBody3D.new()
	quay.collision_layer = BoatBody.LAYER_WORLD
	port.add_child(quay)
	add_box(quay,Vector3(20,.5,80),Vector3(0,1.45,0),Color(.22,.24,.25))
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300,300)
	water.mesh = plane
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(.045,.11,.14)
	water.material_override = water_mat
	add_child(water)
	player = preload("res://scenes/shared/player.tscn").instantiate()
	player.position = Vector3(0,1.75,0)
	add_child(player)
	player.set_process_unhandled_input(false)
	player.get_node("BodyMesh").visual.set_local_first_person(false)
	camera = Camera3D.new()
	add_child(camera)
	camera.current = true
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(30,30)
	label.add_theme_font_size_override("font_size",22)
	canvas.add_child(label)
	capture_prefix = "C:/Users/noahs/Pictures/machinescreenshots/gangway-%s" % int(Time.get_unix_time_from_system())
	call_deferred("run")

func add_box(parent: Node3D,size: Vector3,at: Vector3,color: Color) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = at
	parent.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	parent.add_child(mesh)

func wait_frames(count: int) -> void:
	for i in count: await get_tree().physics_frame

func check(ok: bool,message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	label.text = "BOARDING GANGWAY\n"+message+(" — PASS" if ok else " — FAIL")
	if not ok: failures.append(message)

func capture(tag: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("C:/Users/noahs/Pictures/machinescreenshots")
	var path := capture_prefix+"-"+tag+".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ",path)

func run() -> void:
	for option: Dictionary in CompanyContracts.starter_options():
		for side in [-1,1]:
			await test_vessel(str(option.id),side)
	check(completed == CompanyContracts.starter_options().size()*2,"Every starter completed on both sides")
	print("GANGWAY RESULT: ",failures)
	player.queue_free()
	await wait_frames(2)
	get_tree().quit(0 if failures.is_empty() else 1)

func test_vessel(id: String,side: int) -> void:
	port.rotation.y = side*.58 if OS.get_cmdline_user_args().has("--rotated") else 0.0
	var slot := QuayBerthSlot.new()
	slot.setup("gangway-review/"+id+str(side),id,"general",[],100,20,side,Vector3(side,0,0),10)
	port.add_child(slot)
	var posts: Array[Node] = []
	for z in [-12,12]:
		var post := Node3D.new()
		port.add_child(post)
		post.position = Vector3(side*9.6,1.7,z)
		post.add_to_group(MooringComponent.DOCK_MOORING_GROUP)
		slot.add_bollard(post)
		posts.append(post)
	harbour.register_berth(slot)
	boat = VesselSpawn.instantiate_from_record(CompanyService.build_starter_vessel_record(id)) as ImportedDraftVessel
	boat.freeze = true
	boat.transform = port.global_transform * Transform3D(Basis.IDENTITY,Vector3(side*(10+boat.beam_m*.5+2.5),-boat.draft_m,0))
	var saved_draft := JSON.stringify(boat.draft)
	add_child(boat)
	await wait_frames(10)
	var mooring := boat.get_node("ShipGameplay/MooringComponent") as MooringComponent
	mooring.moor_to_posts(posts[0],posts[1])
	check(harbour.plug_ship(slot.berth_id,boat),id+" berth assignment")
	await wait_frames(20)
	var bridge := boat.gangway
	check(bridge.deployed,id+" side "+str(side)+" deployed: "+bridge.status)
	if bridge.deployed:
		var middle := (bridge.ship_end+bridge.shore_end)*.5
		camera.global_position = middle+port.global_basis*Vector3(-side*6,3.2,5.5)
		camera.look_at(middle+Vector3.UP*.6)
		check(absf(port.to_local(bridge.shore_end).x)<10 and absf(bridge.shore_end.y-1.735)<.01,id+" lands on physical quay")
		var toward_ship := (bridge.ship_end-bridge.shore_end).normalized()
		toward_ship.y = 0
		toward_ship = toward_ship.normalized()
		player.global_position = bridge.shore_end-toward_ship*.7+Vector3.UP*.05
		player.velocity = Vector3.ZERO
		player._air_deck = null
		player.rotation = Vector3(0,atan2(-toward_ship.x,-toward_ship.z),0)
		await wait_frames(20)
		check(player.is_on_floor(),id+" starts on quay")
		await capture(id+str(side)+"-deployed")
		await walk_to(bridge.ship_end+toward_ship*.9,toward_ship,id+" board",false)
		check(player.is_on_floor() and absf(boat.to_local(player.global_position).x)<boat.beam_m*.5-.4,id+" passed open bulwark onto deck")
		await capture(id+str(side)+"-aboard")
		await walk_to(bridge.shore_end-toward_ship*.9,-toward_ship,id+" ashore",true)
		check(player.is_on_floor() and absf(port.to_local(player.global_position).x)<9.0,id+" returns to quay without jumping")
		mooring.release_mooring()
		await wait_frames(4)
		check(not bridge.deployed and bridge._walk.collision_layer==0,id+" cast off stows ramp")
		for entry: Dictionary in bridge._gates.values():
			check(entry.part.transform.is_equal_approx(entry.closed),id+" boarding gate closes")
		# No phantom bridge to empty sea or a quay outside physical reach.
		mooring.moor_to_posts(posts[0],posts[1])
		harbour.plug_ship(slot.berth_id,boat)
		var docked := boat.transform
		boat.position += port.global_basis*Vector3(side*12.0,0,0)
		boat._sync_walk_deck_transform()
		await wait_frames(20)
		check(not bridge.deployed,id+" out-of-reach ramp rejected")
		boat.transform = docked
		boat.position.y += 3.0
		boat._sync_walk_deck_transform()
		await wait_frames(20)
		check(not bridge.deployed,id+" excessive slope rejected")
		boat.transform = docked
		boat.position += port.global_basis*Vector3(0,0,100.0)
		boat._sync_walk_deck_transform()
		await wait_frames(20)
		check(not bridge.deployed,id+" no phantom ramp when quay is absent")
		boat.transform = docked
		boat._sync_walk_deck_transform()
		await wait_frames(20)
		check(bridge.deployed,id+" redeploys on return to valid landing")
		check(JSON.stringify(boat.draft)==saved_draft,id+" boarding never modifies saved fit-out")
		if id == "coaster":
			var updated := boat.draft.duplicate(true)
			updated["name"] = "Gangway fixture refresh"
			boat.apply_brick_layout(updated)
			await wait_frames(30)
			check(bridge.deployed,id+" fit-out refresh rebuilds gate and ramp safely")
	mooring.release_mooring()
	harbour.unplug_ship(boat)
	boat.queue_free()
	boat = null
	player.global_position = Vector3(0,1.8,0)
	player.velocity = Vector3.ZERO
	player._air_deck = null
	for post in posts: post.queue_free()
	slot.queue_free()
	await wait_frames(4)
	completed += 1

func walk_to(target: Vector3,direction: Vector3,tag: String,bob: bool) -> void:
	player.rotation.y = atan2(-direction.x,-direction.z)
	Input.action_press("move_forward")
	var start_y := boat.position.y
	var arrived := false
	for frame in 420:
		if bob:
			boat.position.y = start_y+sin(frame*.03)*.08
			boat.rotation.z = sin(frame*.025)*.012
			boat._sync_walk_deck_transform()
		await get_tree().physics_frame
		if (player.global_position-target).dot(direction) >= 0:
			arrived = true
			break
	Input.action_release("move_forward")
	await wait_frames(20)
	check(arrived,tag+" walked across "+("moving" if bob else "stationary")+" bridge")
	print("WALK END ",tag," actual=",player.global_position," target=",target," velocity=",player.velocity)
	boat.position.y = start_y
	boat.rotation.z = 0
	boat._sync_walk_deck_transform()
