@tool
class_name BoatBody
extends RigidBody3D

enum PhysicsQuality { FULL, MEDIUM, SLEEP }

## Root node of every boat. Owns physics properties.
## Visuals and collision are handled by the MeshTransformer child component.
##
## Hull collision lives on layer "boat_hull" so the CharacterBody player does not
## directly push the RigidBody (infinite-mass kinematic vs dynamic = huge impulses).
## A thin AnimatableBody3D "WalkDeck" on the boat_walk layer — flat box only, synced
## each physics step. No hull mesh concave collider (that shell scales with ultra hulls
## and was launching players on the quay when ships spawned).

const LAYER_WORLD:     int = 1
const LAYER_BOAT_HULL: int = 2
const LAYER_BOAT_WALK: int = 4
const LAYER_PLAYER:    int = 8
const MERGED_COLLIDER_NAME := "MergedBoatCollider"
const WALK_DECK_COLLIDER_NAME := "WalkDeckCollider"
const WALK_HULL_COLLIDER_NAME := "WalkHullCollider"
const BRICK_COL_PREFIX := "BrickCol_"

@export_group("Physics")
## Manual mass override (kg). Used when `auto_mass_from_hull = false`. Ignored otherwise.
## Prefer `displacement_t` (tonnes) for the new vessel contract.
@export var hull_mass:           float = 22000.0:
	set(v):
		hull_mass = v
		_refresh_mass()
## Baseline linear damping (air resistance). Water resistance is handled by HydrodynamicsComponent.
@export var linear_damp_coeff:   float = 0.05:
	set(v):
		linear_damp_coeff = v
		linear_damp = v
## Baseline angular damping.
@export var angular_damp_coeff:  float = 0.7:
	set(v):
		angular_damp_coeff = v
		angular_damp = v

@export_group("Vessel size (metres)")
## Length overall — bow face to stern face.
@export var length_m: float = 15.0:
	set(v):
		length_m = maxf(v, 1.0)
		_on_si_size_changed()
## Max beam — port face to starboard face.
@export var beam_m: float = 12.0:
	set(v):
		beam_m = maxf(v, 1.0)
		_on_si_size_changed()
## Design draft (metres submerged at displacement_t).
@export var draft_m: float = 1.5:
	set(v):
		draft_m = maxf(v, 0.1)
		_on_si_size_changed()
## Keel to deck height.
@export var depth_m: float = 3.0:
	set(v):
		depth_m = maxf(v, 0.5)
		_on_si_size_changed()
## Mass at design draft, in tonnes (1 t = 1000 kg). Drives RigidBody mass when set > 0.
@export var displacement_t: float = 120.0:
	set(v):
		displacement_t = maxf(v, 0.0)
		_refresh_mass()

@export_group("Hull faces")
## Which local axis points to each face of the footprint rectangle.
## Default matches propulsion: bow −Z (Godot forward), stern +Z, port −X, starboard +X.
enum FaceAxis { PLUS_X = 0, MINUS_X = 1, PLUS_Z = 2, MINUS_Z = 3 }
@export var bow_face: FaceAxis = FaceAxis.MINUS_Z
@export var stern_face: FaceAxis = FaceAxis.PLUS_Z
@export var port_face: FaceAxis = FaceAxis.MINUS_X
@export var starboard_face: FaceAxis = FaceAxis.PLUS_X

@export_group("Mass model")
## When true, mass comes from strip displacement or `displacement_t`. Prefer displacement_t.
@export var auto_mass_from_hull: bool = true:
	set(v):
		auto_mass_from_hull = v
		_refresh_mass()
## Targeted equilibrium draft (fraction of hull height) when deriving mass from stations only.
@export_range(0.05, 0.95, 0.01) var design_draft_fraction: float = 0.5:
	set(v):
		design_draft_fraction = clampf(v, 0.05, 0.95)
		_refresh_mass()
## Deprecated — always 1.0. Kept so old callers compile; do not use.
@export_range(1.0, 2.0, 0.01) var mass_scale: float = 1.0:
	set(v):
		mass_scale = 1.0
		_refresh_mass()

## Strip-theory hull data. Built from length/beam/depth for box vessels, or from JSON historically.
@export var hull_stations: HullStations:
	set(v):
		hull_stations = v
		_refresh_mass()

## Authoritative SI physics contract for hand-authored vessels.
@export var physics_profile: HullPhysicsProfile
## Serializable paint choices. Call apply_hull_livery() after changing values.
@export var hull_livery: Dictionary = {}

@export_group("Simulation LOD")
@export var automatic_physics_lod: bool = true
@export var medium_physics_distance_m: float = 350.0
@export var sleep_physics_distance_m: float = 1200.0
@export var physics_quality: PhysicsQuality = PhysicsQuality.FULL


func apply_hull_livery(livery: Dictionary = {}) -> void:
	hull_livery = HullLivery.to_dict(livery)
	HullLivery.apply_to_boat(self, hull_livery)

@export_group("Component masses (kg)")
## Engine + drivetrain (steel block, low and aft).
@export var engine_mass: float = 0.0:
	set(v):
		engine_mass = maxf(0.0, v)
		_refresh_mass()
## Permanent ballast / iron keel — adds mass; set `artificial_keel_extra_depth` to bias COM.
@export var keel_ballast_mass: float = 0.0:
	set(v):
		keel_ballast_mass = maxf(0.0, v)
		_refresh_mass()
## Fuel + freshwater + lubes + stores.
@export var fuel_stores_mass: float = 0.0:
	set(v):
		fuel_stores_mass = maxf(0.0, v)
		_refresh_mass()
## Cargo / payload (variable per voyage). Plays into mass; visual cargo lives in the model.
@export var cargo_mass: float = 0.0:
	set(v):
		cargo_mass = maxf(0.0, v)
		_refresh_mass()

@export_group("Fuel")
## Tank capacity in litres. Scales with hull size — defaults sized for a
## coastal trader. Templates can override per-vessel; a value > 0 here
## ensures any hull spawned cold-boot has a usable tank.
@export var fuel_capacity_l: float = 400.0:
	set(v):
		fuel_capacity_l = maxf(v, 1.0)
		fuel_l = minf(fuel_l, fuel_capacity_l)

## Current fuel level in litres for this spawned vessel instance.
@export var fuel_l: float = 400.0:
	set(v):
		var clamped := clampf(v, 0.0, fuel_capacity_l)
		var was_dry := fuel_l <= 0.0001
		fuel_l = clamped
		_refresh_mass()
		fuel_changed.emit(get_fuel_fraction())
		if not was_dry and fuel_l <= 0.0001:
			fuel_depleted.emit()

## Emitted when fuel level changes. Argument is current fraction (0..1).
signal fuel_changed(fraction: float)
## Emitted once when the tank crosses from non-empty to empty.
signal fuel_depleted


## Empirical cruise speed in m/s used to estimate range on the map's
## fuel-range ring. Doesn't drive physics — it's a UI hint that lines up
## with what a starter trader actually does at full throttle.
const CRUISE_SPEED_MS : float = 5.0


## How far the vessel can travel before running dry, at cruise speed and
## current fuel level. Returns metres. Returns 0 when there's no propulsion
## component so the ring stays hidden in that case.
func get_estimated_range_m() -> float:
	var prop := find_child("PropulsionComponent", true, false)
	if prop == null:
		return 0.0
	var burn := float(prop.get("fuel_burn_l_per_sec_full"))
	if burn <= 0.0:
		return 0.0
	return fuel_l / burn * CRUISE_SPEED_MS

@export_group("Stability (artificial keel)")
## Push the rigid-body center of mass below the mesh geometric center (ballast / keel).
## Vertical offset from `hull_center` = `hull_size.y * center_of_mass_depth_fraction`
## + `artificial_keel_extra_depth` (metres, along body −Y).
var _center_of_mass_depth_fraction: float = 0.4

@export_range(0.0, 1.5, 0.01) var center_of_mass_depth_fraction: float:
	get:
		return _center_of_mass_depth_fraction
	set(v):
		_center_of_mass_depth_fraction = clampf(v, 0.0, 2.0)
		_refresh_center_of_mass()

## Additional downward shift in metres (dense keel, fuel, engines) — same axis as depth fraction.
var _artificial_keel_extra_depth: float = 0.0

@export_range(0.0, 10.0, 0.01) var artificial_keel_extra_depth: float:
	get:
		return _artificial_keel_extra_depth
	set(v):
		_artificial_keel_extra_depth = maxf(0.0, v)
		_refresh_center_of_mass()

## Longitudinal trim ballast: metres from hull_center along LOA.
## Positive = toward stern (+Z), negative = toward bow (−Z).
## Use stern bias on pointed-bow hulls so CoM tracks the aft-shifted center of buoyancy.
var _center_of_mass_longitudinal_m: float = 0.0

@export_range(-40.0, 40.0, 0.05) var center_of_mass_longitudinal_m: float:
	get:
		return _center_of_mass_longitudinal_m
	set(v):
		_center_of_mass_longitudinal_m = clampf(v, -80.0, 80.0)
		_refresh_center_of_mass()

@export_group("Hull")
## Deprecated uniform mesh scale — always 1.0 (1 unit = 1 metre).
@export var mesh_scale: float = 1.0:
	set(v):
		mesh_scale = 1.0
		if _transformer:
			_transformer.set("absolute_scale", 1.0)
			_build_merged_collision()
		if _model_assembler:
			_model_assembler.set("absolute_scale", 1.0)
			_sync_hull_size_from_mesh()
			_build_merged_collision()

var hull_size: Vector3 = Vector3(12.0, 3.0, 15.0)
var hull_center: Vector3 = Vector3.ZERO

const DEFAULT_HULL_JSON := ""

@export_file("*.json") var model_data_path: String:
	set(v):
		model_data_path = v
		if _model_assembler:
			_model_assembler.set("model_data_path", v)
			_sync_hull_size_from_mesh()
			_build_merged_collision()

@export_file("*.json") var mesh_data_path: String = DEFAULT_HULL_JSON:
	set(v):
		mesh_data_path = v
		if _transformer:
			_transformer.set("mesh_data_path", v)
			_sync_hull_size_from_mesh()
			_build_merged_collision()

@export var mesh_rotation_degrees: Vector3 = Vector3(0.0, 0.0, 0.0):
	set(v):
		mesh_rotation_degrees = v
		if _transformer:
			_transformer.set("mesh_rotation_degrees", v)
			_sync_hull_size_from_mesh()
			_build_merged_collision()

@export_group("Berthing")
## Legacy toggle — berthing no longer shoves the hull seaward; see `dock_at_berth()`.
@export var berth_auto_fit_enabled: bool = true
@export_range(0.0, 3.0, 0.05) var berth_lateral_margin_m: float = 0.35

var _transformer: Node3D
var _model_assembler: ModelAssembler
var _walk_deck:   AnimatableBody3D

## Mooring positional solve runs here (inside Jolt/Godot integration), not via impulses.
var _mooring_integrate: Callable = Callable()
## id -> {mass_kg, position, category}. Bricks and pallets register here.
var _mass_entries: Dictionary = {}
var _mass_breakdown: Dictionary = {}
var _physics_lod_timer: float = 0.0
var _applied_physics_quality: int = -1

signal mass_properties_changed(total_mass_kg: float, local_center_of_mass: Vector3)


# ── Fuel API ─────────────────────────────────────────────────────────────────

## 0..1 fraction of capacity.
func get_fuel_fraction() -> float:
	if fuel_capacity_l <= 0.0:
		return 0.0
	return clampf(fuel_l / fuel_capacity_l, 0.0, 1.0)


## Deduct fuel; clamps to zero. Called by PropulsionComponent each tick.
func consume_fuel(litres: float) -> void:
	if litres <= 0.0:
		return
	fuel_l = maxf(fuel_l - litres, 0.0)


## Add fuel up to capacity. Used by FuelStation when refuelling at a pump.
## Returns the actual amount added (may be less than requested if the
## tank was already nearly full).
func add_fuel(litres: float) -> float:
	if litres <= 0.0:
		return 0.0
	var before := fuel_l
	fuel_l = minf(fuel_l + litres, fuel_capacity_l)
	return fuel_l - before


## Top up to full. Used by the shipwright on commission so a freshly-built
## ship is ready to sail.
func fill_tank() -> void:
	fuel_l = fuel_capacity_l


func mount_mooring_integrate(callback: Callable) -> void:
	_mooring_integrate = callback


func clear_mooring_integrate() -> void:
	_mooring_integrate = Callable()


func _ready() -> void:
	linear_damp  = linear_damp_coeff
	angular_damp = angular_damp_coeff

	# Hull vs world: player mask excludes boat_hull so CharacterBody does not shove the ship.
	collision_layer = LAYER_BOAT_HULL
	collision_mask  = LAYER_WORLD

	var pm := PhysicsMaterial.new()
	pm.bounce = 0.0
	physics_material_override = pm

	_ensure_model()
	_build_merged_collision()
	_refresh_mass()
	set_physics_quality(physics_quality)

	if not Engine.is_editor_hint():
		call_deferred("_ensure_walk_deck")
		var audio: Node = load("res://scripts/ship/boat_audio_system.gd").new()
		audio.name = "BoatAudio"
		add_child(audio)

		var lighting := ShipLighting.new()
		lighting.name = "ShipLighting"
		add_child(lighting)


func _exit_tree() -> void:
	PlayerVessel.unmark_player_ship(self)
	PlayerVessel.unregister_ship_from_docks(self)
	if _walk_deck != null and is_instance_valid(_walk_deck):
		_walk_deck.queue_free()
		_walk_deck = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and not Engine.is_editor_hint():
		# Fit-out may have built WalkDeck before we were in the tree — sync now.
		call_deferred("_sync_walk_deck_after_enter")


func _sync_walk_deck_after_enter() -> void:
	if not is_inside_tree():
		return
	if _walk_deck != null and is_instance_valid(_walk_deck):
		_ensure_walk_deck()
		_sync_walk_deck_transform()
		_enable_walk_deck_collision()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not Engine.is_editor_hint() and _mooring_integrate.is_valid():
		_mooring_integrate.call(state)

	if Engine.is_editor_hint():
		return
	if not is_inside_tree():
		return
	if _walk_deck == null or not is_instance_valid(_walk_deck) or not _walk_deck.is_inside_tree():
		return
	_sync_walk_deck_transform()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		var missing_single := _transformer == null or not is_instance_valid(_transformer)
		if _model_assembler == null and missing_single:
			_ensure_model()
		return

	if _walk_deck == null or not is_instance_valid(_walk_deck):
		_ensure_walk_deck()
	if automatic_physics_lod:
		_physics_lod_timer += _delta
		if _physics_lod_timer >= 1.0:
			_physics_lod_timer = 0.0
			_update_automatic_physics_quality()


func set_physics_quality(value: PhysicsQuality) -> void:
	if physics_quality == value and _applied_physics_quality == int(value):
		return
	physics_quality = value
	_applied_physics_quality = int(value)
	freeze = physics_quality == PhysicsQuality.SLEEP
	sleeping = physics_quality == PhysicsQuality.SLEEP
	for child_name in [
		"StripBuoyancyComponent",
		"HydrodynamicsComponent",
		"PropulsionComponent",
		"RudderComponent",
		"BowThrusterComponent",
	]:
		var component := get_node_or_null(child_name)
		if component != null:
			component.set_physics_process(physics_quality != PhysicsQuality.SLEEP)


func get_physics_station_stride() -> int:
	return 2 if physics_quality == PhysicsQuality.MEDIUM else 1


func get_physics_force_scale_for_tick() -> float:
	if physics_quality == PhysicsQuality.SLEEP:
		return 0.0
	if physics_quality == PhysicsQuality.MEDIUM:
		return 2.0 if Engine.get_physics_frames() % 2 == 0 else 0.0
	return 1.0


func get_physics_quality_name() -> String:
	return PhysicsQuality.keys()[physics_quality]


func _update_automatic_physics_quality() -> void:
	var peer_active := (
		multiplayer != null and multiplayer.multiplayer_peer != null
	)
	if peer_active and not is_multiplayer_authority():
		set_physics_quality(PhysicsQuality.SLEEP)
		return
	if is_in_group(PlayerVessel.GROUP):
		set_physics_quality(PhysicsQuality.FULL)
		return
	var nearest_distance := INF
	if get_tree() != null:
		for node in get_tree().get_nodes_in_group(PlayerVessel.GROUP):
			var relevant := node as Node3D
			if relevant != null and relevant != self:
				nearest_distance = minf(
					nearest_distance, global_position.distance_to(relevant.global_position)
				)
	if nearest_distance == INF or nearest_distance < medium_physics_distance_m:
		set_physics_quality(PhysicsQuality.FULL)
	elif nearest_distance < sleep_physics_distance_m:
		set_physics_quality(PhysicsQuality.MEDIUM)
	else:
		set_physics_quality(PhysicsQuality.SLEEP)


func _ensure_model() -> void:
	if not model_data_path.is_empty():
		_ensure_model_assembler()
	elif not mesh_data_path.is_empty():
		_ensure_transformer()


func _ensure_model_assembler() -> void:
	_clear_single_mesh_transformer()
	_model_assembler = get_node_or_null("ShipFrame/ModelAssembler") as ModelAssembler
	if _model_assembler == null:
		_model_assembler = get_node_or_null("ModelAssembler") as ModelAssembler
	if _model_assembler == null:
		_model_assembler = ModelAssembler.new()
		_model_assembler.name = "ModelAssembler"
		var visual_parent: Node = get_node_or_null("ShipFrame")
		if visual_parent == null:
			visual_parent = self
		visual_parent.add_child(_model_assembler)
		if Engine.is_editor_hint() and get_tree() != null:
			_model_assembler.owner = get_tree().edited_scene_root

	var parent := _model_assembler.get_parent()
	var collision_path := NodePath("../..") if parent != null and parent.name == "ShipFrame" else NodePath("..")
	_model_assembler.collision_parent_path = collision_path
	_model_assembler.build_part_colliders = false
	_model_assembler.absolute_scale = mesh_scale
	_model_assembler.model_data_path = model_data_path
	_sync_hull_size_from_mesh()
	_build_merged_collision()


func _ensure_transformer() -> void:
	_clear_model_assembler()
	_transformer = get_node_or_null("MeshTransformer")
	if _transformer == null:
		var transformer_script := load("res://scripts/core/mesh_transformer.gd")
		_transformer = Node3D.new()
		_transformer.set_script(transformer_script)
		_transformer.name = "MeshTransformer"
		add_child(_transformer)
		if Engine.is_editor_hint() and get_tree() != null:
			_transformer.owner = get_tree().edited_scene_root

	_transformer.set("mesh_data_path", mesh_data_path)
	_transformer.set("absolute_scale", mesh_scale)
	_transformer.set("mesh_color", Color(0.005, 0.005, 0.005))
	_transformer.set("mesh_rotation_degrees", mesh_rotation_degrees)
	_transformer.set("create_collision", false)
	_sync_hull_size_from_mesh()
	_build_merged_collision()


func refresh_hull_bounds_from_visuals() -> void:
	_sync_hull_size_from_mesh()


func _sync_hull_size_from_mesh() -> void:
	if _model_assembler != null and is_instance_valid(_model_assembler):
		var physics_part := _model_assembler.get_first_mesh_part_by_role("physics_body")
		if physics_part != null:
			_sync_hull_size_from_part(physics_part)
			return

	if _transformer and "actual_size" in _transformer:
		_sync_hull_size_from_part(_transformer)


func _sync_hull_size_from_part(part: Node) -> void:
	if not ("actual_size" in part):
		return
	var size: Vector3 = part.get("actual_size")
	if size.length_squared() <= 0.01:
		return

	var center: Vector3 = part.get("actual_center") if "actual_center" in part else Vector3.ZERO
	if _model_in_ship_frame():
		# Mesh bounds are in ShipFrame space (length on X); body space has length on Z.
		size = Vector3(size.z, size.y, size.x)
		center = center.rotated(Vector3.UP, deg_to_rad(-90.0))

	hull_size = size
	hull_center = center
	# _ready() runs before JSON bounds are known. Keep stability and mass tied to the
	# real mesh-derived hull dimensions, not the fallback default.
	_refresh_mass()
	_resize_walk_deck_shape()


func _model_in_ship_frame() -> bool:
	if _model_assembler == null or not is_instance_valid(_model_assembler):
		return false
	var parent := _model_assembler.get_parent()
	return parent != null and parent.name == "ShipFrame"


func _refresh_center_of_mass() -> void:
	if not is_node_ready():
		return
	if physics_profile != null:
		_refresh_profile_mass()
		return
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	var down: float = hull_size.y * _center_of_mass_depth_fraction + _artificial_keel_extra_depth
	## Bow −Z / stern +Z — longitudinal_m > 0 shifts CoM aft (stern ballast).
	center_of_mass = hull_center + Vector3(0.0, -down, _center_of_mass_longitudinal_m)


func _refresh_mass() -> void:
	if not is_node_ready():
		return
	if physics_profile != null:
		_refresh_profile_mass()
		return
	# displacement_t is design mass in tonnes (1 t = 1000 kg). Cargo adds on top.
	# Component mass exports are for CoM / tuning docs — not stacked on displacement_t.
	if displacement_t > 0.0:
		mass = maxf(displacement_t * 1000.0 + cargo_mass, 1.0)
	elif auto_mass_from_hull:
		var components: float = engine_mass + keel_ballast_mass + fuel_stores_mass + cargo_mass
		mass = maxf(_hull_displacement_kg() + components, 1.0)
	else:
		mass = maxf(hull_mass + engine_mass + keel_ballast_mass + fuel_stores_mass + cargo_mass, 1.0)
	_refresh_center_of_mass()


func set_mass_entry(
	entry_id: String,
	entry_mass_kg: float,
	local_position: Vector3,
	category: String = "equipment",
) -> void:
	if entry_id.is_empty():
		return
	var clamped_mass := maxf(entry_mass_kg, 0.0)
	if clamped_mass <= 0.0:
		_mass_entries.erase(entry_id)
	else:
		_mass_entries[entry_id] = {
			"mass_kg": clamped_mass,
			"position": local_position,
			"category": category,
		}
	if category == "cargo":
		cargo_mass = _entry_category_mass("cargo")
	else:
		_refresh_mass()


func remove_mass_entry(entry_id: String) -> void:
	if not _mass_entries.has(entry_id):
		return
	var category := str((_mass_entries[entry_id] as Dictionary).get("category", "equipment"))
	_mass_entries.erase(entry_id)
	if category == "cargo":
		cargo_mass = _entry_category_mass("cargo")
	else:
		_refresh_mass()


func clear_mass_entries(prefix: String = "") -> void:
	for key in _mass_entries.keys().duplicate():
		if prefix.is_empty() or str(key).begins_with(prefix):
			_mass_entries.erase(key)
	cargo_mass = _entry_category_mass("cargo")
	_refresh_mass()


func get_mass_breakdown() -> Dictionary:
	return _mass_breakdown.duplicate(true)


func get_world_center_of_mass() -> Vector3:
	return to_global(center_of_mass)


func _entry_category_mass(category: String) -> float:
	var total := 0.0
	for entry in _mass_entries.values():
		var data := entry as Dictionary
		if str(data.get("category", "")) == category:
			total += float(data.get("mass_kg", 0.0))
	return total


func _refresh_profile_mass() -> void:
	if physics_profile == null or not is_node_ready():
		return
	var profile := physics_profile
	var design_mass := profile.design_mass_kg()
	var engine := maxf(profile.engine_mass_kg, 0.0)
	var ballast := maxf(profile.ballast_mass_kg, 0.0)
	var full_stores := maxf(profile.full_stores_mass_kg, 0.0)
	var stores := full_stores * get_fuel_fraction()
	var hull := maxf(design_mass - engine - ballast - full_stores, 1000.0)

	var weighted := profile.hull_center_of_mass * hull
	weighted += profile.engine_position * engine
	weighted += profile.ballast_position * ballast
	weighted += profile.stores_position * stores
	var entries_total := 0.0
	var category_totals: Dictionary = {}
	for entry in _mass_entries.values():
		var data := entry as Dictionary
		var entry_mass := maxf(float(data.get("mass_kg", 0.0)), 0.0)
		var entry_position: Vector3 = data.get("position", Vector3.ZERO)
		var category := str(data.get("category", "equipment"))
		entries_total += entry_mass
		weighted += entry_position * entry_mass
		category_totals[category] = float(category_totals.get(category, 0.0)) + entry_mass

	# Compatibility for callers that still assign cargo_mass directly.
	var registered_cargo := float(category_totals.get("cargo", 0.0))
	var unregistered_cargo := maxf(cargo_mass - registered_cargo, 0.0)
	entries_total += unregistered_cargo
	weighted += Vector3(0.0, hull_size.y, 0.0) * unregistered_cargo

	var total := maxf(hull + engine + ballast + stores + entries_total, 1.0)
	mass = total
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = weighted / total

	# Approximate principal moments from configurable radii of gyration. Boat
	# body axes: X=pitch, Y=yaw, Z=roll.
	var pitch_radius := maxf(profile.length_m * profile.pitch_gyradius_fraction, 0.1)
	var yaw_radius := maxf(profile.length_m * profile.yaw_gyradius_fraction, 0.1)
	var roll_radius := maxf(profile.beam_m * profile.roll_gyradius_fraction, 0.1)
	inertia = Vector3(
		total * pitch_radius * pitch_radius,
		total * yaw_radius * yaw_radius,
		total * roll_radius * roll_radius
	)
	_mass_breakdown = {
		"total_kg": total,
		"hull_kg": hull,
		"engine_kg": engine,
		"ballast_kg": ballast,
		"stores_kg": stores,
		"entries_kg": entries_total,
		"categories": category_totals,
		"center_of_mass": center_of_mass,
		"inertia": inertia,
	}
	mass_properties_changed.emit(total, center_of_mass)


func _on_si_size_changed() -> void:
	hull_size = Vector3(beam_m, depth_m, length_m)
	hull_center = Vector3(0.0, depth_m * 0.5, 0.0)
	if design_draft_fraction > 0.0 and depth_m > 0.0:
		# Keep draft_m and design_draft_fraction loosely aligned for legacy callers.
		pass
	_refresh_mass()


## Local unit vector toward the bow face.
func get_bow_axis_local() -> Vector3:
	return _face_axis_vector(bow_face)


func get_stern_axis_local() -> Vector3:
	return _face_axis_vector(stern_face)


func get_port_axis_local() -> Vector3:
	return _face_axis_vector(port_face)


func get_starboard_axis_local() -> Vector3:
	return _face_axis_vector(starboard_face)


func _face_axis_vector(face: FaceAxis) -> Vector3:
	match face:
		FaceAxis.PLUS_X:
			return Vector3(1.0, 0.0, 0.0)
		FaceAxis.MINUS_X:
			return Vector3(-1.0, 0.0, 0.0)
		FaceAxis.PLUS_Z:
			return Vector3(0.0, 0.0, 1.0)
		FaceAxis.MINUS_Z:
			return Vector3(0.0, 0.0, -1.0)
	return Vector3(0.0, 0.0, -1.0)


func get_displacement_tonnes() -> float:
	if displacement_t > 0.0:
		return displacement_t
	return mass / 1000.0


## Hull-share mass: the steel of the hull itself. Calibrated so that hull_share +
## *empty* components (engine, ballast, fuel) equals displacement at design draft —
## i.e. an empty ship sits exactly at design draft. Cargo is NOT subtracted, so
## loading cargo sinks the ship deeper (which is what we want).
##
## Uses strip-theory volume integration when hull_stations is available, otherwise
## falls back to the old bbox × block_coefficient approximation.
func _hull_displacement_kg() -> float:
	var rho: float = _buoyancy_field("water_density", 1025.0)
	if hull_stations != null and not hull_stations.stations.is_empty():
		var vol_m3: float = _submerged_volume_m3(design_draft_fraction)
		# Empty-ship components: engine + ballast + fuel. Cargo deliberately excluded
		# so it adds extra mass that pushes the ship below design draft when loaded.
		var empty_components: float = engine_mass + keel_ballast_mass + fuel_stores_mass
		return maxf(vol_m3 * rho - empty_components, 1000.0)
	# Legacy fallback (no stations available).
	var draft: float = maxf(hull_size.y * design_draft_fraction, 0.0)
	var area: float = maxf(hull_size.x * hull_size.z, 0.0)
	var coeff: float = _buoyancy_field("block_coefficient", 0.7)
	return area * draft * coeff * rho


func _buoyancy_field(field: String, fallback: float) -> float:
	var b: Node = get_node_or_null("StripBuoyancyComponent")
	if b == null:
		b = get_node_or_null("BuoyancyComponent")  # backward-compat with old scenes
	if b != null and field in b:
		return float(b.get(field))
	return fallback


func get_total_mass_kg() -> float:
	return mass


func get_hull_displacement_kg() -> float:
	return _hull_displacement_kg()


func get_cargo_pads() -> Array[CargoSlotPadComponent]:
	var out: Array[CargoSlotPadComponent] = []
	_collect_cargo_pads(self, out)
	return out


func _collect_cargo_pads(n: Node, out: Array[CargoSlotPadComponent]) -> void:
	if n is CargoSlotPadComponent:
		out.append(n as CargoSlotPadComponent)
	for c in n.get_children():
		_collect_cargo_pads(c, out)


func get_bulk_holds() -> Array[BulkHoldComponent]:
	return BulkHoldComponent.get_all_for_ship(self)


func get_bulk_hold_states() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for hold in get_bulk_holds():
		out.append(hold.get_state().to_dict())
	return out


func get_moored_berth_id() -> String:
	return str(get_meta("harbour_berth_id", ""))


func get_harbour_port_id() -> String:
	return str(get_meta("harbour_port_id", ""))


func get_moored_berth() -> Node:
	var port_id := get_harbour_port_id()
	if port_id.is_empty():
		return null
	var hc = HarbourRegistry.controller(port_id)
	if hc == null:
		return null
	return hc.ship_berth(self)


func get_fishing_systems() -> Array[FishingSystem]:
	## Live FishingSystem nodes mounted by DeckFitout for accepted fishing slots.
	var out: Array[FishingSystem] = []
	for n in find_children("*", "FishingSystem", true, false):
		var fishing := n as FishingSystem
		if fishing != null:
			out.append(fishing)
	return out


func get_bridge_stations() -> Array[BridgeInteractable]:
	## Live helm interactables mounted for accepted helm slots.
	var out: Array[BridgeInteractable] = []
	for n in find_children("*", "BridgeInteractable", true, false):
		var station := n as BridgeInteractable
		if station != null:
			out.append(station)
	return out


## Position the ship so that the keel is `total_height × draft_fraction` below water_y.
## `draft_fraction = -1` (default) means "use this ship's own design_draft_fraction" so
## the spawn sits at the buoyancy equilibrium and the ship doesn't drift down at start.
## Teleport hull to a berth (or spawn) pose; clears velocity so mooring/physics do not fight the move.
func snap_to_transform(xform: Transform3D) -> void:
	freeze = true
	global_transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = false
	sleeping = false


func place_at_waterline(water_y: float, draft_fraction: float = -1.0) -> void:
	_ensure_model()
	_sync_hull_size_from_mesh()
	# Spawn against the current macro surface when the caller requests nominal
	# sea level. Before the first async snapshot, flat water is deterministic.
	if is_equal_approx(water_y, WaveSurface.WATER_LEVEL):
		var water := WaveSurface.sample_at(global_position.x, global_position.z)
		if water.valid and not water.stale:
			water_y = water.height
	if draft_fraction < 0.0:
		draft_fraction = floating_draft_fraction()
	# Prefer strip-theory height (includes keel) when available, else hull_size.y
	# (which is just the physics_body part's height, missing the keel_lower run).
	var total_height: float
	var keel_local_y: float
	if hull_stations != null and hull_stations.height_m > 0.0:
		total_height = hull_stations.height_m
		keel_local_y = hull_stations.keel_y
	elif depth_m > 0.0:
		total_height = depth_m
		keel_local_y = 0.0
	else:
		total_height = hull_size.y
		keel_local_y = hull_center.y - hull_size.y * 0.5
	var draft := total_height * clampf(draft_fraction, 0.0, 1.0)
	global_position.y = water_y - draft - keel_local_y
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## Draft fraction for spawn / berth placement. Auto-mass ships with `mass_scale` > 1 are
## heavier than Archimedes at `design_draft_fraction`, so spawning at design draft leaves
## them under-buoyant until they settle — looks like they sink deep on load.
func floating_draft_fraction() -> float:
	if auto_mass_from_hull and hull_stations != null and not hull_stations.stations.is_empty():
		return _equilibrium_draft_fraction()
	return design_draft_fraction


func _submerged_volume_m3(draft_fraction: float) -> float:
	if hull_stations == null or hull_stations.stations.is_empty():
		return 0.0
	var wl: float = hull_stations.keel_y + hull_stations.height_m * clampf(draft_fraction, 0.0, 1.0)
	var vol_m3: float = 0.0
	for i in range(hull_stations.stations.size()):
		var half_area: float = hull_stations.half_section_area_below(i, wl)
		vol_m3 += half_area * 2.0 * hull_stations.station_length(i)
	return vol_m3


func _equilibrium_draft_fraction() -> float:
	var rho: float = _buoyancy_field("water_density", 1025.0)
	var target_mass: float = maxf(mass, 1.0)
	var lo: float = 0.05
	var hi: float = 0.98
	for _attempt in range(20):
		var mid: float = (lo + hi) * 0.5
		var buoy_mass: float = _submerged_volume_m3(mid) * rho
		if buoy_mass < target_mass:
			lo = mid
		else:
			hi = mid
	return clampf((lo + hi) * 0.5, 0.05, 0.98)


## Place alongside a quay face: correct heading, offset from quay, waterline.
func dock_at_berth(dock: Node3D, _berth_index: int = 0) -> void:
	if dock == null:
		return
	refresh_hull_bounds_from_visuals()
	var half_beam := get_half_beam_m()
	var xform: Transform3D
	if dock is QuayBerthSlot:
		var slot := dock as QuayBerthSlot
		xform = slot.global_transform * slot.ship_dock_local(half_beam)
	else:
		var local := Vector3(0.0, 0.0, -(half_beam + 1.5))
		## Legacy PortDock faces: offset −Z, bow along +X.
		xform = dock.global_transform * Transform3D(
			Basis.from_euler(Vector3(0.0, PI * 0.5, 0.0)),
			local,
		)
	snap_to_transform(xform)
	place_at_waterline(WaveSurface.WATER_LEVEL)


## Compatibility alias — continuous vessel calls are deferred.
func dock_at_call(dock: Node3D, _call: Variant = null) -> void:
	dock_at_berth(dock, 0)


func get_half_beam_m() -> float:
	return _effective_half_beam_m()


## Deprecated — kept so old call sites do nothing harmful.
func fit_to_port_berth(dock: Node3D, berth_index: int) -> void:
	if not berth_auto_fit_enabled:
		return
	dock_at_berth(dock, berth_index)


func _effective_half_beam_m() -> float:
	if beam_m > 0.01:
		return beam_m * 0.5
	if hull_stations != null and hull_stations.beam_m > 0.01:
		return hull_stations.beam_m * 0.5
	return hull_size.x * 0.5


func _clear_single_mesh_transformer() -> void:
	if _transformer != null and is_instance_valid(_transformer):
		_transformer.queue_free()
		_transformer = null
	for child in get_children():
		if child.name.begins_with("Generated_MeshTransformer_"):
			child.queue_free()


func _clear_model_assembler() -> void:
	if _model_assembler != null and is_instance_valid(_model_assembler):
		_model_assembler.queue_free()
		_model_assembler = null
	for child in get_children():
		if child.name.begins_with("Generated_ModelPart_"):
			child.queue_free()


func _ensure_walk_deck() -> void:
	if Engine.is_editor_hint():
		return
	if _walk_deck == null or not is_instance_valid(_walk_deck):
		_walk_deck = AnimatableBody3D.new()
		_walk_deck.name = "WalkDeck"
		_walk_deck.sync_to_physics = false
		_walk_deck.collision_layer = LAYER_BOAT_WALK
		_walk_deck.collision_mask  = LAYER_PLAYER

		var cs := CollisionShape3D.new()
		cs.name = WALK_DECK_COLLIDER_NAME
		var box := BoxShape3D.new()
		box.size = _walk_deck_box_size()
		cs.shape = box
		cs.disabled = true
		_walk_deck.add_child(cs)

	# Prefer a sibling under the same parent so walk/brick colliders stay off the RigidBody.
	var parent_node := get_parent()
	var walk_parent := _walk_deck.get_parent()
	if walk_parent == null:
		if parent_node != null:
			_defer_walk_deck_attachment(parent_node)
		else:
			add_child(_walk_deck)
	elif parent_node != null and walk_parent == self:
		_defer_walk_deck_attachment(parent_node)

	_walk_deck.set_meta("_boat_owner", self)
	_ensure_walk_hull_collider()
	_sync_walk_deck_transform()
	call_deferred("_enable_walk_deck_collision")


func _defer_walk_deck_attachment(target_parent: Node) -> void:
	if _walk_deck.get_meta("_attachment_pending", false):
		return
	_walk_deck.set_meta("_attachment_pending", true)
	call_deferred("_attach_walk_deck_deferred", target_parent)


func _attach_walk_deck_deferred(target_parent: Node) -> void:
	if _walk_deck == null or not is_instance_valid(_walk_deck):
		return
	_walk_deck.set_meta("_attachment_pending", false)
	if target_parent == null or not is_instance_valid(target_parent):
		return
	var current_parent := _walk_deck.get_parent()
	if current_parent == target_parent:
		return
	if current_parent == null:
		target_parent.add_child(_walk_deck)
	elif current_parent == self:
		_walk_deck.reparent(target_parent, true)


func _walk_deck_box_size() -> Vector3:
	## Full hull footprint — no inset rim (avoids gray hull ledge you can fall through).
	return Vector3(hull_size.x, 0.14, hull_size.z)


func _walk_deck_local_origin() -> Vector3:
	# Prefer the brick-grid deck plane when this hull exposes one.
	if has_method("_deck_y"):
		return Vector3(0.0, float(call("_deck_y")) + 0.04, 0.0)
	# Slightly above geometric deck so the slab clears the hull collider visually.
	return hull_center + Vector3(0.0, hull_size.y * 0.5 + 0.08, 0.0)


func _walk_hull_box_size() -> Vector3:
	## Matches the gray hull shell (full beam/loa, 85% depth).
	return Vector3(hull_size.x, maxf(hull_size.y * 0.85, 0.5), hull_size.z)


func _walk_hull_boat_local_center() -> Vector3:
	var sz := _walk_hull_box_size()
	return Vector3(0.0, sz.y * 0.5, 0.0)


func _ensure_walk_hull_collider() -> void:
	## Player-facing hull volume on boat_walk — RigidBody hull stays on boat_hull.
	if _walk_deck == null or not is_instance_valid(_walk_deck):
		return
	var cs := _walk_deck.get_node_or_null(WALK_HULL_COLLIDER_NAME) as CollisionShape3D
	if cs == null:
		cs = CollisionShape3D.new()
		cs.name = WALK_HULL_COLLIDER_NAME
		_walk_deck.add_child(cs)
	var box := cs.shape as BoxShape3D
	if box == null:
		box = BoxShape3D.new()
		cs.shape = box
	box.size = _walk_hull_box_size()
	cs.position = boat_to_walk_deck_local(_walk_hull_boat_local_center())
	cs.rotation = Vector3.ZERO
	cs.disabled = false


## Attach a brick CollisionShape3D as a *direct* child of WalkDeck (Godot ignores nested shapes).
func add_walk_brick_collider(
	name_suffix: String,
	boat_local_center: Vector3,
	size: Vector3,
	yaw_deg: float,
) -> CollisionShape3D:
	var walk := ensure_walk_deck()
	if walk == null:
		return null
	var cs := CollisionShape3D.new()
	cs.name = "%s%s" % [BRICK_COL_PREFIX, name_suffix]
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = boat_to_walk_deck_local(boat_local_center)
	cs.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	walk.add_child(cs)
	return cs


func add_walk_brick_convex_collider(
	name_suffix: String,
	boat_local_center: Vector3,
	points: PackedVector3Array,
	yaw_deg: float,
) -> CollisionShape3D:
	var walk := ensure_walk_deck()
	if walk == null or points.size() < 4:
		return null
	var cs := CollisionShape3D.new()
	cs.name = "%s%s" % [BRICK_COL_PREFIX, name_suffix]
	var convex := ConvexPolygonShape3D.new()
	convex.points = points
	cs.shape = convex
	cs.position = boat_to_walk_deck_local(boat_local_center)
	cs.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	walk.add_child(cs)
	return cs


func clear_walk_brick_colliders() -> void:
	var walk := get_walk_deck()
	if walk == null:
		return
	var to_free: Array[Node] = []
	for child in walk.get_children():
		if child is CollisionShape3D and str(child.name).begins_with(BRICK_COL_PREFIX):
			to_free.append(child)
	for child in to_free:
		walk.remove_child(child)
		child.free()


func _sync_walk_deck_transform() -> void:
	if _walk_deck == null or not is_instance_valid(_walk_deck):
		return
	# global_transform errors loudly when either node is outside the tree
	# (fit-out / spawn often builds the WalkDeck before the boat is added).
	if not is_inside_tree() or not _walk_deck.is_inside_tree():
		return
	_walk_deck.global_transform = global_transform * Transform3D(Basis(), _walk_deck_local_origin())


func _enable_walk_deck_collision() -> void:
	if _walk_deck == null or not is_instance_valid(_walk_deck):
		return
	if not is_inside_tree() or not _walk_deck.is_inside_tree():
		return
	_sync_walk_deck_transform()
	_ensure_walk_hull_collider()
	var cs := _walk_deck.get_node_or_null(WALK_DECK_COLLIDER_NAME) as CollisionShape3D
	if cs != null:
		cs.disabled = false


func _resize_walk_deck_shape() -> void:
	if _walk_deck == null or not is_instance_valid(_walk_deck):
		return
	var cs := _walk_deck.get_node_or_null(WALK_DECK_COLLIDER_NAME) as CollisionShape3D
	if cs != null and cs.shape is BoxShape3D:
		(cs.shape as BoxShape3D).size = _walk_deck_box_size()
	_ensure_walk_hull_collider()
	_sync_walk_deck_transform()


## Ensure WalkDeck exists (player stands / brick colliders live here).
func ensure_walk_deck() -> AnimatableBody3D:
	_ensure_walk_deck()
	return _walk_deck


func get_walk_deck() -> AnimatableBody3D:
	return _walk_deck


## Convert a point in boat-local space into WalkDeck-local space.
func boat_to_walk_deck_local(boat_local: Vector3) -> Vector3:
	return boat_local - _walk_deck_local_origin()


func _build_merged_collision() -> void:
	_clear_merged_collision()

	var points := _merged_collision_points()
	if points.size() < 4:
		return

	var shape := ConvexPolygonShape3D.new()
	shape.points = points

	var collision := CollisionShape3D.new()
	collision.name = MERGED_COLLIDER_NAME
	collision.shape = shape
	add_child(collision)
	if Engine.is_editor_hint() and get_tree() != null:
		collision.owner = get_tree().edited_scene_root


func _merged_collision_points() -> Array[Vector3]:
	if _model_assembler != null and is_instance_valid(_model_assembler):
		return _model_assembler.get_collision_points_in(self)
	if _transformer != null and is_instance_valid(_transformer):
		if _transformer.has_method("get_collision_points_in"):
			return _transformer.call("get_collision_points_in", self)
	return []


func _clear_merged_collision() -> void:
	for child in get_children():
		if child.name == MERGED_COLLIDER_NAME:
			remove_child(child)
			child.free()
		elif child is CollisionShape3D and child.name.begins_with("Generated_ModelPart_"):
			remove_child(child)
			child.free()
		elif child is CollisionShape3D and child.name.begins_with("Generated_MeshTransformer_"):
			remove_child(child)
			child.free()
