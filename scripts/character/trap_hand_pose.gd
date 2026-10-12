extends SkeletonModifier3D
## Fixed-length arm IK. Each palm sits on a creel handle; fingers use the rod grip.

const HANDLE_RADIUS := 0.012

var creel: Node3D
var right_handle: Node3D
var left_handle: Node3D
var hand_mesh: MeshInstance3D
var _bones: Dictionary = {}
var _contacts: Dictionary = {}
var _grips: Dictionary = {}


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or not is_instance_valid(creel):
		return
	if _bones.is_empty():
		_contacts = JSON.parse_string(FileAccess.get_file_as_string("res://resources/models/characters/hand_contacts.json"))
		_grips = JSON.parse_string(FileAccess.get_file_as_string("res://resources/models/characters/hand_grips.json"))
		for side in ["L", "R"]:
			for part in ["upper_arm", "forearm", "forearm_twist", "hand", "index_01", "index_02", "index_03", "middle_01", "middle_02", "middle_03", "ring_01", "ring_02", "ring_03", "little_01", "little_02", "little_03", "thumb_01", "thumb_02"]:
				var bone_name := "%s.%s" % [part, side]
				_bones[bone_name] = skeleton.find_bone(bone_name)
	for side in ["L", "R"]:
		# This rig's .L bone lies on +X, so it takes the handle named Right.
		var grip := right_handle if side == "L" else left_handle
		if not is_instance_valid(grip):
			continue
		var upper: int = _bones["upper_arm." + side]
		var lower: int = _bones["forearm." + side]
		var hand: int = _bones["hand." + side]
		if upper < 0 or lower < 0 or hand < 0:
			continue
		var shoulder := skeleton.get_bone_global_pose(upper).origin
		var elbow := skeleton.get_bone_global_pose(lower).origin
		var wrist := skeleton.get_bone_global_pose(hand).origin
		var a := shoulder.distance_to(elbow)
		var b := elbow.distance_to(wrist)
		var inward := creel.global_position - grip.global_position
		inward.y = 0.0
		if inward.length_squared() < 0.0001:
			inward = creel.global_basis.x
		var fingers := inward.normalized()
		var knuckles := Vector3.UP
		var hand_basis := Basis(fingers.cross(knuckles), fingers, knuckles).orthonormalized()
		var contact_data: Array = _contacts[side].palm_contact
		var contact := Vector3(contact_data[0], contact_data[1], contact_data[2])
		if is_instance_valid(hand_mesh):
			for index in hand_mesh.mesh.get_blend_shape_count():
				var key := str(hand_mesh.mesh.get_blend_shape_name(index))
				var shift: Array = _contacts[side].morph_deltas[key]
				contact += Vector3(shift[0], shift[1], shift[2]) * hand_mesh.get_blend_shape_value(index)
		var surface := grip.global_position + knuckles * HANDLE_RADIUS
		var target := skeleton.to_local(surface - hand_basis * contact)
		var axis := (target - shoulder).normalized()
		var distance := clampf(shoulder.distance_to(target), absf(a - b) + 0.002, a + b - 0.003)
		var along := (a * a - b * b + distance * distance) / (2.0 * distance)
		var height := sqrt(maxf(0.0, a * a - along * along))
		var away := -inward
		var pole := skeleton.global_basis.inverse() * (away - Vector3.UP * 0.35)
		pole = (pole - axis * pole.dot(axis)).normalized()
		if pole.length_squared() < 0.5:
			pole = (skeleton.global_basis.inverse() * creel.global_basis.z).normalized()
		_aim(skeleton, upper, lower, shoulder + axis * along + pole * height)
		_aim(skeleton, lower, hand, shoulder + axis * distance)
		var pose := skeleton.get_bone_global_pose(hand)
		pose.basis = (skeleton.global_basis.inverse() * hand_basis).orthonormalized()
		skeleton.set_bone_global_pose(hand, pose)
		for bone_name: String in _grips[side]:
			var bone: int = _bones[bone_name]
			var quaternion: Array = _grips[side][bone_name]
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_rest(bone).basis.get_rotation_quaternion() * Quaternion(quaternion[1], quaternion[2], quaternion[3], quaternion[0]))


func _aim(skeleton: Skeleton3D, bone: int, child: int, target: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var from := skeleton.get_bone_global_pose(child).origin - pose.origin
	var to := target - pose.origin
	if from.length_squared() < 0.000001 or to.length_squared() < 0.000001:
		return
	pose.basis = (Basis(Quaternion(from.normalized(), to.normalized())) * pose.basis).orthonormalized()
	skeleton.set_bone_global_pose(bone, pose)


func release() -> void:
	var skeleton := get_skeleton()
	if skeleton != null:
		for bone_name: String in _bones:
			var bone: int = _bones[bone_name]
			if bone >= 0:
				skeleton.set_bone_pose(bone, skeleton.get_bone_rest(bone))
	active = false
	queue_free()
