@tool
class_name CharacterVisual
extends Node3D

## Shared unclothed base for the player, remote players and NPCs.
## Old saved wardrobe IDs remain data only; they cannot select the rejected model.
const MODEL_PATH := "res://resources/models/crew_base/crew_base.glb"
const HAND_CONTACTS_PATH := "res://resources/models/crew_base/hand_contacts.json"
const HAND_GRIPS_PATH := "res://resources/models/crew_base/hand_grips.json"
const LEG_IK := preload("res://scripts/character/character_leg_ik.gd")
const FIRST_PERSON_SETBACK_M := .14
var appearance := CharacterAppearance.default_appearance()
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var _model: Node3D
var _authored_model_transform := Transform3D.IDENTITY
var _meshes: Array[MeshInstance3D] = []
var _decorated := true
var _local_first_person := false
var _anchors: Dictionary = {}
var _balance_ik := false
var ik: SkeletonModifier3D

func _ready() -> void:
	rebuild()

func rebuild() -> void:
	if is_instance_valid(_model): _model.free()
	_model = null
	skeleton = null
	animation_player = null
	ik = null
	_meshes.clear()
	_anchors.clear()
	var scene := load(MODEL_PATH) as PackedScene
	if scene == null:
		push_error("Character base could not be loaded: " + MODEL_PATH)
		return
	_model = scene.instantiate() as Node3D
	_authored_model_transform = _model.transform
	add_child(_model)
	for child: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		_meshes.append(mesh)
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface)
			if material != null:
				# Tint one actor without modifying any other instance of the shared asset.
				mesh.set_surface_override_material(surface, material.duplicate())
	var rigs := _model.find_children("*", "Skeleton3D", true, false)
	if not rigs.is_empty(): skeleton = rigs[0] as Skeleton3D
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		animation_player = players[0] as AnimationPlayer
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
	if _balance_ik: _attach_balance_ik()


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
	var morphs := {"Build": appearance.build, "Belly": appearance.belly,
		"Frame": appearance.frame, "Age": (appearance.age - 18.0) / 62.0}
	for item in _meshes:
		for index in item.mesh.get_blend_shape_count():
			item.set_blend_shape_value(index, float(morphs.get(str(item.mesh.get_blend_shape_name(index)), 0.0)))
		for surface in item.mesh.get_surface_count():
			var material := item.get_surface_override_material(surface) as StandardMaterial3D
			if material != null and material.resource_name.begins_with("Skin"):
				material.albedo_color = appearance.skin_color
	set_local_first_person(_local_first_person)

func set_local_first_person(enabled: bool) -> void:
	_local_first_person = enabled
	if is_instance_valid(_model):
		# The camera stays in its gameplay position. Only the locally viewed body
		# sits behind the eye, so looking down sees its outside rather than its neck cut.
		_model.transform = _authored_model_transform
		if enabled:
			_model.position += Vector3.BACK * FIRST_PERSON_SETBACK_M
	for item in _meshes:
		if str(item.name) in ["Head", "Neck", "Eyes", "Teeth", "Mouth"]:
			item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func presentation_offset_world() -> Vector3:
	# Equipment shares the local visual setback, independent of camera pitch.
	if not is_instance_valid(_model): return Vector3.ZERO
	return _model.global_position - global_position

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
