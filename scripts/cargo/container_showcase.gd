extends Node3D
## F6: exact cargo models; 1/2/3 sizes, O inspects independent door pivots.
var cargo: ContainerNode
var camera: Camera3D
var label: Label

func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("263943")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .65
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42,35,0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	add_child(camera)
	var ui := CanvasLayer.new()
	add_child(ui)
	label = Label.new()
	label.position = Vector2(95,24)
	label.add_theme_font_size_override("font_size",24)
	ui.add_child(label)
	await display("20ft")
	var args := OS.get_cmdline_user_args()
	if args.has("--verify"): await verify()
	var i := args.find("--capture-dir")
	if i >= 0:
		for kind in ["20ft","40ft","legacy_4m"]:
			await display(kind)
			await capture(args[i+1].path_join("container-%s.png" % kind))
		await display("20ft")
		camera.size = 4.3
		camera.position = Vector3(3,3,6)
		camera.look_at(Vector3(0,1.2,2.9))
		await capture(args[i+1].path_join("container-doors.png"))
		open_doors()
		await capture(args[i+1].path_join("container-open.png"))
		await display("20ft")
		cargo.notify_grabbed()
		await capture(args[i+1].path_join("container-lifting.png"))
		cargo.queue_free()
		for frame in 3: await get_tree().process_frame
		get_tree().quit()

func display(kind: String) -> void:
	if is_instance_valid(cargo): cargo.queue_free()
	cargo = ContainerNode.new()
	add_child(cargo)
	var unit := ContainerUnit.create("showcase", "provisions",3200,kind)
	unit.paint_variant = 1 if kind == "40ft" else 0
	cargo.setup(unit,true)
	var dimensions := unit.dimensions_m()
	camera.position = Vector3(dimensions.z*.7,dimensions.z*.56,dimensions.z*.85)
	camera.size = dimensions.z*1.06
	camera.look_at(Vector3(0,1.2,0))
	camera.make_current()
	label.text = "%s CARGO CONTAINER\n%.3f × %.3f × %.3f m   ·   1/2/3 sizes · O doors" % [kind.to_upper(),dimensions.z,dimensions.x,dimensions.y]
	for frame in 6: await get_tree().process_frame

func open_doors() -> void:
	for spec in [["DoorPortPivot",-105.0],["DoorStarboardPivot",105.0]]:
		var pivot := cargo.find_child(spec[0],true,false) as Node3D
		assert(pivot != null)
		pivot.rotation.y = deg_to_rad(spec[1])

func capture(path: String) -> void:
	for frame in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)

func verify() -> void:
	for kind in ["20ft","40ft","legacy_4m"]:
		await display(kind)
		var bounds := BrickCatalog.visual_bounds(cargo)
		var size := cargo.dimensions_m()
		assert(bounds.size.distance_to(size) < .06, "Container external envelope: " + str(bounds))
		var data := cargo.unit.to_dict()
		assert(ContainerUnit.from_dict(JSON.parse_string(JSON.stringify(data))).to_dict() == data)
		assert(cargo.find_child("DoorPortPivot",true,false) != null)
	var old := ContainerUnit.from_dict({"id":"old", "footprint":[4,4], "mass_kg":7123,"consignment_id":"keep"})
	assert(old.container_type == "legacy_4m" and old.mass_kg == 7123 and old.consignment_id == "keep")
	assert(old.footprint_cells(.5) == Vector2i(8,8))
	var ship := BoatBody.new()
	ship.freeze = true
	add_child(ship)
	var pads: Array[CargoSlotPadComponent] = []
	for x in [-1.25,1.25]:
		var pad := ImportedCargoPad.new()
		pad.name = "CargoPad" # Same names under different parents must not merge mass.
		pad.deck_width_m = 2.5; pad.deck_length_m = 6.5; pad.cell_size_m = .5
		pad.container_footprint = Vector2i(5,13)
		var bed := Node3D.new();ship.add_child(bed);bed.add_child(pad);bed.position.x=x
		pads.append(pad)
		assert(pad.add_container(ContainerUnit.create("box"+str(x),"provisions",3200)) >= 0)
		assert(pad.add_container(ContainerUnit.create()) < 0)
	assert(pads[0]._mass_prefix() != pads[1]._mass_prefix())
	var moving := pads[0].iter_container_nodes()[0]
	var unit := pads[0].take_container_node(moving)
	assert(unit.id == moving.unit.id and pads[0].get_containers().is_empty())
	assert(pads[0].place_container_node(moving) >= 0)
	assert(pads[0].place_container_node(moving) >= 0 and pads[0].get_containers().size() == 1,"Repeated landing is idempotent")
	pads[0].clear_all()
	assert(pads[0].add_container(ContainerUnit.create("too_long","provisions",3200,"40ft")) < 0)
	var yard := ImportedCargoPad.new()
	yard.affects_boat_cargo_mass = false;yard.deck_width_m = 6;yard.deck_length_m = 13
	add_child(yard)
	assert(yard.add_container(ContainerUnit.create("long","provisions",6400,"40ft")) >= 0)
	assert(yard.add_container(ContainerUnit.create("long","provisions",6400,"40ft")) < 0)
	var crane := ProvisionCrane.new()
	add_child(crane)
	for frame in 4: await get_tree().process_frame
	var long_box := yard.iter_container_nodes()[0]
	assert(crane.attach_container(long_box))
	assert(yard.get_containers().is_empty())
	var hook := long_box.find_child("Hook",true,false) as Node3D
	assert(hook != null and hook.global_position.distance_to(crane.get_hook_global()) < .001)
	crane._tick_attached_container()
	# Move the target underneath the real hook; release goes through the pad API.
	yard.global_position = crane.get_hook_global() - Vector3(0,long_box.lift_height_m(),0)
	crane.release_container_on_pad(yard)
	assert(yard.contains_node(long_box) and long_box.unit.id == "long")
	assert(long_box._body.collision_layer == 1)
	crane.queue_free()
	yard.queue_free();ship.queue_free()
	print("CONTAINERS PASS: dimensions, pivots, old/new persistence, pad resolution, overlap, 40 ft rejection, mass identity")

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: display("20ft")
			KEY_2: display("40ft")
			KEY_3: display("legacy_4m")
			KEY_O: open_doors()
