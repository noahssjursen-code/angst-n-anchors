class_name CustomPortCollection
extends RefCounted

## Read-only preflight for a complete proposed collection of individually
## validated CustomPortState snapshots. This checks claims BETWEEN documents;
## it neither authenticates ownership nor replaces per-document validation.
## Plot rectangles are local metres; comparisons use world X/Z scalar doubles
## so distant coordinates do not lose small overlaps through Vector2 float32.

static func validate(snapshots: Array) -> Dictionary:
	var errors: Array[Dictionary] = []
	var port_ids: Dictionary = {}
	var plot_ids: Dictionary = {}
	var plots: Array[Dictionary] = []
	var world: Dictionary = {}
	for index in snapshots.size():
		var value: Variant = snapshots[index]
		if not _record_shape(value):
			errors.append({"code":"invalid_record", "record_index":index,
				"message":"A collection entry is missing its validated port identity, origin or plots."})
			continue
		var record: Dictionary = value
		var id: String = record.id
		if port_ids.has(id):
			errors.append({"code":"duplicate_port_id", "port_id":id,
				"record_index":index, "other_record_index":int(port_ids[id]),
				"message":"Port %s appears more than once in the proposed collection." % id})
		else:
			port_ids[id] = index
		if world.is_empty():
			world = record.world.duplicate(true)
		elif world != record.world:
			errors.append({"code":"world_mismatch", "port_id":id, "record_index":index,
				"message":"Port %s belongs to a different world." % id})
			continue
		for raw: Variant in record.plots:
			if not _plot_shape(raw):
				errors.append({"code":"invalid_plot", "port_id":id, "record_index":index,
					"message":"Port %s contains an invalid plot rectangle." % id})
				continue
			var plot: Dictionary = raw
			var bounds: Array = [float(record.origin_m[0])+float(plot.rect_m[0]),
				float(record.origin_m[2])+float(plot.rect_m[1]),
				float(plot.rect_m[2]), float(plot.rect_m[3])]
			var end_x: float = bounds[0]+bounds[2]
			var end_z: float = bounds[1]+bounds[3]
			if not is_finite(bounds[0]) or not is_finite(bounds[1]) or not is_finite(end_x) or not is_finite(end_z) or end_x<=bounds[0] or end_z<=bounds[1]:
				errors.append({"code":"invalid_plot", "port_id":id, "plot_id":str(plot.id),
					"record_index":index, "message":"Plot %s has unrepresentable world bounds." % str(plot.id)})
				continue
			var row := {"port_id":id, "plot_id":str(plot.id), "record_index":index,
				"bounds":bounds, "end_x":end_x, "end_z":end_z}
			if plot_ids.has(plot.id):
				var previous: Dictionary = plot_ids[plot.id]
				if int(previous.record_index) != index:
					var code := "duplicate_plot_id" if previous.bounds == bounds else "plot_bounds_conflict"
					var detail := _pair_error(code,row,previous)
					detail.message = "Plot %s is claimed by ports %s and %s%s." % [plot.id,previous.port_id,id,
						" with different world bounds" if code=="plot_bounds_conflict" else ""]
					errors.append(detail)
			else:
				plot_ids[plot.id] = row
			plots.append(row)

	# Sweep world X to skip disjoint ranges. Same-record topology remains the
	# responsibility of CustomPortState; no source arrays are sorted or changed.
	plots.sort_custom(_plot_less)
	var active: Array[Dictionary] = []
	for row: Dictionary in plots:
		var next_active: Array[Dictionary] = []
		for previous: Dictionary in active:
			if float(previous.end_x)<=float(row.bounds[0]): continue
			next_active.append(previous)
			if int(previous.record_index)==int(row.record_index): continue
			# Strict positive widths: exact edge/corner contact is legal.
			if minf(previous.end_z,row.end_z)<=maxf(previous.bounds[1],row.bounds[1]): continue
			var detail := _pair_error("plot_overlap",row,previous)
			detail.message = "Plots %s (%s) and %s (%s) overlap." % [previous.plot_id,previous.port_id,row.plot_id,row.port_id]
			errors.append(detail)
		next_active.append(row)
		active = next_active
	return {"ok":errors.is_empty(), "code":"valid_collection" if errors.is_empty() else "invalid_collection", "errors":errors}


static func _pair_error(code: String, row: Dictionary, other: Dictionary) -> Dictionary:
	return {"code":code, "port_id":row.port_id, "other_port_id":other.port_id,
		"plot_id":row.plot_id, "other_plot_id":other.plot_id,
		"record_index":row.record_index, "other_record_index":other.record_index,
		"rect_world_m":row.bounds.duplicate(), "other_rect_world_m":other.bounds.duplicate()}


static func _plot_less(a: Dictionary, b: Dictionary) -> bool:
	if a.bounds[0]!=b.bounds[0]: return a.bounds[0]<b.bounds[0]
	if a.bounds[1]!=b.bounds[1]: return a.bounds[1]<b.bounds[1]
	if a.port_id!=b.port_id: return a.port_id<b.port_id
	if a.plot_id!=b.plot_id: return a.plot_id<b.plot_id
	return a.record_index<b.record_index


static func _record_shape(value: Variant) -> bool:
	return value is Dictionary and value.get("id") is String and not str(value.id).is_empty() \
		and value.get("world") is Dictionary and not value.world.is_empty() \
		and _vector(value.get("origin_m"),3) and value.get("plots") is Array


static func _plot_shape(value: Variant) -> bool:
	return value is Dictionary and value.get("id") is String and not str(value.id).is_empty() \
		and _vector(value.get("rect_m"),4) and float(value.rect_m[2])>0 and float(value.rect_m[3])>0


static func _vector(value: Variant, count: int) -> bool:
	if not value is Array or value.size()!=count: return false
	for component in value:
		if not (component is int or component is float) or not is_finite(float(component)): return false
	return true
