extends SceneTree
# Authoring-only bake: no noise generation or worker startup during gameplay.
func _initialize() -> void:
	call_deferred("bake")
func bake() -> void:
	var noise := FastNoiseLite.new()
	noise.seed=7319
	noise.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency=.075
	noise.fractal_octaves=3
	var generated := NoiseTexture3D.new()
	generated.width=64
	generated.height=64
	generated.depth=64
	generated.seamless=true
	generated.seamless_blend_skirt=.25
	generated.noise=noise
	await generated.changed
	var slices := generated.get_data()
	assert(slices.size()==64)
	for slice in slices: slice.convert(Image.FORMAT_R8)
	var level: Array[Image] = slices.duplicate()
	while level.size()>1:
		var size := level.size()/2
		var next: Array[Image] = []
		for z in size:
			var a := level[z*2].duplicate() as Image
			var b := level[z*2+1].duplicate() as Image
			a.resize(size,size,Image.INTERPOLATE_BILINEAR)
			b.resize(size,size,Image.INTERPOLATE_BILINEAR)
			for y in size:
				for x in size:
					a.set_pixel(x,y,a.get_pixel(x,y).lerp(b.get_pixel(x,y),.5))
			next.append(a)
		slices.append_array(next)
		level=next
	var volume := ImageTexture3D.new()
	assert(volume.create(Image.FORMAT_R8,64,64,64,true,slices)==OK)
	assert(volume.get_data().size()==127)
	assert(ResourceSaver.save(volume,"res://resources/textures/sky/cloud_density.res",ResourceSaver.FLAG_COMPRESS)==OK)
	print("CLOUD VOLUME BAKED 64 cubed R8")
	quit()

