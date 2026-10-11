class_name CharacterLegIK
extends SkeletonModifier3D

## A gait in metres/seconds, with contacts stored in the support's frame.
## Only advance state on positive delta; Godot can also request zero-time poses.
## Bone lengths stay authored. IK owns legs/pelvis, FK owns shoulders and elbows.
const ANKLE := 0.12
const STANCE_X := 0.11
## Sole extents of the authored mariner boot, relative to its ankle.
const TOE_LENGTH := .17
const HEEL_LENGTH := .095

class Foot:
	var contact := Vector3.ZERO
	var start := Vector3.ZERO
	var target := Vector3.ZERO
	var lift := 0.0
	var swing := false
	var duration := 0.3
	var height := 0.12
	var was_stance := true
	var start_cycle := 0.0
	var end_cycle := 1.0
	var progress := 0.0
	var cycle_step := false
	var heel := 0.0
	var heading := Vector3.FORWARD
	var angle := 0.0
	var angle_start := 0.0
	var stance_time := 0.0

var _feet: Array[Foot] = [Foot.new(), Foot.new()]
var _actor: CharacterBody3D
var _bones: Dictionary = {}
var _thigh_len := 0.42
var _shin_len := 0.39
var _ready_contacts := false
var _support_id := 0
var _support := Transform3D.IDENTITY
var _phase := 0.0
var _cycles := 0.0
var _speed := 0.0
var _velocity := Vector3.ZERO
var _moving := false
var _grounded := false
var _lean := Vector3.ZERO
var _drop := 0.015
var _motion_frame := -1
var _last_position := Vector3.ZERO
var _air_blend := 0.0
var _settle_delay := 0.0
var _torso_yaw := 0.0
var _twist := 0.0
var _plant_yaw: Array[float] = [0.0, 0.0]
var _gait_weight := 0.0
var _weight_shift := 0.0
var _arm_swing: Array[float] = [0.0, 0.0]
var _yaw_velocity := 0.0
var _last_support_yaw := 0.0
var _support_velocity := Vector3.ZERO
var _travel_lean := Vector3.ZERO
var _travel_lean_rate := Vector3.ZERO

## Let the feet step through a heading change before the hips twist past them.
## Camera intent stays immediate; the controller slows travel until the body aligns.
func limit_grounded_turn(yaw_step: float) -> float:
	if not _ready_contacts or not _grounded or _air_blend > .1 or (_feet[0].swing and _feet[1].swing):
		return yaw_step
	var support: Transform3D = _actor.mount_deck_transform() if _support_id != 0 else Transform3D.IDENTITY
	var separation := support.basis * (_feet[0].contact - _feet[1].contact)
	var current := separation.dot(_actor.global_basis.x)
	var proposed := separation.dot(_actor.global_basis.x.rotated(Vector3.UP, yaw_step))
	if proposed >= .12 or proposed >= current:
		return yaw_step
	if current < .12:
		return 0.0
	var low := 0.0
	var high := 1.0
	for iteration in 6:
		var middle := (low + high) * .5
		if separation.dot(_actor.global_basis.x.rotated(Vector3.UP, yaw_step * middle)) >= .12:
			low = middle
		else:
			high = middle
	return yaw_step * low

func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null: return
	if _actor == null and not _cache(skeleton): return
	if not is_instance_valid(_actor): return
	if _actor.is_vehicle_occupied(): return
	var id: int = _actor.deck_support_id()
	var support: Transform3D = _actor.mount_deck_transform() if id != 0 else Transform3D.IDENTITY
	var normal := support.basis.y.normalized() if id != 0 else Vector3.UP
	var frame := Engine.get_process_frames()
	var dt := 0.0
	if delta > 0.0 and frame != _motion_frame:
		_motion_frame = frame
		dt = delta
	# Changing decks, teleporting or respawning invalidates the old anchors.
	var local_position := support.affine_inverse() * _actor.global_position
	if not _ready_contacts or id != _support_id or local_position.distance_to(_last_position) > 2.0:
		_support = support
		_support_id = id
		_reset_contacts(normal)
	_last_position = local_position
	_support = support
	if dt > 0.0:
		_advance(dt, normal)
	# Reconstruct from bind every time: never integrate a solved pose back into itself.
	for bone: int in _bones.values():
		skeleton.set_bone_pose(bone, skeleton.get_bone_rest(bone))
	_pose_body(skeleton)
	for i in 2:
		_solve_leg(skeleton, i, normal)
	_pose_arms(skeleton)

func _cache(skeleton: Skeleton3D) -> bool:
	var node: Node = self
	while node != null:
		if node is CharacterBody3D and node.is_in_group("player"):
			_actor = node as CharacterBody3D
			break
		node = node.get_parent()
	if _actor == null: return false
	for name in ["hips", "spine", "chest", "neck", "head", "thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R", "upper_arm.L", "forearm.L", "upper_arm.R", "forearm.R"]:
		var index := skeleton.find_bone(name)
		if index < 0: return false
		_bones[name] = index
	_thigh_len = skeleton.get_bone_rest(_bones["shin.L"]).origin.length()
	_shin_len = skeleton.get_bone_rest(_bones["foot.L"]).origin.length()
	return true

func _reset_contacts(normal: Vector3) -> void:
	_ready_contacts = false
	for i in 2:
		var foot := _feet[i]
		foot.contact = _placement(i, Vector3.ZERO, normal)
		foot.start = foot.contact
		foot.target = foot.contact
		foot.lift = 0.0
		foot.swing = false
		foot.was_stance = true
		foot.heading = (_support.basis.inverse() * -_actor.global_basis.z).normalized()
		foot.angle = 0.0
		foot.stance_time = .2
		_plant_yaw[i] = _actor.rotation.y
	_ready_contacts = true
	_moving = false
	_grounded = _actor.is_on_floor()
	var back := _support.basis.inverse() * _actor.global_basis.z
	_last_support_yaw = atan2(back.x, back.z)
	_yaw_velocity = 0.0
	_support_velocity = _support.basis.inverse() * _actor.locomotion_velocity()

func _advance(dt: float, normal: Vector3) -> void:
	var velocity: Vector3 = _actor.locomotion_velocity()
	velocity -= normal * velocity.dot(normal)
	_velocity = _velocity.lerp(velocity, 1.0 - exp(-14.0 * dt))
	_speed = _velocity.length()
	var back := _support.basis.inverse() * _actor.global_basis.z
	var yaw := atan2(back.x, back.z)
	_yaw_velocity = lerpf(_yaw_velocity, clampf(wrapf(yaw - _last_support_yaw, -PI, PI) / dt, -4.0, 4.0), 1.0 - exp(-8.0 * dt))
	_last_support_yaw = yaw
	var landed := _actor.is_on_floor() and not _grounded
	_grounded = _actor.is_on_floor()
	_air_blend = move_toward(_air_blend, 0.0 if _grounded else 1.0, dt * 8.0)
	if landed: _reset_contacts(normal)
	var was_moving := _moving
	_moving = _grounded and _speed > (.12 if _moving else .23)
	# Walking step length grows with speed up to what the short legs can cover
	# with heel-off and a little pelvis drop. Faster movement becomes a running
	# gait, shortening ground contact rather than cranking tiny steps.
	var run := smoothstep(2.2, 3.4, _speed)
	var step := clampf(.43 + _speed * .18, .43, .80)
	# Sideways steps are short; legs cannot reach across the body like forward.
	var sideways := 0.0
	var backwards := 0.0
	if _speed > .05:
		sideways = absf(_velocity.normalized().dot(_actor.global_basis.x))
		backwards = maxf(0.0, _velocity.normalized().dot(_actor.global_basis.z))
		# The longer forward stride must not turn a deliberate lateral step into
		# a split. Retain the quicker support exchange when travelling sideways.
		step = lerpf(step, clampf(.34 + _speed * .13, .34, .60), smoothstep(.25, .6, sideways))
		step *= lerpf(1.0, .42, sideways)
		# Retreat has no forward toe-off to extend the supporting leg's reach.
		step *= lerpf(1.0, .86, backwards)
	var walk_frequency := clampf(_speed / (2.0 * step), .7, 2.0)
	var frequency := lerpf(walk_frequency, clampf(1.55 + _speed * .14, 1.85, 2.85), run)
	var duty := lerpf(.60, clampf(.8 / maxf(_speed / frequency, .1), .24, .43), run)
	if _moving:
		if not was_moving and not _feet[0].swing and not _feet[1].swing:
			# From a neutral stance the first foot must lift immediately. Waiting
			# through a full stance while accelerating drags both feet behind us.
			_cycles = ceilf(_cycles - duty) + duty
			for foot in _feet: foot.was_stance = true
		else:
			_cycles += dt * frequency
		_phase = fposmod(_cycles, 1.0)
	_update_lean(normal, dt)
	_update_travel_lean(velocity, dt)
	_twist = lerpf(_twist, _actor.look_twist(), 1.0 - exp(-14.0 * dt))
	_settle_delay = maxf(0, _settle_delay - dt)
	for i in 2:
		var foot := _feet[i]
		var phase := fposmod(_phase + i * .5, 1.0)
		var stance := phase < duty
		var trail := (_actor.global_position - _support * foot.contact).dot(_velocity.normalized())
		var reach_step := trail > lerpf(lerpf(.60, .50, backwards), .43, sideways)
		# Walking transfers support before the next pickup. Only a running gait
		# has a flight phase; recovery steps must respect the same handover.
		var can_lift := not _feet[1 - i].swing or run > .5
		if _moving and not foot.swing and can_lift and (foot.was_stance and not stance or not was_moving and not stance or reach_step):
			# The outward side-step lands promptly so the following leg can move
			# before the body pulls away from it. Equal swing times stretch that
			# trailing leg; alternating support does not require identical steps.
			var outward := _velocity.dot(_actor.global_basis.x) * (1.0 if i == 0 else -1.0) > .2
			var swing_cycle := (1.0 - duty) * (1.0 - .30 * sideways if outward else 1.0)
			_begin_step(foot, swing_cycle / frequency, lerpf(.07, .17, run))
			foot.cycle_step = true
			foot.start_cycle = _cycles + i * .5
			foot.end_cycle = minf(floorf(foot.start_cycle) + 1.0, foot.start_cycle + swing_cycle)
		if foot.swing:
			# Predict touchdown from the body speed, then hold in support coordinates.
			# A planted contact is never regenerated at the player's new position.
			# Touch down slightly less than half the stance ahead. The trailing half
			# is covered by heel-off; an over-long lead can only be met by sliding.
			# Sideways the leading foot lands a whole stance out so the body can
			# travel across it without reaching the other leg's lane.
			var remaining := maxf(0.0, foot.end_cycle - (_cycles + i * .5)) / frequency if foot.cycle_step else foot.duration * (1.0 - foot.progress)
			# The body will travel while this foot is still in the air. Omitting
			# that travel left each landing behind its intended position, forcing
			# a second recovery step before the other foot could finish landing.
			var lead := _velocity * (maxf(0.0, remaining) + duty / frequency * lerpf(.40, .85, smoothstep(.45, .95, sideways))) if _moving else Vector3.ZERO
			# Commit the landing spot before descent. Re-aiming at the last moment
			# makes the foot chase a moving target along the ground.
			if foot.progress < .7:
				foot.target = _placement(i, lead, normal, clampf(_yaw_velocity * remaining, -.45, .45), _velocity * remaining)
			if foot.cycle_step and _moving:
				# Touchdown stays in phase even as slope changes the player's speed.
				# A fixed wall-clock swing can otherwise land halfway through stance.
				foot.progress = maxf(foot.progress, (_cycles + i * .5 - foot.start_cycle) / maxf(.01, foot.end_cycle - foot.start_cycle))
			else:
				# A stop/reversal must never rewind an already airborne foot when
				# the walking cycle restarts. Finish this placement in elapsed time.
				foot.cycle_step = false
				foot.progress += dt / foot.duration
			var u := clampf(foot.progress, 0.0, 1.0)
			# Pick up, carry, set down: horizontal travel waits for clearance and
			# finishes before the foot descends, so it never skids along the floor.
			var carry := smoothstep(0.0, 1.0, u)
			# Steer the path inside this foot's lane. Clamping the current contact
			# instead snapped a swinging foot across in one frame.
			var path := foot.start.lerp(foot.target, carry)
			# Establish lateral clearance during pickup, before the forward carry.
			# Waiting until mid-swing let a turning body drag the airborne boot
			# through the planted leg during rapid reversals.
			var desired := path.lerp(_constrain_contact(i, path, normal), smoothstep(0.0, .15, u))
			# Only a guard against teleport-sized jumps. A tight rate limit made the
			# foot trail its path and finish the step scraping along the ground.
			foot.contact = foot.contact.move_toward(desired, (6.0 + _speed * 3.0) * dt)
			# A continuous low arc, rather than lifting vertically, carrying at
			# a fixed height and dropping vertically like a marching mechanism.
			var arc := foot.height * sin(u * PI)
			if foot.contact.distance_to(desired) > .02:
				arc = maxf(arc, .035)
			foot.lift = move_toward(foot.lift, arc, dt * 6.0)
			var heading := _support.basis.inverse() * -_actor.global_basis.z
			foot.heading = foot.heading.slerp(heading.normalized(), 1.0 - exp(-12.0 * dt)).normalized()
			var travel_forward := clampf(_velocity.dot(-_actor.global_basis.z) / maxf(_speed, .01), -1.0, 1.0)
			var strike := .16 * travel_forward
			# Toe-off, knee recovery, then ankle extension for the next contact.
			foot.angle = lerpf(foot.angle_start, -.18 * travel_forward, smoothstep(0.0, .35, u))
			foot.angle = lerpf(foot.angle, strike, smoothstep(.35, .88, u))
			if u >= 1.0:
				foot.target = desired
			if u >= 1.0 and foot.contact.distance_to(foot.target) < .015:
				foot.swing = false
				foot.contact = foot.target
				foot.lift = 0.0
				foot.stance_time = 0.0
				_plant_yaw[i] = _actor.rotation.y
				_settle_delay = .1
		elif _grounded and not _feet[1 - i].swing and (_plant_must_recover(i, foot.contact, normal) \
				or absf(wrapf(_actor.rotation.y - _plant_yaw[i], -PI, PI)) > deg_to_rad(40.0)):
			# Quick turns and reversals: step this foot round rather than leave it
			# twisted behind or across the new heading.
			_begin_step(foot, .22, .09)
		# Remember a pickup that was waiting for the other foot to land.
		foot.was_stance = stance or (not foot.swing and not can_lift)
		if not foot.swing:
			foot.stance_time += dt
			var heading := _support.basis * foot.heading
			var forward_speed := _velocity.dot(heading)
			var offset := (_support * foot.contact - _actor.global_position).dot(heading)
			var strike := .16 * signf(forward_speed) * (1.0 - smoothstep(0.0, .09, foot.stance_time))
			var push := -.85 * smoothstep(.06, .53, -offset) if forward_speed >= 0.0 else .45 * smoothstep(.08, .42, offset)
			var pitch := strike + push * smoothstep(.3, 1.0, absf(forward_speed))
			foot.angle = lerpf(foot.angle, pitch, 1.0 - exp(-25.0 * dt))
	# Reposition ONE foot after stopping or turning, with a full settling step.
	# Small wave-driven weight shifts do not continuously shuffle the feet.
	if _grounded and not _moving and not _feet[0].swing and not _feet[1].swing and _settle_delay <= 0:
		# A pivot in place barely moves a narrow stance in metres, so also
		# step when the root has yawed away from where this foot was planted.
		var errors: Array[float] = []
		for i in 2:
			var error := _feet[i].contact.distance_to(_placement(i, Vector3.ZERO, normal))
			if absf(wrapf(_actor.rotation.y - _plant_yaw[i], -PI, PI)) > deg_to_rad(20.0):
				error = maxf(error, .13)
			errors.append(error)
		var pick := 0 if errors[0] > errors[1] else 1
		if errors[pick] > .12:
			_begin_step(_feet[pick], .30, .075)
	_gait_weight = lerpf(_gait_weight, smoothstep(.15, 1.0, _speed) * (1.0 - _air_blend), 1.0 - exp(-8.0 * dt))
	var support_side := sin(_phase * TAU)
	_weight_shift = lerpf(_weight_shift, support_side * _gait_weight, 1.0 - exp(-10.0 * dt))
	for i in 2:
		# Counter-swing follows the actual leg, including backwards steps and
		# recovery placements, instead of a separate forward-only metronome.
		var leg_forward := (_support * _feet[i].contact - _actor.global_position).dot(-_actor.global_basis.z)
		var arm_target := clampf(-leg_forward * lerpf(1.0, 1.5, run), -.65, .65) * _gait_weight
		_arm_swing[i] = lerpf(_arm_swing[i], arm_target, 1.0 - exp(-12.0 * dt))
	_update_drop(normal, dt)

func _begin_step(foot: Foot, duration: float, height: float) -> void:
	foot.swing = true
	foot.angle_start = foot.angle
	foot.start = foot.contact
	foot.duration = maxf(.16, duration)
	foot.height = height
	foot.progress = 0.0
	foot.cycle_step = false

func _placement(i: int, lead: Vector3, normal: Vector3, yaw_ahead: float = 0.0, anticipation: Vector3 = Vector3.ZERO) -> Vector3:
	var side := STANCE_X if i == 0 else -STANCE_X
	# Widen the stance slightly at sea, without moving contacts on every wave.
	if _support_id != 0: side *= 1.12
	var point := _actor.global_position + (_actor.global_basis * Vector3(side, 0, 0)).rotated(normal, yaw_ahead) + lead
	point -= normal * (point - _actor.global_position).dot(normal)
	point = _support * _constrain_contact(i, _support.affine_inverse() * point, normal, anticipation)
	# Resolve actual steps/sloping ground at touchdown. Small bounded rays, no
	# persistent physics objects and no dependence on an ocean height estimate.
	var query := PhysicsRayQueryParameters3D.create(point + normal * .45, point - normal * .5, _actor.collision_mask, [_actor.get_rid()])
	var hit := _actor.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.normal.dot(normal) > .65:
		point = hit.position
	return _support.affine_inverse() * point

func _plant_must_recover(i: int, point: Vector3, normal: Vector3) -> bool:
	# Heading changes from looking around shift a forward plant's lane by
	# millimetres. That is not a crossed step. Recover only when this foot is
	# actually through the other one, or outside a full reachable stride.
	var right := _actor.global_basis.x.slide(normal).normalized()
	if right.length_squared() < .0001:
		return false
	var forward := normal.cross(right).normalized()
	var mine := _support * point
	var offset := mine - _actor.global_position
	var side := 1.0 if i == 0 else -1.0
	var lateral := offset.dot(right) * side
	var longitudinal := offset.dot(forward)
	var through_other := lateral < -.02 and mine.distance_to(_support * _feet[1 - i].contact) < .16
	return through_other or lateral > .55 or absf(longitudinal) > .62

func _constrain_contact(i: int, point: Vector3, normal: Vector3, anticipation: Vector3 = Vector3.ZERO) -> Vector3:
	# Keep each foot in its own reachable lane, measured on the supporting plane.
	# This also constrains the swing path, not just its final touchdown location.
	var right := _actor.global_basis.x.slide(normal).normalized()
	var forward := normal.cross(right).normalized()
	# A future landing is reachable from the future pelvis, not today's pelvis.
	# Swing-path checks still use the present frame (the default zero offset).
	var centre := _actor.global_position + anticipation
	var offset := _support * point - centre
	var side := 1.0 if i == 0 else -1.0
	# During a side-step the following foot must close toward the leading foot.
	# Forcing both targets to remain on their half of the moving pelvis leaves
	# the following leg behind and stretches the character into a split.
	var lateral := clampf(offset.dot(right), side * STANCE_X - .38, side * STANCE_X + .38)
	# Step AROUND the supporting boot. Its contact remains fixed even when
	# the hips turn across it; only the airborne foot changes its path.
	if _ready_contacts:
		var other := _support * _feet[1 - i].contact - centre
		lateral = maxf(lateral * side, other.dot(right) * side + .14) * side
	# A downward-sloping step also consumes vertical leg reach. Shorten the
	# placement on steep decks instead of asking fixed-length legs to stretch.
	var reach := .48 - absf(forward.y) * .50
	var longitudinal := clampf(offset.dot(forward), -reach, reach)
	return _support.affine_inverse() * (centre + right * lateral + forward * longitudinal + normal * offset.dot(normal))

func _update_lean(normal: Vector3, dt: float) -> void:
	var inverse := _actor.global_basis.inverse()
	var up := inverse * normal
	var uphill := Vector3(-up.x, 0, -up.z)
	var accel: Vector3 = inverse * _actor.deck_accel()
	var raw := uphill * .36 - Vector3(accel.x, 0, accel.z) * .018
	# Lean into the effort of making headway on a steep deck, but let the
	# counterbalance dominate at rest. This follows actual relative travel.
	if _support_id != 0 and _speed > .15:
		var direction := inverse * _velocity.normalized()
		var effort: float = 1.0 - _actor.deck_pace_scale()
		raw += Vector3(direction.x, 0, direction.z) * effort * .07
	raw.x = clampf(raw.x, -.10, .10)
	raw.z = clampf(raw.z, -.09, .09)
	# Exponential damping is frame-rate independent and zero-delta is a no-op.
	_lean = _lean.lerp(raw, 1.0 - exp(-5.0 * dt))

func _ankle(skeleton: Skeleton3D, i: int, normal: Vector3) -> Vector3:
	var foot := _feet[i]
	var forward := (_support.basis * foot.heading).slide(normal).normalized()
	# Rigid boot rolling about its heel or toe. The ground contact is fixed;
	# the ankle describes an arc around it, with the same pitch as the boot.
	var pivot := TOE_LENGTH if foot.angle < 0.0 else -HEEL_LENGTH
	var right := forward.cross(normal).normalized()
	var offset := forward * pivot - (forward * pivot - normal * ANKLE).rotated(right, foot.angle)
	var world := _support * foot.contact + offset + normal * foot.lift
	var air := _actor.global_position + _actor.global_basis * Vector3(STANCE_X if i == 0 else -STANCE_X, .18, .04)
	return skeleton.global_transform.affine_inverse() * world.lerp(air, _air_blend)

func _update_travel_lean(velocity: Vector3, dt: float) -> void:
	# Work relative to the deck: its world speed must not pitch a standing
	# sailor forward. Filter displacement before differentiating, then give
	# the upper body its own critically damped response to effort and braking.
	var measured := _support.basis.inverse() * velocity
	var next_velocity := _support_velocity.lerp(measured, 1.0 - exp(-10.0 * dt))
	var acceleration := (next_velocity - _support_velocity) / dt
	_support_velocity = next_velocity
	var target := (_support_velocity * .050 + acceleration * .018) * (1.0 - _air_blend)
	target.y = 0.0
	target = target.limit_length(.24)
	var frequency := 9.0
	var offset := _travel_lean - target
	var impulse := _travel_lean_rate + offset * frequency
	var decay := exp(-frequency * dt)
	_travel_lean = target + (offset + impulse * dt) * decay
	_travel_lean_rate = (_travel_lean_rate - impulse * frequency * dt) * decay

func _update_drop(normal: Vector3, dt: float) -> void:
	var skeleton := get_skeleton()
	# Rise over the support leg and absorb the next contact. This is the base
	# motion; terrain/reach correction is bounded and cannot drive a deep crouch.
	var target := lerpf(.018, .023 + .035 * (.5 + .5 * cos(_phase * TAU * 2.0)), _gait_weight)
	var needed := target
	for i in 2:
		var thigh: int = _bones["thigh.L" if i == 0 else "thigh.R"]
		var hip := skeleton.get_bone_global_rest(thigh).origin + Vector3(_lean.x * .5 + _weight_shift * .018, 0, _lean.z * .4)
		var ankle := _ankle(skeleton, i, normal)
		if _feet[i].swing:
			# Prepare the pelvis for the landing before the boot reaches ground.
			# Waiting until touchdown forced the length-limited IK to drag the
			# ankle into place while the smoothed pelvis caught up.
			ankle -= _axis(skeleton, normal) * _feet[i].lift * smoothstep(.45, .8, _feet[i].progress)
		var flat := Vector2(ankle.x - hip.x, ankle.z - hip.z).length()
		var reach := _thigh_len + _shin_len - .012
		var vertical := sqrt(maxf(.01, reach * reach - flat * flat))
		needed = maxf(needed, hip.y - ankle.y - vertical)
	target = clampf(maxf(target, needed), .018, .09 if _support_id == 0 else .12)
	_drop = lerpf(_drop, target, 1.0 - exp(-12.0 * dt))

func _pose_body(skeleton: Skeleton3D) -> void:
	var hips: int = _bones["hips"]
	var pose := skeleton.get_bone_global_pose(hips)
	pose.origin += Vector3(_lean.x * .5 + _weight_shift * .018, -_drop, _lean.z * .4)
	var pelvic_yaw := (_arm_swing[1] - _arm_swing[0]) * .10
	pose.basis = (Basis(Quaternion(_axis(skeleton, Vector3.UP), pelvic_yaw) * Quaternion(_axis(skeleton, -_actor.global_basis.z), -_weight_shift * .025)) * pose.basis).orthonormalized()
	skeleton.set_bone_global_pose(hips, pose)
	var right := _axis(skeleton, _actor.global_basis.x)
	var forward := _axis(skeleton, -_actor.global_basis.z)
	# Look fills the head first, then the stomach and chest. The root is the
	# legs, so they yaw only after both of those are saturated.
	var head_limit := deg_to_rad(_actor.LOOK_HEAD_DEG)
	var torso_limit := deg_to_rad(_actor.LOOK_TORSO_DEG)
	var head := clampf(_twist * .65, -head_limit, head_limit)
	var torso := clampf(_twist - head, -torso_limit, torso_limit)
	head = clampf(_twist - torso, -head_limit, head_limit)
	var gait_twist := (_arm_swing[0] - _arm_swing[1]) * .08
	var inertia := _actor.global_basis.inverse() * _support.basis * _travel_lean
	var roll := clampf(inertia.x, -.16, .16)
	var pitch := clampf(inertia.z, -.24, .18)
	_face_yaw(skeleton, _bones["spine"], torso * .45 + gait_twist * .5, Quaternion(forward, _lean.x * 1.6 + roll * .55) * Quaternion(right, _lean.z * 1.6 + pitch * .55))
	_face_yaw(skeleton, _bones["chest"], torso + gait_twist, Quaternion(forward, _lean.x * .45 + roll) * Quaternion(right, _lean.z * .4 + pitch))
	# The head follows the torso with partial stabilization, rather than
	# remaining bolted upright while the shoulders move underneath it.
	_face_yaw(skeleton, _bones["neck"], torso + head * .4, Quaternion(forward, roll * .75) * Quaternion(right, pitch * .75))
	_face_yaw(skeleton, _bones["head"], torso + head, Quaternion(forward, roll * .45) * Quaternion(right, pitch * .45))
	_torso_yaw = torso

func _solve_leg(skeleton: Skeleton3D, i: int, normal: Vector3) -> void:
	var suffix := ".L" if i == 0 else ".R"
	var thigh: int = _bones["thigh" + suffix]
	var shin: int = _bones["shin" + suffix]
	var foot: int = _bones["foot" + suffix]
	var ankle := _ankle(skeleton, i, normal)
	var hip := skeleton.get_bone_global_pose(thigh).origin
	var n := _axis(skeleton, normal)
	var forward := _axis(skeleton, _support.basis * _feet[i].heading)
	forward = (forward - n * forward.dot(n)).normalized()
	var ground := skeleton.global_transform.affine_inverse() * (_support * _feet[i].contact)
	_feet[i].heel = maxf(0.0, (ankle - ground).dot(n) - ANKLE - _feet[i].lift)
	var span := ankle - hip
	var distance := clampf(span.length(), .05, _thigh_len + _shin_len - .005)
	var direction := span.normalized()
	ankle = hip + direction * distance
	var pole := _axis(skeleton, -_actor.global_basis.z) + _axis(skeleton, _actor.global_basis.x) * (.08 if i == 0 else -.08)
	var bend := (pole - direction * pole.dot(direction)).normalized()
	var along := (_thigh_len * _thigh_len - _shin_len * _shin_len + distance * distance) / (2.0 * distance)
	var knee := hip + direction * along + bend * sqrt(maxf(0, _thigh_len * _thigh_len - along * along))
	_aim(skeleton, thigh, knee)
	_aim(skeleton, shin, ankle)
	var rest := skeleton.get_bone_global_rest(foot)
	var current := skeleton.get_bone_global_pose(foot)
	var right := forward.cross(n).normalized()
	current.basis = (Basis(right, n, -forward) * Basis(Vector3.RIGHT, _feet[i].angle * (1.0 - _air_blend)) * rest.basis).orthonormalized()
	skeleton.set_bone_global_pose(foot, current)

func _pose_arms(skeleton: Skeleton3D) -> void:
	var up := _axis(skeleton, Vector3.UP)
	var right := _axis(skeleton, _actor.global_basis.x).rotated(up, _torso_yaw)
	var forward := _axis(skeleton, -_actor.global_basis.z).rotated(up, _torso_yaw)
	var run := smoothstep(2.0, 4.0, _speed)
	for i in 2:
		var suffix := ".L" if i == 0 else ".R"
		var sign := 1.0 if i == 0 else -1.0
		var swing := _arm_swing[i]
		_rotate(skeleton, _bones["upper_arm" + suffix], Quaternion(forward, sign * .20) * Quaternion(right, swing))
		_rotate(skeleton, _bones["forearm" + suffix], Quaternion(right, lerpf(.25 + maxf(0.0, swing) * .3, .95, run)))

func _aim(skeleton: Skeleton3D, bone: int, target: Vector3) -> void:
	var current := skeleton.get_bone_global_pose(bone)
	var to := target - current.origin
	if to.length_squared() < .000001: return
	_rotate(skeleton, bone, Quaternion(current.basis.y.normalized(), to.normalized()))

func _face_yaw(skeleton: Skeleton3D, bone: int, yaw: float, extra: Quaternion = Quaternion.IDENTITY) -> void:
	var up := _axis(skeleton, Vector3.UP)
	var pose := skeleton.get_bone_global_pose(bone)
	var rest := skeleton.get_bone_global_rest(bone)
	pose.basis = (Basis(Quaternion(up, yaw) * extra) * rest.basis).orthonormalized()
	skeleton.set_bone_global_pose(bone, pose)

func _rotate(skeleton: Skeleton3D, bone: int, rotation: Quaternion) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	pose.basis = (Basis(rotation) * pose.basis).orthonormalized()
	skeleton.set_bone_global_pose(bone, pose)

func _axis(skeleton: Skeleton3D, world: Vector3) -> Vector3:
	return (skeleton.global_basis.inverse() * world).normalized()
