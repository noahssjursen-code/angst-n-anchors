extends RefCounted

## The same empty container yard used by generated ports and the construction kit.
const MAX_WIDTH_M := 28.0
const MAX_LENGTH_M := 80.0

static func packed_size(available: Vector2) -> Vector2:
	var slot := Vector2(ContainerUnit.DEFAULT_FOOTPRINT)
	return (available / slot).floor() * slot

static func size_for_lane(lane_width: float, bay_length: float) -> Vector2:
	return packed_size(Vector2(clampf(lane_width*.88,8.0,MAX_WIDTH_M),clampf(bay_length*.88,12.0,MAX_LENGTH_M)))

static func container_pad(size: Vector2, service_discovery_enabled := true) -> CargoSlotPadComponent:
	var pad := CargoSlotPadComponent.new()
	pad.service_discovery_enabled=service_discovery_enabled
	pad.show_pad_visual = false
	pad.is_quay_yard_pad = true
	pad.affects_boat_cargo_mass = false
	pad.deck_width_m = size.x
	pad.deck_length_m = size.y
	pad.cell_size_m = 1.0
	pad.container_footprint = ContainerUnit.DEFAULT_FOOTPRINT
	var drop := Node3D.new()
	drop.name = "YardDrop"
	if service_discovery_enabled:drop.add_to_group("container_yard_drop")
	pad.add_child(drop)
	return pad
