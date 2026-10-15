extends RefCounted
## Distribute palm pronation through the weighted distal forearm while preserving
## elbow and wrist positions. Shared by held fishing equipment and creels.
static func align(skeleton:Skeleton3D,lower:int,hand:int,twist:int,knuckles_world:Vector3)->void:
	if twist<0:return
	var axis:Vector3=(skeleton.get_bone_global_pose(hand).origin-skeleton.get_bone_global_pose(lower).origin).normalized()
	var from:Vector3=skeleton.get_bone_global_pose(hand).basis.z
	var to:Vector3=skeleton.global_basis.inverse()*knuckles_world
	from=(from-axis*from.dot(axis)).normalized()
	to=(to-axis*to.dot(axis)).normalized()
	if from.length_squared()<.5 or to.length_squared()<.5:return
	var pose:=skeleton.get_bone_global_pose(twist)
	var roll:=atan2(axis.dot(from.cross(to)),from.dot(to))
	pose.basis=(Basis(axis,roll)*pose.basis).orthonormalized()
	skeleton.set_bone_global_pose(twist,pose)
