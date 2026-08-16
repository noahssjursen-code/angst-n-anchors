extends Node

## Scratch probe (leading underscore — NOT a gate unit). Lane B.
##
## Photographs `scenes/showcases/catch_hold_showcase.tscn` at five fill stages,
## because that scene's whole job is displaying them and from `bd548bc` until
## today it displayed a closed lid at every one of them.
##
## The scene is loaded AS SHIPPED — its own camera, its own lighting, its own
## opening state. Nothing here poses it; if the pose is wrong the frames say so.

const OUT_DIR := "res://screenshots/vessels/hold"
const STAGES := [0.0, 0.10, 0.25, 0.50, 1.0]

var _viewport: SubViewport
var _showcase: Node3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 900)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	get_tree().root.add_child(_viewport)
	_showcase = (load("res://scenes/showcases/catch_hold_showcase.tscn") as PackedScene).instantiate()
	_viewport.add_child(_showcase)
	await get_tree().process_frame
	var hold := _showcase.get_node_or_null("CatchHold") as CatchHoldComponent
	if hold == null:
		print("ABORT: the showcase has no hold")
		get_tree().quit(1)
		return
	print("SHOWCASE hatch_open=%s footprint=%v boards=%d slot=%.3f m"
		% [str(hold.is_hatch_open()), hold.footprint_m, hold.hatch_board_count(),
			hold.hatch_slot_width_m()])
	for ratio in STAGES:
		hold.withdraw_oldest(hold.get_state().total_mass_kg())
		if ratio > 0.0:
			hold.accept_lot(CatchLot.create({
				"lot_id": "stage%d" % int(ratio * 100.0),
				"mass_kg": hold.get_state().capacity_kg * float(ratio),
			}))
		await _save("hold__showcase__fill%03d" % int(float(ratio) * 100.0))
	## And the lid, for the comparison the report has to make.
	## EMPTY, LOAD, THEN CLOSE — and two separate defects sit behind that order.
	##
	## LOAD BEFORE CLOSE, because since 2026-08-16 a shut hold refuses catch, so
	## closing first would photograph a lid over an EMPTY hold and label it 50%.
	##
	## EMPTY BEFORE LOADING, because this frame has NEVER been 50% — that one is
	## older than the hatch. The stage loop above ends at ratio 1.0 and leaves the
	## hold at 4000 of 4000 kg, so the 2000 kg offered here has always overflowed
	## whole and the frame named `closed_50` has always photographed a hold at
	## 100%, with its own on-screen label saying so.
	hold.withdraw_oldest(hold.get_state().total_mass_kg())
	hold.accept_lot(CatchLot.create({"lot_id": "closed", "mass_kg": 2000.0}))
	hold.set_hatch_open(false)
	await _save("hold__showcase__closed_50")
	print("SHOWCASE SHOT DONE")
	get_tree().quit(0)


func _save(case: String) -> void:
	for _frame in range(5):
		await get_tree().process_frame
	var image := _viewport.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, case]))
	print("SHOT %s" % case)
