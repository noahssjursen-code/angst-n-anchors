class_name DockCargoRamp
extends Node3D

## Spawns / updates a static walk plank when `MooringComponent.is_moored` is true.
## Mooring proves the berth side; geometry is straight **abeam**: horizontal perpendicular
## to the hull (+ optional deck height), pier end sits on that ray (never on the bollard).

## Intended as a child of `DockFacilities`, sibling of `ShipSpawner`.
## Uses mooring gap midpoints (`MooringComponent.tied_gap_hint_world`) once lines are taut.

const LAYER_BOAT_WALK: int = 4

@export_group("Ends")
## Hull-side endpoint in boat `RigidBody3D` local space (`ShipGameplay` is usually identity).
@export var boat_attachment_local: Vector3 = Vector3(-2.72, 2.06, 0.0)
## Pier deck elevation (adjust to dock slab kit / berth-relative spawn).
@export var pier_walk_y: float = 0.08
## Along the abeam ray, reach at least this far toward the dock (m) so the foot sits on deck.
@export var min_along_abeam: float = 0.65
## Extra reach beyond the chosen dock hint so the foot overlaps pier deck slightly.
@export var dock_overlap_m: float = 0.35

@export_group("Plank")
@export_range(0.5, 4.5, 0.05) var ramp_width: float = 1.45
@export_range(0.06, 0.36, 0.01) var plank_thickness: float = 0.14

@export_group("Clamp")
## Hide if 3D ramp span shorter than this.
@export var min_span: float = 0.58
## Hide if span or along-abeam reach exceeds this.
@export var max_span: float = 32.0



var _ramp: StaticBody3D


func _ready() -> void:
	_ensure_ramp_body()
	_set_visible_ramp(false)


func _physics_process(_delta: float) -> void:
	var spawner := get_parent().get_node_or_null("ShipSpawner") as ShipSpawner
	if spawner == null:
		return

	var mooring := _mooring_component(spawner.current_ship as Node)
	if mooring == null or not mooring.is_moored:
		_set_visible_ramp(false)
		return

	var boat := mooring.get_boat_rigid_body()
	if boat == null:
		_set_visible_ramp(false)
		return

	var post_hint := mooring.tied_dock_anchors_average_world()
	var gap_hint := mooring.tied_gap_hint_world()
	var has_post_hint := post_hint.length_squared() >= 0.001
	var has_gap_hint := gap_hint.length_squared() >= 0.001
	if not has_post_hint and not has_gap_hint:
		_set_visible_ramp(false)
		return

	var hull_end := boat.to_global(boat_attachment_local)
	var hull_xz := Vector3(hull_end.x, 0.0, hull_end.z)

	var to_post_xz := Vector3.ZERO
	if has_post_hint:
		to_post_xz = post_hint - hull_end
		to_post_xz.y = 0.0
	var to_gap_xz := Vector3.ZERO
	if has_gap_hint:
		to_gap_xz = gap_hint - hull_end
		to_gap_xz.y = 0.0

	var side_probe := to_post_xz if has_post_hint else to_gap_xz
	if side_probe.length_squared() < 1e-5:
		_set_visible_ramp(false)
		return

	var fwd_flat := boat.global_transform.basis.z
	fwd_flat.y = 0.0
	if fwd_flat.length_squared() < 1e-8:
		fwd_flat = Vector3(0.0, 0.0, 1.0)
	fwd_flat = fwd_flat.normalized()
	var abeam := Vector3.UP.cross(fwd_flat).normalized()
	if abeam.dot(side_probe) < 0.0:
		abeam = -abeam

	var s := min_along_abeam
	if has_gap_hint:
		s = maxf(s, abeam.dot(to_gap_xz))
	if has_post_hint:
		s = maxf(s, abeam.dot(to_post_xz))
	s += dock_overlap_m
	if s > max_span:
		_set_visible_ramp(false)
		return

	var pier_end := Vector3(
		hull_xz.x + abeam.x * s,
		pier_walk_y + 0.02,
		hull_xz.z + abeam.z * s,
	)

	var delta := hull_end - pier_end
	var span := delta.length()
	if span < min_span or span > max_span:
		_set_visible_ramp(false)
		return

	var fwd := delta.normalized()
	var right_h := Vector3.UP.cross(delta)
	if right_h.length_squared() < 1e-8:
		right_h = Vector3.RIGHT.cross(fwd)
	right_h = right_h.normalized()
	var surf_normal := fwd.cross(right_h).normalized()
	var right_v := surf_normal.cross(fwd).normalized()
	surf_normal = fwd.cross(right_v).normalized()
	var ramp_basis := Basis(right_v, surf_normal, fwd)

	var plank := plank_thickness + 1e-4
	var mi := _ramp.get_node_or_null("PlankVisual") as MeshInstance3D
	var cs := _ramp.get_node_or_null("PlankCollider") as CollisionShape3D
	var box_mesh := mi.mesh as BoxMesh
	var box_shape := cs.shape as BoxShape3D
	if box_mesh != null:
		box_mesh.size = Vector3(ramp_width, plank, span)
	if box_shape != null and box_mesh != null:
		box_shape.size = box_mesh.size

	_ramp.global_transform = Transform3D(ramp_basis, (pier_end + hull_end) * 0.5)
	_set_visible_ramp(true)


func _ensure_ramp_body() -> void:
	_ramp = get_node_or_null("RampBody") as StaticBody3D
	if _ramp != null:
		return

	_ramp = StaticBody3D.new()
	_ramp.name = "RampBody"
	# Keep plank boardable, but prevent hull-vs-ramp rigid-body contact impulses.
	# Boat hull collides with WORLD (1); walk surfaces use BOAT_WALK (4).
	_ramp.collision_layer = LAYER_BOAT_WALK
	_ramp.collision_mask = 0
	add_child(_ramp)

	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(ramp_width, plank_thickness, 1.0)

	var mi := MeshInstance3D.new()
	mi.name = "PlankVisual"
	mi.mesh = box_mesh
	mi.material_override = MeshBuilder.make_material(Color(0.38, 0.33, 0.28), 0.76, 0.02)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	var cs := CollisionShape3D.new()
	cs.name = "PlankCollider"
	var bx := BoxShape3D.new()
	bx.size = box_mesh.size
	cs.shape = bx

	_ramp.add_child(mi)
	_ramp.add_child(cs)


func _set_visible_ramp(on: bool) -> void:
	if _ramp == null:
		return
	_ramp.visible = on
	var cs := _ramp.get_node_or_null("PlankCollider") as CollisionShape3D
	if cs != null:
		cs.disabled = not on


func _mooring_component(ship_root: Node) -> MooringComponent:
	if ship_root == null:
		return null
	var n := ship_root.find_child("MooringComponent", true, false)
	return n as MooringComponent
