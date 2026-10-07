class_name ProvisionCrane
extends Node3D

## Harbour T-crane for provisions / general cargo.
## Same pipeline as BulkCrane: ModelAssembler + role-bound parts.
## Axes: slew (cabin), trolley (talje along waist rails), hoist (wire + hook).

const DEFAULT_MODEL := "res://resources/data/models/dockyard/provision_crane.json"
const ASSEMBLER_SCRIPT := preload("res://scripts/core/model_assembler.gd")
const WIRE_REST_LENGTH_M := 10.0

signal model_loaded(path: String)
signal slew_changed(degrees: float)
signal trolley_changed(metres: float)
signal hoist_changed(length_m: float)

@export_file("*.json") var model_path: String = DEFAULT_MODEL:
	set(v):
		model_path = v
		if is_inside_tree():
			reload_model()

@export var slew_degrees: float = 0.0:
	set(v):
		slew_degrees = v
		_apply_slew()

@export_range(-54.0, -1.0, 0.1) var trolley_z_m: float = -14.0:
	set(v):
		trolley_z_m = clampf(v, trolley_min_z_m, trolley_max_z_m)
		_apply_trolley()

@export_range(2.0, 40.0, 0.1) var hoist_length_m: float = 10.0:
	set(v):
		var clamped := clampf(v, hoist_min_m, hoist_max_m)
		if is_equal_approx(hoist_length_m, clamped):
			return
		hoist_length_m = clamped
		_apply_hoist()

@export var trolley_min_z_m: float = -54.0
@export var trolley_max_z_m: float = -1.0
@export var hoist_min_m: float = 2.0
@export var hoist_max_m: float = 32.0
@export var slew_speed_deg: float = 45.0
@export var trolley_speed_m: float = 10.0
@export var hoist_speed_m: float = 8.0
@export var model_scale: float = 1.0:
	set(v):
		model_scale = maxf(v, 0.01)
		scale = Vector3.ONE * model_scale
		if _assembler != null and is_instance_valid(_assembler):
			_assembler.absolute_scale = model_scale

var _assembler: Node3D
var _pad: Node3D
var _girder: Node3D
var _cabin: Node3D
var _engine: Node3D
var _boom: Node3D
var _waist_rails: Node3D
var _talje: Node3D
var _wire: Node3D
var _wire_mesh: MeshInstance3D
var _wire_mesh_base_scale := Vector3.ONE
var _hook: Node3D
var _wire_rest_length := WIRE_REST_LENGTH_M
var _imported_hoist := false
const HOIST_MODELS := "res://resources/models/parts/provision_hoist/"
const LOWER_SHEAVE_HEIGHT_M := 0.85
var _talje_rail_y := -0.78
var _attached_container: ContainerNode = null
var _space_held := false
const GRAB_RADIUS_M := 5.0


func _ready() -> void:
	scale = Vector3.ONE * model_scale
	reload_model()


func reload_model() -> void:
	_imported_hoist = false
	_pad = null
	_girder = null
	_cabin = null
	_engine = null
	_boom = null
	_waist_rails = null
	_talje = null
	_wire = null
	_wire_mesh = null
	_hook = null
	if _assembler != null and is_instance_valid(_assembler):
		_assembler.queue_free()
		_assembler = null
	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		push_warning("ProvisionCrane: missing model %s" % model_path)
		return
	_assembler = ASSEMBLER_SCRIPT.new()
	_assembler.name = "Model"
	_assembler.absolute_scale = model_scale
	## Part meshes host their own StaticBody3D via MeshTransformer (pad/mast/boom…).
	_assembler.build_part_colliders = true
	add_child(_assembler)
	_assembler.model_data_path = model_path
	call_deferred("_bind_rig")


func _bind_rig() -> void:
	if _assembler == null or not is_instance_valid(_assembler):
		return
	if _assembler.has_method("rebuild"):
		_assembler.rebuild()
	_pad = _part("pad")
	_girder = _part("girder")
	_cabin = _part("cabin")
	_engine = _part("engine")
	_boom = _part("boom")
	_waist_rails = _part("waist_rails")
	_talje = _part("talje")
	_wire = _part("wire")
	_hook = _part("hook")
	_load_meta()
	_rig_hoist_parts()
	if model_path == DEFAULT_MODEL:
		_install_imported_hoist()
	_apply_slew()
	_apply_trolley()
	_apply_hoist()
	model_loaded.emit(model_path)


func _load_meta() -> void:
	var meta := _model_meta()
	trolley_min_z_m = float(meta.get("rail_z_min_m", trolley_min_z_m))
	trolley_max_z_m = float(meta.get("rail_z_max_m", trolley_max_z_m))
	_wire_rest_length = float(meta.get("wire_rest_length_m", WIRE_REST_LENGTH_M))
	if _talje != null and is_instance_valid(_talje):
		_talje_rail_y = _talje.position.y
		trolley_z_m = _talje.position.z
	hoist_length_m = _wire_rest_length


func _rig_hoist_parts() -> void:
	if _wire == null:
		return
	_wire.scale = Vector3.ONE
	_wire_mesh = _find_wire_mesh(_wire)
	if _wire_mesh != null:
		_wire_mesh_base_scale = _wire_mesh.scale
	## Hook must not inherit wire mesh scale — reparent under talje like bulk bucket→boom.
	if _hook != null and is_instance_valid(_hook) and _talje != null and is_instance_valid(_talje):
		if _hook.get_parent() != _talje:
			_hook.reparent(_talje, false)


func _model_meta() -> Dictionary:
	if model_path.is_empty() or not FileAccess.file_exists(model_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(model_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var root := parsed as Dictionary
	var meta: Variant = root.get("meta", {})
	return meta as Dictionary if typeof(meta) == TYPE_DICTIONARY else {}


func _install_imported_hoist() -> void:
	# Keep the existing role nodes, pivots and cargo load seat. Only replace the
	# default crane's generated visual/collision children after rig reparenting.
	for entry in [[_hook, "provision_hook_block"], [_wire, "provision_rope_pair_10m"], [_talje, "provision_trolley"]]:
		var part: Node3D = entry[0]
		for child in part.get_children():
			if child is MeshTransformer or child is ModelAssembler:
				continue
			part.remove_child(child)
			child.queue_free()
		var scene := load(HOIST_MODELS + entry[1] + ".glb") as PackedScene
		assert(scene != null)
		var visual := scene.instantiate() as Node3D
		visual.scale = Vector3.ONE * model_scale
		part.add_child(visual)
	# Guard collision follows the moving block, never the stretching wire.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.76,.82,.42)
	shape.shape = box
	shape.position.y = .81
	body.add_child(shape)
	_hook.add_child(body)
	body.scale = Vector3.ONE * model_scale
	var trolley_body := StaticBody3D.new()
	trolley_body.collision_layer = 1
	trolley_body.collision_mask = 0
	var trolley_shape := CollisionShape3D.new()
	var trolley_box := BoxShape3D.new()
	trolley_box.size = Vector3(1.4,.3,1.4)
	trolley_shape.shape = trolley_box
	trolley_shape.position.y = -.25
	trolley_body.add_child(trolley_shape)
	_talje.add_child(trolley_body)
	trolley_body.scale = Vector3.ONE * model_scale
	_wire_mesh = _find_wire_mesh(_wire)
	_wire_mesh_base_scale = _wire_mesh.scale
	_imported_hoist = true


func _apply_slew() -> void:
	if _cabin == null or not is_instance_valid(_cabin):
		return
	var r := _cabin.rotation_degrees
	r.y = slew_degrees
	_cabin.rotation_degrees = r
	slew_changed.emit(slew_degrees)


func _apply_trolley() -> void:
	if _talje == null or not is_instance_valid(_talje):
		return
	_talje.position = Vector3(0.0, _talje_rail_y, trolley_z_m)
	trolley_changed.emit(trolley_z_m)


func _apply_hoist() -> void:
	if _wire == null or not is_instance_valid(_wire):
		return
	if _wire_mesh == null or not is_instance_valid(_wire_mesh):
		_wire_mesh = _find_wire_mesh(_wire)
		if _wire_mesh != null:
			_wire_mesh_base_scale = _wire_mesh.scale
	var rest := maxf(_wire_rest_length, 0.1)
	# The straight falls meet the sheave tangents above the unchanged load seat.
	var visible_length := hoist_length_m - LOWER_SHEAVE_HEIGHT_M * model_scale if _imported_hoist else hoist_length_m
	var ratio := visible_length / (rest * model_scale) if _imported_hoist else visible_length / rest
	_wire.scale = Vector3.ONE
	if _wire_mesh != null and is_instance_valid(_wire_mesh):
		_wire_mesh.scale = Vector3(
			_wire_mesh_base_scale.x,
			_wire_mesh_base_scale.y * ratio,
			_wire_mesh_base_scale.z,
		)
	if _hook != null and is_instance_valid(_hook):
		_hook.position = _hoist_attachment_on_talje()
		_hook.rotation = _wire.rotation
	hoist_changed.emit(hoist_length_m)


func _hoist_attachment_on_talje() -> Vector3:
	if _wire == null or not is_instance_valid(_wire):
		return Vector3(0.0, -hoist_length_m, 0.0)
	return _wire.position + _wire.basis * Vector3(0.0, -hoist_length_m, 0.0)


func _find_wire_mesh(wire_node: Node3D) -> MeshInstance3D:
	if wire_node == null:
		return null
	for child in wire_node.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
		if child is Node3D:
			var nested := _find_wire_mesh(child as Node3D)
			if nested != null:
				return nested
	return null


func step(delta: float, command: ProvisionCraneCommand = null) -> void:
	if command == null:
		command = ProvisionCraneCommand.new()
	if not is_zero_approx(command.slew_rate):
		slew_degrees = slew_degrees + command.slew_rate * slew_speed_deg * delta
	if not is_zero_approx(command.trolley_rate):
		trolley_z_m = trolley_z_m + command.trolley_rate * trolley_speed_m * delta
	if not is_zero_approx(command.hoist_rate):
		hoist_length_m = hoist_length_m + command.hoist_rate * hoist_speed_m * delta


func playtest_input(delta: float) -> void:
	var cmd := ProvisionCraneCommand.new()
	if Input.is_key_pressed(KEY_A):
		cmd.slew_rate += 1.0
	if Input.is_key_pressed(KEY_D):
		cmd.slew_rate -= 1.0
	if Input.is_key_pressed(KEY_W):
		cmd.trolley_rate -= 1.0
	if Input.is_key_pressed(KEY_S):
		cmd.trolley_rate += 1.0
	if Input.is_key_pressed(KEY_Q):
		cmd.hoist_rate -= 1.0
	if Input.is_key_pressed(KEY_E):
		cmd.hoist_rate += 1.0
	step(delta, cmd)
	var space_down := Input.is_physical_key_pressed(KEY_SPACE)
	if space_down and not _space_held:
		if _attached_container == null:
			try_attach_nearest_container()
		else:
			release_container()
	_space_held = space_down
	_tick_attached_container()


func get_pad() -> Node3D:
	return _pad


func get_girder() -> Node3D:
	return _girder


func get_cabin() -> Node3D:
	return _cabin


func get_engine() -> Node3D:
	return _engine


func get_boom() -> Node3D:
	return _boom


func get_waist_rails() -> Node3D:
	return _waist_rails


func get_talje() -> Node3D:
	return _talje


func get_wire() -> Node3D:
	return _wire


func get_hook() -> Node3D:
	return _hook


func get_slew_pivot_global() -> Vector3:
	if _cabin != null and is_instance_valid(_cabin):
		return _cabin.global_position
	return global_position


func get_hook_global() -> Vector3:
	if _hook != null and is_instance_valid(_hook):
		return _hook.global_position
	return global_position


func get_talje_global() -> Vector3:
	if _talje != null and is_instance_valid(_talje):
		return _talje.global_position
	return global_position


func get_attached_container() -> ContainerNode:
	return _attached_container


func try_attach_nearest_container() -> bool:
	if _attached_container != null:
		return true
	if not is_inside_tree():
		return false
	var hook_pos := get_hook_global()
	var best: ContainerNode = null
	var best_d := GRAB_RADIUS_M
	for node in get_tree().get_nodes_in_group(ContainerNode.GROUP):
		if node is not ContainerNode:
			continue
		var cn := node as ContainerNode
		if cn == _attached_container:
			continue
		var d := hook_pos.distance_to(cn.to_global(Vector3(0,cn.lift_height_m(),0)))
		if d < best_d:
			best_d = d
			best = cn
	if best == null:
		return false
	return attach_container(best)


func attach_container(node: ContainerNode) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if _attached_container != null:
		return false
	var pad := CargoSlotPadComponent.find_pad_for_node(node)
	if pad != null:
		pad.take_container_node(node)
	var parent := _hook if _hook != null else self
	node.reparent(parent, true)
	node.position = Vector3(0.0, -node.lift_height_m(), 0.0)
	node.rotation = Vector3.ZERO
	_attached_container = node
	node.notify_grabbed()
	## Floor halo is pad-selection only — hide while airborne under the hook.
	node.set_highlighted(false)
	return true


func release_container() -> ContainerNode:
	if _attached_container == null or not is_instance_valid(_attached_container):
		_attached_container = null
		return null
	var node := _attached_container
	_attached_container = null
	node.set_highlighted(false)
	node.notify_released()
	var hook_pos := get_hook_global()
	if is_inside_tree():
		var pad := CargoSlotPadComponent.find_nearest_pad(get_tree(), hook_pos)
		if pad != null and pad.try_place_container_node(node, hook_pos):
			return node
	return _drop_container_to_quay(node)


func release_container_on_pad(pad: CargoSlotPadComponent) -> ContainerNode:
	if _attached_container == null or not is_instance_valid(_attached_container):
		_attached_container = null
		return null
	var node := _attached_container
	_attached_container = null
	node.set_highlighted(false)
	node.notify_released()
	if pad != null and is_instance_valid(pad) and is_inside_tree():
		if pad.try_place_container_node(node, get_hook_global()):
			return node
	return _drop_container_to_quay(node)


func release_container_to_world(world_pos: Vector3, parent: Node = null) -> ContainerNode:
	if _attached_container == null or not is_instance_valid(_attached_container):
		_attached_container = null
		return null
	var node := _attached_container
	_attached_container = null
	node.set_highlighted(false)
	node.notify_released()
	var drop_parent := parent
	if drop_parent == null:
		drop_parent = _quay_drop_parent()
	if drop_parent == null and is_inside_tree():
		drop_parent = get_tree().current_scene
	node.reparent(drop_parent, true)
	node.global_position = world_pos
	node.rotation = Vector3.ZERO
	return node


func _drop_container_to_quay(node: ContainerNode) -> ContainerNode:
	var drop_parent := _quay_drop_parent()
	if drop_parent == null and is_inside_tree():
		drop_parent = get_tree().current_scene
	var world_xf := node.global_transform
	node.reparent(drop_parent, true)
	node.global_transform = world_xf
	return node


func _quay_drop_parent() -> Node:
	var drop_parent := get_parent()
	while drop_parent != null and drop_parent.get_parent() != null \
			and str(drop_parent.name) != "QuayRow" and str(drop_parent.name) != "CraneShowcase":
		if str(drop_parent.name).begins_with("Bay_"):
			break
		drop_parent = drop_parent.get_parent()
	return drop_parent


func ik_hook_to(delta: float, target: Vector3, hoist_mode: String = "track") -> void:
	var pivot := get_slew_pivot_global()
	var hook := get_hook_global()
	var slew_step := slew_speed_deg * delta
	var trolley_step := trolley_speed_m * delta
	var hoist_step := hoist_speed_m * delta * 1.4

	var to_target := Vector2(target.x - pivot.x, target.z - pivot.z)
	var to_hook := Vector2(hook.x - pivot.x, hook.z - pivot.z)
	var slew_err := 0.0
	if to_target.length() > 0.4 and to_hook.length() > 0.4:
		slew_err = rad_to_deg(to_hook.angle_to(to_target))
		if absf(slew_err) > 2.0:
			slew_degrees -= clampf(slew_err, -slew_step, slew_step)

	## Trolley — radial reach from slew pivot. Gated on azimuth (like bulk boom IK)
	## so slewing does not pump the talje in and out on a rotating jib bearing.
	var target_reach := to_target.length()
	var hook_reach := to_hook.length()
	var reach_err := target_reach - hook_reach
	var want_z := clampf(-target_reach, trolley_min_z_m, trolley_max_z_m)
	if absf(slew_err) < 12.0 and target_reach > 0.4 and absf(want_z - trolley_z_m) > 0.5:
		var reach_deadzone := 2.0 if hoist_mode == "raise" else 1.25
		if absf(reach_err) > reach_deadzone:
			var soft := clampf(absf(reach_err) / 8.0, 0.15, 1.0)
			var rate := 0.35 if hoist_mode == "raise" else 0.55
			trolley_z_m = move_toward(trolley_z_m, want_z, trolley_step * soft * rate)

	match hoist_mode:
		"raise":
			var raised := hoist_min_m + 2.0
			hoist_length_m = move_toward(hoist_length_m, raised, hoist_step)
		"track":
			var y_err := target.y - hook.y
			if y_err < -0.35:
				hoist_length_m += hoist_step
			elif y_err > 0.35:
				hoist_length_m -= hoist_step
		_:
			pass


func hook_distance_to(target: Vector3) -> float:
	return get_hook_global().distance_to(target)


func hook_horizontal_distance_to(target: Vector3) -> float:
	var hook := get_hook_global()
	return Vector2(target.x - hook.x, target.z - hook.z).length()


func is_hook_near(target: Vector3, radius_m: float = 3.5) -> bool:
	return hook_distance_to(target) <= radius_m


func is_hook_over(target: Vector3, radius_m: float = 4.0) -> bool:
	return hook_horizontal_distance_to(target) <= radius_m


## Trolley rail span along the jib (metres from slew pivot).
func horizontal_reach_limits_m() -> Vector2:
	var inner := absf(trolley_max_z_m)
	var outer := absf(trolley_min_z_m)
	if inner > outer:
		var swap := inner
		inner = outer
		outer = swap
	return Vector2(inner, outer)


func can_reach_point(target: Vector3, margin_m: float = 3.0) -> bool:
	var pivot := get_slew_pivot_global()
	var horiz := Vector2(target.x - pivot.x, target.z - pivot.z).length()
	var limits := horizontal_reach_limits_m()
	return horiz >= limits.x - margin_m and horiz <= limits.y + margin_m


func can_reach_ship(ship: BoatBody) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	for pad in ship.get_cargo_pads():
		if can_reach_point(pad.global_position):
			return true
	return can_reach_point(ship.global_position)


func get_auto_operator() -> Node:
	return get_node_or_null("AutoOperator")


func start_auto_load(ship: BoatBody) -> bool:
	var op := get_auto_operator()
	if op == null or not op.has_method("start_load"):
		return false
	return op.start_load(ship)


func start_auto_unload(ship: BoatBody) -> bool:
	var op := get_auto_operator()
	if op == null or not op.has_method("start_unload"):
		return false
	return op.start_unload(ship)


func stop_auto() -> void:
	var op := get_auto_operator()
	if op != null and op.has_method("stop"):
		op.stop()


func is_auto_active() -> bool:
	var op := get_auto_operator()
	return op != null and op.has_method("is_active") and op.is_active()


func _tick_attached_container() -> void:
	if _attached_container == null or not is_instance_valid(_attached_container):
		_attached_container = null
		return
	## Keep snug under hook while slewing / trolleying / hoisting.
	_attached_container.position = Vector3(0.0, -_attached_container.lift_height_m(), 0.0)
	_attached_container.rotation = Vector3.ZERO


func get_status_lines() -> PackedStringArray:
	var load_line := "Hook   empty  (Space grab/drop — snaps to cargo pad)"
	if _attached_container != null:
		load_line = "Hook   container  (Space drop onto pad grid)"
	return PackedStringArray([
		"Type   Provision T-crane",
		"Model  %s" % model_path.get_file(),
		"Slew   %.1f°   (A / D)" % slew_degrees,
		"Trolley z=%.1f m  (W / S)" % trolley_z_m,
		"Hoist  %.1f m  (Q / E)" % hoist_length_m,
		load_line,
	])


func _part(role_or_name: String) -> Node3D:
	if _assembler == null:
		return null
	if _assembler.has_method("get_part"):
		var by_name: Node3D = _assembler.get_part(role_or_name) as Node3D
		if by_name != null:
			return by_name
	if _assembler.has_method("get_first_part_by_role"):
		var by_role: Node3D = _assembler.get_first_part_by_role(role_or_name) as Node3D
		if by_role != null:
			return by_role
	return _assembler.find_child("ModelPart_%s" % role_or_name, true, false) as Node3D
