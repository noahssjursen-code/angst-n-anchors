class_name CoastalGull
extends Node3D
## Shared geometry, per-bird appearance, and a procedural flight pose.
## Movement/decisions belong to the flock, not to the render asset.

const MODEL = preload("res://resources/models/wildlife/coastal_gull.glb")
const PLUMAGE = preload("res://scripts/wildlife/gull_plumage.gdshader")
static var _material: ShaderMaterial
var profile: GullProfile
var calls: GullCallAudio
var _model: Node3D
var _left: Node3D
var _right: Node3D
var _left_tip: Node3D
var _right_tip: Node3D
var _folded: Node3D
var _legs: Node3D
var _body: MeshInstance3D
var _rest_shape: int = -1
var _call_shape: int = -1
var _neck_shape: int = -1
var _look_left_shape: int = -1
var _look_right_shape: int = -1
var _meshes: Array[MeshInstance3D] = []

func _ready() -> void:
	if profile == null: profile = GullProfile.new()
	var species_model: PackedScene = MODEL if profile.species == "herring_gull" else load("res://resources/models/wildlife/" + profile.species + ".glb")
	_model = species_model.instantiate()
	add_child(_model)
	_left = _model.find_child("LeftWing", true, false)
	_right = _model.find_child("RightWing", true, false)
	_left_tip = _model.find_child("LeftWingTip", true, false)
	_right_tip = _model.find_child("RightWingTip", true, false)
	_folded = _model.find_child("FoldedWings", true, false)
	_legs = _model.find_child("Legs", true, false)
	_body = _model.find_child("CoastalGullMesh", true, false) as MeshInstance3D
	_rest_shape = _body.find_blend_shape_by_name("WaterRest")
	_call_shape = _body.find_blend_shape_by_name("Call")
	_neck_shape = _body.find_blend_shape_by_name("NeckLift")
	_look_left_shape = _body.find_blend_shape_by_name("LookLeft")
	_look_right_shape = _body.find_blend_shape_by_name("LookRight")
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = PLUMAGE
		_material.set_shader_parameter("adult_atlas", load("res://resources/models/wildlife/gull_adult.png"))
		_material.set_shader_parameter("juvenile_atlas", load("res://resources/models/wildlife/gull_juvenile.png"))
	_collect_meshes(_model)
	apply_profile(profile if profile != null else GullProfile.new())
	calls = GullCallAudio.new()
	calls.name = "Calls"
	add_child(calls)
	calls.enabled = profile.species == "herring_gull"
	pose(0.0)

func _process(_delta: float) -> void:
	if _call_shape >= 0 and is_instance_valid(calls):
		_body.set_blend_shape_value(_call_shape, calls.beak_amount())

func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		if profile.species == "herring_gull":
			part.material_override = _material
		_meshes.append(part)
	for child in node.get_children():
		_collect_meshes(child)

func apply_profile(value: GullProfile) -> void:
	profile = value
	if _model == null:
		return
	_model.scale = Vector3.ONE * profile.size_scale
	for part in _meshes:
		part.set_instance_shader_parameter("maturity", profile.maturity())

func pose(seconds: float, glide: float = 0.0, folded: bool = false) -> void:
	if _model == null:
		return
	_set_head_pose(0.0, 0.0, 1.0 if folded else 0.0)
	_left.visible = not folded
	_right.visible = not folded
	_folded.visible = folded
	_legs.rotation.x = 0.0 if folded else -1.2
	_legs.visible = true
	var phase := seconds * profile.flap_hz * TAU + profile.phase_offset
	var angle := lerpf(0.18 + 0.65 * sin(phase), 0.10, glide)
	var tip_angle := 0.30 * sin(phase - 0.65) * (1.0 - glide)
	var sweep := 0.10 * (1.0 + cos(phase)) * (1.0 - glide)
	_left.rotation = Vector3(0.03 * cos(phase), 0, -angle)
	_right.rotation = Vector3(0.03 * cos(phase), 0, angle)
	_left_tip.rotation = Vector3(0, sweep, -tip_angle)
	_right_tip.rotation = Vector3(0, -sweep, tip_angle)

func pose_water(seconds: float, motion: GullWaterBehaviour) -> void:
	var folding := motion.fold_amount()
	var flare := motion.flare_amount()
	var resting := motion.stage == GullWaterBehaviour.Stage.RESTING
	var activity := motion.rest_activity()
	pose(seconds, 1.0 if resting else (0.9 if motion.stage == GullWaterBehaviour.Stage.LANDING else 0.0))
	_left.rotation.y = lerpf(0.0, 1.35, folding)
	_right.rotation.y = -_left.rotation.y
	_left.rotation.z = lerpf(_left.rotation.z, -0.10, folding) - flare * 0.18
	if resting:
		# Deliberate slow extension, not the airborne wingbeat cycle.
		_left.rotation.z -= float(activity.wing_stretch) * 0.75
	_right.rotation.z = -_left.rotation.z
	_left_tip.rotation.y += folding * 0.15
	_right_tip.rotation.y -= folding * 0.15
	_left.visible = folding < 0.92
	_right.visible = folding < 0.92
	_folded.visible = folding >= 0.92
	_legs.rotation.x = lerpf(-1.2, 0.0, flare)
	_legs.visible = motion.stage != GullWaterBehaviour.Stage.RESTING
	_set_head_pose(float(activity.neck_lift), float(activity.look), motion.water_weight())

func _set_head_pose(neck_lift: float, look: float, upright: float = 0.0) -> void:
	if is_instance_valid(calls):
		calls.position = Vector3(0, 0.13 + upright * 0.11 + neck_lift * 0.028, -0.36 + upright * 0.045) * profile.size_scale
	if _rest_shape >= 0:
		_body.set_blend_shape_value(_rest_shape, upright)
	if _neck_shape >= 0:
		_body.set_blend_shape_value(_neck_shape, neck_lift)
	if _look_left_shape >= 0:
		_body.set_blend_shape_value(_look_left_shape, maxf(look, 0.0))
	if _look_right_shape >= 0:
		_body.set_blend_shape_value(_look_right_shape, maxf(-look, 0.0))

func update_audio(seconds: float, water: GullWaterBehaviour = null) -> void:
	if calls == null or profile.species != "herring_gull": return
	var resting := water != null and water.stage == GullWaterBehaviour.Stage.RESTING
	var alarm := water != null and water.stage == GullWaterBehaviour.Stage.TAKING_OFF and water.startled and water.elapsed < 0.5
	calls.tick(seconds, profile, resting, alarm)

static func water_basis(forward: Vector3, surface_normal: Vector3) -> Basis:
	var up := surface_normal.normalized()
	# Suppress implausibly steep roll at sharp crests, while preserving small waves.
	if up.y < 0.75:
		up = Vector3(up.x, 0, up.z).normalized() * 0.66 + Vector3.UP * 0.75
		up = up.normalized()
	var direction := forward.slide(up).normalized()
	if direction.length_squared() < 0.01:
		direction = Vector3.FORWARD.slide(up).normalized()
	return Basis.looking_at(direction, up)
