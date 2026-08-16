extends Node

## SCRATCH PROBE (leading underscore — not a gate unit). Lane B.
##
## Answers one question about `tests/_starter_shot.gd`: between two runs with no
## code change, does the SUBJECT move, or only the pixels? Prints the granted
## record, the spawned boat's transform bit-for-bit (as float bits, so a 1e-12
## drift is visible), and the same after every settle the shot rig performs.

func _ready() -> void:
	call_deferred("_run")


func _bits(v: float) -> int:
	var b := PackedFloat64Array([v]).to_byte_array()
	return b.decode_s64(0)


func _dump(tag: String, boat: Node3D) -> void:
	var t := boat.global_transform
	print("%s origin=(%.17f,%.17f,%.17f) bits=(%d,%d,%d) basis=%s" % [
		tag, t.origin.x, t.origin.y, t.origin.z,
		_bits(t.origin.x), _bits(t.origin.y), _bits(t.origin.z),
		str(t.basis),
	])


func _run() -> void:
	var world := Node3D.new()
	add_child(world)
	var granted := CompanyService.build_starter_vessel_record(CompanyContracts.DEFAULT_STARTER)
	print("RECORD hull=%s name=%s reg=%s keys=%s" % [
		str(granted.get("hull_id", "")), str(granted.get("name", "")),
		str(granted.get("registration_id", "")), str(granted.keys()),
	])
	var boat: BoatBody = VesselSpawn.instantiate_from_record(granted)
	boat.freeze = true
	boat.automatic_physics_lod = false
	world.add_child(boat)
	boat.position = Vector3(0.0, -1.5 - boat.draft_m - boat.hull_stations.keel_y, 0.0)
	print("PLACE draft=%.17f keel_y=%.17f deck_y=%.17f beam=%.17f loa=%.17f" % [
		boat.draft_m, boat.hull_stations.keel_y, boat.hull_stations.deck_y,
		boat.beam_m, boat.length_m,
	])
	_dump("F000", boat)
	for i in 40:
		await get_tree().process_frame
		if i == 3 or i == 7 or i == 19 or i == 39:
			_dump("F%03d" % (i + 1), boat)
	print("FREEZE=%s SLEEPING=%s QUALITY=%d PHYS_FRAMES=%d PROC_FRAMES=%d" % [
		str(boat.freeze), str(boat.sleeping), int(boat.physics_quality),
		Engine.get_physics_frames(), Engine.get_process_frames(),
	])
	# Every MeshInstance3D under the boat, hashed by world AABB — catches a child
	# that moved while the body did not.
	var acc := ""
	_walk(boat, acc)
	print("MESHHASH %s" % _hash)
	_hash_surfaces(boat)
	print("SURFHASH %s" % _hash)
	_hash_materials(boat)
	print("MATHASH %s" % _hash)
	print("CLOCK time_of_day=%s unix=%d" % [
		str(get_tree().root.get_node_or_null("WorldClock")),
		Time.get_unix_time_from_system(),
	])
	get_tree().quit(0)


## Every surface's VERTEX/NORMAL/COLOR arrays, in a stable order.
func _hash_surfaces(root: Node) -> void:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var rows: Array[String] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				for s in mi.mesh.get_surface_count():
					var arrays := mi.mesh.surface_get_arrays(s)
					var sub := HashingContext.new()
					sub.start(HashingContext.HASH_MD5)
					for entry in arrays:
						sub.update(var_to_bytes(entry))
					rows.append("%s#%d=%s" % [str(mi.get_path()), s, sub.finish().hex_encode()])
		for c in n.get_children():
			stack.append(c)
	rows.sort()
	for r in rows:
		ctx.update(r.to_utf8_buffer())
	_hash = "%s (%d surfaces)" % [ctx.finish().hex_encode(), rows.size()]


func _hash_materials(root: Node) -> void:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var rows: Array[String] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var mats: Array = [mi.material_override]
			if mi.mesh != null:
				for s in mi.mesh.get_surface_count():
					mats.append(mi.mesh.surface_get_material(s))
					mats.append(mi.get_surface_override_material(s))
			for m in mats:
				if m is StandardMaterial3D:
					var sm := m as StandardMaterial3D
					rows.append("%s|%s|%.9f|%.9f|%s" % [
						str(mi.get_path()), str(sm.albedo_color),
						sm.roughness, sm.metallic,
						"tex" if sm.albedo_texture != null else "-",
					])
				elif m != null:
					rows.append("%s|%s" % [str(mi.get_path()), str(m)])
		for c in n.get_children():
			stack.append(c)
	rows.sort()
	for r in rows:
		ctx.update(r.to_utf8_buffer())
	_hash = "%s (%d materials)" % [ctx.finish().hex_encode(), rows.size()]


var _hash := ""


func _walk(node: Node, _acc: String) -> void:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var stack: Array[Node] = [node]
	var names: Array[String] = []
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VisualInstance3D:
			var vi := n as VisualInstance3D
			var box := vi.global_transform * vi.get_aabb()
			names.append("%s|%v|%v" % [str(vi.get_path()), box.position, box.size])
		for c in n.get_children():
			stack.append(c)
	names.sort()
	for s in names:
		ctx.update(s.to_utf8_buffer())
	_hash = "%s (%d instances)" % [ctx.finish().hex_encode(), names.size()]
