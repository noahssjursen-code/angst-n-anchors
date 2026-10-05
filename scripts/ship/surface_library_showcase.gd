extends Node3D

func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(.025,.035,.045)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color(.8,.87,.94)
	environment.environment.ambient_light_energy=.7
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-55,-25,0)
	light.light_energy=1.5
	add_child(light)
	var camera := Camera3D.new()
	camera.position=Vector3(10,16,19)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=13
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current=true
	var examples := [
		{"label":"FLAT ROOF / RECTANGULAR","position":Vector3(-3.8,0,-3),"points":[[-1.5,-2],[1.5,-2],[1.5,2],[-1.5,2]],"crown":false,"visor_direction":0,"color":Color(.72,.75,.72)},
		{"label":"CROWNED ROOF / LONG CANOPY","position":Vector3(3.8,0,-3),"points":[[-1.5,-2.5],[1.5,-2.5],[1.5,2.5],[-1.5,2.5]],"crown":true,"visor_direction":0,"color":Color(.43,.54,.56)},
		{"label":"ANGLED ROOF / SIDE OVERHANG","position":Vector3(-3.8,0,3),"points":[[-1.5,1.5],[1.5,1.5],[1.5,-.5],[1,-1.5],[.5,-2],[-.5,-2],[-1,-1.5],[-1.5,-.5]],"crown":true,"visor_direction":4,"color":Color(.69,.7,.62)},
		{"label":"FLOOR / CONCAVE FOOTPRINT","position":Vector3(3.8,0,3),"points":[[-1.5,-1.5],[1.5,-1.5],[1.5,0],[0,0],[0,1.5],[-1.5,1.5]],"crown":false,"visor_direction":0,"color":Color(.22,.31,.33)}
	]
	for i in examples.size():
		var example: Dictionary=examples[i]
		var record := {"asset_id":"floor_tile" if i==3 else "roof_tile","outline":example["points"],"crown":example["crown"],"visor_direction":example["visor_direction"]}
		var model := ShipSurfaceKit.create(record)
		model.position=example["position"]
		add_child(model)
		ModelPaint.apply(model,{"surface":example["color"],"fascia":Color(.09,.21,.25),"underside":Color(.64,.68,.65)})
		var caption := Label3D.new()
		caption.text=example["label"]
		caption.font_size=44
		caption.pixel_size=.008
		caption.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		caption.position=example["position"]+Vector3(0,.2,2.8)
		caption.no_depth_test=true
		add_child(caption)
	var canvas:=CanvasLayer.new();canvas.layer=100;add_child(canvas)
	var header:=ColorRect.new();header.color=Color(.025,.035,.045);header.size=Vector2(4000,115);canvas.add_child(header)
	var title:=Label.new();title.text="MODULAR SHIP SURFACES";title.position=Vector2(40,25);title.add_theme_font_size_override("font_size",34);canvas.add_child(title)
	var subtitle:=Label.new();subtitle.text="One Blender module library · Custom footprints · Independent profile, overhang and paint";subtitle.position=Vector2(40,75);subtitle.add_theme_font_size_override("font_size",20);canvas.add_child(subtitle)
	for i in 12: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("C:/Users/noahs/Documents/Codex/2026-10-05/referenced-chatgpt-conversation-this-is-an/outputs/roof-kit/modular-surfaces.png")
	print("PASS: four different footprints from the same imported module library")
	if "--verify-roof" in OS.get_cmdline_user_args(): get_tree().quit()
