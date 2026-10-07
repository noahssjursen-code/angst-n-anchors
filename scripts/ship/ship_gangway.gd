class_name ShipGangway
extends Node3D

## Boarding is derived from replicated mooring, not a second ownership/save state.
## Authored ship-end hinge follows the hull; shore rollers land on actual quay physics.
const SPAN_MODEL := "res://resources/models/parts/gangway/boarding_gangway_4m.glb"
const ROLLER_MODEL := "res://resources/models/parts/gangway/gangway_landing_rollers.glb"
const WIDTH := .90
const MAX_SPAN := 8.0
const MAX_SLOPE := .60 # tangent: 31 degrees, below the player's walking limit
var boat: ImportedDraftVessel
var deployed := false
var ship_end := Vector3.ZERO
var shore_end := Vector3.ZERO
var status := "Not moored"
var _gates: Dictionary = {}
var _candidates: Dictionary = {}
var _active_gate: Node3D
var _active_closed := Transform3D.IDENTITY
var _walk: AnimatableBody3D
var _floor: CollisionShape3D
var _guards: Array[CollisionShape3D] = []
var _span: Node3D
var _rollers: Node3D
var _probe_time := 0.0
var _shore_valid := false
var _berth: QuayBerthSlot
var _side := 0

func _ready() -> void:
	process_physics_priority = -5
	refresh_gates()
	_walk = AnimatableBody3D.new()
	_walk.name = "GangwayWalk"
	_walk.sync_to_physics = false
	_walk.collision_layer = 0
	_walk.collision_mask = BoatBody.LAYER_PLAYER
	add_child(_walk)
	_walk.top_level = true
	_walk.set_meta("_boat_owner", boat)
	_floor = _box(Vector3(WIDTH,.10,4), Vector3(0,-.05,-2))
	for side in [-1,1]:
		_guards.append(_box(Vector3(.07,.98,4), Vector3(side*.49,.51,-2)))
	_span = (load(SPAN_MODEL) as PackedScene).instantiate()
	_walk.add_child(_span)
	SurfaceMaterialLibrary.apply(_span)
	_rollers = (load(ROLLER_MODEL) as PackedScene).instantiate()
	_walk.add_child(_rollers)
	SurfaceMaterialLibrary.apply(_rollers)
	for mesh in _walk.find_children("*", "MeshInstance3D", true, false):
		# Ramp has its own moving walk body, never bake a second copy into hull collision.
		mesh.set_meta("walk_detail_visual", true)
	_walk.hide()

func _box(size: Vector3, at: Vector3) -> CollisionShape3D:
	var node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	node.shape = shape
	node.position = at
	_walk.add_child(node)
	return node

func refresh_gates() -> void:
	_close_gate()
	deployed = false
	_gates.clear()
	_candidates.clear()
	# Existing straight 1 m bulwark modules become hinged boarding gates. The
	# authored model, paint, draft records and collision are retained.
	for side in [-1,1]:
		var candidates: Array[Dictionary] = []
		for part in boat.part_roots:
			var id := str(part.get_meta("asset_id", ""))
			if not id.begins_with("halfwall_straight_100cm_"): continue
			if absf(part.position.x-side*boat.beam_m*.5) > .05: continue
			if absf(part.position.y-boat.depth_m) > .05 or absf(part.rotation.y) > .01: continue
			part.set_meta("gangway_gate", true)
			candidates.append({"part":part, "closed":part.transform})
		candidates.sort_custom(func(a: Dictionary,b: Dictionary): return absf(a.part.position.z-1.0)<absf(b.part.position.z-1.0))
		_candidates[side] = candidates
	_shore_valid = false
	_probe_time = 0.0

func _physics_process(delta: float) -> void:
	if not is_instance_valid(boat) or _walk == null: return
	var mooring := boat.get_node_or_null("ShipGameplay/MooringComponent") as MooringComponent
	var berth := boat.get_moored_berth() as QuayBerthSlot
	if mooring == null or not mooring.is_moored or berth == null:
		_stow("Not moored")
		return
	if Vector2(boat.linear_velocity.x,boat.linear_velocity.z).length() > .8:
		_stow("Vessel moving")
		return
	var toward := boat.to_local(berth.global_position)
	var side := -1 if toward.x < 0 else 1
	if berth != _berth or side != _side:
		_close_gate()
		deployed = false
		_shore_valid = false
		_probe_time = 0.0
	_berth = berth
	_side = side
	_probe_time -= delta
	var probing := _probe_time <= 0.0
	if probing: _probe_time = .20
	if not deployed and probing:
		var candidate := _clear_gate(side)
		if candidate.is_empty():
			_gates.erase(side)
			_stow("No clear boarding gate",false)
			return
		_gates[side] = candidate
	if not _gates.has(side):
		_stow("No compatible boarding gate",false)
		return
	var gate: Node3D = _gates[side].part
	var closed: Transform3D = _gates[side].closed
	var local_end := closed * Vector3(0,.035,-.5)
	local_end.x -= side*.24
	ship_end = boat.to_global(local_end)
	if probing:
		_shore_valid = _find_shore(berth)
	if not _shore_valid:
		_stow("No clear quay landing", false)
		return
	var span := shore_end-ship_end
	var horizontal := Vector2(span.x,span.z).length()
	if horizontal < .5 or span.length() > MAX_SPAN or absf(span.y) > horizontal*MAX_SLOPE:
		_stow("Outside gangway reach", false)
		return
	if _active_gate != gate:
		_close_gate()
		_active_gate = gate
		_active_closed = closed
	gate.transform = closed * Transform3D(Basis(Vector3.UP,-side*PI*.5),Vector3.ZERO)
	var length := span.length()
	_walk.global_transform = Transform3D(Basis.looking_at(span,Vector3.UP),ship_end)
	_span.scale.z = length/4.0
	_rollers.position.z = -length
	(_floor.shape as BoxShape3D).size.z = length
	_floor.position.z = -length*.5
	for guard in _guards:
		(guard.shape as BoxShape3D).size.z = length
		guard.position.z = -length*.5
	_walk.collision_layer = BoatBody.LAYER_BOAT_WALK
	_walk.show()
	deployed = true
	status = "Gangway deployed"

func _clear_gate(side: int) -> Dictionary:
	if boat.get_walk_deck() == null: return {}
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .36
	capsule.height = 1.85
	query.shape = capsule
	query.collision_mask = BoatBody.LAYER_BOAT_WALK | BoatBody.LAYER_WORLD
	query.exclude = [_walk.get_rid()]
	for entry: Dictionary in _candidates.get(side,[]):
		var point: Vector3 = entry.closed * Vector3(0,.975,-.5)
		var clear := true
		for inset in [.6,1.0]:
			var position := point-Vector3(side*inset,0,0)
			query.transform = Transform3D(boat.global_basis,boat.to_global(position))
			if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():
				clear = false
				break
		if clear: return entry
	return {}

func _find_shore(berth: QuayBerthSlot) -> bool:
	var water := berth.water_dir_local.normalized()
	var point := berth.to_local(ship_end)
	point += water*(berth.face_offset_m-.9-point.dot(water))
	var target := berth.to_global(point)
	var query := PhysicsRayQueryParameters3D.create(target+Vector3.UP*5,target-Vector3.UP*8,BoatBody.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.dot(Vector3.UP) < .9: return false
	# A real clear landing for a player's capsule; never land through a warehouse,
	# bollard or crane. No teleportation or generated platform under the player.
	var clearance := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .34
	capsule.height = 1.8
	clearance.shape = capsule
	clearance.transform.origin = hit.position+Vector3.UP*.96
	clearance.collision_mask = BoatBody.LAYER_WORLD
	if not get_world_3d().direct_space_state.intersect_shape(clearance,1).is_empty(): return false
	shore_end = hit.position+Vector3.UP*.035
	return true

func _close_gate() -> void:
	if is_instance_valid(_active_gate):
		_active_gate.transform = _active_closed
	_active_gate = null

func _stow(reason: String, clear_berth := true) -> void:
	deployed = false
	status = reason
	_close_gate()
	if is_instance_valid(_walk):
		_walk.hide()
		_walk.collision_layer = 0
	if clear_berth:
		_berth = null
		_shore_valid = false

func _exit_tree() -> void:
	_close_gate()
