extends Node

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	call_deferred("run")

func run() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var levels := [0.0, .008, .02, .08, .5, 1.0]
	var size := get_viewport().get_visible_rect().size
	for i in levels.size():
		var rect := ColorRect.new()
		rect.position = Vector2(i*size.x/levels.size(),0)
		rect.size = Vector2(size.x/levels.size()+1,size.y)
		rect.color = Color(levels[i],levels[i],levels[i])
		layer.add_child(rect)
	var effect := ColorRect.new()
	effect.size = size
	var material := ShaderMaterial.new()
	material.shader = preload("res://resources/shaders/screen_effects.gdshader")
	for field in ["outline_strength","grain_strength","vignette_strength","shadow_coolness","highlight_warmth","underwater_strength"]:
		material.set_shader_parameter(field,0.0)
	material.set_shader_parameter("weather_contrast",.03)
	effect.material=material
	layer.add_child(effect)
	for frame in 5: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var output := "C:/Users/noahs/Pictures/machinescreenshots/screen-grade-"+str(Time.get_unix_time_from_system()).replace(".","-")+".png"
	assert(image.save_png(output)==OK)
	print("CAPTURE ",output)
	var previous := -1.0
	for i in levels.size():
		var value := image.get_pixel(int((i+.5)*size.x/levels.size()),int(size.y*.5)).r
		assert(value > previous, "Screen grade must retain distinct dark tones")
		if i == 0: assert(value < .004, "Black must remain black")
		if i == 1: assert(value > .003, "Faint illumination must survive contrast")
		previous=value
	print("PASS rendered screen grade: black preserved and faint dark tones remain distinct")
	get_tree().quit()
