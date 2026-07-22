extends SceneTree

## Curated wardrobe author for the approved articulated character. Garments
## are fitted shells around individual body anchors and remain ordinary JSON
## meshes at runtime. This intentionally replaces the rejected block wardrobe.

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
		var pieces := String(key).split("/")
		if pieces.size() != 2:
			continue
		var directory := "%s/%s" % [OUTPUT_ROOT, pieces[0]]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		var path := "%s/%s.json" % [directory, pieces[1]]
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			push_error("CharacterFittedWardrobeAuthor: cannot write %s" % path)
			quit(1)
			return
		file.store_string(JSON.stringify({
			"name": "character_%s_%s" % [pieces[0], pieces[1]],
			"slot": pieces[0],
			"parts": models[key],
		}, "  "))
		file.close()
		written += 1
	print("CharacterFittedWardrobeAuthor: wrote %d fitted models" % written)
	quit()


func _recipes() -> Dictionary:
	return {
		"hair/cropped": _cropped_hair(),
		"hair/side_part": _side_part_hair(),
		"facial_hair/moustache": _moustache(),
		"facial_hair/short_beard": _short_beard(),
		"tops/wool_sweater": _sweater("icelander_knit"),
		"tops/plain_wool_sweater": _sweater("plain_wool"),
		"tops/roll_neck_sweater": _roll_neck_sweater(),
		"tops/work_shirt": _work_shirt(),
		"outerwear/deck_jacket": _jacket("work_twill", false),
		"outerwear/rain_jacket_yellow": _oilskin_jacket(),
		"outerwear/rain_jacket_orange": _oilskin_jacket(),
		"outerwear/shore_suit_jacket": _shore_suit_jacket(),
		"outerwear/wool_peacoat": _wool_peacoat(),
		"outerwear/high_visibility_vest": _high_visibility_vest(),
		"trousers/work_trousers": _trousers("work_twill", false),
		"trousers/denim_trousers": _trousers("work_denim", false),
		"trousers/rain_trousers": _trousers("oilskin", true),
		"trousers/bib_overalls": _bib_overalls(),
		"trousers/shore_suit_trousers": _trousers("work_twill", false),
		"footwear/deck_boots": _boots("work_rubber", false),
		"footwear/sea_boots": _boots("work_rubber", true),
		"footwear/work_boots": _boots("work_leather", false),
		"footwear/yellow_rubber_boots": _boots("work_rubber", true),
		"headwear/watch_cap": _watch_cap(),
		"headwear/flat_cap": _flat_cap(),
		"headwear/souwester": _souwester(),
		"headwear/peaked_cap": _peaked_cap(),
		"headwear/hard_hat": _hard_hat(),
		"eyewear/wire_glasses": _wire_glasses(),
		"face_accessories/bent_pipe": _bent_pipe(),
		"neckwear/work_tie": _work_tie(),
		"neckwear/wool_scarf": _wool_scarf(),
		"handwear/leather_gloves": _gloves("work_leather", false),
		"handwear/rubber_gloves_yellow": _gloves("work_rubber", true),
		"handwear/rubber_gloves_blue": _gloves("work_rubber", true),
		"utility_accessories/handheld_radio": _radio(),
		"utility_accessories/tool_belt": _tool_belt(),
	}


func _sweater(profile: String) -> Array:
	var parts: Array = [
		_part("torso", "chest", _loft_y([
			_ring(-0.040, 0.170, 0.107, 0.024, 0.875),
			_ring(0.060, 0.174, 0.110, 0.026, 0.76),
			_ring(0.245, 0.178, 0.112, 0.027, 0.38),
			_ring(0.370, 0.170, 0.108, 0.025, 0.08),
		]), profile),
		_part("hem", "chest", _loft_y([
			_ring(-0.050, 0.176, 0.112, 0.025, 1.00),
			_ring(0.005, 0.176, 0.112, 0.025, 0.89),
		]), profile),
		_part("crew_collar", "chest", _loft_y([
			_ring(0.365, 0.082, 0.070, 0.018, 0.04),
			_ring(0.418, 0.076, 0.066, 0.017, 0.00),
		]), profile),
	]
	for side in ["left", "right"]:
		parts.append(_part("upper_sleeve_%s" % side, "arm_%s" % side, _loft_y([
			_ring(0.035, 0.062, 0.069, 0.016, 0.04),
			_ring(-0.100, 0.061, 0.068, 0.015, 0.27),
			_ring(-0.305, 0.057, 0.064, 0.014, 0.58),
		]), profile))
		parts.append(_part("lower_sleeve_%s" % side, "forearm_%s" % side, _loft_y([
			_ring(0.025, 0.058, 0.065, 0.014, 0.56),
			_ring(-0.120, 0.056, 0.063, 0.013, 0.76),
			_ring(-0.220, 0.053, 0.060, 0.012, 0.89),
		]), profile))
		parts.append(_part("cuff_%s" % side, "forearm_%s" % side, _loft_y([
			_ring(-0.218, 0.057, 0.064, 0.013, 0.89),
			_ring(-0.258, 0.055, 0.062, 0.012, 1.00),
		]), profile))
	return parts


func _roll_neck_sweater() -> Array:
	var parts := _sweater("plain_wool")
	parts[2] = _part("roll_neck", "chest", _loft_y([
		_ring(0.350,0.083,0.071,0.018,0.18),_ring(0.430,0.079,0.068,0.017,0.02),
	]), "plain_wool", "secondary")
	return parts


func _work_shirt() -> Array:
	var parts := _sweater("work_twill")
	parts[0]["name"] = "shirt_body"
	parts[1]["name"] = "shirt_tail"
	parts[2] = _part("collar_left", "chest", _extrude_xy([
		Vector2(-0.078,0.365), Vector2(-0.008,0.342), Vector2(-0.012,0.292), Vector2(-0.094,0.348),
	], -0.119, -0.105), "work_twill", "light")
	parts.append(_part("collar_right", "chest", _extrude_xy([
		Vector2(0.078,0.365), Vector2(0.008,0.342), Vector2(0.012,0.292), Vector2(0.094,0.348),
	], -0.119, -0.105), "work_twill", "light"))
	parts.append(_part("button_placket", "chest", _box(Vector3(0.022,0.285,0.014)), "", "secondary", Vector3(0,0.18,-0.119)))
	parts.append(_part("breast_pocket", "chest", _box(Vector3(0.075,0.075,0.012)), "work_twill", "secondary", Vector3(-0.09,0.19,-0.119)))
	return parts


func _jacket(profile: String, hooded: bool) -> Array:
	var parts: Array = [
		_part("jacket_body", "chest", _loft_y([
			_ring(-0.070,0.190,0.126,0.028,0.92),
			_ring(0.080,0.194,0.130,0.030,0.68),
			_ring(0.275,0.191,0.128,0.030,0.28),
			_ring(0.372,0.177,0.116,0.027,0.05),
		]), profile),
		_part("storm_placket", "chest", _box(Vector3(0.030,0.330,0.018)), profile, "secondary", Vector3(0,0.165,-0.137)),
		_part("collar", "chest", _loft_y([
			_ring(0.344,0.094,0.079,0.019,0.15), _ring(0.420,0.086,0.074,0.018,0.01),
		]), profile, "secondary"),
	]
	for side in ["left", "right"]:
		parts.append(_part("jacket_arm_%s" % side, "arm_%s" % side, _loft_y([
			_ring(0.040,0.070,0.077,0.017,0.05), _ring(-0.120,0.068,0.075,0.016,0.36), _ring(-0.310,0.062,0.069,0.015,0.67),
		]), profile))
		parts.append(_part("jacket_forearm_%s" % side, "forearm_%s" % side, _loft_y([
			_ring(0.030,0.064,0.071,0.015,0.63), _ring(-0.120,0.061,0.068,0.014,0.81), _ring(-0.250,0.057,0.064,0.013,0.98),
		]), profile))
	if hooded:
		parts.append(_part("oilskin_hood", "head", _loft_y([
			_ring(-0.020,0.124,0.118,0.028,0.78), _ring(0.130,0.132,0.122,0.030,0.38), _ring(0.245,0.092,0.092,0.024,0.10),
		]), profile, "primary", Vector3(0,0,0.025)))
	return parts


func _oilskin_jacket() -> Array:
	# Proper working oilskins are a loose waterproof shell, not a second head.
	# The old raised hood enclosed the face and collided with every hat and pair
	# of glasses. Keep the hood folded behind the collar until a future garment
	# state explicitly raises it.
	var parts: Array = [
		_part("oilskin_body", "chest", _loft_y([
			_ring(-0.070,0.180,0.120,0.027,0.94),
			_ring(0.060,0.183,0.124,0.028,0.73),
			_ring(0.250,0.181,0.122,0.028,0.32),
			_ring(0.365,0.168,0.111,0.025,0.06),
		]), "oilskin"),
		# The shell itself closes the front. A narrow storm flap gives the coat
		# a readable waterproof closure without turning the entire chest into a
		# pair of rigid, overlapping armour plates.
		_part("storm_flap", "chest", _extrude_xy([
			Vector2(-0.020,-0.045),Vector2(-0.020,0.305),
			Vector2(0.032,0.305),Vector2(0.032,-0.045),
		],-0.153,-0.140), "oilskin", "secondary"),
		_part("storm_collar", "chest", _loft_y([
			_ring(0.340,0.092,0.078,0.018,0.16),
			_ring(0.412,0.084,0.072,0.017,0.02),
		]), "oilskin", "secondary"),
		# A flattened six-sided roll at the rear reads as a stowed hood without
		# hiding facial hair, glasses, caps or the sou'wester.
		_part("folded_hood", "chest", _extrude_xy([
			Vector2(-0.090,0.378),Vector2(-0.143,0.323),
			Vector2(-0.128,0.257),Vector2(0.128,0.257),
			Vector2(0.143,0.323),Vector2(0.090,0.378),
		],0.112,0.158), "oilskin", "secondary"),
		_part("pocket_flap_left", "chest", _extrude_xy([
			Vector2(-0.158,0.030),Vector2(-0.074,0.030),
			Vector2(-0.078,-0.018),Vector2(-0.154,-0.024),
		],-0.154,-0.142), "oilskin", "secondary"),
		_part("pocket_flap_right", "chest", _extrude_xy([
			Vector2(0.074,0.030),Vector2(0.158,0.030),
			Vector2(0.154,-0.024),Vector2(0.078,-0.018),
		],-0.154,-0.143), "oilskin", "secondary"),
	]
	for snap_index in range(3):
		parts.append(_part(
			"storm_snap_%d" % snap_index,
			"chest",
			_box(Vector3(0.018,0.018,0.010)),
			"oilskin",
			"dark",
			Vector3(0.012,0.080 + float(snap_index) * 0.082,-0.153)
		))
	for side in ["left", "right"]:
		parts.append(_part("oilskin_arm_%s" % side, "arm_%s" % side, _loft_y([
			_ring(0.040,0.068,0.075,0.016,0.06),
			_ring(-0.125,0.066,0.073,0.016,0.38),
			_ring(-0.310,0.060,0.067,0.014,0.70),
		]), "oilskin"))
		parts.append(_part("oilskin_forearm_%s" % side, "forearm_%s" % side, _loft_y([
			_ring(0.030,0.062,0.069,0.014,0.63),
			_ring(-0.120,0.059,0.066,0.014,0.82),
			_ring(-0.250,0.055,0.062,0.013,0.98),
		]), "oilskin"))
	return parts


func _shore_suit_jacket() -> Array:
	# A restrained late-20th-century company suit: fitted shell, short notched
	# lapels, modest shoulder line and proper articulated sleeves. The shirt and
	# tie remain visible instead of being buried under a solid front block.
	var parts: Array = [
		_part("suit_body", "chest", _loft_y([
			_ring(-0.060,0.184,0.120,0.027,0.94),
			_ring(0.085,0.188,0.123,0.028,0.68),
			_ring(0.270,0.184,0.120,0.028,0.30),
			_ring(0.365,0.168,0.108,0.025,0.08),
		]), "work_twill"),
		_part("lapel_left", "chest", _extrude_xy([
			Vector2(-0.020,0.347),Vector2(-0.102,0.300),Vector2(-0.064,0.165),Vector2(-0.012,0.245),
		],-0.134,-0.119), "work_twill", "secondary"),
		_part("lapel_right", "chest", _extrude_xy([
			Vector2(0.020,0.347),Vector2(0.102,0.300),Vector2(0.064,0.165),Vector2(0.012,0.245),
		],-0.134,-0.119), "work_twill", "secondary"),
		_part("lower_button", "chest", _box(Vector3(0.013,0.013,0.010)), "", "light", Vector3(0,0.115,-0.137)),
		_part("breast_welt", "chest", _box(Vector3(0.072,0.010,0.010)), "", "secondary", Vector3(-0.092,0.245,-0.136), Vector3(0,0,-7)),
	]
	for side in ["left", "right"]:
		parts.append(_part("suit_arm_%s" % side, "arm_%s" % side, _loft_y([
			_ring(0.040,0.066,0.073,0.016,0.06),_ring(-0.125,0.063,0.070,0.015,0.38),_ring(-0.310,0.058,0.065,0.014,0.70),
		]), "work_twill"))
		parts.append(_part("suit_forearm_%s" % side, "forearm_%s" % side, _loft_y([
			_ring(0.025,0.059,0.066,0.014,0.68),_ring(-0.120,0.057,0.064,0.013,0.84),_ring(-0.245,0.054,0.061,0.012,0.98),
		]), "work_twill"))
	return parts


func _wool_peacoat() -> Array:
	var parts := _jacket("plain_wool", false)
	parts[0]["name"] = "peacoat_body"
	# Two overlapping front panels give the coat a readable tailored closure. A
	# single centred box looked like a rigid bib and opened a black trench down
	# the torso when the actor moved.
	parts[1] = _part("double_breasted_front_left", "chest", _extrude_xy([
		Vector2(-0.174,-0.055),Vector2(-0.174,0.300),Vector2(0.004,0.318),Vector2(-0.014,-0.055),
	],-0.147,-0.121), "plain_wool", "primary")
	parts[2] = _part("double_breasted_front_right", "chest", _extrude_xy([
		Vector2(-0.025,-0.055),Vector2(-0.004,0.318),Vector2(0.174,0.300),Vector2(0.174,-0.055),
	],-0.149,-0.122), "plain_wool", "primary")
	parts.append(_part("broad_collar_back", "chest", _loft_y([
		_ring(0.337,0.119,0.089,0.020,0.18),_ring(0.414,0.091,0.076,0.018,0.02),
	]), "plain_wool", "secondary"))
	parts.append(_part("broad_lapel_left", "chest", _extrude_xy([
		Vector2(-0.010,0.335),Vector2(-0.145,0.285),Vector2(-0.075,0.145),Vector2(-0.018,0.232),
	],-0.158,-0.143), "plain_wool", "secondary"))
	parts.append(_part("broad_lapel_right", "chest", _extrude_xy([
		Vector2(0.010,0.335),Vector2(0.145,0.285),Vector2(0.075,0.145),Vector2(0.018,0.232),
	],-0.159,-0.144), "plain_wool", "secondary"))
	for x in [-0.045,0.045]:
		for y in [0.070,0.145,0.220]:
			parts.append(_part("coat_button_%s_%s" % [str(x),str(y)], "chest", _box(Vector3(0.014,0.014,0.010)), "", "light", Vector3(x,y,-0.165)))
	return parts


func _high_visibility_vest() -> Array:
	return [
		_part("vest_body", "chest", _loft_y([
			_ring(-0.045,0.184,0.119,0.026,0.94),_ring(0.115,0.187,0.122,0.028,0.61),_ring(0.345,0.169,0.109,0.025,0.08),
		]), "oilskin"),
		# The dark V and split reflective tape expose the garment below and keep
		# this recognisable as an open waistcoat rather than a yellow chest box.
		_part("vest_neck_opening", "chest", _extrude_xy([
			Vector2(-0.112,0.349),Vector2(0.112,0.349),Vector2(0.000,0.205),
		],-0.142,-0.128), "", "dark"),
		_part("vest_opening", "chest", _box(Vector3(0.027,0.250,0.014)), "", "dark", Vector3(0,0.080,-0.143)),
		_part("reflective_band_upper_left", "chest", _box(Vector3(0.151,0.026,0.012)), "", "light", Vector3(-0.095,0.225,-0.145)),
		_part("reflective_band_upper_right", "chest", _box(Vector3(0.151,0.026,0.012)), "", "light", Vector3(0.095,0.225,-0.145)),
		_part("reflective_band_lower_left", "chest", _box(Vector3(0.159,0.026,0.012)), "", "light", Vector3(-0.099,0.050,-0.145)),
		_part("reflective_band_lower_right", "chest", _box(Vector3(0.159,0.026,0.012)), "", "light", Vector3(0.099,0.050,-0.145)),
		_part("reflective_shoulder_left", "chest", _box(Vector3(0.026,0.112,0.012)), "", "light", Vector3(-0.117,0.290,-0.143), Vector3(0,0,-18)),
		_part("reflective_shoulder_right", "chest", _box(Vector3(0.026,0.112,0.012)), "", "light", Vector3(0.117,0.290,-0.143), Vector3(0,0,18)),
	]


func _trousers(profile: String, bib: bool) -> Array:
	var parts: Array = []
	for side in ["left", "right"]:
		parts.append(_part("thigh_%s" % side, "leg_%s" % side, _loft_y([
			_ring(0.035,0.078,0.091,0.018,0.02), _ring(-0.180,0.075,0.087,0.017,0.48), _ring(-0.405,0.069,0.080,0.016,0.94),
		]), profile))
		parts.append(_part("lower_leg_%s" % side, "shin_%s" % side, _loft_y([
			_ring(0.030,0.070,0.081,0.016,0.02), _ring(-0.175,0.067,0.077,0.015,0.52), _ring(-0.375,0.061,0.071,0.014,0.96),
		]), profile))
	if bib:
		parts.append(_part("work_bib", "chest", _extrude_xy([
			Vector2(-0.125,-0.035),Vector2(0.125,-0.035),Vector2(0.108,0.245),Vector2(-0.108,0.245),
		], -0.124,-0.105), profile, "primary"))
		parts.append(_part("bib_pocket", "chest", _box(Vector3(0.100,0.085,0.014)), profile, "secondary", Vector3(0,0.115,-0.135)))
	return parts


func _bib_overalls() -> Array:
	return _trousers("work_denim", true)


func _boots(profile: String, tall: bool) -> Array:
	var parts: Array = []
	for side in ["left", "right"]:
		var shaft_top := 0.030
		var shaft_bottom := -0.255 if tall else -0.105
		parts.append(_part("shaft_%s" % side, "shin_%s" % side, _loft_y([
			_ring(shaft_top,0.073,0.083,0.016,0.02), _ring(shaft_bottom,0.069,0.079,0.015,0.76),
		]), profile))
		parts.append(_part("foot_%s" % side, "foot_%s" % side, _loft_y([
			_ring(-0.105,0.073,0.150,0.018,0.98), _ring(0.012,0.071,0.145,0.017,0.78),
		]), profile))
		parts.append(_part("sole_%s" % side, "foot_%s" % side, _box(Vector3(0.150,0.025,0.218)), "", "dark", Vector3(0,-0.108,-0.042)))
	return parts


func _watch_cap() -> Array:
	return [
		_part("knit_crown", "head", _loft_y([
			_ring(0.155,0.108,0.104,0.024,0.78), _ring(0.235,0.096,0.094,0.023,0.28), _ring(0.280,0.060,0.060,0.018,0.05),
		]), "plain_wool"),
		_part("folded_band", "head", _loft_y([
			_ring(0.145,0.111,0.107,0.025,1.00), _ring(0.190,0.111,0.107,0.025,0.82),
		]), "plain_wool", "secondary"),
	]


func _flat_cap() -> Array:
	return [
		_part("cap_crown", "head", _loft_y([
			_ring(0.165,0.112,0.104,0.026,0.90), _ring(0.220,0.120,0.112,0.030,0.42), _ring(0.252,0.082,0.078,0.022,0.10),
		]), "work_twill"),
		_part("cap_peak", "head", _slab_xz([
			Vector2(-0.092,-0.095),Vector2(0.092,-0.095),Vector2(0.075,-0.164),Vector2(-0.075,-0.164),
		],0.158,0.176), "work_twill", "dark"),
	]


func _souwester() -> Array:
	return [
		_part("rain_crown", "head", _loft_y([
			_ring(0.118,0.112,0.108,0.026,0.82), _ring(0.200,0.106,0.101,0.025,0.35), _ring(0.250,0.060,0.061,0.018,0.05),
		]), "oilskin"),
		# A sou'wester has a short forward brim and a long rain-shedding tail at
		# the back. The old outline had those proportions reversed and read as a
		# construction helmet perched over a dark plate.
		_part("wide_brim", "head", _slab_xz([
			Vector2(-0.115,-0.112),Vector2(0.115,-0.112),
			Vector2(0.138,-0.040),Vector2(0.150,0.145),
			Vector2(0.105,0.215),Vector2(-0.105,0.215),
			Vector2(-0.150,0.145),Vector2(-0.138,-0.040),
		],0.108,0.126), "oilskin", "secondary"),
		_part("neck_flap", "head", _extrude_xy([
			Vector2(-0.118,0.126),Vector2(0.118,0.126),Vector2(0.102,-0.080),Vector2(-0.102,-0.080),
		],0.110,0.132), "oilskin", "primary"),
	]


func _peaked_cap() -> Array:
	return [
		_part("cap_crown", "head", _loft_y([
			_ring(0.158,0.108,0.102,0.024,0.90),_ring(0.207,0.116,0.108,0.028,0.48),_ring(0.240,0.092,0.084,0.022,0.14),
		]), "work_twill"),
		_part("cap_band", "head", _loft_y([
			_ring(0.148,0.111,0.105,0.025,0.96),_ring(0.177,0.112,0.106,0.025,0.82),
		]), "work_twill", "secondary"),
		_part("cap_peak", "head", _slab_xz([
			Vector2(-0.088,-0.096),Vector2(0.088,-0.096),Vector2(0.072,-0.174),Vector2(-0.072,-0.174),
		],0.146,0.164), "work_twill", "dark"),
		_part("cap_badge", "head", _extrude_xy([
			Vector2(-0.018,0.204),Vector2(0,0.224),Vector2(0.018,0.204),Vector2(0,0.184),
		],-0.112,-0.103), "", "light"),
	]


func _hard_hat() -> Array:
	return [
		_part("helmet_crown", "head", _loft_y([
			_ring(0.152,0.108,0.102,0.024,0.90),_ring(0.218,0.110,0.104,0.025,0.45),_ring(0.278,0.057,0.060,0.017,0.08),
		]), "oilskin"),
		_part("helmet_brim", "head", _slab_xz([
			Vector2(-0.132,-0.125),Vector2(0.132,-0.125),Vector2(0.132,0.112),Vector2(-0.132,0.112),
		],0.145,0.165), "oilskin", "secondary"),
		_part("helmet_ridge", "head", _box(Vector3(0.026,0.060,0.160)), "", "secondary", Vector3(0,0.228,-0.005)),
	]


func _cropped_hair() -> Array:
	return [
		_part("cropped_top", "head", _loft_y([
			_ring(0.150,0.100,0.096,0.024,0.82), _ring(0.222,0.100,0.096,0.024,0.18), _ring(0.245,0.070,0.067,0.020,0.05),
		]), "", "primary"),
	]


func _side_part_hair() -> Array:
	var result := _cropped_hair()
	result.append(_part("side_part", "head", _extrude_xy([
		Vector2(-0.102,0.226),Vector2(0.030,0.226),Vector2(0.075,0.190),Vector2(-0.102,0.183),
	],-0.106,-0.096), "", "light"))
	return result


func _moustache() -> Array:
	return [_part("harbour_moustache", "head", _extrude_xy([
		Vector2(-0.058,0.070),Vector2(-0.012,0.080),Vector2(0,0.066),Vector2(0.012,0.080),Vector2(0.058,0.070),Vector2(0.039,0.050),Vector2(0,0.058),Vector2(-0.039,0.050),
	],-0.108,-0.099), "", "primary")]


func _short_beard() -> Array:
	return [
		_part("short_beard", "head", _extrude_xy([
			Vector2(-0.082,0.070),Vector2(-0.072,-0.003),Vector2(-0.036,-0.025),Vector2(0,-0.036),Vector2(0.036,-0.025),Vector2(0.072,-0.003),Vector2(0.082,0.070),Vector2(0.048,0.044),Vector2(0,0.035),Vector2(-0.048,0.044),
		],-0.107,-0.097), "", "primary"),
		_moustache()[0],
	]


func _wire_glasses() -> Array:
	var parts: Array = []
	for side_value in [-1.0,1.0]:
		var side: String = "left" if float(side_value) < 0.0 else "right"
		var x: float = 0.041 * float(side_value)
		parts.append(_part("lens_%s" % side,"head",_octagonal_ring(0.035,0.025,0.003),"","secondary",Vector3(x,0.127,-0.105)))
	parts.append(_part("bridge","head",_box(Vector3(0.025,0.004,0.004)),"","secondary",Vector3(0,0.127,-0.108)))
	return parts


func _bent_pipe() -> Array:
	return [
		_part("pipe_stem", "head", _box(Vector3(0.065,0.008,0.008)), "", "dark", Vector3(0.050,0.047,-0.115), Vector3(0,0,-18)),
		_part("pipe_drop", "head", _box(Vector3(0.010,0.055,0.010)), "", "dark", Vector3(0.082,0.022,-0.116), Vector3(0,0,8)),
		_part("pipe_bowl", "head", _loft_y([_ring(-0.022,0.019,0.019,0.005,0.9),_ring(0.018,0.026,0.026,0.006,0.2)]), "work_leather", "primary", Vector3(0.086,-0.004,-0.116)),
	]


func _work_tie() -> Array:
	return [
		_part("tie_knot", "chest", _extrude_xy([
			Vector2(-0.024,0.340),Vector2(0.024,0.340),Vector2(0.017,0.305),Vector2(-0.017,0.305),
		],-0.137,-0.128), "work_twill", "primary"),
		_part("tie_blade", "chest", _extrude_xy([
			Vector2(-0.016,0.305),Vector2(0.016,0.305),Vector2(0.025,0.135),Vector2(0,0.105),Vector2(-0.025,0.135),
		],-0.136,-0.127), "work_twill", "primary"),
	]


func _wool_scarf() -> Array:
	return [
		_part("scarf_loop", "chest", _loft_y([
			_ring(0.345,0.095,0.078,0.019,0.24),_ring(0.415,0.088,0.074,0.018,0.02),
		]), "plain_wool", "primary"),
		_part("scarf_end_left", "chest", _extrude_xy([
			Vector2(-0.075,0.350),Vector2(-0.018,0.350),Vector2(-0.026,0.105),Vector2(-0.084,0.118),
		],-0.137,-0.124), "plain_wool", "primary"),
		_part("scarf_end_right", "chest", _extrude_xy([
			Vector2(0.018,0.350),Vector2(0.075,0.350),Vector2(0.086,0.170),Vector2(0.028,0.154),
		],-0.139,-0.126), "plain_wool", "secondary"),
	]


func _gloves(profile: String, long_cuff: bool) -> Array:
	var parts: Array = []
	for side in ["left","right"]:
		parts.append(_part("glove_%s" % side,"hand_%s" % side,_loft_y([
			_ring(-0.118,0.050,0.060,0.012,0.95),_ring(0.010,0.050,0.057,0.012,0.50),
		]),profile))
		if long_cuff:
			parts.append(_part("long_cuff_%s" % side,"forearm_%s" % side,_loft_y([
				_ring(-0.260,0.061,0.068,0.014,0.95),_ring(-0.170,0.065,0.072,0.015,0.70),
			]),profile,"primary"))
	return parts


func _radio() -> Array:
	return [
		_part("radio_body","chest",_box(Vector3(0.050,0.085,0.025)),"","dark",Vector3(0.135,0.105,-0.130)),
		_part("radio_screen","chest",_box(Vector3(0.028,0.020,0.006)),"","light",Vector3(0.135,0.122,-0.147)),
		_part("radio_antenna","chest",_box(Vector3(0.006,0.080,0.006)),"","dark",Vector3(0.153,0.185,-0.132),Vector3(0,0,-8)),
	]


func _tool_belt() -> Array:
	return [
		_part("belt_front", "chest", _box(Vector3(0.345,0.030,0.026)), "work_leather", "dark", Vector3(0,-0.030,-0.126)),
		_part("belt_buckle", "chest", _box(Vector3(0.038,0.038,0.014)), "", "light", Vector3(0,-0.030,-0.148)),
		_part("tool_pouch", "chest", _box(Vector3(0.080,0.105,0.038)), "work_leather", "primary", Vector3(0.135,-0.070,-0.137)),
		_part("tool_handle", "chest", _box(Vector3(0.018,0.145,0.018)), "work_leather", "secondary", Vector3(-0.130,-0.030,-0.145), Vector3(0,0,-8)),
	]


func _part(name: String, anchor: String, mesh: Dictionary, texture_profile := "", palette_channel := "primary", position := Vector3.ZERO, rotation := Vector3.ZERO) -> Dictionary:
	return {
		"name": name,
		"anchor": anchor,
		"mesh": mesh,
		"texture_profile": texture_profile,
		"palette_channel": palette_channel,
		"position": _v3(position),
		"rotation_degrees": _v3(rotation),
		"color": [1.0,1.0,1.0,1.0],
		"roughness": 0.9,
		"metallic": 0.0,
		"collision": "none",
	}


func _ring(y: float, half_x: float, half_z: float, chamfer: float, v: float) -> Dictionary:
	return {"y":y,"half_x":half_x,"half_z":half_z,"chamfer":chamfer,"v":v}


func _ring_points(spec: Dictionary) -> Array[Vector3]:
	var y := float(spec.y)
	var hx := float(spec.half_x)
	var hz := float(spec.half_z)
	var c := minf(float(spec.chamfer), minf(hx,hz) * 0.48)
	return [
		Vector3(-hx+c,y,-hz),Vector3(hx-c,y,-hz),Vector3(hx,y,-hz+c),Vector3(hx,y,hz-c),
		Vector3(hx-c,y,hz),Vector3(-hx+c,y,hz),Vector3(-hx,y,hz-c),Vector3(-hx,y,-hz+c),
	]


func _loft_y(rings: Array) -> Dictionary:
	var vertices: Array = []
	var uvs: Array = []
	var indices: Array = []
	for ring_spec in rings:
		var points := _ring_points(ring_spec)
		for segment in range(9):
			vertices.append_array(_v3(points[segment % 8]))
			uvs.append(float(segment) / 8.0)
			uvs.append(float(ring_spec.v))
	for ring_index in range(rings.size()-1):
		var lower := ring_index*9
		var upper := (ring_index+1)*9
		for segment in range(8):
			var a := lower+segment
			var b := lower+segment+1
			var c := upper+segment+1
			var d := upper+segment
			indices.append_array([a,b,c,a,c,d])
	return {"vertices":vertices,"indices":indices,"uvs":uvs}


func _box(size: Vector3) -> Dictionary:
	var h := size * 0.5
	return {"vertices":[
		-h.x,-h.y,-h.z, h.x,-h.y,-h.z, h.x,h.y,-h.z, -h.x,h.y,-h.z,
		-h.x,-h.y,h.z, h.x,-h.y,h.z, h.x,h.y,h.z, -h.x,h.y,h.z,
	],"indices":BOX_INDICES.duplicate()}


func _extrude_xy(points: Array[Vector2], z_front: float, z_back: float) -> Dictionary:
	var vertices: Array = []
	var indices: Array = []
	for p in points:
		vertices.append_array([p.x,p.y,z_front])
	for p in points:
		vertices.append_array([p.x,p.y,z_back])
	for index in range(1,points.size()-1):
		indices.append_array([0,index,index+1])
		indices.append_array([points.size(),points.size()+index+1,points.size()+index])
	for index in range(points.size()):
		var next := (index+1)%points.size()
		indices.append_array([index,next,points.size()+next,index,points.size()+next,points.size()+index])
	return {"vertices":vertices,"indices":indices}


func _slab_xz(points: Array[Vector2], y_bottom: float, y_top: float) -> Dictionary:
	var vertices: Array = []
	var indices: Array = []
	for p in points:
		vertices.append_array([p.x,y_bottom,p.y])
	for p in points:
		vertices.append_array([p.x,y_top,p.y])
	for index in range(1,points.size()-1):
		indices.append_array([0,index+1,index])
		indices.append_array([points.size(),points.size()+index,points.size()+index+1])
	for index in range(points.size()):
		var next := (index+1)%points.size()
		indices.append_array([index,points.size()+next,next,index,points.size()+index,points.size()+next])
	return {"vertices":vertices,"indices":indices}


func _octagonal_ring(half_x: float, half_y: float, thickness: float) -> Dictionary:
	var outer := [Vector2(-half_x+0.008,-half_y),Vector2(half_x-0.008,-half_y),Vector2(half_x,-half_y+0.008),Vector2(half_x,half_y-0.008),Vector2(half_x-0.008,half_y),Vector2(-half_x+0.008,half_y),Vector2(-half_x,half_y-0.008),Vector2(-half_x,-half_y+0.008)]
	var inner: Array[Vector2] = []
	for point in outer:
		inner.append(Vector2(point.x * 0.78,point.y * 0.70))
	var vertices: Array = []
	var indices: Array = []
	for depth in [-thickness,thickness]:
		for point in outer:
			vertices.append_array([point.x,point.y,depth])
		for point in inner:
			vertices.append_array([point.x,point.y,depth])
	for depth_index in range(2):
		var base := depth_index*16
		for index in range(8):
			var next := (index+1)%8
			indices.append_array([base+index,base+next,base+8+next,base+index,base+8+next,base+8+index])
	return {"vertices":vertices,"indices":indices}


func _v3(value: Vector3) -> Array:
	return [snappedf(value.x,0.000001),snappedf(value.y,0.000001),snappedf(value.z,0.000001)]
