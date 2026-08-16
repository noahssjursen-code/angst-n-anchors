extends Node3D

## SCRATCH PROBE — leading underscore, so the gate skips it in both lanes.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_walk_slab_over_water_probe.tscn
##
## IS THE PLAYER-FACING DECK A RECTANGLE ON A POINTED HULL?
##
## `grid_deck_outline_test` measures `BoatBody._walk_deck_box_size()` as
## `hull_size.x` by `hull_size.z` — a rectangle — while the drawn weather deck
## tapers. That is read off the source. This asks the PHYSICS SERVER instead:
## stand the hull up, let `_ensure_walk_deck` run, and cast a downward ray on the
## PLAYER mask at points over the bow that the drawn plate does not cover.
##
## `CaptureSubject.hold_still` is called before anything is measured — a
## BoatBody's LOD revokes `freeze` one second after it enters the tree, and a
## moving subject would move every one of these hit heights.

const CaptureSubject := preload("res://tests/support/capture_subject.gd")
const LAYER_BOAT_WALK := 4  ## BoatBody.LAYER_BOAT_WALK


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for hull_id in ["hull_28x10", "hull_150x32", "hull_45x16_cat"]:
		await _probe(hull_id)
	get_tree().quit(0)


func _probe(hull_id: String) -> void:
	var boat: Node3D = VesselSpawn.instantiate(hull_id, {}, "")
	add_child(boat)
	CaptureSubject.hold_still(boat)
	boat.position = Vector3.ZERO
	## The walk deck is built on a deferred call and enabled on the one after.
	for i in range(8):
		await get_tree().physics_frame

	var stations: HullStations = boat.get("hull_stations")
	var hull_size: Vector3 = boat.get("hull_size")
	var walk := boat.get_parent().get_node_or_null("WalkDeck")
	if walk == null:
		walk = boat.get_node_or_null("WalkDeck")
	print("\n  %s — hull_size %v, WalkDeck %s" % [
		hull_id, hull_size, "present" if walk != null else "MISSING",
	])
	if walk != null:
		for child in walk.get_children():
			var cs := child as CollisionShape3D
			if cs == null:
				continue
			var size := Vector3.ZERO
			if cs.shape is BoxShape3D:
				size = (cs.shape as BoxShape3D).size
			print("      %-22s size %v at %v  disabled=%s"
				% [cs.name, size, cs.position, cs.disabled])
		print("      collision_layer=%d (boat_walk=%d)" % [walk.collision_layer, LAYER_BOAT_WALK])

	var ring := _ring(boat)
	var deck_y := stations.deck_y
	var space := get_viewport().world_3d.direct_space_state
	print("      %-10s %-10s %-14s %-10s %s"
		% ["x", "z", "inside plate?", "ray hit y", "what it hit"])
	for spot in _spots(hull_id, hull_size):
		var from := Vector3(spot.x, deck_y + 3.0, spot.y)
		var to := Vector3(spot.x, deck_y - 3.0, spot.y)
		var query := PhysicsRayQueryParameters3D.create(from, to)
		## The mask a CharacterBody player is on.
		query.collision_mask = LAYER_BOAT_WALK
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		print("      %-10.3f %-10.3f %-14s %-10s %s" % [
			spot.x, spot.y,
			"yes" if _inside(ring, spot) else "NO — over water",
			("%.3f" % (hit["position"] as Vector3).y) if not hit.is_empty() else "(none)",
			str(hit.get("collider", "")) if not hit.is_empty() else "-",
		])
	remove_child(boat)
	boat.queue_free()
	await get_tree().process_frame


## Points along the bow: on the centreline (always over deck) and out at the
## quarter-beam and near the side, at three stations inside the bow taper.
func _spots(hull_id: String, hull_size: Vector3) -> Array[Vector2]:
	var half_beam := hull_size.x * 0.5
	var half_loa := hull_size.z * 0.5
	var out: Array[Vector2] = []
	for zf in [0.99, 0.95, 0.90, 0.0]:
		for xf in [0.0, 0.5, 0.95]:
			out.append(Vector2(half_beam * xf, -half_loa * zf))
	return out


func _ring(boat: Node) -> PackedVector2Array:
	var mi := boat.get_node_or_null("HullVisual/Deck") as MeshInstance3D
	if mi == null or not mi.has_meta("plate_args"):
		return PackedVector2Array()
	var args: Dictionary = mi.get_meta("plate_args")
	var raw: PackedVector2Array = args.get("ring", PackedVector2Array())
	var out := PackedVector2Array()
	for p in raw:
		out.append(p + Vector2(mi.position.x, mi.position.z))
	return out


func _inside(ring: PackedVector2Array, point: Vector2) -> bool:
	var n := ring.size()
	if n < 3:
		return false
	var area := 0.0
	for i in range(n):
		area += ring[i].x * ring[(i + 1) % n].y - ring[(i + 1) % n].x * ring[i].y
	var sign := 1.0 if area >= 0.0 else -1.0
	for i in range(n):
		var a := ring[i]
		var edge := ring[(i + 1) % n] - a
		if ((edge.x * (point.y - a.y) - edge.y * (point.x - a.x)) * sign) < -1e-6:
			return false
	return true
