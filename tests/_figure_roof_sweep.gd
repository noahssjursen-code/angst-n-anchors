extends SceneTree

## SCRATCH PROBE (leading underscore, not gate-scored).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_figure_roof_sweep.gd
##
## THE ATTACK ON `FIGURE_REQUIRED_VIEWS`.
##
## The parent rig asserts the figure only in `profile_port` and `plan`, on the
## argument that those two see the whole deck BY CONSTRUCTION and the only way to
## hide from them is to be inside something. `plan` shoots from 88 degrees, so
## hiding from it means being ROOFED. `profile_port` shoots from -X at 3 degrees,
## so hiding from it means something to PORT standing between.
##
## A spot that is roofed AND port-blocked AND standing in open air on the
## starboard side is exactly the counter-example the argument denies exists: a
## person in an alleyway under a boat deck, invisible to both asserted views and
## perfectly visible from the starboard quarter. This sweeps every fixture's
## resolved colliders for one.
##
## Plan space, offset zero, same space as FIGURE_SPOT.
##
## ── WHAT IT FOUND, AND WHY THE ANSWER IS NO ─────────────────────────────────
##
## 25 candidates on `demo_workboat`, 24 on each trawler, 227 and 273 on the two
## catamarans, 1 on `probe_spar_kit`. Six were SHOT through
## `tests/_figure_spot_shot.gd` and every one of them is a figure INSIDE a
## deckhouse whose head shows through an open DOOR: `demo_workboat`'s `decks[]` 5
## is the house roof, not a canopy, and the catamaran's promenade candidates
## resolve to 7 x 6 px of scalp. A doorway is a hole in the collider set, so a
## sight line goes straight through it and this probe calls the spot visible; a
## person looking at the frame sees no scale reference at all.
##
## THE LESSON FOR ANYONE REUSING THIS: it is a CANDIDATE GENERATOR, not a verdict.
## It over-reports by exactly the amount that the collider set is not the
## rendered geometry — doors, windows, and anything the baker does not collide.
## Every hit has to be shot and looked at before it means anything.
##
## `probe_container_feeder` and the three `critic_*` plans were NOT swept: the
## feeder is 3084 boxes over a 32 x 150 m deck and did not finish in 20 minutes.

const FIXTURES := [
	"res://resources/data/structures/demo_workboat.json",
	"res://resources/data/structures/probe_trawler_bulwark.json",
	"res://resources/data/structures/probe_trawler_bow_bulwark.json",
	"res://resources/data/structures/probe_ferry_catamaran.json",
	"res://resources/data/structures/probe_ferry_catamaran_trim.json",
	"res://resources/data/structures/probe_spar_kit.json",
	"res://resources/data/structures/probe_container_feeder.json",
	"res://resources/data/structures/probe_sheer_bulwark.json",
	"res://resources/data/structures/probe_sheer_bulwark_flat.json",
	"res://resources/data/structures/probe_plate_deckhouse.json",
	"res://resources/data/structures/critic_ferry.json",
	"res://resources/data/structures/critic_yacht.json",
	"res://resources/data/structures/critic_barge.json",
]

const FIG_RADIUS := 0.30
const FIG_LOW := 0.10
const FIG_HIGH := 1.80
const STEP := 0.5

## The two asserted views, as unit directions from the subject toward the camera.
## Same maths as `_shoot`: dir = (cos(el)sin(az), sin(el), cos(el)cos(az)).
const PROFILE_AZ := 270.0
const PROFILE_EL := 3.0
const PLAN_AZ := 90.0
const PLAN_EL := 88.0

## How far a sight line has to travel before it is out of the vessel. Longer than
## the longest hull in the fleet.
const RAY_LENGTH := 400.0


func _init() -> void:
	for path in FIXTURES:
		_sweep(path)
	quit()


func _dir(az: float, el: float) -> Vector3:
	var a := deg_to_rad(az)
	var e := deg_to_rad(el)
	return Vector3(cos(e) * sin(a), sin(e), cos(e) * cos(a))


func _sweep(path: String) -> void:
	var stem := path.get_file().get_basename()
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
	var plan := StructurePlan.from_dict(doc)
	var loa := 0.0
	var beam := 0.0
	var hull: Dictionary = doc.get("hull", {}) as Dictionary
	loa = float(hull.get("loa_m", 0.0))
	beam = float(hull.get("beam_m", 0.0))
	if loa <= 0.0 and plan.hull_id != "":
		var grid := HullRegistry.make_grid(plan.hull_id)
		if grid != null:
			loa = grid.half_loa * 2.0
			beam = grid.half_beam * 2.0

	var boxes: Array[AABB] = []
	var yaws := PackedFloat32Array()
	var centres: Array[Vector3] = []
	var sizes: Array[Vector3] = []
	for row_variant in StructureBaker.entity_colliders(plan, Vector3.ZERO):
		for box_variant in (row_variant as Dictionary)["boxes"] as Array:
			var box := box_variant as Dictionary
			centres.append(box["center"] as Vector3)
			sizes.append(box["size"] as Vector3)
			yaws.append(float(box.get("yaw_deg", 0.0)))
			boxes.append(_bounds_of(box))

	print("\n=== %s  deck x 0..%.1f  z 0..%.1f  %d collider boxes"
		% [stem, beam, loa, boxes.size()])

	var hits := 0
	var roofed_clear := 0
	var x := STEP * 0.5
	while x < beam:
		var z := STEP * 0.5
		while z < loa:
			## THE STANDING SURFACES UNDER THIS POINT, in ONE pass over the
			## colliders. The first cut took the union of every collider top in the
			## plan as a level list and tested all of them at every point: 2118
			## boxes on the trawler is ~300 heights, and the sweep did not finish a
			## second fixture in six minutes of wall clock.
			var levels := {0.0: true}
			for b in boxes:
				if x < b.position.x or x > b.position.x + b.size.x:
					continue
				if z < b.position.z or z > b.position.z + b.size.z:
					continue
				var top: float = snappedf(b.position.y + b.size.y, 0.02)
				if top > 0.05 and top < 12.0:
					levels[top] = true
			var level_list := levels.keys()
			level_list.sort()
			for level_variant in level_list:
				var y := float(level_variant)
				var at := Vector3(x, y, z)
				if _blocked(centres, sizes, yaws, at):
					continue
				var roof := _roof(boxes, at)
				if roof < 0.0:
					continue
				roofed_clear += 1
				## Roofed AND clear. Now: can the two asserted views see it, by ray?
				var profile := _sees(centres, sizes, yaws, at, _dir(PROFILE_AZ, PROFILE_EL))
				var plan_view := _sees(centres, sizes, yaws, at, _dir(PLAN_AZ, PLAN_EL))
				var bow_q := _sees(centres, sizes, yaws, at, _dir(145.0, 16.0))
				var stern_q := _sees(centres, sizes, yaws, at, _dir(35.0, 16.0))
				if profile or plan_view:
					continue
				if not (bow_q or stern_q):
					continue
				hits += 1
				if hits <= 24:
					print("   COUNTER-EXAMPLE (%.2f, %.2f, %.2f)  roof y=%.2f  headroom=%.2f m"
						% [at.x, at.y, at.z, roof, roof - at.y]
						+ "  profile=HIDDEN plan=HIDDEN  bow_q=%s stern_q=%s"
						% ["SEES" if bow_q else "hidden", "SEES" if stern_q else "hidden"])
			z += STEP
		x += STEP
	print("   roofed+clear standing points: %d   counter-examples: %d" % [roofed_clear, hits])


## Sight lines from the figure toward the camera. Three heights — knee, chest and
## head — because "the camera can see the head" and "the camera can see the
## figure" are different claims and the second is the one a scale reference makes.
##
## EXACT slab intersection in each box's own yawed frame, NOT a marched ray: a
## 0.02 m glass pane or a 0.06 m mullion is thinner than any sane step, and a
## marcher that steps over one reports a wheelhouse as transparent.
func _sees(
	centres: Array[Vector3], sizes: Array[Vector3], yaws: PackedFloat32Array,
	at: Vector3, dir: Vector3
) -> bool:
	for height in [0.45, 1.20, 1.70]:
		var from := at + Vector3(0.0, float(height), 0.0)
		if not _occluded(centres, sizes, yaws, from, dir):
			return true
	return false


func _occluded(
	centres: Array[Vector3], sizes: Array[Vector3], yaws: PackedFloat32Array,
	from: Vector3, dir: Vector3
) -> bool:
	for i in centres.size():
		var c := centres[i]
		var s := sizes[i]
		var o := from - c
		var d := dir
		if not is_zero_approx(yaws[i]):
			var yaw := -deg_to_rad(yaws[i])
			o = o.rotated(Vector3.UP, yaw)
			d = d.rotated(Vector3.UP, yaw)
		var t_near := -INF
		var t_far := INF
		for axis in 3:
			var half: float = [s.x, s.y, s.z][axis] * 0.5
			var oa: float = [o.x, o.y, o.z][axis]
			var da: float = [d.x, d.y, d.z][axis]
			if absf(da) < 1.0e-9:
				if absf(oa) > half:
					t_near = INF
					break
				continue
			var t1 := (-half - oa) / da
			var t2 := (half - oa) / da
			if t1 > t2:
				var swap := t1
				t1 = t2
				t2 = swap
			t_near = maxf(t_near, t1)
			t_far = minf(t_far, t2)
		if t_near <= t_far and t_far > 0.001 and t_near < RAY_LENGTH:
			return true
	return false


## Point-in-collider, YAW CORRECT — the same test `_guarded` uses in the rig, and
## NOT the axis-aligned bounds `_figure_spot_pick` scores with. On a 45-degree
## breakwater the two disagree by metres.
func _inside(
	centres: Array[Vector3], sizes: Array[Vector3], yaws: PackedFloat32Array, p: Vector3
) -> bool:
	for i in centres.size():
		var c := centres[i]
		var s := sizes[i]
		if p.y < c.y - s.y * 0.5 or p.y > c.y + s.y * 0.5:
			continue
		var flat := Vector3(p.x - c.x, 0.0, p.z - c.z)
		if not is_zero_approx(yaws[i]):
			flat = flat.rotated(Vector3.UP, -deg_to_rad(yaws[i]))
		if absf(flat.x) <= s.x * 0.5 and absf(flat.z) <= s.z * 0.5:
			return true
	return false


## The figure's body against the colliders, yaw correct: samples the capsule axis
## rather than an AABB, so a diagonal wall is judged on its own plating and not on
## the 4 m square its bounds draw.
func _blocked(
	centres: Array[Vector3], sizes: Array[Vector3], yaws: PackedFloat32Array, at: Vector3
) -> bool:
	var y := FIG_LOW
	while y <= FIG_HIGH:
		for a in [Vector3.ZERO, Vector3(FIG_RADIUS, 0, 0), Vector3(-FIG_RADIUS, 0, 0),
				Vector3(0, 0, FIG_RADIUS), Vector3(0, 0, -FIG_RADIUS)]:
			if _inside(centres, sizes, yaws, at + Vector3(0.0, y, 0.0) + (a as Vector3)):
				return true
		y += 0.15
	return false


func _supported(boxes: Array[AABB], at: Vector3) -> bool:
	if is_zero_approx(at.y):
		return true
	for b in boxes:
		var top := b.position.y + b.size.y
		if absf(top - at.y) > 0.02:
			continue
		if at.x < b.position.x or at.x > b.position.x + b.size.x:
			continue
		if at.z < b.position.z or at.z > b.position.z + b.size.z:
			continue
		return true
	return false


## The lowest thing standing over the figure's head, or -1 for open sky.
func _roof(boxes: Array[AABB], at: Vector3) -> float:
	var best := 1e9
	for b in boxes:
		if b.position.y < at.y + FIG_HIGH:
			continue
		if at.x < b.position.x - FIG_RADIUS or at.x > b.position.x + b.size.x + FIG_RADIUS:
			continue
		if at.z < b.position.z - FIG_RADIUS or at.z > b.position.z + b.size.z + FIG_RADIUS:
			continue
		best = minf(best, b.position.y)
	return -1.0 if best > 1.0e8 else best


func _bounds_of(box: Dictionary) -> AABB:
	var centre := box["center"] as Vector3
	var size := box["size"] as Vector3
	var basis := Basis(Vector3.UP, deg_to_rad(float(box.get("yaw_deg", 0.0))))
	var out := AABB()
	for i in 8:
		var local := Vector3(
			size.x * (0.5 if (i & 1) else -0.5),
			size.y * (0.5 if (i & 2) else -0.5),
			size.z * (0.5 if (i & 4) else -0.5)
		)
		var world := centre + basis * local
		if i == 0:
			out = AABB(world, Vector3.ZERO)
		else:
			out = out.expand(world)
	return out
