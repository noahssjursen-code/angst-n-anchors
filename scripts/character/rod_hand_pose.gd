extends SkeletonModifier3D
## A local equipment pose layered after balance IK. Authored limb lengths remain fixed.
var handline:=false
var rod: Node3D
var right_grip: Node3D
var left_grip: Node3D
var _bones: Dictionary = {}
var _contacts: Dictionary = {}
var _grips: Dictionary = {}
var hand_mesh: MeshInstance3D

func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or not is_instance_valid(rod): return
	if _bones.is_empty():
		_contacts = JSON.parse_string(FileAccess.get_file_as_string("res://resources/models/characters/hand_contacts.json"))
		_grips = JSON.parse_string(FileAccess.get_file_as_string("res://resources/models/characters/hand_grips.json"))
		for side in ["L", "R"]:
			for part in ["upper_arm", "forearm", "forearm_twist", "hand", "index_01", "index_02", "index_03", "middle_01", "middle_02", "middle_03", "ring_01", "ring_02", "ring_03", "little_01", "little_02", "little_03", "thumb_01", "thumb_02"]:
				var name: String = part + "." + side
				_bones[name] = skeleton.find_bone(name)
	for side in ["L", "R"]:
		# This authored rig uses +X for .L; socket assignment follows its geometry.
		var grip := right_grip if side == "L" else left_grip
		if not is_instance_valid(grip): continue
		var upper: int = _bones["upper_arm."+side]
		var lower: int = _bones["forearm."+side]
		var hand: int = _bones["hand."+side]
		if upper < 0 or lower < 0 or hand < 0: continue
		var shoulder := skeleton.get_bone_global_pose(upper).origin
		var elbow := skeleton.get_bone_global_pose(lower).origin
		var wrist := skeleton.get_bone_global_pose(hand).origin
		var a := shoulder.distance_to(elbow)
		var b := elbow.distance_to(wrist)
		var outward := 1.0 if side == "L" else -1.0
		# A palm surface authored in Blender meets the equipment socket. Moving
		# the wrist by a guessed offset puts the shaft through the hand's centre.
		# Right palm lies over the blank. A downward-pointing rest hand forced
		# the wrist to fold backwards against an upward-reaching forearm.
		var fingers := (-rod.global_basis.x*.9396926+rod.global_basis.y*.3420201) if side == "L" else -rod.global_basis.z
		var knuckles := (rod.global_basis.x*.3420201+rod.global_basis.y*.9396926) if side == "L" else rod.global_basis.y
		if handline:
			fingers=-rod.global_basis.y
			knuckles=rod.global_basis.z
		var hand_basis := Basis(fingers.cross(knuckles),fingers,knuckles).orthonormalized()
		var contact_data: Array = _contacts[side].palm_contact
		var contact := Vector3(contact_data[0],contact_data[1],contact_data[2])
		if is_instance_valid(hand_mesh):
			for index in hand_mesh.mesh.get_blend_shape_count():
				var key:=str(hand_mesh.mesh.get_blend_shape_name(index))
				var shift:Array=_contacts[side].morph_deltas[key]
				contact+=Vector3(shift[0],shift[1],shift[2])*hand_mesh.get_blend_shape_value(index)
		# The crank socket is on the spindle axis, so a turning crank does not
		# rotate the palm around the knob. Its round grip has a 12 mm radius.
		var surface := grip.global_position+(knuckles*.012 if side=="R" and not handline else Vector3.ZERO)
		var target := skeleton.to_local(surface-hand_basis*contact)
		var axis := (target-shoulder).normalized()
		var distance := clampf(shoulder.distance_to(target),absf(a-b)+.002,a+b-.003)
		var along := (a*a-b*b+distance*distance)/(2*distance)
		var height := sqrt(maxf(0,a*a-along*along))
		var pole := skeleton.global_basis.inverse()*(rod.global_basis.x*outward*.6-Vector3.UP)
		pole=(pole-axis*pole.dot(axis)).normalized()
		_aim(skeleton,upper,lower,shoulder+axis*along+pole*height)
		_aim(skeleton,lower,hand,shoulder+axis*distance)
		var pose := skeleton.get_bone_global_pose(hand)
		# Blender-authored hand frame: +Y fingers, +Z knuckles, -Z palm.
		# Fingers cross the handle; palms face into it, not away from the body.
		pose.basis=(skeleton.global_basis.inverse()*hand_basis).orthonormalized()
		skeleton.set_bone_global_pose(hand,pose)
		for name:String in _grips[side]:
			var bone:int=_bones[name]
			var q:Array=_grips[side][name] # Blender stores quaternion W, X, Y, Z.
			skeleton.set_bone_pose_rotation(bone,skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()*Quaternion(q[1],q[2],q[3],q[0]))

func _aim(skeleton: Skeleton3D, bone: int, child: int, target: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var from := skeleton.get_bone_global_pose(child).origin-pose.origin
	var to := target-pose.origin
	if from.length_squared()<.000001 or to.length_squared()<.000001:return
	pose.basis=(Basis(Quaternion(from.normalized(),to.normalized()))*pose.basis).orthonormalized()
	# Preserve the joint origin. Only rotation bends the arm.
	skeleton.set_bone_global_pose(bone,pose)

func release() -> void:
	var skeleton := get_skeleton()
	if skeleton != null:
		for name: String in _bones:
			var bone: int = _bones[name]
			if bone>=0:skeleton.set_bone_pose(bone,skeleton.get_bone_rest(bone))
	active=false
	queue_free()
