class_name DeckFitoutJob
extends Node

## Main-thread, frame-budgeted construction for large brick vessels.
## Geometry is still created through BrickCatalog; this job prevents one large
## scene-tree/collision spike and exposes stable readiness milestones.
##
## The job merges static bricks into the same VesselSkinBaker skin `apply_sync`
## builds, through the same Session object, one item at a time. It used to call
## `create_item_visual` per item instead: at 3000 bricks that was 3002 mesh
## instances against the synchronous path's 3 for the same layout, so the
## vessels that most need the merged skin — the large ones, which are the only
## ones that come through here — were the only ones that never got it.
##
## WHAT IS AND IS NOT INSIDE THE FRAME BUDGET. Every unit below is one `_step`.
## Costs are off `tests/_fitout_seam_probe.gd` at 3000 bricks, called straight
## through with no renderer competing:
##
##   register one item into the skin      0.012 ms  (footprint cells + bucket)
##   emit one item's faces                0.026 ms mean, 1.95 ms worst single
##   mount one brick's gameplay          ~0.03 ms — CARRIED, not re-measured
##   commit the whole skin                 3.2 ms at 3000 bricks (one material
##                                         bucket), + 0.0 ms to parent it
##
##   flush the staged colliders             17.1 ms at 3000 bricks, 23.1 at 4000
##                                         — linear, and the ONE moment in a
##                                           staged fit-out when the WalkDeck
##                                           leaves its physics space. See
##                                           `_open_collider_stage`.
##
## `_prepare_gameplay` is the exception and is DECLARED as one: a single
## `VesselCompliance.validate` call — 113 ms at 3000 bricks, 28x this job's own
## budget — with no resumable seam anywhere in it. 72% of that is
## `VesselOutfit.validate`, which DOES walk the layout brick by brick and so
## could be given one; that is a change to two files this job does not own.
## It is counted in `indivisible_steps` rather than hidden.
##
## DO NOT ADD A MILLISECOND ASSERTION AROUND ANY OF THOSE NUMBERS ON THIS BOX.
## `max_unit_usec` is wall clock around GDScript that is sharing four cores with
## llvmpipe rasterising the skin, and it was measured at 31.59 ms
## (EXTERIOR_VISUALS) and 4.59 ms (GAMEPLAY) on two runs of identical code. The
## assertable, clock-free statement is `steps_by_phase`: is the work divided at
## all, and which steps are declared as not divided.

signal readiness_changed(readiness: Readiness)

const BrickShellClassifierScript := preload(
	"res://scripts/ship/brick_shell_classifier.gd"
)

enum Readiness {
	HULL,
	EXTERIOR,
	FULL_VISUAL,
	INTERACTIVE,
}

enum Phase {
	REGISTER_SKIN,
	EXTERIOR_VISUALS,
	INTERIOR_VISUALS,
	GAMEPLAY,
	COMPLETE,
}

const FRAME_BUDGET_USEC := 4000

var readiness: Readiness = Readiness.HULL
var max_frame_work_usec: int = 0
## Worst frame that contained no step declared indivisible — the budget the
## `_process` loop is actually able to keep.
var max_divisible_frame_usec: int = 0
## Worst single divisible step. A frame may overrun the budget by at most this,
## because the loop checks the clock BEFORE starting a unit, never during one.
var max_unit_usec: int = 0
## Which phase that worst unit was in — an allowance nobody can attribute is an
## allowance nobody can shrink.
var max_unit_phase: String = ""
## [{"name": String, "usec": int}] for every step that cannot be subdivided.
var indivisible_steps: Array[Dictionary] = []
## Phase name -> how many `_step` calls were spent in it. CLOCK-FREE evidence
## that a phase is divided into units at all, and the only evidence there is:
## `max_unit_usec` was measured swinging 4.6 ms -> 31.6 ms between two runs of
## the same code on this box, because it times GDScript work while llvmpipe
## rasterises the growing skin on the same four cores. A phase that collapsed
## its whole loop into one call would cost the same milliseconds on a fast box
## and only this counter would notice.
var steps_by_phase: Dictionary = {}
## Phase name -> total usec spent inside `_step` for that phase. Wall clock, so
## machine-dependent in absolute terms (§ the header) — but it brackets only the
## job's own GDScript, never the frame's draw, so the SHAPE of `usec_by_phase`
## against brick count is the one thing here that says the same on any box. It
## exists because "the staged fit-out is slow" was true for years without anyone
## being able to say WHICH phase, and a fix aimed at the wrong phase measures a
## real improvement on the wrong half.
var usec_by_phase: Dictionary = {}
var exterior_ready_usec: int = 0
var interactive_ready_usec: int = 0
## How many colliders the closing flush moved from the staging node onto the
## WalkDeck. Zero after a complete fit-out of a vessel with colliders means the
## flush ran on an empty window, which is the failure staging can produce that
## the old code could not: colliders built and never delivered.
var staged_colliders_flushed: int = 0

var _boat: BoatBody
var _root: Node3D
var _layout: BrickLayout
var _grid: DeckGrid
var _hull_id := ""
var _outfit: Dictionary = {}
var _declared := ""
var _exterior: Array = []
var _interior: Array = []
var _all_items: Array = []
var _accepted_fishing: Dictionary = {}
var _accepted_helm: Dictionary = {}
var _visual_by_key: Dictionary = {}
var _mount_state := {"brick_i": 0, "ladder_n": 0}
var _phase: Phase = Phase.EXTERIOR_VISUALS
var _cursor := 0
var _full_requested := true
var _started_usec := 0
var _gameplay_prepared := false
var _skin: VesselSkinBaker.Session = null
var _mass_batch_open := false
var _collider_stage_open := false
var _frame_indivisible_usec := 0


func configure(
	boat: BoatBody,
	root: Node3D,
	layout: BrickLayout,
	grid: DeckGrid,
	hull_id: String,
	declared: String,
	primary_items: Array,
	full_requested: bool,
) -> void:
	_boat = boat
	_root = root
	_layout = layout
	_grid = grid
	_hull_id = hull_id
	_declared = declared
	_all_items = primary_items.duplicate(false)
	_full_requested = full_requested
	var shell: Dictionary = BrickShellClassifierScript.classify(layout, grid, primary_items)
	_exterior = (shell.get("exterior", []) as Array).duplicate(false)
	_interior = (shell.get("interior", []) as Array).duplicate(false)
	_skin = DeckFitout.new_skin_session(grid)
	_phase = Phase.REGISTER_SKIN if _skin != null else Phase.EXTERIOR_VISUALS
	_started_usec = Time.get_ticks_usec()
	_set_readiness(Readiness.HULL)
	set_process(true)


func request_full_detail() -> void:
	_full_requested = true
	if _phase != Phase.COMPLETE:
		set_process(true)


func is_complete() -> bool:
	return _phase == Phase.COMPLETE


func _process(_delta: float) -> void:
	if _boat == null or _root == null or not is_instance_valid(_boat) or not is_instance_valid(_root):
		queue_free()
		return
	var frame_started := Time.get_ticks_usec()
	_frame_indivisible_usec = 0
	var did_work := false
	while not did_work or Time.get_ticks_usec() - frame_started < FRAME_BUDGET_USEC:
		did_work = true
		var unit_phase := _phase
		var phase_name := str(Phase.keys()[int(unit_phase)])
		steps_by_phase[phase_name] = int(steps_by_phase.get(phase_name, 0)) + 1
		var unit_started := Time.get_ticks_usec()
		var more := _step()
		var unit_elapsed := Time.get_ticks_usec() - unit_started
		usec_by_phase[phase_name] = int(usec_by_phase.get(phase_name, 0)) + unit_elapsed
		if _frame_indivisible_usec == 0 and unit_elapsed > max_unit_usec:
			max_unit_usec = unit_elapsed
			max_unit_phase = Phase.keys()[int(unit_phase)]
		if not more:
			break
	var elapsed := Time.get_ticks_usec() - frame_started
	max_frame_work_usec = maxi(max_frame_work_usec, elapsed)
	if _frame_indivisible_usec == 0:
		max_divisible_frame_usec = maxi(max_divisible_frame_usec, elapsed)
	_publish_timings()


func _publish_timings() -> void:
	if _boat == null or not is_instance_valid(_boat):
		return
	_boat.set_meta("fitout_max_frame_usec", max_frame_work_usec)
	_boat.set_meta("fitout_max_divisible_frame_usec", max_divisible_frame_usec)
	_boat.set_meta("fitout_max_unit_usec", max_unit_usec)
	_boat.set_meta("fitout_max_unit_phase", max_unit_phase)
	_boat.set_meta("fitout_indivisible_steps", indivisible_steps.duplicate(true))
	_boat.set_meta("fitout_steps_by_phase", steps_by_phase.duplicate())
	_boat.set_meta("fitout_usec_by_phase", usec_by_phase.duplicate())
	_boat.set_meta("fitout_staged_colliders_flushed", staged_colliders_flushed)


## Records a step that has no resumable seam. Declaring one is a design
## statement, not an escape hatch: the bench counts them and fails on a second.
func _run_indivisible(step_name: String, callable: Callable) -> void:
	var started := Time.get_ticks_usec()
	callable.call()
	var spent := Time.get_ticks_usec() - started
	_frame_indivisible_usec += spent
	indivisible_steps.append({"name": step_name, "usec": spent})


func _step() -> bool:
	match _phase:
		Phase.REGISTER_SKIN:
			## Every item, exterior AND interior, before a single face is
			## emitted: face culling and corner AO are computed against the
			## whole solid field, so a brick registered late would leave the
			## faces around it drawn and its neighbours' corners mis-shaded.
			if _cursor < _all_items.size():
				_skin.register_item(_all_items[_cursor] as Dictionary)
				_cursor += 1
				return true
			_cursor = 0
			_phase = Phase.EXTERIOR_VISUALS
			return true
		Phase.EXTERIOR_VISUALS:
			if _cursor < _exterior.size():
				_add_visual(_exterior[_cursor] as Dictionary)
				_cursor += 1
				return true
			_commit_skin()
			exterior_ready_usec = Time.get_ticks_usec() - _started_usec
			_boat.set_meta("fitout_exterior_ready_usec", exterior_ready_usec)
			_set_readiness(Readiness.EXTERIOR)
			_cursor = 0
			_phase = Phase.INTERIOR_VISUALS
			if not _full_requested:
				set_process(false)
				return false
			return true
		Phase.INTERIOR_VISUALS:
			if not _full_requested:
				set_process(false)
				return false
			if _cursor < _interior.size():
				_add_visual(_interior[_cursor] as Dictionary)
				_cursor += 1
				return true
			_commit_skin()
			_set_readiness(Readiness.FULL_VISUAL)
			_cursor = 0
			_phase = Phase.GAMEPLAY
			return true
		Phase.GAMEPLAY:
			if not _gameplay_prepared:
				_run_indivisible("VesselCompliance.validate", _prepare_gameplay)
				return true
			if _cursor < _all_items.size():
				_open_mass_batch()
				_open_collider_stage()
				_mount_gameplay(_all_items[_cursor] as Dictionary)
				_cursor += 1
				return true
			## Declared rather than absorbed: this call serialises the whole
			## layout into `brick_layout` meta in one `to_dict()`, which is 12 ms
			## at n=3000 and has no more of a seam in it than the compliance
			## pass does. Left undeclared it inflated `max_unit_usec` — the
			## allowance the frame-budget check is measured against — from a
			## tenth of a millisecond to twelve, which would have made that
			## check unable to fail.
			_run_indivisible(
				"DeckFitout.finish_fitout",
				func() -> void:
					_close_mass_batch()
					DeckFitout.finish_fitout(
						_boat,
						_root,
						_layout,
						_grid,
						_outfit,
						_declared,
						_mount_state,
					)
			)
			## Declared as its own step rather than folded into the one above,
			## because it is the whole subject of the staging change, and an
			## allowance nobody can attribute is an allowance nobody can shrink.
			## `finish_fitout` runs FIRST: it mounts pads and holds, and any
			## collider they ever come to emit has to land in the same flush as
			## the bricks', or the vessel would gain that one box afterwards
			## through the in-space path this exists to avoid.
			_run_indivisible(
				"BoatBody.flush_walk_collider_staging",
				_close_collider_stage,
			)
			interactive_ready_usec = Time.get_ticks_usec() - _started_usec
			_boat.set_meta("fitout_interactive_ready_usec", interactive_ready_usec)
			_phase = Phase.COMPLETE
			_set_readiness(Readiness.INTERACTIVE)
			set_process(false)
			return false
	return false


## Publishes what has been emitted so far. The SurfaceTools keep their vertices,
## so the interior stage adds to the same buckets and the second commit replaces
## each mesh with the complete one — the final skin is byte-for-byte the shape
## `apply_sync` would have built, not a second set of nodes beside the first.
func _commit_skin() -> void:
	if _skin == null:
		return
	_skin.commit()
	DeckFitout.attach_skin(_root, _skin)


## `apply_sync` has batched brick mass since it was written; the staged path did
## not, so every `set_mass_entry` re-summed every entry placed so far — O(n^2)
## across the mount phase, 4.5M dictionary steps at n=3000. Batching per FRAME
## instead of per brick was still wrong for a different reason: it hid one O(n)
## mass-and-centre-of-mass refresh inside every frame, 18 ms of it at n=3000,
## outside any `_step` and so outside the unit accounting. The batch stays open
## for the whole mount phase and closes inside the declared finish step, where
## its cost is measured and reported like any other indivisible work.
func _open_mass_batch() -> void:
	if _mass_batch_open or _boat == null or not is_instance_valid(_boat):
		return
	_boat.begin_mass_batch()
	_mass_batch_open = true


func _close_mass_batch() -> void:
	if not _mass_batch_open:
		return
	_mass_batch_open = false
	if _boat != null and is_instance_valid(_boat):
		_boat.end_mass_batch()


## The staged path's answer to the quadratic the synchronous path shed a wave
## ago. `apply_sync` wraps its whole mount loop in `begin/end_walk_collider_batch`
## and hands the body back complete in one call; this job's mount loop is spread
## over hundreds of frames, and a batch left open across one is a vessel a player
## falls through — `BoatBody._physics_process` forces exactly that case closed.
##
## So the colliders are built into a detached node instead and moved onto the
## body in one synchronous flush at the end. Measured on this box, the GAMEPLAY
## phase's own `_step` time at 4000 bricks: 9416 ms -> 990 ms, and the curve goes
## from x15.8 to x4.9 across a 4x brick range. See
## `BoatBody.begin_walk_collider_staging` for the full table and for the two
## options this was chosen over.
##
## Opened lazily at the first mount for the same reason the mass batch is: a
## remote replica stops after EXTERIOR_VISUALS and never mounts anything, and a
## window opened for it would be one nobody ever closes.
func _open_collider_stage() -> void:
	if _collider_stage_open or _boat == null or not is_instance_valid(_boat):
		return
	_boat.begin_walk_collider_staging(self)
	_collider_stage_open = true


func _close_collider_stage() -> void:
	if not _collider_stage_open:
		return
	_collider_stage_open = false
	if _boat != null and is_instance_valid(_boat):
		staged_colliders_flushed = _boat.end_walk_collider_staging()


## A cancelled fitout (reapply, despawn) must not leave the boat batched open —
## its mass would never refresh again. `DeckFitout.clear` removes this node,
## which lands here.
func _exit_tree() -> void:
	_close_mass_batch()
	## FLUSH, not discard. A cancelled fit-out's colliders are about to be thrown
	## away by `DeckFitout.clear`'s `clear_walk_brick_colliders()` anyway, so the
	## cost of flushing is one wasted linear pass — while the cost of discarding
	## is a vessel with no brick collision on any path that frees this job without
	## clearing, and "no caller does that today" is how the batch latch was argued
	## safe too.
	_close_collider_stage()


func _prepare_gameplay() -> void:
	_outfit = VesselCompliance.validate(_layout, _hull_id, _declared, _grid)
	var accepted: Dictionary = _outfit.get("accepted_slots", {})
	_accepted_fishing = _cell_set(accepted.get("fishing", []))
	_accepted_helm = _cell_set(accepted.get("helm", []))
	_gameplay_prepared = true


func _add_visual(item: Dictionary) -> void:
	if _skin != null and _skin.emit_item(item):
		## Static brick: its geometry is in the merged skin. Signs and light
		## fixtures mounted ON the cell are still their own nodes.
		DeckFitout.create_cell_mounts(_root, _grid, item)
		return
	var visual := DeckFitout.create_item_visual(_root, _grid, item)
	if visual == null:
		return
	var cell: Vector3i = item.get("cell", Vector3i(-1, -1, -1))
	visual.set_meta(
		"fitout_stage",
		"exterior" if _phase == Phase.EXTERIOR_VISUALS else "interior",
	)
	visual.set_meta("brick_cell", cell)
	_visual_by_key[BrickLayout.cell_key(cell)] = visual


func _mount_gameplay(item: Dictionary) -> void:
	var cell: Vector3i = item.get("cell", Vector3i(-1, -1, -1))
	## `visual` is null for every skin-baked brick, which is most of a large
	## vessel. It is passed through, not returned on: mass, colliders and
	## mounted fixtures do not need a node, and skipping them here is how a
	## merged deck becomes a deck you fall through.
	var visual := _visual_by_key.get(BrickLayout.cell_key(cell), null) as Node3D
	if visual != null and not is_instance_valid(visual):
		visual = null
	DeckFitout.mount_item_gameplay(
		_boat,
		_root,
		_grid,
		item,
		visual,
		_accepted_fishing,
		_accepted_helm,
		_mount_state,
	)


func _set_readiness(next: Readiness) -> void:
	if readiness == next and _boat != null and _boat.has_meta("fitout_readiness"):
		return
	readiness = next
	if _boat != null and is_instance_valid(_boat):
		_boat.set_meta("fitout_readiness", int(readiness))
	readiness_changed.emit(readiness)


func _cell_set(cells: Variant) -> Dictionary:
	var out := {}
	if cells is Array:
		for cell in cells as Array:
			if cell is Vector3i:
				out[cell] = true
	return out
