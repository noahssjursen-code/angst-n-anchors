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

var _body: BoatBody = null
var _propulsion: PropulsionComponent = null
var _cargo_deck: CargoDeckComponent = null

var _trommel_winch: Node3D
var _drum_rotation_node: Node3D
var _net_mesh: MeshInstance3D
var _catch_timer: float = 0.0

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
		if child.name in ["TrommelWinch", "TrawlNet"]:
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
	
	position = Vector3(absf(stern_z) - 0.6 * scale, deck_y + 0.25 * scale, 0.0) # Sits in front of the stern (moved towards bow), raised up
	
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
 
	# 6. Procedural Trawl Net (trailing cone pointing backward)
	_net_mesh = MeshInstance3D.new()
	_net_mesh.name = "TrawlNet"
	var net_mesh := CylinderMesh.new()
	net_mesh.top_radius = 0.05
	net_mesh.bottom_radius = 0.8
	net_mesh.height = 7.0
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
	
	# Rotate to point backward (+X) and position behind the boat
	_net_mesh.rotation.z = PI * 0.5 - 0.12 # Tilted slightly downwards (by ~7 degrees) to dip into the water
	_net_mesh.position = Vector3(3.8 + 0.4 * scale, -1.15 * scale, 0.0) # Trailing behind, lowered to meet the waterline
	_add_child_with_owner(self, _net_mesh)


func _add_child_with_owner(parent_node: Node, child_node: Node) -> void:
	parent_node.add_child(child_node)
	if Engine.is_editor_hint():
		var scene_root := get_tree().edited_scene_root if is_inside_tree() else null
		if scene_root != null:
			child_node.owner = scene_root


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	if trawling:
		# Spin the drum to show winching activity
		if _drum_rotation_node != null:
			_drum_rotation_node.rotate_z(delta * trommel_rotation_speed)

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
				_catch_timer += delta
				if _catch_timer >= catch_interval_seconds:
					_catch_timer = 0.0
					_try_catch_fish()
	else:
		_catch_timer = 0.0


func _try_catch_fish() -> void:
	if _body == null:
		return
		
	# Find all cargo decks on the boat
	var decks := _body.find_children("*", "CargoDeckComponent", true, false)
	if decks.is_empty():
		return
		
	# Build the fish pallet
	var fish_pallet := Pallet.new()
	fish_pallet.id = UuidUtil.generate()
	fish_pallet.contract_id = ""
	fish_pallet.origin_port_id = ""
	fish_pallet.destination_port_id = ""
	fish_pallet.commodity = "fish"
	fish_pallet.display_name = "Fresh Fish"
	fish_pallet.units = 4
	fish_pallet.max_units = 4
	fish_pallet.footprint = Vector2i(2, 2)
	fish_pallet.mass_kg = 800.0
	fish_pallet.value_gold = 64
	
	# Try to add to any of the cargo decks
	var placed := false
	for deck_node in decks:
		var deck := deck_node as CargoDeckComponent
		var idx := deck.add_pallet(fish_pallet)
		if idx >= 0:
			placed = true
			break
			
	# Show toast notification
	var controller = _body.find_child("BoatController", true, false) as BoatController
	if controller != null:
		var hud = controller.get("_ship_hud")
		if hud != null and hud.has_method("show_toast"):
			if placed:
				hud.show_toast("Caught a crate of Fresh Fish!")
			else:
				hud.show_toast("Deck is FULL! No room for fish!")


func _update_trawl_visuals() -> void:
	if _net_mesh != null:
		_net_mesh.visible = trawling
