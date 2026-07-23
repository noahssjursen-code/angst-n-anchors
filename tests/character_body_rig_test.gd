extends Node

const REQUIRED_PARTS := [
	"pelvis", "chest", "neck", "head",
	"arm_left", "forearm_left", "hand_left",
	"arm_right", "forearm_right", "hand_right",
	"leg_left", "shin_left", "foot_left",
	"leg_right", "shin_right", "foot_right",
]
const MOTIONS: Array[StringName] = [
	WalkAnimator.IDLE,
	WalkAnimator.WALK,
	WalkAnimator.RUN,
	WalkAnimator.TURN_LEFT,
	WalkAnimator.TURN_RIGHT,
	WalkAnimator.CROUCH,
	WalkAnimator.JUMP,
	WalkAnimator.WORK,
	WalkAnimator.WAVE,
]

var failures := PackedStringArray()


func _ready() -> void:
	var actor := NpcBase.new()
	actor.name = "BodyOnlyActor"
	actor.wardrobe_enabled = false
	add_child(actor)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(actor.visual != null, "body owns the shared CharacterVisual")
	_check(actor.assembler != null, "body is assembled from the JSON model")
	if actor.assembler != null:
		_check(actor.assembler.model_data_path == AssetPaths.NPC_CHARACTER_STUDY_MODEL,
			"body uses the canonical JSON character model")
	_check(actor.visual.get_all_assemblers().size() == 1,
		"body-only actor contains exactly one model assembler")
	_check(actor.find_children("Wardrobe_*", "", true, false).is_empty(),
		"body-only actor contains no wardrobe nodes")

	for part_name in REQUIRED_PARTS:
		_check(actor.get_part(part_name) != null, "required articulated part exists: %s" % part_name)

	for index in range(MOTIONS.size()):
		var state := MOTIONS[index]
		var phase := PI * 0.5 if state in [WalkAnimator.WALK, WalkAnimator.RUN, WalkAnimator.JUMP] else 0.0
		actor.animator.set_preview_pose(state, phase, 0.72)
		_check(actor.animator.current_state() == state, "animator enters %s" % String(state))
		for part_name in REQUIRED_PARTS:
			var part := actor.get_part(part_name)
			if part != null:
				_check(_transform_is_finite(part.transform), "%s produces a finite %s transform" % [String(state), part_name])

	if failures.is_empty():
		print("Character body rig test: all checks passed")
		get_tree().quit()
		return
	for failure in failures:
		push_error("Character body rig test: " + failure)
	get_tree().quit(1)


func _transform_is_finite(value: Transform3D) -> bool:
	return _vector_is_finite(value.origin) \
		and _vector_is_finite(value.basis.x) \
		and _vector_is_finite(value.basis.y) \
		and _vector_is_finite(value.basis.z)


func _vector_is_finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
