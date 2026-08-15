extends Node

## SCRATCH PROBE (leading underscore — the gate must not discover it).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_visual_survey.tscn
##
## Owner decision 1b. Enumerates EVERY node class each of the 64 bricks emits,
## then measures what survives `BuildingCache`'s flatten/stamp against what
## `BuildingFitout` drew. Lane B: BuildingFitout -> BrickDoor -> WorldGateway.

const OUT := "user://visual_survey.txt"

var _lines: PackedStringArray = []


func _log(s: String) -> void:
	print(s)
	_lines.append(s)


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	_survey_catalog()
	_log("[t] section A %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	_survey_fitout_level()
	_log("[t] section B %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	_survey_cache_delta()
	_log("[t] section C %d ms" % (Time.get_ticks_msec() - t0))
	_survey_duplicate_semantics()
	_survey_blueprint_usage()
	_survey_stamp_cost()
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
	get_tree().quit(0)


## ── 1. every brick, every node class it emits ──────────────────────────────
func _survey_catalog() -> void:
	_log("=== A. BrickCatalog.create_visual — node classes per brick (%d bricks) ===" % BrickCatalog.ids().size())
	var by_class: Dictionary = {}  ## class -> [brick_id]
	for brick_id in BrickCatalog.ids():
		var opts := {}
		if BrickCatalog.has_tag(brick_id, "text"):
			opts["text"] = "WAREHOUSE"
		var v := BrickCatalog.create_visual(brick_id, opts)
		var kinds := _class_census(v)
		var non_mesh: PackedStringArray = []
		for k in kinds:
			if k == "MeshInstance3D" or k == "Node3D":
				continue
			non_mesh.append("%s x%d" % [k, kinds[k]])
			var arr: Array = by_class.get(k, [])
			arr.append(brick_id)
			by_class[k] = arr
		if not non_mesh.is_empty():
			_log("  %-26s ship_only=%s  %s" % [
				brick_id, str(BrickCatalog.has_tag(brick_id, "ship_only")), ", ".join(non_mesh)])
		v.free()
	_log("  -- roll-up --")
	var keys := by_class.keys()
	keys.sort()
	for k in keys:
		var ids: Array = by_class[k]
		_log("  %-18s %d brick(s): %s" % [str(k), ids.size(), ", ".join(PackedStringArray(ids))])

	## The editor-only aim gizmo is a separate opt; note whether it adds classes.
	_log("  -- with show_aim_gizmo (editor palette only) --")
	for brick_id in BrickCatalog.ids():
		if not BrickCatalog.has_tag(brick_id, "light"):
			continue
		var v2 := BrickCatalog.create_visual(brick_id, {"show_aim_gizmo": true})
		var kinds2 := _class_census(v2)
		var extra: PackedStringArray = []
		for k in kinds2:
			if k == "MeshInstance3D" or k == "Node3D":
				continue
			extra.append("%s x%d" % [k, kinds2[k]])
		_log("  %-26s %s" % [brick_id, ", ".join(extra)])
		v2.free()


## ── 2. what BuildingFitout adds on top of create_visual ────────────────────
func _survey_fitout_level() -> void:
	_log("")
	_log("=== B. BuildingFitout adds (per brick, on a 1-cell synthetic layout) ===")
	for brick_id in BrickCatalog.ids():
		var layout := BuildingLayout.new()
		layout.blueprint_id = ""
		layout.grid_size = Vector3i(16, 16, 16)
		var props: Dictionary = {}
		if BrickCatalog.has_tag(brick_id, "text"):
			props["text"] = "WAREHOUSE"
		if not layout.place_footprint(Vector3i(4, 0, 4), brick_id, 0, null, null, props):
			_log("  %-26s REFUSED by place_footprint" % brick_id)
			continue
		print("    [b] %s" % brick_id)
		var fitout := BuildingFitout.build(layout, false)
		var kinds := _class_census(fitout)
		var interesting: PackedStringArray = []
		for k in kinds:
			if k == "MeshInstance3D" or k == "Node3D":
				continue
			interesting.append("%s x%d" % [k, kinds[k]])
		## Meshes parented UNDER another MeshInstance3D: `_flatten_visuals` copies a
		## mesh and does not recurse into it, so these never reach the prototype.
		var counts := [0, 0]
		_mesh_depth_census(fitout, false, counts)
		if not interesting.is_empty() or counts[1] > 0:
			_log("  %-26s ship_only=%-5s %s  meshes=%d buried_under_mesh=%d" % [
				brick_id, str(BrickCatalog.has_tag(brick_id, "ship_only")),
				", ".join(interesting), counts[0], counts[1]])
		fitout.free()


## ── 3. the shipped warehouse: fitout vs cache ──────────────────────────────
func _survey_cache_delta() -> void:
	_log("")
	_log("=== C. warehouse.json — BuildingFitout vs BuildingCache ===")
	var layout := BuildingBlueprintCatalog.by_id("warehouse")
	if layout == null:
		_log("  warehouse blueprint did not load")
		return
	var fitout := BuildingFitout.build(layout, false)
	var f_kinds := _class_census(fitout)
	_log("  BuildingFitout.build(layout, false): %s" % _fmt(f_kinds))
	fitout.free()

	BuildingCache.clear()
	var cached := BuildingCache.instance(layout, true)
	var c_kinds := _class_census(cached)
	_log("  BuildingCache.instance(layout, true): %s" % _fmt(c_kinds))
	## Visual subtree only — the cache root also carries BuildingLighting + Collision.
	var visual := cached.get_node_or_null("Visual")
	if visual != null:
		_log("  ...its Visual subtree:              %s" % _fmt(_class_census(visual)))
	var lost: PackedStringArray = []
	for k in f_kinds:
		var before: int = f_kinds[k]
		var after: int = int(c_kinds.get(k, 0))
		if after < before:
			lost.append("%s %d -> %d" % [k, before, after])
	_log("  LOST: %s" % (", ".join(lost) if not lost.is_empty() else "(nothing)"))
	cached.free()
	BuildingCache.clear()


## ── 4. does Node.duplicate() deep-copy Resources? model_cache.gd says it does ──
func _survey_duplicate_semantics() -> void:
	_log("")
	_log("=== D. Node.duplicate() resource semantics ===")
	var label := Label3D.new()
	label.text = "WAREHOUSE"
	label.font = BrandTheme.font_display()
	label.set_meta("probe_meta", 7)
	var copy := label.duplicate() as Label3D
	_log("  Label3D.font shared:  %s (orig %d, copy %d)" % [
		str(copy.font == label.font), label.font.get_instance_id(), copy.font.get_instance_id()])
	_log("  Label3D.text carried: %s" % str(copy.text == label.text))
	_log("  metadata carried:     %s" % str(copy.get_meta("probe_meta", -1) == 7))
	copy.free()
	label.free()

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	mi.mesh = bm
	mi.material_override = MeshBuilder.make_material(Color.RED, 0.5, 0.0)
	var mi_copy := mi.duplicate() as MeshInstance3D
	_log("  MeshInstance3D.mesh shared: %s" % str(mi_copy.mesh == mi.mesh))
	_log("  material_override shared:   %s" % str(mi_copy.material_override == mi.material_override))
	mi_copy.free()
	mi.free()

	var omni := OmniLight3D.new()
	omni.light_energy = 2.8
	omni.set_meta("building_light_base_energy", 2.8)
	var omni_copy := omni.duplicate() as OmniLight3D
	_log("  OmniLight3D energy %.2f -> %.2f, meta carried %s" % [
		omni.light_energy, omni_copy.light_energy,
		str(omni_copy.has_meta("building_light_base_energy"))])
	omni_copy.free()
	omni.free()


## ── 5. which shipped blueprints use the affected bricks ────────────────────
func _survey_blueprint_usage() -> void:
	_log("")
	_log("=== E. shipped blueprints — affected brick usage ===")
	for blueprint_id in BuildingBlueprintCatalog.ids():
		var layout := BuildingBlueprintCatalog.by_id(blueprint_id)
		if layout == null:
			continue
		var used: Dictionary = {}
		for entry in layout.iter_primary_cells():
			var bid := str(entry.get("brick_id", ""))
			used[bid] = int(used.get(bid, 0)) + 1
			if entry.has("sign_id"):
				var sid := str(entry["sign_id"])
				used["sign:" + sid] = int(used.get("sign:" + sid, 0)) + 1
		var keys := used.keys()
		keys.sort()
		var parts: PackedStringArray = []
		for k in keys:
			parts.append("%s=%d" % [str(k), int(used[k])])
		_log("  %s: %s" % [blueprint_id, ", ".join(parts)])


## ── 6. what the fix costs per stamped building ─────────────────────────────
func _survey_stamp_cost() -> void:
	_log("")
	_log("=== F. stamp cost (warehouse, 20 instances) ===")
	var layout := BuildingBlueprintCatalog.by_id("warehouse")
	if layout == null:
		return
	BuildingCache.clear()
	var t_bake := Time.get_ticks_usec()
	var warm := BuildingCache.instance(layout, false)
	var bake_us := Time.get_ticks_usec() - t_bake
	var per_instance := _class_census(warm)
	warm.free()
	var t0 := Time.get_ticks_usec()
	var made: Array[Node3D] = []
	for i in 20:
		made.append(BuildingCache.instance(layout, false))
	var total_us := Time.get_ticks_usec() - t0
	for node in made:
		node.free()
	BuildingCache.clear()
	_log("  first call (bake + stamp): %.1f ms" % (float(bake_us) / 1000.0))
	_log("  20 stamps: %.1f ms total, %.2f ms each" % [
		float(total_us) / 1000.0, float(total_us) / 20000.0])
	_log("  per instance: %s" % _fmt(per_instance))

	## Where does the delta sit — the one duplicated Label3D, or the 72 door
	## meshes the old code was dropping? Timed separately so the answer is not a
	## guess off a total (REALITY.md §4e: vary one input).
	var label := Label3D.new()
	label.text = "WAREHOUSE"
	label.font = BrandTheme.font_display()
	label.font_size = 128
	var t_dup := Time.get_ticks_usec()
	for i in 200:
		var c := label.duplicate()
		c.free()
	_log("  Label3D.duplicate(): %.4f ms each (200 runs)"
		% (float(Time.get_ticks_usec() - t_dup) / 200000.0))
	label.free()

	var proto_mesh := MeshBuilder.box(Vector3.ONE, Color.GRAY, 0.8, 0.0)
	proto_mesh.name = "Panel"
	var host := Node3D.new()
	var t_mesh := Time.get_ticks_usec()
	for i in 720:
		var mi := MeshInstance3D.new()
		mi.name = proto_mesh.name
		mi.mesh = proto_mesh.mesh
		mi.material_override = proto_mesh.material_override
		mi.cast_shadow = proto_mesh.cast_shadow
		mi.gi_mode = proto_mesh.gi_mode
		host.add_child(mi)
	_log("  720 same-named mesh copies into one parent: %.2f ms"
		% (float(Time.get_ticks_usec() - t_mesh) / 1000.0))
	host.free()
	proto_mesh.free()


func _fmt(kinds: Dictionary) -> String:
	var keys := kinds.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s=%d" % [str(k), int(kinds[k])])
	return ", ".join(parts)


## counts[0] = every MeshInstance3D; counts[1] = those with a MeshInstance3D ancestor.
func _mesh_depth_census(node: Node, under_mesh: bool, counts: Array) -> void:
	for child in node.get_children():
		var is_mesh := child is MeshInstance3D
		if is_mesh:
			counts[0] = int(counts[0]) + 1
			if under_mesh:
				counts[1] = int(counts[1]) + 1
		_mesh_depth_census(child, under_mesh or is_mesh, counts)


func _class_census(node: Node, out: Dictionary = {}) -> Dictionary:
	for child in node.get_children():
		var cls := child.get_class()
		var script: Script = child.get_script() as Script
		if script != null:
			var gname := script.get_global_name()
			if gname != &"":
				cls = "%s(%s)" % [str(gname), cls]
		out[cls] = int(out.get(cls, 0)) + 1
		_class_census(child, out)
	return out
