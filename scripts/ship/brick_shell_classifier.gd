class_name BrickShellClassifier
extends RefCounted

## Separates a sparse vessel layout into outside-visible and enclosed bricks.
## The hull/deck beneath y=0 is treated as closed; flood fill enters from the
## padded sides and sky, so arbitrary superstructure shapes need no templates.

const NEIGHBORS: Array[Vector3i] = [
	Vector3i.LEFT,
	Vector3i.RIGHT,
	Vector3i.UP,
	Vector3i.DOWN,
	Vector3i.FORWARD,
	Vector3i.BACK,
]


static func classify(
	layout: BrickLayout,
	_grid: DeckGrid = null,
	known_primary_items: Array = [],
) -> Dictionary:
	var primary_items: Array = (
		known_primary_items if not known_primary_items.is_empty()
		else layout.iter_primary_cells() if layout != null
		else []
	)
	if primary_items.is_empty():
		return {
			"exterior": [],
			"interior": [],
			"exterior_keys": {},
			"exterior_air_count": 0,
		}

	var occupied := {}
	var primary_by_occupied := {}
	var min_x := 0
	var max_x := 0
	var max_y := 0
	var min_z := 0
	var max_z := 0
	var first := true
	for key_raw in layout.cells.keys():
		var key := str(key_raw)
		var cell := BrickLayout.parse_key(key)
		if cell.y < 0:
			continue
		var entry := layout.cells[key_raw] as Dictionary
		occupied[cell] = true
		primary_by_occupied[cell] = (
			BrickLayout.parse_key(str(entry.get("occupied_by", key))) if entry.has("occupied_by")
			else cell
		)
		if first:
			min_x = cell.x
			max_x = cell.x
			max_y = cell.y
			min_z = cell.z
			max_z = cell.z
			first = false
		else:
			min_x = mini(min_x, cell.x)
			max_x = maxi(max_x, cell.x)
			max_y = maxi(max_y, cell.y)
			min_z = mini(min_z, cell.z)
			max_z = maxi(max_z, cell.z)

	var bounds_min := Vector3i(min_x - 1, 0, min_z - 1)
	var bounds_max := Vector3i(max_x + 1, max_y + 1, max_z + 1)
	var exterior_air := _flood_exterior_air(occupied, bounds_min, bounds_max)
	var exterior_primary := {}
	for occupied_raw in occupied.keys():
		var cell: Vector3i = occupied_raw
		for offset in NEIGHBORS:
			if exterior_air.has(cell + offset):
				var primary: Vector3i = primary_by_occupied.get(cell, cell)
				exterior_primary[BrickLayout.cell_key(primary)] = true
				break

	var exterior: Array = []
	var interior: Array = []
	for item_raw in primary_items:
		var item := (item_raw as Dictionary).duplicate(false)
		var primary: Vector3i = item.get("cell", Vector3i.ZERO)
		if exterior_primary.has(BrickLayout.cell_key(primary)):
			exterior.append(item)
		else:
			interior.append(item)
	exterior.sort_custom(_item_before)
	interior.sort_custom(_item_before)
	return {
		"exterior": exterior,
		"interior": interior,
		"exterior_keys": exterior_primary,
		"exterior_air_count": exterior_air.size(),
	}


static func _flood_exterior_air(
	occupied: Dictionary,
	bounds_min: Vector3i,
	bounds_max: Vector3i,
) -> Dictionary:
	var reached := {}
	var queue: Array[Vector3i] = []
	for y in range(bounds_min.y, bounds_max.y + 1):
		for z in range(bounds_min.z, bounds_max.z + 1):
			_seed_air(Vector3i(bounds_min.x, y, z), occupied, reached, queue)
			_seed_air(Vector3i(bounds_max.x, y, z), occupied, reached, queue)
		for x in range(bounds_min.x + 1, bounds_max.x):
			_seed_air(Vector3i(x, y, bounds_min.z), occupied, reached, queue)
			_seed_air(Vector3i(x, y, bounds_max.z), occupied, reached, queue)
	for x in range(bounds_min.x + 1, bounds_max.x):
		for z in range(bounds_min.z + 1, bounds_max.z):
			_seed_air(Vector3i(x, bounds_max.y, z), occupied, reached, queue)

	var read_i := 0
	while read_i < queue.size():
		var cell := queue[read_i]
		read_i += 1
		for offset in NEIGHBORS:
			var next := cell + offset
			if not _inside_bounds(next, bounds_min, bounds_max):
				continue
			if occupied.has(next) or reached.has(next):
				continue
			reached[next] = true
			queue.append(next)
	return reached


static func _seed_air(
	cell: Vector3i,
	occupied: Dictionary,
	reached: Dictionary,
	queue: Array[Vector3i],
) -> void:
	if occupied.has(cell) or reached.has(cell):
		return
	reached[cell] = true
	queue.append(cell)


static func _inside_bounds(cell: Vector3i, mn: Vector3i, mx: Vector3i) -> bool:
	return (
		cell.x >= mn.x and cell.x <= mx.x
		and cell.y >= mn.y and cell.y <= mx.y
		and cell.z >= mn.z and cell.z <= mx.z
	)


static func _item_before(a_raw: Variant, b_raw: Variant) -> bool:
	var a := a_raw as Dictionary
	var b := b_raw as Dictionary
	var ac: Vector3i = a.get("cell", Vector3i.ZERO)
	var bc: Vector3i = b.get("cell", Vector3i.ZERO)
	if ac.y != bc.y:
		return ac.y < bc.y
	if ac.z != bc.z:
		return ac.z < bc.z
	if ac.x != bc.x:
		return ac.x < bc.x
	var aid := str(a.get("brick_id", ""))
	var bid := str(b.get("brick_id", ""))
	if aid != bid:
		return aid < bid
	return int(a.get("yaw", 0)) < int(b.get("yaw", 0))
