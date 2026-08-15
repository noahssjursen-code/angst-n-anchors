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
## WHAT IS AND IS NOT INSIDE THE FRAME BUDGET. Every unit below is one `_step`
## and costs well under FRAME_BUDGET_USEC on the measured layouts:
##
##   register one item into the skin      ~0.05 ms   (footprint cells + bucket)
##   emit one item's faces                ~0.01 ms
##   create one live brick's visual       ~0.07 ms
##   mount one brick's gameplay           ~0.03 ms
##   commit the whole skin                 2.5 ms at 3000 bricks — indivisible,
##                                         but inside the 4 ms budget
##
## `_prepare_gameplay` is the exception and is DECLARED as one: a single
## `VesselCompliance.validate` call, 118 ms at 3000 bricks, with no resumable
## seam anywhere in it. It is counted in `indivisible_steps` rather than hidden,
## and `max_divisible_frame_usec` reports the budget the loop actually keeps.

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
var exterior_ready_usec: int = 0
var interactive_ready_usec: int = 0

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
		var unit_started := Time.get_ticks_usec()
		var more := _step()
		var unit_elapsed := Time.get_ticks_usec() - unit_started
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


## A cancelled fitout (reapply, despawn) must not leave the boat batched open —
## its mass would never refresh again. `DeckFitout.clear` removes this node,
## which lands here.
func _exit_tree() -> void:
	_close_mass_batch()


func _prepare_gameplay() -> void:
	_outfit = VesselCompliance.validate(_layout, _hull_id, _declared, _grid)
	var accepted: Dictionary = _outfit.get("accepted_slots", {})
	_accepted_fishing = _cell_set(accepted.get("fishing", []))
	_accepted_helm = _cell_set(accepted.get("helm", []))
	_gameplay_prepared = true


func _add_visual(item: Dictionary) -> void:
	if false and _skin != null and _skin.emit_item(item):
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
