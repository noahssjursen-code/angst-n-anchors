extends Node3D

## SCRATCH PROBE — leading underscore, so the gate skips it in both lanes.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_walk_bow_sea_shot.tscn
##
## WHAT DOES IT LOOK LIKE WHEN A PLAYER WALKS PAST THE BOW?
##
## `_walk_bow_body_drive` establishes that a `CharacterBody3D` on the player's
## mask walks 3.323 m outboard of the drawn deck on `hull_28x10` and 10.695 m on
## `hull_150x32`, standing on `WalkDeckCollider` the whole way. This stands the
## same bare hull at its DESIGN WATERLINE over a sea plane, drives the same body
## to the same place, and photographs it, so the severity is LOOKED AT rather
## than read off a number (REALITY.md §1, §2).
##
## The figure is not placed — it is the collision capsule's own children, so the
## orange body in the frame is literally where the physics put it.
##
## ── IT SHOOTS BOTH STATES, AND THAT IS WHY THE "BEFORE" IS STILL LIVE ───────
##
## `boat_body.gd` now cuts both walk shapes from `plate_args.ring`, so the pose
## in `walk_bow__*` cannot be reached on a shipped hull any more. Rather than
## keep a frame this tree can no longer produce (CONVENTIONS §3), the rig puts
## the RECTANGLE back itself — explicitly, in `_force_rectangle`, as the shape
## that shipped until 2026-08-16 — photographs the defect, then restores the
## shipped shapes and photographs the same walk again. Both halves are
## reproducible from this tree, and the pair is the evidence.
##
## REPRODUCIBLE, deliberately: `CaptureClock.pin` fixes the game hour (a
## 24-real-minute day would otherwise relight the frame), `CaptureClock.settle`
## awaits `RenderingServer.frame_post_draw`, `CaptureSubject.hold_still` stops
## the LOD revoking the hull's freeze, and the march is hand-driven so no wall
## clock enters it.

const CaptureSubject := preload("res://tests/support/capture_subject.gd")
const CaptureClock := preload("res://tests/support/capture_clock.gd")
const OUT_DIR := "res://screenshots/studio"

const LAYER_WORLD := 1
const LAYER_BOAT_WALK := 4
const LAYER_PLAYER := 8

const CAPSULE_R := 0.35
const CAPSULE_H := 1.8
const WALK_SPEED := 4.5
const GRAVITY := 20.0
const STEP_DT := 1.0 / 60.0

## Ship-local x of the lane walked. 4.75 on the trawler is the quarter-beam
## station `_walk_slab_over_water_probe` rayed and `_walk_bow_body_drive`
## reached; it is inside the 5.0 m half-beam and outside the bow taper.
const LANE_X := 4.75

var _camera: Camera3D
var _stage: Node3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	CaptureClock.pin(get_tree())
	_hide_hud()

	_stage = Node3D.new()
	add_child(_stage)
	_light()
	_sea()

	var boat: Node3D = VesselSpawn.instantiate("hull_28x10", {}, "")
	_stage.add_child(boat)
	CaptureSubject.hold_still(boat)
	var stations: HullStations = boat.get("hull_stations")
	var draft: float = boat.get("draft_m")
	## Float it: the design waterline sits at world y = 0, so the sea plane in
	## this frame is where the sea would actually be.
	boat.position = Vector3(0.0, -(stations.keel_y + draft), 0.0)
	for i in range(10):
		await get_tree().physics_frame

	var walk := _walk_deck(boat)
	var slab_top := _slab_top(walk)
	print("  deck_y %.3f keel_y %.3f draft %.3f -> deck stands %.3f m above the sea"
		% [stations.deck_y, stations.keel_y, draft,
			stations.deck_y - (stations.keel_y + draft)])

	_camera = Camera3D.new()
	_camera.fov = 38.0
	_stage.add_child(_camera)

	_force_rectangle(walk, boat)
	await get_tree().physics_frame
	await _walk_and_shoot(boat, walk, slab_top, "walk_bow", "THE RECTANGLE THAT SHIPPED")

	_restore_shipped(boat)
	await get_tree().physics_frame
	await _walk_and_shoot(boat, walk, slab_top, "walk_bow_fixed", "THE SHIPPED SHAPE")

	print("BOW SEA SHOT DONE")
	get_tree().quit(0)


## Put the pre-2026-08-16 shapes back: `hull_size.x` by `hull_size.z` boxes on
## both walk colliders. Stated here rather than reached for, so the frame this
## produces is a labelled mutation and not a leftover.
##
## Nothing in this rig applies a plan, so no deferred `_ensure_walk_deck` runs
## to undo it — and the pose each pass PRINTS is the proof of which shape was in
## force: the rectangle carries the figure to z −13.950 with `WalkDeckCollider`
## under it, the shipped shape stops it at z −9.601 with nothing under its
## centre. A reader never has to take the label's word for it.
func _force_rectangle(walk: Node, boat: Node3D) -> void:
	var hull_size: Vector3 = boat.get("hull_size")
	var slab := walk.get_node_or_null("WalkDeckCollider") as CollisionShape3D
	var deck_box := BoxShape3D.new()
	deck_box.size = Vector3(hull_size.x, 0.14, hull_size.z)
	slab.shape = deck_box
	var hull_col := walk.get_node_or_null("WalkHullCollider") as CollisionShape3D
	if hull_col != null:
		var hull_box := BoxShape3D.new()
		hull_box.size = Vector3(hull_size.x, maxf(hull_size.y * 0.85, 0.5), hull_size.z)
		hull_col.shape = hull_box


func _restore_shipped(boat: Node3D) -> void:
	## The production path rebuilds both shapes from the ring.
	boat.call("_resize_walk_deck_shape")


func _walk_and_shoot(
	boat: Node3D, walk: Node, slab_top: float, stem: String, label: String
) -> void:
	print("\n  --- %s ---" % label)
	var body := _make_body()
	_stage.add_child(body)
	body.global_position = Vector3(LANE_X, slab_top + 0.60, 0.0)
	for i in range(240):
		_step(body, Vector3.ZERO)
		if body.is_on_floor() and absf(body.velocity.y) < 0.001:
			break
	print("  figure settled amidships at %v" % body.global_position.snappedf(0.001))
	## Walk it forward until it is one step short of the rectangle's forward
	## face — the last place it could still stand when the slab was a rectangle.
	## −13.950 is the furthest supported stance `_walk_bow_body_drive` measured
	## on this lane; the rectangle's forward face is at −14.000.
	var stop_z := -13.90
	## Both frames show THE FURTHEST THE FIGURE CAN STAND, which is the thing
	## being compared. Walking until it falls and grabbing whatever pose the
	## last step left would photograph a body mid-air on one side and a body on
	## the deck on the other, and those are not the same measurement.
	var last_supported := body.global_position
	for i in range(1200):
		if body.global_position.z <= stop_z:
			break
		if body.global_position.y < 0.5:
			break
		_step(body, Vector3(0.0, 0.0, -1.0))
		if body.is_on_floor():
			last_supported = body.global_position
	body.velocity = Vector3.ZERO
	body.global_position = last_supported
	for i in range(30):
		_step(body, Vector3.ZERO)
	var p := body.global_position
	print("  figure walked to %v · on_floor=%s · standing on %s"
		% [p.snappedf(0.001), str(body.is_on_floor()), _floor_under(body)])
	print("  the drawn deck at x=%.2f ends at z=%.3f; the figure is %.3f m FORWARD of it"
		% [LANE_X, -14.0 + LANE_X, (-14.0 + LANE_X) - p.z])
	print("  sea is at y=0; the figure's feet are at y=%.3f" % p.y)

	## Nothing may move between here and the grab.
	body.process_mode = Node.PROCESS_MODE_DISABLED
	boat.process_mode = Node.PROCESS_MODE_DISABLED

	var focus := Vector3(p.x, p.y + 0.9, p.z)
	## Three views, all with the camera ABOVE the sea plane so the water is in
	## frame. The sea is a single-sided `PlaneMesh`: an eye below y = 0 sees no
	## water at all, which is how the first pass produced a figure floating in
	## an empty sky. The poses are FIXED, not derived from where the figure
	## ended up, so the two states are photographed from the same place.
	await _shoot("%s__over_the_sea" % stem, Vector3(17.0, 12.5, -29.0), Vector3(1.5, 3.0, -12.0))
	await _shoot("%s__under_the_feet" % stem, Vector3(10.5, 1.4, -21.0),
		Vector3(LANE_X - 0.5, 3.01, -13.95))
	await _shoot("%s__plan" % stem, Vector3(2.0, 24.0, -10.5), Vector3(2.0, 3.0, -10.5))
	body.queue_free()
	boat.process_mode = Node.PROCESS_MODE_INHERIT
	await get_tree().physics_frame


func _step(body: CharacterBody3D, dir: Vector3) -> void:
	if not body.is_on_floor():
		body.velocity.y -= GRAVITY * STEP_DT
	elif body.velocity.y < 0.0:
		body.velocity.y = 0.0
	body.velocity.x = dir.x * WALK_SPEED
	body.velocity.z = dir.z * WALK_SPEED
	body.move_and_slide()


func _make_body() -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = "PlayerBody"
	body.collision_layer = LAYER_PLAYER
	body.collision_mask = LAYER_WORLD | LAYER_BOAT_WALK
	body.floor_snap_length = 0.35
	body.floor_stop_on_slope = true
	body.floor_max_angle = deg_to_rad(48.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = CAPSULE_R
	cap.height = CAPSULE_H
	cs.shape = cap
	cs.position = Vector3(0.0, CAPSULE_H * 0.5, 0.0)
	body.add_child(cs)

	## The same 1.8 m figure `vessel_render_capture._add_scale_figure` draws, but
	## parented to the COLLIDER, so the picture cannot disagree with the physics.
	var torso := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 1.5
	torso.mesh = capsule
	torso.position = Vector3(0.0, 0.75, 0.0)
	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(0.95, 0.55, 0.1)
	torso.material_override = suit
	body.add_child(torso)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.14
	head_mesh.height = 0.28
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.66, 0.0)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.70, 0.55)
	head.material_override = skin
	body.add_child(head)
	return body


func _walk_deck(boat: Node) -> Node:
	var parent := boat.get_parent()
	var walk: Node = null
	if parent != null:
		walk = parent.get_node_or_null("WalkDeck")
	if walk == null:
		walk = boat.get_node_or_null("WalkDeck")
	return walk


## The top of the walk slab, whatever shape it is carrying. Reading `.size.y`
## off a `BoxShape3D` cast returns 0.0 the moment the slab becomes convex, which
## silently drops the figure from the slab's mid-plane instead of above it.
func _slab_top(walk: Node) -> float:
	var cs := walk.get_node_or_null("WalkDeckCollider") as CollisionShape3D
	if cs == null:
		return 0.0
	var box := cs.shape as BoxShape3D
	if box != null:
		return cs.global_position.y + box.size.y * 0.5
	var convex := cs.shape as ConvexPolygonShape3D
	if convex != null:
		var top := -1e18
		for point in convex.points:
			top = maxf(top, point.y)
		return cs.global_position.y + top
	return cs.global_position.y


func _floor_under(body: CharacterBody3D) -> String:
	var space := get_viewport().world_3d.direct_space_state
	var from := body.global_position + Vector3.UP * 0.10
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.5)
	query.collision_mask = LAYER_WORLD | LAYER_BOAT_WALK
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return "(nothing)"
	var collider: Object = hit.get("collider")
	var shape_name := "?"
	if collider is CollisionObject3D:
		var owner_id := (collider as CollisionObject3D).shape_find_owner(int(hit.get("shape", 0)))
		var owner_node := (collider as CollisionObject3D).shape_owner_get_owner(owner_id)
		if owner_node != null:
			shape_name = str(owner_node.name)
	return "%s/%s at y %.3f" % [
		str(collider.name) if collider != null else "?", shape_name,
		(hit["position"] as Vector3).y,
	]


func _sea() -> void:
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(600.0, 600.0)
	sea.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.26, 0.34)
	mat.roughness = 0.25
	sea.material_override = mat
	sea.position = Vector3.ZERO
	_stage.add_child(sea)


func _light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 220.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.4
	_stage.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, -125.0, 0.0)
	fill.light_energy = 0.35
	_stage.add_child(fill)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.86, 0.90)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.85)
	env.ambient_light_energy = 0.85
	we.environment = env
	_stage.add_child(we)


func _shoot(stem: String, eye: Vector3, look: Vector3) -> void:
	_camera.position = eye
	_camera.look_at(look, Vector3.UP)
	_camera.current = true
	await CaptureClock.settle(get_tree(), 6)
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, stem]))
	print("  wrote %s/%s.png" % [OUT_DIR, stem])


func _hide_hud() -> void:
	for child in get_tree().root.get_children():
		if child == self:
			continue
		_hide_canvas(child)


func _hide_canvas(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
		return
	if node is CanvasItem:
		(node as CanvasItem).visible = false
		return
	for child in node.get_children():
		_hide_canvas(child)
