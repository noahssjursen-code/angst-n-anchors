extends SceneTree

## SCRATCH (leading underscore — not a gate unit). Writes the DOUBLED blueprint
## that option (c) — `BuildingGrid.CELL_M = 0.5` — requires, so the gate units
## can be run against a MIGRATED building and not against (c)-minus-the-work.
##
##   Q1_MIGRATE_OUT=res://... xvfb-run -a --server-args="-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_q1_migrate_blueprint.gd
##
## Same rule as `_q1_arms_shot.gd::_reauthor_doubled`, which is the only rule
## that preserves metres: a brick of footprint F covers F cells, so each primary
## becomes eight placements, two per axis at doubled coordinates; floor underlays
## take the bottom layer only.
##
## THE CALLER IS RESPONSIBLE FOR PUTTING THE ORIGINAL BACK, and for checking it
## by CONTENT HASH rather than by `git status` — a stat-cache mismatch reports
## `M` on a byte-identical file and that has already misled a wave here.

const SRC := "res://resources/data/buildings/warehouse.json"


func _init() -> void:
	var out_path := OS.get_environment("Q1_MIGRATE_OUT")
	if out_path.is_empty():
		out_path = SRC
	var text := FileAccess.get_file_as_string(SRC)
	if text.is_empty():
		printerr("[migrate] could not read %s" % SRC)
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		printerr("[migrate] %s is not a JSON object" % SRC)
		quit(1)
		return
	var src := BuildingLayout.from_dict(parsed as Dictionary)
	var out := _reauthor_doubled(src)

	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		printerr("[migrate] could not write %s" % out_path)
		quit(1)
		return
	f.store_string(JSON.stringify(out.to_dict(), "\t", true))
	f.close()
	print("[migrate] wrote %s: grid %s -> %s, cells %d -> %d"
		% [out_path, str(src.grid_size), str(out.grid_size),
			src.cells.size(), out.cells.size()])
	quit(0)


func _reauthor_doubled(src: BuildingLayout) -> BuildingLayout:
	var out := BuildingLayout.new()
	out.blueprint_id = src.blueprint_id
	out.display_name = src.display_name
	out.role = src.role
	out.pad_template_id = src.pad_template_id
	out.grid_size = src.grid_size * 2

	var content: Array[Dictionary] = []
	var surfaces: Array[Dictionary] = []
	for entry in src.iter_primary_cells():
		var cell := entry["cell"] as Vector3i
		if BuildingLayout.entry_is_surface_only(entry):
			surfaces.append({"cell": cell, "entry": entry})
			continue
		content.append({"cell": cell, "entry": entry})
		if entry.has("surface"):
			surfaces.append({"cell": cell, "entry": entry["surface"] as Dictionary})

	var placed := 0
	var refused := 0
	for job in content:
		var cell := job["cell"] as Vector3i
		var entry := job["entry"] as Dictionary
		var brick_id := str(entry.get("brick_id", ""))
		var yaw := int(entry.get("yaw", 0))
		var step := _footprint_steps(brick_id, yaw)
		var color: Variant = entry.get("color", null)
		var props: Dictionary = {}
		if entry.has("text"):
			props["text"] = str(entry["text"])
		for i in 2:
			for j in 2:
				for k in 2:
					var origin := Vector3i(
						cell.x * 2 + i * step.x,
						cell.y * 2 + j * step.y,
						cell.z * 2 + k * step.z)
					if out.place_footprint(origin, brick_id, yaw, null, color, props):
						placed += 1
					else:
						refused += 1

	var surfaced := 0
	for job in surfaces:
		var cell := job["cell"] as Vector3i
		var entry := job["entry"] as Dictionary
		var brick_id := str(entry.get("brick_id", "floor"))
		var yaw := int(entry.get("yaw", 0))
		var step := _footprint_steps(brick_id, yaw)
		var color: Variant = entry.get("color", null)
		for i in 2:
			for k in 2:
				var origin := Vector3i(
					cell.x * 2 + i * step.x, cell.y * 2, cell.z * 2 + k * step.z)
				if out.place_footprint(origin, brick_id, yaw, null, color):
					surfaced += 1
	print("[migrate] %d content primaries -> %d placements (%d refused); %d surfaces -> %d"
		% [content.size(), placed, refused, surfaces.size(), surfaced])
	return out


func _footprint_steps(brick_id: String, yaw: int) -> Vector3i:
	var fp := BrickCatalog.footprint_of(brick_id)
	var steps := int(round(float(yaw) / 90.0)) % 4
	if steps % 2 != 0:
		return Vector3i(fp.z, fp.y, fp.x)
	return fp
