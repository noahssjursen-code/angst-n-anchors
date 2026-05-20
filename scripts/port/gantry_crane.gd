@tool
class_name GantryCrane
extends Node3D

## Wharf gantry crane.
## Geometry comes from resources/data/models/dockyard/gantry_crane.json (loaded
## via ModelAssembler). Kinematic parts (trolley, hook) are looked up by role
## and animated by this script.
##
## Controls (active only while operator is seated):
##   W / A / S / D — pan hook relative to the camera view (forward / left /
##                  back / right). Mapped onto gantry roll + trolley travel.
##   LMB / RMB   — hoist up / down (held; LMB raises, RMB lowers)
##   RMB drag    — orbit camera around hook
##   Scroll      — camera zoom
##   F           — engage chains (when hook is near a pallet) /
##                  release pallet (when carrying) /
##                  board / exit (when not carrying)
##   Q           — rotate carried pallet 90° (matches deck orientation)
##   MMB drag    — orbit camera around hook
##   Scroll      — zoom
##   Escape      — force exit (drops pallet in place if carrying)

const MODEL_PATH := "res://resources/data/models/dockyard/gantry_crane.json"

signal player_boarded
signal player_exited

## How many cranes are currently being operated. Used by PalletAttachPoint
## to show/hide the corner rings (pickup hints) only while someone is seated.
static var _seated_count: int = 0

# ── Tunables ──────────────────────────────────────────────────────────────────

@export var gantry_roll_range_x: float = 4.0     # ±range from spawn X
@export var gantry_speed_m: float    = 3.0
@export var trolley_speed_m: float   = 4.0
@export var hoist_speed_m: float     = 3.5

## Berth this crane serves (set by PortDock at spawn). Used so the crane can
## switch its beacon to green + show an "ASSIGNED" label when a ship is
## moored at the matching berth — answering "which crane is mine?".
@export var berth_index: int = -1

## Trolley travel limits along Z. -Z = over water/ship berth, +Z = over apron.
@export var trolley_min_z: float = -28.0
@export var trolley_max_z: float = 20.0

## Hoist limits — how far the hook hangs below the trolley.
## Trolley sits at world Y ≈ 17.22 (quay 0.6 + rails 0.12 + model 16.5);
## hook mesh extends 0.35 m below its origin, so max drop 16.1 m bottoms
## the visual hook at world Y ≈ 0.77 — sits cleanly above the asphalt
## (Y=0.6) while still within pickup range of pallet sockets at Y≈0.78.
@export var hoist_min_drop: float = 1.0
@export var hoist_max_drop: float = 16.1

## How close (XZ) the hook must be to a pallet's center to engage chains.
## Tight so the player must position the trolley right over the pallet.
@export var pickup_xz_range_m: float = 1.15
## Hook can be at most this far above the pallet top to engage.
@export var pickup_max_height_m: float = 1.8

## How close (XZ) the hook must be to a delivery zone / deck cell to release.
@export var release_xz_range_m: float = 2.0
## How far above the target surface the hook may be when releasing.
@export var release_max_height_m: float = 2.5

## Player must be within this range to board.
@export var board_range_m: float = 7.0

# ── Runtime state ─────────────────────────────────────────────────────────────

var _assembler: ModelAssembler
var _gantry_frame: Node3D      # holds the assembler; slides in X
var _trolley: Node3D
var _hook: Node3D
var _cable: MeshInstance3D
var _rigging: CraneRigging
var _camera: CraneCamera

var _spawn_x: float           # crane.position.x captured at _ready
var _gantry_x_offset: float = 0.0
var _trolley_z: float = 0.0
var _hoist_drop: float = 8.0

var _occupied: bool = false
var _player: CharacterBody3D = null
var _carried_pallet: Node3D = null      # PalletNode currently lifted
var _highlighted_pallet: Node3D = null  # PalletNode whose sockets glow
var _carry_rotated: bool = false        # carried pallet rotated 90° from spawn
var _carry_baseline_basis: Basis = Basis.IDENTITY  # actual basis at pickup

var _ui: CanvasLayer
var _prompt: Label
var _hud: Label
var _prev_mouse_mode: int = Input.MOUSE_MODE_VISIBLE

# ── Polish: lights, hook sway, snap-preview ───────────────────────────────────
var _beacon: OmniLight3D
var _beacon_phase: float = 0.0
var _floods: Array[SpotLight3D] = []
var _berth_number: Label3D
var _is_assigned: bool = false

# Hook sway: trolley/gantry motion drags the hook with damped spring response.
var _last_gantry_x: float = 0.0
var _last_trolley_z: float = 0.0
var _sway: Vector2 = Vector2.ZERO       # x = along gantry axis, y = along trolley axis
var _sway_vel: Vector2 = Vector2.ZERO
@export var sway_drag: float = 0.16     # how strongly motion drags the hook (m·s/m/s)
@export var sway_spring: float = 18.0   # restoring stiffness
@export var sway_damp: float = 6.0      # damping

var _snap_ghost: MeshInstance3D
var _snap_ghost_mat: StandardMaterial3D
var _snap_label: Label3D
var _snap_phase: float = 0.0

# Persistent indicator that hovers over the destination apron cell whenever
# the operator is carrying a pallet whose destination matches that apron.
# Visible across the whole dock so the player knows where to go right after
# engaging chains.
var _dest_target: MeshInstance3D
var _dest_target_mat: StandardMaterial3D
var _dest_label: Label3D

# ── Audio ─────────────────────────────────────────────────────────────────────
# Crane sounds: motor loops in looped/crane/, one-shots in normal/crane/. Files
# named "<base>_N.wav" are treated as variants — one is picked at random PER
# CRANE INSTANCE at build time so each crane has its own consistent voice.
const SOUND_DIR_LOOPED := "res://resources/audio/looped/crane"
const SOUND_DIR_NORMAL := "res://resources/audio/normal/crane"
const MOTOR_SPEED_THRESHOLD_M_PER_S := 0.08
const HOIST_LIMIT_EPSILON := 0.01

var _sfx_motor_gantry: AudioStreamPlayer3D
var _sfx_motor_trolley: AudioStreamPlayer3D
var _sfx_motor_hoist: AudioStreamPlayer3D
# Cached streams for one-shots; one-shot players are created on demand and
# freed when finished so concurrent plays don't cut each other off.
var _sfx_chain_engage: AudioStream
var _sfx_chain_release: AudioStream
var _sfx_crane_board: AudioStream
var _sfx_crane_exit: AudioStream
var _sfx_hook_bottom: AudioStream
var _sfx_hook_top: AudioStream
var _was_hoist_at_bottom: bool = false
var _was_hoist_at_top: bool = false
var _last_gantry_x_for_audio: float = 0.0
var _last_trolley_z_for_audio: float = 0.0
var _last_hoist_drop_for_audio: float = 0.0


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_spawn_x = position.x
	_trolley_z = clampf(_trolley_z, trolley_min_z, trolley_max_z)
	_hoist_drop = clampf(_hoist_drop, hoist_min_drop, hoist_max_drop)
	if not Engine.is_editor_hint():
		_register_input_actions()
	_build()


func _exit_tree() -> void:
	if _rigging != null and is_instance_valid(_rigging):
		_rigging.detach_all()
	if _snap_ghost != null and is_instance_valid(_snap_ghost):
		_snap_ghost.queue_free()
	if _dest_target != null and is_instance_valid(_dest_target):
		_dest_target.queue_free()


# ── Build ─────────────────────────────────────────────────────────────────────

func _build() -> void:
	_build_rails()

	_gantry_frame = Node3D.new()
	_gantry_frame.name = "GantryFrame"
	# Sit the gantry on top of the rails (0.12 m tall) instead of floating at
	# crane origin level. Leg bottoms (model Y=0) now align with rail tops.
	_gantry_frame.position.y = 0.12
	add_child(_gantry_frame)
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		_gantry_frame.owner = get_tree().edited_scene_root

	_assembler = ModelAssembler.new()
	_assembler.name = "CraneModel"
	_assembler.model_data_path = MODEL_PATH
	_gantry_frame.add_child(_assembler)
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		_assembler.owner = get_tree().edited_scene_root

	_wire_kinematic_parts.call_deferred()
	_build_hazard_bands()
	_build_lights()

	if not Engine.is_editor_hint():
		_build_rigging.call_deferred()
		_build_camera.call_deferred()
		_build_snap_ghost.call_deferred()
		_build_ui()
		_build_audio.call_deferred()


func _build_rails() -> void:
	# Two parallel rails on the ground showing where the gantry travels.
	# The legs sit at X=±2.5 in the gantry frame; the frame slides ±roll_range,
	# so the gantry's X sweep is (-roll_range - 2.5) … (+roll_range + 2.5).
	# We pad each end by 0.6 m for visual end stops.
	var sweep_half := gantry_roll_range_x + 2.5
	var rail_len   := (sweep_half + 0.6) * 2.0
	var rail_z     := 2.5
	var rail_color := Color(0.12, 0.12, 0.13)
	var stop_color := Color(0.95, 0.78, 0.10)

	for sign_z in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		rail.name = "Rail_" + ("F" if sign_z > 0 else "B")
		var mesh := BoxMesh.new()
		mesh.size = Vector3(rail_len, 0.12, 0.32)
		rail.mesh = mesh
		rail.position = Vector3(0.0, 0.06, rail_z * sign_z)
		rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.albedo_color = rail_color
		mat.roughness = 0.8
		rail.material_override = mat
		add_child(rail)
		if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
			rail.owner = get_tree().edited_scene_root

		# Yellow end stops at each end of the rail.
		for sign_x in [-1.0, 1.0]:
			var stop := MeshInstance3D.new()
			stop.name = "RailStop_%s_%s" % [
				"L" if sign_x < 0 else "R",
				"B" if sign_z < 0 else "F",
			]
			var smesh := BoxMesh.new()
			smesh.size = Vector3(0.5, 0.55, 0.55)
			stop.mesh = smesh
			stop.position = Vector3(sign_x * (sweep_half + 0.35), 0.28, rail_z * sign_z)
			stop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var smat := StandardMaterial3D.new()
			smat.albedo_color = stop_color
			smat.roughness = 0.6
			stop.material_override = smat
			add_child(stop)
			if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
				stop.owner = get_tree().edited_scene_root


func _build_hazard_bands() -> void:
	# Yellow/black diagonal stripes around the bottom 1.4 m of each leg, plus
	# a thin band wrapping the trolley for visibility.
	var leg_xs := [-2.5, 2.5]
	var leg_zs := [-2.5, 2.5]
	for lx in leg_xs:
		for lz in leg_zs:
			var band := MeshInstance3D.new()
			band.name = "HazardBand_%s%s" % [
				"L" if lx < 0 else "R",
				"B" if lz < 0 else "F",
			]
			var mesh := BoxMesh.new()
			mesh.size = Vector3(1.12, 1.4, 1.12)
			band.mesh = mesh
			band.position = Vector3(lx, 0.7, lz)
			band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			band.material_override = _hazard_material()
			_gantry_frame.add_child(band)
			if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
				band.owner = get_tree().edited_scene_root


func _hazard_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode cull_disabled, shadows_disabled;\nvoid fragment() {\n\tfloat s = fract((UV.x + UV.y) * 4.0);\n\tALBEDO = s > 0.5 ? vec3(0.95, 0.78, 0.0) : vec3(0.06, 0.06, 0.06);\n\tROUGHNESS = 0.7;\n\tMETALLIC = 0.05;\n}"
	mat.shader = shader
	return mat


func _build_lights() -> void:
	# Floodlights aimed down-and-outward from the four top corners.
	var top_y := 16.5
	var positions := [
		Vector3(-2.5, top_y, -2.5),
		Vector3( 2.5, top_y, -2.5),
		Vector3(-2.5, top_y,  2.5),
		Vector3( 2.5, top_y,  2.5),
	]
	for i in positions.size():
		var sx: float = -1.0 if positions[i].x < 0 else 1.0
		var sz: float = -1.0 if positions[i].z < 0 else 1.0
		var flood := SpotLight3D.new()
		flood.name = "Flood%d" % i
		flood.position = positions[i]
		# SpotLight3D shines along its local -Z, so build a basis whose -Z
		# matches the desired down-and-outward aim. Done manually because
		# look_at requires the node to be in the tree.
		var aim_dir := Vector3(sx * 0.6, -1.0, sz * 0.6).normalized()
		var z_axis  := -aim_dir
		var ref_up  := Vector3.UP if absf(z_axis.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
		var x_axis  := ref_up.cross(z_axis).normalized()
		var y_axis  := z_axis.cross(x_axis).normalized()
		flood.basis = Basis(x_axis, y_axis, z_axis)
		flood.light_color = Color(1.0, 0.94, 0.82)
		flood.light_energy = 4.0
		flood.spot_range = 32.0
		flood.spot_angle = 55.0
		flood.spot_attenuation = 0.6
		flood.shadow_enabled = false
		_gantry_frame.add_child(flood)
		_floods.append(flood)
		if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
			flood.owner = get_tree().edited_scene_root

	# Red obstruction beacon on top of the trolley rail, slow-blinking.
	_beacon = OmniLight3D.new()
	_beacon.name = "Beacon"
	_beacon.position = Vector3(0.0, 18.2, 0.0)
	_beacon.light_color = Color(1.0, 0.1, 0.1)
	_beacon.light_energy = 1.0
	_beacon.omni_range = 6.0
	_beacon.shadow_enabled = false
	_gantry_frame.add_child(_beacon)
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		_beacon.owner = get_tree().edited_scene_root

	var bulb := MeshInstance3D.new()
	bulb.name = "BeaconBulb"
	var bmesh := SphereMesh.new()
	bmesh.radius = 0.22
	bmesh.height = 0.44
	bulb.mesh = bmesh
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1.0, 0.15, 0.15)
	bmat.emission_enabled = true
	bmat.emission = Color(1.0, 0.15, 0.15)
	bmat.emission_energy_multiplier = 2.0
	bulb.material_override = bmat
	_beacon.add_child(bulb)
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		bulb.owner = get_tree().edited_scene_root

	# Huge berth number painted on the dock in front of the crane, facing the
	# water — readable from the open sea like an airport runway number.
	# Sits flat on the asphalt; bright green when the player's ship is moored
	# here, off-white otherwise.
	_berth_number = Label3D.new()
	_berth_number.name = "BerthNumber"
	_berth_number.text = str(berth_index + 1) if berth_index >= 0 else "?"
	_berth_number.font_size = 192
	_berth_number.pixel_size = 0.026   # ~5 m tall painted digit
	# Sharp safety-paint yellow, slightly translucent to read as sun-bleached.
	_berth_number.modulate = Color(1.00, 0.82, 0.05, 0.90)
	_berth_number.outline_modulate = Color(0.03, 0.03, 0.03, 1.0)
	_berth_number.outline_size = 40
	_berth_number.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_berth_number.no_depth_test = false
	# Flat on the dock surface, rotated 180° around Y so the digit reads
	# right-side-up from a ship approaching from the open sea.
	_berth_number.rotation_degrees = Vector3(-90.0, 180.0, 0.0)
	_berth_number.position = Vector3(0.0, 0.01, -7.0)
	_berth_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_berth_number)
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		_berth_number.owner = get_tree().edited_scene_root


func _build_snap_ghost() -> void:
	# Hover-confirmation ghost — placed under the hook over a valid target.
	_snap_ghost = MeshInstance3D.new()
	_snap_ghost.name = "SnapGhost"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.3, 0.04, 1.3)
	_snap_ghost.mesh = mesh
	_snap_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_snap_ghost.visible = false
	_snap_ghost_mat = StandardMaterial3D.new()
	_snap_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_snap_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_snap_ghost_mat.no_depth_test = true
	_snap_ghost.material_override = _snap_ghost_mat
	get_tree().current_scene.add_child(_snap_ghost)

	_snap_label                  = Label3D.new()
	_snap_label.name             = "SnapLabel"
	_snap_label.font_size        = 44
	_snap_label.pixel_size       = 0.0035
	_snap_label.billboard        = BaseMaterial3D.BILLBOARD_ENABLED
	_snap_label.no_depth_test    = true
	_snap_label.outline_size     = 3
	_snap_label.modulate         = Color.WHITE
	_snap_label.outline_modulate = Color(0.05, 0.05, 0.05, 0.85)
	_snap_ghost.add_child(_snap_label)

	# Persistent destination target — sits on the cell of the destination apron.
	_dest_target = MeshInstance3D.new()
	_dest_target.name = "DestinationTarget"
	var dmesh := BoxMesh.new()
	dmesh.size = Vector3(1.3, 0.04, 1.3)
	_dest_target.mesh = dmesh
	_dest_target.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dest_target.visible = false
	_dest_target_mat = StandardMaterial3D.new()
	_dest_target_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dest_target_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dest_target_mat.no_depth_test = true
	_dest_target.material_override = _dest_target_mat
	get_tree().current_scene.add_child(_dest_target)

	_dest_label                  = Label3D.new()
	_dest_label.name             = "DestLabel"
	_dest_label.font_size        = 48
	_dest_label.pixel_size       = 0.004
	_dest_label.billboard        = BaseMaterial3D.BILLBOARD_ENABLED
	_dest_label.no_depth_test    = true
	_dest_label.outline_size     = 3
	_dest_label.modulate         = Color(1.0, 0.84, 0.20)
	_dest_label.outline_modulate = Color(0.04, 0.04, 0.04, 0.85)
	_dest_target.add_child(_dest_label)


func _wire_kinematic_parts() -> void:
	var trolley_part := _assembler.get_first_part_by_role("trolley")
	var hook_part := _assembler.get_first_part_by_role("hook")
	if trolley_part == null or hook_part == null:
		push_error("GantryCrane: trolley/hook role not found in model JSON")
		return

	_trolley = trolley_part
	_hook = hook_part

	# Reparent hook under trolley so trolley motion drags the hook with it.
	# Hoist then becomes a local Y on the hook.
	_hook.reparent(_trolley, false)
	_hook.position = Vector3(0.0, -_hoist_drop, 0.0)
	_hook.rotation = Vector3.ZERO

	_build_cable()
	_apply_kinematics()


func _build_cable() -> void:
	if _cable != null and is_instance_valid(_cable):
		_cable.queue_free()
	_cable = MeshInstance3D.new()
	_cable.name = "Cable"
	# Thin cylinder reads as a rope/cable far better than a box. CylinderMesh's
	# default axis is +Y with height 1 — gets scaled in _apply_kinematics.
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.05
	cyl.height = 1.0
	cyl.radial_segments = 10
	cyl.rings = 1
	_cable.mesh = cyl
	_cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.14)
	mat.roughness = 0.85
	mat.metallic = 0.3
	_cable.material_override = mat
	_trolley.add_child(_cable)


func _build_rigging() -> void:
	if _hook == null:
		return
	_rigging = CraneRigging.new()
	_rigging.name = "Rigging"
	_rigging.hook = _hook
	add_child(_rigging)


func _build_camera() -> void:
	if _hook == null:
		return
	_camera = CraneCamera.new()
	_camera.name = "CraneCamera"
	_camera.target = _hook
	add_child(_camera)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "CraneUI"
	add_child(_ui)

	_prompt = Label.new()
	_prompt.name = "Prompt"
	_prompt.text = "Press F to operate crane"
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.visible = false
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -240.0
	_prompt.offset_right = 240.0
	_prompt.offset_top = -96.0
	_prompt.offset_bottom = -48.0
	_ui.add_child(_prompt)

	_hud = Label.new()
	_hud.name = "Hud"
	_hud.visible = false
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_theme_font_size_override("font_size", 16)
	_hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hud.offset_left = 16.0
	_hud.offset_top = 16.0
	_hud.offset_right = 460.0
	_hud.offset_bottom = 160.0
	_ui.add_child(_hud)


# ── Main loop ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_beacon(delta)
	if _occupied:
		_read_kinematic_input(delta)
	# Always keep the cable + hook position in sync with state — otherwise the
	# cable renders at its default 1 m size when no one is operating the crane.
	_apply_kinematics(delta)
	_update_audio(delta)
	if _occupied:
		_update_carried_pallet()
		_update_pickup_highlight()
		_update_snap_ghost()
		_update_hud()
	else:
		_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if _occupied:
		if event.is_action_pressed("ui_cancel"):
			_exit_crane()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("interact"):
			# E is contextual: release > engage > exit
			if _carried_pallet != null:
				_try_release()
			elif _highlighted_pallet != null:
				_engage_chains(_highlighted_pallet)
			else:
				_exit_crane()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("crane_rotate_pallet"):
			if _carried_pallet != null:
				_toggle_rotation()
			get_viewport().set_input_as_handled()
	else:
		if event.is_action_pressed("interact") and _nearest_boardable_player() != null:
			_enter_crane()
			get_viewport().set_input_as_handled()


# ── Kinematics ────────────────────────────────────────────────────────────────

func _read_kinematic_input(delta: float) -> void:
	# Camera-relative pan: WASD is in screen space, projected onto the crane's
	# local X (gantry rails) and Z (trolley boom).
	var pan_y := Input.get_axis("crane_pan_back",  "crane_pan_forward")
	var pan_x := Input.get_axis("crane_pan_left",  "crane_pan_right")
	if absf(pan_x) > 0.001 or absf(pan_y) > 0.001:
		var local_wish := _camera_relative_wish(pan_x, pan_y)
		_gantry_x_offset = clampf(
			_gantry_x_offset + local_wish.x * gantry_speed_m * delta,
			-gantry_roll_range_x, gantry_roll_range_x,
		)
		_trolley_z = clampf(
			_trolley_z + local_wish.z * trolley_speed_m * delta,
			trolley_min_z, trolley_max_z,
		)

	# Hoist on mouse buttons: LMB raises, RMB lowers.
	# (Orbit moved to MMB drag in CraneCamera so LMB/RMB are free for this.)
	var hoist_dir := 0.0
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		hoist_dir -= 1.0
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		hoist_dir += 1.0
	_hoist_drop = clampf(
		_hoist_drop + hoist_dir * hoist_speed_m * delta,
		hoist_min_drop, hoist_max_drop,
	)


## Translates a screen-space WASD input (pan_x = right, pan_y = forward) into
## a unit-clamped direction expressed in the crane's local XZ frame, using the
## active orbit camera's facing. World-Y components are stripped so panning
## stays horizontal regardless of camera pitch.
func _camera_relative_wish(pan_x: float, pan_y: float) -> Vector3:
	if _camera == null:
		# Camera not built yet — fall back to crane-local axes.
		return Vector3(pan_x, 0.0, -pan_y)
	var cam_basis  := _camera.global_transform.basis
	var forward_xz := -cam_basis.z
	forward_xz.y = 0.0
	if forward_xz.length_squared() < 1e-6:
		forward_xz = -cam_basis.y  # camera looking straight down — use its Y
		forward_xz.y = 0.0
	forward_xz = forward_xz.normalized()
	var right_xz := cam_basis.x
	right_xz.y = 0.0
	right_xz = right_xz.normalized()

	var wish_world := forward_xz * pan_y + right_xz * pan_x
	if wish_world.length() > 1.0:
		wish_world = wish_world.normalized()

	# Crane root may be rotated by its parent dock — use the inverse basis
	# rather than assuming world XZ == crane XZ.
	var local_wish := global_transform.basis.inverse() * wish_world
	local_wish.y = 0.0
	return local_wish


func _apply_kinematics(delta: float = 0.0) -> void:
	if _gantry_frame != null:
		_gantry_frame.position.x = _gantry_x_offset
	if _trolley != null:
		_trolley.position.z = _trolley_z

	# Hook sway: trolley/gantry motion drags the hook with a damped spring.
	if delta > 0.0001:
		var gantry_vel  := (_gantry_x_offset - _last_gantry_x) / delta
		var trolley_vel := (_trolley_z      - _last_trolley_z) / delta
		var target := Vector2(-gantry_vel * sway_drag, -trolley_vel * sway_drag)
		# Spring–damper toward the velocity-driven target.
		var accel := (target - _sway) * sway_spring - _sway_vel * sway_damp
		_sway_vel += accel * delta
		_sway += _sway_vel * delta
	_last_gantry_x  = _gantry_x_offset
	_last_trolley_z = _trolley_z

	if _hook != null:
		_hook.position = Vector3(_sway.x, -_hoist_drop, _sway.y)
	if _cable != null and _hook != null:
		# Cable runs from trolley (Y=0) to hook position; orient local +Y toward
		# the hook so it tilts with the sway. Basis MUST be set before scale —
		# assigning a unit-length basis wipes any prior scale.
		var hook_local := _hook.position
		var length := hook_local.length()
		var dir := hook_local.normalized() if length > 0.0001 else Vector3.DOWN
		var ref_up := Vector3.FORWARD if absf(dir.dot(Vector3.UP)) > 0.99 else Vector3.UP
		var x_axis := dir.cross(ref_up).normalized()
		var z_axis := x_axis.cross(dir).normalized()
		_cable.basis = Basis(x_axis, dir, z_axis)
		_cable.scale = Vector3(1.0, length, 1.0)
		_cable.position = hook_local * 0.5


# ── Carried pallet ────────────────────────────────────────────────────────────

func _update_carried_pallet() -> void:
	if _carried_pallet == null or _rigging == null:
		return
	if not is_instance_valid(_carried_pallet):
		# Pallet was freed externally — drop our reference.
		_carried_pallet = null
		if _rigging != null:
			_rigging.detach_all()
		return
	# Fully attached: pallet rides under the hook. Basis stays at whatever
	# it was when picked up — apron-rotation if it came off the apron, ship-
	# rotation if re-picked off a ship, etc. Q applies a 90° twist relative
	# to that captured basis. No snapping to world or to decks underneath.
	if _rigging.attached_count() >= CraneRigging.MAX_CHAINS:
		var hp := _hook.global_position
		var oriented := _carry_baseline_basis
		if _carry_rotated:
			oriented = oriented.rotated(Vector3.UP, PI * 0.5)
		_carried_pallet.global_transform = Transform3D(
			oriented,
			Vector3(hp.x, hp.y - 1.4, hp.z),
		)


# ── Beacon ────────────────────────────────────────────────────────────────────

func _update_beacon(delta: float) -> void:
	if _beacon == null:
		return
	_beacon_phase = fmod(_beacon_phase + delta * 1.6, TAU)
	# Sharp pulse — bright for ~0.2 s, then dim, every ~3.9 s.
	var pulse := pow(maxf(sin(_beacon_phase), 0.0), 12.0)
	_beacon.light_energy = 0.2 + pulse * 5.0

	# Update the painted berth number — off-white normally, bright green
	# when this crane's berth has the player's ship moored.
	var was_assigned := _is_assigned
	_is_assigned = _berth_has_ship()
	if _is_assigned != was_assigned and _berth_number != null:
		_berth_number.modulate = (
			Color(0.30, 0.95, 0.45, 1.0) if _is_assigned
			else Color(0.96, 0.92, 0.70, 1.0)
		)


## True when a ship is moored at this crane's berth. Reads PortDock berth
## state via the parent — set by PortDock at spawn (berth_index).
func _berth_has_ship() -> bool:
	if berth_index < 0:
		return false
	var dock := get_parent() as PortDock
	if dock == null:
		return false
	return dock.find_player_berth(PortDock.local_player_owner_id()) == berth_index


# ── Snap-preview ──────────────────────────────────────────────────────────────

func _update_snap_ghost() -> void:
	if _snap_ghost == null or _hook == null:
		return
	if _carried_pallet == null:
		_hide_snap_ghost()
		_hide_dest_target()
		return

	var hook_pos := _hook.global_position

	var xz_r2 := release_xz_range_m * release_xz_range_m

	var pallet_res: Pallet = _carried_pallet.get("pallet") as Pallet
	_update_destination_target(pallet_res)

	# 1. Delivery — apron deck whose port_id matches pallet.destination_port_id.
	for node in get_tree().get_nodes_in_group(CargoDeckComponent.DECK_GROUP):
		var deck := node as CargoDeckComponent
		if deck == null or not deck.accepts_delivery(pallet_res):
			continue
		if not deck.contains_world_point(hook_pos):
			continue
		if hook_pos.y - deck.global_position.y > release_max_height_m:
			continue
		var cell_pos_d := deck.get_nearest_free_cell_world(hook_pos, pallet_res)
		if cell_pos_d == Vector3.INF:
			cell_pos_d = deck.global_position
		var reward := pallet_res.value_gold if pallet_res != null else 0
		_show_ghost(cell_pos_d, deck.global_basis, _footprint_size(deck, pallet_res),
				Color(1.0, 0.84, 0.20),
				"+%s" % PlayerSession.format_money(reward),
				true)
		return

	# 2. Staging — any deck that accepts the pallet (ship deck OR origin apron).
	for node in get_tree().get_nodes_in_group(CargoDeckComponent.DECK_GROUP):
		var deck := node as CargoDeckComponent
		if deck == null or not deck.accepts_pallet(pallet_res):
			continue
		if not deck.contains_world_point(hook_pos):
			continue
		if hook_pos.y - deck.global_position.y > release_max_height_m:
			continue
		var cell_pos := deck.get_nearest_free_cell_world(hook_pos, pallet_res)
		if cell_pos == Vector3.INF:
			continue
		_show_ghost(cell_pos, deck.global_basis, _footprint_size(deck, pallet_res),
				Color(0.30, 0.95, 0.45),
				"",
				false)
		return

	# 3. No valid target.
	_hide_snap_ghost()


func _show_ghost(pos: Vector3, deck_basis: Basis, footprint_xz: Vector2, color: Color, label_text: String, is_delivery: bool) -> void:
	_snap_ghost.visible = true
	# Match deck orientation and stretch to the footprint so a 1×4 timber pad
	# is shown as a long rectangle instead of a tiny square.
	var oriented := deck_basis.orthonormalized()
	oriented.x *= maxf(footprint_xz.x, 0.5)
	oriented.z *= maxf(footprint_xz.y, 0.5)
	_snap_ghost.global_transform = Transform3D(oriented, pos + Vector3(0.0, 0.05, 0.0))

	_snap_phase = fmod(_snap_phase + get_process_delta_time() * 3.0, TAU)
	var pulse := 0.5 + 0.5 * sin(_snap_phase)

	_snap_ghost_mat.albedo_color = Color(color.r, color.g, color.b, 0.40)
	_snap_ghost_mat.emission_enabled = true
	_snap_ghost_mat.emission = color
	_snap_ghost_mat.emission_energy_multiplier = (0.8 + pulse * 0.9) if is_delivery else 0.6

	if _snap_label != null:
		if label_text.is_empty():
			_snap_label.visible = false
		else:
			_snap_label.visible  = true
			_snap_label.text     = label_text
			_snap_label.position = Vector3(0.0, 1.05, 0.0)
			_snap_label.modulate = color


func _hide_snap_ghost() -> void:
	if _snap_ghost != null:
		_snap_ghost.visible = false
	if _snap_label != null:
		_snap_label.visible = false


# ── Destination target (persistent while carrying matching pallet) ────────────

func _update_destination_target(pallet_res: Pallet) -> void:
	if pallet_res == null or pallet_res.destination_port_id.is_empty():
		_hide_dest_target()
		return

	# Find the apron deck whose port_id matches the pallet's destination.
	var best: CargoDeckComponent = null
	for node in get_tree().get_nodes_in_group(CargoDeckComponent.DECK_GROUP):
		var deck := node as CargoDeckComponent
		if deck != null and deck.accepts_delivery(pallet_res):
			best = deck
			break

	if best == null:
		_hide_dest_target()
		return

	var cell_pos := best.get_nearest_free_cell_world(_hook.global_position, pallet_res)
	if cell_pos == Vector3.INF:
		cell_pos = best.global_position

	_dest_target.visible = true
	var dbasis := best.global_basis.orthonormalized()
	var fpz := _footprint_size(best, pallet_res)
	dbasis.x *= maxf(fpz.x, 0.5)
	dbasis.z *= maxf(fpz.y, 0.5)
	_dest_target.global_transform = Transform3D(
		dbasis,
		cell_pos + Vector3(0.0, 0.06, 0.0),
	)

	# Bigger, slower pulse than the under-hook snap-ghost so they read as
	# separate things from a distance.
	var dphase := fmod(_snap_phase * 0.5, TAU)
	var dp := 0.5 + 0.5 * sin(dphase)
	_dest_target_mat.albedo_color = Color(1.0, 0.84, 0.20, 0.35 + dp * 0.25)
	_dest_target_mat.emission_enabled = true
	_dest_target_mat.emission = Color(1.0, 0.84, 0.20)
	_dest_target_mat.emission_energy_multiplier = 1.0 + dp * 1.5

	if _dest_label != null:
		_dest_label.visible  = true
		_dest_label.text     = "DELIVER"
		_dest_label.position = Vector3(0.0, 1.4 + dp * 0.15, 0.0)


## Footprint as a unitless cell multiplier in the deck's LOCAL axes — used to
## stretch the snap-ghost mesh (which is parented in deck-local space via the
## deck's basis). Calls CargoDeckComponent's world→deck-local converter so a
## (1, 5) world pallet on a 90°-rotated deck previews as (5, 1) deck-local —
## same world shape as the carried pallet.
func _footprint_size(deck: CargoDeckComponent, pallet: Pallet) -> Vector2:
	if pallet == null:
		return Vector2.ONE
	var fp_local := pallet.footprint
	if deck != null:
		fp_local = deck._world_to_deck_local_fp(pallet.footprint)
	return Vector2(maxi(fp_local.x, 1), maxi(fp_local.y, 1))


func _hide_dest_target() -> void:
	if _dest_target != null:
		_dest_target.visible = false
	if _dest_label != null:
		_dest_label.visible = false


# ── Pickup highlight ──────────────────────────────────────────────────────────

func _update_pickup_highlight() -> void:
	if _carried_pallet != null or _hook == null:
		_clear_highlight()
		return

	var nearest := _find_nearest_pallet()
	if nearest == _highlighted_pallet:
		return
	_clear_highlight()
	if nearest != null:
		_highlighted_pallet = nearest
		_set_pallet_highlight(_highlighted_pallet, true)


## Returns the nearest pallet within pickup_xz_range_m horizontally AND
## pickup_max_height_m vertically (hook above pallet). Forces the operator
## to position the trolley directly over the pallet and lower the hook.
func _find_nearest_pallet() -> Node3D:
	var hp := _hook.global_position
	var best: Node3D = null
	var best_d2 := pickup_xz_range_m * pickup_xz_range_m
	for n in get_tree().get_nodes_in_group(PalletNode.GROUP):
		var pn := n as Node3D
		if pn == null:
			continue
		var dx := hp.x - pn.global_position.x
		var dz := hp.z - pn.global_position.z
		var dy := hp.y - pn.global_position.y     # >0 means hook above pallet
		if dy < -0.4 or dy > pickup_max_height_m:
			continue
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best = pn
	return best


func _clear_highlight() -> void:
	if _highlighted_pallet != null and is_instance_valid(_highlighted_pallet):
		_set_pallet_highlight(_highlighted_pallet, false)
	_highlighted_pallet = null


func _set_pallet_highlight(pallet_node: Node3D, on: bool) -> void:
	if pallet_node != null and pallet_node.has_method("set_highlighted"):
		pallet_node.set_highlighted(on)


func _sockets_of(pallet_node: Node3D) -> Array:
	var out := []
	if pallet_node == null:
		return out
	for c in pallet_node.get_children():
		if c is PalletAttachPoint:
			out.append(c)
	return out


func _toggle_rotation() -> void:
	if _carried_pallet == null or not is_instance_valid(_carried_pallet):
		return
	var pallet_res: Pallet = _carried_pallet.get("pallet") as Pallet
	if pallet_res == null:
		return
	# Swap X/Z of the footprint — the deck reads pallet.footprint when adding,
	# the visual rebuild reads it for cell layout, and the snap-ghost / dest
	# target both read it for sizing — one mutation propagates everywhere.
	pallet_res.footprint = Vector2i(pallet_res.footprint.y, pallet_res.footprint.x)
	_carry_rotated = not _carry_rotated
	# Visual rotation is applied by _update_carried_pallet each frame based on
	# the deck the pallet will land on — that way rotation reads correctly
	# against the destination cell, not against world axes.


func _engage_chains(pallet_node: Node3D) -> void:
	if _rigging == null or pallet_node == null or not is_instance_valid(pallet_node):
		return
	# Each new pickup starts in its natural orientation — anchor to the
	# pallet's CURRENT global basis (apron/ship rotation, etc.) so it doesn't
	# visually snap to world or anywhere else.
	_carry_rotated = false
	_carry_baseline_basis = pallet_node.global_basis.orthonormalized()
	# Clear pickup halo — we're now carrying it.
	if pallet_node.has_method("set_highlighted"):
		pallet_node.set_highlighted(false)
	_play_one_shot(_sfx_chain_engage, _hook)

	# If this pallet is currently a child of a CargoDeckComponent's
	# PalletVisuals, reparent it to the scene root first. Otherwise the
	# deck's remove_pallet_by_resource() will queue_free the very node we're
	# about to carry, leaving _carried_pallet pointing at a freed instance.
	var scene_root := get_tree().current_scene
	if scene_root != null and pallet_node.get_parent() != scene_root:
		pallet_node.reparent(scene_root, true)

	# Now the deck can't reach the visual by name. Releasing the resource is
	# still required to clear the deck's _cells dict and mass accounting.
	if pallet_node.has_method("get") and pallet_node.get("pallet") != null:
		_detach_from_deck(pallet_node.get("pallet"))

	# Snap all four chains in one go.
	_rigging.detach_all()
	for socket in _sockets_of(pallet_node):
		_rigging.attach(socket as Node3D)
		if socket.has_method("set_attached"):
			socket.set_attached(true)
	_carried_pallet = pallet_node
	if _highlighted_pallet != null:
		_set_pallet_highlight(_highlighted_pallet, false)
		_highlighted_pallet = null


# ── Release ───────────────────────────────────────────────────────────────────

func _try_release() -> void:
	if _carried_pallet == null:
		return
	var hook_pos := _hook.global_position
	var pallet_res = _carried_pallet.get("pallet")

	var xz_r2 := release_xz_range_m * release_xz_range_m

	# 1) Apron delivery — destination port matches. Sells the pallet via the
	#    ContractRegistry; deck is responsible for the bookkeeping.
	if pallet_res != null:
		for node in get_tree().get_nodes_in_group(CargoDeckComponent.DECK_GROUP):
			var deck := node as CargoDeckComponent
			if deck == null or not deck.accepts_delivery(pallet_res):
				continue
			if not deck.contains_world_point(hook_pos):
				continue
			if hook_pos.y - deck.global_position.y > release_max_height_m:
				continue
			deck.deliver_pallet(pallet_res)
			_consume_pallet()
			return

	# 2) Staging — any deck (ship cargo or origin-port apron) that takes us.
	for node in get_tree().get_nodes_in_group(CargoDeckComponent.DECK_GROUP):
		var deck := node as CargoDeckComponent
		if deck == null or not deck.accepts_pallet(pallet_res):
			continue
		if not deck.contains_world_point(hook_pos):
			continue
		if hook_pos.y - deck.global_position.y > release_max_height_m:
			continue
		var cell := deck.add_pallet(pallet_res, hook_pos)
		if cell >= 0:
			_consume_pallet()
			return

	# 3) No valid target — silently refuse. Pallet keeps hanging so the
	#    player must position over the apron or a ship's cargo deck. The
	#    HUD's hint line already reflects the lack of a snap target.
	return


func _consume_pallet() -> void:
	if _rigging != null:
		_rigging.detach_all()
	_play_one_shot(_sfx_chain_release, _hook)
	if _carried_pallet != null and is_instance_valid(_carried_pallet):
		_carried_pallet.queue_free()
	_carried_pallet = null
	_carry_rotated = false


func _drop_in_place() -> void:
	if _carried_pallet == null:
		return
	var scene_root := get_tree().current_scene
	if scene_root != null and _carried_pallet.get_parent() != scene_root:
		_carried_pallet.reparent(scene_root)
	var hp := _hook.global_position
	_carried_pallet.global_position = Vector3(hp.x, 0.0, hp.z)
	if _carried_pallet.has_signal("released"):
		_carried_pallet.emit_signal("released", _carried_pallet)
	if _rigging != null:
		_rigging.detach_all()
	_play_one_shot(_sfx_chain_release, _hook)
	_carried_pallet = null


func _detach_from_deck(pallet_res) -> void:
	for node in get_tree().get_nodes_in_group(CargoDeckComponent.DECK_GROUP):
		var deck := node as CargoDeckComponent
		if deck == null:
			continue
		if deck.remove_pallet_by_resource(pallet_res) != null:
			return


# ── Board / exit ──────────────────────────────────────────────────────────────

func _nearest_boardable_player() -> CharacterBody3D:
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as CharacterBody3D
		if body != null and global_position.distance_to(body.global_position) <= board_range_m:
			return body
	return null


func _enter_crane() -> void:
	_player = _nearest_boardable_player()
	if _player == null:
		return
	_occupied = true
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	_player.velocity = Vector3.ZERO
	if _camera != null:
		_camera.set_enabled(true)
	get_viewport().physics_object_picking = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_seated_count += 1
	_play_one_shot(_sfx_crane_board, self)
	if _prompt != null:
		_prompt.visible = false
	if _hud != null:
		_hud.visible = true
	player_boarded.emit()


func _exit_crane() -> void:
	_occupied = false
	# Note: a carried pallet stays attached to the hook when the operator
	# leaves. They (or another operator) must re-board and position over a
	# valid drop target. This prevents cargo being lost over the water.
	_clear_highlight()
	_hide_snap_ghost()
	_hide_dest_target()
	if _camera != null:
		_camera.set_enabled(false)
	Input.mouse_mode = _prev_mouse_mode
	_seated_count = maxi(_seated_count - 1, 0)
	_play_one_shot(_sfx_crane_exit, self)
	if _player != null:
		var pcam := _player.get_node_or_null("Camera3D") as Camera3D
		if pcam != null:
			pcam.current = true
		_player.global_position = to_global(Vector3(_gantry_x_offset + 4.0, 0.0, 4.0))
		_player.velocity = Vector3.ZERO
		_player.set_physics_process(true)
		_player.set_process_unhandled_input(true)
		_player = null
	if _hud != null:
		_hud.visible = false
	player_exited.emit()


# ── UI ────────────────────────────────────────────────────────────────────────

func _update_prompt() -> void:
	if _prompt == null:
		return
	_prompt.visible = _nearest_boardable_player() != null


func _update_hud() -> void:
	if _hud == null:
		return
	var hint := ""
	if _carried_pallet != null:
		if _snap_ghost != null and _snap_ghost.visible:
			hint = "[E] release here"
		else:
			hint = "No drop target below — move over apron, ship deck, or delivery zone"
	elif _highlighted_pallet != null:
		hint = "[E] engage chains"
	else:
		hint = "Move hook close to a pallet (gold halo means ready)"
	_hud.text = "Gantry %+5.1f m   Trolley %+5.1f m   Hook drop %4.1f m\n%s\n[WASD] pan  [LMB/RMB] hoist up/down  [Q] rotate  [F] engage/release  [MMB] orbit  [scroll] zoom  [Esc] exit" % [
		_gantry_x_offset, _trolley_z, _hoist_drop, hint,
	]


# ── Input registration ────────────────────────────────────────────────────────

func _register_input_actions() -> void:
	var bindings := {
		"crane_pan_left":     KEY_A,
		"crane_pan_right":    KEY_D,
		"crane_pan_back":     KEY_S,
		"crane_pan_forward":  KEY_W,
		# Hoist no longer keyboard-bound — it's on LMB/RMB now.
		"crane_rotate_pallet": KEY_Q,
	}
	for action: String in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = int(bindings[action])
		InputMap.action_add_event(action, ev)


# ── Audio ─────────────────────────────────────────────────────────────────────

func _build_audio() -> void:
	# Cache one-shot streams once. Variant pick is per-spawn; if the user adds
	# additional <base>_N.wav files later, each crane independently picks one.
	_sfx_chain_engage   = _pick_random_sound(SOUND_DIR_NORMAL, "chain_engage")
	_sfx_chain_release  = _pick_random_sound(SOUND_DIR_NORMAL, "chain_release")
	_sfx_crane_board    = _pick_random_sound(SOUND_DIR_NORMAL, "crane_board")
	_sfx_crane_exit     = _pick_random_sound(SOUND_DIR_NORMAL, "crane_exit")
	_sfx_hook_bottom    = _pick_random_sound(SOUND_DIR_NORMAL, "hook_bottom")
	_sfx_hook_top       = _pick_random_sound(SOUND_DIR_NORMAL, "hook_top")

	# Motor loops — parented to their relevant moving part so the sound pans
	# correctly as the gantry rolls, the trolley travels, or the hook descends.
	_sfx_motor_gantry  = _make_motor_player("motor_gantry",  _gantry_frame, -10.0)
	_sfx_motor_trolley = _make_motor_player("motor_trolley", _trolley,      -10.0)
	_sfx_motor_hoist   = _make_motor_player("motor_hoist",   _trolley,      -12.0)

	_last_gantry_x_for_audio  = _gantry_x_offset
	_last_trolley_z_for_audio = _trolley_z
	_last_hoist_drop_for_audio = _hoist_drop


## Returns one of the .wav files in `folder` whose name is `<base>.wav` or
## `<base>_N.wav`. Choice is random — called once per sound per crane.
func _pick_random_sound(folder: String, base: String) -> AudioStream:
	var dir := DirAccess.open(folder)
	if dir == null:
		return null
	var exact := base + ".wav"
	var matches: Array[String] = []
	for f in dir.get_files():
		if not f.ends_with(".wav"):
			continue
		if f == exact or f.begins_with(base + "_"):
			matches.append(folder.path_join(f))
	if matches.is_empty():
		return null
	return load(matches[randi() % matches.size()]) as AudioStream


func _make_motor_player(base: String, parent: Node3D, db: float) -> AudioStreamPlayer3D:
	if parent == null:
		return null
	var stream := _pick_random_sound(SOUND_DIR_LOOPED, base)
	if stream == null:
		return null
	# .import sets loop_mode=1, so the stream loops natively. Use it as-is.
	var p := AudioStreamPlayer3D.new()
	p.name = "Sfx_" + base
	p.stream = stream
	p.volume_db = db
	p.unit_size = 10.0
	p.max_distance = 80.0
	p.autoplay = false
	parent.add_child(p)
	return p


## Spawns a one-shot AudioStreamPlayer3D at `parent`, plays the stream, frees
## itself when finished. Concurrent calls don't truncate each other.
func _play_one_shot(stream: AudioStream, parent: Node3D, db: float = -6.0) -> void:
	if stream == null or parent == null or not is_instance_valid(parent):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = db
	p.unit_size = 8.0
	p.max_distance = 60.0
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Per-frame audio update — called from _process. Gates motor loops by axis
## speed and fires hoist-limit clacks on transition.
func _update_audio(delta: float) -> void:
	if delta <= 0.0:
		return
	# Speeds (m/s) since last frame for each axis.
	var v_gantry  := absf(_gantry_x_offset  - _last_gantry_x_for_audio)  / delta
	var v_trolley := absf(_trolley_z        - _last_trolley_z_for_audio) / delta
	var v_hoist   := absf(_hoist_drop       - _last_hoist_drop_for_audio) / delta
	_last_gantry_x_for_audio   = _gantry_x_offset
	_last_trolley_z_for_audio  = _trolley_z
	_last_hoist_drop_for_audio = _hoist_drop

	_gate_motor(_sfx_motor_gantry,  v_gantry)
	_gate_motor(_sfx_motor_trolley, v_trolley)
	_gate_motor(_sfx_motor_hoist,   v_hoist)

	# Hoist limit clacks — fire on edge into the limit, reset on departure.
	var at_bottom := _hoist_drop >= hoist_max_drop - HOIST_LIMIT_EPSILON
	var at_top    := _hoist_drop <= hoist_min_drop + HOIST_LIMIT_EPSILON
	if at_bottom and not _was_hoist_at_bottom and _hook != null:
		_play_one_shot(_sfx_hook_bottom, _hook)
	if at_top and not _was_hoist_at_top and _hook != null:
		_play_one_shot(_sfx_hook_top, _hook)
	_was_hoist_at_bottom = at_bottom
	_was_hoist_at_top = at_top


func _gate_motor(player: AudioStreamPlayer3D, speed: float) -> void:
	if player == null:
		return
	if speed > MOTOR_SPEED_THRESHOLD_M_PER_S:
		if not player.playing:
			player.play()
	else:
		if player.playing:
			player.stop()
