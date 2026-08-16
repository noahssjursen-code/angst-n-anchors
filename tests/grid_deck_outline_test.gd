extends Node

## EVERY CELL THE GRID OFFERS A BUILDER IS OVER DECK THAT EXISTS.
##
## `HullRegistry.make_grid` produces `DeckGrid` — the cells a player is offered
## to build on in Structure Studio. It is one of several statements a hull makes
## about its own planform, and until this file existed nothing compared them.
## Where the grid runs past the deck, the builder is handed cells over open
## water and a wall placed there stands on nothing.
##
## ── WHERE THE OUTLINE COMES FROM, AND WHY NOT FROM `make_grid` ──────────────
##
## The trap in this check is that a hull publishes FOUR planforms and three of
## them are downstream of the same rule, so a check can compare a number with a
## copy of itself and never fail. Measured on the fleet, 2026-08-16:
##
##   grid        `make_grid` — cells, with a 45 degree bow chamfer of
##               `bow_taper_m` = half the beam (0 on the catamaran).
##   plate       the WEATHER DECK the hull DRAWS: the polygon in the
##               `plate_args.ring` meta on `HullVisual/Deck`, which is literally
##               the array `MeshBuilder.plan_plate_mesh` extrudes. **This is
##               what this file asks.**
##   loft        `hull_stations` — see the note at the foot of this file. On the
##               catamaran it is an AGGREGATE hydrostatic lattice and describes
##               no surface the vessel draws, so it is not the authority here.
##   walk slab   `BoatBody._walk_deck_box_size()` — `hull_size.x` by
##               `hull_size.z`, a RECTANGLE on every hull. Also not the
##               authority: it is looser than the plate on every pointed hull.
##
## The plate is the right one of the four because it is the surface the player
## sees, the one the studio draws its grid lines on top of, and the one a piece
## is actually standing on. It is also not a restatement of the grid: the ring
## stored in the meta is the exact array `plan_plate_mesh` extrudes, so this
## file reads the drawn mesh's own polygon rather than re-deriving one.
##
## ⚠ AND IT IS NOT FULLY INDEPENDENT OF THE GRID, SO DO NOT READ IT AS MORE.
## On the seven catalogue hulls both sides descend from the same sentence —
## "taper = half the beam" — through two different functions:
## `CatalogHullVessel.make_grid` computes `beam_m * 0.5` itself, while the plate
## is fed `profile.bow_taper_fraction`, which `make_physics_profile` computes as
## `beam_m * 0.5 / loa_m`. Changing ONE of them reddens this file (mutation A);
## changing the shared rule in BOTH would not. The two hand-authored hulls are
## the exception and are the reason this is worth running at all:
## `FishingTrawlerSmall` states `BOW_LENGTH_M` on the grid side and `BOW_FRAC`
## on the plate side, and `PassengerCatamaran` states 0.0 and `rect_plan_ring`.
## Note also that `StructurePlan.make_hull_stations` honours the catalogue's
## `bow_taper_m` field while `make_physics_profile` ignores it and recomputes
## `beam_m * 0.5`; every catalogue entry happens to declare a `bow_taper_m`
## equal to half its beam today, so those two agree by coincidence, not by
## construction.
##
## ── MUTATION-VERIFIED, BOTH WAYS, 2026-08-16 ────────────────────────────────
##
##   A. `FishingTrawlerSmall.make_grid`'s taper term set to 0.0 — a rectangular
##      grid on a pointed hull, which is exactly the catamaran's shape of
##      mistake transplanted onto a monohull. **38 checks, 1 FAILED**, against
##      38 / 0 unmutated: *hull_28x10 offers 90 of 1120 cells whose centre is
##      outside the drawn deck, worst +3.182 m at ship-local (-4.750, -13.750)*.
##      (3.182 m is the perpendicular distance outside the chamfer edge, which
##      is what this file measures; the cell sits 4.750 m off the centreline
##      where the plate has collapsed to the stem point.)
##   B. THE BLIND VERSION, and it is why the outline is the plate's. With
##      mutation A still in place, the ring replaced by the rectangle
##      `grid.half_beam` x `grid.half_loa` — a second copy of the grid — the
##      same run comes back **38 checks, 0 FAILED: GREEN ON THE DEFECT**, on
##      all nine hulls. A check written against the grid's own rectangle cannot
##      see a grid that is the wrong shape, which is REALITY.md §3b in one
##      measurement.
##
## ── WHAT THIS DOES NOT ANSWER, so nobody reads it as more than it is ────────
##
##   • It asks whether there is DECK under the cell, not whether there is HULL
##     under the deck. On `hull_45x16_cat` the bridge deck is drawn as a full
##     16 x 45 m rectangle (`rect_plan_ring`) while the demihulls under it come
##     to a point: at z = -22.25 m the plate spans |x| <= 8.000 and the two
##     demihulls occupy only |x| in [5.950, 6.450]. Every cell here is over
##     drawn deck and the forward corners of that deck are over open water.
##     Whether a catamaran's bridge deck should run square to the stem is a hull
##     design question and it is OPEN — this file does not decide it.
##   • It tests the CELL CENTRE, not the cell. A full cell adjacent to a 45
##     degree chamfer has corners outside the ring by construction, and the
##     corner number this file prints is 0.354 m on all eight pointed hulls —
##     exactly half a cell diagonal, i.e. the chamfer's own quantisation and not
##     a defect. It is printed rather than asserted so it stays visible.
##   • It says nothing about the WALK SLAB, and the walk slab is looser than
##     both the plate and the grid on every pointed hull. Measured through the
##     PHYSICS SERVER, not read off the source
##     (`tests/_walk_slab_over_water_probe.gd`): a downward ray on the
##     `boat_walk` mask hits `WalkDeck` at y = 5.810 on hull_28x10 at
##     (x 4.750, z -13.860) and at y = 15.150 on hull_150x32 at
##     (x 15.200, z -74.250) — both well outside the drawn plate, which has
##     tapered to the stem point at those stations. `WalkDeckCollider` is
##     `10.000 x 0.140 x 28.000` and `32.000 x 0.140 x 150.000`, i.e. the full
##     rectangle, `disabled=false`. So a builder is offered LESS than a walker
##     is given, on all eight pointed hulls. That is a different system's
##     outline, no player character has actually been driven out there, and
##     nothing in this file changes it.

const TestReport := preload("res://tests/support/test_report.gd")

var _t


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_t = TestReport.new("grid_deck_outline_test")

	var hull_ids := PackedStringArray()
	for entry in HullRegistry.catalog():
		hull_ids.append(str(entry.get("id", "")))
	_t.check("the fleet has hulls to test (%d)" % hull_ids.size(), hull_ids.size() >= 6)

	var total_cells := 0
	for hull_id in hull_ids:
		total_cells += _test_hull(hull_id)

	## A run that tested nothing must not report green — the grid could have
	## come back one cell wide and every per-hull claim would still pass.
	_t.check(
		"the fleet's grids offered %d cells to test (>= 50 000)" % total_cells,
		total_cells >= 50000,
	)
	_t.finish(get_tree())


func _test_hull(hull_id: String) -> int:
	var grid := HullRegistry.make_grid(hull_id)
	if not _t.check("%s: make_grid returns a grid" % hull_id, grid != null):
		return 0
	var boat := HullRegistry.build_hull(hull_id)
	if not _t.check("%s: the hull builds" % hull_id, boat != null):
		return 0

	var ring := _deck_plate_ring(boat)
	## Without this the claim below is vacuous on any hull that stops drawing a
	## plate: an empty ring makes `_outside_by` return 0.0 for every cell.
	if not _t.check(
		"%s: the hull draws a weather deck with a plan ring (%d points)"
			% [hull_id, ring.size()],
		ring.size() >= 3,
	):
		boat.free()
		return 0

	var offered := 0
	var outside_centres := 0
	var worst_centre := -1e18
	var worst_z := 0.0
	var worst_x := 0.0
	var worst_corner := -1e18
	for iz in range(grid.length):
		for ix in range(grid.width):
			if grid.cell_shape(ix, iz) == DeckGrid.CellShape.NONE:
				continue
			offered += 1
			var c := grid.cell_center_local(Vector3i(ix, 0, iz))
			var centre_out := _outside_by(ring, Vector2(c.x, c.z))
			if centre_out > TOLERANCE_M:
				outside_centres += 1
			if centre_out > worst_centre:
				worst_centre = centre_out
				worst_z = c.z
				worst_x = c.x
			var half := DeckGrid.CELL_M * 0.5
			for sx in [-half, half]:
				for sz in [-half, half]:
					worst_corner = maxf(
						worst_corner, _outside_by(ring, Vector2(c.x + sx, c.z + sz))
					)

	print(
		"  [outline] %-15s %5d cells offered · worst centre %+.3f m at (%+.3f, %+.3f)"
			% [hull_id, offered, worst_centre, worst_x, worst_z]
		+ " · worst corner %+.3f m · walk slab %.1f x %.1f m"
			% [worst_corner, float(boat.hull_size.x), float(boat.hull_size.z)]
	)
	_t.check(
		(
			"%s: every one of the %d cells the grid offers has its centre over the"
			+ " deck the hull draws (%d outside, worst %+.3f m at ship-local"
			+ " x=%+.3f z=%+.3f, allowed %.3f)"
		) % [
			hull_id, offered, outside_centres, worst_centre, worst_x, worst_z,
			TOLERANCE_M,
		],
		outside_centres == 0,
	)
	boat.free()
	return offered


## The chamfer shoulder is a chord across a corner and the grid's own half-cells
## land on it, so a millimetre of float residue at the shoulder is not a cell
## over water. Nothing in the fleet is within three orders of magnitude of this:
## the worst measured centre excursion on any hull is +0.000 m and the first
## real offender in this repo's history was +6.639 m.
const TOLERANCE_M := 0.001


## The weather deck's own plan polygon, in SHIP-LOCAL metres.
##
## `plate_args.ring` is in the plate NODE's frame — `boat_body.gd` says so and
## the catamaran relies on it, positioning its bridge deck by Y — so the node's
## own X/Z is added back rather than assumed zero.
func _deck_plate_ring(boat: Node) -> PackedVector2Array:
	var mi := boat.get_node_or_null("HullVisual/Deck") as MeshInstance3D
	if mi == null or not mi.has_meta("plate_args"):
		return PackedVector2Array()
	var args: Dictionary = mi.get_meta("plate_args")
	var raw: PackedVector2Array = args.get("ring", PackedVector2Array())
	var shift := Vector2(mi.position.x, mi.position.z)
	var out := PackedVector2Array()
	for point in raw:
		out.append(point + shift)
	return out


## How far outside the ring the point is, in metres; 0.0 when it is inside.
##
## The rings this fleet draws are convex (a rectangle and a five-point pointed
## planform), so the distance to the outside of the nearest violated edge is the
## excursion. Winding is taken from the ring itself rather than assumed, so a
## ring authored the other way round is measured, not inverted.
func _outside_by(ring: PackedVector2Array, point: Vector2) -> float:
	var n := ring.size()
	if n < 3:
		return 0.0
	var area := 0.0
	for i in range(n):
		var a := ring[i]
		var b := ring[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	var sign := 1.0 if area >= 0.0 else -1.0
	var worst := -1e18
	for i in range(n):
		var a := ring[i]
		var b := ring[(i + 1) % n]
		var edge := b - a
		var length := edge.length()
		if length < 1e-9:
			continue
		## Positive when the point is on the OUTSIDE of this edge.
		var cross := (edge.x * (point.y - a.y) - edge.y * (point.x - a.x)) * sign
		worst = maxf(worst, -cross / length)
	return maxf(worst, 0.0)


## ── WHY `hull_stations` IS NOT THE OUTLINE THIS FILE ASKS — 2026-08-16 ──────
##
## The obvious authority is the loft, and on eight hulls of nine it is the same
## answer: `hull_stations.gd` deliberately cuts its deck-level bow with the same
## linear 45 degree chamfer `pointed_deck_plate` and `DeckGrid.cell_shape` use,
## and says so ("the straight half is not a taste decision — it is the §3b fix").
## Measured cell-centre overhang of grid past loft on the fleet: -0.000 m on all
## eight monohulls, every cell of every row.
##
## `hull_45x16_cat` reads **+6.639 m**, and it is not the grid that is wrong.
## `PassengerCatamaran._assemble` builds TWO lattices: `make_demihull_stations()`
## — drawn, collided, and fed to both buoyancy strips and the hydrodynamics — and
## `physics_profile.make_stations()`, an AGGREGATE 45 x 16 m monohull that is
## published as `hull_stations` and drawn nowhere. At z = -22.25 m the aggregate
## claims hull at |x| <= 1.111, where this vessel has an 11.9 m tunnel of open
## air, and claims water at |x| = 6.450, where a demihull bow actually is. It is
## wrong in both directions, and the 6.639 m is one symptom of that.
##
## It is NOT simply mis-shaped, and this is why nothing here changes it:
## `boat_physics_validation` calibrates every registered hull's draft through
## `hull_stations.volume_below(draft)` to within 1.5%, and `ShipwrightPricing`
## quotes a hull's price from the same lattice. The aggregate is doing a real
## hydrostatic job. `HullStations` is a single-body strip model — one `half_beam`
## per level, symmetric about x = 0 — so it CANNOT describe two demihulls and a
## bridge deck at once, and this hull needs it to be two things.
##
## So the finding is not a wrong number. It is that one field carries two
## properties — the hydrostatic model and the geometric outline — and the fleet
## got away with it for eight hulls because on a monohull they coincide.
## `vessel_render_capture._check_figure_on_the_ship` reads the loft as an
## outline and is therefore measuring a shape the catamaran does not have; no
## shipped figure spot is far enough forward to trip it today. Splitting the two
## is an owner decision with real cost on both sides and it is written up in
## it is OPEN. Nothing in this file decides it.
