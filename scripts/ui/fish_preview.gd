class_name FishPreview
extends SubViewportContainer

## Allocated only while inspecting a catch. No per-fish viewport in the world.
var viewport: SubViewport
var pivot: Node3D
var camera: Camera3D
var fish: Node3D
var _dragging := false

func _ready() -> void:
	stretch=true
	viewport=SubViewport.new();viewport.size=Vector2i(640,400)
	viewport.own_world_3d=true;viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("12232c")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("b4cbd1");environment.environment.ambient_light_energy=.5
	viewport.add_child(environment)
	var key:=DirectionalLight3D.new();key.rotation_degrees=Vector3(-35,-30,0);key.light_energy=1.1;viewport.add_child(key)
	var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(25,135,0);fill.light_color=Color("b0d8e9");fill.light_energy=.6;viewport.add_child(fill)
	pivot=Node3D.new();viewport.add_child(pivot)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.80
	viewport.add_child(camera);camera.position=Vector3(0,.18,2);camera.look_at(Vector3.ZERO);camera.current=true
	gui_input.connect(_input_preview)

func show_species(id: String) -> void:
	if is_instance_valid(fish):fish.free()
	fish=FishCatalog.model(id)
	if fish!=null:
		pivot.add_child(fish)
		for animation in fish.find_children("*","AnimationPlayer",true,false):
			for clip in animation.get_animation_list():
				if "Swim" in clip:animation.get_animation(clip).loop_mode=Animation.LOOP_LINEAR;animation.play(clip)
	pivot.rotation=Vector3(.9 if id=="halibut" else .05,-.18,0)
	camera.size=.80

func _input_preview(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT:_dragging=event.pressed
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_UP:camera.size=maxf(.65,camera.size-.1)
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN:camera.size=minf(2.2,camera.size+.1)
	elif event is InputEventMouseMotion and _dragging:
		pivot.rotation.y+=event.relative.x*.008
		pivot.rotation.x=clampf(pivot.rotation.x+event.relative.y*.008,-PI,PI)
