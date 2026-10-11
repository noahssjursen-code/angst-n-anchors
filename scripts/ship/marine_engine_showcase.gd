extends Node
var inspector: MarineEngineInspector
const HULLS := ["trawler_hull_14m","hull_24x8","hull_32x10","hull_88x14","catamaran_36x11"]
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var capture := args.find("--capture-dir")
	for hull in HULLS:
		for spec in MarineEngineCatalog.options(hull):
			var layout := ImportedVesselLayout.empty(hull)
			layout.engine_preset = spec.id
			assert(ImportedVesselLayout.valid(layout,hull))
			var restored: Dictionary = JSON.parse_string(JSON.stringify(layout))
			var boat := VesselSpawn.instantiate(hull,restored) as ImportedDraftVessel
			assert(boat.physics_profile.shaft_power_kw == float(spec.power_kw))
			assert(is_equal_approx(boat.physics_profile.fuel_burn_l_per_sec_full,float(spec.fuel_lph)/3600.0))
			assert(is_equal_approx(boat.physics_profile.reverse_multiplier,float(spec.get("reverse_multiplier", .65))))
			VesselSpawn.apply_propulsion_override(boat,{"shaft_power_kw":999999})
			assert(boat.physics_profile.shaft_power_kw == float(spec.power_kw))
			assert(boat.engine_visual.find_child("CouplingRotor",true,false) != null)
			boat.assembler.free() # Not entered into a tree, so _exit_tree is not called.
			boat.free()
			if capture >= 0:
				show_engine(hull, spec.id)
				for frame in 12: await get_tree().process_frame
				await RenderingServer.frame_post_draw
				inspector.viewport.get_texture().get_image().save_png(args[capture+1].path_join("engine-%s.png" % spec.id))
				inspector.model.rotation.y = PI
				for frame in 8: await get_tree().process_frame
				await RenderingServer.frame_post_draw
				inspector.viewport.get_texture().get_image().save_png(args[capture+1].path_join("engine-%s-reverse.png" % spec.id))
	var invalid := ImportedVesselLayout.empty(HULLS[0]);invalid.engine_preset = "freighter_1600"
	assert(not ImportedVesselLayout.valid(invalid,HULLS[0]))
	var old_factory := ImportedVesselLayout.empty("hull_88x14")
	old_factory.engine_preset = "feeder_1500"
	var saved_layout := JSON.stringify(old_factory)
	var upgraded := VesselSpawn.instantiate("hull_88x14", old_factory) as ImportedDraftVessel
	assert(upgraded.physics_profile.shaft_power_kw == 5600)
	assert(is_equal_approx(upgraded.physics_profile.design_displacement_t, 1870.8))
	assert(JSON.stringify(old_factory) == saved_layout)
	# Existing explicitly selected 2100 package still resolves unchanged.
	assert(MarineEngineCatalog.resolve("hull_88x14", "feeder_2100").power_kw == 2100)
	upgraded.free()
	print("ENGINE PACKAGES PASS: all catalog presets, matching models, power/fuel, JSON persistence, no arbitrary power override, hull compatibility")
	if capture >= 0:
		inspector.queue_free()
		for frame in 3: await get_tree().process_frame
		get_tree().quit()
	else: show_engine(HULLS[0])

func show_engine(hull: String, preset: String = "") -> void:
	if is_instance_valid(inspector):
		inspector.hide()
		inspector.queue_free()
	inspector = MarineEngineInspector.new()
	add_child(inspector)
	inspector.inspect(hull,preset)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_5: show_engine(HULLS[event.keycode-KEY_1])
