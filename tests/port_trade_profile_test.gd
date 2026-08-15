extends SceneTree

## Determinism: same seed + definition → identical trade profile + layout.

const TestReport := preload("res://tests/support/test_report.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestReport.new("port_trade_profile_test")
	var definition := PortDefinition.new()
	definition.port_id = "port-home"
	definition.display_name = "Haugsvik"
	definition.size = 2
	definition.region_kind = PortDefinition.RegionKind.MAINLAND
	definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
	definition.site_seed = 991122

	var a := PortExpander.expand(definition, 424242)
	## Two INDEPENDENT expansions. `PortDataCache` now registers the resolved
	## definition as well as the request, so without this clear the second call
	## returns the first PortData object and every determinism check below
	## compares a thing to itself. The cache's own identity guarantee is
	## `port_perf_cache_test`'s job; this file's is that the generator is
	## reproducible, which needs it to actually run twice.
	PortDataCache.clear()
	var b := PortExpander.expand(definition, 424242)
	t.check("the determinism checks compare two distinct expansions", a != b)
	if not t.check("both expansions produce a trade profile", a.trade_profile != null and b.trade_profile != null):
		t.finish(self)
		return
	t.check("export slots are deterministic", a.trade_profile.export_slots == b.trade_profile.export_slots)
	t.check("import slots are deterministic", a.trade_profile.import_slots == b.trade_profile.import_slots)
	if not t.check("both expansions produce a layout graph", a.layout_graph != null and b.layout_graph != null):
		t.finish(self)
		return
	t.check(
		"layout graph is deterministic",
		JSON.stringify(a.layout_graph.to_dict()) == JSON.stringify(b.layout_graph.to_dict()),
	)
	t.check("port exports something", not a.trade_profile.export_slots.is_empty())
	t.check("every port exports general cargo", a.trade_profile.export_slots.has("provisions"))
	t.check("every port imports general cargo", a.trade_profile.import_slots.has("provisions"))
	t.check("trade profile has a theme", not str(a.trade_profile.theme_id).is_empty())
	## Size 2 always gets at least one import from themes.
	t.check("size 2 port imports something", not a.trade_profile.import_slots.is_empty())
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
		t.check("berth plan missing trade commodity %s" % id, planned.has(str(id)))
	## Different products never share a pad side (twin pier keeps one commodity per side).
	for raw in plan.get("quay_stations", []) as Array:
		var station: Dictionary = raw
		if str(station.get("layout", "")) == "twin_joined":
			t.check("twin quay must expose two berth faces", int(station.get("berth_faces", 0)) == 2)
			t.check("twin quay needs two sides", (station.get("sides", []) as Array).size() == 2)
			for side in station.get("sides", []) as Array:
				var side_commodities: Array = (side as Dictionary).get("commodities", []) as Array
				t.check("twin side shares commodities: %s" % str(side_commodities), side_commodities.size() <= 1)
		else:
			var commodities: Array = station.get("commodities", []) as Array
			t.check("pad shares multiple commodities: %s" % str(commodities), commodities.size() <= 1)
	## Apron berths hug the dock face with local orientation and stay clear of quay loading roots.
	var asphalt_seen: Dictionary = {}
	for raw in plan.get("asphalt_stations", []) as Array:
		var station: Dictionary = raw
		var cid := str(station.get("commodity_id", ""))
		t.check("duplicate asphalt berth for %s" % cid, not asphalt_seen.has(cid))
		asphalt_seen[cid] = true
		t.check(
			"asphalt berth too short for %s" % cid,
			float(station.get("length_m", 0.0)) >= PortSizing.design_hull_loa_m(a.size) * 0.7,
		)
		t.check(
			"asphalt berth working pad too shallow for %s" % cid,
			float(station.get("depth_m", 0.0)) >= 20.0,
		)
		t.check(
			"asphalt working pad must extend into the apron (%s)" % cid,
			str(station.get("extends", "")) == "inland",
		)
		var dir: Array = station.get("direction", []) as Array
		if not t.check("asphalt berth missing local seaward for %s" % cid, dir.size() >= 2):
			continue
		t.check(
			"asphalt berth seaward degenerate for %s" % cid,
			Vector2(float(dir[0]), float(dir[1])).length_squared() > 0.25,
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
					t.check(
						"apron berth arc %.1f inside quay loading exclusion [%.1f, %.1f]" % [arc, lo, hi],
						arc < lo - 0.5 or arc > hi + 0.5,
					)
	t.check("layout graph has a local footprint", a.layout_graph.local_footprints().size() >= 1)
	t.check("layout seed is deterministic", a.layout_seed == b.layout_seed)

	## Land plan defines the inland buildable zone (apron + hinterland).
	var land: Dictionary = a.layout_graph.initial_attributes.get("land_plan", {}) as Dictionary
	t.check("land_plan missing", not land.is_empty())
	var zone: Dictionary = land.get("buildable_zone", {}) as Dictionary
	t.check("buildable_zone missing", not zone.is_empty())
	t.check("zone needs seaward edge", (zone.get("seaward_edge", []) as Array).size() >= 2)
	t.check("zone needs inland edge", (zone.get("inland_edge", []) as Array).size() >= 2)
	t.check("buildable zone too shallow inland", float(zone.get("inland_depth_m", 0.0)) >= 400.0)
	t.check("buildable zone too narrow", float(zone.get("along_span_m", 0.0)) >= 20.0)
	t.check(
		"zone must bloom wider inland",
		float(zone.get("along_span_inland_m", 0.0)) > float(zone.get("along_span_seaward_m", 0.0)),
	)
	t.check(
		"zone must rise inland",
		float(zone.get("height_inland_m", 0.0)) > float(zone.get("height_seaward_m", 0.0)),
	)
	var grid: Dictionary = land.get("terrain_grid", {}) as Dictionary
	t.check("terrain_grid missing", not grid.is_empty())
	t.check("terrain grid too small", int(grid.get("u_count", 0)) >= 2 and int(grid.get("v_count", 0)) >= 2)
	t.check("terrain grid needs stake points", (grid.get("points", []) as Array).size() >= 4)
	var house_n := 0
	var trade_n := 0
	for raw in grid.get("points", []) as Array:
		var kind := str((raw as Dictionary).get("kind", ""))
		if kind == PortLandPlan.KIND_TRADE:
			trade_n += 1
			t.check("trade stake needs commodity", not str((raw as Dictionary).get("commodity_id", "")).is_empty())
			t.check(
				"trade sphere should be larger",
				float((raw as Dictionary).get("radius_m", 0.0)) > PortLandPlan.HOUSE_RADIUS_M,
			)
		elif kind == PortLandPlan.KIND_HOUSE:
			house_n += 1
	t.check("need house stakes", house_n >= 1)
	if not a.trade_profile.all_slots().is_empty():
		t.check("trade profile should sprinkle trade decorations", trade_n >= 1)
	var apron: Dictionary = land.get("apron_decor", {}) as Dictionary
	t.check("apron should sprinkle service props", int(apron.get("point_count", 0)) >= 3)
	for raw in apron.get("points", []) as Array:
		var entry: Dictionary = raw
		var local_arr: Array = entry.get("local", []) as Array
		t.check("apron prop needs local XZ", local_arr.size() >= 2)
		t.check("apron prop needs kind", not str(entry.get("kind", "")).is_empty())
	## The prop keep-out around a pier root has no check anywhere else, and it is
	## the thing that breaks if the clearance is ever re-derived: a prop dropped
	## on a berth's loading face reads as rubbish left in the truck lane. State
	## the property (no prop stands within a station's own along-face footprint)
	## rather than the clearance constant, so the check survives a re-tune.
	var apron_props := apron.get("points", []) as Array
	var quay_stations := plan.get("quay_stations", []) as Array
	if not quay_stations.is_empty():
		var inland_dir: Vector2 = PortCoastTracer.PORT_LOCAL_INLAND_DIR
		var along_dir := Vector2(-inland_dir.y, inland_dir.x)
		var intruders := 0
		var pairs := 0
		for raw_prop in apron_props:
			var local_arr: Array = (raw_prop as Dictionary).get("local", []) as Array
			if local_arr.size() < 2:
				continue
			var prop := Vector2(float(local_arr[0]), float(local_arr[1]))
			for raw_station in quay_stations:
				var station: Dictionary = raw_station
				var origin_arr: Array = station.get("origin", [0.0, 0.0]) as Array
				var origin := Vector2(float(origin_arr[0]), float(origin_arr[1]))
				var half_w := float(
					station.get("width_m", PortSizing.quay_deck_width_m(a.size))
				) * 0.5
				pairs += 1
				if absf((prop - origin).dot(along_dir)) < half_w:
					intruders += 1
		## Without this the intruder count below is 0 whenever the sprinkler
		## produced nothing, and a keep-out check that passes on an empty apron
		## is the vacuous pass this suite keeps finding.
		t.check(
			"the quay keep-out sweep had something to check (%d props x %d stations)"
			% [apron_props.size(), quay_stations.size()],
			pairs > 0,
		)
		t.equal("no apron prop stands on a quay station's own width", intruders, 0)
	var apron_pads: Dictionary = land.get("apron_pads", {}) as Dictionary
	t.check("apron should seed every required brick pad",
			int(apron_pads.get("pad_count", 0)) >= PortApronPadCatalog.UNIVERSAL_REQUIRED_V1.size())
	t.check("pad cell size", is_equal_approx(float(apron_pads.get("cell_m", 0.0)), PortApronPadCatalog.CELL_M))
	t.check("uniform clipped grid needs host cells", int(apron_pads.get("host_count", 0)) >= 1)
	var grid_summary: Dictionary = apron_pads.get("grid", {}) as Dictionary
	t.check("apron_pads.grid should summarize host lattice", int(grid_summary.get("host_count", 0)) >= 1)
	var host := PortApronPadCatalog.build_host_grid(
		a.layout_graph.initial_attributes.get("foundation", {}) as Dictionary,
		a.layout_graph.initial_attributes.get("berth_plan", {}) as Dictionary,
	)
	var host_mask: Dictionary = host.get("mask", {}) as Dictionary
	var host_poly := PackedVector2Array()
	for raw_pt in host.get("polygon", []) as Array:
		if raw_pt is Array and (raw_pt as Array).size() >= 2:
			var arr: Array = raw_pt
			host_poly.append(Vector2(float(arr[0]), float(arr[1])))
	var pad_roles: Dictionary = {}
	for raw in apron_pads.get("pads", []) as Array:
		var pad: Dictionary = raw
		t.check("pad needs role", not str(pad.get("role", "")).is_empty())
		t.check("pad needs template", not str(pad.get("pad_template_id", "")).is_empty())
		var origin_ok := t.check("pad needs origin", (pad.get("origin", []) as Array).size() >= 2)
		var cells_ok := t.check("pad needs cell footprint", (pad.get("cells", []) as Array).size() >= 2)
		var ij: Array = pad.get("grid_ij", []) as Array
		var ij_ok := t.check("pad needs grid_ij", ij.size() >= 2)
		if cells_ok and ij_ok:
			var footprint: Array = pad.get("cells", []) as Array
			var w := int(footprint[0])
			var h := int(footprint[1])
			var i0 := int(ij[0])
			var j0 := int(ij[1])
			for jj in range(j0, j0 + h):
				for ii in range(i0, i0 + w):
					t.check("pad %s footprint leaves host grid at %d,%d" % [str(pad.get("role", "")), ii, jj],
							host_mask.has("%d,%d" % [ii, jj]))
		if origin_ok:
			var origin_arr: Array = pad.get("origin", []) as Array
			var origin := Vector2(float(origin_arr[0]), float(origin_arr[1]))
			t.check("pad %s origin outside apron polygon" % str(pad.get("role", "")),
					Geometry2D.is_point_in_polygon(origin, host_poly))
		pad_roles[str(pad.get("role", ""))] = true
	## Harbour office is mandatory on every port.
	for role_id in PortApronPadCatalog.UNIVERSAL_REQUIRED_V1:
		t.check("missing required apron pad role %s" % role_id, pad_roles.has(role_id))
	t.check("parking apron should not auto-place", not pad_roles.has("parking_apron"))
	## Unlocked asphalt trades must get waterside handling pads.
	for commodity_id in a.trade_profile.all_slots():
		var cid := str(commodity_id)
		if not CommodityCatalog.uses_asphalt_dock(cid):
			continue
		var found_trade := false
		for raw in apron_pads.get("pads", []) as Array:
			var pad: Dictionary = raw
			if str(pad.get("commodity_id", "")) != cid:
				continue
			t.check("trade pad %s should be waterside" % str(pad.get("role", "")),
					str(pad.get("zone", "")) == PortApronPadCatalog.ZONE_WATERSIDE)
			found_trade = true
			break
		t.check("missing waterside trade pad for asphalt commodity %s" % cid, found_trade)
	## Trade stakes follow the live recipe roles — never invent the opposite direction.
	for raw in grid.get("points", []) as Array:
		var entry: Dictionary = raw
		if str(entry.get("kind", "")) != PortLandPlan.KIND_TRADE:
			continue
		var cid := str(entry.get("commodity_id", ""))
		var role := str(entry.get("role", ""))
		match role:
			"export":
				t.check("export stake for unoffered %s" % cid, a.trade_profile.export_slots.has(cid))
				t.check("one-way export stake must not also be an import-only commodity",
						not a.trade_profile.import_slots.has(cid) or PortTradeProfile.is_bidirectional_trade(cid))
			"import":
				t.check("import stake for unoffered %s" % cid, a.trade_profile.import_slots.has(cid))
				t.check("import stake must not invent export for %s" % cid,
						not a.trade_profile.export_slots.has(cid))
			"bidirectional":
				t.check("bidirectional only for containers", PortTradeProfile.is_bidirectional_trade(cid))
				t.check(
					"bidirectional stake not in recipe",
					a.trade_profile.export_slots.has(cid) or a.trade_profile.import_slots.has(cid),
				)
			_:
				t.fail("unknown trade role %s" % role)

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
	t.check("growing never re-rolls the theme", grown_small.theme_id == grown_big.theme_id)
	t.check("growing never re-rolls destiny exports", grown_small.destiny_export_slots == grown_big.destiny_export_slots)
	t.check("growing never re-rolls destiny imports", grown_small.destiny_import_slots == grown_big.destiny_import_slots)
	## Unlocked exports are a prefix of destiny.
	for index in range(grown_small.export_slots.size()):
		if index >= grown_small.destiny_export_slots.size():
			t.fail("unlocked export %d has no destiny slot" % index)
			break
		t.check(
			"unlocked export %d matches destiny" % index,
			grown_small.export_slots[index] == grown_small.destiny_export_slots[index],
		)
	t.check("bigger port unlocks at least as many exports", grown_big.export_slots.size() >= grown_small.export_slots.size())
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
			t.check("size %d dropped export %s" % [grow_size, id], grown.export_slots.has(id))
		for id in prev_imports:
			t.check("size %d dropped import %s" % [grow_size, id], grown.import_slots.has(id))
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
	t.check("complete port unlocks every destiny export", complete.export_slots == complete.destiny_export_slots)
	t.check("complete port unlocks every destiny import", complete.import_slots == complete.destiny_import_slots)

	## Sparse destinies cannot grow into mega hubs.
	t.check("two trade products cap size at 3", PortSizing.max_size_for_trade_products(2) <= 3)
	t.check(
		"four trade products cap size at the trade-complete size",
		PortSizing.max_size_for_trade_products(4) <= PortSizing.TRADE_COMPLETE_SIZE,
	)
	t.check(
		"profile max size respects its destiny product count",
		PortTradeProfile.max_size_for_profile(complete) \
				<= PortSizing.max_size_for_trade_products(
					PortTradeProfile.destiny_product_count(complete)
				),
	)
	var sparse := PortTradeProfile.derive(def_small, 424242)
	var sparse_max := PortTradeProfile.max_size_for_profile(sparse)
	t.check(
		"sparse destiny cannot reach max size",
		sparse_max < PortSizing.MAX_SIZE or PortTradeProfile.destiny_product_count(sparse) >= 7,
	)

	t.finish(self)
