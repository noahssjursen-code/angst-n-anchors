extends SceneTree

## Scratch probe (leading underscore: the gate skips it).
##
## Drives every invariant that used to be a bare `assert()` FALSE, through the
## production call, and prints what the new guard does instead. The bar is not
## "it printed an error" — a `push_error` that then continues into the same
## broken state is not a fix. The bar is: the process survives, the answer is
## defined, and the substitution is visible.
##
## Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_guard_fire_probe.gd > out.log 2>&1
##
## Redirect to a FILE. If any guard fails to hold, the process idles (an
## uncaught cast error or a failed assert aborts the function but not the
## process) and `timeout` discards the pipe buffer with everything in it.

const STREAMER := preload("res://scripts/world/world_terrain_streamer.gd")
const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")


## Run one section at a time with `-- --only=<name>`. That is not a convenience:
## this probe is also run against the PRE-GUARD files (a pristine copy of the
## tree at HEAD) to get the other half of each mutation pair, and there a firing
## `assert()` aborts the enclosing function while leaving the process alive — so
## one section's failure would swallow every section after it and the run would
## idle to the timeout with an empty pipe buffer. One section per process keeps
## each half of each pair independently observable.
const SECTIONS := [
	"world_layout", "terrain_streamer", "world_config", "ocean_clipmap",
	"hull_profile", "port_expander", "port_trade_profile", "land_field",
	"port_showcase",
]


func _initialize() -> void:
	var only := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			only = argument.trim_prefix("--only=")
	for section in SECTIONS:
		if only != "" and only != section:
			continue
		match section:
			"world_layout": _world_layout_guards()
			"terrain_streamer": _terrain_streamer_guards()
			"world_config": _world_config_guards()
			"ocean_clipmap": _ocean_clipmap_guard()
			"hull_profile": _hull_profile_guard()
			"port_expander": _port_expander_guard()
			"port_trade_profile": _port_trade_profile_guard()
			"land_field": _land_field_guards()
			"port_showcase": _port_showcase_guard()
	print("\n=== PROBE REACHED THE END (%s) ===" % ("all sections" if only == "" else only))
	quit(0)


func _head(title: String) -> void:
	print("\n=== %s ===" % title)


# ── world_layout.gd (4 asserts) ───────────────────────────────────────────────
func _world_layout_guards() -> void:
	_head("world_layout: resolution < 2")
	var tiny := WorldLayout.new()
	tiny._initialize(1, 40000.0, 1, PackedFloat32Array([0.0]), PackedByteArray([0]), [], [], "x")
	print("  raster_resolution after refusal: %d (0 == refused, left empty)" % tiny.raster_resolution)
	print("  sample_signed_distance(Vector2(10, 10)) = %s  (positive == water, no divide by zero)"
			% tiny.sample_signed_distance(Vector2(10.0, 10.0)))
	print("  is_land(Vector2(10, 10)) = %s" % tiny.is_land(Vector2(10.0, 10.0)))
	print("  classify_region(Vector2(10, 10)) = %d (3 == OPEN_WATER)" % tiny.classify_region(Vector2(10.0, 10.0)))

	_head("world_layout: raster size disagrees with resolution")
	var ragged := WorldLayout.new()
	## resolution 4 wants 16 cells; give it 9 signed distances and 16 regions.
	var short_sd := PackedFloat32Array()
	short_sd.resize(9)
	var regions16 := PackedByteArray()
	regions16.resize(16)
	ragged._initialize(1, 40000.0, 4, short_sd, regions16, [], [], "x")
	print("  raster_resolution after refusal: %d" % ragged.raster_resolution)
	print("  sample_signed_distance survives: %s" % ragged.sample_signed_distance(Vector2(0.0, 0.0)))

	_head("world_layout: initialized twice")
	var good := WorldLayout.new()
	var sd := PackedFloat32Array()
	sd.resize(16)
	for i in range(16):
		sd[i] = -100.0
	var rg := PackedByteArray()
	rg.resize(16)
	good._initialize(7, 40000.0, 4, sd, rg, [], [], "first")
	print("  first initialize: resolution=%d seed=%d checksum=%s cell=%s"
			% [good.raster_resolution, good.seed, good.layout_checksum, good.cell_size_m])
	var sd2 := PackedFloat32Array()
	sd2.resize(64)
	var rg2 := PackedByteArray()
	rg2.resize(64)
	good._initialize(99, 10000.0, 8, sd2, rg2, [], [], "second")
	print("  after refused second initialize: resolution=%d seed=%d checksum=%s cell=%s"
			% [good.raster_resolution, good.seed, good.layout_checksum, good.cell_size_m])
	print("  VERDICT: the live raster was NOT swapped under its holders"
			if good.raster_resolution == 4 and good.seed == 7 and good.layout_checksum == "first"
			else "  VERDICT: FAILED — the second initialize got through")


# ── world_terrain_streamer.gd (2 asserts) ─────────────────────────────────────
func _terrain_streamer_guards() -> void:
	var layout := WorldLayout.new()
	var sd := PackedFloat32Array()
	sd.resize(16)
	for i in range(16):
		sd[i] = -50.0
	var rg := PackedByteArray()
	rg.resize(16)
	layout._initialize(3, 40000.0, 4, sd, rg, [], [], "streamer")

	_head("world_terrain_streamer: step_m that does not divide CHUNK_SIZE_M")
	var legal := STREAMER.build_chunk_mesh_data(layout, Vector2i(0, 0), 25.0)
	print("  step 25 (legal): surface_side=%d returned step_m=%s"
			% [int(legal["surface_side"]), legal["step_m"]])
	var ragged := STREAMER.build_chunk_mesh_data(layout, Vector2i(0, 0), 30.0)
	print("  step 30 (1000 %% 30 == 10): surface_side=%d returned step_m=%s"
			% [int(ragged["surface_side"]), ragged["step_m"]])
	var used := float(ragged["step_m"])
	var cells := int(ragged["surface_side"]) - 1
	print("  cells x used = %s (CHUNK_SIZE_M is 1000.0) → the substituted step still")
	print("  divides a chunk exactly, by construction: %d x %s = %s"
			% [cells, used, float(cells) * used])
	print("  (`fmod(1000.0, %s)` reports %s, not 0 — which is why the guard checks the"
			% [used, fmod(1000.0, used)])
	print("   round trip `CHUNK_SIZE_M / round(CHUNK_SIZE_M / step)` instead of the")
	print("   `fmod(...) == 0` the old assert used. That assert would have rejected its")
	print("   own arithmetic on any step it did not already accept exactly.)")
	print("  the caller is told which step it got, not the one it asked for: %s != 30.0" % used)

	_head("world_terrain_streamer: step_m <= 0")
	var zero := STREAMER.build_chunk_mesh_data(layout, Vector2i(0, 0), 0.0)
	print("  step 0: surface_side=%d returned step_m=%s vertices=%d"
			% [int(zero["surface_side"]), zero["step_m"], (zero["vertices"] as PackedVector3Array).size()])

	_head("world_terrain_streamer: unknown border edge")
	var north := STREAMER.sample_chunk_border(layout, Vector2i(0, 0), 100.0, &"north")
	var typo_a := STREAMER.sample_chunk_border(layout, Vector2i(0, 0), 100.0, &"nort")
	var typo_b := STREAMER.sample_chunk_border(layout, Vector2i(1, 0), 100.0, &"wets")
	print("  &\"north\" -> %d samples" % north.size())
	print("  &\"nort\"  -> %d samples (refused, named in the error above)" % typo_a.size())
	print("  &\"wets\"  -> %d samples" % typo_b.size())
	print("  THE OLD FAILURE MODE, still visible: typo_a == typo_b is %s —"
			% str(typo_a == typo_b))
	print("  two misspelt edges compare EQUAL, so a seam check written with a typo")
	print("  in both names passes on nothing at all. The guard cannot stop a caller")
	print("  comparing two empties; what it does is put the reason in the log,")
	print("  named, once per call instead of never.")


# ── world_config.gd (2 asserts) ───────────────────────────────────────────────
func _world_config_guards() -> void:
	_head("world_config: archetype file missing")
	var missing := WorldConfig.resolve(40000.0, "res://resources/data/world/does_not_exist.json")
	print("  resolve() returned %d keys: world_size_m=%s raster_resolution=%s archetype_path=%s"
			% [missing.size(), missing.get("world_size_m"), missing.get("raster_resolution"),
				missing.get("archetype_path")])

	_head("world_config: archetype is valid JSON but not an object")
	var bad_path := "user://_probe_bad_archetype.json"
	var f := FileAccess.open(bad_path, FileAccess.WRITE)
	f.store_string("[1, 2, 3]")
	f.close()
	var bad := WorldConfig.resolve(80000.0, bad_path)
	print("  resolve() returned %d keys: world_size_m=%s raster_resolution=%s"
			% [bad.size(), bad.get("world_size_m"), bad.get("raster_resolution")])
	print("  and a world of that size is still generatable from defaults, which is")
	print("  what the old `assert` denied by dereferencing null one line later.")

	_head("world_config: the real archetype is untouched")
	var real := WorldConfig.resolve()
	print("  resolve() default: %d keys, raster_resolution=%s, has mainland=%s"
			% [real.size(), real.get("raster_resolution"), real.has("mainland")])


# ── ocean_clipmap.gd (1 assert) ───────────────────────────────────────────────
func _ocean_clipmap_guard() -> void:
	_head("ocean_clipmap: fewer than four materials")
	var clipmap := OceanClipmap.new()
	var shader_materials: Array[ShaderMaterial] = []
	for i in range(4):
		shader_materials.append(ShaderMaterial.new())
	clipmap.build(shader_materials)
	var built := clipmap.get_child_count()
	print("  built with 4 materials: %d child meshes" % built)
	var short_list: Array[ShaderMaterial] = [ShaderMaterial.new(), ShaderMaterial.new()]
	clipmap.build(short_list)
	print("  build() with 2 materials: %d child meshes still present" % clipmap.get_child_count())
	print("  VERDICT: the existing clipmap survived the refusal"
			if clipmap.get_child_count() == built
			else "  VERDICT: FAILED — the ocean was torn down before the guard ran")
	clipmap.free()


# ── hull_physics_profile.gd (1 assert) ────────────────────────────────────────
## `stations_geometry()` is new, so it is reached through `has_method` — this
## same probe has to compile and run against the pre-guard files.
func _hull_report(label: String, profile: HullPhysicsProfile) -> void:
	print("  --- %s ---" % label)
	print("  validate() = %s" % [profile.validate()])
	var draft := profile.design_draft_m
	if profile.has_method("stations_geometry"):
		var g: Dictionary = profile.call("stations_geometry")
		draft = float(g["draft_m"])
		print("  stations_geometry: clamped=%s L=%s B=%s D=%s draft=%s disp=%s"
				% [g["clamped"], g["length_m"], g["beam_m"], g["depth_m"], g["draft_m"],
					g["displacement_t"]])
	else:
		print("  (no stations_geometry() on this build — pre-guard file)")
	print("  design_draft_fraction() = %s" % profile.design_draft_fraction())
	var stations := profile.make_stations()
	if stations == null:
		print("  make_stations() returned NULL — the assert aborted it")
		return
	var lift: float = stations.volume_below(draft)
	print("  volume_below(%s) = %s   finite=%s  positive=%s"
			% [draft, lift, is_finite(lift), lift > 0.0])
	print("  waterplane_area_at(%s) = %s" % [draft, stations.waterplane_area_at(draft)])


func _hull_profile_guard() -> void:
	_head("hull_physics_profile: profiles validate() has rejected")
	var good := HullPhysicsProfile.new()
	good.length_m = 28.0
	good.beam_m = 10.0
	good.depth_m = 5.6
	good.design_draft_m = 2.4
	good.design_displacement_t = 256.0
	_hull_report("valid 28x10 trawler (control — must not move)", good)

	var broken := HullPhysicsProfile.new()
	broken.length_m = 28.0
	broken.beam_m = 10.0
	broken.depth_m = 5.6
	broken.design_draft_m = 9.0            ## past the deck
	broken.design_displacement_t = 9000.0  ## denser than the box it fits in
	_hull_report("draft past the deck, displacement past the envelope", broken)

	var flat := HullPhysicsProfile.new()
	flat.length_m = 0.0
	flat.beam_m = 0.0
	flat.depth_m = 0.0
	flat.design_draft_m = 0.0
	flat.design_displacement_t = 0.0
	_hull_report("every dimension zero", flat)


# ── port_expander.gd (2 asserts) ──────────────────────────────────────────────
func _port_expander_guard() -> void:
	_head("port_expander: definition from an older generation")
	var stale := PortDefinition.new()
	stale.port_id = "stale_haven"
	stale.display_name = "Stale Haven"
	stale.size = 3
	stale.site_seed = 12345
	stale.region_kind = PortDefinition.RegionKind.MAINLAND
	stale.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION - 3
	print("  before chart_summary: definition version = %d (current is %d)"
			% [stale.port_generation_version, PortDefinition.CURRENT_PORT_GENERATION_VERSION])
	var summary := PortExpander.chart_summary(stale, 4242)
	print("  after  chart_summary: definition version = %d, summary size=%s"
			% [stale.port_generation_version, summary.get("size")])
	print("  VERDICT: re-stamped, so anything built from it is labelled with the rules that built it"
			if stale.port_generation_version == PortDefinition.CURRENT_PORT_GENERATION_VERSION
			else "  VERDICT: FAILED — still carrying the stale version")

	var current := PortDefinition.new()
	current.port_id = "current_haven"
	current.size = 3
	current.site_seed = 999
	var before := current.port_generation_version
	PortExpander.chart_summary(current, 4242)
	print("  a current definition is not touched: %d -> %d"
			% [before, current.port_generation_version])


# ── port_trade_profile.gd (1 assert) ──────────────────────────────────────────
func _port_trade_profile_guard() -> void:
	_head("port_trade_profile: derive(null)")
	var profile := PortTradeProfile.derive(null, 7)
	print("  returned: %s" % ("null" if profile == null else "a PortTradeProfile"))
	if profile != null:
		print("  theme_id=%s exports=%s imports=%s"
				% [("<empty>" if profile.theme_id == "" else profile.theme_id),
					profile.destiny_export_slots, profile.destiny_import_slots])
		print("  VERDICT: a usable provisions-only profile, distinguishable by its empty theme"
				if profile.theme_id == "" and profile.destiny_export_slots.has("provisions")
				else "  VERDICT: FAILED")


# ── land_field.gd (2 asserts) ─────────────────────────────────────────────────
func _land_field_guards() -> void:
	## Seed a REAL previous world first. The interesting difference between the
	## assert and the guard is not the error text: it is that an aborted
	## `initialize` leaves the PREVIOUS world's islands installed, so loading a
	## second world with a bad source silently keeps sheltering ships behind land
	## that is no longer there.
	_head("land_field: a previous world is installed first")
	LandField.initialize([
		{"center": Vector3(0.0, 0.0, 0.0), "half_x": 900.0, "half_z": 700.0, "rotation_y": 0.0},
	])
	print("  island world: distance_to_land(0,0)=%s shelter(0,0)=%s"
			% [LandField.distance_to_land(Vector3.ZERO), LandField.wave_shelter(Vector3.ZERO)])

	_head("land_field: initialize() with something that is neither a layout nor an array")
	print("  (with the assert compiled out — every release build — the next line is")
	print("   `SCRIPT ERROR: Invalid cast', which aborts the function and idles the")
	print("   process; measured in tests/_hole_facts_probe.gd)")
	LandField.initialize(5)
	print("  distance_to_land(0,0) after the bad call = %s" % LandField.distance_to_land(Vector3.ZERO))
	print("  (inf == the stale island is GONE; 0.0-ish == the previous world is still installed)")
	print("  survived. shelter at (0,0) = %s" % LandField.wave_shelter(Vector3.ZERO))
	print("  coastal_exposure at (0,0) = %s" % LandField.coastal_exposure(Vector3.ZERO))

	_head("land_field: initialize_from_layout(null)")
	LandField.initialize_from_layout(null)
	print("  survived. shelter at (0,0) = %s" % LandField.wave_shelter(Vector3.ZERO))
	print("  distance_to_land at (0,0) = %s" % LandField.distance_to_land(Vector3.ZERO))


# ── port_showcase.gd (1 assert) ───────────────────────────────────────────────
func _port_showcase_guard() -> void:
	_head("port_showcase: no site was generated")
	var showcase := PortShowcase.new()
	showcase.world_seed = 20260815
	## An all-open-water layout: `place_ports` finds no coast, so the pool the
	## `assert` guarded really is empty, by the route it would empty in the game.
	var empty_sea := WorldLayout.new()
	var sd := PackedFloat32Array()
	sd.resize(64 * 64)
	for i in range(64 * 64):
		sd[i] = 4000.0
	var rg := PackedByteArray()
	rg.resize(64 * 64)
	for i in range(64 * 64):
		rg[i] = WorldLayout.Region.OPEN_WATER
	empty_sea._initialize(20260815, 40000.0, 64, sd, rg, [], [], "allwater")
	var placed: Array = PLACER.place_ports(empty_sea, 35, PackedStringArray(["Nowhere"]))
	print("  coastal placer on all-water layout returned %d definitions" % placed.size())
	var picked: PortDefinition = showcase._select_world_port(empty_sea)
	print("  _select_world_port returned: %s"
			% ("null" if picked == null else "\"%s\" (id %s)" % [picked.display_name, picked.port_id]))
	if picked != null:
		print("  caller's very next statement works: site_seed %d -> %d"
				% [picked.site_seed, picked.site_seed ^ showcase.world_seed])
		print("  VERDICT: no modulo by zero, and the substitution is named in the display string"
				if picked.port_id == "showcase_placeholder"
				else "  VERDICT: a real site was found — the guard did not need to fire")
	showcase.free()
