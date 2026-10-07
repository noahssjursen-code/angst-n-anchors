extends "res://tests/marine_material_review.gd"

## Real assembled assets and the same shared material profiles used in play.
## F6 is isolated before autoloads start. Nothing is saved to a captain.
var subject: Node3D
var page := 0
var target := Vector3.ZERO
var orbiting := false
var night := false
var review_lamp: OmniLight3D
const HELP := "1–4 ships · 5 office · 6 storage · 7 tanks · 8 landing · 9 cranes · 0 swatches · C clothing · V cargo · X bulk\nRight-drag orbit · Wheel zoom · N lighting · P save photo · B before/after"
const SWATCHES := [
	["hull_painted_plate","antifouling","cabin_enamel","roof_enamel","machinery_enamel","galvanized","brushed_steel","bronze","working_steel","tread_plate","corroded_plate","riveted_bare_plate"],
	["deck_grip","rubber","seat_vinyl","woven_upholstery","rope_fibre","console_laminate","timber_clean","timber_weathered","pallet_wood","painted_cladding","exterior_render","working_concrete"],
	["asphalt","warehouse_sheet","roof_sheet","anodized","dark_enamel","painted_timber","concrete_cast","concrete_worn","moulded_polymer","heatshield","tank_cladding","packing_cardboard"],
	["crushed_aggregate","coal_aggregate","container_enamel"]
]

func _ready() -> void:
	await super._ready()
	labels.text += "\n" + HELP
	target = Vector3(0, boat.depth_m + .8, 0)
	if OS.get_cmdline_user_args().has("--benchmark-materials"):
		await benchmark_materials()
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--capture-library"):
		for mode in range(5,10):
			show_assets(mode)
			await shot("assets-"+str(mode))
			var offset := camera.position-target
			camera.position=target+offset*.65
			await shot("assets-"+str(mode)+"-detail")
			if mode in [5,8]:
				toggle_lighting()
				await shot("assets-"+str(mode)+"-artificial")
				toggle_lighting()
		for i in SWATCHES.size():
			show_swatches(i)
			await shot("swatches-"+str(i))
		show_character()
		await shot("character-clothing")
		var actor:=subject.get_node("Character") as CharacterVisual
		actor.animation_player.play("walk",0.0)
		actor.animation_player.speed_scale=0
		actor.animation_player.seek(.3,true)
		actor.animation_player.advance(0)
		await shot("character-clothing-walk")
		camera.position=Vector3(.9,1.5,-1.5);camera.look_at(Vector3(0,1.1,0))
		await shot("character-clothing-close")
		show_cargo()
		await shot("container-detail")
		camera.position=Vector3(2.8,2.8,4.5);camera.look_at(Vector3(0,1.4,2.5))
		await shot("container-doors")
		show_bulk()
		await shot("bulk-aggregate")
		print("MATERIAL LIBRARY REVIEW PASS source profiles=",SurfaceMaterialLibrary.profiles().size())
		get_tree().quit()

func show_character() -> void:
	clear_subject();current=10;camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	var actor:=CharacterVisual.new();actor.name="Character";subject.add_child(actor)
	actor.apply_appearance(CharacterCatalog.appearance_preset("dock_worker"))
	actor.play_motion(&"idle",0)
	target=Vector3(0,.9,0);camera.position=Vector3(1.7,1.6,-2.8);camera.look_at(target)
	labels.text="WORK CLOTHING · Authored UVs follow the skeleton · Fabric030 / Rubber004\n"+HELP

func show_cargo() -> void:
	clear_subject();current=11;camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	var cargo:=ContainerNode.new();subject.add_child(cargo)
	var unit:=ContainerFactory.make_one();unit.paint_variant=2;cargo.setup(unit)
	target=Vector3(0,1.3,0);camera.position=Vector3(4,3.3,-5.5);camera.look_at(target)
	labels.text="CONTAINER · Coated steel, zinc locks, seals and plywood\n"+HELP

func show_bulk() -> void:
	clear_subject();current=12;camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	for i in 2:
		var pile:=OreMoundBuilder.build_mound("coal" if i==0 else "iron_ore",Vector3(7,2.4,8),42)
		pile.position.x=-4.5 if i==0 else 4.5
		subject.add_child(pile)
	target=Vector3(0,1,0);camera.position=Vector3(10,7,-13);camera.look_at(target)
	labels.text="BULK STOCK · Original gravel grain with commodity colouring\n"+HELP
	update_lamp()

func benchmark_materials() -> void:
	var viewport:=get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport,true)
	for mode in [3,5,9]:
		for finished in [false,true,false,true]:
			SurfaceMaterialLibrary.enabled=finished
			if mode==3:
				if is_instance_valid(subject):subject.free()
				await show_ship(3)
			else:show_assets(mode)
			var timings:Array[float]=[]
			for frame in 210:
				await RenderingServer.frame_post_draw
				if frame>=90:timings.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
			timings.sort()
			print("MATERIAL BENCH mode=",mode," finished=",finished," median_gpu_ms=",timings[timings.size()/2]," draws=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)," triangles=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)," texture_bytes=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED))
	print("MATERIAL BENCH PASS")

func clear_subject() -> void:
	if is_instance_valid(boat): boat.free()
	if is_instance_valid(subject): subject.free()
	subject=Node3D.new()
	add_child(subject)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size=Vector2(160,160)
	floor.mesh=plane
	floor.position.y=-.03
	floor.material_override=HarbourEnvironmentKit.paving()
	subject.add_child(floor)

func show_assets(mode: int) -> void:
	current=mode
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	clear_subject()
	var kit := "res://resources/models/parts/port_facilities/"
	match mode:
		5:
			HarbourEnvironmentKit.model(subject,kit+"harbour_authority_20m.glb",Vector3.ZERO)
			camera.position=Vector3(24,12,-24); target=Vector3(0,6,0)
			labels.text="HARBOUR AUTHORITY · Render, cladding, painted metal and glass"
		6:
			HarbourEnvironmentKit.model(subject,kit+"cargo_shelter_8m.glb",Vector3.ZERO)
			HarbourEnvironmentKit.model(subject,kit+"loaded_storage_rack.glb",Vector3(-1.8,0,1.8))
			HarbourEnvironmentKit.model(subject,kit+"loaded_storage_rack.glb",Vector3(1.8,0,1.8))
			HarbourEnvironmentKit.model(subject,"warehouse_12x18",Vector3(-14,0,10))
			camera.position=Vector3(10,7,-13); target=Vector3(0,2,0)
			labels.text="STORAGE · Pallet grain, galvanized racks and coated roof sheets"
		7:
			HarbourEnvironmentKit.model(subject,kit+"lng_terminal_tank_24m.glb",Vector3.ZERO)
			camera.position=Vector3(34,20,-36); target=Vector3(0,7,0)
			labels.text="LNG STORAGE · Coatings, concrete and access steelwork"
		8:
			for id in ["landing_skid","landing_separator","landing_pump_drive","landing_trough"]:
				HarbourEnvironmentKit.model(subject,"res://resources/models/parts/port_kit/"+id+".glb",Vector3.ZERO)
			HarbourEnvironmentKit.repeated(subject,"quay_coping_2m",[Transform3D(Basis.IDENTITY,Vector3(0,0,-4)),Transform3D(Basis.IDENTITY,Vector3(2,0,-4))])
			camera.position=Vector3(9,5,-11); target=Vector3(0,1.6,0)
			labels.text="LANDING PLANT · Painted steel, rubber, working metal and concrete"
		9:
			var rig:=BlenderBulkCraneRig.new()
			subject.add_child(rig)
			rig.get_part("boom").rotation_degrees.x=-25
			rig.update_luff_cylinder()
			camera.position=Vector3(8,6,10); target=Vector3(-.8,2.4,0)
			labels.text="BULK CRANE · Authored markings retained, ambientCG paint and steel detail"
	labels.text += "\n"+HELP
	camera.look_at(target)
	update_lamp()

func show_swatches(index: int) -> void:
	current=0; page=posmod(index,SWATCHES.size())
	clear_subject()
	var names: Array = SWATCHES[page]
	for i in names.size():
		var profile: String=names[i]
		var x:=float(i%4)*3.1-4.65
		var z:=float(i/4)*3.4-3.4
		var spec: Dictionary=SurfaceMaterialLibrary.profiles()[profile]
		var colour:=Color("9fadae")
		if profile in ["hull_painted_plate","machinery_enamel","painted_cladding"]: colour=Color("326d73")
		if profile in ["rubber","deck_grip","dark_enamel","antifouling"]: colour=Color("27383d")
		if profile in ["seat_vinyl","woven_upholstery"]: colour=Color("3e5360")
		if profile=="bronze": colour=Color("a37e47")
		if float(spec.get("source_colour",0))>0: colour=Color.WHITE
		var mat:=SurfaceMaterialLibrary.material(profile,colour)
		var block:=MeshInstance3D.new(); var box:=BoxMesh.new();box.size=Vector3(2.4,.20,1.65)
		block.mesh=box;block.material_override=mat;block.position=Vector3(x,.12,z);subject.add_child(block)
		var sphere:=MeshInstance3D.new();var ball:=SphereMesh.new();ball.radius=.48;ball.height=.96
		sphere.mesh=ball;sphere.material_override=mat;sphere.position=Vector3(x,.7,z);subject.add_child(sphere)
		var name_label:=Label3D.new(); name_label.text=profile.replace("_"," ")+"\nambientCG · "+str(spec.asset)
		name_label.font_size=30;name_label.pixel_size=.0065;name_label.position=Vector3(x,.4,z+1.25)
		name_label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;name_label.no_depth_test=false;subject.add_child(name_label)
	target=Vector3(0,0,0);camera.position=Vector3(0,12,10);camera.look_at(target)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=12.8
	labels.text="SHARED MATERIAL LIBRARY · Original ambientCG maps · Page "+str(page+1)+" / "+str(SWATCHES.size())+"\n"+HELP
	update_lamp()

func toggle_lighting() -> void:
	night=not night
	sun.light_energy=.025 if night else 1.35
	environment.ambient_light_energy=.15 if night else .55
	update_lamp()

func update_lamp() -> void:
	if not is_instance_valid(review_lamp):
		review_lamp=OmniLight3D.new();add_child(review_lamp)
		review_lamp.light_color=Color("ffd8ac");review_lamp.light_energy=4
		review_lamp.omni_range=28;review_lamp.light_size=.6;review_lamp.shadow_enabled=true
	review_lamp.position=target+Vector3(1,4,-3);review_lamp.visible=night

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.is_pressed() or event.is_echo():return
	if event.keycode>=KEY_1 and event.keycode<=KEY_4:
		camera.projection=Camera3D.PROJECTION_PERSPECTIVE
		if is_instance_valid(subject):subject.free()
		await show_ship(event.keycode-KEY_1)
		target=Vector3(0,boat.depth_m+.8,0);labels.text+="\n"+HELP;update_lamp()
	elif event.keycode>=KEY_5 and event.keycode<=KEY_9: show_assets(event.keycode-KEY_0)
	elif event.keycode==KEY_0:show_swatches(page+1 if current==0 else 0)
	elif event.keycode==KEY_N:toggle_lighting()
	elif event.keycode==KEY_C:show_character()
	elif event.keycode==KEY_V:show_cargo()
	elif event.keycode==KEY_X:show_bulk()
	elif event.keycode==KEY_P:await shot("manual-"+str(Time.get_ticks_msec()))
	elif event.keycode==KEY_B:
		SurfaceMaterialLibrary.enabled=not SurfaceMaterialLibrary.enabled
		if current==10:show_character()
		elif current==11:show_cargo()
		elif current==12:show_bulk()
		elif current>=5:show_assets(current)
		elif is_instance_valid(boat):await show_ship(current);labels.text+="\n"+HELP

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT:orbiting=event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			camera.position=target+(camera.position-target)*(.88 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.14)
	if event is InputEventMouseMotion and orbiting:
		var offset:=camera.position-target
		offset=offset.rotated(Vector3.UP,-event.relative.x*.005)
		var side:=offset.normalized().cross(Vector3.UP).normalized()
		var pitched:=offset.rotated(side,-event.relative.y*.005)
		if absf(pitched.normalized().y)<.98:offset=pitched
		camera.position=target+offset;camera.look_at(target)
