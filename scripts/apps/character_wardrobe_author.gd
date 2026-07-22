extends SceneTree

## Source-controlled authoring recipe for the block-built character wardrobe.
## Run headless with `--script` after changing a recipe. Production loads only
## the generated JSON models; it never constructs clothing from Godot primitives.

const OUTPUT_ROOT := "res://resources/data/models/characters/wardrobe"
const BOX_INDICES := [
	0,2,1, 0,3,2, 4,5,6, 4,6,7,
	0,5,4, 0,1,5, 1,6,5, 1,2,6,
	2,7,6, 2,3,7, 3,4,7, 3,0,4,
]


func _init() -> void:
	call_deferred("_author")


func _author() -> void:
	var models := _recipes()
	var written := 0
	for key in models:
		var split := String(key).split("/")
		if split.size() != 2:
			continue
		var directory := "%s/%s" % [OUTPUT_ROOT, split[0]]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		var path := "%s/%s.json" % [directory, split[1]]
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			push_error("Could not author wardrobe model: %s" % path)
			quit(1)
			return
		file.store_string(JSON.stringify({
			"name": "character_%s_%s" % [split[0], split[1]],
			"_doc": "Generated block-built character wardrobe model. Coordinates are shared with npc_character_study.",
			"parts": models[key],
		}, "  "))
		written += 1
	print("CHARACTER_WARDROBE_MODELS=%d" % written)
	quit(0)


func _recipes() -> Dictionary:
	var result := {}

	result["hair/cropped"] = [
		_p("top", "hair", Vector3(0,1.722,0.005), Vector3(0.27,0.055,0.23)),
		_p("back", "hair_shadow", Vector3(0,1.625,0.118), Vector3(0.24,0.14,0.025)),
	]
	result["hair/side_part"] = [
		_p("top", "hair", Vector3(-0.012,1.724,0.005), Vector3(0.275,0.05,0.23)),
		_p("part", "hair_highlight", Vector3(0.055,1.748,-0.035), Vector3(0.012,0.018,0.17)),
		_p("side", "hair", Vector3(-0.128,1.625,0), Vector3(0.025,0.14,0.21)),
		_p("back", "hair_shadow", Vector3(0,1.625,0.118), Vector3(0.24,0.14,0.025)),
	]
	result["hair/tied_back"] = [
		_p("top", "hair", Vector3(0,1.722,0.012), Vector3(0.27,0.05,0.225)),
		_p("back", "hair", Vector3(0,1.605,0.122), Vector3(0.235,0.18,0.03)),
		_p("tie", "hair_shadow", Vector3(0,1.49,0.145), Vector3(0.075,0.055,0.06)),
		_p("tail", "hair", Vector3(0,1.40,0.155), Vector3(0.09,0.17,0.07)),
	]

	result["facial_hair/moustache"] = [
		_p("left", "facial_hair", Vector3(-0.026,1.542,-0.126), Vector3(0.054,0.018,0.016), Vector3(0,0,8)),
		_p("right", "facial_hair", Vector3(0.026,1.542,-0.126), Vector3(0.054,0.018,0.016), Vector3(0,0,-8)),
	]
	result["facial_hair/pencil_moustache"] = [
		_p("left", "facial_hair", Vector3(-0.025,1.542,-0.126), Vector3(0.05,0.010,0.014)),
		_p("right", "facial_hair", Vector3(0.025,1.542,-0.126), Vector3(0.05,0.010,0.014)),
	]
	result["facial_hair/handlebar"] = [
		_p("left", "facial_hair", Vector3(-0.032,1.542,-0.127), Vector3(0.066,0.020,0.016), Vector3(0,0,8)),
		_p("right", "facial_hair", Vector3(0.032,1.542,-0.127), Vector3(0.066,0.020,0.016), Vector3(0,0,-8)),
		_p("tip_left", "facial_hair", Vector3(-0.071,1.548,-0.127), Vector3(0.024,0.012,0.016), Vector3(0,0,-24)),
		_p("tip_right", "facial_hair", Vector3(0.071,1.548,-0.127), Vector3(0.024,0.012,0.016), Vector3(0,0,24)),
	]
	result["facial_hair/stubble"] = [
		_p("chin", "facial_hair_faded", Vector3(0,1.454,-0.119), Vector3(0.13,0.045,0.018)),
		_p("left", "facial_hair_faded", Vector3(-0.09,1.493,-0.119), Vector3(0.045,0.085,0.018)),
		_p("right", "facial_hair_faded", Vector3(0.09,1.493,-0.119), Vector3(0.045,0.085,0.018)),
	]
	result["facial_hair/short_beard"] = [
		_p("chin", "facial_hair", Vector3(0,1.438,-0.120), Vector3(0.15,0.075,0.022)),
		_p("left", "facial_hair", Vector3(-0.105,1.49,-0.120), Vector3(0.035,0.10,0.022)),
		_p("right", "facial_hair", Vector3(0.105,1.49,-0.120), Vector3(0.035,0.10,0.022)),
		_p("moustache", "facial_hair", Vector3(0,1.542,-0.127), Vector3(0.095,0.018,0.016)),
	]
	result["facial_hair/full_beard"] = [
		_p("chin", "facial_hair", Vector3(0,1.405,-0.115), Vector3(0.17,0.14,0.035)),
		_p("left", "facial_hair", Vector3(-0.108,1.49,-0.120), Vector3(0.035,0.12,0.024)),
		_p("right", "facial_hair", Vector3(0.108,1.49,-0.120), Vector3(0.035,0.12,0.024)),
		_p("moustache", "facial_hair", Vector3(0,1.542,-0.128), Vector3(0.11,0.022,0.018)),
	]
	result["facial_hair/goatee"] = [
		_p("chin", "facial_hair", Vector3(0,1.435,-0.122), Vector3(0.075,0.09,0.022)),
		_p("moustache", "facial_hair", Vector3(0,1.542,-0.127), Vector3(0.09,0.016,0.016)),
	]

	result["tops/work_shirt"] = [
		_p("collar_left", "top_accent", Vector3(-0.055,1.275,-0.12), Vector3(0.10,0.05,0.025), Vector3(0,0,-12)),
		_p("collar_right", "top_accent", Vector3(0.055,1.275,-0.12), Vector3(0.10,0.05,0.025), Vector3(0,0,12)),
		_p("placket", "top_shadow", Vector3(0,1.08,-0.121), Vector3(0.018,0.34,0.018)),
		_p("pocket", "top_accent", Vector3(0.115,1.13,-0.122), Vector3(0.10,0.08,0.018)),
	]
	result["tops/wool_sweater"] = [
		_p("collar", "top_shadow", Vector3(0,1.315,-0.015), Vector3(0.17,0.045,0.16)),
		_p("cuff_left", "top_shadow", Vector3(-0.275,0.835,0), Vector3(0.13,0.045,0.16)),
		_p("cuff_right", "top_shadow", Vector3(0.275,0.835,0), Vector3(0.13,0.045,0.16)),
	]
	result["tops/fisherman_sweater"] = [
		_p("collar", "top_shadow", Vector3(0,1.315,-0.015), Vector3(0.17,0.045,0.16)),
		_p("band_upper", "top_accent", Vector3(0,1.17,-0.121), Vector3(0.425,0.025,0.018)),
		_p("band_lower", "top_accent", Vector3(0,1.10,-0.121), Vector3(0.425,0.025,0.018)),
		_p("cuff_left", "top_shadow", Vector3(-0.275,0.835,0), Vector3(0.13,0.045,0.16)),
		_p("cuff_right", "top_shadow", Vector3(0.275,0.835,0), Vector3(0.13,0.045,0.16)),
	]
	result["tops/turtleneck"] = [
		_p("collar", "top", Vector3(0,1.36,0), Vector3(0.16,0.11,0.14)),
		_p("collar_band", "top_shadow", Vector3(0,1.325,-0.075), Vector3(0.165,0.025,0.02)),
	]
	result["tops/dress_shirt"] = [
		_p("collar_left", "top", Vector3(-0.052,1.285,-0.121), Vector3(0.10,0.045,0.02), Vector3(0,0,-16)),
		_p("collar_right", "top", Vector3(0.052,1.285,-0.121), Vector3(0.10,0.045,0.02), Vector3(0,0,16)),
		_p("buttons", "top_shadow", Vector3(0,1.06,-0.122), Vector3(0.012,0.37,0.015)),
		_p("cuff_left", "top_shadow", Vector3(-0.275,0.835,0), Vector3(0.13,0.035,0.16)),
		_p("cuff_right", "top_shadow", Vector3(0.275,0.835,0), Vector3(0.13,0.035,0.16)),
	]
	result["tops/flannel_shirt"] = [
		_p("collar_left", "top_accent", Vector3(-0.055,1.275,-0.12), Vector3(0.10,0.05,0.025), Vector3(0,0,-12)),
		_p("collar_right", "top_accent", Vector3(0.055,1.275,-0.12), Vector3(0.10,0.05,0.025), Vector3(0,0,12)),
		_p("placket", "top_shadow", Vector3(0,1.06,-0.122), Vector3(0.018,0.38,0.018)),
		_p("pocket_left", "top_accent", Vector3(-0.12,1.13,-0.122), Vector3(0.095,0.08,0.018)),
		_p("pocket_right", "top_accent", Vector3(0.12,1.13,-0.122), Vector3(0.095,0.08,0.018)),
	]

	result["outerwear/deck_jacket"] = [
		_p("collar_left", "outerwear_shadow", Vector3(-0.06,1.285,-0.128), Vector3(0.115,0.052,0.025), Vector3(0,0,-14)),
		_p("collar_right", "outerwear_shadow", Vector3(0.06,1.285,-0.128), Vector3(0.115,0.052,0.025), Vector3(0,0,14)),
		_p("placket", "accent", Vector3(0,1.06,-0.13), Vector3(0.018,0.39,0.02)),
		_p("pocket", "outerwear_highlight", Vector3(0.115,1.13,-0.13), Vector3(0.10,0.08,0.02)),
		_p("hem", "outerwear_shadow", Vector3(0,0.79,-0.012), Vector3(0.44,0.035,0.23)),
	]
	result["outerwear/heavy_work_coat"] = [
		_p("body", "outerwear", Vector3(0,1.00,-0.006), Vector3(0.46,0.60,0.24)),
		_p("collar_left", "outerwear_shadow", Vector3(-0.065,1.285,-0.132), Vector3(0.12,0.06,0.025), Vector3(0,0,-16)),
		_p("collar_right", "outerwear_shadow", Vector3(0.065,1.285,-0.132), Vector3(0.12,0.06,0.025), Vector3(0,0,16)),
		_p("pocket_left", "outerwear_highlight", Vector3(-0.13,0.91,-0.134), Vector3(0.105,0.09,0.022)),
		_p("pocket_right", "outerwear_highlight", Vector3(0.13,0.91,-0.134), Vector3(0.105,0.09,0.022)),
		_p("hem", "outerwear_shadow", Vector3(0,0.70,-0.007), Vector3(0.46,0.04,0.24)),
	]
	result["outerwear/rain_jacket_yellow"] = _rain_jacket_parts()
	result["outerwear/rain_jacket_orange"] = _rain_jacket_parts()
	result["outerwear/officer_coat"] = [
		_p("lapel_left", "outerwear_highlight", Vector3(-0.075,1.20,-0.132), Vector3(0.12,0.055,0.022), Vector3(0,0,-28)),
		_p("lapel_right", "outerwear_highlight", Vector3(0.075,1.20,-0.132), Vector3(0.12,0.055,0.022), Vector3(0,0,28)),
		_p("buttons_left", "accent", Vector3(-0.055,1.03,-0.133), Vector3(0.014,0.26,0.014)),
		_p("buttons_right", "accent", Vector3(0.055,1.03,-0.133), Vector3(0.014,0.26,0.014)),
		_p("epaulette_left", "accent", Vector3(-0.245,1.295,0), Vector3(0.13,0.025,0.13)),
		_p("epaulette_right", "accent", Vector3(0.245,1.295,0), Vector3(0.13,0.025,0.13)),
	]
	result["outerwear/suit_jacket"] = [
		_p("lapel_left", "outerwear_highlight", Vector3(-0.072,1.17,-0.132), Vector3(0.15,0.055,0.022), Vector3(0,0,-34)),
		_p("lapel_right", "outerwear_highlight", Vector3(0.072,1.17,-0.132), Vector3(0.15,0.055,0.022), Vector3(0,0,34)),
		_p("button", "outerwear_shadow", Vector3(0,0.98,-0.134), Vector3(0.02,0.025,0.015)),
		_p("pocket_left", "outerwear_shadow", Vector3(-0.135,0.94,-0.133), Vector3(0.09,0.022,0.015)),
		_p("pocket_right", "outerwear_shadow", Vector3(0.135,0.94,-0.133), Vector3(0.09,0.022,0.015)),
		_p("tie", "accent", Vector3(0,1.15,-0.136), Vector3(0.028,0.20,0.018)),
	]
	result["outerwear/reflective_vest"] = [
		_p("body", "outerwear", Vector3(0,1.07,-0.127), Vector3(0.45,0.40,0.028)),
		_p("opening", "outerwear_shadow", Vector3(0,1.08,-0.145), Vector3(0.035,0.39,0.012)),
		_p("band_upper", "reflective", Vector3(0,1.15,-0.147), Vector3(0.45,0.025,0.012)),
		_p("band_lower", "reflective", Vector3(0,1.00,-0.147), Vector3(0.45,0.025,0.012)),
	]
	result["outerwear/fleece_vest"] = [
		_p("body", "outerwear", Vector3(0,1.08,-0.126), Vector3(0.45,0.42,0.028)),
		_p("zip", "outerwear_shadow", Vector3(0,1.08,-0.145), Vector3(0.014,0.40,0.012)),
		_p("collar", "outerwear_highlight", Vector3(0,1.30,-0.03), Vector3(0.19,0.07,0.18)),
	]

	result["trousers/work_trousers"] = _knee_parts("trouser_detail")
	result["trousers/bib_overalls"] = [
		_p("bib", "trousers", Vector3(0,1.00,-0.126), Vector3(0.27,0.30,0.025)),
		_p("pocket", "trouser_detail", Vector3(0,1.02,-0.145), Vector3(0.12,0.08,0.014)),
		_p("strap_left", "trousers", Vector3(-0.095,1.22,-0.13), Vector3(0.035,0.22,0.02), Vector3(0,0,-5)),
		_p("strap_right", "trousers", Vector3(0.095,1.22,-0.13), Vector3(0.035,0.22,0.02), Vector3(0,0,5)),
	]
	result["trousers/uniform_trousers"] = [
		_p("stripe_left", "accent", Vector3(-0.157,0.39,0), Vector3(0.012,0.75,0.17)),
		_p("stripe_right", "accent", Vector3(0.157,0.39,0), Vector3(0.012,0.75,0.17)),
	]
	result["trousers/rain_trousers"] = [
		_p("left", "trousers", Vector3(-0.085,0.39,-0.086), Vector3(0.155,0.78,0.018)),
		_p("right", "trousers", Vector3(0.085,0.39,-0.086), Vector3(0.155,0.78,0.018)),
		_p("band_left", "reflective", Vector3(-0.085,0.25,-0.098), Vector3(0.16,0.025,0.012)),
		_p("band_right", "reflective", Vector3(0.085,0.25,-0.098), Vector3(0.16,0.025,0.012)),
	]
	result["trousers/suit_trousers"] = [
		_p("crease_left", "trouser_detail", Vector3(-0.085,0.43,-0.089), Vector3(0.012,0.63,0.012)),
		_p("crease_right", "trouser_detail", Vector3(0.085,0.43,-0.089), Vector3(0.012,0.63,0.012)),
	]
	result["trousers/denim_trousers"] = _knee_parts("trouser_detail")

	result["footwear/work_boots"] = _work_boot_parts()
	result["footwear/sea_boots"] = _sea_boot_parts()
	result["footwear/yellow_rubber_boots"] = _sea_boot_parts() + [
		_p("band_left", "footwear_detail", Vector3(-0.085,0.38,-0.002), Vector3(0.16,0.025,0.18)),
		_p("band_right", "footwear_detail", Vector3(0.085,0.38,-0.002), Vector3(0.16,0.025,0.18)),
	]
	result["footwear/dress_shoes"] = [
		_p("toe_left", "footwear", Vector3(-0.085,0.07,-0.105), Vector3(0.155,0.14,0.10)),
		_p("toe_right", "footwear", Vector3(0.085,0.07,-0.105), Vector3(0.155,0.14,0.10)),
	]

	result["headwear/beanie"] = _beanie_parts()
	result["headwear/watch_cap"] = _beanie_parts()
	result["headwear/flat_cap"] = [
		_p("crown", "headwear", Vector3(0,1.742,0.005), Vector3(0.29,0.075,0.245)),
		_p("brim", "headwear_shadow", Vector3(0,1.716,-0.15), Vector3(0.18,0.028,0.10)),
	]
	result["headwear/peaked_cap"] = [
		_p("crown", "headwear", Vector3(0,1.76,0.005), Vector3(0.29,0.09,0.24)),
		_p("band", "headwear_shadow", Vector3(0,1.718,-0.01), Vector3(0.295,0.035,0.245)),
		_p("brim", "headwear_shadow", Vector3(0,1.706,-0.15), Vector3(0.19,0.025,0.10)),
		_p("badge", "headwear_badge", Vector3(0,1.745,-0.132), Vector3(0.035,0.04,0.018)),
	]
	result["headwear/souwester"] = [
		_p("crown", "headwear", Vector3(0,1.755,0.01), Vector3(0.29,0.085,0.24)),
		_p("brim_front", "headwear", Vector3(0,1.71,-0.155), Vector3(0.33,0.025,0.13)),
		_p("brim_back", "headwear", Vector3(0,1.71,0.15), Vector3(0.36,0.025,0.14)),
		_p("neck_flap", "headwear", Vector3(0,1.61,0.135), Vector3(0.28,0.16,0.025)),
	]
	result["headwear/hard_hat"] = [
		_p("crown", "headwear", Vector3(0,1.755,0.01), Vector3(0.29,0.085,0.23)),
		_p("brim", "headwear_shadow", Vector3(0,1.71,0.0), Vector3(0.35,0.025,0.29)),
		_p("ridge", "headwear_highlight", Vector3(0,1.808,0.0), Vector3(0.025,0.035,0.20)),
	]

	# Additional hair and clothing keep the same block vocabulary as the base.
	result["hair/buzz_cut"] = [
		_p("top", "hair", Vector3(0,1.716,0.01), Vector3(0.265,0.035,0.225)),
		_p("back", "hair_shadow", Vector3(0,1.635,0.119), Vector3(0.235,0.11,0.022)),
	]
	result["hair/curly_crop"] = [
		_p("top_left", "hair", Vector3(-0.085,1.73,0.005), Vector3(0.09,0.065,0.22)),
		_p("top_mid", "hair_highlight", Vector3(0,1.742,0.0), Vector3(0.09,0.075,0.23)),
		_p("top_right", "hair", Vector3(0.085,1.73,0.005), Vector3(0.09,0.065,0.22)),
		_p("back", "hair_shadow", Vector3(0,1.63,0.12), Vector3(0.25,0.14,0.025)),
	]
	result["hair/shoulder_bob"] = [
		_p("top", "hair", Vector3(0,1.725,0.01), Vector3(0.275,0.05,0.23)),
		_p("left", "hair", Vector3(-0.14,1.51,0.015), Vector3(0.04,0.39,0.22)),
		_p("right", "hair", Vector3(0.14,1.51,0.015), Vector3(0.04,0.39,0.22)),
		_p("back", "hair_shadow", Vector3(0,1.50,0.125), Vector3(0.25,0.40,0.03)),
	]
	result["hair/ponytail"] = [
		_p("top", "hair", Vector3(0,1.725,0.01), Vector3(0.27,0.05,0.23)),
		_p("back", "hair", Vector3(0,1.59,0.125), Vector3(0.24,0.20,0.03)),
		_p("tie", "hair_shadow", Vector3(0,1.47,0.15), Vector3(0.065,0.05,0.055)),
		_p("tail", "hair", Vector3(0,1.33,0.16), Vector3(0.08,0.25,0.065)),
	]
	result["facial_hair/sideburns"] = [
		_p("left", "facial_hair", Vector3(-0.13,1.53,-0.02), Vector3(0.025,0.18,0.13)),
		_p("right", "facial_hair", Vector3(0.13,1.53,-0.02), Vector3(0.025,0.18,0.13)),
	]
	result["tops/striped_sailor_sweater"] = [
		_p("collar", "top_shadow", Vector3(0,1.315,-0.015), Vector3(0.17,0.045,0.16)),
		_p("band_1", "top_accent", Vector3(0,1.18,-0.121), Vector3(0.425,0.026,0.018)),
		_p("band_2", "top_accent", Vector3(0,1.09,-0.121), Vector3(0.425,0.026,0.018)),
		_p("band_3", "top_accent", Vector3(0,1.00,-0.121), Vector3(0.425,0.026,0.018)),
	]
	result["tops/thermal_henley"] = [
		_p("collar", "top_shadow", Vector3(0,1.31,-0.02), Vector3(0.15,0.04,0.14)),
		_p("placket", "top_shadow", Vector3(0,1.22,-0.124), Vector3(0.045,0.15,0.018)),
		_p("buttons", "top_accent", Vector3(0,1.22,-0.136), Vector3(0.012,0.10,0.012)),
	]
	result["tops/company_polo"] = [
		_p("collar_left", "company_secondary", Vector3(-0.055,1.285,-0.121), Vector3(0.10,0.045,0.02), Vector3(0,0,-14)),
		_p("collar_right", "company_secondary", Vector3(0.055,1.285,-0.121), Vector3(0.10,0.045,0.02), Vector3(0,0,14)),
		_p("placket", "company_primary", Vector3(0,1.20,-0.125), Vector3(0.025,0.13,0.018)),
		_p("badge", "company_secondary", Vector3(0.13,1.15,-0.127), Vector3(0.07,0.055,0.018)),
	]
	result["tops/mechanic_shirt"] = [
		_p("collar_left", "top_accent", Vector3(-0.055,1.275,-0.122), Vector3(0.10,0.05,0.022), Vector3(0,0,-12)),
		_p("collar_right", "top_accent", Vector3(0.055,1.275,-0.122), Vector3(0.10,0.05,0.022), Vector3(0,0,12)),
		_p("placket", "top_shadow", Vector3(0,1.06,-0.124), Vector3(0.018,0.39,0.018)),
		_p("pockets", "top_accent", Vector3(0,1.12,-0.125), Vector3(0.30,0.075,0.018)),
		_p("patch", "company_secondary", Vector3(0.13,1.17,-0.138), Vector3(0.065,0.025,0.012)),
	]
	result["outerwear/bomber_jacket"] = [
		_p("body", "outerwear", Vector3(0,1.04,-0.005), Vector3(0.46,0.48,0.24)),
		_p("zip", "outerwear_shadow", Vector3(0,1.04,-0.133), Vector3(0.018,0.45,0.018)),
		_p("collar", "outerwear_highlight", Vector3(0,1.29,-0.02), Vector3(0.20,0.065,0.18)),
		_p("cuffs", "outerwear_shadow", Vector3(0,0.83,0), Vector3(0.70,0.04,0.18)),
		_p("hem", "outerwear_shadow", Vector3(0,0.80,-0.005), Vector3(0.46,0.045,0.24)),
	]
	result["outerwear/hi_vis_jacket"] = [
		_p("body", "outerwear", Vector3(0,1.04,-0.006), Vector3(0.46,0.54,0.24)),
		_p("placket", "outerwear_shadow", Vector3(0,1.04,-0.135), Vector3(0.025,0.50,0.018)),
		_p("band_upper", "reflective", Vector3(0,1.16,-0.137), Vector3(0.46,0.025,0.014)),
		_p("band_lower", "reflective", Vector3(0,0.96,-0.137), Vector3(0.46,0.025,0.014)),
		_p("arm_bands", "reflective", Vector3(0,0.95,-0.085), Vector3(0.70,0.025,0.17)),
	]
	result["outerwear/company_work_jacket"] = [
		_p("body", "company_primary", Vector3(0,1.04,-0.006), Vector3(0.46,0.52,0.24)),
		_p("collar", "company_secondary", Vector3(0,1.30,-0.02), Vector3(0.20,0.055,0.18)),
		_p("placket", "company_secondary", Vector3(0,1.05,-0.135), Vector3(0.02,0.46,0.018)),
		_p("patch", "company_secondary", Vector3(0.13,1.16,-0.138), Vector3(0.075,0.055,0.014)),
		_p("hem", "company_secondary", Vector3(0,0.78,-0.005), Vector3(0.46,0.035,0.24)),
	]
	result["outerwear/insulated_vest"] = [
		_p("body", "outerwear", Vector3(0,1.07,-0.127), Vector3(0.45,0.45,0.03)),
		_p("zip", "outerwear_shadow", Vector3(0,1.07,-0.147), Vector3(0.014,0.43,0.012)),
		_p("pockets", "outerwear_highlight", Vector3(0,0.94,-0.148), Vector3(0.32,0.075,0.012)),
		_p("bands", "outerwear_shadow", Vector3(0,1.11,-0.149), Vector3(0.44,0.025,0.012)),
	]
	result["trousers/cargo_trousers"] = [
		_p("pocket_left", "trouser_detail", Vector3(-0.165,0.52,-0.01), Vector3(0.035,0.18,0.15)),
		_p("pocket_right", "trouser_detail", Vector3(0.165,0.52,-0.01), Vector3(0.035,0.18,0.15)),
	] + _knee_parts("trouser_detail")
	result["trousers/company_work_trousers"] = [
		_p("stripe_left", "company_secondary", Vector3(-0.157,0.39,0), Vector3(0.012,0.75,0.17)),
		_p("stripe_right", "company_secondary", Vector3(0.157,0.39,0), Vector3(0.012,0.75,0.17)),
	] + _knee_parts("company_primary")
	result["trousers/mechanic_coveralls"] = [
		_p("bib", "trousers", Vector3(0,1.00,-0.126), Vector3(0.29,0.31,0.025)),
		_p("zip", "company_secondary", Vector3(0,1.02,-0.145), Vector3(0.014,0.24,0.012)),
		_p("strap_left", "trousers", Vector3(-0.10,1.22,-0.13), Vector3(0.04,0.22,0.02), Vector3(0,0,-5)),
		_p("strap_right", "trousers", Vector3(0.10,1.22,-0.13), Vector3(0.04,0.22,0.02), Vector3(0,0,5)),
		_p("pocket", "company_secondary", Vector3(0,1.05,-0.147), Vector3(0.13,0.075,0.012)),
	]
	result["footwear/short_rubber_boots"] = [
		_p("shaft_left", "footwear", Vector3(-0.085,0.17,0), Vector3(0.16,0.25,0.18)),
		_p("shaft_right", "footwear", Vector3(0.085,0.17,0), Vector3(0.16,0.25,0.18)),
		_p("toe_left", "footwear", Vector3(-0.085,0.07,-0.11), Vector3(0.16,0.14,0.10)),
		_p("toe_right", "footwear", Vector3(0.085,0.07,-0.11), Vector3(0.16,0.14,0.10)),
	]
	result["footwear/work_trainers"] = [
		_p("left", "footwear", Vector3(-0.085,0.065,-0.11), Vector3(0.16,0.13,0.11)),
		_p("right", "footwear", Vector3(0.085,0.065,-0.11), Vector3(0.16,0.13,0.11)),
		_p("soles", "footwear_detail", Vector3(0,0.018,-0.11), Vector3(0.33,0.025,0.115)),
	]
	result["headwear/baseball_cap"] = _baseball_cap_parts("headwear", "headwear_shadow")
	result["headwear/company_cap"] = _baseball_cap_parts("company_primary", "company_secondary") + [
		_p("badge", "company_secondary", Vector3(0,1.748,-0.126), Vector3(0.06,0.045,0.015)),
	]
	result["headwear/helmet_earmuffs"] = [
		_p("crown", "headwear", Vector3(0,1.755,0.01), Vector3(0.29,0.085,0.23)),
		_p("brim", "headwear_shadow", Vector3(0,1.71,0.0), Vector3(0.35,0.025,0.29)),
		_p("left", "headwear_shadow", Vector3(-0.165,1.57,0), Vector3(0.055,0.15,0.12)),
		_p("right", "headwear_shadow", Vector3(0.165,1.57,0), Vector3(0.055,0.15,0.12)),
		_p("band", "headwear", Vector3(0,1.67,0.10), Vector3(0.34,0.025,0.035)),
	]

	# Independent cosmetic slots. These combine with all clothing and uniforms.
	result["eyewear/wire_glasses"] = _glasses_parts("lens", 0.066, 0.045, 0.007)
	result["eyewear/square_glasses"] = _glasses_parts("lens", 0.072, 0.050, 0.011)
	result["eyewear/reading_glasses"] = _glasses_parts("lens", 0.065, 0.037, 0.008, -0.020)
	result["eyewear/sunglasses"] = _glasses_parts("dark_lens", 0.075, 0.050, 0.010)
	result["eyewear/aviator_glasses"] = _glasses_parts("dark_lens", 0.078, 0.055, 0.009) + [
		_p("top_bar", "eyewear", Vector3(0,1.621,-0.148), Vector3(0.17,0.008,0.009)),
	]
	result["eyewear/safety_glasses"] = _glasses_parts("safety_lens", 0.082, 0.050, 0.010) + [
		_p("shield", "safety_lens", Vector3(0,1.596,-0.153), Vector3(0.19,0.010,0.010)),
	]
	result["face_accessories/bent_pipe"] = [
		_p("stem", "wood", Vector3(0.052,1.515,-0.17), Vector3(0.016,0.014,0.095), Vector3(6,0,-10)),
		_p("bend", "wood", Vector3(0.067,1.493,-0.212), Vector3(0.016,0.045,0.016)),
		_p("bowl", "wood", Vector3(0.067,1.472,-0.218), Vector3(0.045,0.050,0.045)),
	]
	result["face_accessories/straight_pipe"] = [
		_p("stem", "wood", Vector3(0.052,1.515,-0.175), Vector3(0.016,0.014,0.105), Vector3(0,0,-10)),
		_p("bowl", "wood", Vector3(0.063,1.497,-0.225), Vector3(0.043,0.050,0.043)),
	]
	result["face_accessories/toothpick"] = [
		_p("toothpick", "wood", Vector3(0.065,1.515,-0.145), Vector3(0.14,0.010,0.010), Vector3(0,0,-10)),
	]
	result["face_accessories/pencil"] = [
		_p("body", "accessory", Vector3(0.07,1.515,-0.145), Vector3(0.15,0.014,0.014), Vector3(0,0,-8)),
		_p("tip", "wood", Vector3(0.147,1.504,-0.145), Vector3(0.025,0.010,0.010), Vector3(0,0,-8)),
	]
	result["neckwear/wool_scarf"] = [
		_p("band", "accessory", Vector3(0,1.34,0), Vector3(0.22,0.10,0.18)),
		_p("drop", "accessory", Vector3(0.075,1.18,-0.135), Vector3(0.09,0.28,0.025)),
	]
	result["neckwear/neckerchief"] = [
		_p("band", "accessory", Vector3(0,1.34,0), Vector3(0.19,0.055,0.16)),
		_p("knot", "accessory", Vector3(0,1.30,-0.13), Vector3(0.07,0.06,0.025)),
		_p("drop", "accessory", Vector3(0,1.22,-0.135), Vector3(0.11,0.12,0.022)),
	]
	result["neckwear/company_tie"] = [
		_p("knot", "company_secondary", Vector3(0,1.26,-0.137), Vector3(0.055,0.055,0.018)),
		_p("body", "company_primary", Vector3(0,1.10,-0.137), Vector3(0.045,0.27,0.018)),
	]
	result["neckwear/id_lanyard"] = [
		_p("left", "company_secondary", Vector3(-0.045,1.20,-0.136), Vector3(0.014,0.25,0.014), Vector3(0,0,-10)),
		_p("right", "company_secondary", Vector3(0.045,1.20,-0.136), Vector3(0.014,0.25,0.014), Vector3(0,0,10)),
		_p("card", "accessory", Vector3(0,1.05,-0.145), Vector3(0.10,0.075,0.014)),
	]
	result["neckwear/hearing_protection"] = [
		_p("band", "accessory", Vector3(0,1.31,0.09), Vector3(0.24,0.025,0.035)),
		_p("left", "accessory", Vector3(-0.125,1.30,0.045), Vector3(0.05,0.10,0.08)),
		_p("right", "accessory", Vector3(0.125,1.30,0.045), Vector3(0.05,0.10,0.08)),
	]
	result["handwear/leather_gloves"] = _glove_parts("accessory")
	result["handwear/rubber_gloves_blue"] = _glove_parts("accessory", true)
	result["handwear/rubber_gloves_yellow"] = _glove_parts("accessory", true)
	result["handwear/wool_gloves"] = _glove_parts("accessory")
	result["handwear/company_work_gloves"] = _glove_parts("company_primary", true)
	result["utility_accessories/tool_belt"] = [
		_p("belt", "accessory_shadow", Vector3(0,0.77,-0.01), Vector3(0.47,0.055,0.22)),
		_p("pouch_left", "accessory", Vector3(-0.23,0.72,-0.02), Vector3(0.09,0.17,0.12)),
		_p("pouch_right", "accessory", Vector3(0.23,0.72,-0.02), Vector3(0.09,0.17,0.12)),
		_p("hammer", "metal", Vector3(0.29,0.70,0.02), Vector3(0.035,0.25,0.035)),
	]
	result["utility_accessories/handheld_radio"] = [
		_p("radio", "accessory", Vector3(0.245,0.91,-0.08), Vector3(0.09,0.18,0.07)),
		_p("screen", "company_secondary", Vector3(0.245,0.94,-0.121), Vector3(0.055,0.045,0.012)),
		_p("antenna", "metal", Vector3(0.27,1.06,-0.08), Vector3(0.012,0.16,0.012)),
		_p("clip", "accessory_shadow", Vector3(0.20,0.93,-0.035), Vector3(0.02,0.11,0.04)),
	]
	result["utility_accessories/flashlight"] = [
		_p("body", "accessory", Vector3(0.245,0.81,-0.04), Vector3(0.055,0.22,0.055)),
		_p("lens", "metal", Vector3(0.245,0.92,-0.04), Vector3(0.075,0.045,0.075)),
		_p("clip", "accessory_shadow", Vector3(0.21,0.81,-0.04), Vector3(0.015,0.13,0.03)),
	]
	result["utility_accessories/clipboard"] = [
		_p("board", "accessory", Vector3(-0.30,0.78,0.0), Vector3(0.20,0.30,0.035)),
		_p("clip", "metal", Vector3(-0.30,0.91,-0.025), Vector3(0.075,0.035,0.018)),
		_p("paper", "company_secondary", Vector3(-0.30,0.78,-0.025), Vector3(0.16,0.22,0.012)),
	]
	result["utility_accessories/deck_knife"] = [
		_p("sheath", "accessory", Vector3(0.245,0.77,-0.03), Vector3(0.075,0.22,0.045)),
		_p("handle", "wood", Vector3(0.245,0.91,-0.03), Vector3(0.045,0.09,0.04)),
		_p("loop", "accessory_shadow", Vector3(0.245,0.83,0.02), Vector3(0.09,0.035,0.055)),
	]
	result["utility_accessories/key_ring"] = [
		_p("clip", "metal", Vector3(0.235,0.80,-0.07), Vector3(0.055,0.055,0.025)),
		_p("key_1", "metal", Vector3(0.225,0.72,-0.07), Vector3(0.018,0.12,0.018), Vector3(0,0,8)),
		_p("key_2", "metal", Vector3(0.255,0.72,-0.07), Vector3(0.018,0.12,0.018), Vector3(0,0,-8)),
	]
	return result


func _rain_jacket_parts() -> Array:
	return [
		_p("body", "outerwear", Vector3(0,1.05,-0.006), Vector3(0.46,0.54,0.24)),
		_p("hood", "outerwear", Vector3(0,1.58,0.13), Vector3(0.31,0.25,0.055)),
		_p("storm_flap", "outerwear_shadow", Vector3(0,1.10,-0.135), Vector3(0.055,0.36,0.025)),
		_p("band", "reflective", Vector3(0,0.93,-0.136), Vector3(0.46,0.028,0.015)),
		_p("arm_band_left", "reflective", Vector3(-0.275,0.97,-0.083), Vector3(0.13,0.028,0.17)),
		_p("arm_band_right", "reflective", Vector3(0.275,0.97,-0.083), Vector3(0.13,0.028,0.17)),
	]


func _knee_parts(role: String) -> Array:
	return [
		_p("knee_left", role, Vector3(-0.085,0.42,-0.088), Vector3(0.14,0.13,0.018)),
		_p("knee_right", role, Vector3(0.085,0.42,-0.088), Vector3(0.14,0.13,0.018)),
	]


func _work_boot_parts() -> Array:
	return [
		_p("toe_left", "footwear", Vector3(-0.085,0.08,-0.11), Vector3(0.16,0.15,0.10)),
		_p("toe_right", "footwear", Vector3(0.085,0.08,-0.11), Vector3(0.16,0.15,0.10)),
		_p("cuff_left", "footwear_detail", Vector3(-0.085,0.27,0), Vector3(0.16,0.035,0.18)),
		_p("cuff_right", "footwear_detail", Vector3(0.085,0.27,0), Vector3(0.16,0.035,0.18)),
	]


func _sea_boot_parts() -> Array:
	return [
		_p("shaft_left", "footwear", Vector3(-0.085,0.25,0), Vector3(0.16,0.40,0.18)),
		_p("shaft_right", "footwear", Vector3(0.085,0.25,0), Vector3(0.16,0.40,0.18)),
		_p("toe_left", "footwear", Vector3(-0.085,0.08,-0.11), Vector3(0.16,0.15,0.10)),
		_p("toe_right", "footwear", Vector3(0.085,0.08,-0.11), Vector3(0.16,0.15,0.10)),
	]


func _beanie_parts() -> Array:
	return [
		_p("crown", "headwear", Vector3(0,1.755,0.005), Vector3(0.28,0.09,0.235)),
		_p("cuff", "headwear_shadow", Vector3(0,1.715,0.005), Vector3(0.29,0.035,0.24)),
	]


func _baseball_cap_parts(crown_role: String, detail_role: String) -> Array:
	return [
		_p("crown", crown_role, Vector3(0,1.75,0.005), Vector3(0.29,0.085,0.235)),
		_p("brim", detail_role, Vector3(0,1.705,-0.16), Vector3(0.21,0.025,0.12)),
		_p("band", detail_role, Vector3(0,1.715,0.005), Vector3(0.295,0.025,0.24)),
	]


func _glasses_parts(lens_role: String, lens_width: float, lens_height: float, frame: float, y_offset := 0.0) -> Array:
	var y := 1.605 + y_offset
	return [
		_p("lens_left", lens_role, Vector3(-0.065,y,-0.149), Vector3(lens_width,lens_height,0.012)),
		_p("lens_right", lens_role, Vector3(0.065,y,-0.149), Vector3(lens_width,lens_height,0.012)),
		_p("bridge", "eyewear", Vector3(0,y,-0.157), Vector3(0.055,frame,frame)),
		_p("arm_left", "eyewear", Vector3(-0.128,y,0.0), Vector3(frame,frame,0.27)),
		_p("arm_right", "eyewear", Vector3(0.128,y,0.0), Vector3(frame,frame,0.27)),
	]


func _glove_parts(role: String, long_cuff := false) -> Array:
	var cuff_height := 0.10 if long_cuff else 0.055
	return [
		_p("left", role, Vector3(-0.275,0.765,-0.005), Vector3(0.135,0.15,0.175)),
		_p("right", role, Vector3(0.275,0.765,-0.005), Vector3(0.135,0.15,0.175)),
		_p("cuff_left", role, Vector3(-0.275,0.85,0), Vector3(0.145,cuff_height,0.18)),
		_p("cuff_right", role, Vector3(0.275,0.85,0), Vector3(0.145,cuff_height,0.18)),
	]


func _p(name: String, role: String, position: Vector3, size: Vector3, rotation := Vector3.ZERO) -> Dictionary:
	return {
		"name": name,
		"role": role,
		"position": [position.x, position.y, position.z],
		"rotation_degrees": [rotation.x, rotation.y, rotation.z],
		"mesh": _box_mesh(size),
		"color": [0.5,0.5,0.5],
		"roughness": 0.88,
		"metallic": 0.0,
		"collision": "none",
	}


func _box_mesh(size: Vector3) -> Dictionary:
	var h := size * 0.5
	return {
		"vertices": [
			-h.x,-h.y,-h.z, h.x,-h.y,-h.z, h.x,h.y,-h.z, -h.x,h.y,-h.z,
			-h.x,-h.y,h.z, h.x,-h.y,h.z, h.x,h.y,h.z, -h.x,h.y,h.z,
		],
		"indices": BOX_INDICES.duplicate(),
	}
