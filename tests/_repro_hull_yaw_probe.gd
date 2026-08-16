extends Node

## SCRATCH PROBE (leading underscore — not a gate unit). Lane B.
##
## `hull_visual_capture`'s `three_quarter` view is the only one of its three that
## moves between runs (0.86% of pixels on hull_15x5, 0.81% on hull_28x10, deltas
## up to 241/255 — not dither). It is also the only one that YAWS the hull:
## `boat.rotation_degrees.y = -18.0` on a frozen RigidBody3D, then three
## `process_frame` awaits and a grab.
##
## This dumps every VisualInstance3D's world AABB after each of eight frames
## following that yaw, so "has the visual caught up" has an answer rather than
## an assumption.

const CaptureSubject := preload("res://tests/support/capture_subject.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	add_child(world)
	for hull_id in ["hull_15x5", "hull_28x10"]:
		var boat = HullRegistry.build_hull(hull_id)
		boat.freeze = true
		world.add_child(boat)
		## This probe exists to ask whether the yawed hull holds still over frames,
		## so it must not be the one rig that answers with `freeze` alone — BoatBody's
		## automatic physics LOD revokes that (`tests/support/capture_subject.gd`).
		CaptureSubject.hold_still(boat)
		print("%s: frame0 %s" % [hull_id, _snapshot(boat)])
		boat.rotation_degrees.y = -18.0
		for i in 8:
			await get_tree().process_frame
			print("%s: after %d frames  phys=%d  %s" % [
				hull_id, i + 1, Engine.get_physics_frames(), _snapshot(boat),
			])
		world.remove_child(boat)
		boat.free()
	get_tree().quit(0)


func _snapshot(root: Node) -> String:
	var rows: Array[String] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VisualInstance3D:
			var vi := n as VisualInstance3D
			var box := vi.global_transform * vi.get_aabb()
			rows.append("%s|%.6f,%.6f,%.6f|%.6f,%.6f,%.6f|%s" % [
				str(vi.get_path()),
				box.position.x, box.position.y, box.position.z,
				box.size.x, box.size.y, box.size.z,
				str(vi.visible),
			])
		for c in n.get_children():
			stack.append(c)
	rows.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	for r in rows:
		ctx.update(r.to_utf8_buffer())
	var t := (root as Node3D).global_transform
	var bits := PackedFloat32Array([
		t.basis.x.x, t.basis.x.y, t.basis.x.z,
		t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z,
		t.origin.x, t.origin.y, t.origin.z,
	]).to_byte_array()
	return "instances=%d hash=%s xform=%s" % [
		rows.size(), ctx.finish().hex_encode(), bits.hex_encode(),
	]
