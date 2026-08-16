extends Node

## Scratch probe: which way do `_extrude_plan_ring`'s two fans face, and what
## would it cost to turn them the right way up?
##
## Part 1 reads the committed mesh arrays back, so the answer comes from what
## Godot stored rather than from reasoning about winding order.
## `generate_normals()` assigns each triangle the normal consistent with its
## FRONT face, so a fan at the top of the plate whose stored normal points DOWN
## is a fan nothing above the deck can see.
##
## Part 2 prices the alternative. "Fix the winding" only helps if the callers'
## `deck_y + 0.1` compensation comes out with it; that puts the plate's SOLID
## band at [deck_y - 0.1, deck_y], and the lofted shell tops out at exactly
## deck_y. Part 2 counts how much shell that band swallows.


## Where the controlled render lands. Deliberately NOT under `screenshots/`: this
## is a measurement rig, not a shipped capture.
const SHOT_DIR := "user://ring_probe"


func _ready() -> void:
	_faces("fishing trawler 28x10", 28.0, 10.0, 0.28, 2.7)
	_shell_overlap()
	await _stand_on_the_deck()
	await _controlled_render()
	get_tree().quit(0)


## A DETERMINISTIC RENDER OF THE PLATE ALONE — added 2026-08-16.
##
## `tests/_starter_shot.gd` cannot answer "did the winding fix change what you
## see": re-run with ZERO code change it moved 5.386% of its pixels, 20.9% in
## `starter__on_deck` (REALITY §8 — suspect the instrument). It floats a hull,
## settles it under physics and shoots a whole vessel, and none of that repeats.
##
## This does not. One plate mesh, one fixed light, one fixed camera, no physics,
## no RNG, no other geometry — so any pixel that moves between two runs moved
## because the mesh did. A red reference slab sits at the plate's span BOTTOM and
## a green one at its span TOP, both 4 mm proud of their fan, so the frame says
## WHICH surface survived culling rather than just that something changed.
func _controlled_render() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 480)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.03, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.30, 0.34, 0.38)
	e.ambient_light_energy = 0.6
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -30.0, 0.0)
	sun.light_energy = 1.2
	vp.add_child(sun)
	var plate := MeshBuilder.pointed_deck_plate(28.0, 10.0, 2.8, 0.1, 0.28)
	vp.add_child(plate)
	## TWO MARKERS, AND THE FIRST IS THE WHOLE MEASUREMENT. The plate spans
	## [2.700, 2.800]. The MAGENTA slab is BURIED — it lies at 2.750, inside that
	## band — so depth testing answers the question outright:
	##
	##   visible surface is the fan at 2.700  ->  the slab is above it  -> MAGENTA SHOWS
	##   visible surface is the fan at 2.800  ->  the slab is below it  -> MAGENTA GONE
	##
	## The GREEN slab at 2.804 sits proud of both fans and can never be culled. It
	## is the control: a frame with no magenta and no green is a broken rig, not a
	## fixed winding (REALITY §8).
	for marker in [
		[2.750, Color(0.95, 0.05, 0.85), 6.0], [2.804, Color(0.1, 0.9, 0.1), 1.2]
	]:
		var bar := MeshBuilder.box(
			Vector3(marker[2] as float, 0.002, 22.0), marker[1] as Color, 0.9
		)
		bar.position = Vector3(0.0 if float(marker[2]) > 3.0 else 3.6, marker[0] as float, 0.0)
		vp.add_child(bar)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.look_at_from_position(Vector3(11.0, 9.0, 13.0), Vector3(0.0, 2.7, 0.0), Vector3.UP)
	vp.add_child(cam)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png("%s/ring__plate_quarter.png" % SHOT_DIR)
	## And straight down, which is the view a deckhand's camera takes.
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 32.0
	cam.look_at_from_position(Vector3(0.0, 20.0, 0.001), Vector3(0.0, 2.7, 0.0), Vector3.UP)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png("%s/ring__plate_plan.png" % SHOT_DIR)
	print("== controlled render ==")
	print("  wrote %s/ring__plate_{quarter,plan}.png" % ProjectSettings.globalize_path(SHOT_DIR))
	print("  plate mesh: %d triangles  AABB %v size %v" % [
		plate.mesh.get_faces().size() / 3,
		plate.mesh.get_aabb().position,
		plate.mesh.get_aabb().size,
	])


## What a capsule's feet find over BARE deck, against the plate surface a player
## can see. The hold has had this check since `bd548bc`; the deck itself never
## has.
func _stand_on_the_deck() -> void:
	var boat := HullRegistry.build_hull("fishing_trawler_small")
	if boat == null:
		print("== bare deck == could not build the trawler")
		return
	add_child(boat)
	await get_tree().process_frame
	await get_tree().process_frame
	var stations = boat.hull_stations
	var deck := boat.get_node_or_null("HullVisual/Deck") as MeshInstance3D
	print("== what a deckhand stands on over BARE deck ==")
	print("  stations.deck_y = %.4f" % stations.deck_y)
	if deck != null:
		var aabb := deck.mesh.get_aabb()
		print("  drawn plate span [%.4f, %.4f] (node y %.4f)" % [
			aabb.position.y, aabb.position.y + aabb.size.y, deck.position.y
		])
		## Read off the mesh rather than named: before 2026-08-16 the fans were
		## inside out and the surface you saw from above was the span BOTTOM.
		print("  VISIBLE plate surface from above = %.4f" % _visible_top(deck.mesh))
	var space := boat.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	var hits := 0
	var sum := 0.0
	for z in [-4.0, 0.0, 4.0, 8.0]:
		for x in [-2.0, 0.0, 2.0]:
			var from := boat.to_global(Vector3(x, stations.deck_y + 3.0, z))
			var params := PhysicsShapeQueryParameters3D.new()
			params.shape = shape
			params.transform = Transform3D(Basis.IDENTITY, from)
			params.collision_mask = 0xFFFFFFFF
			params.motion = Vector3(0.0, -6.0, 0.0)
			var motion := space.cast_motion(params)
			if motion.size() < 1 or is_equal_approx(float(motion[0]), 1.0):
				continue
			var rest := from + Vector3(0.0, -6.0, 0.0) * float(motion[0])
			var feet := boat.to_local(rest).y - 0.9
			hits += 1
			sum += feet
	if hits > 0:
		var visible: float = _visible_top(deck.mesh) if deck != null else float(stations.deck_y)
		print("  capsule feet over bare deck: %.4f (mean of %d stations)" % [sum / float(hits), hits])
		print("  gap above the VISIBLE plate surface: %.4f m" % (sum / float(hits) - visible))
	else:
		print("  no capsule found any support over the deck")
	remove_child(boat)
	boat.free()


func _faces(label: String, loa: float, beam: float, bow_frac: float, deck_y: float) -> void:
	var thickness := 0.1
	var mesh := MeshBuilder.pointed_deck_plate_mesh(loa, beam, deck_y + 0.1, thickness, bow_frac)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var y0 := deck_y
	var y1 := deck_y + thickness
	print("== %s ==" % label)
	print("  span [%.3f, %.3f]  tris %d  AABB %v size %v" % [
		y0, y1, verts.size() / 3, mesh.get_aabb().position, mesh.get_aabb().size
	])
	var stats := {}
	for i in range(0, verts.size(), 3):
		var a := verts[i]
		var b := verts[i + 1]
		var c := verts[i + 2]
		var level := "side"
		if is_equal_approx(a.y, y0) and is_equal_approx(b.y, y0) and is_equal_approx(c.y, y0):
			level = "fan at y0 (span BOTTOM)"
		elif is_equal_approx(a.y, y1) and is_equal_approx(b.y, y1) and is_equal_approx(c.y, y1):
			level = "fan at y1 (span TOP)   "
		var stored := norms[i]
		var key := "%s  stored normal %s  -> visible from %s" % [
			level,
			("+Y" if stored.y > 0.5 else ("-Y" if stored.y < -0.5 else "horizontal")),
			("ABOVE" if stored.y > 0.5 else ("BELOW" if stored.y < -0.5 else "the side")),
		]
		stats[key] = int(stats.get(key, 0)) + 1
	for key in stats:
		print("  %4d  %s" % [stats[key], key])
	print()


## What "fix the winding, take the compensation out" would actually do.
func _shell_overlap() -> void:
	var stations := FishingTrawlerSmall.make_physics_profile().make_stations()
	var mesh: ArrayMesh = MeshBuilder.lofted_hull_shell(stations).mesh
	var faces := mesh.get_faces()
	var max_y := -1e9
	for v in faces:
		max_y = maxf(max_y, v.y)
	var ring := MeshBuilder.pointed_plan_ring(
		FishingTrawlerSmall.LOA_M, FishingTrawlerSmall.BEAM_M, FishingTrawlerSmall.BOW_FRAC
	)
	print("== the price of turning the fans the right way up ==")
	print("  lofted shell tops out at y = %.4f (deck_y = %.4f)" % [max_y, stations.deck_y])
	print("  plate plan ring half-beam amidships: %.4f" % _ring_half_beam(ring, 0.0))
	## The plate's plan ring is CONSTANT with height. The shell is not. A plate
	## band pushed 0.1 m below the deck line keeps the deck-line ring at a height
	## where the shell has already tumbled inboard, so its rim stands outside the
	## hull. Measured as the shell's half-beam at three heights on one station.
	for probe_z in [-4.0, 0.0, 6.0]:
		var at_deck := _shell_half_beam(faces, probe_z, stations.deck_y, 0.02)
		var below := _shell_half_beam(faces, probe_z, stations.deck_y - 0.1, 0.02)
		var ring_half := _ring_half_beam(ring, probe_z)
		print(
			"  z=%+5.1f  ring %.4f | shell at deck_y %.4f | shell 0.1 m lower %.4f"
			% [probe_z, ring_half, at_deck, below]
			+ "  -> de-compensated rim stands %.4f m OUTSIDE the hull"
			% maxf(ring_half - below, 0.0)
		)


## Highest y whose triangle stores an UPWARD normal — the surface a camera above
## the deck actually sees, as opposed to the mesh's numeric top.
func _visible_top(mesh: Mesh) -> float:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var best := -1e9
	for i in range(verts.size()):
		if norms[i].y > 0.99:
			best = maxf(best, verts[i].y)
	return best


func _ring_half_beam(ring: PackedVector2Array, z: float) -> float:
	var best := 0.0
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		if is_equal_approx(a.y, b.y):
			continue
		var t := (z - a.y) / (b.y - a.y)
		if t < 0.0 or t > 1.0:
			continue
		best = maxf(best, absf(a.x + (b.x - a.x) * t))
	return best


## Widest half-beam the shell reaches at height `y` near station `z`, found by
## slicing every triangle edge with the plane rather than hunting for vertices
## that happen to sit on it — the loft has no vertex ring between deck_y and
## deck_y - 0.1, which is why a vertex count found nothing.
func _shell_half_beam(faces: PackedVector3Array, z: float, y: float, _tol: float) -> float:
	var best := 0.0
	for i in range(0, faces.size(), 3):
		for e in [[0, 1], [1, 2], [2, 0]]:
			var a := faces[i + int(e[0])]
			var b := faces[i + int(e[1])]
			if (a.y - y) * (b.y - y) > 0.0:
				continue
			if is_equal_approx(a.y, b.y):
				continue
			var t := (y - a.y) / (b.y - a.y)
			var p := a.lerp(b, t)
			if absf(p.z - z) <= 0.75:
				best = maxf(best, absf(p.x))
	return best


func _in_ring(ring: PackedVector2Array, x: float, z: float) -> bool:
	var n := ring.size()
	for i in range(n):
		var a := ring[i]
		var b := ring[(i + 1) % n]
		var e := b - a
		var p := Vector2(x, z) - a
		if e.x * p.y - e.y * p.x > 0.0001:
			return false
	return true
