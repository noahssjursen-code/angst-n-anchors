class_name FerryBoarding
extends Node

## A rigid, authored bow ramp. Its hinge stays on the ship; its roller end rests
## on the physical landing. Installed equipment, not the vessel name, owns this.
signal status_changed(text: String)
const STOW_ANGLE := PI * .5
const MAX_SLOPE := 12.0
const ROTATION_SPEED := .65
var boat: ImportedDraftVessel
var part: Node3D
var deployed := false
var status := "Ramp stowed"
var angle := STOW_ANGLE
var _rest := Transform3D.IDENTITY
var _hinge := Vector3.ZERO
var _length := 2.0
var _want_down := false
var _was_secured := false
var landing_rejection := ""
var _mount: Node3D
var _barrels: Array[Node3D] = []
var _rods: Array[Node3D] = []

func setup(owner_boat: ImportedDraftVessel, visual: Node3D) -> void:
	boat = owner_boat
	part = visual
	_rest = part.transform
	var hinge := part.find_child("RampHinge", true, false) as Node3D
	var tip := part.find_child("RampTip", true, false) as Node3D
	assert(hinge != null and tip != null)
	_hinge = hinge.position
	_length = hinge.position.distance_to(tip.position)
	part.set_meta("boarding_ramp", true)
	process_physics_priority = -21
	# Construct siblings before entering the scene tree; the part is busy
	# propagating child-ready callbacks when this component's _ready runs.
	_mount = _gear("ferry_ramp_mount",part)
	_mount.top_level = true
	for side in 2:
		var barrel := _gear("ferry_ramp_cylinder",_mount)
		_barrels.append(barrel)
		_rods.append(_gear("ferry_ramp_rod",barrel))
	_gear("ferry_ramp_landing",part,false)
	_pose()

func _ready() -> void:
	_pose()
	boat.departure_checks.append(departure_block_reason)
	boat.departure_requested.connect(request_stow)

func _exit_tree() -> void:
	if is_instance_valid(boat):
		boat.departure_checks.erase(departure_block_reason)
		if boat.departure_requested.is_connected(request_stow):
			boat.departure_requested.disconnect(request_stow)

func departure_block_reason() -> String:
	if angle >= STOW_ANGLE-.002 and not _want_down: return ""
	if occupied(): return "Keep clear of the bow ramp before casting off."
	return "Bow ramp stowing. Order lines off once it is secured."

func request_stow() -> void:
	_want_down = false

func request_boarding() -> bool:
	if not _secured(): return false
	if _landing_solution().is_empty(): return false
	_want_down = true
	return true

func _secured() -> bool:
	var mooring := boat.get_node_or_null("ShipGameplay/MooringComponent") as MooringComponent
	return mooring != null and mooring.bow_line_tied and mooring.stern_line_tied and boat.get_moored_berth() != null

func _physics_process(delta: float) -> void:
	var secured := _secured()
	if secured and not _was_secured: _want_down = true
	if not secured: _want_down = false
	_was_secured = secured
	var solution := _landing_solution() if secured else {}
	var target := float(solution.angle) if _want_down and not solution.is_empty() else STOW_ANGLE
	# Do not lift or lower a person. Once landed, small wave-following changes
	# remain active so their support never freezes in space as the hull heaves.
	if absf(target-angle) > .08 and occupied():
		deployed = false
		_set_status("Keep clear of the bow ramp")
		return
	angle = move_toward(angle, target, ROTATION_SPEED*delta)
	_pose()
	deployed = _want_down and not solution.is_empty() and absf(angle-target)<.012
	if deployed: _set_status("Boarding ramp ready")
	elif angle >= STOW_ANGLE-.002:
		_set_status(landing_rejection if _want_down else "Ramp stowed")
	else: _set_status("Ramp lowering" if target < angle else "Ramp stowing")

func _pose() -> void:
	var rotation := Basis(Vector3.RIGHT, angle)
	part.transform = _rest * Transform3D(rotation, _hinge-rotation*_hinge)
	if is_instance_valid(_mount):
		if _mount.is_inside_tree():
			_mount.global_transform = boat.global_transform * _rest * Transform3D(Basis.IDENTITY,_hinge)
		for i in 2:
			var side := -1.0 if i==0 else 1.0
			var base := Vector3(side*1.18,.4,1.0)
			var end := rotation*Vector3(side*1.18,0,-1.6)
			_barrels[i].transform = Transform3D(Basis.looking_at(end-base,Vector3.UP),base)
			_rods[i].position.z = -(end.distance_to(base)-1.35)

func _gear(asset: String, parent: Node3D, detail: bool = true) -> Node3D:
	var visual := (load("res://resources/models/parts/passenger_ferry/"+asset+".glb") as PackedScene).instantiate() as Node3D
	parent.add_child(visual)
	SurfaceMaterialLibrary.apply(visual,"composite_ferry")
	if detail:
		for mesh in visual.find_children("*","MeshInstance3D",true,false):
			mesh.set_meta("walk_detail_visual",true)
	return visual

func occupied() -> bool:
	if not part.is_inside_tree(): return false
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.25, 2.15, _length+.5)
	query.shape = shape
	query.transform = part.global_transform * Transform3D(Basis.IDENTITY, Vector3(0,1.075,0))
	query.collision_mask = BoatBody.LAYER_PLAYER
	return not part.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _landing_solution() -> Dictionary:
	var slot := boat.get_moored_berth() as QuayBerthSlot
	if slot == null or not slot.bow_in or not is_instance_valid(slot.boarding_landing): return _reject("No passenger landing")
	if Vector2(boat.linear_velocity.x,boat.linear_velocity.z).length() > .35: return _reject("Wait for the ferry to settle")
	var landing := slot.boarding_landing
	var rest_world := boat.global_transform * _rest
	var hinge_world := rest_world * _hinge
	var normal := landing.global_basis.y.normalized()
	var a := normal.dot(rest_world.basis.y)
	var b := normal.dot(-rest_world.basis.z)
	var radius := sqrt(a*a+b*b)
	if radius < .01: return _reject("Unsafe boarding angle")
	# Authored rollers sit 17 cm below the leaf; the tapered toe meets the pier.
	var height := normal.dot(landing.global_position+normal*.17-hinge_world)
	if absf(height) > _length*radius: return _reject("Landing outside ramp reach")
	var theta := asin(height/(_length*radius))-atan2(b,a)
	var rotation := Basis(Vector3.RIGHT,theta)
	var tip := hinge_world + rest_world.basis*rotation*Vector3(0,0,-_length)
	var span := tip-hinge_world
	if absf(rad_to_deg(asin(span.normalized().dot(normal)))) > MAX_SLOPE: return _reject("Boarding slope too steep")
	# Allow modest roll at the padded landing, never a steep sideways ramp.
	if absf(normal.dot(rest_world.basis.x)) > sin(deg_to_rad(5)): return _reject("Excessive roll for boarding")
	var local := landing.to_local(tip)
	var area: Vector2 = landing.get_meta("landing_size",Vector2(5.5,2.0))
	if absf(local.x)>area.x*.5-1.05 or absf(local.z)>area.y*.5-.12: return _reject("Align the bow with the passenger landing")
	# Both roller lanes need support. The centre can lie on a slab joint and its
	# tiny bevel; that is not an unusable landing and must not veto the ramp.
	for side: float in [-.8,.8]:
		var probe := tip+rest_world.basis.x*side
		var ray := PhysicsRayQueryParameters3D.create(probe+normal*.4,probe-normal*.4,BoatBody.LAYER_WORLD)
		var hit := part.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or not landing.get_parent().is_ancestor_of(hit.collider): return _reject("No solid pier under ramp")
		if hit.normal.dot(normal)<.95: return _reject("Uneven landing surface")
	var clearance := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.1,1.85,.45)
	clearance.shape = box
	clearance.transform = Transform3D(landing.global_basis,tip+normal*.97)
	clearance.collision_mask = BoatBody.LAYER_WORLD
	if not part.get_world_3d().direct_space_state.intersect_shape(clearance,1).is_empty(): return _reject("Obstructed passenger landing")
	landing_rejection = ""
	return {"angle":theta,"tip":tip,"hinge":hinge_world}

func _reject(reason: String) -> Dictionary:
	landing_rejection = reason
	return {}

func _set_status(text: String) -> void:
	if status == text: return
	status = text
	status_changed.emit(status)
