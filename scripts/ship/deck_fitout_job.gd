class_name DeckFitoutJob
extends Node

## Main-thread, frame-budgeted construction for large brick vessels.
## Geometry is still created through BrickCatalog; this job prevents one large
## scene-tree/collision spike and exposes stable readiness milestones.

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
	EXTERIOR_VISUALS,
	INTERIOR_VISUALS,
	GAMEPLAY,
	COMPLETE,
}

const FRAME_BUDGET_USEC := 4000

var readiness: Readiness = Readiness.HULL
var max_frame_work_usec: int = 0
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
var _accepted_cargo: Dictionary = {}
var _visual_by_key: Dictionary = {}
var _mount_state := {"brick_i": 0, "ladder_n": 0}
var _phase: Phase = Phase.EXTERIOR_VISUALS
var _cursor := 0
var _full_requested := true
var _started_usec := 0
var _gameplay_prepared := false


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
	var did_work := false
	while not did_work or Time.get_ticks_usec() - frame_started < FRAME_BUDGET_USEC:
		did_work = true
		if not _step():
			break
	var elapsed := Time.get_ticks_usec() - frame_started
	max_frame_work_usec = maxi(max_frame_work_usec, elapsed)
	_boat.set_meta("fitout_max_frame_usec", max_frame_work_usec)


func _step() -> bool:
	match _phase:
		Phase.EXTERIOR_VISUALS:
			if _cursor < _exterior.size():
				_add_visual(_exterior[_cursor] as Dictionary)
				_cursor += 1
				return true
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
			_set_readiness(Readiness.FULL_VISUAL)
			_cursor = 0
			_phase = Phase.GAMEPLAY
			return true
		Phase.GAMEPLAY:
			if not _gameplay_prepared:
				_prepare_gameplay()
				return true
			if _cursor < _all_items.size():
				_mount_gameplay(_all_items[_cursor] as Dictionary)
				_cursor += 1
				return true
			DeckFitout.finish_fitout(
				_boat,
				_root,
				_layout,
				_grid,
				_outfit,
				_accepted_cargo,
				_declared,
				_mount_state,
			)
			interactive_ready_usec = Time.get_ticks_usec() - _started_usec
			_boat.set_meta("fitout_interactive_ready_usec", interactive_ready_usec)
			_phase = Phase.COMPLETE
			_set_readiness(Readiness.INTERACTIVE)
			set_process(false)
			return false
	return false


func _prepare_gameplay() -> void:
	_outfit = VesselCompliance.validate(_layout, _hull_id, _declared, _grid)
	var accepted: Dictionary = _outfit.get("accepted_slots", {})
	_accepted_fishing = _cell_set(accepted.get("fishing", []))
	_accepted_helm = _cell_set(accepted.get("helm", []))
	_accepted_cargo.clear()
	for idx in accepted.get("cargo_zone_indices", []):
		_accepted_cargo[int(idx)] = true
	_gameplay_prepared = true


func _add_visual(item: Dictionary) -> void:
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
	var visual := _visual_by_key.get(BrickLayout.cell_key(cell), null) as Node3D
	if visual == null or not is_instance_valid(visual):
		return
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
