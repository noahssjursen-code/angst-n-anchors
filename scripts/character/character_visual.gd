@tool
class_name CharacterVisual
extends Node3D

## One imported Blender skeleton shared by body, clothes and accessories.
const MODEL = preload("res://resources/models/characters/mariner.glb")
const LEG_IK := preload("res://scripts/character/character_leg_ik.gd")
var appearance := CharacterAppearance.default_appearance()
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var _model: Node3D
var _meshes: Array[MeshInstance3D] = []
var _decorated := true
var _local_first_person := false
var _anchors: Dictionary = {}
var _balance_ik := false
var ik: SkeletonModifier3D

func _ready() -> void:
	rebuild()

func rebuild() -> void:
	if _model != null:
		_model.free()
	_meshes.clear()
	_anchors.clear()
	_model = MODEL.instantiate()
	add_child(_model)
	for child in _model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(child)
		for surface in range(child.mesh.get_surface_count()):
			var material: Material = child.mesh.surface_get_material(surface)
			if material != null:
				child.set_surface_override_material(surface, SurfaceMaterialLibrary.character_material(material,str(child.name)))
	var rigs := _model.find_children("*", "Skeleton3D", true, false)
	if not rigs.is_empty(): skeleton = rigs[0]
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		animation_player = players[0]
		for clip in animation_player.get_animation_list():
			animation_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	if skeleton != null:
		for side in ["left", "right"]:
			var anchor := BoneAttachment3D.new()
			anchor.name = "HandAnchor_" + side
			anchor.bone_name = "hand.L" if side == "left" else "hand.R"
			skeleton.add_child(anchor)
			_anchors[side] = anchor
	apply_appearance(appearance)
	play_motion(&"idle")
	if _balance_ik:
		_attach_balance_ik()


func enable_balance_ik() -> void:
	_balance_ik = true
	_attach_balance_ik()


func uses_balance_ik() -> bool:
	return _balance_ik and ik != null and is_instance_valid(ik)


func _attach_balance_ik() -> void:
	if skeleton == null:
		return
	if ik != null and is_instance_valid(ik):
		ik.queue_free()
	ik = LEG_IK.new()
	ik.name = "BalanceIK"
	skeleton.add_child(ik)
	# Pose after the player has mounted to this frame's deck, not on the previous one.
	skeleton.process_priority = 8
	if animation_player != null:
		animation_player.process_priority = 8
		animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE

func apply_appearance(value: CharacterAppearance) -> void:
	appearance = value.duplicate() if value != null else CharacterAppearance.default_appearance()
	var visibility := {
		"Body_Torso": not (_decorated and appearance.top_id == "sweater"),
		"Body_Arms": not (_decorated and appearance.top_id == "sweater"),
		"Body_Legs": not (_decorated and appearance.trousers_id == "work"),
		"Body_Feet": not (_decorated and appearance.footwear_id == "boots"),
		"Base_Shorts": not (_decorated and appearance.trousers_id == "work"),
		"Hair_Crop": appearance.hair_id == "crop" and not (_decorated and appearance.headwear_id in ["cap", "hardhat"]),
		"Top_Sweater": _decorated and appearance.top_id == "sweater",
		"Top_Trim": _decorated and appearance.top_id == "sweater",
		"Trousers_Work": _decorated and appearance.trousers_id == "work",
		"Footwear_Boots": _decorated and appearance.footwear_id == "boots",
		"Outerwear_Vest": _decorated and appearance.outerwear_id == "vest",
		"Headwear_Cap": _decorated and appearance.headwear_id == "cap",
		"Headwear_Hardhat": _decorated and appearance.headwear_id == "hardhat",
		"FacialHair_Moustache": appearance.facial_hair_id == "moustache",
		"Eyewear_Glasses": _decorated and appearance.eyewear_id == "glasses",
		"Accessory_Pipe": _decorated and appearance.face_accessory_id == "pipe",
		"Utility_Belt": _decorated and appearance.utility_id == "belt",
	}
	var age_weight := (appearance.age - 18.0) / 62.0
	var colors := {
		"Skin": appearance.skin_color, "Top": appearance.top_color,
		"Trousers": appearance.trousers_color, "Footwear": appearance.footwear_color,
		"Hair": appearance.hair_color.lerp(Color(.55,.55,.52), age_weight * .8),
		"Headwear": appearance.headwear_color, "Outerwear": appearance.accent_color,
		"Lips": appearance.skin_color.darkened(.28),
	}
	var morphs := {"Build": appearance.build, "Belly": appearance.belly, "Frame": appearance.frame, "Age": age_weight}
	for item in _meshes:
		item.visible = visibility.get(str(item.name), true)
		for index in range(item.mesh.get_blend_shape_count()):
			item.set_blend_shape_value(index, morphs.get(str(item.mesh.get_blend_shape_name(index)), 0.0))
		for surface in range(item.mesh.get_surface_count()):
			var material := item.get_surface_override_material(surface) as StandardMaterial3D
			if material != null and colors.has(material.resource_name):
				material.albedo_color = colors[material.resource_name]

	set_local_first_person(_local_first_person)

func set_local_first_person(enabled: bool) -> void:
	_local_first_person = enabled
	for item in _meshes:
		if str(item.name) in ["Head", "Neck", "Face", "Hair_Crop", "Headwear_Cap", "Headwear_Hardhat", "Eyewear_Glasses", "FacialHair_Moustache", "Accessory_Pipe"]:
			# Shadows retain the complete head; only this camera hides its geometry.
			item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func set_decorated(value: bool) -> void:
	_decorated = value
	apply_appearance(appearance)

func play_motion(state: StringName, playback_speed: float = 1.0) -> void:
	if animation_player == null: return
	for clip in animation_player.get_animation_list():
		if str(clip).get_slice("/", str(clip).get_slice_count("/") - 1) == str(state):
			animation_player.speed_scale = playback_speed
			if animation_player.current_animation != clip:
				var old := animation_player.current_animation
				var phase := 0.0
				if old in ["walk", "run"] and state in [&"walk", &"run"]:
					phase = fposmod(animation_player.current_animation_position / animation_player.current_animation_length, 1.0)
				animation_player.play(clip, .24)
				if phase > 0.0: animation_player.seek(phase * animation_player.get_animation(clip).length, true)
			return

func set_walk_distance(distance_m: float) -> void:
	play_motion(&"walk", 0.0)
	if animation_player != null:
		animation_player.seek(fposmod(distance_m, 1.0) * animation_player.get_animation("walk").length, true)

func get_part(part_name: String) -> Node3D:
	return _model.find_child(part_name, true, false) as Node3D if _model != null else null
func get_base_assembler() -> ModelAssembler:
	return null
func get_all_assemblers() -> Array[ModelAssembler]:
	return []
func get_hand_anchor(side: String) -> Node3D:
	return _anchors.get(side)
