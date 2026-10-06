class_name ImportedBulkHold
extends BulkHoldComponent
## Inventory/transfer API remains BulkHoldComponent. Blender supplies real walls.
const DESIGN_CAPACITY_T := 40.0
var boat: BoatBody

func get_crane_aim_toward(_world_hint: Vector3) -> Vector3:
	# Compact compartments need a central grab approach, away from the divider.
	return get_crane_aim_global()

func contains_grab_mouth(world_point: Vector3) -> bool:
	var local := to_local(world_point)
	return absf(local.x) < hold_width_m*.5-.7 and absf(local.z) < hold_length_m*.5-.7 and absf(local.y)<1.45

func _ready() -> void:
	super._ready()
	state.capacity_tonnes_t = DESIGN_CAPACITY_T
	_on_state_changed(state)

func _rebuild_visual() -> void:
	if not is_inside_tree(): return
	_clear_fill_layer()
	if is_instance_valid(_visual_root): _visual_root.queue_free()
	_visual_root = Node3D.new()
	_visual_root.name = "CargoPresentation"
	add_child(_visual_root)
	_pit_mesh = null
	_update_fill_visual()

func _update_cargo_fill_layer() -> void:
	super._update_cargo_fill_layer()
	if is_instance_valid(_fill_layer):
		_fill_layer.position.y = -hold_depth_m + .025
		for mesh in _fill_layer.find_children("*","MeshInstance3D",true,false):
			mesh.set_meta("bulk_fill_visual",true)

func _on_state_changed(value: BulkHoldState) -> void:
	super._on_state_changed(value)
	if is_instance_valid(boat) and is_inside_tree():
		var centre := to_global(Vector3(0,-hold_depth_m + _inner_fill_size().y * state.fill_ratio() * .5,0))
		boat.set_mass_entry("bulk:"+hold_id, state.filled_tonnes_t*1000,boat.to_local(centre),"cargo")

func _exit_tree() -> void:
	if is_instance_valid(boat): boat.remove_mass_entry("bulk:"+hold_id)
