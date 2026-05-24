@tool
class_name FishingSystem
extends Node3D

## Visual and physical fishing system component.
## Instantiated on vessels with the "fishing" capability.
## Renders a spinning trommel winch and casts a trailing semi-transparent net.

@export var trawling: bool = false:
	set(v):
		trawling = v
		_update_trawl_visuals()

@export var trommel_rotation_speed: float = 3.0
@export var drag_coefficient: float = 8000.0
@export var catch_interval_seconds: float = 20.0
## Seconds between each crate winched aboard during a haul.
@export var crate_stagger_seconds: float = 5.0
## Crates per successful haul (placed one at a time).
@export var crates_per_haul: int = 4
## How far the net mouth sits below the wave surface when trawling.
@export var net_mouth_submerge: float = 0.45
## Pay-out rope length from the trommel drum to the net head (metres, before hull scale).
@export var net_rope_length: float = 11.0

const NET_MESH_HEIGHT := 7.0
## How far the net mouth trails horizontally beyond the rope head ring.
const NET_MOUTH_AFT_OFFSET := 2.6

var _body: BoatBody = null
var _propulsion: PropulsionComponent = null
var _cargo_deck: CargoDeckComponent = null

var _trommel_winch: Node3D
var _drum_rotation_node: Node3D
var _net_mesh: MeshInstance3D
var _rope_mesh: MeshInstance3D
var _visual_scale: float = 1.0
var _catch_timer: float = 0.0
var _zone_catch_mul: float = 1.0
var _haul_crates_remaining: int = 0
var _haul_stagger_timer: float = 0.0
var _haul_zone: Dictionary = {}
var _haul_toast_sent: bool = false
var _net_base_local_pos: Vector3 = Vector3.ZERO
var _net_base_local_basis: Basis = Basis.IDENTITY

func _ready() -> void:
	_body = get_parent() as BoatBody
	if _body == null:
		# If added under ShipGameplay, search upwards
		var p := get_parent()
		while p != null:
			if p is BoatBody:
				_body = p as BoatBody
				break
			p = p.get_parent()
	
	if _body != null:
		# Find siblings
		_propulsion = _body.find_child("PropulsionComponent", true, false) as PropulsionComponent
		_cargo_deck = _body.find_child("CargoDeck_*", true, false) as CargoDeckComponent

	_setup_visuals()
	_update_trawl_visuals()


func toggle_trawling() -> void:
	trawling = not trawling
	if not trawling:
		_cancel_haul(false)
	if _body != null:
		var controller = _body.find_child("BoatController", true, false) as BoatController
		if controller != null:
			var hud = controller.get("_ship_hud")
			if hud != null and hud.has_method("show_toast"):
				if trawling:
					hud.show_toast("Net Cast - Trawling Active")
				else:
					hud.show_toast("Net Retracted - Trawling Stopped")


func _setup_visuals() -> void:
	# Clean up existing nodes to avoid duplicates when running in tool mode
	for child in get_children():
		if child.name in ["TrommelWinch", "TrawlNet", "TowRope"]:
			if Engine.is_editor_hint():
				child.free()
			else:
				child.queue_free()

	# Position at the center stern deck. We derive the Z position from propulsion offset.
	var stern_z := -5.5
	if _propulsion != null:
		stern_z = _propulsion.stern_offset.z
	else:
		# Fallback for showcase preview / tool mode
		var visuals = get_parent().get_node_or_null("HullVisuals") if get_parent() != null else null
		if visuals != null and "model_data_path" in visuals:
			var path: String = visuals.model_data_path
			if not path.is_empty():
				var data = JsonUtil.load(path)
				if data is Dictionary and data.has("slots"):
					var raw_slots = data["slots"]
					if raw_slots is Dictionary and raw_slots.has("propulsion"):
						var prop_arr = raw_slots["propulsion"]
						if prop_arr is Array and prop_arr.size() >= 3:
							var scale: float = 1.0
							if "absolute_scale" in visuals:
								scale = float(visuals.absolute_scale)
							stern_z = float(prop_arr[2]) * scale
	
	# Adjust deck height based on parent scale
	var deck_y := 1.2
	var scale: float = 1.0
	if _body != null:
		scale = _body.mesh_scale
		deck_y = 1.2 * scale
	else:
		# Fallback for showcase
		var visuals = get_parent().get_node_or_null("HullVisuals") if get_parent() != null else null
		if visuals != null:
			if "absolute_scale" in visuals:
				scale = float(visuals.absolute_scale)
			deck_y = 1.2 * scale
	_visual_scale = scale
	var stern_local := Vector3(absf(stern_z) - 0.6 * scale, 0.0, 0.0)
	if _propulsion != null and _body != null and get_parent() is Node3D:
		# stern_offset is the actual stern point; the PropulsionComponent node stays at hull origin.
		var stern_world := _body.to_global(_propulsion.stern_offset)
		stern_local = (get_parent() as Node3D).to_local(stern_world)
		stern_local.x -= 0.6 * scale
	position = Vector3(stern_local.x, deck_y + 0.2 * scale, stern_local.z)
	
	# 1. Trommel Winch Mount Node
	_trommel_winch = Node3D.new()
	_trommel_winch.name = "TrommelWinch"
	_add_child_with_owner(self, _trommel_winch)
	
	# 2. Spin-capable drum
	_drum_rotation_node = Node3D.new()
	_drum_rotation_node.name = "DrumRotationNode"
	_add_child_with_owner(_trommel_winch, _drum_rotation_node)
	
	# 3. Main drum mesh (horizontal cylinder)
	var drum_mi := MeshInstance3D.new()
	drum_mi.name = "WinchDrum"
	var drum_mesh := CylinderMesh.new()
	drum_mesh.top_radius = 0.22
	drum_mesh.bottom_radius = 0.22
	drum_mesh.height = 1.6
	drum_mesh.radial_segments = 16
	drum_mi.mesh = drum_mesh
	
	# Steel material
	var steel_mat := StandardMaterial3D.new()
	steel_mat.albedo_color = Color(0.20, 0.22, 0.24)
	steel_mat.metallic = 0.9
	steel_mat.roughness = 0.25
	drum_mi.material_override = steel_mat
	
	# Rotate horizontal (align with Z axis)
	drum_mi.rotation.x = PI * 0.5
	_add_child_with_owner(_drum_rotation_node, drum_mi)
	
	# 4. Flanges (side metal plates)
	for side in [-0.8, 0.8]:
		var flange := MeshInstance3D.new()
		flange.name = "Flange_" + ("Port" if side < 0 else "Stbd")
		var flange_mesh := CylinderMesh.new()
		flange_mesh.top_radius = 0.38
		flange_mesh.bottom_radius = 0.38
		flange_mesh.height = 0.08
		flange_mesh.radial_segments = 16
		flange.mesh = flange_mesh
		flange.material_override = steel_mat
		flange.rotation.x = PI * 0.5
		flange.position.z = side
		_add_child_with_owner(_drum_rotation_node, flange)
 
	# 5. Trommel Winch Supports (V-shaped legs down to the deck at 70 degrees stilt angle)
	var leg_angle_rad := deg_to_rad(20.0) # 70 degrees relative to horizontal deck
	var leg_length := 1.49 * scale
	var leg_thickness := 0.08 * scale
	var leg_width := 0.12 * scale
	for side in [-0.8, 0.8]:
		for tilt in [-1.0, 1.0]:
			var leg_pivot := Node3D.new()
			leg_pivot.name = "LegPivot_" + ("Port" if side < 0 else "Stbd") + "_" + ("Fwd" if tilt > 0 else "Aft")
			leg_pivot.position = Vector3(0.0, 0.0, side)
			leg_pivot.rotation.z = tilt * leg_angle_rad
			_add_child_with_owner(_trommel_winch, leg_pivot)
			
			var leg_mesh_instance := MeshInstance3D.new()
			leg_mesh_instance.name = "LegMesh"
			var leg_mesh := BoxMesh.new()
			leg_mesh.size = Vector3(leg_width, leg_length, leg_thickness)
			leg_mesh_instance.mesh = leg_mesh
			leg_mesh_instance.material_override = steel_mat
			leg_mesh_instance.position = Vector3(0.0, -leg_length * 0.5, 0.0)
			_add_child_with_owner(leg_pivot, leg_mesh_instance)
 
	# 6. Tow rope + trawl net trailing far astern on the pay-out line.
	_rope_mesh = MeshInstance3D.new()
	_rope_mesh.name = "TowRope"
	var rope_mesh := CylinderMesh.new()
	rope_mesh.top_radius = 0.035
	rope_mesh.bottom_radius = 0.035
	rope_mesh.height = 1.0
	rope_mesh.radial_segments = 8
	rope_mesh.rings = 1
	_rope_mesh.mesh = rope_mesh
	_rope_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rope_mat := StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.42, 0.36, 0.24)
	rope_mat.roughness = 0.92
	_rope_mesh.material_override = rope_mat
	_add_child_with_owner(self, _rope_mesh)

	_net_mesh = MeshInstance3D.new()
	_net_mesh.name = "TrawlNet"
	var net_mesh := CylinderMesh.new()
	net_mesh.top_radius = 0.05
	net_mesh.bottom_radius = 0.8
	net_mesh.height = NET_MESH_HEIGHT
	net_mesh.radial_segments = 12
	net_mesh.rings = 6
	_net_mesh.mesh = net_mesh
	
	# Premium translucent green net material
	var net_mat := StandardMaterial3D.new()
	net_mat.albedo_color = Color(0.12, 0.48, 0.28, 0.40)
	net_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	net_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	net_mat.roughness = 0.95
	_net_mesh.material_override = net_mat
	_add_child_with_owner(self, _net_mesh)
	_store_net_rest_pose()


func _add_child_with_owner(parent_node: Node, child_node: Node) -> void:
	parent_node.add_child(child_node)
	if Engine.is_editor_hint():
		var scene_root := get_tree().edited_scene_root if is_inside_tree() else null
		if scene_root != null:
			child_node.owner = scene_root


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if trawling and _drum_rotation_node != null:
		_drum_rotation_node.rotate_z(delta * trommel_rotation_speed)
	_update_trawl_rig()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	if trawling:
		# Apply backward central drag force to slow the boat
		if _body != null and _body is RigidBody3D:
			var vel := _body.linear_velocity
			var horiz_vel := Vector3(vel.x, 0.0, vel.z)
			var speed := horiz_vel.length()
			if speed > 0.1:
				var drag_force := -horiz_vel.normalized() * (speed * drag_coefficient)
				_body.apply_central_force(drag_force)

			# Periodically catch fish if moving > 0.5 m/s (approx 1 knot)
			if speed > 0.5:
				_update_zone_catch_rate(_body.global_position)
				_process_haul(delta)
				if _haul_crates_remaining <= 0:
					_catch_timer += delta
					var interval := catch_interval_seconds / maxf(_zone_catch_mul, 0.1)
					if _catch_timer >= interval:
						_catch_timer = 0.0
						_try_start_haul()
	else:
		_catch_timer = 0.0
		_cancel_haul(false)


func _update_zone_catch_rate(sample_pos: Vector3) -> void:
	if not FishingField.is_initialized():
		_zone_catch_mul = 1.0
		return
	var zone := FishingField.sample(sample_pos)
	_zone_catch_mul = maxf(float(zone.get("catch_mul", 1.0)), 0.1)


func _process_haul(delta: float) -> void:
	if _haul_crates_remaining <= 0:
		return
	_haul_stagger_timer -= delta
	if _haul_stagger_timer > 0.0:
		return
	if _place_one_fish_crate():
		_haul_crates_remaining -= 1
		if _haul_crates_remaining > 0:
			_haul_stagger_timer = crate_stagger_seconds
		else:
			_haul_zone = {}
			_haul_toast_sent = false
	else:
		_notify_trawl("Deck is FULL! No room for fish!")
		_cancel_haul(false)


func _cancel_haul(reset_catch_timer: bool) -> void:
	_haul_crates_remaining = 0
	_haul_stagger_timer = 0.0
	_haul_zone = {}
	_haul_toast_sent = false
	if reset_catch_timer:
		_catch_timer = 0.0


func _try_start_haul() -> void:
	if _body == null or _haul_crates_remaining > 0:
		return

	var sample_pos := _body.global_position
	var zone := FishingField.sample(sample_pos) if FishingField.is_initialized() else {}
	if FishingField.is_initialized() and not bool(zone.get("open_water", false)):
		_notify_trawl("Too close to shore — move to open water")
		return
	if float(zone.get("catch_mul", 1.0)) < 0.2:
		return

	var decks := _body.find_children("*", "CargoDeckComponent", true, false)
	if decks.is_empty():
		return

	var crate_count := _crates_for_zone(zone)
	if crate_count <= 0:
		return

	_haul_zone = zone
	_haul_crates_remaining = crate_count
	_haul_stagger_timer = 0.0
	_haul_toast_sent = false


func _crates_for_zone(zone: Dictionary) -> int:
	var catch_mul := float(zone.get("catch_mul", 1.0))
	if catch_mul >= 1.4:
		return maxi(crates_per_haul, 1)
	if catch_mul >= 1.1:
		return maxi(crates_per_haul - 1, 1)
	if catch_mul >= 0.85:
		return maxi(mini(crates_per_haul, 3), 1)
	return maxi(mini(crates_per_haul, 2), 1)


func _place_one_fish_crate() -> bool:
	if _body == null:
		return false

	var zone := _haul_zone
	var price_mul := float(zone.get("price_mul", 1.0)) if not zone.is_empty() else 1.0
	var tier_label := str(zone.get("tier_label", ""))
	var crate_value := ContractRegistry.fish_crate_value(price_mul)

	var fish_pallet := Pallet.new()
	fish_pallet.id = UuidUtil.generate()
	fish_pallet.contract_id = ""
	fish_pallet.origin_port_id = ""
	fish_pallet.destination_port_id = ""
	fish_pallet.commodity = "fish"
	fish_pallet.display_name = "Fresh Fish" if tier_label.is_empty() else "Fresh Fish (%s)" % tier_label
	fish_pallet.units = 1
	fish_pallet.max_units = 1
	fish_pallet.footprint = Vector2i(1, 1)
	fish_pallet.mass_kg = 200.0
	fish_pallet.value_gold = crate_value

	var decks := _body.find_children("*", "CargoDeckComponent", true, false)
	for deck_node in decks:
		var deck := deck_node as CargoDeckComponent
		if deck.add_pallet(fish_pallet) >= 0:
			if not _haul_toast_sent:
				_haul_toast_sent = true
				var pay_line := PlayerData.format_money(crate_value)
				if tier_label.is_empty() or tier_label == "Normal":
					_notify_trawl("Fish on deck — %s per crate at port" % pay_line)
				else:
					_notify_trawl("%s grounds — %s per crate" % [tier_label, pay_line])
			return true
	return false


func _notify_trawl(message: String) -> void:
	if _body == null:
		return
	var controller := _body.find_child("BoatController", true, false) as BoatController
	if controller == null:
		return
	var hud = controller.get("_ship_hud")
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message)


func _update_trawl_visuals() -> void:
	if _net_mesh != null:
		_net_mesh.visible = trawling
		if not trawling:
			_net_mesh.position = _net_base_local_pos
			_net_mesh.basis = _net_base_local_basis
	if _rope_mesh != null:
		_rope_mesh.visible = trawling


func _store_net_rest_pose() -> void:
	var astern := Vector3.RIGHT
	var head := Vector3(_scaled_rope_length(), -1.6 * _visual_scale, 0.0)
	var mouth := head + astern * NET_MOUTH_AFT_OFFSET + Vector3(0.0, -2.2 * _visual_scale, 0.0)
	var y_dir := (head - mouth).normalized()
	_net_base_local_pos = head - y_dir * (NET_MESH_HEIGHT * 0.5)
	_net_mesh.position = _net_base_local_pos
	_net_mesh.basis = _basis_y_points_to(y_dir, astern)
	_net_base_local_basis = _net_mesh.basis


func _scaled_rope_length() -> float:
	return net_rope_length * _visual_scale


func _rope_payout_local() -> Vector3:
	# Drum pay-out point just aft of the trommel drum centre.
	return Vector3(0.18 * _visual_scale, 0.0, 0.0)


func _ship_astern_horizontal() -> Vector3:
	var aft := global_transform.basis.x
	aft.y = 0.0
	if aft.length_squared() < 0.0001:
		return Vector3.FORWARD
	return aft.normalized()


func _basis_y_points_to(y_dir: Vector3, astern_hint: Vector3) -> Basis:
	y_dir = y_dir.normalized()
	var x_dir := astern_hint.cross(y_dir).normalized()
	if x_dir.length_squared() < 0.0001:
		x_dir = Vector3.RIGHT.cross(y_dir).normalized()
	var z_dir := x_dir.cross(y_dir).normalized()
	return Basis(x_dir, y_dir, z_dir)


func _update_trawl_rig() -> void:
	if _net_mesh == null or not trawling:
		return

	var payout_global := global_transform * _rope_payout_local()
	var astern := _ship_astern_horizontal()

	# Rope runs from the drum down to the net head at the surface.
	var head_global := payout_global + astern * _scaled_rope_length()
	head_global.y = WaveSurface.get_height_at(head_global.x, head_global.z) + 0.12 * _visual_scale

	# Net mouth opens further astern and below the surface.
	var mouth_global := head_global + astern * (NET_MOUTH_AFT_OFFSET * _visual_scale)
	mouth_global.y = WaveSurface.get_height_at(mouth_global.x, mouth_global.z) - net_mouth_submerge

	var y_dir := (head_global - mouth_global).normalized()
	if y_dir.length_squared() < 0.0001:
		y_dir = (Vector3.UP * 0.35 + astern * 0.35).normalized()

	var center_global := head_global - y_dir * (NET_MESH_HEIGHT * 0.5)
	_net_mesh.global_position = center_global
	_net_mesh.global_basis = _basis_y_points_to(y_dir, astern)

	_update_rope_mesh_between(payout_global, head_global)


func _update_rope_mesh_between(start_global: Vector3, end_global: Vector3) -> void:
	if _rope_mesh == null or not trawling:
		return

	var start := global_transform.affine_inverse() * start_global
	var end := global_transform.affine_inverse() * end_global
	var span := end - start
	var length := span.length()
	if length <= 0.05:
		_rope_mesh.visible = false
		return

	_rope_mesh.visible = true
	var dir := span / length
	var ref_up := Vector3.FORWARD if absf(dir.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var x_axis := dir.cross(ref_up).normalized()
	var z_axis := x_axis.cross(dir).normalized()
	_rope_mesh.basis = Basis(x_axis, dir, z_axis)
	_rope_mesh.scale = Vector3(1.0, length, 1.0)
	_rope_mesh.position = start + span * 0.5
