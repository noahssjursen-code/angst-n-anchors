extends Node

## Scratch probe (leading underscore — not a gate unit). Lane B.
##
## The bow-on and plan renders of the granted starter show something protruding
## about a metre outboard of the STARBOARD deck edge. `general_vessel`'s
## `brick_side` rule cannot see it: that rule tests the sign of the HOST CELL's
## local x and never looks at where a fixture is DRAWN. So this measures every
## drawn mesh against the deck edge, on the granted 15 m starter and on the 28 m
## trawler as a control, and names what hangs over the water.


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await _survey(CompanyService.build_starter_vessel_record(CompanyContracts.DEFAULT_STARTER), "GRANTED STARTER")
	await _survey(_prebuilt_record("fishing_trawler"), "28 m TRAWLER CONTROL")
	get_tree().quit(0)


func _prebuilt_record(prebuilt_id: String) -> Dictionary:
	for entry in PrebuiltVesselCatalog.catalog_entries():
		if str(entry.get("prebuilt_id", "")) != prebuilt_id:
			continue
		return VesselSpawn.normalize_record({
			"uid": "probe_%s" % prebuilt_id,
			"hull_id": str(entry.get("hull_id", "")),
			"registration_id": str(entry.get("registration_id", "")),
			"name": str(entry.get("prebuilt_name", "")),
			"shaft_power_kw": float(entry.get("shaft_power_kw", 1.0)),
			"brick_layout": (entry.get("prebuilt_layout", {}) as Dictionary).duplicate(true),
		})
	return {}


func _survey(record: Dictionary, label: String) -> void:
	if record.is_empty():
		print("%s: no record" % label)
		return
	var hull_id := str(record.get("hull_id", ""))
	var grid := HullRegistry.make_grid(hull_id)
	var boat := VesselSpawn.instantiate_from_record(record)
	if boat == null:
		print("%s: no boat" % label)
		return
	add_child(boat)
	await get_tree().process_frame
	await get_tree().process_frame
	print("== %s  hull=%s  deck half-beam %.3f m (beam %.1f m)" % [
		label, hull_id, grid.half_beam, grid.half_beam * 2.0,
	])
	## Group by the fitting each mesh belongs to, so the report names the fitting
	## and not forty anonymous MeshInstance3Ds.
	var groups := {}
	_walk(boat, boat, groups)
	var keys := groups.keys()
	keys.sort()
	for key in keys:
		var g: Dictionary = groups[key]
		var over := maxf(float(g["hi"]) - grid.half_beam, -float(g["lo"]) - grid.half_beam)
		print("   %-28s local x %+.3f .. %+.3f  vis=%s  %s" % [
			key, float(g["lo"]), float(g["hi"]), str(bool(g["visible"])),
			("OVERHANGS by %.3f m" % over) if over > 0.001 else "",
		])
	boat.free()
	await get_tree().process_frame


func _walk(node: Node, boat: Node3D, groups: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var aabb := mi.get_aabb()
		var lo := 1e9
		var hi := -1e9
		for i in range(8):
			var p: Vector3 = boat.to_local(mi.global_transform * aabb.get_endpoint(i))
			lo = minf(lo, p.x)
			hi = maxf(hi, p.x)
		var key := _group_of(mi, boat)
		if not groups.has(key):
			groups[key] = {"lo": 1e9, "hi": -1e9, "visible": false}
		var g: Dictionary = groups[key]
		g["lo"] = minf(float(g["lo"]), lo)
		g["hi"] = maxf(float(g["hi"]), hi)
		g["visible"] = bool(g["visible"]) or mi.is_visible_in_tree()
	for child in node.get_children():
		_walk(child, boat, groups)


## Collapse "DeckFitout/railing_9_0_12/@MeshInstance3D@42" to "DeckFitout/railing",
## and keep named subsystems (CatchHold, FishingSystem) whole.
func _group_of(node: Node, root: Node) -> String:
	var bits := PackedStringArray()
	var cursor := node
	while cursor != null and cursor != root:
		var n := str(cursor.name)
		if not n.begins_with("@"):
			bits.append(n.rstrip("0123456789_"))
		cursor = cursor.get_parent()
	bits.reverse()
	return "/".join(bits)
