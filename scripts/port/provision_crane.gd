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
		var next_scale := maxf(v, 0.01)
		if is_equal_approx(model_scale, next_scale):
			return
		model_scale = next_scale
		scale = Vector3.ONE * model_scale
		if is_node_ready():
			reload_model()

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
var _running_wheels: Array[Node3D] = []
var _head_sheaves: Array[Node3D] = []
var _lower_sheave: Node3D
var _hoist_drum: Node3D
var _feed_ropes: Array[Node3D] = []
const HOIST_MODELS := "res://resources/models/parts/provision_hoist/"
const LOWER_SHEAVE_HEIGHT_M := 0.85
var _talje_rail_y := -0.78
var _attached_container: ContainerNode = null
var _space_held := false
var _has_loaded_model := false
const GRAB_RADIUS_M := 5.0


func _ready() -> void:
	scale = Vector3.ONE * model_scale
	reload_model()


func reload_model() -> void:
	var preserve_pose := _has_loaded_model
	var saved_pose := Vector3(slew_degrees, trolley_z_m, hoist_length_m)
	# Cargo belongs to gameplay, not to the replaceable model subtree. Keep its
	# identity and grabbed state while rebuilding; do not release/re-grab it.
	if is_instance_valid(_attached_container):
		_attached_container.reparent(self, true)
	_imported_hoist = false
	_running_wheels.clear()
	_head_sheaves.clear()
	_feed_ropes.clear()
	_lower_sheave = null
	_hoist_drum = null
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
		remove_child(_assembler)
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
	_assembler.model_data_path = model_path
	# Configure before entering the tree: its ready callback builds exactly once.
	add_child(_assembler)
	_bind_rig(preserve_pose, saved_pose)


func _bind_rig(preserve_pose: bool = false, saved_pose: Vector3 = Vector3.ZERO) -> void:
	if _assembler == null or not is_instance_valid(_assembler):
		return
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
		_install_imported_structure()
		_install_imported_station()
		_install_hoist_motion()
	if preserve_pose:
		slew_degrees = saved_pose.x
		trolley_z_m = saved_pose.y
		hoist_length_m = saved_pose.z
	_apply_slew()
	_apply_trolley()
	_apply_hoist()
	if is_instance_valid(_attached_container) and is_instance_valid(_hook):
		_attached_container.reparent(_hook, true)
		_tick_attached_container()
	_has_loaded_model = true
	model_loaded.emit(model_path)


func _load_meta() -> void:
	var meta := _model_meta()
	var reach_scale := model_scale if model_path == DEFAULT_MODEL else 1.0
	trolley_min_z_m = float(meta.get("rail_z_min_m", -54.0 if model_path == DEFAULT_MODEL else trolley_min_z_m))*reach_scale
	trolley_max_z_m = float(meta.get("rail_z_max_m", -1.0 if model_path == DEFAULT_MODEL else trolley_max_z_m))*reach_scale
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
		SurfaceMaterialLibrary.apply(visual)
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


func _install_hoist_motion() -> void:
	for side in ["L", "R"]:
		for end in ["F", "B"]:
			_running_wheels.append(_talje.find_child("RunningWheel_"+side+end,true,false) as Node3D)
		_head_sheaves.append(_talje.find_child("HeadSheave_"+side,true,false) as Node3D)
	_lower_sheave = _hook.find_child("LowerSheave",true,false) as Node3D
	for entry in [["provision_hoist_winch", Vector3(-.3,-1.96,10)], ["provision_rope_anchor", Vector3(.3,-1.66,-54.8)]]:
		var scene := load(HOIST_MODELS+entry[0]+".glb") as PackedScene
		var visual := scene.instantiate() as Node3D
		SurfaceMaterialLibrary.apply(visual)
		visual.position = entry[1]*model_scale
		visual.scale = Vector3.ONE*model_scale
		_boom.add_child(visual)
		if entry[0] == "provision_hoist_winch":
			_hoist_drum = visual.find_child("HoistDrum",true,false) as Node3D
	var rope_scene := load(HOIST_MODELS+"provision_feed_rope_1m.glb") as PackedScene
	for side in 2:
		var rope := rope_scene.instantiate() as Node3D
		rope.name = "FeedRope"+str(side)
		_boom.add_child(rope)
		_feed_ropes.append(rope)


func _update_hoist_motion() -> void:
	if _running_wheels.is_empty():
		return
	# Position-derived phases also respond to replicated poses and reverse exactly.
	# The right fall is anchored at the tip; the drum pays out twice the hook travel.
	var travel := trolley_z_m/model_scale
	var drop := hoist_length_m/model_scale
	for wheel in _running_wheels:
		wheel.rotation.x = fposmod(travel/.18,TAU)
	_head_sheaves[0].rotation.x = fposmod(-(2.0*drop+travel)/.17,TAU)
	_head_sheaves[1].rotation.x = fposmod(-travel/.17,TAU)
	_lower_sheave.rotation.z = fposmod((drop+travel)/.30,TAU)
	_hoist_drum.rotation.x = fposmod(-2.0*drop/.30,TAU)
	for side in 2:
		var fixed := Vector3(-.3,-1.66,10) if side==0 else Vector3(.3,-1.66,-54.8)
		var moving := _talje.position + Vector3(-.3 if side==0 else .3,-.88,.17 if side==0 else -.17)*model_scale
		var start := fixed*model_scale
		var direction := moving-start
		var basis := Basis.looking_at(direction.normalized(),Vector3.UP)
		_feed_ropes[side].transform = Transform3D(basis.scaled(Vector3(model_scale,model_scale,direction.length())),start)


func _install_imported_station() -> void:
	# Preserve the nested authority/pose roles and their conservative colliders.
	_clear_station_meshes(_cabin, _engine)
	_clear_station_meshes(_engine, _boom)
	_clear_station_meshes(_pad, _girder)
	var counterweight := _part("counterweight")
	_clear_station_meshes(counterweight, null)
	for entry in [[_cabin, "operator_cab"], [_cabin, "slew_platform"], [_engine, "machinery_station"], [_pad, "tower_foundation"], [counterweight, "counterweight_rack"]]:
		var scene := load("res://resources/models/parts/provision_station/" + entry[1] + ".glb") as PackedScene
		assert(scene != null)
		var visual := scene.instantiate() as Node3D
		SurfaceMaterialLibrary.apply(visual)
		visual.name = entry[1]
		visual.scale = Vector3.ONE * model_scale
		entry[0].add_child(visual)
	# New deck and raised cab roof extend beyond the old opaque-body collision.
	for entry in [[Vector3(-.55,.35,1.105), Vector3(5.20,.10,5.19)], [Vector3(0,2.55,-.04), Vector3(2.36,.14,2.64)]]:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = entry[1]
		shape.shape = box
		shape.position = entry[0]
		body.add_child(shape)
		body.scale = Vector3.ONE * model_scale
		_cabin.add_child(body)


func _clear_station_meshes(node: Node, stop: Node) -> void:
	for child in node.get_children():
		if child == stop:
			continue
		if child is MeshInstance3D:
			node.remove_child(child)
			child.queue_free()
		else:
			_clear_station_meshes(child, stop)


func _install_imported_structure() -> void:
	var mast_offsets: Array[Vector3] = []
	for section in 6:
		mast_offsets.append(Vector3(0,section*5,0))
	_structure_modules(_girder,"mast_section_5m",mast_offsets)
	var jib_offsets: Array[Vector3] = []
	for section in range(-4,11):
		jib_offsets.append(Vector3(0,0,-section*5))
	_structure_modules(_boom,"jib_section_5m",jib_offsets)
	_structure_modules(_boom,"jib_end_frame",[Vector3(0,0,-55)])
	var rail_offsets: Array[Vector3] = []
	for section in 10:
		rail_offsets.append(Vector3(0,0,-.5-section*5))
	_structure_modules(_waist_rails,"trolley_rails_5m",rail_offsets)
	_structure_modules(_waist_rails,"trolley_rails_4m",[Vector3(0,0,-50.5)])
	# Match the raised upper chord; retain the original lower-jib collider.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4,.55,75)
	shape.shape = box
	shape.position = Vector3(0,.935,-17.5)
	body.add_child(shape)
	_boom.add_child(body)
	body.scale = Vector3.ONE * model_scale


func _structure_modules(part: Node3D, asset: String, offsets: Array[Vector3]) -> void:
	# Keep the role children and existing conservative collision envelope.
	for child in part.get_children():
		if child is MeshInstance3D:
			part.remove_child(child)
			child.queue_free()
	var scene := load("res://resources/models/parts/provision_structure/"+asset+".glb") as PackedScene
	var prototype := scene.instantiate() as Node3D
	SurfaceMaterialLibrary.apply(prototype)
	var meshes := prototype.find_children("*","MeshInstance3D",true,false)
	assert(meshes.size()==1,"Structure module must export one merged mesh")
	var source := meshes[0] as MeshInstance3D
	assert(source.transform.is_equal_approx(Transform3D.IDENTITY))
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = SurfaceMaterialLibrary.finished_mesh(source)
	instances.instance_count = offsets.size()
	for index in offsets.size():
		instances.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*model_scale),offsets[index]*model_scale))
	var visual := MultiMeshInstance3D.new()
	visual.name = asset
	visual.multimesh = instances
	part.add_child(visual)
	prototype.free()


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
	_update_hoist_motion()
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
	_update_hoist_motion()
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
	if is_auto_active():
		_space_held = Input.is_physical_key_pressed(KEY_SPACE)
		return
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
	_attached_container = node
	_tick_attached_container()
	node.notify_grabbed()
	## Floor halo is pad-selection only — hide while airborne under the hook.
	node.set_highlighted(false)
	return true


func release_container() -> ContainerNode:
	if _attached_container == null or not is_instance_valid(_attached_container):
		_attached_container = null
		return null
	var node := _attached_container
	if is_inside_tree():
		var pad := CargoSlotPadComponent.find_nearest_pad(get_tree(), node.global_position)
		return release_container_on_pad(pad, node.global_position)
	return null


func release_container_on_pad(pad: CargoSlotPadComponent, world_hint: Vector3 = Vector3.INF) -> ContainerNode:
	if _attached_container == null or not is_instance_valid(_attached_container):
		_attached_container = null
		return null
	var node := _attached_container
	if pad != null and is_instance_valid(pad) and is_inside_tree():
		var target := pad.slot_drop_world_for_free(node.unit.footprint_cells(pad.cell_size_m), world_hint)
		if target == Vector3.INF: return null
		if pad.show_pad_visual: target += pad.global_basis.y * ContainerNode.floor_offset_y()
		# Transactional landing: don't detach until an actual free bed is reached.
		# Failed placement used to reparent at the airborne pose, creating floaters.
		if node.global_position.distance_to(target) > .4: return null
		if pad.try_place_container_node(node, node.global_position):
			_attached_container = null
			node.set_highlighted(false)
			node.notify_released()
			return node
	return null


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
		if absf(slew_err) > 0.04:
			slew_degrees -= clampf(slew_err, -slew_step, slew_step)

	## Trolley — radial reach from slew pivot. Gated on azimuth (like bulk boom IK)
	## so slewing does not pump the talje in and out on a rotating jib bearing.
	var target_reach := to_target.length()
	var hook_reach := to_hook.length()
	var reach_err := target_reach - hook_reach
	# The jib is offset from the slew pivot (-1.75, ..., -.25 in the authored
	# rig). Setting trolley_z=-radius leaves a permanent lateral/radial error.
	# Correct from the actual hook radius, in the trolley parent's local units.
	var rail_scale := maxf(_talje.get_parent_node_3d().global_basis.z.length(), .001)
	var want_z := clampf(trolley_z_m - reach_err / rail_scale, trolley_min_z_m, trolley_max_z_m)
	if absf(slew_err) < 12.0 and target_reach > 0.4 and absf(want_z - trolley_z_m) > 0.025:
		var reach_deadzone := .05
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
			# World-space error to local hoist units; no fixed-step oscillation.
			var hoist_scale := maxf(_talje.global_basis.y.length(), .001)
			hoist_length_m = move_toward(hoist_length_m, hoist_length_m - y_err / hoist_scale, hoist_step / hoist_scale)
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
	if is_instance_valid(_talje) and is_instance_valid(_hook) and is_inside_tree():
		var rail := _talje.get_parent_node_3d()
		var offset := get_hook_global() - get_talje_global()
		var pivot := get_slew_pivot_global()
		var a := rail.to_global(Vector3(0, _talje_rail_y, trolley_max_z_m)) + offset - pivot
		var b := rail.to_global(Vector3(0, _talje_rail_y, trolley_min_z_m)) + offset - pivot
		inner = Vector2(a.x, a.z).length()
		outer = Vector2(b.x, b.z).length()
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
	_attached_container.global_basis = _hook.global_basis.orthonormalized()
	_attached_container.global_position = get_hook_global() - _attached_container.global_basis.y * _attached_container.lift_height_m()


func align_attached_container(target_basis: Basis, delta: float) -> void:
	if not is_instance_valid(_attached_container): return
	var rotation := _attached_container.global_basis.get_rotation_quaternion()
	_attached_container.global_basis = Basis(rotation.slerp(target_basis.get_rotation_quaternion(), minf(delta * 5.0, 1.0)))
	_attached_container.global_position = get_hook_global() - _attached_container.global_basis.y * _attached_container.lift_height_m()


func get_status_lines() -> PackedStringArray:
	var load_line := "Hook   empty  (Space grab/drop — snaps to cargo pad)"
	if _attached_container != null:
		load_line = "Hook   container  (Lower onto a free bed · Space release)"
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
