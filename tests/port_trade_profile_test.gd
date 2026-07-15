extends SceneTree

## Determinism: same seed + definition → identical trade profile + layout.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var definition := PortDefinition.new()
	definition.port_id = "port-home"
	definition.display_name = "Haugsvik"
	definition.size = 2
	definition.region_kind = PortDefinition.RegionKind.MAINLAND
	definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
	definition.site_seed = 991122

	var a := PortExpander.expand(definition, 424242)
	var b := PortExpander.expand(definition, 424242)
	assert(a.trade_profile != null and b.trade_profile != null)
	assert(a.trade_profile.export_slots == b.trade_profile.export_slots)
	assert(a.trade_profile.import_slots == b.trade_profile.import_slots)
	assert(a.layout_graph != null and b.layout_graph != null)
	assert(JSON.stringify(a.layout_graph.to_dict()) == JSON.stringify(b.layout_graph.to_dict()))
	assert(not a.trade_profile.export_slots.is_empty())
	assert(not str(a.trade_profile.theme_id).is_empty())
	## Size 2 always gets at least one import from themes.
	assert(not a.trade_profile.import_slots.is_empty())
	## Quay commodities in the profile must appear in the berth plan.
	var plan: Dictionary = a.layout_graph.initial_attributes.get("berth_plan", {}) as Dictionary
	var planned: Dictionary = {}
	for raw in plan.get("quay_stations", []) as Array:
		var station: Dictionary = raw
		for zone in station.get("zones", []) as Array:
			planned[str((zone as Dictionary).get("commodity_id", ""))] = true
		for commodity in station.get("commodities", []) as Array:
			planned[str(commodity)] = true
		for side in station.get("sides", []) as Array:
			for commodity in (side as Dictionary).get("commodities", []) as Array:
				planned[str(commodity)] = true
			for zone in (side as Dictionary).get("zones", []) as Array:
				planned[str((zone as Dictionary).get("commodity_id", ""))] = true
	for raw in plan.get("asphalt_stations", []) as Array:
		planned[str((raw as Dictionary).get("commodity_id", ""))] = true
	for id in a.trade_profile.all_slots():
		assert(planned.has(str(id)), "berth plan missing trade commodity %s" % id)
	## Different products never share a pad side (twin pier keeps one commodity per side).
	for raw in plan.get("quay_stations", []) as Array:
		var station: Dictionary = raw
		if str(station.get("layout", "")) == "twin_joined":
			assert(int(station.get("berth_faces", 0)) == 2, "twin quay must expose two berth faces")
			assert((station.get("sides", []) as Array).size() == 2, "twin quay needs two sides")
			for side in station.get("sides", []) as Array:
				var side_commodities: Array = (side as Dictionary).get("commodities", []) as Array
				assert(side_commodities.size() <= 1, "twin side shares commodities: %s" % str(side_commodities))
		else:
			var commodities: Array = station.get("commodities", []) as Array
			assert(commodities.size() <= 1, "pad shares multiple commodities: %s" % str(commodities))
	## Apron berths hug the dock face with local orientation and stay clear of quay loading roots.
	var asphalt_seen: Dictionary = {}
	for raw in plan.get("asphalt_stations", []) as Array:
		var station: Dictionary = raw
		var cid := str(station.get("commodity_id", ""))
		assert(not asphalt_seen.has(cid), "duplicate asphalt berth for %s" % cid)
		asphalt_seen[cid] = true
		assert(
			float(station.get("length_m", 0.0)) >= PortSizing.design_hull_loa_m(a.size) * 0.7,
			"asphalt berth too short for %s" % cid,
		)
		assert(
			float(station.get("depth_m", 0.0)) >= 20.0,
			"asphalt berth too short seaward for %s" % cid,
		)
		assert(
			str(station.get("extends", "")) == "seaward",
			"asphalt berth must extend outside the apron (%s)" % cid,
		)
		var dir: Array = station.get("direction", []) as Array
		assert(dir.size() >= 2, "asphalt berth missing local seaward for %s" % cid)
		assert(
			Vector2(float(dir[0]), float(dir[1])).length_squared() > 0.25,
			"asphalt berth seaward degenerate for %s" % cid,
		)
	if not plan.get("asphalt_stations", []).is_empty() and not plan.get("quay_stations", []).is_empty():
		var dock_face := PackedVector2Array()
		var foundation: Dictionary = a.layout_graph.initial_attributes.get("foundation", {}) as Dictionary
		for pt in foundation.get("dock_face_polyline", []) as Array:
			var arr := pt as Array
			if arr.size() >= 2:
				dock_face.append(Vector2(float(arr[0]), float(arr[1])))
		if dock_face.size() >= 2:
			var blocked: Array = PortBerthPlan._quay_loading_exclusions_along_face(
				dock_face, plan.get("quay_stations", []) as Array, a.size
			)
			for raw in plan.get("asphalt_stations", []) as Array:
				var arc := float((raw as Dictionary).get("arc_m", -1.0))
				for block in blocked:
					var lo := float((block as Dictionary).get("lo", 0.0))
					var hi := float((block as Dictionary).get("hi", 0.0))
					assert(
						arc < lo - 0.5 or arc > hi + 0.5,
						"apron berth arc %.1f inside quay loading exclusion [%.1f, %.1f]" % [arc, lo, hi],
					)
	assert(a.layout_graph.local_footprints().size() >= 1)
	assert(a.layout_seed == b.layout_seed)

	## Growing size unlocks destiny — never re-rolls theme or mature lists.
	var def_small := PortDefinition.new()
	def_small.port_id = definition.port_id
	def_small.display_name = definition.display_name
	def_small.size = 1
	def_small.region_kind = definition.region_kind
	def_small.port_generation_version = definition.port_generation_version
	def_small.site_seed = definition.site_seed
	var def_big := PortDefinition.new()
	def_big.port_id = definition.port_id
	def_big.display_name = definition.display_name
	def_big.size = 6
	def_big.region_kind = definition.region_kind
	def_big.port_generation_version = definition.port_generation_version
	def_big.site_seed = definition.site_seed
	var grown_small := PortTradeProfile.derive(def_small, 424242)
	var grown_big := PortTradeProfile.derive(def_big, 424242)
	assert(grown_small.theme_id == grown_big.theme_id)
	assert(grown_small.destiny_export_slots == grown_big.destiny_export_slots)
	assert(grown_small.destiny_import_slots == grown_big.destiny_import_slots)
	## Unlocked exports are a prefix of destiny.
	for index in range(grown_small.export_slots.size()):
		assert(grown_small.export_slots[index] == grown_small.destiny_export_slots[index])
	assert(grown_big.export_slots.size() >= grown_small.export_slots.size())
	## Unlock is monotonic — growing never re-locks a destiny commodity.
	var prev_exports: Array[String] = []
	var prev_imports: Array[String] = []
	for grow_size in range(0, PortSizing.TRADE_COMPLETE_SIZE + 1):
		var def_g := PortDefinition.new()
		def_g.port_id = definition.port_id
		def_g.display_name = definition.display_name
		def_g.size = grow_size
		def_g.region_kind = definition.region_kind
		def_g.port_generation_version = definition.port_generation_version
		def_g.site_seed = definition.site_seed
		var grown := PortTradeProfile.derive(def_g, 424242)
		for id in prev_exports:
			assert(grown.export_slots.has(id), "size %d dropped export %s" % [grow_size, id])
		for id in prev_imports:
			assert(grown.import_slots.has(id), "size %d dropped import %s" % [grow_size, id])
		prev_exports = grown.export_slots.duplicate()
		prev_imports = grown.import_slots.duplicate()
	## By TRADE_COMPLETE_SIZE the full destiny is unlocked.
	var def_complete := PortDefinition.new()
	def_complete.port_id = definition.port_id
	def_complete.display_name = definition.display_name
	def_complete.size = PortSizing.TRADE_COMPLETE_SIZE
	def_complete.region_kind = definition.region_kind
	def_complete.port_generation_version = definition.port_generation_version
	def_complete.site_seed = definition.site_seed
	var complete := PortTradeProfile.derive(def_complete, 424242)
	assert(complete.export_slots == complete.destiny_export_slots)
	assert(complete.import_slots == complete.destiny_import_slots)

	## Sparse destinies cannot grow into mega hubs.
	assert(PortSizing.max_size_for_trade_products(2) <= 3)
	assert(PortSizing.max_size_for_trade_products(4) <= PortSizing.TRADE_COMPLETE_SIZE)
	assert(PortTradeProfile.max_size_for_profile(complete) \
			<= PortSizing.max_size_for_trade_products(
				PortTradeProfile.destiny_product_count(complete)
			))
	var sparse := PortTradeProfile.derive(def_small, 424242)
	var sparse_max := PortTradeProfile.max_size_for_profile(sparse)
	assert(sparse_max < PortSizing.MAX_SIZE or PortTradeProfile.destiny_product_count(sparse) >= 7)

	print("Port trade profile tests: all checks passed")
	quit()
