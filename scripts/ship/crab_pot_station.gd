class_name CrabPotStation
extends Node3D

## Grab a creel by its handles, throw it over the side, and let it sink.
const PotWork = preload("res://scripts/ship/crab_pot_work.gd")
const HandPose = preload("res://scripts/character/trap_hand_pose.gd")
const PotField = preload("res://scripts/ship/deployed_crab_pots.gd")
const BUOY_SCENE := "res://resources/models/parts/coastal_fishing/pot_rope_buoy.glb"
const REACH_M := 3.2

var manual := false
var hauler: Node3D
var forced_depth := -1.0
var _boat: Node3D
var _haul_point: Node3D
var _slots: Array[Dictionary] = []
var _active := -1
var _held := false
var _message := ""
var _message_until := 0
var _hands: SkeletonModifier3D


func _init() -> void:
	add_to_group("ship_owner_only")


func bind(boat: Node3D, hauler_part: Node3D) -> void:
	_boat = boat
	hauler = hauler_part
	_haul_point = hauler.find_child("HaulPoint", true, false) as Node3D
	assert(_haul_point != null, "Pot hauler requires a HaulPoint socket")
	var creels: Array[Node3D] = []
	for entry in boat.get("part_roots"):
		var part := entry as Node3D
		if part != null and str(part.get_meta("asset_id", "")) == "crab_creel":
			creels.append(part)
	creels.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		if not is_equal_approx(a.position.z, b.position.z):
			return a.position.z < b.position.z
		if not is_equal_approx(a.position.x, b.position.x):
			return a.position.x < b.position.x
		return a.position.y < b.position.y
	)
	for index in creels.size():
		var creel := creels[index]
		var left := creel.find_child("LeftHandle", true, false) as Node3D
		var right := creel.find_child("RightHandle", true, false) as Node3D
		assert(left != null and right != null, "Creel requires LeftHandle and RightHandle")
		var area := _area(creel, "creel", index, _local_center(creel), 0.28)
		_slots.append({
			"index": index,
			"creel": creel,
			"rest": creel.transform,
			"area": area,
			"work": PotWork.new(),
			"buoy": _new_buoy(index),
			"rope": _new_rope(),
			"line": FishingLineShape.new(),
			"drop_xz": Vector2.ZERO,
			"handle_mid": ( _local_point(creel, left) + _local_point(creel, right) ) * 0.5,
			"grab_from": Transform3D.IDENTITY,
			"throw_from": Transform3D.IDENTITY,
			"stow_from": Transform3D.IDENTITY,
			"ready_hours": 0.0,
			"pot_id": "",
			"timer": _new_timer(index),
		})
		var buoy := _slots[index].buoy as Node3D
		(buoy.get_meta("marker") as Node3D).add_child(_slots[index].timer as Node)
	var haul_center := _haul_point.position if _haul_point.get_parent() == hauler else Vector3(0.65, 1.6, 0)
	_area(hauler, "hauler", -1, haul_center, 0.55)


func _ready() -> void:
	_adopt_world_pots()


func slot_count() -> int:
	return _slots.size()


func phase_of(index: int) -> int:
	return _slots[index].work.phase


func begin_grab(index: int) -> bool:
	if index < 0 or index >= _slots.size() or _handling():
		return false
	var slot := _slots[index]
	var work = slot.work
	if work.phase != PotWork.Phase.STOWED:
		return false
	var spot := _throw_spot()
	if not bool(spot.ok):
		_say("Step to the side so the trap can go overboard")
		return false
	var at: Vector3 = spot.at
	var depth := _depth_at(at)
	if depth < PotWork.MIN_DEPTH_M:
		_say("Too shallow to set a trap")
		return false
	if depth > PotWork.MAX_DEPTH_M:
		_say("Too deep for a crab pot. Set it in 10–35 m")
		return false
	var creel := slot.creel as Node3D
	slot.drop_xz = _separated(slot, Vector2(at.x, at.z))
	slot.grab_from = creel.global_transform
	work.begin_carry()
	_active = index
	_message = ""
	_pose_carry(slot)
	return true


func cancel_carry(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return
	var slot := _slots[index]
	if slot.work.phase != PotWork.Phase.CARRYING:
		return
	slot.work.cancel()
	if _active == index:
		_active = -1
	_pose_stowed(slot)
	_release_hands()


func begin_haul(index: int) -> bool:
	if _handling():
		return false
	if index < 0:
		index = _alongside_index()
	if index < 0 or index >= _slots.size():
		if _deployed_count() > 0:
			_say("Bring the hauler alongside the buoy")
		return false
	var slot := _slots[index]
	var work = slot.work
	if work.phase != PotWork.Phase.DEPLOYED:
		return false
	if _haul_point.global_position.distance_to(Vector3(slot.drop_xz.x, _haul_point.global_position.y, slot.drop_xz.y)) > PotWork.ALONGSIDE_M:
		_say("Bring the hauler alongside the buoy")
		return false
	if not _soak_ready(slot):
		_say("Still soaking · %s" % _soak_text(slot))
		return false
	var field = _field()
	if field != null and not str(slot.pot_id).is_empty():
		field.set_hauling(str(slot.pot_id), true)
	work.begin_haul()
	_active = index
	_message = ""
	return true


func advance(dt: float) -> void:
	for slot in _slots:
		var work = slot.work
		if work.phase == PotWork.Phase.CARRYING:
			if not manual and _deck_player() == null:
				cancel_carry(int(slot.index))
				continue
			_pose_carry(slot)
			if work.advance_carry(dt):
				_start_throw(slot)
		elif work.phase == PotWork.Phase.THROWING:
			var entered_water: bool = work.advance_throw(dt)
			_pose_throw(slot)
			if entered_water:
				_enter_sink(slot)
		elif work.phase == PotWork.Phase.SINKING:
			_sink(slot, dt)
		elif work.phase == PotWork.Phase.HAULING:
			_haul(slot, dt)
		elif work.phase == PotWork.Phase.STOWING:
			_stow_motion(slot, dt)
	_update_hands()


func hint() -> String:
	if WorldGateway.is_remote():
		return ""
	if _active >= 0:
		var work = _slots[_active].work
		if work.phase == PotWork.Phase.CARRYING:
			return "Grabbing trap"
		if work.phase == PotWork.Phase.THROWING:
			return "Throwing trap"
		if work.phase == PotWork.Phase.HAULING:
			var creel := _slots[_active].creel as Node3D
			var left := _surface(_slots[_active].drop_xz) - creel.global_position.y
			return "Hauling trap  %.0f m left" % maxf(0.0, left)
		if work.phase == PotWork.Phase.STOWING:
			return "Setting the trap down"
	if not _message.is_empty() and Time.get_ticks_msec() < _message_until:
		return _message
	var aim := _aimed()
	if aim.is_empty():
		return ""
	if str(aim.role) == "creel":
		var aimed = _slots[int(aim.index)].work
		if aimed.phase == PotWork.Phase.STOWED:
			return "Press F to grab trap"
	if str(aim.role) == "hauler" or str(aim.role) == "buoy":
		if _deployed_count() == 0:
			return ""
		var alongside := _alongside_index()
		if alongside < 0:
			return "Bring the hauler alongside the buoy"
		if not _soak_ready(_slots[alongside]):
			return "Soaking · %s" % _soak_text(_slots[alongside])
		return "Press F to haul trap"
	return ""


func _physics_process(delta: float) -> void:
	if manual or _boat == null or WorldGateway.is_remote():
		return
	if LocalPlayerView.get_active_ship() != _boat:
		return
	var pressed := Input.is_action_pressed("interact") and _deck_player() != null and not GameMenu.is_modal_open() and not LocalPlayerView.is_helming()
	if pressed and not _held:
		_try_begin()
	_held = pressed
	advance(delta)


func _process(delta: float) -> void:
	if _boat == null:
		return
	for slot in _slots:
		var phase = slot.work.phase
		if phase == PotWork.Phase.CARRYING:
			_pose_carry(slot)
		elif phase == PotWork.Phase.THROWING:
			_pose_throw(slot)
		elif phase == PotWork.Phase.SINKING or phase == PotWork.Phase.HAULING:
			_draw_rope(slot, delta)
		elif phase == PotWork.Phase.STOWING:
			_pose_stow(slot)
		_show_timer(slot)
	_update_hands()


func _exit_tree() -> void:
	_release_hands()
	var field = _field()
	if field != null:
		field.release_claims(self)


func _try_begin() -> void:
	if _handling():
		return
	var aim := _aimed()
	if aim.is_empty():
		return
	if str(aim.role) == "creel":
		begin_grab(int(aim.index))
	elif str(aim.role) == "hauler":
		begin_haul(_alongside_index())
	elif str(aim.role) == "buoy":
		var pot_id := str(aim.get("pot_id", ""))
		begin_haul(_slot_for_pot(pot_id) if not pot_id.is_empty() else int(aim.index))


func _start_throw(slot: Dictionary) -> void:
	var creel := slot.creel as Node3D
	slot.throw_from = creel.global_transform
	var work = slot.work
	work.begin_throw(_depth_at(Vector3(slot.drop_xz.x, 0.0, slot.drop_xz.y)))
	_pose_throw(slot)


func _enter_sink(slot: Dictionary) -> void:
	var work = slot.work
	work.phase = PotWork.Phase.SINKING
	var creel := slot.creel as Node3D
	var drop: Vector2 = slot.drop_xz
	creel.top_level = true
	creel.global_transform = Transform3D(Basis.IDENTITY, Vector3(drop.x, _surface(drop) + 0.2, drop.y))
	_float_buoy(slot)
	_show_gear(slot, true)
	if _active == int(slot.index):
		_active = -1
	_release_hands()


func _sink(slot: Dictionary, dt: float) -> void:
	var creel := slot.creel as Node3D
	var drop: Vector2 = slot.drop_xz
	var surface := _surface(drop)
	var bed: float = surface - float(slot.work.depth_m)
	var height := creel.global_position.y - PotWork.TRAVEL_M_S * dt
	if height <= bed:
		if str(slot.pot_id).is_empty():
			slot.work.finish_sink()
			slot.ready_hours = _next_day_hours()
			_commit_pot(slot)
			_say("Trap is set. Haul it tomorrow.")
		return
	creel.top_level = true
	creel.global_transform = Transform3D(Basis.IDENTITY, Vector3(drop.x, height, drop.y))
	_float_buoy(slot)
	_show_gear(slot, true)


func _haul(slot: Dictionary, dt: float) -> void:
	var shown := _water_gear(slot)
	var creel := shown.creel as Node3D if not shown.is_empty() else slot.creel as Node3D
	var buoy := shown.buoy as Node3D if not shown.is_empty() else slot.buoy as Node3D
	var drop: Vector2 = slot.drop_xz
	var mouth := _haul_point.global_position.y
	var height := creel.global_position.y + PotWork.TRAVEL_M_S * dt
	if height >= mouth:
		var deck := slot.creel as Node3D
		var field = _field()
		if field != null and not str(slot.pot_id).is_empty():
			field.remove(str(slot.pot_id))
		slot.pot_id = ""
		deck.show()
		deck.top_level = true
		deck.global_position = _haul_point.global_position
		slot.stow_from = deck.global_transform
		slot.work.begin_stow()
		_pose_stow(slot)
		return
	var risen := clampf((height - (_surface(drop) - float(slot.work.depth_m))) / maxf(0.1, float(slot.work.depth_m)), 0.0, 1.0)
	creel.top_level = true
	creel.global_transform = Transform3D(Basis.IDENTITY, Vector3(drop.x, height, drop.y))
	_place_buoy(buoy, Vector3(drop.x, _surface(drop), drop.y).lerp(_haul_point.global_position, risen))


func _stow_motion(slot: Dictionary, dt: float) -> void:
	if slot.work.advance_stow(dt):
		if _active == int(slot.index):
			_active = -1
		_pose_stowed(slot)
		_say("Trap aboard")
		return
	_pose_stow(slot)


func _handling() -> bool:
	for slot in _slots:
		var phase = slot.work.phase
		if phase == PotWork.Phase.CARRYING or phase == PotWork.Phase.THROWING or phase == PotWork.Phase.HAULING or phase == PotWork.Phase.STOWING:
			return true
	return false


func _deployed_count() -> int:
	var count := 0
	for slot in _slots:
		if slot.work.phase == PotWork.Phase.DEPLOYED or slot.work.phase == PotWork.Phase.SINKING:
			count += 1
	return count


func _alongside_index() -> int:
	var best := -1
	var nearest := PotWork.ALONGSIDE_M
	var origin := _haul_point.global_position
	for slot in _slots:
		if slot.work.phase != PotWork.Phase.DEPLOYED:
			continue
		var drop: Vector2 = slot.drop_xz
		var distance := origin.distance_to(Vector3(drop.x, origin.y, drop.y))
		if distance <= nearest:
			nearest = distance
			best = int(slot.index)
	return best


func _pose_carry(slot: Dictionary) -> void:
	var creel := slot.creel as Node3D
	var t := _smooth(float(slot.work.progress))
	creel.top_level = true
	creel.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	creel.global_transform = (slot.grab_from as Transform3D).interpolate_with(_carry_transform(slot), t)
	(slot.area as Area3D).monitorable = false
	_show_gear(slot, false)


func _pose_throw(slot: Dictionary) -> void:
	var creel := slot.creel as Node3D
	var t := float(slot.work.progress)
	var start: Transform3D = slot.throw_from
	var drop: Vector2 = slot.drop_xz
	var end := Vector3(drop.x, _surface(drop) + 0.35, drop.y)
	var position := start.origin.lerp(end, t) + Vector3.UP * sin(t * PI) * 1.05
	var basis := start.basis.slerp(Basis.IDENTITY, t).rotated(start.basis.x.normalized(), t * 2.4)
	creel.top_level = true
	creel.global_transform = Transform3D(basis, position)
	(slot.area as Area3D).monitorable = false
	_show_gear(slot, false)


func _pose_deployed(slot: Dictionary) -> void:
	var drop: Vector2 = slot.drop_xz
	var surface := _surface(drop)
	var creel := slot.creel as Node3D
	creel.top_level = true
	creel.global_transform = Transform3D(Basis.IDENTITY, Vector3(drop.x, surface - float(slot.work.depth_m), drop.y))
	_show_gear(slot, true)
	_float_buoy(slot)


func _pose_stow(slot: Dictionary) -> void:
	var creel := slot.creel as Node3D
	var parent := creel.get_parent() as Node3D
	var home := parent.global_transform * (slot.rest as Transform3D)
	var t := _smooth(float(slot.work.progress))
	creel.top_level = true
	creel.global_transform = (slot.stow_from as Transform3D).interpolate_with(home, t)
	_show_gear(slot, t < 0.35)


func _pose_stowed(slot: Dictionary) -> void:
	var creel := slot.creel as Node3D
	creel.top_level = false
	creel.transform = slot.rest
	creel.show()
	(slot.buoy as Node3D).hide()
	(slot.rope as MeshInstance3D).hide()
	(slot.line as FishingLineShape).clear()
	(slot.area as Area3D).monitorable = true


func _carry_transform(slot: Dictionary) -> Transform3D:
	var mid: Vector3 = slot.handle_mid
	var player := _deck_player()
	if player == null:
		var lifted: Transform3D = slot.grab_from
		return Transform3D(lifted.basis, lifted.origin + Vector3.UP * 0.45)
	var forward := -player.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = -_boat.global_basis.z
		forward.y = 0.0
	forward = forward.normalized()
	var right := player.global_basis.x
	right.y = 0.0
	right = right.normalized()
	var basis := Basis(right, Vector3.UP, right.cross(Vector3.UP)).orthonormalized()
	var creel := slot.creel as Node3D
	var left := creel.find_child("LeftHandle", true, false) as Node3D
	var right_handle := creel.find_child("RightHandle", true, false) as Node3D
	mid = creel.global_transform.affine_inverse() * ((left.global_position + right_handle.global_position) * 0.5)
	var chest := player.global_position + Vector3.UP * 1.28 + forward * 0.12
	var body := player.get_node_or_null("BodyMesh") as NpcBase
	if body != null and body.visual != null and body.visual.skeleton != null:
		var skeleton := body.visual.skeleton
		var left_bone := skeleton.find_bone("upper_arm.L")
		var right_bone := skeleton.find_bone("upper_arm.R")
		if left_bone >= 0 and right_bone >= 0:
			var left_at := skeleton.to_global(skeleton.get_bone_global_pose(left_bone).origin)
			var right_at := skeleton.to_global(skeleton.get_bone_global_pose(right_bone).origin)
			chest = (left_at + right_at) * 0.5
	# The authored arms are about 0.51 m. The handles have to sit inside that reach.
	var handles_at := chest + forward * 0.32 + Vector3.DOWN * 0.06
	return Transform3D(basis, handles_at - basis * mid)


func _show_gear(slot: Dictionary, visible: bool) -> void:
	var buoy := slot.buoy as Node3D
	var rope := slot.rope as MeshInstance3D
	if visible:
		buoy.show()
		rope.show()
	else:
		buoy.hide()
		rope.hide()
		(slot.line as FishingLineShape).clear()


func _throw_spot() -> Dictionary:
	if manual or _deck_player() == null:
		var rail := _rail_world()
		if not _open_water(rail):
			return {"ok": false}
		return {"ok": true, "at": rail}
	var player := _deck_player()
	var lateral := _boat.global_transform.affine_inverse() * player.global_position
	var sign_x := 1.0 if lateral.x >= 0.0 else -1.0
	if absf(lateral.x) < 0.35:
		sign_x = 1.0 if hauler.position.x >= 0.0 else -1.0
	var outward := _boat.global_basis.x.normalized() * sign_x
	for step in [3.0, 3.8, 4.6]:
		var at := player.global_position + outward * float(step)
		if _open_water(at):
			return {"ok": true, "at": at}
	return {"ok": false}


func _update_hands() -> void:
	var creel: Node3D = null
	if _active >= 0 and _slots[_active].work.hands_bound():
		creel = _slots[_active].creel as Node3D
	if creel == null:
		_release_hands()
		return
	_bind_hands(creel)


func _bind_hands(creel: Node3D) -> void:
	if manual:
		return
	var player := _deck_player()
	if player == null:
		return
	var body := player.get_node_or_null("BodyMesh") as NpcBase
	if body == null or body.visual == null or body.visual.skeleton == null:
		return
	var left := creel.find_child("LeftHandle", true, false) as Node3D
	var right := creel.find_child("RightHandle", true, false) as Node3D
	if left == null or right == null:
		return
	if _hands == null or not is_instance_valid(_hands):
		var pose := HandPose.new() as SkeletonModifier3D
		pose.name = "TrapHandPose"
		pose.set("hand_mesh", body.visual.get_part("Hands") as MeshInstance3D)
		body.visual.skeleton.add_child(pose)
		_hands = pose
	_hands.set("creel", creel)
	_hands.set("right_handle", right)
	_hands.set("left_handle", left)
	_hands.active = true


func _release_hands() -> void:
	if _hands != null and is_instance_valid(_hands):
		_hands.call("release")
	_hands = null


func _draw_rope(slot: Dictionary, delta: float) -> void:
	var shown := _water_gear(slot)
	var creel := shown.creel as Node3D if not shown.is_empty() else slot.creel as Node3D
	var buoy := shown.buoy as Node3D if not shown.is_empty() else slot.buoy as Node3D
	var line: FishingLineShape = shown.line if not shown.is_empty() else slot.line
	var rope := shown.rope as MeshInstance3D if not shown.is_empty() else slot.rope as MeshInstance3D
	var work = slot.work
	var top := _haul_point.global_position if work.phase != PotWork.Phase.DEPLOYED and work.phase != PotWork.Phase.SINKING else _marker_position(buoy)
	var bridle := creel.find_child("BridleSocket", true, false) as Node3D
	var end := bridle.global_position if bridle != null else creel.global_position + Vector3.UP * 0.55
	var points := line.advance(delta, top, end, 0.35)
	var view := get_viewport().get_camera_3d()
	var mesh := rope.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if view == null or points.size() < 2:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in points.size():
		var tangent := points[mini(i + 1, points.size() - 1)] - points[maxi(0, i - 1)]
		var side := tangent.cross(view.global_position - points[i]).normalized()
		if side.length_squared() < 0.5:
			side = Vector3.RIGHT
		var radius := clampf(view.global_position.distance_to(points[i]) * 0.0012, 0.012, 0.045)
		mesh.surface_add_vertex(points[i] - side * radius)
		mesh.surface_add_vertex(points[i] + side * radius)
	mesh.surface_end()


func _separated(slot: Dictionary, xz: Vector2) -> Vector2:
	var along := Vector2(_boat.global_basis.z.x, _boat.global_basis.z.z)
	if along.length_squared() < 0.01:
		along = Vector2.UP
	along = along.normalized()
	for _step in 12:
		var clash := false
		for other in _slots:
			if int(other.index) == int(slot.index):
				continue
			if other.work.phase == PotWork.Phase.STOWED or other.work.phase == PotWork.Phase.CARRYING:
				continue
			if xz.distance_to(other.drop_xz) < 1.3:
				clash = true
		var field = _field()
		if field != null:
			for drop in field.drops():
				if xz.distance_to(drop) < 1.3:
					clash = true
		if not clash:
			break
		xz += along * 1.6
	return xz


func _rail_world() -> Vector3:
	var outward := _boat.global_basis.x.normalized()
	if hauler.position.x < 0.0:
		outward = -outward
	return _haul_point.global_position + outward * 1.2


func _depth_at(at: Vector3) -> float:
	if forced_depth > 0.0:
		return forced_depth
	if FishingField.habitat == null:
		return 22.0
	return maxf(0.0, _surface(Vector2(at.x, at.z)) - FishingField.habitat.bottom(Vector2(at.x, at.z)))


func _surface(at: Vector2) -> float:
	return WaveSurface.sample_at(at.x, at.y).height


func _open_water(at: Vector3) -> bool:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, Vector3(at.x, WaveSurface.WATER_LEVEL - 0.4, at.z), 1)
	query.exclude = [(_boat as RigidBody3D).get_rid()]
	var player := _deck_player()
	if player != null:
		query.exclude.append(player.get_rid())
	return space.intersect_ray(query).is_empty()


func _deck_player() -> CharacterBody3D:
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player == null or player.is_vehicle_occupied() or LocalPlayerView.is_helming():
		return null
	if LocalPlayerView.get_active_ship() != _boat:
		return null
	return player


func _aimed() -> Dictionary:
	var player := _deck_player()
	if player == null:
		return {}
	var camera := player.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 4.0, 16)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var collider := hit.get("collider") as Node
	if collider == null or not collider.has_meta("crab_role"):
		return {}
	if player.global_position.distance_to(collider.global_position) > REACH_M:
		return {}
	return {
		"role": str(collider.get_meta("crab_role")),
		"index": int(collider.get_meta("crab_index")),
		"pot_id": str(collider.get_meta("crab_pot_id", "")),
	}


func _say(text: String) -> void:
	_message = text
	_message_until = Time.get_ticks_msec() + 4000


func _smooth(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _local_center(part: Node3D) -> Vector3:
	var socket := part.find_child("BridleSocket", true, false) as Node3D
	if socket == null:
		return Vector3(0.0, 0.3, 0.0)
	return _local_point(part, socket) * 0.5


func _local_point(root: Node3D, node: Node3D) -> Vector3:
	var point := Vector3.ZERO
	var current := node
	while current != null and current != root:
		point = current.transform * point
		current = current.get_parent() as Node3D
	return point


func _area(host: Node3D, role: String, index: int, center: Vector3, radius: float) -> Area3D:
	var area := Area3D.new()
	area.name = "CrabInteraction"
	area.collision_layer = 16
	area.collision_mask = 0
	area.set_meta("crab_role", role)
	area.set_meta("crab_index", index)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	shape.position = center
	area.add_child(shape)
	host.add_child(area)
	return area


func _new_rope() -> MeshInstance3D:
	var rope := MeshInstance3D.new()
	rope.mesh = ImmediateMesh.new()
	rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rope.top_level = true
	rope.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var filament := StandardMaterial3D.new()
	filament.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	filament.albedo_color = Color(0.33, 0.42, 0.30)
	filament.cull_mode = BaseMaterial3D.CULL_DISABLED
	rope.material_override = filament
	add_child(rope)
	rope.global_transform = Transform3D.IDENTITY
	rope.hide()
	return rope


func _game_hours() -> float:
	var clock: Node = get_node_or_null("/root/WorldClock")
	if clock == null:
		return 0.0
	return float(clock.call("get_game_hours_elapsed"))


func _next_day_hours() -> float:
	var hours := _game_hours()
	return (floor(hours / 24.0) + 1.0) * 24.0


func _hours_left(slot: Dictionary) -> float:
	var ready := float(slot.ready_hours)
	var id := str(slot.get("pot_id", ""))
	var field = _field()
	if field != null and not id.is_empty() and bool(field.has_pot(id)):
		ready = float(field.ready_hours(id))
	return maxf(0.0, ready - _game_hours())


func _soak_ready(slot: Dictionary) -> bool:
	return _hours_left(slot) <= 0.0


func _soak_text(slot: Dictionary) -> String:
	var left := _hours_left(slot)
	if left <= 0.0:
		return "Ready"
	return "%d h" % int(ceil(left))


func _field():
	if not is_inside_tree():
		return null
	return PotField.ensure(get_tree())


func _owner_id() -> String:
	var summary: Dictionary = LocalPlayerView.get_company_summary()
	var company := str(summary.get("id", "")).strip_edges()
	if not company.is_empty():
		return company
	var captain := LocalPlayerView.get_captain_id().strip_edges()
	if not captain.is_empty():
		return captain
	return "local"


func _commit_pot(slot: Dictionary) -> void:
	var field = _field()
	var drop: Vector2 = slot.drop_xz
	var id := str(field.place(_owner_id(), drop, float(slot.work.depth_m), float(slot.ready_hours)))
	slot.pot_id = id
	field.claim(id, self)
	_park_deck_creel(slot)


func _park_deck_creel(slot: Dictionary) -> void:
	var creel := slot.creel as Node3D
	creel.top_level = false
	creel.transform = slot.rest
	creel.hide()
	(slot.area as Area3D).monitorable = false
	(slot.buoy as Node3D).hide()
	(slot.rope as MeshInstance3D).hide()
	(slot.line as FishingLineShape).clear()
	(slot.timer as Label3D).visible = false


func _adopt_world_pots() -> void:
	var field = _field()
	if field == null:
		return
	var taken := {}
	for slot in _slots:
		var existing := str(slot.get("pot_id", ""))
		if not existing.is_empty():
			taken[existing] = true
	for pot in field.unclaimed(_owner_id()):
		var id := str(pot.id)
		if taken.has(id) or not bool(field.claim(id, self)):
			continue
		var slot := _stowed_slot()
		if slot.is_empty():
			field.unclaim(id)
			break
		slot.pot_id = id
		slot.drop_xz = pot.drop
		slot.ready_hours = float(pot.ready_hours)
		slot.work.phase = PotWork.Phase.DEPLOYED
		slot.work.depth_m = float(pot.depth_m)
		_park_deck_creel(slot)
		taken[id] = true


func _stowed_slot() -> Dictionary:
	for slot in _slots:
		if slot.work.phase == PotWork.Phase.STOWED and str(slot.get("pot_id", "")).is_empty():
			return slot
	return {}


func _slot_for_pot(pot_id: String) -> int:
	for slot in _slots:
		if str(slot.get("pot_id", "")) == pot_id:
			return int(slot.index)
	return -1


func _water_gear(slot: Dictionary) -> Dictionary:
	var id := str(slot.get("pot_id", ""))
	var field = _field()
	if field == null or id.is_empty():
		return {}
	return field.gear(id)


func _new_timer(index: int) -> Label3D:
	var label := Label3D.new()
	label.name = "SoakTimer%d" % index
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.004
	label.outline_size = 16
	label.modulate = Color(1.0, 0.93, 0.62)
	label.position = Vector3(0.0, 0.55, 0.0)
	label.visible = false
	return label


func _show_timer(slot: Dictionary) -> void:
	var label := slot.timer as Label3D
	var buoy := slot.buoy as Node3D
	if slot.work.phase != PotWork.Phase.DEPLOYED or not buoy.visible:
		label.visible = false
		return
	var marker := buoy.get_meta("marker") as Node3D
	if label.get_parent() != marker:
		marker.add_child(label)
	label.text = _soak_text(slot)
	label.visible = true


func _new_buoy(index: int) -> Node3D:
	var root := (load(BUOY_SCENE) as PackedScene).instantiate() as Node3D
	SurfaceMaterialLibrary.apply(root)
	root.name = "PotBuoy%d" % index
	root.top_level = true
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var marker := root.find_child("Marker buoy", true, false) as Node3D
	assert(marker != null, "Pot buoy model requires Marker buoy")
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		mesh.visible = mesh == marker
	add_child(root)
	root.set_meta("marker", marker)
	var area := _area(marker, "buoy", index, Vector3.ZERO, 0.45)
	root.set_meta("area", area)
	root.hide()
	return root


func _float_buoy(slot: Dictionary) -> void:
	var drop: Vector2 = slot.drop_xz
	_place_buoy(slot.buoy, Vector3(drop.x, _surface(drop), drop.y))


func _place_buoy(root: Node3D, water: Vector3) -> void:
	var marker := root.get_meta("marker") as Node3D
	root.global_position += water + Vector3.UP * 0.2 - marker.global_position
	(root.get_meta("area") as Area3D).monitorable = true


func _marker_position(root: Node3D) -> Vector3:
	return (root.get_meta("marker") as Node3D).global_position
