class_name CustomPortCatalog
extends RefCounted

## Construction geometry, visuals and simulation share these asset definitions.
const ASSET_MANIFEST := "res://resources/data/ports/custom_harbour_assets.json"
static var _definitions: Dictionary = {}

static func definitions() -> Dictionary:
	if not _definitions.is_empty(): return _definitions.duplicate(true)
	for spec in PlotBuildLayout.catalog():
		var row: Dictionary = spec.duplicate(true)
		row.asset_id = str(row.id)
		row.footprint_m = [float(row.cells[0])*2.0,float(row.cells[1])*2.0]
		row.kind = "platform" if row.get("anchor","")=="top" else "decoration"
		row.placement_layer = "platform" if row.kind=="platform" else "surface"
		# Retain the original solid-box buildings for saved port compatibility.
		# New rooms use the authored modular walls, doors, windows and roofs.
		if str(row.id) in ["warehouse", "workshop"]: row.build_library_visible = false
		if str(row.id)=="bollard": row.kind="bollard"
		if str(row.get("visual","")) in ["container_crane","bulk_crane"]:
			row.kind="crane"
			row.reach_max_m=float(row.reach_m)
			var base: float=float(row.base_size_m)
			var crane_at: Array=row.crane_offset_m
			var pad_at: Array=row.pad_offset_m
			var pad_size: Array=row.pad_size_m
			row.occupied_rects_m=[
				[float(crane_at[0])-base*.5,float(crane_at[1])-base*.5,base,base],
				[float(pad_at[0])-float(pad_size[1])*.5,float(pad_at[1])-float(pad_size[0])*.5,float(pad_size[1]),float(pad_size[0])]]
			row.storage_rect_m=row.occupied_rects_m[1].duplicate()
			if str(row.visual)=="container_crane":
				row.cargo_types=["container","general"]
				row.attached_store={"name":"Container yard","capacity_kg":int(row.slot_count)*24000.0,"capacity_units":int(row.slot_count),
					"accepted_handling_modes":["container"],"accepted_container_types":["20ft"],"accepted_commodities":[],"public_loading":false}
			else:
				row.cargo_types=["bulk"]
				row.attached_store={"name":"Bulk yard","capacity_kg":450000.0,"accepted_handling_modes":["bulk"],
					"accepted_commodities":["iron_ore","coal","grain"],"public_loading":false}
		_definitions[str(row.id)]=row
	if FileAccess.file_exists(ASSET_MANIFEST):
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSET_MANIFEST))
		for asset in manifest.get("assets",[]):
			var row: Dictionary = asset.duplicate(true)
			row.kind = str(row.get("kind","bollard" if str(row.id).contains("bollard") else "decoration"))
			row.placement_layer = "roof" if str(row.id).contains("roof") else ("edge" if row.get("placement_kind","")=="edge" else "surface")
			if str(row.id)=="quay_edge_4m": row.placement_layer="coping"
			if str(row.id)=="workshop_corner_trim": row.placement_layer="wall_trim"
			if str(row.id)=="workshop_roof_edge_4m": row.placement_layer="roof_trim"
			if row.has("layer") and str(row.layer) in ["roof", "roof_trim", "wall_trim", "coping", "upper_floor"]: row.placement_layer=str(row.layer)
			row.requires_support = true
			if str(row.get("placement_kind",""))=="foundation":
				row.kind="platform"
				row.placement_layer="platform"
				row.requires_support=false
			_definitions[str(row.id)]=row
	_definitions["port_clerk"]={"id":"port_clerk","name":"Port operator","category":"People","kind":"npc","footprint_m":[1.0,1.0],"height_m":1.8,"placement_layer":"surface","requires_support":true}
	_definitions["fish_landing_plant"]={"id":"fish_landing_plant","name":"Fish landing plant","category":"Cargo equipment",
		"factory":"fish_landing_plant","kind":"crane","attached_store_only":true,"footprint_m":[20.0,16.0],"height_m":5.35,
		"placement_layer":"surface","requires_support":true,"snap_m":4.0,"rotation_step_degrees":90.0,"cargo_types":["catch"],
		"crane_offset_m":[5.18,-4.72],"reach_min_m":0.0,"reach_max_m":24.0,
		"occupied_rects_m":[[-8.2,-5.75,10.55,11.5],[4.1,-4.725,3.8,8.355]],"storage_rect_m":[-8.2,-5.75,10.55,11.5],
		"attached_store":{"name":"Refrigerated fish store","capacity_kg":40000.0,"accepted_handling_modes":["catch"],
			"accepted_commodities":["fresh_groundfish"],"public_loading":false,"public_unloading":false}}
	return _definitions.duplicate(true)

static func definition(id: String) -> Dictionary:
	return definitions().get(id,{})

static func placement(id: String, asset_id: String, at: Vector3, yaw_degrees := 0.0, attributes := {}) -> Dictionary:
	var spec := definition(asset_id)
	var geometry := {}
	for key in ["kind","footprint_m","footprint_polygon_m","placement_layer","placement_kind","requires_support","crane_offset_m","reach_min_m","reach_max_m","cargo_types","occupied_rects_m","storage_rect_m"]:
		if spec.has(key): geometry[key]=spec[key]
	geometry.merge(attributes,true)
	return {"id":id,"asset_id":asset_id,"position_m":[at.x,at.y,at.z],"yaw_degrees":yaw_degrees,"attributes":geometry}

static func vector3(values: Array) -> Vector3:
	return Vector3(float(values[0]),float(values[1]),float(values[2]))
