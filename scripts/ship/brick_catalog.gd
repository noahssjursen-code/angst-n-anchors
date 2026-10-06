class_name BrickCatalog
extends RefCounted
## Legacy construction artwork removed for the Blender model migration.
const BRICKS: Dictionary = {}
static var _imported: Dictionary = {}

static func imported_entries() -> Dictionary:
	if _imported.is_empty():
		for path in ["res://resources/models/parts/access_kit/manifest.json","res://resources/models/parts/trawl_rig/manifest.json","res://resources/models/parts/lighting_kit/manifest.json","res://resources/models/parts/coaster_kit/manifest.json", "res://resources/models/parts/coaster_perimeter/manifest.json","res://resources/models/parts/bulk_kit/manifest.json", "res://resources/models/parts/cargo_kit/manifest.json", "res://resources/models/parts/cargo_perimeter/manifest.json", "res://resources/models/parts/fishing_kit/manifest.json", "res://resources/models/parts/trawler_rails/manifest.json", "res://resources/models/parts/wheelhouse/manifest.json", "res://resources/models/parts/surface_tiles/manifest.json", "res://resources/models/parts/interior/manifest.json"]:
			var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			for raw in data["assets"]:
				var entry: Dictionary = raw.duplicate(true)
				var id := str(entry["id"])
				entry["display"] = id.replace("_", " ").capitalize()
				entry["tags"] = ["structure" if id.begins_with("cabin_") or entry["style"] in ["floor", "roof", "stair", "support"] else "railing", "ship_only", "imported"]
				if entry["style"]=="light":entry["tags"]=["light","ship_only","imported"]
				entry["color"] = ModelPaint.DEFAULTS["wall"] if entry["style"] != "rail" else Color(0.58, 0.64, 0.65)
				_imported[id] = entry
	return _imported
static func ids() -> Array[String]:
	# Palette families; exact asset variants remain addressable for placement and saves.
	return ["rail_straight_100cm", "halfwall_straight_100cm", "cabin_wall_straight", "cabin_door_straight", "cabin_window_straight", "floor_tile", "roof_tile", "deck_stair_220cm", "deck_bracket_2m", "cabin_console_straight", "helm_chair", "passenger_seat", "helm_wheel", "helm_throttle", "helm_display", "cabin_bench_straight", "trawl_winch", "trawl_gantry_4m", "insulated_catch_tank", "hold_coaming_5x8", "hatch_cover_5x4", "bulk_divider_5m", "deck_floodlight", "nav_port", "nav_starboard", "nav_stern", "mast_lantern"]

static func ids_for_buildings() -> Array[String]:
	## Land building editor palette — shared kit minus marine-only systems.
	var out: Array[String] = []
	for brick_id in ids():
		if has_tag(brick_id, "ship_only"):
			continue
		out.append(brick_id)
	return out

static func has(brick_id: String) -> bool:
	return imported_entries().has(brick_id.strip_edges())

static func get_entry(brick_id: String) -> Dictionary:
	var id := brick_id.strip_edges()
	if not imported_entries().has(id):
		return {}
	return (imported_entries()[id] as Dictionary).duplicate(true)

static func footprint_of(brick_id: String) -> Vector3i:
	var e := get_entry(brick_id)
	if e.is_empty():
		return Vector3i(1, 1, 1)
	var raw: Variant = e.get("footprint", [1, 1, 1])
	if raw is Vector3i:
		return raw as Vector3i
	if raw is Array:
		var a: Array = raw
		return Vector3i(int(a[0]), int(a[1]) if a.size() > 1 else 1, int(a[2]) if a.size() > 2 else 1)
	return Vector3i(1, 1, 1)

static func size_m(brick_id: String) -> Vector3:
	var entry := get_entry(brick_id)
	if not entry.is_empty():
		var end: Array = entry["end_xz"]
		return Vector3(maxf(absf(float(end[0])), 0.12), maxf(float(entry["height_start_m"]), float(entry["height_end_m"])) + 0.05, maxf(absf(float(end[1])), 0.12))
	var fp := footprint_of(brick_id)
	var s := DeckGrid.CELL_M
	return Vector3(float(fp.x) * s, float(fp.y) * s, float(fp.z) * s)

static func yaw_step_of(brick_id: String) -> int:
	return maxi(int(get_entry(brick_id).get("yaw_step", 90)), 1)

static func display_name(brick_id: String) -> String:
	var names := {"trawl_gantry_4m":"Trawl gantry","deck_floodlight":"Deck floodlight", "nav_port":"Port light", "nav_starboard":"Starboard light", "nav_stern":"Stern light", "mast_lantern":"White mast light","hold_coaming_5x8":"Hold coaming", "hatch_cover_5x4":"Hatch cover","helm_chair":"Helm chair", "passenger_seat":"Passenger seat", "helm_wheel":"Steering wheel", "helm_throttle":"Throttle", "helm_display":"Display"}
	if names.has(brick_id): return names[brick_id]
	if brick_id in ["floor_tile", "roof_tile"]:
		return "Floor" if brick_id == "floor_tile" else "Roof"
	if brick_id.begins_with("cabin_"):
		return str(get_entry(brick_id).get("style", "Structure")).capitalize()
	if brick_id == "rail_straight_100cm":
		return "Railing"
	if brick_id == "halfwall_straight_100cm":
		return "Solid half-wall"
	return str(get_entry(brick_id).get("display", brick_id))

static func has_tag(brick_id: String, tag: String) -> bool:
	var tags = get_entry(brick_id).get("tags", [])
	return tags is Array and (tags as Array).has(tag)

static func create_visual(brick_id: String, opts: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = brick_id
	var entry := get_entry(brick_id)
	if not entry.is_empty():
		var model := (load(entry["model"]) as PackedScene).instantiate() as Node3D
		root.add_child(model)
		for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			var all_detail := mesh.mesh.get_surface_count()>0
			for i in mesh.mesh.get_surface_count():
				var material := mesh.mesh.surface_get_material(i)
				all_detail = all_detail and material != null and entry.get("walk_exclude_materials",[]).has(material.resource_name)
			if all_detail:mesh.set_meta("walk_detail_visual",true)
		for component in entry.get("components",[]):
			var part := create_visual(component["id"])
			if component.has("pivot"):
				var pivots:=model.find_children(component["pivot"]+"*","Node3D",true,false)
				if not pivots.is_empty(): pivots[0].add_child(part)
			else: model.add_child(part)

		if entry.has("light_type"):
			var aim := model.find_child("LightAim",true,false) as Node3D
			assert(aim != null,"Imported lighting needs an authored LightAim")
			var light := ShipLight.new()
			light.name="FixtureLight"
			light.light_type=int(entry.light_type)
			light.build_housing=false
			light.spot_pitch_deg=0
			light.spot_range_m=18
			light.spot_energy=3.5
			light.omni_range_scale=.22
			light.omni_energy_scale=.16
			light.lens_energy_scale=.35
			light.spot_angle_deg=48
			aim.add_child(light)
		if bool(opts.get("preview_mesh", false)):
			model.position -= visual_bounds(root).get_center()
		if (entry["style"] == "halfwall" or entry.get("paintable", false)) and opts.has("color"):
			ModelPaint.apply(model, {"wall": opts["color"]})
	return root

static func visual_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var initialized := false
	for mesh: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		var transform := mesh.transform
		var parent := mesh.get_parent()
		while parent != root:
			if parent is Node3D:transform=parent.transform*transform
			parent=parent.get_parent()
		var box: AABB = transform * mesh.get_aabb()
		bounds=bounds.merge(box) if initialized else box
		initialized=true
	return bounds
