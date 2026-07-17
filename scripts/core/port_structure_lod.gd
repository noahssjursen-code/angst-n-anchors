class_name PortStructureLod
extends Node3D

## Swaps a port structure between full mesh and ImpostorCache stamp by camera distance.
## Default full range matches house/building near LOD; cranes pass ~2× that.

const IMPOSTOR_CACHE := preload("res://scripts/core/impostor_cache.gd")
const CHECK_INTERVAL_S := 0.5
const DEFAULT_FULL_RANGE_M := WorldPropLod.LOD_NEAR_M
const CRANE_FULL_RANGE_M := WorldPropLod.LOD_NEAR_M * 2.0
## Stay on full mesh until this far past full_range_m (camera orbit thrash).
const HYSTERESIS_M := 120.0

var cache_key := ""
var full_factory: Callable = Callable()
var teardown: Callable = Callable()
var full_range_m: float = DEFAULT_FULL_RANGE_M
var _mode := ""  ## "full" | "impostor" | ""
var _check_accum := 0.0
var _visual: Node3D = null


func setup(
		key: String,
		factory: Callable,
		range_m: float = DEFAULT_FULL_RANGE_M,
		teardown_cb: Callable = Callable(),
) -> void:
	cache_key = key
	full_factory = factory
	full_range_m = maxf(range_m, 1.0)
	teardown = teardown_cb
	call_deferred("_apply_desired", true)


func _process(delta: float) -> void:
	_check_accum += delta
	if _check_accum < CHECK_INTERVAL_S:
		return
	_check_accum = 0.0
	_apply_desired(false)


func _apply_desired(force: bool = false) -> void:
	if cache_key.is_empty() or not full_factory.is_valid():
		return
	var want := _desired_mode()
	if not force and want == _mode:
		return
	if want == "impostor":
		_swap_impostor()
	else:
		_swap_full()


func _desired_mode() -> String:
	if not IMPOSTOR_CACHE.has_key(cache_key):
		return "full"
	var dist := _distance_to_camera()
	## Once full is up, keep it until clearly past the near band.
	if _mode == "full":
		if dist > full_range_m + HYSTERESIS_M:
			return "impostor"
		return "full"
	if dist <= full_range_m:
		return "full"
	return "impostor"


func _distance_to_camera() -> float:
	if not is_inside_tree():
		return 0.0
	var cam_pos := WorldReference.stream_position(get_viewport())
	return cam_pos.distance_to(global_position)


func _swap_full() -> void:
	_clear_visual()
	var built: Variant = full_factory.call()
	var node := built as Node3D
	if node == null:
		_mode = "full"
		return
	node.name = "Full"
	add_child(node)
	_visual = node
	_mode = "full"


func _swap_impostor() -> void:
	_clear_visual()
	if not IMPOSTOR_CACHE.has_key(cache_key):
		_swap_full()
		return
	var stamp := IMPOSTOR_CACHE.instance(cache_key, false) as Node3D
	stamp.name = "Impostor"
	add_child(stamp)
	_visual = stamp
	_mode = "impostor"


func _clear_visual() -> void:
	if teardown.is_valid():
		teardown.call()
	if _visual != null and is_instance_valid(_visual):
		_visual.free()
		_visual = null
	for child in get_children():
		child.free()
